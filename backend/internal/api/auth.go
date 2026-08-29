package api

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strings"

	firebase "firebase.google.com/go/v4"
	fbauth "firebase.google.com/go/v4/auth"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/ramsang/rise-backend/internal/config"
	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// Principal — 인증된 호출자(역할·센터·회원 스코프). 모든 핸들러가 여기서 스코프를 읽는다
// (설계00 P13: 역할 3종, 설계03 P37 권한 매트릭스).
type Principal struct {
	UID      string
	Role     string // owner|trainer|member
	CenterID string
	MemberID string // role=member일 때만(가입 매칭 전엔 빈 값 — P48 플로우 부트스트랩)
	// Phone — Firebase 전화 인증으로 검증된 번호(P06 실연동). 값이 있으면 join/match·confirm이
	// 클라이언트 제공 번호 대신 이 값을 쓴다 — 번호 위조로 타인 레코드에 매칭하는 경로 차단.
	Phone string
}

func (p Principal) IsOwner() bool   { return p.Role == domain.RoleOwner }
func (p Principal) IsTrainer() bool { return p.Role == domain.RoleTrainer }
func (p Principal) IsMember() bool  { return p.Role == domain.RoleMember }
func (p Principal) IsStaff() bool   { return p.IsOwner() || p.IsTrainer() }

// ErrForbidden — 역할 스코프 위반(403 매핑, util.go의 writeErr 참고).
var ErrForbidden = errors.New("api: forbidden")

type principalKey struct{}

func principalFrom(ctx context.Context) (Principal, bool) {
	p, ok := ctx.Value(principalKey{}).(Principal)
	return p, ok
}

func withPrincipal(ctx context.Context, p Principal) context.Context {
	return context.WithValue(ctx, principalKey{}, p)
}

var (
	errMissingToken       = errors.New("missing bearer token")
	errDevHeadersRequired = errors.New("X-Dev-Uid, X-Dev-Role headers required in dev mode")
	errInvalidRole        = errors.New("X-Dev-Role must be owner|trainer|member")
)

// Authenticator — Firebase ID 토큰 검증(FIREBASE_PROJECT 설정 시) 또는 dev 헤더 인증(미설정 시).
type Authenticator struct {
	fbClient *fbauth.Client // nil이면 dev 모드
	// fbApp — 초기화된 Admin SDK 앱. Storage 클라이언트(MediaPurger)가 여기서 파생된다 —
	// SDK를 두 번 초기화하면 자격증명 로딩이 두 번 일어난다(Provisioner가 fbClient를 재사용하는
	// 것과 같은 이유).
	fbApp         *firebase.App
	store         store.Store
	defaultCenter string
}

// NewAuthenticator — cfg.FirebaseProject가 설정된 경우 Firebase Admin SDK로 ID 토큰을 검증한다.
// 비어있으면 dev 모드(X-Dev-Role/X-Dev-Uid 헤더)로 동작한다 — 로컬 개발·테스트 전용.
func NewAuthenticator(ctx context.Context, cfg config.Config, st store.Store) (*Authenticator, error) {
	a := &Authenticator{store: st, defaultCenter: cfg.DefaultCenterID}
	if cfg.FirebaseProject == "" {
		return a, nil
	}
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: cfg.FirebaseProject})
	if err != nil {
		return nil, err
	}
	client, err := app.Auth(ctx)
	if err != nil {
		return nil, err
	}
	a.fbClient = client
	a.fbApp = app
	return a, nil
}

