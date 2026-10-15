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

// IsSuperadmin — 교차 센터 관리 평면 전용 롤(멀티센터 Phase A). **IsStaff에 넣지 않는다** —
// 기존 owner/staff 가드 87곳이 무변경으로 superadmin을 403 처리하는 것이 설계다(설계04 §2:
// 일상 운영·회원 개인정보에는 들어가지 않는 경계). CenterID는 빈 값이다.
func (p Principal) IsSuperadmin() bool { return p.Role == domain.RoleSuperadmin }

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
	errInvalidRole        = errors.New("X-Dev-Role must be owner|trainer|member|superadmin")
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
			// 본문은 **항상 사용자향 한국어**다. 두 클라이언트 모두 서버의 error 문자열을
			// 자기 폴백보다 우선해 화면에 띄우므로(admin api.ts·앱 api_result_guard), 여기에
			// "unauthorized"나 dev 헤더 이름을 실으면 그대로 사용자 화면에 뜬다 — util.go가
			// 세운 "영문 내부 문구 노출 금지" 원칙이 이 한 줄에서 깨진다. 원인 구분이 필요하면
			// 기계 판독용 code 필드를 쓴다(로그에는 이미 원문이 남는다).
			code := "unauthorized"
			switch {
			case errors.Is(err, errMissingToken):
				code = "missing_token"
			case errors.Is(err, errDevHeadersRequired):
				code = "dev_headers_required"
			case errors.Is(err, errInvalidRole):
				code = "invalid_role"
			}
			writeJSON(w, http.StatusUnauthorized, struct {
				Error string `json:"error"`
				Code  string `json:"code"`
			}{Error: "인증이 필요해요 — 다시 로그인해주세요", Code: code})
			return
		}
		// 접속기록(accesslog.go, v2.30)에 Principal을 역주입한다. accessLog는 이 미들웨어보다
		// **앞**에 서 있고(401을 기록하려고), 아래 r.WithContext가 만드는 파생 컨텍스트의 값 타입
		// Principal은 그쪽에서 보이지 않는다 — 그래서 앞에서 심어 둔 포인터 엔트리를 여기서 채운다.
		// 이 두 줄을 지우면 모든 스태프 요청이 '미인증'으로 기록된다(TestAccessLogRecordsStaffRequest).
		if e := accessEntryFrom(r.Context()); e != nil {
			e.principal, e.resolved = p, true
		}
		// superadmin은 관리 평면(/admin/*)과 /me만 쓴다. 센터 스코프 API에 들어가면
		// CenterID=""로 store를 때려 Firestore nil doc ref panic(→500)이 되거나 빈 답을
		// 진실처럼 주게 된다 — 개별 서비스 가드 87곳을 재검토하는 대신 여기 한 관문에서
		// 막는다(운영 침입 방지가 기본값, 설계04 §2).
		if p.IsSuperadmin() && !superadminAllowedPath(r.URL.Path) {
			writeJSON(w, http.StatusForbidden,
				errBody{Error: "forbidden: superadmin은 관리 평면(/v1/admin/*)만 사용할 수 있어요"})
			return
		}
		next.ServeHTTP(w, r.WithContext(withPrincipal(r.Context(), p)))
	})
}

// superadminAllowedPath — /v1 · /api/v1 두 마운트를 모두 커버한다. /me는 어드민 로그인
// 부트스트랩(fetchMe)이 역할 판별에 쓴다.
//
// **경로 파라미터 자리까지 포함한 정확한 형태로 판정한다**(v2.37, P73). 종전 판정은
// `strings.Contains(path, "/admin/") || strings.HasSuffix(path, "/me")`였는데, `{id}`가 경로의
// 마지막 세그먼트인 라우트(`DELETE /v1/inbody/{id}` 등)에 id=`me`를 주거나, `{id}` 뒤에 정적
// 세그먼트가 붙는 라우트(`POST /v1/bookings/{id}/complete`)에 id=`admin`을 주면 문자열이 우연히
// 조건을 만족해 이 관문을 지나갔다. 데이터가 새지는 않았다(CenterID=""로 내려간 조회가 스토어에서
// 먼저 실패한다) — 하지만 그 결과가 403이 아니라 500이라 "관문 하나가 87곳을 대신한다"는 위
// 불변식이 특정 경로에서 조용히 깨져 있었다. 마운트 접두사(/api)만 벗기고 나머지는 상수 비교다.
func superadminAllowedPath(path string) bool {
	p := strings.TrimPrefix(path, "/api")
	return p == "/v1/me" || strings.HasPrefix(p, "/v1/admin/")
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
	if role != domain.RoleOwner && role != domain.RoleTrainer && role != domain.RoleMember &&
		role != domain.RoleSuperadmin {
		return Principal{}, errInvalidRole
	}
	p := a.enrich(r.Context(), uid, role)
	// dev 헤더로 superadmin을 흉내낼 때는 센터 소속을 비운다 — 운영에선 UserIndex의
	// center_id=""가 같은 일을 한다(enrich가 인덱스 값을 그대로 복사).
	if p.Role == domain.RoleSuperadmin {
		p.CenterID = ""
	}
	return p, nil
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