// Middleware — 모든 /v1 요청에 대해 Principal을 resolve해 컨텍스트에 심는다.
func (a *Authenticator) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p, err := a.resolve(r)
		if err != nil {
			// 원인은 로그에만 — VerifyIDToken 실패(JWKS 페치 불가·시계 오차·프로젝트 설정)가
			// 전면 401 폭풍이 될 수 있는데, 종전엔 이 경로에 로그가 한 줄도 없어 사고가 나도
			// 서버 로그에서 원인을 찾을 수 없었다(P35 H-4). 응답에는 우리가 만든 안내 sentinel만
			// 싣고 SDK 에러 원문은 흘리지 않는다(util.go의 원문 노출 금지 원칙).
			log.Printf("auth reject: reqid=%s %s %s: %v",
				middleware.GetReqID(r.Context()), r.Method, r.URL.Path, err)
			msg := "unauthorized"
			if errors.Is(err, errMissingToken) || errors.Is(err, errDevHeadersRequired) || errors.Is(err, errInvalidRole) {
				msg = "unauthorized: " + err.Error()
			}
			writeJSON(w, http.StatusUnauthorized, errBody{Error: msg})
			return
		}
		next.ServeHTTP(w, r.WithContext(withPrincipal(r.Context(), p)))
	})
}

func (a *Authenticator) resolve(r *http.Request) (Principal, error) {
	if a.fbClient != nil {
		return a.resolveFirebase(r)
	}
	return a.resolveDev(r)
}

func (a *Authenticator) resolveFirebase(r *http.Request) (Principal, error) {
	authz := r.Header.Get("Authorization")
	if !strings.HasPrefix(authz, "Bearer ") {
		return Principal{}, errMissingToken
	}
	token, err := a.fbClient.VerifyIDToken(r.Context(), strings.TrimPrefix(authz, "Bearer "))
	if err != nil {
		return Principal{}, err
	}
	// 신규 가입 흐름 부트스트랩: 처음 로그인한 사용자는 UserIndex가 없다 — 기본 role=member로
	// 통과시켜 /v1/join/* 을 호출할 수 있게 한다. staff(owner/trainer) 권한은 UserIndex에
	// 미리 심어둔 값으로만 부여된다(수동 시딩 필요 — README 갭 참고, 계약에 스태프 생성 API 없음).
	p := a.enrich(r.Context(), token.UID, domain.RoleMember)
	if phone, ok := token.Claims["phone_number"].(string); ok {
		p.Phone = phone // 전화 인증 사용자면 검증된 번호가 실림(P06 — join 매칭의 진실 원천)
	}
	return p, nil
}

// resolveDev — 로컬 개발 인증: X-Dev-Uid(필수) + X-Dev-Role(필수, owner|trainer|member).
// Store에 이미 UserIndex가 있으면 센터·회원ID를 덧붙여 실사용에 가깝게 만든다(선택적 보강).
func (a *Authenticator) resolveDev(r *http.Request) (Principal, error) {
	uid := r.Header.Get("X-Dev-Uid")
	role := r.Header.Get("X-Dev-Role")
	if uid == "" || role == "" {
		return Principal{}, errDevHeadersRequired
	}
	if role != domain.RoleOwner && role != domain.RoleTrainer && role != domain.RoleMember {
		return Principal{}, errInvalidRole
	}
	return a.enrich(r.Context(), uid, role), nil
}

// enrich — Store의 UserIndex로 centerID/memberID를 보강한다. 인덱스가 없으면 기본 센터 +
// 주어진 role로 폴백한다(가입 매칭 전 신규 사용자도 /v1/me, /v1/join/* 을 호출할 수 있어야 함).
func (a *Authenticator) enrich(ctx context.Context, uid, fallbackRole string) Principal {
	p := Principal{UID: uid, Role: fallbackRole, CenterID: a.defaultCenter}
	if a.store == nil {
		return p
	}
	idx, err := a.store.GetUserIndex(ctx, uid)
	if err != nil {
		if !errors.Is(err, store.ErrNotFound) {
			// 인덱스 없음(신규 가입자)은 정상 경로지만, 그 외(Firestore 장애 등)는 owner가
			// 조용히 member로 강등되는 사건이다 — 보안상 fail-closed 폴백 자체는 유지하되,
			// "DB 장애"가 "권한 버그"로 위장되지 않게 로그로 드러낸다(P35 L-1).
			log.Printf("user index lookup failed (role fallback to %s): uid=%s: %v", fallbackRole, uid, err)
		}
		return p
	}
	p.Role = idx.Role
	p.CenterID = idx.CenterID
	p.MemberID = idx.MemberID
	return p
}
