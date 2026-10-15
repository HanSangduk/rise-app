// Package api는 chi 라우터·인증 미들웨어·서비스 오케스트레이션·핸들러를 담는다.
// 의존 방향: api → {store, domain}. 순수 판정(환불·예약규칙·홈워크배정·체크인시간창)은
// domain에 위임하고, 이 레이어는 스토어 조합·역할 스코프·트랜잭션 순서만 책임진다.
package api

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"slices"
	"strings"
	"time"

	"github.com/ramsang/rise-backend/internal/config"
	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// recurringExpandWeeks — 고정 스케줄 생성 시 선행 예약할 주 수(설계03 §5: "2~4주 선행 자동 생성"의 상한).
const recurringExpandWeeks = 4

// Service — 코어 오케스트레이션. 역할 스코프 검증 + 스토어 조합.
type Service struct {
	store store.Store
	cfg   config.Config
	// users — 스태프 온보딩 시 로그인 계정을 확보하는 경계(provision.go). Firebase 모드면
	// Admin SDK 구현, dev 모드면 합성 uid 구현이 주입된다.
	users UserProvisioner
	// media — 회원탈퇴 시 Cloud Storage 원본 파일을 파기하는 경계(provision.go, v2.11).
	media MediaPurger
	// uploader — 트레이너 프로필 사진을 Storage에 올리는 경계(provision.go, v2.25).
	// 기본값이 **no-op이 아니라 503 구현**인 것이 media와의 차이다: 업로드가 조용히
	// 성공하면 "저장했어요"가 거짓말이 된다(MediaUploader 주석).
	uploader MediaUploader
}

// NewService — users가 nil이면 dev 합성 uid 구현으로 폴백한다(테스트·로컬이 SDK 없이 돌아야 한다).
func NewService(st store.Store, cfg config.Config, users UserProvisioner) *Service {
	if users == nil {
		users = devUserProvisioner{}
	}
	return &Service{
		store: st, cfg: cfg, users: users,
		// 주입되지 않으면 파기는 no-op, 훑기는 503이다(unconfiguredPurger 주석, v2.28). 테스트·
		// 로컬이 SDK 없이 도는 것과, 미구성 서버가 "고아 0건"이라고 거짓말하지 않는 것을 같은
		// 기본값으로 만족시킨다 — uploader의 기본값이 503 구현인 것과 같은 규율.
		media: unconfiguredPurger{reason: "사진 저장소가 설정되지 않았어요(관리자에게 STORAGE_BUCKET 설정을 요청해주세요)"},
		// 주입되지 않으면 업로드는 503이다 — 테스트·로컬이 SDK 없이 도는 것과, 미구성
		// 서버가 가짜 URL을 돌려주지 않는 것을 **같은 기본값**으로 만족시킨다.
		uploader: unconfiguredUploader{reason: "사진 업로드 저장소가 설정되지 않았어요(관리자에게 STORAGE_BUCKET 설정을 요청해주세요)"},
	}
}

// WithMediaPurger — Storage 파기 경계를 주입한다(기본은 dev no-op). NewService의 인자로 넣지
// 않은 이유: 이 경계를 쓰는 경로가 탈퇴 하나뿐인데 생성자를 바꾸면 기존 호출부 전부와
// 테스트 30여 곳이 함께 움직인다. users처럼 필수 의존이 아니라 **선택적 강화**다.
func (s *Service) WithMediaPurger(m MediaPurger) *Service {
	if m != nil {
		s.media = m
	}
	return s
}

// WithMediaUploader — Storage 업로드 경계를 주입한다(v2.25). WithMediaPurger와 같은 이유로
// 생성자가 아니라 옵션이다. nil을 넘기면 기본값(503 구현)이 유지된다 — **no-op으로
// 되돌아가지 않는다**는 것이 이 가드의 요점이다.
func (s *Service) WithMediaUploader(u MediaUploader) *Service {
	if u != nil {
		s.uploader = u
	}
	return s
}

// today — 센터 타임존(KST) 기준 오늘 날짜 문자열.
func today() string { return time.Now().In(domain.KST).Format("2006-01-02") }

// ---- /v1/me ----

type MeResponse struct {
	UID      string `json:"uid"`
	Role     string `json:"role"`
	CenterID string `json:"center_id"`
	MemberID string `json:"member_id,omitempty"`
	// Name — 화면에 띄울 본인 이름(v2.2). 없으면 빈 문자열.
	// 이게 없어서 앱은 세션 복원 후 헤더가 센터명으로 떨어졌고, 어드민은 이메일 원문을 감추려고
	// GET /v1/staff 목록을 받아 uid로 조인하고 있었다 — 이름 하나 때문에 목록 조회에 의존했다.
	Name string `json:"name,omitempty"`
	// JoinRequest — **member_id가 없을 때만** 실리는 대기 상태(v2.27). 종전엔 "가입 요청을
	// 보냈다"는 사실의 주인이 앱의 SharedPreferences였다 — 기기를 바꾸거나 앱을 지우면
	// 사라져서, 이미 큐에 서 있는 사람이 화면상 아무것도 안 한 사람이 되고 재요청을 누른다
	// (그 재요청이 큐를 늘렸고, 늘어난 큐가 C-2 좀비 승인의 재료였다). 대기 상태의 주인을
	// 서버로 옮긴다.
	//
	// 연결된 회원·스태프에겐 나가지 않는다(omitempty + Me의 분기) — member_id가 있다는 것
	// 자체가 "대기 끝"이고, 두 값이 동시에 실리면 앱이 어느 쪽을 믿을지 정해야 한다.
	JoinRequest *MeJoinRequest `json:"join_request,omitempty"`
}

// MeJoinRequest — 대기 상태의 **최소 노출**(v2.27). 두 칸뿐이다.
//
// 왜 id·name·phone·center_id를 싣지 않는가: JoinMatchMember(연결 전 단계 최소 노출)와 같은
// 규율이다. 이름·번호는 신청자가 **방금 자기 손으로 적은 값**이라 서버가 되돌려줄 이유가
// 없고(화면에 다시 띄울 곳도 없다), id는 승인·거절이 owner 전용 동사라 신청자에게 쓸모가
// 없다 — 있으면 "그 id로 무엇을 할 수 있나"를 찾게 만드는 표면만 는다. center_id는 v1이
// 단일 센터라 진실이 아닌 선택지를 암시한다(JoinRequestCreate의 봉인 주석 참고).
//
// 오라클 표면도 없다: 이 값은 **자기 uid로만** 스코프되므로 남의 존재를 캐낼 수 없다.
type MeJoinRequest struct {
	Status string `json:"status"` // pending|approved|rejected
	// CenterID — 요청이 귀속된 센터(v2.34, P69). v2.27은 "v1 단일 센터라 진실이 아닌 선택지를
	// 암시한다"며 이 칸을 뺐는데, v2.33이 `POST /v1/join/request.center_id`로 선택을 열면서
	// 그 근거가 소멸했다. 이제는 **감추는 쪽이 거짓**이다 — 요청은 2호점에 있는데 앱 대기실은
	// 1호점 연락처를 찍는다. 자기 uid 스코프의, 신청자가 방금 자기 손으로 고른 값이라
	// (`GET /v1/join/centers`가 인증 사용자에게 이미 주는 ID 집합의 원소) 새 오라클 표면은 없다.
	CenterID  string    `json:"center_id"`
	CreatedAt time.Time `json:"created_at"`
}

// Me — GET /v1/me. 세션 부트스트랩이자 **모든 클라이언트가 가장 먼저 부르는 엔드포인트**다.
//
// 이름은 **best-effort**로 채운다: 조회가 실패해도 에러를 올리지 않고 빈 값으로 둔다.
// 이 호출이 실패하면 앱은 온보딩도 시작하지 못하고 어드민은 로그인 화면에 갇힌다 — 표시용
// 이름 하나 때문에 그 위험을 지지 않는다. 이름이 비면 클라이언트가 기존 폴백을 쓰면 된다.
func (s *Service) Me(ctx context.Context, p Principal) MeResponse {
	res := MeResponse{UID: p.UID, Role: p.Role, CenterID: p.CenterID, MemberID: p.MemberID}
	switch {
	case p.IsStaff():
		if st, err := s.store.GetStaff(ctx, p.CenterID, p.UID); err == nil {
			res.Name = st.Name
		}
	case p.MemberID != "":
		if mem, err := s.store.GetMember(ctx, p.CenterID, p.MemberID); err == nil {
			res.Name = mem.Name
		}
	case p.IsMember():
		// 회원인데 member_id가 없다 = **대기실**(v2.27). 이 분기가 스태프·연결된 회원보다
		// 뒤에 오는 것이 규약이다: 스태프는 member_id가 늘 비어 있어 앞 case가 먼저 잡지
		// 않으면 대표의 /v1/me가 매 호출마다 가입 요청 큐를 훑게 된다(그리고 대표에게
		// 신청자의 대기 상태를 보여줄 이유가 없다). superadmin은 어느 case에도 걸리지 않는다.
		if jr := s.latestJoinRequest(ctx, p); jr != nil {
			res.JoinRequest = jr
		}
	}
	return res
}

// latestJoinRequest — 호출자 uid의 **가장 최근** 가입 요청 한 건(v2.27). 없으면 nil.
//
// 왜 최신 1건인가: 앱이 답해야 하는 질문은 "지금 내 요청은 어떻게 됐나" 하나다. 과거 이력을
// 주면 화면이 목록을 그려야 하고, 그 목록에 답이 여러 개면 어느 것이 현재인지 다시 정해야 한다.
// 스토어의 ListJoinRequests가 이미 최신 먼저로 정렬해 돌려준다(두 구현 공통 규약).
//
// **Me의 이름 채우기와 같은 best-effort다** — 조회가 실패해도 에러를 올리지 않는다. 이
// 호출이 실패하면 앱은 온보딩도 시작하지 못하는데(Me 주석), 대기 상태 하나 때문에 그
// 위험을 지지 않는다. 값이 없으면 앱은 기존 폴백(로컬 플래그)을 쓰면 된다.
//
// pending으로 좁히지 **않는** 이유: 거절(D-3)도 결론이고, 그 결론을 신청자에게 전달하는 것이
// 이 필드의 절반이다(rejected를 감추면 신청자는 pending과 구별하지 못해 영원히 기다리거나
// 무한 재요청한다 — D-3이 문서를 통째로 지우지 않기로 한 이유와 같은 자리).
//
// **uid로 묻는다, 센터로 묻지 않는다**(v2.34). 종전엔 `ListJoinRequests(p.CenterID)`였는데
// 미연결 uid의 `p.CenterID`는 기본 센터 폴백이라(v2.32) v2.33이 연 센터 선택을 못 따라갔다 —
// 2호점에 보낸 요청이 여기서 0건이 되어 앱은 "요청 없음"을 읽고, 사용자는 재요청 → 409에
// 갇혔다(P69 팀 C 1-b). 큐 전체(N)가 아니라 그 사람의 요청(k)만 읽으니 폴링 비용도 준다.
func (s *Service) latestJoinRequest(ctx context.Context, p Principal) *MeJoinRequest {
	list, err := s.store.ListJoinRequestsByUID(ctx, p.UID)
	if err != nil {
		log.Printf("me: join request lookup failed (best-effort skip): uid=%s: %v", p.UID, err)
		return nil
	}
	if len(list) == 0 {
		return nil
	}
	jr := list[0] // 최신 먼저 — 첫 항목이 곧 현재 상태다
	return &MeJoinRequest{Status: jr.Status, CenterID: jr.CenterID, CreatedAt: jr.CreatedAt}
}

// ---- 가입 매칭(P48) ----

// JoinMatchMember — 연결 **전** 단계에 노출하는 최소 필드(v1.9). 이 응답은 아직 본인 확인이
// 끝나지 않은 호출자에게 나가므로 회원 엔티티를 통째로 주지 않는다. 특히 flags(부상 메모 =
// 건강정보)·consent·channel·last_visit_at은 확인 1탭에 필요 없다.
// 남긴 필드의 근거: name은 "OOO 님이 맞으세요?" 문구, phone은 클라이언트 표기 대조,
// trainer_id·status는 연결 직후 홈 화면 구성에 쓰인다(app MemberDto의 필수 필드이기도 하다).
type JoinMatchMember struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Phone     string `json:"phone"`
	TrainerID string `json:"trainer_id"`
	Status    string `json:"status"`
}

type JoinMatchResponse struct {
	Member       *JoinMatchMember `json:"member,omitempty"`
	NeedsConfirm bool             `json:"needs_confirm"`
	// Center — 매칭된 **그 회원의 센터** 신원(v2.32, 멀티센터). 미매칭이거나 센터 상호가
	// 미등록이면 생략된다.
	//
	// 싣는 이유: 대기실은 센터 상호를 `GET /v1/public/center`(무인증이라 기본 센터 고정)에서
	// 읽으므로, 2호점 회원에게 1호점 이름을 보여준다. 매칭 응답이 곧 "당신의 센터"를 아는
	// 유일한 지점이라 여기서 함께 준다. 앱이 이 값을 읽기 시작하면 그 표시가 정정된다
	// (앱 반영은 다음 빌드 — work_log/P65 후속).
	Center *CenterIdentityView `json:"center,omitempty"`
}

// joinPhone — join 계열이 신뢰할 전화번호를 고른다.
//
// Firebase 모드에선 **토큰의 검증된 phone_number가 유일한 출처**다. 바디 폴백을 남겨두면
// 전화 인증을 거치지 않은 계정(이메일/비밀번호 등 — 프로젝트에 계정만 만들면 된다)이
// 남의 번호를 바디에 실어 그 회원 레코드에 연결할 수 있다(계정 탈취). 토큰에 번호가 없으면
// 이 기능을 쓸 자격이 없으므로 403이다.
//
// dev 모드(FIREBASE_PROJECT 미설정)에서만 바디 값을 쓴다 — 로컬 개발엔 토큰 자체가 없다.
func (s *Service) joinPhone(p Principal, body string) (string, error) {
	if p.Phone != "" {
		return p.Phone, nil
	}
	if s.cfg.FirebaseProject != "" {
		return "", ErrForbidden
	}
	return body, nil
}

// guardNotStaff — 이미 스태프인 uid를 회원으로 연결(=강등)하지 못하게 막는다.
//
// UserIndex는 역할의 단일 출처다(auth.go의 enrich가 이것만 본다). join 계열이 이 문서를
// role=member로 덮어쓰면 대표는 자기 권한을 잃고, 되돌릴 API가 없어 **센터가 영구히 잠긴다**
// (Firestore를 직접 편집해야 복구된다). 스태프가 실수로든 고의로든 이 경로에 들어오면 거절한다.
// v2.36: **부재와 장애를 가른다.** 종전엔 모든 에러를 "신규 사용자"로 접어 fail-open이었다 —
// Firestore 순단 중 대표 계정이 join 경로를 타면 이 방어선이 조용히 꺼지고, 뒤이은
// SaveUserIndex가 role을 member로 덮어 **그 대표가 자기 센터에서 영구히 잠긴다**(위 주석이
// 말하는 바로 그 사고). 같은 파일의 guardIndexNotLinkedMember·JoinApprove는 이미
// "인프라 에러를 조건 불성립으로 삼키지 않는다"는 규약을 지키고 있었고, 이 함수만 옛 형태였다.
func (s *Service) guardNotStaff(ctx context.Context, uid string) error {
	idx, err := s.store.GetUserIndex(ctx, uid)
	if errors.Is(err, store.ErrNotFound) {
		return nil // 인덱스 없음 = 신규 사용자. 정상 경로다.
	}
	if err != nil {
		return err // 장애는 장애로 — 못 본 것을 "스태프 아님"으로 단정하지 않는다
	}
	if idx.Role == domain.RoleOwner || idx.Role == domain.RoleTrainer {
		return ErrForbidden
	}
	return nil
}

// JoinMatch — 번호 인증 후 자동 매칭 조회(P48①). 매칭되면 회원 명단은 아직 연결 전이므로
// 클라이언트가 "OOO 님이 맞으세요?" 이름 확인 1탭을 띄우게 한다(needs_confirm).
func (s *Service) JoinMatch(ctx context.Context, p Principal, phone string) (JoinMatchResponse, error) {
	phone, err := s.joinPhone(p, phone)
	if err != nil {
		return JoinMatchResponse{}, err
	}
	// **`p.CenterID`를 쓰지 않는다**(v2.32). 처음 앱을 켠 사람은 UserIndex가 없어 그 값이
	// 기본 센터로 채워지므로, 2호점 회원은 라이즈에서만 조회돼 영원히 못 찾는다
	// (service_join_center.go 헤더 주석). 번호가 센터를 정한다.
	match, err := s.resolveMemberByPhone(ctx, phone)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			return JoinMatchResponse{NeedsConfirm: false}, nil
		}
		return JoinMatchResponse{}, err
	}
	mem := match.Member
	return JoinMatchResponse{
		Member: &JoinMatchMember{
			ID: mem.ID, Name: mem.Name, Phone: mem.Phone,
			TrainerID: mem.TrainerID, Status: mem.Status,
		},
		NeedsConfirm: true,
		Center:       s.joinCenterView(ctx, match.CenterID),
	}, nil
}

type JoinConfirmRequest struct {
	MemberID string `json:"member_id"`
	Confirm  bool   `json:"confirm"`
	// Phone — 연결 대상 회원의 전화번호 재대조(2R HIGH-4: member_id만으로 타인 레코드에
	// 연결되는 탈취 체인 차단).
	//
	// **프로덕션에서는 이 값이 쓰이지 않는다**(v1.9). joinPhone이 토큰의 검증된 phone_number를
	// 강제하고, 번호 없는 토큰은 403이다. 이 필드는 dev 모드(FIREBASE_PROJECT 미설정 — 토큰
	// 자체가 없는 환경)의 유일한 번호 출처로만 남아 있다.
	Phone string `json:"phone"`
}

type JoinConfirmResponse struct {
	Linked bool           `json:"linked"`
	Member *domain.Member `json:"member,omitempty"`
}

// JoinConfirm — 이름 확인 1탭(P48). confirm=false면 "본인이 아니에요" — 연결하지 않는다
// (설계03 §"이름 확인이 핵심 보안장치" — 오연결 방지가 마찰보다 우선).
func (s *Service) JoinConfirm(ctx context.Context, p Principal, req JoinConfirmRequest) (JoinConfirmResponse, error) {
	if !req.Confirm {
		return JoinConfirmResponse{Linked: false}, nil
	}
	// 권한 검사는 **데이터 조회보다 먼저** 한다. 순서가 뒤집히면 자격 없는 호출자가 404/403의
	// 차이로 member_id의 존재 여부를 캐낼 수 있고(존재 오라클), 권한 없는 요청이 스토어까지
	// 내려간다. 아래 두 가드는 요청 내용과 무관하게 호출자만 보므로 맨 앞이 제자리다.
	//
	// (1) 스태프 계정 차단 — SaveUserIndex가 role=member로 덮어써 권한을 영구히 잃는다(v1.9).
	if err := s.guardNotStaff(ctx, p.UID); err != nil {
		return JoinConfirmResponse{}, err
	}
	// (2) 검증된 번호 확보 — Firebase 모드에선 토큰의 phone_number가 없으면 자격 자체가 없다.
	checkPhone, err := s.joinPhone(p, req.Phone)
	if err != nil {
		return JoinConfirmResponse{}, err
	}

	// 센터는 **번호가 정한다**(v2.32) — `p.CenterID`는 신규 uid에서 기본 센터로 채워지는
	// 값이라 2호점 회원의 확인이 라이즈 문서를 열려다 404가 된다(JoinMatch와 같은 근거,
	// service_join_center.go 헤더 주석).
	match, err := s.resolveMemberByPhone(ctx, checkPhone)
	if err != nil {
		// **번호로 아무도 못 찾은 건 400이다**(404가 아니라). 탈퇴 회원은 가명화로 번호가
		// 비어 있어 이 경로로 떨어지는데, 계약과 테스트가 그 시도를 400으로 못박아 뒀다
		// (service_account_test "가입 재연결(되살리기)" — 탈퇴는 종단 상태다).
		//
		// 문구가 이유를 특정하지 않는 것도 의도다: 여기 도착하는 세 경우(탈퇴·없는 member_id·
		// 등록 번호 변경)를 갈라 말하면 **member_id를 넣어 보며 존재를 알아내는 오라클**이
		// 된다(ID가 mem_000001 꼴이라 추측이 싸다). 회원이 할 일은 셋 다 같다.
		if errors.Is(err, store.ErrNotFound) {
			return JoinConfirmResponse{}, errors.Join(errBadRequest,
				errors.New("연결할 수 없는 회원이에요 — 센터에 등록된 번호가 맞는지 확인하고, 새로 가입 요청을 해주세요"))
		}
		return JoinConfirmResponse{}, err
	}
	centerID, mem := match.CenterID, match.Member
	// 번호가 가리킨 회원과 클라이언트가 지목한 회원이 다르면 연결하지 않는다. 종전에는
	// `GetMember(p.CenterID, req.MemberID)`로 **클라이언트가 레코드를 골랐고** 번호 대조가
	// 뒤따랐다. 이제 서버가 번호로 먼저 고르고 클라이언트의 지목은 대조 대상일 뿐이다 —
	// 방어선의 순서가 바뀌었을 뿐 세기는 종전 이상이다.
	if mem.ID != req.MemberID {
		return JoinConfirmResponse{}, errors.Join(errBadRequest,
			errors.New("회원 정보가 일치하지 않아요 — 다시 확인해주세요"))
	}
	// 탈퇴한 레코드에는 다시 연결하지 않는다(v2.11 — 탈퇴는 되돌릴 수 없는 종단 상태다).
	//
	// 지금은 아래 번호 대조가 이미 막는다: 가명화가 phone을 ""로 비웠고 빈 번호는 400이다.
	// 그래도 명시하는 이유는 그 차단이 **부수효과**이기 때문이다 — 번호 비교 규칙이 언젠가
	// 바뀌면(예: 빈 값 허용) 아무도 모르는 사이 탈퇴 회원 되살리기가 열린다. 의도는 의도대로 적는다.
	if mem.IsWithdrawn() {
		return JoinConfirmResponse{}, errors.Join(errBadRequest, errors.New("탈퇴한 회원이에요 — 새로 가입 요청을 해주세요"))
	}
	// 전화번호 재대조 — 유출·추측된 member_id만으로는 연결 불가(이름확인 1탭은 UX 장치,
	// 이 검증이 서버측 방어선).
	if domain.NormalizePhone(checkPhone) == "" || domain.NormalizePhone(checkPhone) != domain.NormalizePhone(mem.Phone) {
		return JoinConfirmResponse{}, errors.Join(errBadRequest, errors.New("전화번호가 회원 정보와 일치하지 않아요"))
	}
	mem.AppLinked = true
	if _, err := s.store.SaveMember(ctx, centerID, mem); err != nil {
		return JoinConfirmResponse{}, err
	}
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{
		UID: p.UID, Role: domain.RoleMember, CenterID: centerID, MemberID: mem.ID,
	}); err != nil {
		return JoinConfirmResponse{}, err
	}
	// **연결됐으면 그 uid의 가입 요청은 파기한다**(v2.27 — C-2의 원인 제거).
	//
	// 종전엔 이 함수가 join_requests를 전혀 건드리지 않았다. 그래서 "앱으로 먼저 요청 →
	// 데스크에서 따로 등록 → 회원이 재인증해 진짜 레코드에 연결"이라는 **실제로 흔한 동선**이
	// 큐에 좀비 pending을 남겼고, 며칠 뒤의 승인 한 번이 그 회원의 회원권·예약·기록·체형사진을
	// 통째로 잃게 만들었다(JoinApprove의 "이미 연결된 uid" 가드 주석 참고). 여기서 지우면
	// 그 좀비가 애초에 생기지 않는다.
	//
	// **P53이 만든 DeleteJoinRequestsByUID를 그대로 쓴다**(새 스토어 동사를 만들지 않는다).
	// 그 동사의 규약이 이 자리에 정확히 맞는다: uid 전체 스코프(다른 센터 큐의 요청도 같은
	// 사람의 것이고, 연결된 지금은 어느 센터도 승인해선 안 된다) · 없는 uid도 성공(0건) ·
	// 몇 번을 돌려도 결과가 같다(멱등).
	//
	// 자리가 왜 **맨 뒤**인가: 앞의 두 쓰기(SaveMember·SaveUserIndex)가 연결의 본체다. 이걸
	// 그보다 앞에 두면, 삭제만 성공하고 연결이 실패했을 때 신청자는 큐에서도 사라지고 연결도
	// 안 된 상태가 된다 — 대표에게 보이지 않는 사람이 생긴다. 뒤에 두면 반대로 "연결됐는데
	// 큐에 남은" 상태가 될 수 있지만, 그쪽은 JoinApprove의 가드가 이미 무해하게 만들었고
	// 재시도(JoinConfirm 자체가 멱등이다)가 마저 지운다.
	//
	// 에러를 삼키지 않는 이유: 삼키면 잔여를 아무도 모른다. 호출측에 500이 올라가면 앱이
	// 재시도하고, 재시도는 위 세 쓰기가 전부 멱등이라 깨끗하게 다시 돈다.
	if _, err := s.store.DeleteJoinRequestsByUID(ctx, p.UID); err != nil {
		return JoinConfirmResponse{}, err
	}
	return JoinConfirmResponse{Linked: true, Member: mem}, nil
}

type JoinRequestBody struct {
	// CenterID — **선택한 센터**(계약 v2.33). 비면 종전대로 Principal의 센터(신규 uid면 기본
	// 센터)를 쓴다. 값이 있으면 `GET /v1/join/centers` 목록에 있는 것만 통과한다.
	CenterID string `json:"center_id"`
	Name     string `json:"name"`
	Phone    string `json:"phone"`
}

// JoinRequestCreate — 매칭 실패 폴백(P48③): 센터 검색 후 가입 요청.
func (s *Service) JoinRequestCreate(ctx context.Context, p Principal, req JoinRequestBody) (*store.JoinRequest, error) {
	// 센터는 **토큰이 정한다** — 바디의 center_id는 무시한다.
	//
	// 예전엔 바디 값을 그대로 저장해서, 존재하지 않는 센터("rise-2")로도 200이 나갔다. 그 요청은
	// 어느 owner의 목록(ListJoinRequests는 p.CenterID로 조회)에도 뜨지 않고, 설령 ID를 알아내
	// 승인해도 JoinApprove의 `jr.CenterID != p.CenterID`에 걸려 403이다 — 신청자는 "요청됨"을
	// 본 채 영원히 기다린다. 남의 센터 큐에 요청을 밀어넣는 경로이기도 했다.
	//
	// 계약이 center_id를 옵션(`center_id?`)으로 둔 이유는 "안 보내면 서버가 기본 센터로 채운다"인데,
	// 그 요구는 이미 충족돼 있다: Principal.CenterID는 인증 미들웨어가 UserIndex에서 복원하고,
	// 인덱스가 없는 신규 가입자면 cfg.DefaultCenterID로 폴백한다(auth.go enrich). v1은 단일 센터라
	// 호출자가 고를 여지 자체가 없다 — 멀티센터로 갈 때 "그 센터의 회원인가"를 검증하는 자리가
	// 여기다(지금 바디 값을 신뢰하면 그 검증 없이 열려 있는 셈).
	//
	// **v2.27에서도 열지 않았다 — 이유가 갱신됐다.** 종전의 이유는 "검증할 자리가 없다"였고
	// 지금의 이유는 **넣을 목록이 없다**이다: 회원용 센터 목록 API가 존재하지 않고
	// (GET /v1/admin/centers는 superadmin 전용), 그 아래의 ListCenters는 `name`이 빈 센터를
	// 거르는데 운영 센터(rise)가 바로 그 상태였다 — 열어 봐야 고를 것이 0개인 선택지다.
	// v2.27은 그 선행조건 쪽을 먼저 고친다(PUT /v1/center의 `center` 덩어리로 센터가 신원을
	// 갖는다). 선택을 여는 조건은 셋이다: ① 신원 등록된 센터가 2곳 이상 ② 회원이 읽을 수 있는
	// 목록 엔드포인트 ③ 여기에 "그 센터가 실재하고 가입을 받는가" 검증. 셋이 갖춰지기 전에
	// 바디 값을 믿으면 종전 결함(존재하지 않는 센터로 200 → 영원한 pending)이 그대로 돌아온다.
	// **선택을 연다**(v2.33). 위 주석이 적어 둔 조건 셋 중 ②(회원용 목록 endpoint)와
	// ③(실재 검증)이 갖춰졌다 — `GET /v1/join/centers`와 `resolveJoinCenter`다. ①(신원 등록
	// 센터 2곳 이상)은 런타임 조건이라 앱이 목록 길이로 판단한다.
	//
	// 신뢰 경계는 그대로다: 클라이언트가 **고를 수는 있어도 만들 수는 없다** — 서버가 만든
	// 목록에 없는 값은 400이다. 봉인했던 것은 "임의 문자열 신뢰"였지 선택 자체가 아니었다.
	centerID, err := s.resolveJoinCenter(ctx, p, req.CenterID)
	if err != nil {
		return nil, err
	}
	// 스태프가 가입 요청을 내면 owner 승인 시 JoinApprove가 그 uid를 member로 덮어써 강등된다.
	// 요청 단계에서 막는다(v1.9 — confirm과 같은 규칙).
	if err := s.guardNotStaff(ctx, p.UID); err != nil {
		return nil, err
	}
	// 승인(JoinApprove)이 이 번호를 그대로 회원 레코드로 굳히므로, 토큰의 검증된 번호와
	// 어긋나면 여기서 막는다(P06 — match·confirm과 같은 규칙). 덮어쓰지 않고 대조만 하는 이유는
	// 사용자가 입력한 표기("010-1234-5678")가 어드민 화면의 가독성이라 보존할 가치가 있어서다.
	// 타인 번호로 가입 요청 → owner 승인 → 그 번호의 회원 레코드 선점, 이 체인을 끊는다.
	phone := req.Phone
	verified, err := s.joinPhone(p, phone) // Firebase 모드에서 토큰 번호가 없으면 여기서 403
	if err != nil {
		return nil, err
	}
	if p.Phone != "" {
		switch domain.NormalizePhone(phone) {
		case "":
			phone = verified // 미입력 — 검증된 번호로 채운다.
		case domain.NormalizePhone(verified):
			// 일치 — 입력 표기 그대로 보존.
		default:
			return nil, errors.Join(errBadRequest, errors.New("인증한 번호와 다른 번호로는 가입을 요청할 수 없어요"))
		}
	}
	// pending 중복은 409(v2.27) — CreateConsultRequest(v2.20)와 **같은 규칙·같은 문구 형태**다.
	// 새 패턴이 아니라 같은 "회원발 요청 큐"에 이미 있던 규칙을 이쪽에도 맞춘 것이다.
	//
	// 무엇을 막는가: 앱의 대기 화면에 [다시 요청] 버튼이 있고, 상태의 주인이 로컬이라
	// 재설치·기기 변경이 그 상태를 지웠다 — 같은 사람이 큐에 2·3건씩 쌓였다. 그 잔여가
	// C-2(좀비 승인이 회원 기록을 통째로 날리는 사고)의 재료다. 입구를 하나로 만든다.
	//
	// 이 409는 사용자를 가두지 않는다: 응답 자체가 "요청이 살아 있다"는 사실의 전달이고
	// (문구가 그렇게 말한다), 같은 사실을 GET /v1/me의 join_request가 항구적으로 들고 있다
	// (A-1) — 재요청 버튼이 필요했던 이유 자체가 사라진다. 막다른 길이 생기는 경우는
	// "요청이 영원히 pending으로 남는 것"인데, 그쪽은 D-3(거절)이 대표에게 결론을 낼 수단을
	// 주고 그 결론이 다시 /v1/me로 신청자에게 간다.
	//
	// v2.34: 조회를 uid로(센터 큐 전체가 아니라 그 사람의 요청만 — latestJoinRequest와 같은 이유)
	// 바꾸되 **판정 범위는 종전대로 그 센터**다. 다른 센터에 pending이 있어도 이 센터 요청은
	// 받는다 — 잘못 고른 센터를 바로잡을 철회 동사가 없는 상태에서 전 센터로 넓히면 사용자를
	// 가둔다(두 번째 요청의 승인은 JoinApprove의 "이미 연결된 uid" 가드가 막으므로 데이터
	// 손실은 없다). 409 본문에는 `code:"join_pending"`과 그 요청의 `center_id`를 싣는다 —
	// 앱이 이 409를 "서버 확답 pending"으로 승격시켜 대기 화면으로 돌아가게(막다른 길 차단).
	existing, err := s.store.ListJoinRequestsByUID(ctx, p.UID)
	if err != nil {
		return nil, err
	}
	for _, prev := range existing {
		if prev.CenterID == centerID && prev.Status == store.JoinPending {
			return nil, &joinPendingError{centerID: prev.CenterID}
		}
	}
	jr := &store.JoinRequest{CenterID: centerID, UID: p.UID, Name: req.Name, Phone: phone, Status: store.JoinPending}
	id, err := s.store.CreateJoinRequest(ctx, jr)
	if err != nil {
		return nil, err
	}
	jr.ID = id
	return jr, nil
}

// JoinApprove — owner 원탭 승인(P48③). 회원 레코드를 만들고 요청자 uid를 연결한다.
func (s *Service) JoinApprove(ctx context.Context, p Principal, requestID string) (*domain.Member, error) {
	if !p.IsOwner() {
		return nil, ErrForbidden
	}
	jr, err := s.store.GetJoinRequest(ctx, requestID)
	if err != nil {
		return nil, err
	}
	if jr.CenterID != p.CenterID {
		return nil, ErrForbidden
	}
	// 멱등 가드(v1.9): 상태를 안 보면 두 번 누를 때 같은 사람의 회원 레코드가 둘 생기고,
	// UserIndex는 나중 것만 가리켜 먼저 만든 레코드가 고아가 된다(목록·통계·번호 인덱스엔 잔류).
	// (v2.27 전까지는 목록이 pending 필터를 하지 않아 승인된 요청이 큐에 남았고, 그래서 두 번
	// 누르는 것이 **기본 동선**이었다 — 지금은 ListJoinRequests가 pending만 돌려주므로 이
	// 가드가 잡는 것은 연타·경합 같은 예외뿐이다.)
	if jr.Status != store.JoinPending {
		return nil, errors.Join(ErrConflict, errors.New("이미 처리된 가입 요청이에요"))
	}
	// 요청자가 스태프면 승인이 곧 강등이다 — confirm·request와 같은 가드를 승인 시점에도 건다
	// (요청 이후에 스태프로 초대된 경우까지 잡는다).
	if err := s.guardNotStaff(ctx, jr.UID); err != nil {
		return nil, err
	}
	// **이미 회원으로 연결된 uid는 승인하지 않는다**(v2.27 — C-2의 마지막 방어선).
	//
	// 실측된 사고: 앱으로 가입 요청(pending) → 대표가 데스크에서 그 사람을 어드민에 직접 등록
	// → 회원이 번호 인증으로 join/match+join/confirm을 태워 **진짜 레코드에 연결**(회원권·예약·
	// 기록·체형사진이 그쪽에 붙는다) → ①의 pending은 그대로 남는다 → 며칠 뒤 대표가 큐를
	// 정리하다 승인 → SaveMember가 **빈 회원 레코드를 새로 만들고** SaveUserIndex가 신원을
	// 그리로 옮긴다 → 회원이 자기 회원권·예약·기록·사진을 전부 잃는다. 되돌릴 API가 없다.
	// 위의 멱등 가드는 **그 요청 문서의 status만** 보므로 이 경로를 못 본다 — 좀비는 여전히
	// pending이고, 진실은 다른 문서(UserIndex)에 있다.
	//
	// A-5(JoinConfirm 성공 시 pending 파기)가 원인을 없애지만, 그 삭제가 실패했거나 배포 이전에
	// 만들어진 잔여 요청이 이미 프로덕션에 있다. 원인 제거와 방어선은 **둘 다** 필요하다.
	//
	// **탈퇴 후 재가입을 막지 않는다**: 탈퇴는 DeleteUserIndex를 수행하므로 GetUserIndex가
	// ErrNotFound → 이 가드는 통과한다. 그리고 탈퇴자에게 JoinConfirm은 IsWithdrawn으로
	// 막혀 있으므로 **가입 요청 승인이 재가입의 유일한 길**이다 — 여기서 막으면 탈퇴한 사람이
	// 영원히 돌아올 수 없다. 테스트로 고정돼 있다(TestJoinApproveAllowsRejoinAfterWithdrawal).
	// guardNotStaff가 이미 GetUserIndex를 부르므로 조회 자체는 같은 자리다(호출 1회 추가).
	// **인프라 에러를 "조건 불성립"으로 삼키지 않는다**(P56). `err == nil`만 보면
	// 스토어 순단에 아래 가드가 **조용히 함께 꺼진다** — 방어가 약한 게 아니라 방어가
	// 사라지는 것이고, 로그에도 안 남는다. 부재(ErrNotFound)와 장애를 갈라, 장애면 멈춘다.
	// 이 가드가 막는 사고는 P55 C-2 — 승인 한 번이 회원권·예약·기록·체형사진을 통째로
	// 날리고 되돌릴 API가 없다. 인프라 순단에 조용히 꺼져도 되는 종류가 아니다.
	if idx, err := s.store.GetUserIndex(ctx, jr.UID); err == nil {
		if idx.MemberID != "" {
			return nil, errors.Join(ErrConflict, errors.New("이미 회원으로 연결된 계정이에요"))
		}
	} else if !errors.Is(err, store.ErrNotFound) {
		return nil, err
	}
	// **같은 번호의 살아 있는 회원이 이 센터에 이미 있으면 승인하지 않는다**(v2.34, P69).
	//
	// 승인은 `jr.Phone`으로 **새** 회원 레코드를 만든다. 그 번호의 회원이 이미 있다는 것은
	// "데스크가 이 사람을 (요청 이후에) 등록했다"는 뜻이고, 옳은 연결은 승인이 아니라 회원이
	// 같은 번호를 다시 인증해 `join/match → confirm`으로 **그 레코드에** 붙는 것이다(연결되면
	// v2.27 A-5가 이 pending을 파기한다). 여기서 승인하면 같은 사람이 두 명이 되고 회원권·예약은
	// 데스크 레코드에, 앱 계정은 빈 레코드에 붙는다 — C-2의 변종이라 서버가 막는다. 어드민 큐의
	// 중복 힌트가 같은 말을 먼저 하지만, 화면 경고는 방어선이 아니다.
	//
	// 탈퇴자는 걸리지 않는다 — 탈퇴는 번호를 파기하므로(v2.11) FindMemberByPhone에 잡히지
	// 않고, 잡히더라도 IsWithdrawn을 뺀다(재가입은 승인이 유일한 길 — 위 주석·
	// TestJoinApproveAllowsRejoinAfterWithdrawal). 부재(ErrNotFound)는 정상, 그 외 에러는 전파
	// (위 가드와 같은 규약 — 인프라 순단에 방어가 조용히 꺼지지 않는다).
	if dup, err := s.store.FindMemberByPhone(ctx, p.CenterID, jr.Phone); err == nil {
		if !dup.IsWithdrawn() {
			return nil, errors.Join(ErrConflict, errors.New(
				"같은 번호로 등록된 회원("+dup.Name+")이 이미 있어요 — 승인하면 회원이 2명이 돼요. "+
					"그 회원의 번호를 확인하고, 회원에게 앱에서 '번호 다시 인증하기'를 눌러 달라고 안내해주세요"))
		}
	} else if !errors.Is(err, store.ErrNotFound) {
		return nil, err
	}
	mem := &domain.Member{
		Name: jr.Name, Phone: jr.Phone, AppLinked: true, Status: domain.MemberStatusActive,
		Flags: []domain.MemberFlag{}, // JSON null 방지(어드민 m.flags.some 크래시 — 직렬화 계약: 항상 배열)
	}
	memberID, err := s.store.SaveMember(ctx, p.CenterID, mem)
	if err != nil {
		return nil, err
	}
	mem.ID = memberID
	jr.Status = store.JoinApproved
	// **이름·전화번호를 비운다**(v2.28, P56 A5) — JoinReject와 동형이다.
	//
	// 승인은 이름·번호를 **회원 레코드로 옮기는** 동작이지 복사하는 동작이 아니다. 위 SaveMember가
	// 끝난 순간 그 값의 처리 목적(누구를 어느 레코드로 만들 것인가)은 끝났고, 진실은 members
	// 문서에 있다. 그런데 종전엔 요청 문서에 원본이 그대로 남았다 — join_requests는 **최상위
	// 컬렉션 + uid 키**라 센터 스코프 파기 스윕이 구조적으로 못 닿고(P53), 승인된 요청은 큐에서
	// 사라져(ListJoinRequests가 pending만 돌려준다) 아무 화면도 읽지 않는다. 읽는 사람이 없는데
	// 가장 오래 남는 개인정보였다. 배포된 방침은 *"처리 완료 또는 탈퇴 시 지체 없이 파기"*를
	// 약속하는데 탈퇴 절반(P53의 DeleteJoinRequestsByUID)만 참이었다.
	//
	// 남기는 것: {uid, center_id, status=approved, created_at}. 감사 추적("이 uid가 언제
	// 요청했고 승인됐다")은 이 넷으로 완결되고, /v1/me의 join_request도 status·created_at만
	// 읽는다(MeJoinRequest). "승인 큐 이력에서 누구였는지"는 회원 레코드가 답한다 — 요청 문서의
	// 이름은 그 레코드의 이름과 같은 값이고, 개명·정정은 회원 레코드에만 반영되므로 요청 문서
	// 쪽 사본은 남길수록 틀려지는 사본이다.
	//
	// 순서: 반드시 SaveMember **뒤**다(위 mem이 jr.Name·jr.Phone을 복사한다). 이 줄이 위로
	// 올라가면 빈 이름의 회원이 만들어진다.
	jr.Name = ""
	jr.Phone = ""
	if err := s.store.UpdateJoinRequest(ctx, jr); err != nil {
		return nil, err
	}
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{
		UID: jr.UID, Role: domain.RoleMember, CenterID: p.CenterID, MemberID: memberID,
	}); err != nil {
		return nil, err
	}
	return mem, nil
}

// ListJoinRequests — GET /v1/join/requests(어드민 가정 승인: 가입 요청 목록, v1.1 정합 패치). owner만
// (JoinApprove와 동일한 권한 경계 — 승인 대상 목록이므로).
//
// **pending만 돌려준다**(v2.27). 종전엔 필터가 없어 승인·거절된 요청이 큐에 그대로 남았고,
// 그래서 대표는 "이미 처리한 것"과 "처리할 것"을 눈으로 구별할 수 없었다 — 화면의 대기 건수가
// 사실이 아니었고, 처리 표시를 위해 한 번 더 누르는 것이 기본 동선이 됐다(그 두 번째 누름이
// JoinApprove의 멱등 가드에 걸려 409로 튀거나, 좀비 요청에서는 C-2 사고가 됐다).
//
// **감사 추적은 없어지지 않는다.** 필터는 여기(서비스 응답)에만 걸리고 스토어의 동사는
// 여전히 전체를 돌려준다 — 문서는 status만 바뀐 채 그대로 남아 있고, 어느 것도 삭제되지
// 않는다(삭제는 탈퇴 파기 DeleteJoinRequestsByUID뿐이다, v2.26). 이력이 필요해지면 이
// 자리에 status 쿼리 파라미터를 여는 것이 다음 단계다 — 지금 열지 않는 이유는 그것을 읽을
// 화면이 없어서다(어드민에 이력 뷰가 없다).
//
// 필터를 **스토어가 아니라 여기서** 하는 이유: Firestore에서 `Where(center_id)`에
// `Where(status)`를 더하면 복합 인덱스가 필요해지고, 인덱스 없이 배포되면 프로덕션에서만
// 500이 난다(Memory 구현으로는 보이지 않는다). 큐 규모가 센터당 수십 건이라 서버 필터의
// 비용이 그 위험보다 싸다 — ListMembers의 trainerID/q 필터와 같은 판단이다.
func (s *Service) ListJoinRequests(ctx context.Context, p Principal) ([]store.JoinRequest, error) {
	if !p.IsOwner() {
		return nil, ErrForbidden
	}
	list, err := s.store.ListJoinRequests(ctx, p.CenterID)
	if err != nil {
		return nil, err
	}
	out := make([]store.JoinRequest, 0, len(list))
	for _, jr := range list {
		if jr.Status == store.JoinPending {
			out = append(out, jr)
		}
	}
	return out, nil
}

// JoinReject — POST /v1/join/reject {request_id}(owner 전용, v2.27). 대표가 큐를 줄이는
// 유일한 수단이다.
//
// 왜 지금까지 없었나: store.JoinRejected 상수는 v1.2부터 있었지만 **프로덕션 코드에서 한 번도
// 대입되지 않았다**(유일한 사용처가 스토어 적합성 테스트였다). 그래서 처리할 수 없는 요청
// — 장난·오입력·이미 데스크에서 다른 방식으로 등록된 사람 — 이 큐에 영원히 남았고, 대표가
// 그것을 치우는 방법은 승인(=빈 회원 레코드 생성)뿐이었다. C-2 사고의 실제 동기가 이것이다.
//
// **이름·전화번호를 비운다.** P53(v2.26)이 탈퇴 파기에서 익명화를 기각한 근거는 "남은 것에
// 쓸모가 없을 때"였는데(껍데기만 남는다), 여기서는 남은 `{uid, center_id, status, created_at}`에
// 쓸모가 생긴다 — 신청자에게 **결론을 전달한다**(GET /v1/me의 join_request가 rejected를
// 읽는다). 그래서 같은 문서를 한쪽에선 지우고 한쪽에선 비우는 것이 일관된 판단이다.
//
// **문서를 통째로 지우지는 않는다.** 지우면 신청자 화면은 "요청한 적 없음"으로 되돌아가고,
// 그 사람은 "왜 아직도 승인이 안 되지"라며 다시 요청한다 — 끊을 수 없는 재요청 루프가 생기고
// A-2의 409도 그것을 막지 못한다(pending이 없으니 통과한다). 거절은 결론이므로 남아야 한다.
//
// 가드는 JoinApprove와 **같은 두 겹**(owner + 센터 대조)이다. 큐를 줄이는 것도 승인과 같은
// 무게의 결정이고, 남의 센터 요청을 거절하는 것 역시 남의 큐를 조작하는 일이다.
func (s *Service) JoinReject(ctx context.Context, p Principal, requestID string) (*store.JoinRequest, error) {
	if !p.IsOwner() {
		return nil, ErrForbidden
	}
	jr, err := s.store.GetJoinRequest(ctx, requestID)
	if err != nil {
		return nil, err
	}
	if jr.CenterID != p.CenterID {
		return nil, ErrForbidden
	}
	// JoinApprove와 같은 멱등 가드. 승인된 요청을 뒤늦게 거절로 덮으면 회원 레코드는 이미
	// 만들어졌는데 큐에는 "거절됨"이 남아 두 기록이 서로 다른 말을 한다.
	if jr.Status != store.JoinPending {
		return nil, errors.Join(ErrConflict, errors.New("이미 처리된 가입 요청이에요"))
	}
	jr.Status = store.JoinRejected
	jr.Name = ""  // 처리 목적이 끝난 개인정보 — 결론 전달에 이름은 필요 없다
	jr.Phone = "" // 같은 이유. 여기 남으면 승인 경로가 없는데도 번호만 잔류한다
	if err := s.store.UpdateJoinRequest(ctx, jr); err != nil {
		return nil, err
	}
	return jr, nil
}

// ---- 회원 ----

// MemberWithPasses — GET /v1/members 응답 전용 임베드 타입(v1.1 정합 패치: "GET /v1/members
// 응답에 passes:[] 임베드"). domain.Member를 승격(embed)해 JSON에는 회원 필드 옆에 passes가 나란히
// 붙는다. Member 엔티티 자체(POST/PUT 응답·가입 매칭 등)는 이 필드가 없는 계약 원본 그대로 유지한다.
type MemberWithPasses struct {
	domain.Member
	Passes []domain.Pass `json:"passes"`
}

// ListMembers — 역할 스코프 자동: 트레이너는 담당만(계약 "GET /v1/members?trainer=&q="), 회원은
// 본인 1건만(회원 앱의 "내 프로필" 조회 — 계약 "역할 스코프 자동"의 member 해석, v1.2 정합 패치).
// 각 회원에 passes[]를 임베드해 어드민 회원 목록에서 N+1 조회를 피한다(v1.1 정합 패치).
func (s *Service) ListMembers(ctx context.Context, p Principal, trainerQuery, q string) ([]MemberWithPasses, error) {
	if p.IsMember() {
		if p.MemberID == "" {
			return nil, ErrForbidden // 가입 매칭 전 — 스코프할 본인 레코드가 없다
		}
		mem, err := s.store.GetMember(ctx, p.CenterID, p.MemberID)
		if err != nil {
			return nil, err
		}
		passes, err := s.store.ListPassesByMember(ctx, p.CenterID, mem.ID)
		if err != nil {
			return nil, err
		}
		passes, err = s.hydratePassesRemaining(ctx, p.CenterID, passes)
		if err != nil {
			return nil, err
		}
		// 응답 사본에만 구체화(v2.10) — 앱은 이 경로로 자기 포즈 시퀀스를 받는다.
		// 저장 객체가 아니라 여기서 채우는 이유는 Member.BodyPoses 주석 참고.
		mem.BodyPoses = mem.EffectiveBodyPoses()
		normalizeMemberWire(mem) // 읽기 정규화(v2.28) — 이미 null로 굳은 문서도 배열로 나간다
		return []MemberWithPasses{{Member: *mem, Passes: passes}}, nil
	}
	trainerID := trainerQuery
	if p.IsTrainer() {
		trainerID = p.UID
	}
	members, err := s.store.ListMembers(ctx, p.CenterID, trainerID, q)
	if err != nil {
		return nil, err
	}
	// 회원별 패스·원장 조회는 **동시에**(v2.38, P74). 종전엔 회원 N명 × (패스 1 + 원장 K)회 왕복이
	// 전부 직렬이라 어드민 회원 목록(가장 먼저 여는 화면)이 회원 수에 정비례해 느려졌다 — 위
	// 주석의 "N+1 회피"는 클라이언트의 N+1을 서버 안으로 옮긴 것이었다. 결과 순서는 그대로
	// (인덱스로 제자리에 쓴다), 첫 오류가 곧 전체 오류(종전 계약 유지).
	out := make([]MemberWithPasses, len(members))
	err = forEachParallel(ctx, len(members), memberFanOut, func(ctx context.Context, i int) error {
		mem := members[i]
		passes, err := s.store.ListPassesByMember(ctx, p.CenterID, mem.ID)
		if err != nil {
			return err
		}
		passes, err = s.hydratePassesRemaining(ctx, p.CenterID, passes)
		if err != nil {
			return err
		}
		mem.BodyPoses = mem.EffectiveBodyPoses() // 응답 사본에만(v2.10) — 어드민 포즈 편집기의 초기값
		normalizeMemberWire(&mem)                // 읽기 정규화(v2.28) — 회원 목록은 어드민이 가장 먼저 여는 화면이다
		out[i] = MemberWithPasses{Member: mem, Passes: passes}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// 동시성 상한(v2.38, P74). Firestore 클라이언트는 고루틴 안전하지만 상한이 없으면 회원 수만큼
// 스트림을 연다. 회원 8 × 패스 4 = 최대 32 동시 읽기 — 단일 인스턴스 기준 충분히 보수적이다.
const (
	memberFanOut = 8
	passFanOut   = 4
)

// memberScopeID — 목록 조회의 member= 스코프 결정(v1.1 목록 엔드포인트 공용). member 역할은
// 항상 본인으로 강제하되, 가입 매칭 전(MemberID가 빈 값)이면 403 — 빈 문자열이 필터를 지워
// 센터 전체가 노출되는 스코프 우회를 차단한다(v1.2 보안 수정).
func memberScopeID(p Principal, memberQuery string) (string, error) {
	if !p.IsMember() {
		return memberQuery, nil
	}
	if p.MemberID == "" {
		return "", ErrForbidden
	}
	return p.MemberID, nil
}

// checkMemberScope — owner=전체, trainer=담당만, member=본인만(P13·P37).
func (s *Service) checkMemberScope(p Principal, mem domain.Member) error {
	switch {
	case p.IsOwner():
		return nil
	case p.IsTrainer():
		if mem.TrainerID != p.UID {
			return ErrForbidden
		}
		return nil
	case p.IsMember():
		if mem.ID != p.MemberID {
			return ErrForbidden
		}
		return nil
	}
	return ErrForbidden
}

// CreateMember — POST /v1/members(스태프 전용). 트레이너는 담당을 본인으로 강제.
// 데스크에서 동의를 받고 등록하는 경우 signed_at을 서버가 기록한다(P8 — 클라이언트가 시각을 안 보냄).
//
// 계약 v2.1: trainer_id는 발급(POST /v1/passes)과 **같은 검증**을 받는다 — 퇴사 선행 조건 ①이
// "담당 회원 없음"이라, 여기가 열려 있으면 퇴사자에게 회원 한 명만 붙여도 차단 조건이 되살아난다
// (발급보다 싸고 앞선 우회로다). 강제 대입 뒤에 검사한다 — 검사 대상은 요청 값이 아니라
// **실제로 저장될 값**이어야 한다.
func (s *Service) CreateMember(ctx context.Context, p Principal, mem *domain.Member) (*domain.Member, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	if p.IsTrainer() {
		mem.TrainerID = p.UID // 신규 생성 시 담당을 본인으로 강제
	}
	if err := s.checkAssignableTrainer(ctx, p.CenterID, mem.TrainerID); err != nil {
		return nil, err
	}
	mem.ID = ""
	if mem.Flags == nil {
		mem.Flags = []domain.MemberFlag{} // 직렬화 계약: 항상 배열
	}
	// 정규화 → 검증(v2.36). 순서가 규칙이다(UpdateCenterIdentity·UpdateCenterBusiness와 같은
	// 이유): 붙여넣기로 딸려 온 공백이나 "010-1234-5678" 하이픈 때문에 400이 나면 데스크는
	// 무엇이 틀렸는지 볼 수 없다. 검증 대상은 요청 값이 아니라 **실제로 저장될 값**이다.
	mem.Normalize()
	if err := mem.Validate(); err != nil {
		return nil, errors.Join(errBadRequest, err)
	}
	// **같은 번호 중복 등록은 막지 않는다** — 검수에서 "승인 경로(JoinApprove, v2.34)에는 중복
	// 번호 409가 있는데 데스크 손등록에는 없다"는 비대칭이 결함으로 지적됐고, 실제로 409를
	// 넣어 봤다가 되돌렸다(P71). 그 비대칭은 누락이 아니라 **설계**다:
	//
	//   부모 번호로 자녀 둘을 등록하는 건 실제로 흔하다(store/memory.go betterPhoneMatch 주석).
	//   그래서 이 저장소는 같은 번호 회원 여럿을 **지원하고**, 그 상태에서 매칭이 흔들리지 않도록
	//   전순서 규칙(미연결 우선 → ID 오름차순)까지 두 스토어가 공유한다
	//   (TestJoinMatchIsDeterministicForSharedPhone). 데스크에서 막으면 가족 등록이 불가능해진다.
	//
	// 승인 경로에만 409가 있는 이유는 거기서만 **앱 계정이 레코드에 붙기** 때문이다: 중복이
	// 생기면 앱 연결은 한쪽에, 회원권·기록은 다른 쪽에 남는다. 데스크 등록에는 그 결합이 없다.
	// 오등록(같은 사람을 두 번)은 화면이 경고할 문제이지 서버가 거절할 문제가 아니다.
	// 체형 포즈 시퀀스(v2.10): []는 "센터 기본 사용"(nil)으로 정규화하고, 커스텀을 보냈을 때만
	// 검증한다. **nil이 의미를 가지므로** Flags식 nil→[] 정규화를 이 필드엔 하지 않는다
	// (도메인 필드 주석 참조 — 저장 상태는 nil-또는-검증된-커스텀 둘뿐).
	mem.BodyPoses = domain.NormalizeBodyPoses(mem.BodyPoses)
	if mem.BodyPoses != nil {
		if err := domain.ValidateBodyPoses(mem.BodyPoses); err != nil {
			return nil, err
		}
	}
	// 동의 시각은 **서버가 기록한다**(v2.37, P73 — UpdateMember의 v1.2 불변식을 등록 경로에도).
	// 종전엔 `SignedAt == nil`일 때만 채워서, 어드민이 항상 실어 보내는 데스크 PC 시계값이 그대로
	// 저장됐다 — 민감정보 동의의 "언제"라는 준법 기록이 PC 시계 오차만큼 틀렸다. 클라이언트가
	// 값을 실었으면 "지금 동의했다"는 뜻만 취하고 시각은 서버 것으로 바꾼다. 신규 레코드에 철회
	// 시각이 있을 수는 없으므로 revoked_at은 비운다.
	mem.Consent.RevokedAt = nil
	switch {
	case !mem.Consent.General && !mem.Consent.Sensitive:
		mem.Consent.SignedAt = nil // 동의가 하나도 없는데 서명 시각만 남는 모순을 막는다
	case mem.Consent.Sensitive || mem.Consent.SignedAt != nil:
		now := time.Now().UTC()
		mem.Consent.SignedAt = &now
	}
	id, err := s.store.SaveMember(ctx, p.CenterID, mem)
	if err != nil {
		return nil, err
	}
	mem.ID = id
	// 응답 구체화(v2.10): 클라이언트가 기본 상수를 몰라도 되도록 실효 시퀀스를 채운다.
	// 반드시 SaveMember **뒤** — 저장값은 nil-또는-커스텀이어야 한다(기본이 커스텀으로 굳는 사고 방지).
	mem.BodyPoses = mem.EffectiveBodyPoses()
	return mem, nil
}

// memberSelfUpdate — 회원 본인 PUT 바디(consent만 허용 — 이름·담당·플래그·상태는 스태프 전용,
// 회원이 자기 부상 플래그를 지워 Home Work 제외를 우회하는 류의 셀프 권한 상승을 차단한다).
type memberSelfUpdate struct {
	Consent *struct {
		General   *bool `json:"general"`
		Sensitive *bool `json:"sensitive"`
	} `json:"consent"`
}

// normalizeConsentTransition — sensitive 동의 전이 시각을 서버가 기록한다(P8: 철회 즉시 잠금).
// false→true: signed_at 갱신 + 과거 철회 흔적 해제. true→false: revoked_at 기록.
func normalizeConsentTransition(c *domain.Consent, prevSensitive bool) {
	now := time.Now().UTC()
	switch {
	case c.Sensitive && !prevSensitive:
		c.SignedAt = &now
		c.RevokedAt = nil
	case !c.Sensitive && prevSensitive:
		c.RevokedAt = &now
	}
}

// UpdateMember — PUT /v1/members/{id}. **머지 시맨틱**: 보낸 필드만 갱신한다(기존 레코드 위에
// 언마샬 — 부분 PUT이 app_linked/last_visit_at 같은 서버 관리 필드를 지우지 않도록, v1.2 정합 패치).
// member 역할은 본인 레코드의 consent만 갱신할 수 있다(P8 — 회원 앱 동의 관리 시트).
func (s *Service) UpdateMember(ctx context.Context, p Principal, id string, body []byte) (*domain.Member, error) {
	existing, err := s.store.GetMember(ctx, p.CenterID, id)
	if err != nil {
		return nil, err
	}
	// 탈퇴 레코드는 **되살릴 수 없다**(v2.11). 이 가드가 없으면 스태프 PUT 한 번으로 이름·번호가
	// 다시 박혀 파기가 조용히 무효화되고, status를 active로 되돌리면 탈퇴 사실 자체가 사라진다
	// (탈퇴는 되돌릴 API가 없는 종단 상태다 — 복직 경로가 있는 스태프 퇴사와 다르다).
	// 앞에 두는 이유: 회원 self 경로(consent 수정)도 함께 막아야 한다.
	if err := guardMemberNotWithdrawn(*existing, "정보를 수정할 수 없어요"); err != nil {
		return nil, err
	}
	if p.IsMember() {
		if p.MemberID == "" || existing.ID != p.MemberID {
			return nil, ErrForbidden
		}
		var req memberSelfUpdate
		if err := strictUnmarshal(body, &req); err != nil {
			return nil, err
		}
		if req.Consent == nil {
			return nil, errors.Join(errBadRequest, errors.New("회원 본인은 consent만 수정할 수 있어요"))
		}
		if req.Consent.General != nil {
			existing.Consent.General = *req.Consent.General
		}
		if req.Consent.Sensitive != nil {
			prev := existing.Consent.Sensitive
			existing.Consent.Sensitive = *req.Consent.Sensitive
			normalizeConsentTransition(&existing.Consent, prev)
		}
	} else {
		if p.IsTrainer() && existing.TrainerID != p.UID {
			return nil, ErrForbidden
		}
		prevSensitive := existing.Consent.Sensitive
		prevSignedAt, prevRevokedAt := existing.Consent.SignedAt, existing.Consent.RevokedAt
		prevTrainerID := existing.TrainerID
		// Memory 스토어의 GetMember는 얕은 복사라 slice 백킹 배열을 스토어 원본과 공유한다.
		// strictUnmarshal이 기존 용량을 재사용해 그 자리를 덮어쓰면, 검증 실패(400)로 저장을
		// 안 해도 스토어 원본 요소가 오염된다(Firestore는 문서를 매번 새로 언마샬해서 무관).
		// 머지 전에 소유권을 끊는다(v2.10 — body_poses 검증 도입으로 실패 경로가 생기며 표면화).
		existing.Flags = slices.Clone(existing.Flags)
		existing.BodyPoses = slices.Clone(existing.BodyPoses)
		if err := strictUnmarshal(body, existing); err != nil {
			return nil, err
		}
		existing.ID = id // 바디에 다른 id가 섞여 와도 경로가 우선
		// 트레이너 호출이면 담당을 본인으로 **강제**한다(v2.0 — CreateMember와 같은 규칙).
		// 종전엔 위 권한 검사 뒤 바디의 trainer_id가 그대로 덮어써도 재검증이 없어, 트레이너가
		// 자기 담당 회원을 임의 uid로 넘길 수 있었다(넘기고 나면 본인도 못 보는 회원이 된다).
		// 담당 이관은 owner 전용 전담 엔드포인트로만 이뤄져야 감사가 가능하다.
		if p.IsTrainer() {
			existing.TrainerID = p.UID
		}
		// 계약 v2.1: 담당이 **바뀔 때만** 발급과 같은 검증을 건다(CreateMember·CreatePass 공용 함수).
		// "바뀔 때만"인 이유: 머지 PUT이라 이름만 고치는 요청에도 기존 trainer_id가 그대로 실려
		// 온다. 무조건 검사하면 이미 어긋난 레코드(예: 이관 누락으로 남은 퇴사자 담당)의 이름조차
		// 못 고치게 되고, 정작 그 상태를 푸는 유일한 수단이 담당 변경 PUT이다. 새로 붙이는 값만
		// 막으면 루프는 닫히고(붙이기가 곧 변경이다) 복구 경로는 열려 있다.
		if existing.TrainerID != prevTrainerID {
			if err := s.checkAssignableTrainer(ctx, p.CenterID, existing.TrainerID); err != nil {
				return nil, err
			}
		}
		// 전이 시각은 서버가 기록한다(v1.2) — 클라이언트가 보낸 signed_at/revoked_at은 무시하고
		// 서버 보관값 위에 전이 규칙만 적용(스태프 경로도 member 경로와 동일 보장).
		existing.Consent.SignedAt, existing.Consent.RevokedAt = prevSignedAt, prevRevokedAt
		normalizeConsentTransition(&existing.Consent, prevSensitive)
		// 체형 포즈(v2.10, 스태프 전용): 배열 전송=교체, null/[]=기본으로 초기화([]→nil 정규화),
		// 생략=유지(머지가 기존 값을 보존 — 필드를 모르는 기존 어드민 PUT이 커스텀을 못 지운다).
		// 회원 self 경로는 memberSelfUpdate 구조체라 body_poses를 실으면 위에서 이미 400이다.
		existing.BodyPoses = domain.NormalizeBodyPoses(existing.BodyPoses)
		if existing.BodyPoses != nil {
			if err := domain.ValidateBodyPoses(existing.BodyPoses); err != nil {
				return nil, err
			}
		}
		// 정규화 → 검증(v2.36, CreateMember와 같은 규칙). 여기가 없으면 등록은 막고 수정은
		// 여는 셈이라, PUT 한 번으로 이름·번호를 지워 그 회원의 앱 연결을 끊을 수 있었다.
		//
		// **status 화이트리스트가 특히 중요하다**: 이 경로는 body를 domain.Member에 그대로
		// 언마샬하므로 `{"status":"withdrawn"}` 한 줄이면 그 회원이 수정·발급·계약이 전부 막힌
		// 종단 상태로 굳는데(guardMemberNotWithdrawn), 되돌릴 API가 없고 **실제 파기(번호
		// 가명화·계정 삭제)는 일어나지 않아** 개인정보는 그대로 남는 가짜 탈퇴가 된다.
		// 진짜 탈퇴 경로는 회원 본인의 DELETE /v1/me 하나뿐이다(v2.11).
		existing.Normalize()
		if err := existing.Validate(); err != nil {
			return nil, errors.Join(errBadRequest, err)
		}
	}
	// 쓰기 정규화(v2.28) — **SaveMember 앞**이라 PUT 한 번이 null 문서를 고친다. 머지 PUT은
	// 기존 문서 위에 언마샬하므로 flags를 안 실은 요청이면 문서의 null이 그대로 남고(위
	// slices.Clone(nil)도 nil이다), CreateMember의 정규화는 신규 생성만 지난다 — 이미 null인
	// 문서를 되살릴 쓰기 경로가 없었다(와이어 감사 L-3). member self 경로(consent만)도 포함.
	normalizeMemberWire(existing)
	if _, err := s.store.SaveMember(ctx, p.CenterID, existing); err != nil {
		return nil, err
	}
	// 응답 구체화(v2.10) — SaveMember 뒤에만(CreateMember와 같은 이유). member self 경로 포함.
	existing.BodyPoses = existing.EffectiveBodyPoses()
	return existing, nil
}

func (s *Service) MemberLedger(ctx context.Context, p Principal, memberID, passID string) ([]domain.Ledger, error) {
	mem, err := s.store.GetMember(ctx, p.CenterID, memberID)
	if err != nil {
		return nil, err
	}
	if err := s.checkMemberScope(p, *mem); err != nil {
		return nil, err
	}
	return s.store.ListLedger(ctx, p.CenterID, memberID, passID)
}

// ---- 회원권 ----

// checkTrainerOwnsPass — owner=전체, trainer=본인 소속 패스만(스태프 전용 액션 — 계약 생성 등).
func (s *Service) checkTrainerOwnsPass(p Principal, pass domain.Pass) error {
	if p.IsOwner() {
		return nil
	}
	if p.IsTrainer() && pass.TrainerID == p.UID {
		return nil
	}
	return ErrForbidden
}

// checkPassScope — 패스 단건 액션 권한: owner=전체, trainer=본인 소속, member=본인 패스.
// v1.2 정합 패치: 홀딩 신청·조기 복귀·환불 계산기는 회원 앱 셀프서비스 대상이다(P46 단순화 —
// 계약에 "신청→승인 큐" 엔드포인트가 없어, member는 정책 상한(ValidateNewHold) 안에서 직접 실행).
func (s *Service) checkPassScope(p Principal, pass domain.Pass) error {
	switch {
	case p.IsOwner():
		return nil
	case p.IsTrainer():
		if pass.TrainerID == p.UID {
			return nil
		}
	case p.IsMember():
		if p.MemberID != "" && pass.MemberID == p.MemberID {
			return nil
		}
	}
	return ErrForbidden
}

// hydratePassRemaining — 원장 합산으로 Remaining을 채우고, Status를 오늘 날짜로 확정한다
// (P3 불변식2 — 필드 직접수정 금지).
//
// 두 값 모두 **파생값**이다: Remaining은 원장 합산의 캐시, Status는 유효기간의 함수다
// (domain.Pass.EffectiveStatus 주석 — expired·scheduled를 대입하는 코드가 프로덕션에
// 한 줄도 없어 만료된 회원권이 영원히 "이용 중"으로 보이던 결함).
//
// **응답 사본에만 쓴다.** 여기서 채운 값이 저장으로 돌아가면 홀딩이 유효기간을 늘렸을 때
// 굳어버린 expired가 되살아나지 않는다.
func (s *Service) hydratePassRemaining(ctx context.Context, centerID string, pass *domain.Pass) error {
	entries, err := s.store.ListLedger(ctx, centerID, pass.MemberID, pass.ID)
	if err != nil {
		return err
	}
	pass.Remaining = domain.Sum(entries)
	pass.Status = pass.EffectiveStatus(today())
	normalizePassWire(pass) // 읽기 정규화(v2.28) — 목록(GET /v1/passes · members[].passes)이 전부 여기를 지난다
	return nil
}

// stampPassStatus — 응답으로 나가는 한 건의 Status를 오늘 날짜로 확정한다.
//
// 생성·홀딩·재개·환불 응답은 원장을 다시 읽을 필요가 없어 hydratePassRemaining을 거치지
// 않는다. 그래도 Status는 찍어야 한다 — 안 찍으면 **같은 회원권이 방금 만든 화면에서는
// "이용 중", 목록을 새로고침하면 "예정"** 으로 보인다(valid_from이 미래인 발급).
func stampPassStatus(pass *domain.Pass) {
	if pass == nil {
		return
	}
	pass.Status = pass.EffectiveStatus(today())
	normalizePassWire(pass) // 읽기 정규화(v2.28) — 단건 응답(발급·홀딩·재개·환불)은 hydrate를 안 지난다
}

// hydratePassesRemaining — 리스트 전체에 hydratePassRemaining을 적용한다(GET /v1/passes, GET
// /v1/members의 임베드 passes[]에서 공용으로 사용, v1.1 정합 패치).
func (s *Service) hydratePassesRemaining(ctx context.Context, centerID string, passes []domain.Pass) ([]domain.Pass, error) {
	// 패스마다 원장을 읽는다 — 서로 독립이라 동시에(v2.38, P74). 각 고루틴은 자기 인덱스의 원소만
	// 만지므로 슬라이스 공유가 안전하다.
	err := forEachParallel(ctx, len(passes), passFanOut, func(ctx context.Context, i int) error {
		return s.hydratePassRemaining(ctx, centerID, &passes[i])
	})
	if err != nil {
		return nil, err
	}
	return passes, nil
}

type PassCreateRequest struct {
	MemberID      string `json:"member_id"`
	TrainerID     string `json:"trainer_id"`
	Product       string `json:"product"`
	PaidAmount    int    `json:"paid_amount"`
	TotalSessions int    `json:"total_sessions"`
	ValidFrom     string `json:"valid_from"`
	ValidUntil    string `json:"valid_until"`
}

// checkAssignableTrainer — 담당으로 **새로 박히는** 코치의 실존·재직 검사(계약 v2.1).
// 담당 uid가 처음 들어오는 세 진입점이 이 함수 하나를 공유한다:
// POST /v1/passes(발급) · POST /v1/members(등록) · PUT /v1/members/{id}(담당 변경).
//
// 세 곳이 같은 함수를 써야 하는 이유는 퇴사 선행 조건이 **셋 다**를 보기 때문이다: 조건 ①은
// "담당 회원 없음", ②는 "담당 active 패스 없음"이라 한 곳만 막으면 남은 쪽이 더 싼 우회로가
// 된다(회원 생성은 발급보다 앞서고 값도 안 든다). 규칙이 갈리면 어느 문이 잠겼는지를 사람도
// 코드도 알 수 없게 된다.
//
// v2.0이 예약(CreateBooking)과 고정 스케줄(CreateRecurring)에만 inactive 거부를 넣어 **발급
// 경로가 열려 있었다**: 퇴사자 담당으로 회원권을 새로 끊으면 그 즉시 그 사람의 퇴사 선행 조건
// (active 패스)이 다시 생겨 이관→퇴사 여정이 무한 반복된다. 거부 문구는 예약 쪽과 같은
// 문장을 쓴다 — 같은 상황에 대해 3계층이 다른 말을 하면 안 된다.
//
// 예약 쪽과 **다른 점 하나**: 미존재도 거부한다(계약 v2.1). 예약은 "스태프 레코드가 아직 없는
// 미시딩 dev"를 통과시키려고 `err == nil`일 때만 판정하지만, 발급은 담당이 처음 박히는 지점이라
// 여기서 통과한 오타가 이후 예약·통계·정산의 원천이 된다. 실존 검증을 뺐던 근거("스태프 생성
// API가 없는 v1 dev 흐름", CreateWorkoutLog 주석)는 v1.8의 POST /v1/staff로 이미 해소됐다 —
// 이제 dev도 스태프를 먼저 만들 수 있고, DEV_SEED는 스태프를 패스보다 먼저 심는다.
//
// 빈 trainer_id는 통과시킨다: ""는 오타가 아니라 **미배정**이라는 1급 상태다(TransferStaff의
// to_uid="" 회수가 만들고, domain.CanBook이 ""를 명시적으로 예외 처리한다). 담당 없는 패스는
// 누구의 퇴사도 막지 않아 이 규칙이 닫으려는 루프와 무관하다. ""를 여기서 먼저 걸러 스토어까지
// 내려보내지 않는 이유는 성능이 아니라 **의미**다: 미배정은 "찾다 실패한 것"이 아니라 정상 상태라
// 조회 자체가 불필요하다(스토어도 빈 ID를 ErrNotFound로 정규화하지만 — store/errors.go의
// checkDocID — 그건 마지막 방어선이고, 이 자리의 판단은 그 결과에 기대지 않는다).
func (s *Service) checkAssignableTrainer(ctx context.Context, centerID, trainerID string) error {
	if trainerID == "" {
		return nil
	}
	st, err := s.store.GetStaff(ctx, centerID, trainerID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			// 404(찾을 수 없음)가 아니라 400이다 — 없는 것은 요청 대상(pass)이 아니라 그 안의
			// 필드 값이고, 계약 v2.1이 이 자리를 400으로 못박는다.
			return errors.Join(errBadRequest, errors.New("등록되지 않은 코치예요"))
		}
		return err
	}
	if !st.IsActive() {
		return errors.Join(errBadRequest, errors.New("퇴사 처리된 코치예요 — 담당을 먼저 이관해주세요"))
	}
	return nil
}

// CreatePass — 발급(+원장 issue, 계약 "POST /v1/passes 발급(+원장 issue)"). v1.1 정합 패치:
// 발급과 동시에 Contract를 status=sent로 자동 생성한다(하단 확정 플로우 "추가 계약 = 새 Pass
// 발급 → Contract 자동 생성(sent) → Payment 기록").
func (s *Service) CreatePass(ctx context.Context, p Principal, req PassCreateRequest) (*domain.Pass, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	if p.IsTrainer() && req.TrainerID != p.UID {
		return nil, ErrForbidden
	}
	// 회원 실존 확인 — 빈/오타 member_id로 고아 패스·계약이 생기는 것을 차단(2R LOW).
	mem, err := s.store.GetMember(ctx, p.CenterID, req.MemberID)
	if err != nil {
		return nil, err
	}
	// 탈퇴 회원에게는 발급하지 않는다(v2.11). 그 회원은 앱에 들어올 수 없어 쓸 수 없는
	// 회원권이 되고, 계약·원장까지 함께 생겨 5년 보존 대상만 늘린다.
	if err := guardMemberNotWithdrawn(*mem, "회원권을 발급할 수 없어요"); err != nil {
		return nil, err
	}
	if err := s.checkAssignableTrainer(ctx, p.CenterID, req.TrainerID); err != nil {
		return nil, err
	}
	// 유효기간은 필수다(P09 실플로우 점검에서 발견). 비워두면 **영원히 예약할 수 없는 회원권**이
	// 조용히 만들어진다 — 예약 검사가 문자열 비교(`slotDate > pass.ValidUntil`)라 ValidUntil이 ""면
	// 어떤 날짜든 "유효기간 밖"이 된다. 게다가 만료임박 KPI·홀딩 연장·월별 매출 집계가 전부 이
	// 두 값을 파싱하므로 빈 값은 그 계산들도 함께 망가뜨린다.
	// 기본값으로 채우지 않는 이유: 회원권 기간은 상품마다 다른 영업 조건이라 서버가 추측할 수 없다
	// (정책에도 기본 기간 항목이 없다). 어드민은 이미 두 값을 항상 보낸다.
	if err := domain.ValidatePassPeriod(req.ValidFrom, req.ValidUntil); err != nil {
		return nil, err
	}
	// 금액·횟수 검증(v2.4, P12 감사 H5). CreatePayment는 total<=0을 막는데 **발급만 열려 있었다** —
	// 돈이 들어오는 문보다 회원권이 만들어지는 문이 헐거우면 안 된다.
	// total_sessions=0: 잔여 0으로 시작해 영원히 예약할 수 없는 회원권이 조용히 생긴다(빈
	// 유효기간과 같은 증상 — P09). 음수: {"delta":-5,"reason":"issue"}가 원장에 그대로 박힌다.
	// 원장은 append-only(P3)라 잘못 적재된 발급 이벤트를 지울 수단이 없고, 그 패스는 refund-quote
	// 마저 400이라 정리도 안 된다 — 애초에 들어오지 못하게 막는 것이 유일한 방어다.
	// paid_amount 0은 허용한다: 무료 체험권·서비스 제공은 실제 영업 조건이고, 회차와 달리
	// 어떤 계산도 망가뜨리지 않는다(환불 견적 0원, 매출 0 가산). 음수만 거부한다.
	if req.TotalSessions <= 0 {
		return nil, errors.Join(errBadRequest, errors.New("회원권 횟수는 1회 이상이어야 해요"))
	}
	if req.PaidAmount < 0 {
		return nil, errors.Join(errBadRequest, errors.New("결제 금액은 0원 이상이어야 해요"))
	}
	pass := &domain.Pass{
		MemberID: req.MemberID, TrainerID: req.TrainerID, Product: req.Product,
		PaidAmount: req.PaidAmount, TotalSessions: req.TotalSessions,
		// Remaining은 원장이 진실(P3)이지만, 저장 스냅샷도 발급 시점 값으로 초기화해 둔다 —
		// 저장 전에 채우지 않으면 저장본이 0으로 남아 GetPass 직독 경로가 전부 "잔여 없음"이 된다.
		Remaining: req.TotalSessions,
		ValidFrom: req.ValidFrom, ValidUntil: req.ValidUntil, Status: domain.PassStatusActive,
		Holds: []domain.Hold{}, // nil이면 JSON null — 어드민의 .some/.length 크래시 방지(직렬화 계약: 항상 배열)
	}
	// 발급 3단은 **한 트랜잭션**이다(P13 C3). 쪼개져 있을 때 실측된 사고: 계약 생성만 실패하는
	// 상황에서 발급 3회 시도가 HTTP 500 × 3을 돌려주면서 실제로는 패스 3개(각 20회)와 원장 issue
	// 3건을 남겼다 — 대표는 "실패했다"고 보는데 회원에겐 60회가 지급됐고, 패스 삭제 라우트도
	// 원장 정정 라우트도 없어 Firestore 직접 편집 말고는 복구 경로가 없다.
	entry := &domain.Ledger{
		MemberID: pass.MemberID, Delta: pass.TotalSessions,
		Reason: domain.ReasonIssue, By: p.UID, At: time.Now().UTC(),
	}
	contract, err := s.buildContractForPass(ctx, p, pass)
	if err != nil {
		return nil, err
	}
	if err := s.store.IssuePass(ctx, p.CenterID, pass, entry, contract); err != nil {
		return nil, err
	}
	stampPassStatus(pass) // 목록/단건 응답과 같은 값이어야 한다(hydratePassRemaining 주석)
	return pass, nil
}

type HoldRequest struct {
	From   string `json:"from"`
	To     string `json:"to"`
	Reason string `json:"reason"`
}

// HoldPass — 홀딩(일시정지, P46): holds에 append + 유효기간 자동 연장 + 원장 hold 이벤트.
// member 본인도 실행 가능하되 정책 상한(기본 최대 2회·총 30일)을 강제한다. 스태프는 상한을
// 건너뛴다(데스크 예외 처리 — 장기 부상 등).
//
// 세 변경(holds append · valid_until 연장 · 원장 hold)이 **한 트랜잭션**이다(P13 H2·H3).
// 쪼개져 있을 때 실측된 사고 두 가지:
//   - 동시 홀딩 5건이 전부 200인데 저장된 holds는 1건, 유효기간은 5일만 연장, 원장 hold는 5건.
//     UpdatePass가 문서 통째 교체라 read-modify-write가 서로를 조용히 덮었다. "원장이 진실"이라는
//     약속이 오히려 **양쪽 말이 다 맞는** 상태를 만든다. 정책 상한(최대 2회)도 pass.Holds 기준이라
//     동시 신청으로 우회됐다 — 그래서 상한 검사도 트랜잭션 안으로 내렸다.
//   - UpdatePass 성공 후 AppendLedger 실패 → 대표가 재시도 → 유효기간이 한 번 더 늘어남.
func (s *Service) HoldPass(ctx context.Context, p Principal, passID string, req HoldRequest) (*domain.Pass, error) {
	pass, err := s.store.GetPass(ctx, p.CenterID, passID)
	if err != nil {
		return nil, err
	}
	// 사전 가드(권한·상태)는 값싼 조기 거절용이다. 실제 판정은 아래 트랜잭션 안에서 한 번 더 한다.
	if err := s.checkPassScope(p, *pass); err != nil {
		return nil, err
	}
	h := domain.Hold{From: req.From, To: req.To, Reason: req.Reason}
	// 정책은 트랜잭션 **밖에서** 미리 읽는다 — mutate 안에서 Store를 다시 부르면 안 된다
	// (Memory는 전역 락을 쥔 채라 교착, Firestore는 트랜잭션 밖 읽기가 된다).
	var policy *domain.Policy
	if p.IsMember() {
		policy, err = s.store.GetPolicy(ctx, p.CenterID)
		if err != nil {
			return nil, err
		}
	}
	today := today()
	updated, err := s.store.UpdatePassWithLedger(ctx, p.CenterID, passID,
		func(fresh *domain.Pass, entries []domain.Ledger) (*domain.Ledger, error) {
			if err := s.checkPassScope(p, *fresh); err != nil {
				return nil, err
			}
			if fresh.Status != domain.PassStatusActive {
				return nil, errors.Join(errBadRequest, errors.New("이용 가능한 상태의 패스만 일시정지할 수 있어요"))
			}
			// 멱등 가드(P13 H3): 완전히 같은 구간의 재신청은 재시도이지 새 홀딩이 아니다.
			// 스태프는 ValidateHoldWindow(겹침 금지)를 건너뛰므로 이 검사가 없으면 같은 from/to로
			// 3번 눌러 유효기간이 3번 늘어난다(실측). 겹침 일반은 스태프 예외를 유지하되
			// **완전 동일 구간**만 막는다 — 정당한 데스크 정정에는 같은 날짜 재입력이 없다.
			for _, ex := range fresh.Holds {
				if ex.From == h.From && ex.To == h.To {
					return nil, errors.Join(errBadRequest,
						errors.New("같은 기간으로 이미 일시정지돼 있어요(중복 신청)"))
				}
			}
			if policy != nil { // member — 시간축·정책 상한을 최신 holds 기준으로 재판정
				if err := domain.ValidateHoldWindow(fresh.Holds, h, today, fresh.ValidUntil); err != nil {
					return nil, errors.Join(errBadRequest, err)
				}
				if err := domain.ValidateNewHold(fresh.Holds, h, policy.MaxHoldsPerPass, policy.MaxHoldTotalDays); err != nil {
					return nil, errors.Join(errBadRequest, err)
				}
			}
			newUntil, _, err := domain.ApplyHold(fresh.ValidUntil, h)
			if err != nil {
				return nil, errors.Join(errBadRequest, err)
			}
			fresh.Holds = append(fresh.Holds, h)
			fresh.ValidUntil = newUntil
			fresh.Remaining = domain.Sum(entries) // 저장 스냅샷을 원장 합에 맞춘다(M3)
			return &domain.Ledger{
				MemberID: fresh.MemberID, Delta: 0, Reason: domain.ReasonHold, By: p.UID, At: time.Now().UTC(),
			}, nil
		})
	if err != nil {
		return nil, err
	}
	stampPassStatus(updated) // 목록/단건 응답과 같은 값이어야 한다(hydratePassRemaining 주석)
	return updated, nil
}

// ResumePass — 홀딩 조기 종료(P46): 미사용 일수만큼 유효기간을 되돌리고 원장 resume 이벤트.
// HoldPass와 같은 이유로 한 트랜잭션이다(동시 재개가 서로를 덮거나 원장만 남는 것 방지).
func (s *Service) ResumePass(ctx context.Context, p Principal, passID string) (*domain.Pass, error) {
	pass, err := s.store.GetPass(ctx, p.CenterID, passID)
	if err != nil {
		return nil, err
	}
	if err := s.checkPassScope(p, *pass); err != nil {
		return nil, err
	}
	today := today()
	updated, err := s.store.UpdatePassWithLedger(ctx, p.CenterID, passID,
		func(fresh *domain.Pass, entries []domain.Ledger) (*domain.Ledger, error) {
			if err := s.checkPassScope(p, *fresh); err != nil {
				return nil, err
			}
			if fresh.Status != domain.PassStatusActive {
				return nil, errors.Join(errBadRequest, errors.New("이용 가능한 상태의 패스만 재개할 수 있어요"))
			}
			updatedHolds, newUntil, err := domain.ResumeHold(fresh.Holds, fresh.ValidUntil, today)
			if err != nil {
				return nil, errors.Join(errBadRequest, err)
			}
			fresh.Holds = updatedHolds
			fresh.ValidUntil = newUntil
			fresh.Remaining = domain.Sum(entries)
			return &domain.Ledger{
				MemberID: fresh.MemberID, Delta: 0, Reason: domain.ReasonResume, By: p.UID, At: time.Now().UTC(),
			}, nil
		})
	if err != nil {
		return nil, err
	}
	stampPassStatus(updated) // 목록/단건 응답과 같은 값이어야 한다(hydratePassRemaining 주석)
	return updated, nil
}

// RefundQuote — 환불 계산기(순수 계산, 상태 변경 없음 — 계약에 실행 엔드포인트 없음, README 갭).
// member 본인 패스도 조회 가능(회원 앱 마이탭 환불 계산기 — 읽기 전용이라 부작용 없음).
func (s *Service) RefundQuote(ctx context.Context, p Principal, passID string, used int) (domain.RefundResult, error) {
	pass, err := s.store.GetPass(ctx, p.CenterID, passID)
	if err != nil {
		return domain.RefundResult{}, err
	}
	if err := s.checkPassScope(p, *pass); err != nil {
		return domain.RefundResult{}, err
	}
	if used < 0 || used > pass.TotalSessions {
		return domain.RefundResult{}, errors.Join(errBadRequest, errors.New("사용 횟수가 올바르지 않아요(0~총 횟수)"))
	}
	// 견적도 실행과 같은 정산식(v1.5) — 계산기와 실제 환불액이 조용히 어긋나지 않게.
	rate, paidSum, _, _, err := s.refundBasis(ctx, p.CenterID, pass)
	if err != nil {
		return domain.RefundResult{}, err
	}
	res := domain.SettleRefund(pass.PaidAmount, pass.TotalSessions, used, rate, paidSum)
	// **누르기 전에** 몇 건이 사라지는지 보여준다. 종전엔 견적이 예약을 아예 보지 않아
	// 미리보기 자체가 불가능했고, 그래서 확인 문구도 이 사실을 말할 수 없었다.
	// 실행부(RefundPass)와 **같은 판정**을 쓴다 — 두 곳이 다르게 세면 "3건 취소됩니다"라
	// 예고하고 5건을 지우게 된다.
	n, err := s.countFutureConfirmed(ctx, p.CenterID, pass)
	if err != nil {
		return domain.RefundResult{}, err
	}
	res.CancelledBookings = n
	return res, nil
}

// countFutureConfirmed — 이 패스로 잡힌 **앞으로의 확정 예약** 수.
//
// 환불이 취소할 대상과 **정확히 같은 조건**이어야 한다(RefundPass의 순회 참조) —
// 견적과 실행이 다른 규칙으로 세면 예고한 숫자와 실제로 사라지는 수가 갈린다.
func (s *Service) countFutureConfirmed(ctx context.Context, centerID string, pass *domain.Pass) (int, error) {
	bookings, err := s.store.ListBookingsByMember(ctx, centerID, pass.MemberID)
	if err != nil {
		return 0, err
	}
	now := time.Now()
	n := 0
	for _, b := range bookings {
		if b.PassID != pass.ID || b.Status != domain.BookingConfirmed {
			continue
		}
		if start, err := domain.SlotStart(b.SlotKey); err != nil || start.Before(now) {
			continue
		}
		n++
	}
	return n, nil
}

// usedFromLedger — 환불 정산의 "사용 횟수"(P3·P5). "총 − 잔여"가 아니라 **이용 사유
// (complete/noshow)의 차감 합**으로 센다: 부분 실패 재시도 시 이미 적재된 refund 마감 원장이
// "사용"으로 오집계되는 것을 막는다(P05 통합검수). 사전 검사와 트랜잭션 내부 정산이 같은
// 함수를 쓴다 — 두 곳이 다른 규칙으로 세면 견적과 실제 환불액이 조용히 갈린다.
func usedFromLedger(entries []domain.Ledger) int {
	used := 0
	for _, e := range entries {
		if (e.Reason == domain.ReasonComplete || e.Reason == domain.ReasonNoshow) && e.Delta < 0 {
			used += -e.Delta
		}
	}
	return used
}

// RefundPass — POST /v1/passes/{id}/refund {used}(v1.4 — 환불 "실행"). 견적(refund-quote)과 달리
// 상태를 바꾼다: 원장에 refund 이벤트(잔여를 0으로 마감)를 남기고 status=refunded로 전이.
// owner 전용 — 금전 처리라 트레이너에게 열지 않는다(P13). 모든 변경은 원장으로(P3): 분쟁 시
// "왜 이 패스가 refunded인가"에 원장이 답한다.
func (s *Service) RefundPass(ctx context.Context, p Principal, passID string, used int) (*domain.Pass, domain.RefundResult, error) {
	if !p.IsOwner() {
		return nil, domain.RefundResult{}, ErrForbidden
	}
	pass, err := s.store.GetPass(ctx, p.CenterID, passID)
	if err != nil {
		return nil, domain.RefundResult{}, err
	}
	if pass.Status == domain.PassStatusRefunded {
		return nil, domain.RefundResult{}, errors.Join(errBadRequest, errors.New("이미 환불 처리된 패스예요"))
	}
	entries, err := s.store.ListLedger(ctx, p.CenterID, pass.MemberID, pass.ID)
	if err != nil {
		return nil, domain.RefundResult{}, err
	}
	// 바디의 used는 어드민 견적과의 일치 확인용 사전 검사다: 다르면 400. 최종 정산에 쓰는 값은
	// 아래 트랜잭션이 본 원장에서 다시 센다(그 사이에 완료 처리가 끼어들 수 있다).
	derivedUsed := usedFromLedger(entries)
	if used != 0 && used != derivedUsed {
		return nil, domain.RefundResult{}, errors.Join(errBadRequest,
			fmt.Errorf("사용 횟수가 원장과 달라요 — 원장 기준 %d회로 다시 확인해주세요", derivedUsed))
	}
	// v1.5 정산: 위약금율은 회원이 동의한 계약 스냅샷 우선, 환불액은 실수납 기준(P04 감사).
	rate, paidSum, payments, contracts, err := s.refundBasis(ctx, p.CenterID, pass)
	if err != nil {
		return nil, domain.RefundResult{}, err
	}
	quote := domain.RefundResult{}
	// 미래 confirmed 예약 일괄 취소(무차감) — 환불 후 예약이 살아남으면 완료 처리 시 원장이
	// 음수로 내려가고(정산 오집계) 슬롯 용량도 계속 점유한다(P03 검수 HIGH-1).
	bookings, err := s.store.ListBookingsByMember(ctx, p.CenterID, pass.MemberID)
	if err != nil {
		return nil, domain.RefundResult{}, err
	}
	now := time.Now()
	cancelledBookings := 0
	for _, b := range bookings {
		if b.PassID != pass.ID || b.Status != domain.BookingConfirmed {
			continue
		}
		if start, err := domain.SlotStart(b.SlotKey); err != nil || start.Before(now) {
			continue
		}
		if err := s.store.CancelAtomic(ctx, p.CenterID, b.ID, nil); err != nil && !errors.Is(err, store.ErrStateConflict) {
			return nil, domain.RefundResult{}, err
		}
		// 이미 순회 중이었다 — 세는 것만 안 하고 있었다. 이 숫자가 어드민 확인·완료
		// 문구로 그대로 간다(domain.RefundResult.CancelledBookings 주석).
		cancelledBookings++
	}
	// 마감(원장 refund + status=refunded)은 **한 트랜잭션**이다(P13 C1·C2).
	//
	// 종전에는 ①GetPass 재확인 ②AppendLedger ③UpdatePass가 서로 다른 세 호출이었고 그 사이를
	// 막는 것이 없었다. 실측: 동시 환불 2건이 **둘 다 200**(환불 승인액 495,000원이 두 번, 원장
	// 합 −10) — 대표가 반응 없는 버튼을 한 번 더 누르면 얼마를 보내야 할지 알 수 없게 된다.
	// ②만 성공하고 ③이 실패하면 "잔여 0 · active"인 찢어진 패스가 영구 고착돼 회원은 예약이
	// 막히고(400) 담당 코치는 퇴사 선행 조건에 걸려(409) 영원히 퇴사하지 못했다.
	// ①의 재확인은 트랜잭션 밖이라 **원리적으로** 창을 못 닫는다 — 그래서 스토어 안으로 내렸다.
	//
	// 잔여·사용 회차도 트랜잭션이 본 원장으로 다시 계산한다: 응답에 싣는 견적이 실제 마감된
	// 금액과 어긋나면 안 된다.
	//
	// 미서명 계약 무효화(v1.5)도 **같은 트랜잭션**이다(v2.15, P37 — v2.6 남은 갭의 계약 절반
	// 종결). 종전엔 마감 밖의 루프였다: 루프 vs 서명 경합이 "signed는 무효화 불가" 불변식을
	// 깰 수 있었고, 중간 실패는 refunded 패스에 sent 계약을 남겼다(재시도는 "이미 환불 처리된
	// 패스예요"로 막힌다). 후보는 트랜잭션 밖에서 추리고(위 refundBasis의 목록 — 컬렉션 잠금
	// 회피), 트랜잭션 안에서 ID 점읽기로 다시 읽어 재판정한다: 후보 선정 후 서명이 끼어들었으면
	// 스킵(보존)이 최종 판정이다 — signed는 성립했던 거래의 법적 기록이다.
	voidIDs := []string{}
	for _, c := range contracts {
		if c.PassID == pass.ID && domain.CanVoidContract(c.Status) {
			voidIDs = append(voidIDs, c.ID)
		}
	}
	var txUsed int
	var txQuote domain.RefundResult
	updated, err := s.store.UpdatePassWithLedgerAndContracts(ctx, p.CenterID, passID,
		func(fresh *domain.Pass, entries []domain.Ledger) (*domain.Ledger, error) {
			if fresh.Status == domain.PassStatusRefunded {
				return nil, errors.Join(errBadRequest, errors.New("이미 환불 처리된 패스예요"))
			}
			remaining := domain.Sum(entries)
			txUsed = usedFromLedger(entries)
			// 정산도 트랜잭션이 본 원장으로(v2.37, P73) — 그 결과를 패스에 **함께 기록**한다.
			// 종전엔 마감 뒤 같은 입력으로 다시 계산해 응답에만 실었고 DB엔 금액이 남지 않았다
			// (domain.Pass.RefundedAmount 주석). 재시도(mutate 재호출)마다 다시 계산되므로 값이
			// 트랜잭션이 확정한 원장과 어긋날 수 없다.
			txQuote = domain.SettleRefund(fresh.PaidAmount, fresh.TotalSessions, txUsed, rate, paidSum)
			now := time.Now().UTC()
			refunded := txQuote.Refund
			fresh.Status = domain.PassStatusRefunded
			fresh.Remaining = 0 // 마감 후 잔여는 항상 0(아래 refund 엔트리가 원장에서도 0으로 맞춘다)
			fresh.RefundedAmount = &refunded
			fresh.RefundedAt = &now
			if remaining == 0 {
				// 이미 0이면 원장을 더럽히지 않는다 — 부분 실패 재시도가 refund를 중복 적재해
				// 원장을 음수로 끌어내리지 않게 하는 가드이기도 하다.
				return nil, nil
			}
			return &domain.Ledger{
				MemberID: fresh.MemberID, Delta: -remaining,
				Reason: domain.ReasonRefund, By: p.UID, At: time.Now().UTC(),
			}, nil
		},
		voidIDs,
		func(c *domain.Contract) (bool, error) {
			if !domain.CanVoidContract(c.Status) {
				return false, nil // 트랜잭션이 다시 본 상태가 signed — 보존이 최종 판정
			}
			c.Status = domain.ContractStatusVoided
			return true, nil
		})
	if err != nil {
		return nil, domain.RefundResult{}, err
	}
	pass = updated
	quote = txQuote // 트랜잭션이 기록한 그 값 — 응답과 저장본이 같은 숫자를 말한다

	// ---- 아래는 마감 **이후**의 뒷정리다(남은 갭, P13 후속 — v2.15에서 계약 무효화는 위
	// 트랜잭션 안으로 들어갔고, 미납 회차 종결만 남았다) ----
	//
	// 미납 회차 종결은 환불 트랜잭션 밖에 있다. 여기서 실패하면 응답은 500인데 환불 자체는
	// 이미 확정이고, 재시도는 "이미 환불 처리된 패스예요"(400)로 막힌다 — 미수금 유령이 남는다.
	// 계약처럼 ID 사전 지목으로 접합하지 않은 이유: 결제는 회차 **인덱스 단위**로 다시
	// 판정해야 해 접합의 결이 복잡하고(waived_at은 멱등 표식이라 잔존해도 금액이 틀어지지
	// 않는다), 경합 상대(동시 납부)는 PayInstallment 하나뿐인데 그쪽 원자화가 이미 갭 목록에
	// 있다 — 같은 후속(P13)에서 함께 닫는 편이 맞다. 돈의 방향을 결정하는 마감을 먼저 확정하고,
	// 뒷정리는 사람이 볼 수 있는 실패로 남기는 쪽을 유지한다.

	// 미납 회차 청구 종결(v1.5) — 환불로 정산이 끝난 거래가 미수금으로 영구 잔존하지 않게.
	now2 := time.Now().UTC()
	for i := range payments {
		changed := false
		for j := range payments[i].Installments {
			ins := &payments[i].Installments[j]
			if ins.PaidAt == nil && ins.WaivedAt == nil {
				ins.WaivedAt = &now2
				changed = true
			}
		}
		if changed {
			if err := s.store.UpdatePayment(ctx, p.CenterID, &payments[i]); err != nil {
				return nil, domain.RefundResult{}, err
			}
		}
	}
	stampPassStatus(pass) // 목록/단건 응답과 같은 값이어야 한다(hydratePassRemaining 주석)
	// 취소한 예약 수를 응답에 싣는다 — 어드민 완료 문구가 이 숫자를 그대로 쓴다.
	quote.CancelledBookings = cancelledBookings
	return pass, quote, nil
}

// refundBasis — 환불 정산의 두 기준(v1.5): ① 위약금율 = 패스의 유효(비voided) 계약 스냅샷
// (회원이 동의한 요율 — 패스당 1건 불변식 하에 단일), 없으면(레거시 nil) 현재 정책 ② 실수납 =
// 해당 패스 결제들의 납부 회차 합,
// 결제 기록이 아예 없으면 계약가 폴백(결제 기록 이전 레거시). 결제 목록은 후속 종결 처리,
// 계약 목록은 무효화 후보 선정(RefundPass의 트랜잭션 내 스윕, v2.15)을 위해 함께 반환한다 —
// 같은 스캔을 두 번 돌지 않는다.
func (s *Service) refundBasis(ctx context.Context, centerID string, pass *domain.Pass) (float64, int, []domain.Payment, []domain.Contract, error) {
	policy, err := s.store.GetPolicy(ctx, centerID)
	if err != nil {
		return 0, 0, nil, nil, err
	}
	rate := policy.EffectivePenaltyRate()
	contracts, err := s.store.ListContracts(ctx, centerID, pass.MemberID, "")
	if err != nil {
		return 0, 0, nil, nil, err
	}
	for _, c := range contracts {
		if c.PassID == pass.ID && c.Status != domain.ContractStatusVoided && c.PenaltyRate != nil {
			rate = *c.PenaltyRate // 포인터라 "동의된 0%"와 레거시(nil)를 구분한다(P05 통합검수)
			break
		}
	}
	// 이 패스의 결제만 읽는다(v2.38, P74) — 종전엔 센터 전체 결제를 읽고 pass_id로 걸러, 환불 견적
	// 1건의 비용이 센터의 누적 결제 수에 비례했다.
	passPayments, err := s.store.ListPaymentsByPass(ctx, centerID, pass.ID)
	if err != nil {
		return 0, 0, nil, nil, err
	}
	paidSum := 0
	// 실수납은 "지금까지 들어온 돈" — 미래 paid_at은 세지 않는다(P12 감사 M5). 경계는 생성
	// 게이트와 **같은 값**(now + 허용 오차)을 쓴다: 게이트가 시계 오차로 통과시킨 paid_at을
	// 정산이 다시 떨어뜨리면, 방금 기록한 결제가 몇 분간 "받은 적 없는 돈"이 된다.
	asOf := time.Now().UTC().Add(paidAtClockSkew)
	for _, pay := range passPayments {
		paidSum += pay.PaidSum(asOf)
	}
	if len(passPayments) == 0 {
		paidSum = pass.PaidAmount // 결제 기록 없는 레거시 — 계약가 폴백(README 갭)
	} else if paidSum > pass.PaidAmount {
		// 실수납이 계약가를 넘는 건 언제나 데이터 이상(중복 기록 — P12 감사 C1). 원장주의(P3)라
		// 잘못 적재된 결제 레코드를 지우지는 않는다: 정산 기준액은 domain.SettleRefund가 계약가로
		// 캡핑하고(그쪽이 유일한 강제 지점 — 견적·실행이 함께 보호된다), 여기서는 그 사건을
		// 로그로 남긴다. 조용히 캡만 걸면 중복 기록이 영원히 발견되지 않는다.
		logPaymentOverContract(pass.ID, paidSum, pass.PaidAmount)
	}
	return rate, paidSum, passPayments, contracts, nil
}

// ListPasses — GET /v1/passes?member=(앱 가정 승인: 내/특정 회원 회원권 목록, v1.1 정합 패치).
// member=본인 강제, trainer=담당 패스만, owner=전체(또는 지정 회원). Remaining은 항상 원장 재계산.
func (s *Service) ListPasses(ctx context.Context, p Principal, memberQuery string) ([]domain.Pass, error) {
	memberID, err := memberScopeID(p, memberQuery)
	if err != nil {
		return nil, err
	}
	var list []domain.Pass
	if memberID != "" {
		list, err = s.store.ListPassesByMember(ctx, p.CenterID, memberID)
	} else {
		list, err = s.store.ListPasses(ctx, p.CenterID)
	}
	if err != nil {
		return nil, err
	}
	if p.IsTrainer() {
		filtered := make([]domain.Pass, 0, len(list))
		for _, ps := range list {
			if ps.TrainerID == p.UID {
				filtered = append(filtered, ps)
			}
		}
		list = filtered
	}
	return s.hydratePassesRemaining(ctx, p.CenterID, list)
}

// ---- 슬롯/예약 ----

func (s *Service) ListSlots(ctx context.Context, p Principal, date string) ([]domain.Slot, error) {
	slots, err := s.store.ListSlots(ctx, p.CenterID, date)
	if err != nil {
		return nil, err
	}
	// v1.5 최소노출: member에게는 타인 팀의 member_id·booking_id를 비운다 — 점유율·코치·본인
	// 예약 판정(AlreadyBookedByMe)에 필요한 정보만 남긴다(본인 팀은 원문 유지).
	if p.IsMember() {
		for i := range slots {
			for j := range slots[i].Teams {
				t := &slots[i].Teams[j]
				if t.MemberID != p.MemberID {
					t.MemberID = ""
					t.BookingID = ""
				}
			}
		}
	}
	return slots, nil
}

// ListBookings — GET /v1/bookings?member=&from=(앱 가정 승인: 내 예약 목록, v1.1 정합 패치).
// member=본인 강제, trainer=담당 예약만, owner=전체(또는 지정 회원). from은 "YYYY-MM-DD" 이후
// 슬롯만(그 날짜 포함) 필터한다.
func (s *Service) ListBookings(ctx context.Context, p Principal, memberQuery, from string) ([]domain.Booking, error) {
	memberID, err := memberScopeID(p, memberQuery)
	if err != nil {
		return nil, err
	}
	var list []domain.Booking
	if memberID != "" {
		list, err = s.store.ListBookingsByMember(ctx, p.CenterID, memberID)
	} else {
		list, err = s.store.ListBookings(ctx, p.CenterID)
	}
	if err != nil {
		return nil, err
	}
	if from != "" {
		if _, err := time.Parse("2006-01-02", from); err != nil {
			return nil, errors.Join(errBadRequest, errors.New("from은 YYYY-MM-DD 형식이어야 해요")) // v1.4.1 workout-logs와 대칭
		}
	}
	fromCompact := strings.ReplaceAll(from, "-", "")
	out := make([]domain.Booking, 0, len(list))
	for _, b := range list {
		if p.IsTrainer() && b.TrainerID != p.UID {
			continue
		}
		if fromCompact != "" {
			datePart := b.SlotKey
			if len(datePart) >= 8 {
				datePart = datePart[:8]
			}
			if datePart < fromCompact {
				continue
			}
		}
		out = append(out, b)
	}
	return out, nil
}

// checkBookingScope — 예약 생성·취소 권한: owner 전체, trainer는 자기 소속 패스만,
// member는 본인 패스만(트레이너 대행 예약은 owner/trainer 경로로 커버 — P16).
func (s *Service) checkBookingScope(p Principal, memberID, trainerID string) error {
	switch {
	case p.IsOwner():
		return nil
	case p.IsTrainer():
		if trainerID != p.UID {
			return ErrForbidden
		}
		return nil
	case p.IsMember():
		if memberID != p.MemberID {
			return ErrForbidden
		}
		return nil
	}
	return ErrForbidden
}

type BookingCreateRequest struct {
	SlotKey  string `json:"slot_key"`
	MemberID string `json:"member_id"`
	PassID   string `json:"pass_id"`
	Kind     string `json:"kind,omitempty"` // 계약 예시엔 없음(기본 pt) — README 갭
}

// CreateBooking — 트랜잭션: 용량 + 트레이너동시1 + 회원동시1(store.BookAtomic) + 잔여>0·유효 — P35·v1.5.
func (s *Service) CreateBooking(ctx context.Context, p Principal, req BookingCreateRequest) (*domain.Booking, error) {
	pass, err := s.store.GetPass(ctx, p.CenterID, req.PassID)
	if err != nil {
		return nil, err
	}
	if pass.MemberID != req.MemberID {
		return nil, errors.Join(errBadRequest, errors.New("pass_id가 member_id 소유가 아님"))
	}
	if err := s.checkBookingScope(p, pass.MemberID, pass.TrainerID); err != nil {
		return nil, err
	}
	// 탈퇴 회원의 슬롯 점유를 막는다(v2.11) — 그 예약은 아무도 나타나지 않을 자리를 잡는다.
	bookingMember, err := s.store.GetMember(ctx, p.CenterID, pass.MemberID)
	if err != nil {
		return nil, err
	}
	if err := guardMemberNotWithdrawn(*bookingMember, "예약을 잡을 수 없어요"); err != nil {
		return nil, err
	}
	// Remaining은 원장이 진실(P3) — 저장 스냅샷 대신 항상 재계산 후 판정한다.
	if err := s.hydratePassRemaining(ctx, p.CenterID, pass); err != nil {
		return nil, err
	}
	if !pass.BookableStatus() {
		return nil, errors.Join(errBadRequest, errors.New("이용 가능한 상태의 패스가 아니에요(환불·만료 처리됨)"))
	}
	if pass.Remaining <= 0 {
		return nil, errors.Join(errBadRequest, errors.New("잔여 세션이 없어요"))
	}
	// 예약 예산 = 잔여 − **이미 잡혀 있는** confirmed 예약(P13 H1).
	//
	// 잔여는 완료 시점에 차감되므로(P4) 예약을 아무리 잡아도 줄지 않는다 — 이 뺄셈이 없으면
	// 잔여 2회짜리 패스에 예약을 무한히 잡을 수 있고, CompleteBooking은 잔여를 재검사하지 않아
	// 바닥도 없다(실측: 잔여 2회 → 4건 예약 → 4건 완료 → remaining −2). 같은 뺄셈이
	// CreateRecurring(P12 H4)에는 이미 있었는데 **일반 예약에만 없었다** — 더 싼 우회로였다.
	// 스토어도 BookAtomic 트랜잭션 안에서 같은 판정을 한 번 더 한다(동시 예약 방어).
	open, err := s.countOpenPassBookings(ctx, p.CenterID, pass.MemberID, pass.ID)
	if err != nil {
		return nil, err
	}
	if pass.Remaining-open <= 0 {
		return nil, errors.Join(errBadRequest, fmt.Errorf(
			"이미 잡힌 예약 %d건이 잔여 %d회를 채웠어요 — 기존 예약을 정리하거나 회차를 추가해주세요", open, pass.Remaining))
	}
	// 시간축 판정은 전부 "슬롯" 기준(v1.3, 2R 자문자답): 세션이 실제로 일어나는 시각이 기준 —
	// ① 이미 지난 시간대는 거부, ② valid_from이 미래인 재등록 패스도 유효기간 안의 슬롯이면
	// 선예약 허용(오늘 기준 유효기간 검사는 이 플로우를 막아서 제거), ③ 홀딩 구간의 슬롯 거부.
	start, err := domain.SlotStart(req.SlotKey)
	if err != nil {
		return nil, errors.Join(errBadRequest, err)
	}
	if start.Before(time.Now()) {
		return nil, errors.Join(errBadRequest, errors.New("이미 지난 시간이에요"))
	}
	slotDate := start.In(domain.KST).Format("2006-01-02")
	if slotDate < pass.ValidFrom || slotDate > pass.ValidUntil {
		return nil, errors.Join(errBadRequest, errors.New("슬롯 날짜가 패스 유효기간 밖이에요"))
	}
	if pass.OnHold(slotDate) {
		return nil, errors.Join(errBadRequest, errors.New("슬롯 날짜가 홀딩(일시정지) 기간이에요"))
	}
	// 트레이너 휴무일 예약 거부(v1.4 — recurring 선행 생성만 거르고 일반 예약은 뚫리던 갭).
	// 스태프 레코드가 아직 없으면(미시딩 dev — ErrNotFound) 검사를 건너뛴다. **부재와 장애는
	// 가른다**(v2.37, P73 — P56 B7~B9와 같은 규약): 종전 `err == nil`은 스토어 순단에 퇴사자·
	// 휴무일 거부가 통째로 꺼져 예약이 조용히 성립했다. 장애면 멈춘다.
	if st, err := s.store.GetStaff(ctx, p.CenterID, pass.TrainerID); err == nil {
		// 퇴사자 앞으로는 새 예약을 잡을 수 없다(v2.0 — 휴무일 거부와 같은 자리). 없으면
		// 퇴사 처리로 비운 선행 조건이 곧바로 다시 채워져 이관→퇴사 여정이 무한 반복된다.
		if !st.IsActive() {
			return nil, errors.Join(errBadRequest, errors.New("퇴사 처리된 코치예요 — 담당을 먼저 이관해주세요"))
		}
		// 판정은 domain.Staff.IsOffday에 맡긴다 — 종전엔 여기서 인라인 containsStr로 같은 일을
		// 하는 바람에 도메인 쪽 함수가 호출부 0건의 죽은 코드였다(P14 L4). 휴무 판정이 언젠가
		// 바뀐다면(기간 휴무 등) 고칠 자리가 하나여야 한다.
		if st.IsOffday(slotDate) {
			return nil, errors.Join(errBadRequest, errors.New("담당 코치의 휴무일이에요"))
		}
	} else if !errors.Is(err, store.ErrNotFound) {
		return nil, err
	}
	kind := req.Kind
	if kind == "" {
		kind = domain.BookingKindPT
	}
	if kind != domain.BookingKindPT && kind != domain.BookingKindGroup && kind != domain.BookingKindOT {
		return nil, errors.Join(errBadRequest, errors.New("kind는 pt|group|ot 중 하나여야 해요"))
	}
	policy, err := s.store.GetPolicy(ctx, p.CenterID)
	if err != nil {
		return nil, err
	}
	booking := &domain.Booking{
		SlotKey: req.SlotKey, MemberID: req.MemberID, TrainerID: pass.TrainerID, PassID: pass.ID,
		Kind: kind, Status: domain.BookingConfirmed,
	}
	if err := s.store.BookAtomic(ctx, p.CenterID, req.SlotKey, policy.SlotCapacity, booking); err != nil {
		return nil, err
	}
	return booking, nil
}

// buildNoshowEntry — 노쇼(또는 컷오프 내 취소) 원장 엔트리. 최초 1회 유예(P7)를 history에서 판정.
func buildNoshowEntry(b *domain.Booking, history []domain.Ledger, policy domain.Policy, by string) domain.Ledger {
	reason := domain.ReasonNoshow
	delta := -1
	if policy.GraceOnce {
		usedBefore := false
		for _, e := range history {
			// 유예가 이미 소진됐는지는 noshow뿐 아니라 noshow_waived(유예된 최초 1회)도 포함해
			// 판정한다 — waived만 검색에서 빠지면 매번 "최초"로 오판해 유예가 무한 반복된다(P7).
			if e.Reason == domain.ReasonNoshow || e.Reason == domain.ReasonNoshowWaive {
				usedBefore = true
				break
			}
		}
		if !usedBefore {
			reason = domain.ReasonNoshowWaive
			delta = 0
		}
	}
	return domain.Ledger{
		PassID: b.PassID, MemberID: b.MemberID, Delta: delta, Reason: reason,
		RefBookingID: b.ID, By: by, At: time.Now().UTC(),
	}
}

// CancelBooking — 컷오프(기본24h) 이내 취소는 노쇼에 준해 유예 정책까지 동일 적용(P7).
// 컷오프 이전 취소는 무차감. 취소 자체는 항상 허용한다(막으면 노쇼로 위장할 유인만 커짐).
func (s *Service) CancelBooking(ctx context.Context, p Principal, bookingID string, waivePenalty bool) error {
	b, err := s.store.GetBooking(ctx, p.CenterID, bookingID)
	if err != nil {
		return err
	}
	if err := s.checkBookingScope(p, b.MemberID, b.TrainerID); err != nil {
		return err
	}
	if b.Status != domain.BookingConfirmed {
		// 2R HIGH-2: 완료/노쇼/취소된 예약을 다시 취소하면 상태가 뒤집히고(완료 소실) 컷오프
		// 판정에 따라 노쇼 원장이 추가로 쌓인다(재시도마다 이중 차감). confirmed에서만 허용.
		return errors.Join(errBadRequest, errors.New("confirmed 상태의 예약만 취소할 수 있어요(이미 처리됨)"))
	}
	policy, err := s.store.GetPolicy(ctx, p.CenterID)
	if err != nil {
		return err
	}
	late, cutoffErr := domain.WithinCancelCutoff(b.SlotKey, time.Now(), policy.CancelCutoffHours)

	// 페널티 판정을 **취소보다 먼저** 끝내고, 취소와 원장을 한 트랜잭션에 함께 넣는다(P13 M4).
	//
	// 종전에는 CancelAtomic → AppendLedger 두 호출이었다. 원장 적재만 실패하면 예약은 이미
	// cancelled로 확정인데 페널티는 없고, 재시도는 "confirmed 상태의 예약만 취소할 수 있어요"에
	// 막혀 **페널티가 영구 소실**됐다(실측). complete/noshow는 처음부터
	// SetBookingStatusWithLedger 한 트랜잭션이었는데 취소만 쪼개져 있었다.
	entry, err := s.cancelPenaltyEntry(ctx, p, b, policy, late && cutoffErr == nil, waivePenalty)
	if err != nil {
		return err
	}
	return s.store.CancelAtomic(ctx, p.CenterID, bookingID, entry)
}

// cancelPenaltyEntry — 취소에 딸릴 페널티 원장(없으면 nil). 컷오프 밖이거나 스태프의 운영 사유
// 취소이거나 환불된 패스면 무차감이다.
func (s *Service) cancelPenaltyEntry(ctx context.Context, p Principal, b *domain.Booking,
	policy *domain.Policy, late, waivePenalty bool) (*domain.Ledger, error) {
	if !late {
		return nil, nil
	}
	// v1.5: 스태프의 운영 사유 취소(waive=true)는 무차감 — recurring 정리·코치 사정 취소가 회원
	// 유예를 소진시키지 않게(P04 M1). member 호출은 이 플래그를 쓸 수 없다(핸들러에서 차단).
	if waivePenalty && p.IsStaff() {
		return nil, nil
	}
	// 환불 처리된 패스의 잔존 회차 뒷정리 취소는 페널티 무의미(P04 M2 — 원장 음수 방지).
	// 인프라 에러를 "환불 아님"으로 삼키지 않는다(P56). 스토어 순단에
	// 이 가드가 조용히 꺼지면 **환불된 패스에 차감이 붙는다** — 바로 아래
	// 주석이 막으려던 그 원장 음수다.
	if pass, err := s.store.GetPass(ctx, p.CenterID, b.PassID); err != nil {
		if !errors.Is(err, store.ErrNotFound) {
			return nil, err
		}
	} else if pass.Status == domain.PassStatusRefunded {
		return nil, nil
	}
	history, err := s.store.ListLedger(ctx, p.CenterID, b.MemberID, b.PassID)
	if err != nil {
		return nil, err
	}
	entry := buildNoshowEntry(b, history, *policy, p.UID)
	return &entry, nil
}

// CompleteBooking — 세션 차감(P4: 완료 시점 기준, 예약 시점 아님).
func (s *Service) CompleteBooking(ctx context.Context, p Principal, bookingID string) (*domain.Booking, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	b, err := s.store.GetBooking(ctx, p.CenterID, bookingID)
	if err != nil {
		return nil, err
	}
	if p.IsTrainer() && b.TrainerID != p.UID {
		return nil, ErrForbidden
	}
	if b.Status != domain.BookingConfirmed {
		// 상태 전이 가드: 이미 completed/noshow/cancelled인 예약을 다시 처리하면 원장이 이중
		// 차감되거나 취소가 부활한다(v1.2 정합 패치 — confirmed에서만 전이 허용).
		return nil, errors.Join(errBadRequest, errors.New("confirmed 상태의 예약만 완료 처리할 수 있어요(이미 처리됨)"))
	}
	// 환불된 패스의 잔존 예약 방어(P03 HIGH-1의 이중 방어선 — RefundPass가 미래 예약을 일괄
	// 취소하지만, 취소 실패·경합 잔존분이 완료 처리되면 원장이 음수로 내려간다).
	// 인프라 에러를 "환불 아님"으로 삼키지 않는다(P56). 스토어 순단에
	// 이 가드가 조용히 꺼지면 **환불된 패스에 차감이 붙는다** — 바로 아래
	// 주석이 막으려던 그 원장 음수다.
	if pass, err := s.store.GetPass(ctx, p.CenterID, b.PassID); err != nil {
		if !errors.Is(err, store.ErrNotFound) {
			return nil, err
		}
	} else if pass.Status == domain.PassStatusRefunded {
		return nil, errors.Join(errBadRequest, errors.New("환불 처리된 패스의 예약이라 완료할 수 없어요"))
	}
	entry := &domain.Ledger{
		PassID: b.PassID, MemberID: b.MemberID, Delta: -1, Reason: domain.ReasonComplete,
		RefBookingID: b.ID, By: p.UID, At: time.Now().UTC(),
	}
	if err := s.store.SetBookingStatusWithLedger(ctx, p.CenterID, bookingID, domain.BookingCompleted, entry); err != nil {
		return nil, err
	}
	b.Status = domain.BookingCompleted
	return b, nil
}

// NoshowBooking — 노쇼 차감(최초 1회 유예, P7).
func (s *Service) NoshowBooking(ctx context.Context, p Principal, bookingID string) (*domain.Booking, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	b, err := s.store.GetBooking(ctx, p.CenterID, bookingID)
	if err != nil {
		return nil, err
	}
	if p.IsTrainer() && b.TrainerID != p.UID {
		return nil, ErrForbidden
	}
	if b.Status != domain.BookingConfirmed {
		// 상태 전이 가드 — CompleteBooking과 동일(이중 차감·중복 유예 방지, v1.2 정합 패치).
		return nil, errors.Join(errBadRequest, errors.New("confirmed 상태의 예약만 노쇼 처리할 수 있어요(이미 처리됨)"))
	}
	// 인프라 에러를 "환불 아님"으로 삼키지 않는다(P56). 스토어 순단에
	// 이 가드가 조용히 꺼지면 **환불된 패스에 차감이 붙는다** — 바로 아래
	// 주석이 막으려던 그 원장 음수다.
	if pass, err := s.store.GetPass(ctx, p.CenterID, b.PassID); err != nil {
		if !errors.Is(err, store.ErrNotFound) {
			return nil, err
		}
	} else if pass.Status == domain.PassStatusRefunded {
		return nil, errors.Join(errBadRequest, errors.New("환불 처리된 패스의 예약이라 노쇼 처리할 수 없어요"))
	}
	policy, err := s.store.GetPolicy(ctx, p.CenterID)
	if err != nil {
		return nil, err
	}
	history, err := s.store.ListLedger(ctx, p.CenterID, b.MemberID, b.PassID)
	if err != nil {
		return nil, err
	}
	entry := buildNoshowEntry(b, history, *policy, p.UID)
	if err := s.store.SetBookingStatusWithLedger(ctx, p.CenterID, bookingID, domain.BookingNoshow, &entry); err != nil {
		return nil, err
	}
	b.Status = domain.BookingNoshow
	return b, nil
}

// ---- 고정 스케줄(P47) ----

type RecurringCreateRequest struct {
	MemberID  string   `json:"member_id"`
	TrainerID string   `json:"trainer_id"`
	PassID    string   `json:"pass_id"`
	Days      []string `json:"days"`
	Hour      int      `json:"hour"`
	Until     string   `json:"until"`
}

// countOpenPassBookings — 이 패스로 **이미 잡혀 있는** confirmed 예약 수.
//
// 잔여(Remaining)는 완료 시점에 차감되므로(P4) 예약을 아무리 잡아도 줄지 않는다. "잔여 이내"를
// 뜻하는 캡은 전부 이 수를 함께 세야 성립한다 — confirmed 하나하나가 잔여에 대한 청구권이다
// (과거 confirmed도 센다: 곧 완료 또는 노쇼로 차감될 회차다).
//
// 전용 스토어 메서드를 새로 만들지 않았다. ListBookingsByMember는 이미 있고, RefundPass의 잔존
// 예약 정리(위)도 같은 방식으로 필터한다 — 두 구현(Memory/Firestore)에 인덱스가 필요한 쿼리를
// 추가하는 비용 대비 이득이 없다. 회원 1명의 예약 건수는 v1 규모에서 수백 건 수준이다.
func (s *Service) countOpenPassBookings(ctx context.Context, centerID, memberID, passID string) (int, error) {
	bookings, err := s.store.ListBookingsByMember(ctx, centerID, memberID)
	if err != nil {
		return 0, err
	}
	n := 0
	for _, b := range bookings {
		if b.PassID == passID && b.Status == domain.BookingConfirmed {
			n++
		}
	}
	return n, nil
}

// CreateRecurring — 규칙 저장 + N주 선행 슬롯 즉시 생성(설계03 §5). 특정 주차가 용량/중복으로
// 막히면 그 주만 건너뛰고 계속한다(전체 실패시키지 않음 — 회원 알림·재조정 큐는 v1 미구현, README 갭).
// v1.2 정합 패치: CreateBooking과 동일한 패스 검증(소유·잔여·유효기간·홀딩)을 적용하고, 선행
// 생성 수를 잔여 세션 이내로 캡핑한다 — recurring이 예약 규칙의 우회로가 되지 않도록.
func (s *Service) CreateRecurring(ctx context.Context, p Principal, req RecurringCreateRequest) (*domain.Recurring, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	pass, err := s.store.GetPass(ctx, p.CenterID, req.PassID)
	if err != nil {
		return nil, err
	}
	if pass.MemberID != req.MemberID {
		return nil, errors.Join(errBadRequest, errors.New("pass_id가 member_id 소유가 아님"))
	}
	if req.TrainerID != "" && req.TrainerID != pass.TrainerID {
		return nil, errors.Join(errBadRequest, errors.New("trainer_id가 패스의 담당 트레이너와 다름"))
	}
	if p.IsTrainer() && pass.TrainerID != p.UID {
		return nil, ErrForbidden
	}
	// 슬롯키 위생 검사이지 **운영시간 검사가 아니다**(계약 v2.24 명시). Policy.open_hour/
	// close_hour로 시간대를 강제하지 않는 것은 의도다: 강제하면 대표가 close_hour를 21→20으로
	// 줄이는 순간 이미 잡힌 21시 규칙·예약을 취소·이동조차 못 하게 잠긴다(그 레코드를 만지는
	// 모든 경로가 400). 정책 변경이 과거를 소급 파괴하지 않는다는 규칙(v2.0)과 같은 근거다 —
	// 운영시간은 클라이언트가 그리드를 그리는 값이고, 데스크가 특별히 잡아 주는 영업시간 외
	// 수업은 실재하는 정상 영업이다.
	if req.Hour < 0 || req.Hour > 23 {
		return nil, errors.Join(errBadRequest, errors.New("hour는 0~23 사이여야 해요")) // 유령 규칙 방지(P04 M5)
	}
	if len(req.Days) == 0 {
		return nil, errors.Join(errBadRequest, errors.New("반복 요일을 1개 이상 지정해야 해요"))
	}
	validDays := map[string]bool{"mon": true, "tue": true, "wed": true, "thu": true, "fri": true, "sat": true, "sun": true}
	for _, d := range req.Days {
		if !validDays[d] {
			return nil, errors.Join(errBadRequest, errors.New("요일은 mon~sun 소문자 3글자여야 해요: "+d))
		}
	}
	if req.Until != "" {
		if _, err := time.Parse("2006-01-02", req.Until); err != nil {
			return nil, errors.Join(errBadRequest, errors.New("until은 YYYY-MM-DD 형식이어야 해요"))
		}
		// 형식만 보던 자리(P04 M5)에 값 검사를 더한다: until이 이미 지난 규칙은 예약을 한 건도
		// 만들지 못하는데 문서는 남고, ListRecurrings가 만료 규칙을 숨기므로(아래) UI에서 지울
		// 수도 없는 유령이 된다(P12 M2 실측: until=2020-01-01 → 200 + rec_000050, 예약 0건).
		if req.Until < today() {
			return nil, errors.Join(errBadRequest, errors.New("until이 이미 지난 날짜예요 — 오늘 이후로 지정해주세요"))
		}
	}
	// 퇴사자 앞으로는 고정 스케줄도 만들 수 없다(v2.0 — CreateBooking과 같은 규칙).
	// 규칙 저장 **전에** 본다: 아래 선행 생성 루프의 GetStaff(휴무일 조회)는 이미 규칙이
	// 저장된 뒤라 거기서 막으면 유령 규칙이 남는다.
	// 부재(ErrNotFound)만 통과, 장애는 전파(v2.37, P73 — CreateBooking과 같은 규약). 휴무일도
	// 여기서 함께 받아 둔다: 종전엔 규칙 저장 **뒤** 같은 스태프를 한 번 더 읽어 휴무일을 얻었고
	// 그 두 번째 읽기는 `err == nil`이라 순단 시 휴무일이 빈 집합이 돼 휴무일에 예약이 잡혔다.
	// 한 번 읽어 두 곳에 쓰면 그 창 자체가 없다.
	offdays := map[string]bool{}
	if st, err := s.store.GetStaff(ctx, p.CenterID, pass.TrainerID); err == nil {
		if !st.IsActive() {
			return nil, errors.Join(errBadRequest, errors.New("퇴사 처리된 코치예요 — 담당을 먼저 이관해주세요"))
		}
		for _, d := range st.Offdays {
			offdays[d] = true
		}
	} else if !errors.Is(err, store.ErrNotFound) {
		return nil, err
	}
	if err := s.hydratePassRemaining(ctx, p.CenterID, pass); err != nil {
		return nil, err
	}
	// CreateBooking과 동일한 v1.3 시간축: 상태·잔여는 지금 기준, 날짜 적합성은 회차(슬롯)별로.
	if !pass.BookableStatus() {
		return nil, errors.Join(errBadRequest, errors.New("이용 가능한 상태의 패스가 아니에요(환불·만료 처리됨)"))
	}
	if pass.Remaining <= 0 {
		return nil, errors.Join(errBadRequest, errors.New("잔여 세션이 없어요"))
	}
	// 선행 생성 예산 = 잔여 − **이미 잡혀 있는** confirmed 예약(P12 H4).
	//
	// 종전 캡은 이 호출에서 만든 건수(created)만 셌다. 잔여는 완료 시점에 차감되므로(P4)
	// 예약이 늘어도 줄지 않는다 → 규칙을 두 번 만들면 캡이 통째로 무력화됐다(실측: 잔여 10회에
	// confirmed 21건). 슬롯 정원과 코치 일정이 실제 팔린 세션의 2배로 잠기고, CompleteBooking은
	// 잔여를 재검사하지 않아 원장이 음수로 내려간다. 주석이 약속한 보장("recurring이 예약 규칙의
	// 우회로가 되지 않도록")은 이 뺄셈이 있어야 성립한다.
	open, err := s.countOpenPassBookings(ctx, p.CenterID, pass.MemberID, pass.ID)
	if err != nil {
		return nil, err
	}
	budget := pass.Remaining - open
	if budget <= 0 {
		// 규칙만 남기고 예약을 0건 만드는 편(무해한 no-op)이 더 순한 처리로 보이지만, v1엔
		// 자동연장 크론이 없어 그 규칙은 영원히 아무것도 만들지 않는다 — 대표는 "고정 걸었다"고
		// 믿고 회원은 예약이 없다. 잔여 0과 같은 자리에서 명시적으로 거부한다.
		return nil, errors.Join(errBadRequest, fmt.Errorf(
			"이미 잡힌 예약 %d건이 잔여 %d회를 채웠어요 — 기존 예약을 정리하거나 회차를 추가해주세요", open, pass.Remaining))
	}
	r := &domain.Recurring{
		MemberID: req.MemberID, TrainerID: pass.TrainerID, PassID: req.PassID,
		Days: req.Days, Hour: req.Hour, Until: req.Until,
	}
	id, err := s.store.CreateRecurring(ctx, p.CenterID, r)
	if err != nil {
		return nil, err
	}
	r.ID = id

	policy, err := s.store.GetPolicy(ctx, p.CenterID)
	if err != nil {
		return nil, err
	}
	keys := domain.ExpandSlotKeys(*r, time.Now().In(domain.KST), recurringExpandWeeks, offdays)
	created := 0
	for _, key := range keys {
		if created >= budget {
			break // 잔여 세션(이미 잡힌 예약 포함)을 넘는 선행 예약 생성 금지
		}
		if start, err := domain.SlotStart(key); err != nil || start.Before(time.Now()) {
			continue // 오늘 이미 지난 시각의 회차 생성 금지(P03 — CreateBooking의 과거 거부와 대칭)
		}
		if slotDate, err := domain.SlotDate(key); err != nil ||
			slotDate < pass.ValidFrom || slotDate > pass.ValidUntil || pass.OnHold(slotDate) {
			continue // 유효기간 밖·홀딩 기간의 회차는 건너뛴다
		}
		booking := &domain.Booking{
			SlotKey: key, MemberID: req.MemberID, TrainerID: pass.TrainerID, PassID: req.PassID,
			Kind: domain.BookingKindPT, Status: domain.BookingConfirmed, RecurringID: r.ID,
		}
		if err := s.store.BookAtomic(ctx, p.CenterID, key, policy.SlotCapacity, booking); err == nil {
			created++
		}
	}
	return r, nil
}

// ListRecurrings — GET /v1/recurrings?include_expired=(v1.4 — 고정 스케줄 관리 UI).
// owner=전체, trainer=본인 규칙만. member는 예약 목록의 recurring_id/고정 배지로 충분해
// 관리 API는 스태프 전용.
//
// includeExpired(v2.3): 만료 규칙을 숨기기만 하면(v1.5) 문서는 남는데 UI에 뜨지 않아 **지울
// 방법이 없다**(P12 M2). 기본은 그대로 숨기고, 정리 화면만 이 플래그로 꺼내 볼 수 있게 한다.
func (s *Service) ListRecurrings(ctx context.Context, p Principal, includeExpired bool) ([]domain.Recurring, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	list, err := s.store.ListRecurrings(ctx, p.CenterID)
	if err != nil {
		return nil, err
	}
	out := []domain.Recurring{}
	for _, r := range list {
		if p.IsTrainer() && r.TrainerID != p.UID {
			continue
		}
		if !includeExpired && r.Until != "" && r.Until < today() {
			continue // 만료된 규칙은 목록에서 숨긴다(v1.5 — 자동연장 크론 부재와 겹쳐 "살아있는 규칙"으로 오인 방지)
		}
		out = append(out, r)
	}
	return out, nil
}

// RecurringDeleteResult — DELETE /v1/recurrings/{id} 응답(v2.3). 무엇이 정리됐는지 돌려주지
// 않으면 어드민은 "해제했습니다"만 띄우고, 회원에게 몇 건이 사라졌는지 알릴 근거가 없다
// (v1엔 회원 알림 채널이 없어 대표가 직접 연락한다 — README 갭).
type RecurringDeleteResult struct {
	Cancelled int `json:"cancelled"` // 함께 취소한 미래 confirmed 예약 수
	Kept      int `json:"kept"`      // 남긴 예약 수(이미 지난 회차 · keep_bookings=true)
}

// DeleteRecurring — 규칙 해제 + 그 규칙이 만든 **미래** 예약 정리(P12 M1).
//
// 판단이 갈린 지점이라 근거를 남긴다. 종전에는 규칙 문서만 지워 recurring_id가 붙은 confirmed
// 예약이 그대로 남았다(실측: 삭제 204 → 예약 10건 잔존). 대표는 "해제"를 눌렀는데 회원 앱엔
// 4주치가 계속 뜨고, 남은 걸 하나씩 수동 취소하면 컷오프(24h) 이내 건은 회원의 노쇼 유예를
// 소진했다 — 센터 사정으로 지우는데 회원이 페널티를 먹는 구조였다.
//
//	① 미래 confirmed만 취소한다 — 지난 회차는 완료/노쇼로 정산될 이력이라 손대지 않는다.
//	② 취소는 무차감이다 — CancelBooking을 부르지 않고 CancelAtomic만 쓴다(원장 자체를 만들지
//	   않는다). 운영 사유 취소에 유예를 태우지 않는다는 v1.5 waive=true와 같은 취급이며,
//	   RefundPass의 잔존 예약 정리와도 같은 방식이다.
//	③ keep_bookings=true 탈출구를 둔다 — "규칙만 끊고 이미 잡힌 회차는 그대로 진행"이 실제
//	   운영에 있고(회원과 이미 합의된 일정), 취소는 슬롯을 풀어 되돌릴 수 없다. 파괴적 기본값에
//	   옵트아웃 없이 두지 않는다.
//	④ 삭제를 막고 "향후 예약 취소" 옵션만 주는 안은 버렸다 — 대표가 기대하는 "해제"의 의미가
//	   기본값이어야 하고, 두 단계로 나누면 1단계만 하고 떠난 절반 상태가 지금 버그와 같아진다.
//
// 순서: 예약 정리 → 규칙 삭제. 반대로 하면 중간 실패 시 규칙만 사라져 지금 버그가 재현되고
// 재시도할 손잡이도 없어진다. 이 순서면 재시도가 안전하다(이미 취소된 건은 건너뛴다).
func (s *Service) DeleteRecurring(ctx context.Context, p Principal, id string, keepBookings bool) (RecurringDeleteResult, error) {
	res := RecurringDeleteResult{}
	if p.IsMember() {
		return res, ErrForbidden
	}
	r, err := s.store.GetRecurring(ctx, p.CenterID, id)
	if err != nil {
		return res, err
	}
	if p.IsTrainer() && r.TrainerID != p.UID {
		return res, ErrForbidden
	}
	bookings, err := s.store.ListBookingsByMember(ctx, p.CenterID, r.MemberID)
	if err != nil {
		return res, err
	}
	now := time.Now()
	for _, b := range bookings {
		if b.RecurringID != id || b.Status != domain.BookingConfirmed {
			continue
		}
		if start, err := domain.SlotStart(b.SlotKey); err != nil || start.Before(now) {
			res.Kept++
			continue
		}
		if keepBookings {
			res.Kept++
			continue
		}
		if err := s.store.CancelAtomic(ctx, p.CenterID, b.ID, nil); err != nil {
			if errors.Is(err, store.ErrStateConflict) {
				continue // 경합으로 이미 처리된 예약 — 재시도 안전성을 위해 실패로 보지 않는다
			}
			return res, err
		}
		res.Cancelled++
	}
	if err := s.store.DeleteRecurring(ctx, p.CenterID, id); err != nil {
		return res, err
	}
	return res, nil
}

// ---- 체크인(P44) ----

type CheckinRequest struct {
	Source    string `json:"source"` // tap|self_qr
	BookingID string `json:"booking_id,omitempty"`
	QRToken   string `json:"qr_token,omitempty"`
}

// Checkin — tap(스태프가 예약을 직접 지정)·self_qr(회원이 데스크 고정 QR을 스캔, 서버가 "지금
// 시간창의 내 예약"을 스스로 찾는다) 두 방식(P44). 성공 시 Member.LastVisitAt을 갱신한다
// (설계03 §11: "체크인 시 갱신" — 장기미출석 통계의 근거).
func (s *Service) Checkin(ctx context.Context, p Principal, req CheckinRequest) (*domain.Booking, error) {
	var booking *domain.Booking
	var err error

	switch req.Source {
	case "tap":
		if !p.IsStaff() {
			return nil, ErrForbidden
		}
		if req.BookingID == "" {
			return nil, errors.Join(errBadRequest, errors.New("tap에는 booking_id가 필요함"))
		}
		booking, err = s.store.GetBooking(ctx, p.CenterID, req.BookingID)
		if err != nil {
			return nil, err
		}
		// 담당 경계 — CompleteBooking·NoshowBooking과 **같은 규칙**(v2.5). 종전엔 IsStaff()만 보고
		// booking.TrainerID를 안 봐서, 다른 코치의 예약을 체크인하고 Member.LastVisitAt까지 갱신할
		// 수 있었다(장기미출석 통계의 근거 필드다 — 남의 회원 출석 이력이 조용히 바뀐다).
		// 같은 예약에 대해 세 액션(완료·노쇼·체크인)이 서로 다른 권한을 갖는 게 더 이상하다.
		// 상태 검사보다 앞에 둔다: 권한 없는 호출자가 400/200의 차이로 예약 상태를 캐지 못하게.
		if p.IsTrainer() && booking.TrainerID != p.UID {
			return nil, ErrForbidden
		}
		if booking.Status != domain.BookingConfirmed {
			// 취소·완료된 예약의 tap 체크인 차단(v1.5) — 취소된 예약 체크인이 LastVisitAt을
			// 갱신해 장기미출석 통계를 오염시키던 경로(P04 감사 실증).
			return nil, errors.Join(errBadRequest, errors.New("confirmed 상태의 예약만 체크인할 수 있어요"))
		}
	case "self_qr":
		if !p.IsMember() || p.MemberID == "" {
			return nil, ErrForbidden
		}
		// 대조값의 출처는 **센터 문서에 저장된 토큰**이다(P49, v2.23). 종전엔 환경변수
		// (CHECKIN_QR_TOKEN)였는데, 그 값은 대표가 알 수 없는 곳(Cloud Run 설정)에 있으면서
		// 동시에 대표가 어드민에 손으로 옮겨 적어야 QR이 나오는 구조였다 — 알 수 없는 값을
		// 옮겨 적으라는 요구라 실사용이 불가능했고, 미설정 시 저장소에 적힌 **공개 기본값**
		// 으로 조용히 떨어지는 fail-open이 함께 있었다(그래서 기동 검증이 필요했다).
		qr, err := s.store.GetCheckinQR(ctx, p.CenterID)
		if err != nil {
			return nil, err
		}
		// 미발급은 결측이 아니라 상태다 — 폴백 없이 거부하고, 무엇을 해야 하는지 말한다.
		// 여기에 어떤 폴백(환경변수·기본값)이라도 두는 순간 "발급 안 한 센터가 사실은 열려
		// 있다"는 조용한 구멍이 생긴다. 잠긴 문은 잠긴 것으로 보여야 한다.
		if !qr.Issued() {
			return nil, errors.Join(errBadRequest, errors.New("데스크 체크인 QR이 아직 발급되지 않았습니다 — 어드민 설정에서 발급해 주세요"))
		}
		// 상수 시간 비교 — 값 자체는 192비트라 타이밍으로 캘 물건이 아니지만, 비밀을 `!=`로
		// 비교하는 코드는 다음 사람이 복사해 가는 본보기가 된다. 길이가 다르면 0을 돌려주므로
		// 판정 의미는 바이트 비교 그대로다.
		if subtle.ConstantTimeCompare([]byte(req.QRToken), []byte(qr.Token)) != 1 {
			return nil, errors.Join(errBadRequest, errors.New("qr_token이 유효하지 않음"))
		}
		booking, err = s.findUpcomingBooking(ctx, p)
		if err != nil {
			return nil, err
		}
		if err := domain.ValidateSelfCheckin(booking.SlotKey, time.Now()); err != nil {
			return nil, err
		}
	default:
		return nil, errors.Join(errBadRequest, errors.New("source는 tap|self_qr 이어야 함"))
	}

	if err := s.store.SaveCheckinRecord(ctx, p.CenterID, &store.CheckinRecord{
		BookingID: booking.ID, MemberID: booking.MemberID, Source: req.Source, At: time.Now().UTC(),
	}); err != nil {
		return nil, err
	}
	if mem, err := s.store.GetMember(ctx, p.CenterID, booking.MemberID); err == nil {
		now := time.Now().UTC()
		mem.LastVisitAt = &now
		_, _ = s.store.SaveMember(ctx, p.CenterID, mem)
	}
	return booking, nil
}

// findUpcomingBooking — 셀프체크인 시 "지금 시간창(±30분)에 해당하는 내 예약"을 찾는다(P44).
func (s *Service) findUpcomingBooking(ctx context.Context, p Principal) (*domain.Booking, error) {
	bookings, err := s.store.ListBookingsByMember(ctx, p.CenterID, p.MemberID)
	if err != nil {
		return nil, err
	}
	now := time.Now()
	for i := range bookings {
		b := bookings[i]
		if b.Status != domain.BookingConfirmed {
			continue
		}
		if domain.ValidateSelfCheckin(b.SlotKey, now) == nil {
			return &b, nil
		}
	}
	return nil, errors.Join(errBadRequest, errors.New("시간창 안의 예약을 찾을 수 없음"))
}

// ---- Home Work(P39) ----

type HomeworkCreateRequest struct {
	TrainerID       string            `json:"trainer_id"`
	Scope           string            `json:"scope"`
	TargetMemberIDs []string          `json:"target_member_ids"`
	Include         []string          `json:"include"` // 부상 자동제외를 뒤집을 member_id 목록(수동 포함)
	Items           []domain.HwItem   `json:"items"`
	Schedule        domain.HwSchedule `json:"schedule"`
}

func containsStr(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// ListHomeworks — member=본인 대상만, trainer=본인 배정만, owner=전체(memberQuery로 필터 가능).
//
// date(v2.3): 그 날짜에 스케줄상 유효한 배정만 남긴다(domain.HwSchedule.IsActiveOn).
// **회원 응답의 기본값은 오늘**이다 — 회원 앱의 이 목록은 "오늘의 운동" 그 자체이고, 서버가
// 스케줄을 한 번도 보지 않은 탓에 once 배정이 영구히 남고 days:[mon,wed,fri]도 매일 떴다
// (P12 M4 ①②). 스태프는 배정을 관리·수정하는 화면이라 기본이 전체이고, 필요하면 date로
// 같은 판정을 건다("이 회원 오늘 뭐 하죠?").
//
// 판정 자체는 domain에 있다 — 통계(homeworkCompletion)와 이 목록이 같은 함수를 본다.
func (s *Service) ListHomeworks(ctx context.Context, p Principal, memberQuery, date string) ([]domain.Homework, error) {
	memberID, err := memberScopeID(p, memberQuery)
	if err != nil {
		return nil, err
	}
	if date != "" {
		if _, err := time.Parse("2006-01-02", date); err != nil {
			return nil, errors.Join(errBadRequest, errors.New("date는 YYYY-MM-DD 형식이어야 해요"))
		}
	} else if p.IsMember() {
		date = today()
	}
	all, err := s.store.ListHomeworks(ctx, p.CenterID)
	if err != nil {
		return nil, err
	}
	out := []domain.Homework{}
	for _, hw := range all {
		if p.IsTrainer() && hw.TrainerID != p.UID {
			continue
		}
		if memberID != "" && !hwDeliveredTo(hw, memberID) {
			continue
		}
		if date != "" && !hw.Schedule.IsActiveOn(date) {
			continue
		}
		// 2R HIGH-4: member 응답에서 대상/제외 명단을 지운다 — target_member_ids는 센터 전
		// 회원 ID, excluded는 부상 회원 명단(P39 민감정보)이라 회원 앱에 내려보낼 이유가 없다.
		if p.IsMember() {
			hw.TargetMemberIDs = nil
			hw.Excluded = nil
		}
		out = append(out, hw)
	}
	return out, nil
}

// hwDeliveredTo — 이 배정이 해당 회원에게 **실제로 배달되는가**. 목록 조회(ListHomeworks)와
// 체크 생성(CreateHwCheck)이 같은 함수를 본다 — 읽기와 쓰기가 다른 판정을 쓰면 "화면엔 없는데
// 체크는 되는" 기록이 생긴다(v2.5).
//
//	center_notice → 명단에 없어도 배달(공지 생성 뒤 등록된 회원까지 포함 — 종전 목록 로직 유지)
//	그 외          → target_member_ids에 있어야 배달
//	공통           → 부상 자동제외(excluded) 명단은 어느 scope에서도 배달 대상이 아니다(P39 R5)
func hwDeliveredTo(hw domain.Homework, memberID string) bool {
	if containsStr(hw.Excluded, memberID) {
		return false
	}
	return hw.Scope == domain.HwScopeCenterNotice || containsStr(hw.TargetMemberIDs, memberID)
}

// memberIDs — 회원 레코드 목록에서 ID만 뽑는다(배정 후보 = 해석된 pool 그 자체).
func memberIDs(pool []domain.Member) []string {
	ids := make([]string, 0, len(pool))
	for _, m := range pool {
		ids = append(ids, m.ID)
	}
	return ids
}

// resolveHomeworkTargets — 요청의 target_member_ids를 **실제 회원 레코드로 해석**하고 건건이
// 스코프를 검사한다(v2.5 보안 패치).
//
// 레코드로 되돌리는 게 핵심이다. 종전엔 요청 배열을 그대로 후보로 쓰면서 부상 맵은 pool
// (ListMembers)로만 만들어서, pool 밖 회원 ID를 실으면 담당 경계와 **부상 자동제외가 동시에**
// 뚫렸다 — P39가 막으려던 "부상 회원에게 금기 운동 배정"이 이 경로로 재현됐다(감사 실측:
// excluded:null). 여기서 돌려준 목록이 그대로 ResolveTargets의 members 인자가 되므로 후보와
// 부상 맵은 항상 같은 집합에서 나온다.
//
// scopeTrainerID가 비어있지 않으면(my_members) 그 코치의 담당인지까지 본다. owner 대행은
// checkMemberScope를 전부 통과하므로, subset 없는 경로의 pool(ListMembers(trainerID))과 subset
// 경로의 후보가 어긋나지 않으려면 이 한 겹이 더 필요하다 — "내 담당 회원"이라는 scope의 정의다.
func (s *Service) resolveHomeworkTargets(ctx context.Context, p Principal, ids []string, scopeTrainerID string) ([]domain.Member, error) {
	out := make([]domain.Member, 0, len(ids))
	seen := map[string]bool{}
	for _, id := range ids {
		if seen[id] {
			continue // 중복 지정은 접는다 — 대상 수가 통계 분모(hw_d)라 중복이 분모를 부풀린다
		}
		seen[id] = true
		mem, err := s.store.GetMember(ctx, p.CenterID, id)
		if err != nil {
			return nil, err // 미존재 = 고아 배정(아무에게도 안 보이는데 분모엔 잡힌다) → 404
		}
		if err := s.checkMemberScope(p, *mem); err != nil {
			return nil, err // 담당 아님 → 403
		}
		if scopeTrainerID != "" && mem.TrainerID != scopeTrainerID {
			return nil, ErrForbidden
		}
		// 탈퇴 회원은 배정 대상이 아니다(v2.11). 배달될 앱이 없는데 hw_d(완료율 분모)만
		// 올라가 센터 지표가 구조적으로 내려간다 — v2.3이 "기간이 끝난 배정"을 분모에서
		// 뺀 것과 같은 종류의 오염이다.
		if err := guardMemberNotWithdrawn(*mem, "Home Work를 배정할 수 없어요"); err != nil {
			return nil, err
		}
		out = append(out, *mem)
	}
	return out, nil
}

// CreateHomework — 배정 + 부상 자동 제외(P39).
func (s *Service) CreateHomework(ctx context.Context, p Principal, req HomeworkCreateRequest) (*domain.Homework, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	trainerID := req.TrainerID
	if p.IsTrainer() {
		trainerID = p.UID
	}
	if trainerID == "" {
		return nil, errors.Join(errBadRequest, errors.New("trainer_id required"))
	}
	// 스케줄 값 검증(v2.3). 스토어에 닿기 전에 건다 — {"type":"매일매일","from":"어제"} 같은 값이
	// 저장되면 새 판정 규칙이 weekly로 폴백해 "한 번만" 배정이 영구히 노출된다.
	if err := domain.ValidateHwSchedule(req.Schedule); err != nil {
		return nil, err
	}

	// pool = 이 요청이 건드릴 수 있는 회원 **레코드** 집합. 후보 ID도 부상 맵도 전부 여기서
	// 파생시킨다 — 둘이 다른 출처를 가지면 한쪽만 검사되는 구멍이 다시 생긴다(v2.5).
	var pool []domain.Member
	var err error
	switch req.Scope {
	case domain.HwScopeIndividual:
		if len(req.TargetMemberIDs) == 0 {
			return nil, errors.Join(errBadRequest, errors.New("individual 배정에는 target_member_ids가 필요해요"))
		}
		// individual은 담당 경계만 본다: 부상 자동제외를 건너뛰는 건 P39의 의도된 규칙이고
		// (ResolveTargets 주석 — "개인 지정은 코치가 인지하고 고른 것"), 대표는 센터 전 회원을
		// 지정할 수 있어야 한다(코치 일치까지 강제하면 owner의 개별 배정이 통째로 막힌다).
		pool, err = s.resolveHomeworkTargets(ctx, p, req.TargetMemberIDs, "")
	case domain.HwScopeMyMembers:
		if len(req.TargetMemberIDs) > 0 {
			// subset은 pool과의 **교집합**이어야 한다 — 종전엔 subset을 그대로 써서 담당 경계를
			// 넘었고, 부상 맵은 pool로만 만들어져 경계 밖 회원의 부상 플래그가 탐지되지 않았다.
			pool, err = s.resolveHomeworkTargets(ctx, p, req.TargetMemberIDs, trainerID)
		} else {
			pool, err = s.store.ListMembers(ctx, p.CenterID, trainerID, "")
		}
	case domain.HwScopeCenterNotice:
		if p.IsTrainer() {
			return nil, ErrForbidden // 센터 전체 공지는 owner만
		}
		if len(req.TargetMemberIDs) > 0 {
			pool, err = s.resolveHomeworkTargets(ctx, p, req.TargetMemberIDs, "")
		} else {
			pool, err = s.store.ListMembers(ctx, p.CenterID, "", "")
		}
	default:
		return nil, errors.Join(errBadRequest, errors.New("scope must be individual|my_members|center_notice"))
	}
	if err != nil {
		return nil, err
	}

	override := map[string]bool{}
	for _, id := range req.Include {
		override[id] = true
	}
	targets, excluded := domain.ResolveTargets(req.Scope, memberIDs(pool), pool, override)

	hw := &domain.Homework{
		TrainerID: trainerID, Scope: req.Scope, TargetMemberIDs: targets, Excluded: excluded,
		Items: req.Items, Schedule: req.Schedule,
	}
	id, err := s.store.CreateHomework(ctx, p.CenterID, hw)
	if err != nil {
		return nil, err
	}
	hw.ID = id
	return hw, nil
}

type HwCheckRequest struct {
	MemberID string `json:"member_id,omitempty"` // 스태프 대행 입력 시에만(P16)
	HwID     string `json:"hw_id"`
	Date     string `json:"date"`
	Done     []bool `json:"done"`
}

// CreateHwCheck — 기본은 회원 본인이 체크. 스태프는 member_id를 명시해 대행 입력 가능(P16 대행 패턴).
func (s *Service) CreateHwCheck(ctx context.Context, p Principal, req HwCheckRequest) (*domain.HwCheck, error) {
	memberID := req.MemberID
	switch {
	case p.IsMember():
		// 가입 매칭 전(미연결) 회원은 p.MemberID가 빈 문자열이다 — 그대로 저장하면 주인 없는
		// 체크 기록이 쌓인다. 목록 계열은 memberScopeID가 이 경우를 403으로 막고 있어(P08)
		// 쓰기만 뚫려 있었다.
		if p.MemberID == "" {
			return nil, ErrForbidden
		}
		memberID = p.MemberID
	case p.IsStaff():
		if memberID == "" {
			return nil, errors.Join(errBadRequest, errors.New("member_id required for staff proxy check"))
		}
		// 대행 입력도 읽기와 같은 담당 경계를 받는다(v2.5). 종전엔 검증이 하나도 없어 다른 코치가
		// 남의 담당 회원 완료율을 올릴 수 있었다 — hw_rate는 정산·평가에 쓰이는 지표다.
		mem, err := s.store.GetMember(ctx, p.CenterID, memberID)
		if err != nil {
			return nil, err
		}
		if err := s.checkMemberScope(p, *mem); err != nil {
			return nil, err
		}
	default:
		return nil, ErrForbidden
	}
	// 배정 실존 + "이 회원에게 실제로 배달되는 배정인가"를 목록 조회와 **같은 함수**로 판정한다.
	// 종전엔 hw_id를 아무 문자열로 보내도 200이었다 — 어떤 목록에도 안 뜨는 고아 체크가 쌓였고,
	// hw_id만 알면 남의 배정에도 기록을 붙일 수 있었다.
	hw, err := s.store.GetHomework(ctx, p.CenterID, req.HwID)
	if err != nil {
		return nil, err
	}
	if !hwDeliveredTo(*hw, memberID) {
		return nil, ErrForbidden
	}
	// done은 배정 항목과 1:1이다(앱은 items 인덱스 순서로 배열을 만든다). 길이가 어긋나면
	// 인덱스가 밀려 다른 운동이 완료로 표시되고, 통계의 anyDone도 없는 항목을 세게 된다.
	if len(req.Done) != len(hw.Items) {
		return nil, errors.Join(errBadRequest, errors.New("done 길이가 배정 항목 수와 달라요"))
	}
	// 날짜: 생략은 **오늘(센터 타임존)로 채우고**, 형식 불량만 400이다 — CreateWorkoutLog와 같은 규칙.
	//
	// 400으로 거부하지 않는 이유: 체크는 회원이 이미 화면에서 누른 행동이고(앱은 낙관적 갱신 후
	// 실패하면 체크박스를 되돌린다), 날짜는 서버가 정확히 아는 값이다. 되돌릴 이유가 없다.
	// 빈 값을 **그대로 저장하는 것만은** 막아야 한다: 문서 ID가 (회원,배정,날짜) 합성 키라
	// date:""는 앱의 `?date=오늘` 질의에 영원히 안 잡히는 유령 레코드가 되는데, 통계
	// homeworkCompletion(service_stats.go)은 날짜를 안 보고 anyDone만 세서 "완료"로 집계한다 —
	// 화면엔 미완료, 지표엔 완료라는 정반대 상태가 만들어졌다(감사 실측).
	date := req.Date
	if date == "" {
		date = today()
	} else if _, err := time.Parse("2006-01-02", date); err != nil {
		return nil, errors.Join(errBadRequest, errors.New("date는 YYYY-MM-DD 형식이어야 해요"))
	}
	c := &domain.HwCheck{MemberID: memberID, HwID: req.HwID, Date: date, Done: req.Done}
	if err := s.store.SaveHwCheck(ctx, p.CenterID, c); err != nil {
		return nil, err
	}
	return c, nil
}

// ListHwChecks — GET /v1/hw-checks?hw_id=&member=&date=(어드민·앱 가정 승인, v1.1 정합 패치 +
// v1.2 date 필터 — 앱의 "오늘 체크 상태" 조회가 과거 날짜 체크를 오늘 완료로 오표시하지 않도록).
// member=본인 강제, trainer=담당 회원 체크만(연결된 Homework.trainer_id 기준), owner=전체.
func (s *Service) ListHwChecks(ctx context.Context, p Principal, hwID, memberQuery, date string) ([]domain.HwCheck, error) {
	memberID, err := memberScopeID(p, memberQuery)
	if err != nil {
		return nil, err
	}
	// 회원이 정해졌으면 **그 회원 것만** 읽는다(v2.38, P74). hwChecks는 회원×배정×날짜로 가장 빨리
	// 쌓이는 컬렉션이고, 이 경로는 앱 홈 탭이 열릴 때마다(회원 전원이 매일) 탄다 — 종전엔 센터
	// 전체를 읽고 Go에서 걸렀다(회원 role은 memberScopeID가 본인으로 강제하므로 늘 이 분기다).
	// 아래 Go 필터는 그대로 둔다: hw_id·date·트레이너 소유는 여전히 여기서 거른다.
	var all []domain.HwCheck
	if memberID != "" {
		all, err = s.store.ListHwChecksByMember(ctx, p.CenterID, memberID)
	} else {
		all, err = s.store.ListHwChecks(ctx, p.CenterID)
	}
	if err != nil {
		return nil, err
	}
	var trainerHwIDs map[string]bool
	if p.IsTrainer() {
		homeworks, err := s.store.ListHomeworks(ctx, p.CenterID)
		if err != nil {
			return nil, err
		}
		trainerHwIDs = map[string]bool{}
		for _, hw := range homeworks {
			if hw.TrainerID == p.UID {
				trainerHwIDs[hw.ID] = true
			}
		}
	}
	out := []domain.HwCheck{}
	for _, c := range all {
		if hwID != "" && c.HwID != hwID {
			continue
		}
		if memberID != "" && c.MemberID != memberID {
			continue
		}
		if date != "" && c.Date != date {
			continue
		}
		if p.IsTrainer() && !trainerHwIDs[c.HwID] {
			continue
		}
		out = append(out, c)
	}
	return out, nil
}

// ---- 수업 기록(WorkoutLog, v1.4) ----

type WorkoutLogCreateRequest struct {
	MemberID  string            `json:"member_id"`
	TrainerID string            `json:"trainer_id"`
	BookingID string            `json:"booking_id,omitempty"`
	Date      string            `json:"date"`
	Title     string            `json:"title"`
	Exercises []domain.Exercise `json:"exercises"`
	CoachNote string            `json:"coach_note"`
}

// CreateWorkoutLog — 트레이너의 세션 기록(30초 기록, P29). 완료 처리 모달에서 선택 입력.
func (s *Service) CreateWorkoutLog(ctx context.Context, p Principal, req WorkoutLogCreateRequest) (*domain.WorkoutLog, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	trainerID := req.TrainerID
	if p.IsTrainer() {
		trainerID = p.UID // 본인 명의 강제
	}
	if trainerID == "" {
		return nil, errors.Join(errBadRequest, errors.New("trainer_id required"))
	}
	// owner 대행의 trainer_id 오타 방어는 booking_id 교차검증(아래)이 담당한다 — GetStaff 실존
	// 검증은 스태프 생성 API가 없는 v1 dev 흐름(비시딩)을 막아서 두지 않는다(P03 자문자답).
	mem, err := s.store.GetMember(ctx, p.CenterID, req.MemberID)
	if err != nil {
		return nil, err
	}
	if req.BookingID == "" {
		// booking 연결이 없으면 **담당 경계가 유일한 방어선**이다(v2.5). 종전엔 실존 확인만 하고
		// checkMemberScope를 부르지 않아, booking_id를 생략하는 것만으로 아래 교차검증 전체가
		// 비활성화됐다 — 다른 코치가 남의 회원에게 수업기록을 남길 수 있었고(감사 실측 200),
		// 회원 앱의 "수업 기록"엔 한 번도 본 적 없는 코치의 기록이 뜬다.
		if err := s.checkMemberScope(p, *mem); err != nil {
			return nil, err
		}
	} else {
		// booking_id가 있으면 아래 교차검증이 담당 경계보다 **정확한** 판정을 한다: 회원은 코치별로
		// 패스를 따로 가질 수 있어(앱 패스 스위처) mem.trainer_id(주담당)와 그 회차를 실제로 가르친
		// 코치가 다를 수 있다. 그 경우까지 checkMemberScope로 막으면 정상 기록이 거부된다.
		b, err := s.store.GetBooking(ctx, p.CenterID, req.BookingID)
		if err != nil {
			return nil, err
		}
		if b.MemberID != req.MemberID {
			return nil, errors.Join(errBadRequest, errors.New("booking_id가 member_id의 예약이 아니에요"))
		}
		if p.IsTrainer() && b.TrainerID != p.UID {
			return nil, ErrForbidden // 타 코치 예약에 기록 연결 금지(인가 위반 — 403 유지)
		}
		if b.TrainerID != trainerID {
			// owner 대행 시에도 기록 명의는 예약의 담당 코치여야 한다(입력 오류 — 400).
			return nil, errors.Join(errBadRequest, errors.New("trainer_id가 예약의 담당 코치와 달라요"))
		}
	}
	date := req.Date
	if date == "" {
		date = today()
	} else if _, err := time.Parse("2006-01-02", date); err != nil {
		// 형식 미검증 시 "2026-8-2" 같은 값이 저장돼 문자열 정렬·from 필터가 조용히 오염된다(P03).
		return nil, errors.Join(errBadRequest, errors.New("date는 YYYY-MM-DD 형식이어야 해요"))
	}
	title := req.Title
	if title == "" {
		title = "1:1 PT"
	}
	exercises := req.Exercises
	if exercises == nil {
		exercises = []domain.Exercise{}
	}
	wl := &domain.WorkoutLog{
		MemberID: req.MemberID, TrainerID: trainerID, BookingID: req.BookingID,
		Date: date, Title: title, Exercises: exercises, CoachNote: req.CoachNote,
	}
	id, err := s.store.CreateWorkoutLog(ctx, p.CenterID, wl)
	if err != nil {
		return nil, err
	}
	wl.ID = id
	return wl, nil
}

// ListWorkoutLogs — GET /v1/workout-logs?member=&from=. member=본인 강제(v1.1 스코프 패턴),
// trainer=본인 작성분만, owner=전체. from은 "YYYY-MM-DD" 이후(포함) 필터.
func (s *Service) ListWorkoutLogs(ctx context.Context, p Principal, memberQuery, from string) ([]domain.WorkoutLog, error) {
	memberID, err := memberScopeID(p, memberQuery)
	if err != nil {
		return nil, err
	}
	if from != "" {
		if _, err := time.Parse("2006-01-02", from); err != nil {
			return nil, errors.Join(errBadRequest, errors.New("from은 YYYY-MM-DD 형식이어야 해요"))
		}
	}
	list, err := s.store.ListWorkoutLogs(ctx, p.CenterID, memberID)
	if err != nil {
		return nil, err
	}
	out := []domain.WorkoutLog{}
	for _, wl := range list {
		if p.IsTrainer() && wl.TrainerID != p.UID {
			continue
		}
		if from != "" && wl.Date < from {
			continue
		}
		out = append(out, wl)
	}
	return out, nil
}

// ---- 결제(P19) ----

// paidAtClockSkew — 클라이언트가 보낸 납부 시각(installments[].paid_at)에 허용하는 미래 오차.
// 데스크 PC·브라우저 시계가 서버보다 몇 초~몇 분 앞선 것까지 거부하면 정상 입력이 랜덤하게
// 400이 된다 — 막으려는 것은 시계 오차가 아니라 "내일 받을 돈"을 오늘 수납으로 적는 것이다.
const paidAtClockSkew = 5 * time.Minute

type PaymentCreateRequest struct {
	MemberID     string               `json:"member_id"`
	PassID       string               `json:"pass_id"`
	Method       string               `json:"method"`
	Total        int                  `json:"total"`
	Installments []domain.Installment `json:"installments"`
	Channel      string               `json:"channel"`
}

func (s *Service) CreatePayment(ctx context.Context, p Principal, req PaymentCreateRequest) (*domain.Payment, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	// v1.5 검증 게이트(P04 — 종전엔 음수·유령 참조·남의 패스까지 전부 통과): 돈 기록의 무결성을
	// 어드민 폼 하나에 의존하지 않는다.
	if req.Total <= 0 {
		return nil, errors.Join(errBadRequest, errors.New("결제 금액은 0보다 커야 해요"))
	}
	if !domain.ValidPayMethod(req.Method) {
		return nil, errors.Join(errBadRequest, errors.New("결제 수단은 card|cash|transfer 중 하나여야 해요"))
	}
	pass, err := s.store.GetPass(ctx, p.CenterID, req.PassID)
	if err != nil {
		return nil, err
	}
	if pass.MemberID != req.MemberID {
		return nil, errors.Join(errBadRequest, errors.New("pass_id가 member_id 소유가 아니에요"))
	}
	if pass.Status == domain.PassStatusRefunded {
		return nil, errors.Join(errBadRequest, errors.New("환불 처리된 패스에는 결제를 기록할 수 없어요"))
	}
	if p.IsTrainer() && pass.TrainerID != p.UID {
		return nil, ErrForbidden // 조회와 대칭: 쓰기도 담당 패스만(P04 — 쓰기 스코프 비대칭 해소)
	}
	// 계약가 상한(v2.4, P12 감사 C1): 이 패스에 기록된 결제 총액이 계약가를 넘을 수 없다.
	// 중복 기록은 환불 지급액(실수납 기준)과 매출 집계(Σ Payment.Total)를 **함께** 부풀린다 —
	// 실측: 1,000,000 패스에 결제 2건 → 환불 1,550,000 / 550,000 패스에 5,500,000 오타 → 환불 5,445,000.
	// 도달 경로가 사람의 실수가 아니라 클라이언트 재시도(어드민 "결제만 재시도"가 서버 성공과
	// 응답 유실을 구분하지 못한다)라, 폼이 아니라 서버가 막아야 반복되지 않는다.
	// 패스당 1건으로 제한하지는 않는다 — 카드 일부 + 현금 일부처럼 나눠 기록하는 것은 정상
	// 영업이고, 상한은 "건수"가 아니라 "합계"에 건다.
	recorded, err := s.recordedPaymentTotal(ctx, p.CenterID, req.PassID)
	if err != nil {
		return nil, err
	}
	if recorded+req.Total > pass.PaidAmount {
		if recorded == 0 {
			return nil, errors.Join(errBadRequest,
				fmt.Errorf("결제 금액이 회원권 계약가(%d원)를 넘어요", pass.PaidAmount))
		}
		// 재시도 경로를 위한 문구: "이미 처리됐을 수 있다"가 응답을 잃은 어드민이 알아야 할 사실이다.
		return nil, errors.Join(errBadRequest,
			fmt.Errorf("이 회원권에 이미 %d원이 기록돼 있어요(계약가 %d원) — 앞선 결제가 이미 처리됐는지 확인해주세요",
				recorded, pass.PaidAmount))
	}
	if len(req.Installments) > 0 {
		sum := 0
		now := time.Now().UTC()
		for _, ins := range req.Installments {
			if ins.Amount <= 0 {
				return nil, errors.Join(errBadRequest, errors.New("분할 회차 금액은 0보다 커야 해요"))
			}
			if _, err := time.Parse("2006-01-02", ins.Due); err != nil {
				return nil, errors.Join(errBadRequest, errors.New("납부 기한(due)은 YYYY-MM-DD 형식이어야 해요"))
			}
			if ins.WaivedAt != nil {
				// waived는 환불 정산의 결과 상태 — 생성 시 선탑재하면 환불 없이 청구가 소멸된다(P05 통합검수).
				return nil, errors.Join(errBadRequest, errors.New("waived_at은 생성 시 지정할 수 없어요"))
			}
			if ins.PaidAt != nil && ins.PaidAt.After(now.Add(paidAtClockSkew)) {
				// 미래 납부는 존재할 수 없는 사실인데, 기록되는 순간 실수납(환불 기준액)에 즉시
				// 반영된다 — 아직 들어오지 않은 돈이 환불로 나간다(P12 감사 M5). waived_at을 막는
				// 것과 같은 이유: 클라이언트가 보낸 "결과 상태"를 서버가 검증 없이 믿지 않는다.
				return nil, errors.Join(errBadRequest, errors.New("납부 시각(paid_at)은 미래일 수 없어요"))
			}
			sum += ins.Amount
		}
		if sum != req.Total {
			return nil, errors.Join(errBadRequest,
				fmt.Errorf("분할 회차 합계(%d원)가 총액(%d원)과 달라요", sum, req.Total))
		}
	}
	pay := &domain.Payment{
		MemberID: req.MemberID, PassID: req.PassID, Method: req.Method, Total: req.Total,
		Installments: req.Installments, Channel: req.Channel,
	}
	// 쓰기 정규화(v2.28, P56 A3) — 일시불(installments 생략)은 nil로 들어오고, 스토어는 JSON
	// 왕복이라 한 번 null이면 문서에 **영구히** null이다. 형제 배열(Flags·Holds)은 생성 경로에서
	// 정규화하면서 여기만 빠져 있었다. 어드민 Members.tsx가 `pay.installments.filter`를 무가드로
	// 부르므로 null 1건이 회원 상세를 여는 순간 어드민 전체 폴백이다(P55 C-1과 같은 폭발 반경).
	normalizePaymentWire(pay)
	id, err := s.store.CreatePayment(ctx, p.CenterID, pay)
	if err != nil {
		return nil, err
	}
	pay.ID = id
	return pay, nil
}

// recordedPaymentTotal — 해당 패스에 이미 기록된 결제 총액(Σ Payment.Total). 계약가 상한
// 검사의 기준축을 매출 집계(revenueByMonth도 Total을 쓴다)와 같게 맞춘다 — 상한을 실수납으로
// 재면 "미납 회차만 잔뜩 적힌 중복 결제"가 매출만 부풀리며 통과한다.
func (s *Service) recordedPaymentTotal(ctx context.Context, centerID, passID string) (int, error) {
	pays, err := s.store.ListPaymentsByPass(ctx, centerID, passID) // 패스 것만(v2.38, P74)
	if err != nil {
		return 0, err
	}
	sum := 0
	for _, pay := range pays {
		sum += pay.Total
	}
	return sum, nil
}

func (s *Service) PayInstallment(ctx context.Context, p Principal, paymentID string, index int) (*domain.Payment, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	pay, err := s.store.GetPayment(ctx, p.CenterID, paymentID)
	if err != nil {
		return nil, err
	}
	// 여기엔 읽기 정규화(normalizePaymentWire)를 두지 않는다 — 바로 아래 인덱스 가드가
	// len(nil)==0으로 먼저 400을 내므로 installments가 null인 결제는 이 응답에 실릴 수 없다
	// (뮤테이션으로 확인한 등가 자리 — 두면 죽일 수 없는 코드가 된다, v2.28).
	if index < 0 || index >= len(pay.Installments) {
		return nil, errors.Join(errBadRequest, errors.New("installment index out of range"))
	}
	if pay.Installments[index].PaidAt != nil {
		return nil, errors.Join(errBadRequest, errors.New("이미 납부 처리된 회차예요")) // 멱등 — 납부 시각 증적 보존(v1.5)
	}
	if pay.Installments[index].WaivedAt != nil {
		return nil, errors.Join(errBadRequest, errors.New("환불로 청구가 종결된 회차예요"))
	}
	// **인프라 에러를 "조건 불성립"으로 삼키지 않는다**(P56). `err == nil`만 보면
	// 스토어 순단에 아래 가드가 **조용히 함께 꺼진다** — 방어가 약한 게 아니라 방어가
	// 사라지는 것이고, 로그에도 안 남는다. 부재(ErrNotFound)와 장애를 갈라, 장애면 멈춘다.
	// 납부는 되돌릴 수단이 없다(계약: 회차 취소 동사 없음) — 여기서 여는 비용이 가장 크다.
	if pass, err := s.store.GetPass(ctx, p.CenterID, pay.PassID); err == nil {
		if pass.Status == domain.PassStatusRefunded {
			return nil, errors.Join(errBadRequest, errors.New("환불 처리된 패스의 회차는 납부 처리할 수 없어요"))
		}
		if p.IsTrainer() && pass.TrainerID != p.UID {
			return nil, ErrForbidden // 쓰기 스코프: CreatePayment(v1.5)와 대칭 — 담당 패스만(P05 통합검수)
		}
	} else if !errors.Is(err, store.ErrNotFound) {
		return nil, err
	}
	now := time.Now().UTC()
	pay.Installments[index].PaidAt = &now
	if err := s.store.UpdatePayment(ctx, p.CenterID, pay); err != nil {
		return nil, err
	}
	return pay, nil
}

// passBelongsToTrainer — pass_id로 연결된 Pass.trainer_id가 호출자(p)와 일치하는지. Payment·
// Contract 둘 다 자체 trainer_id가 없어(엔티티에 없음) 연결된 Pass로 트레이너 소유를 판별한다
// (v1.1 정합 패치, 목록 필터링 전용 — checkTrainerOwnsPass와 달리 에러로 중단하지 않고 조용히
// 걸러내기 위해 bool을 반환한다).
func (s *Service) passBelongsToTrainer(ctx context.Context, p Principal, passID string) (bool, error) {
	if passID == "" {
		return false, nil
	}
	pass, err := s.store.GetPass(ctx, p.CenterID, passID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			return false, nil
		}
		return false, err
	}
	return pass.TrainerID == p.UID, nil
}

// ListPayments — GET /v1/payments?member=(결제 목록, 분할·미수 확인, v1.1 정합 패치). member=본인
// 강제, trainer=담당 회원 결제만(연결된 Pass.trainer_id로 판별), owner=전체.
func (s *Service) ListPayments(ctx context.Context, p Principal, memberQuery string) ([]domain.Payment, error) {
	memberID, err := memberScopeID(p, memberQuery)
	if err != nil {
		return nil, err
	}
	// 회원이 정해졌으면 그 회원 결제만 읽는다(v2.38, P74) — 앱 마이 탭이 회원마다 부르는 경로가
	// 센터 전체 결제를 읽지 않게. owner 무필터 조회만 전량이다.
	var all []domain.Payment
	if memberID != "" {
		all, err = s.store.ListPaymentsByMember(ctx, p.CenterID, memberID)
	} else {
		all, err = s.store.ListPayments(ctx, p.CenterID)
	}
	if err != nil {
		return nil, err
	}
	out := []domain.Payment{}
	for _, pay := range all {
		if memberID != "" && pay.MemberID != memberID {
			continue
		}
		if p.IsTrainer() {
			owns, err := s.passBelongsToTrainer(ctx, p, pay.PassID)
			if err != nil {
				return nil, err
			}
			if !owns {
				continue
			}
		}
		// 읽기 정규화(v2.28) — 쓰기만 고치면 이미 프로덕션에 있는 null 문서는 영원히 안 낫는다.
		// 결제는 PUT 경로가 없어 "다시 저장해서 고친다"가 성립하지 않으므로 읽기 쪽이 유일한 바닥이다.
		normalizePaymentWire(&pay)
		out = append(out, pay)
	}
	return out, nil
}

// ---- 전자계약(Contract, v1.1 정합 패치) ----
//
// 확정 플로우(계약 문서 하단): 추가 계약 = 새 Pass 발급(POST /v1/passes) → Contract 자동 생성(sent)
// → Payment 기록(분할 가능). 어드민 회원 상세에서 원스톱으로 처리된다.

type ContractCreateRequest struct {
	MemberID string `json:"member_id"`
	PassID   string `json:"pass_id"`
}

// buildContractForPass — POST /v1/passes 발급 시 함께 만들 계약(status=sent)을 **조립만** 한다
// (계약: "생성(발급 시 자동 생성 가능)" + 하단 확정 플로우). SentAt=발급 시각.
//
// 저장은 하지 않는다: 패스·원장·계약이 store.IssuePass 한 트랜잭션으로 함께 커밋돼야 하기
// 때문이다(P13 C3). PassID는 스토어가 새 패스 ID로 채운다.
func (s *Service) buildContractForPass(ctx context.Context, p Principal, pass *domain.Pass) (*domain.Contract, error) {
	now := time.Now().UTC()
	policy, err := s.store.GetPolicy(ctx, p.CenterID)
	if err != nil {
		return nil, err
	}
	// 서명 시점 요율 스냅샷(v1.5) — 정책 변경 소급 차단. EffectivePenaltyRate를 거치는 이유는
	// **회원이 서명하는 숫자와 실제 공제액이 같아야** 하기 때문이다(P14 C1): 종전엔 정책값을
	// 그대로 스냅샷했는데 환불은 RefundQuote가 상한으로 캡해, 30% 조항에 서명하고 10%만
	// 공제되는 계약서가 발행됐다.
	rate := policy.EffectivePenaltyRate()
	c := &domain.Contract{
		MemberID: pass.MemberID, PassID: pass.ID, Product: pass.Product,
		PaidAmount: pass.PaidAmount, Status: domain.ContractStatusSent, SentAt: &now, FirstSentAt: &now,
		PenaltyRate: &rate,
	}
	// P39(계약 v2.18): 발행 래치가 켜져 있으면 발급(=자동 send)도 Vars 스탬프를 시도한다.
	// 다만 확정 플로우상 결제 기록은 발급 **뒤**라(발급 → Payment 기록) 여기서는 결제 2키
	// (결제방법·납부일정)가 비어 전부-아니면-전무 가드가 통상 스킵을 고른다 — **첫 완전
	// 스탬프는 결제 기록 후 운영자의 (재)발송(SendContract)에서 찍히는 것이 정상 경로다.**
	// 그래도 구현해 두는 이유: "발급이 곧 send"인 이 경로만 스탬프에서 빼면 두 send 경로가
	// 다른 규칙을 갖게 되고, 스킵은 가드의 판정(정직하게 찍을 수 없음)이지 경로의 예외가
	// 아니어야 한다. 래치를 되돌리면 추가 스토어 읽기 없이 종전 경로 그대로다(latch-off
	// 불변 — 롤백 구성 픽스처로 고정. 배포 상태는 P48/v2.22부터 래치 ON).
	//
	// P42: 래치를 통과해도 버전은 시설 신고 상태가 고른다(reported/exempt 2종). unknown이면
	// 세 번째 스킵(contractSkipFacilityUnknown) — 모르는 상태로 문서를 만들지 않는다. 선택
	// 때 읽은 facility를 조립에 재사용한다(같은 문서 2회 읽기 사이에 저장이 끼는 창 제거).
	if contractStampLatchOn() {
		fac, err := s.store.GetFacility(ctx, p.CenterID)
		if err != nil {
			return nil, err
		}
		if ver, tpl, skip := contractTemplateForStatus(fac.ReportStatus); skip == contractSkipNone {
			vars, _, err := s.gatherContractVars(ctx, p.CenterID, c, pass, policy, fac, tpl.requiredVarKeys)
			if err != nil {
				return nil, err
			}
			if vars != nil {
				c.TemplateVersion, c.Vars = ver, vars
			}
		}
	}
	return c, nil
}

// CreateContract — POST /v1/contracts {member_id, pass_id}(수동 생성, 초안 draft). 발급과 동시에
// 자동 생성되는 경로는 buildContractForPass가 담당한다(v2.6부터 조립·저장 분리 — 저장은 IssuePass).
func (s *Service) CreateContract(ctx context.Context, p Principal, req ContractCreateRequest) (*domain.Contract, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	pass, err := s.store.GetPass(ctx, p.CenterID, req.PassID)
	if err != nil {
		return nil, err
	}
	if pass.MemberID != req.MemberID {
		return nil, errors.Join(errBadRequest, errors.New("pass_id가 member_id 소유가 아님"))
	}
	if err := s.checkTrainerOwnsPass(p, *pass); err != nil {
		return nil, err
	}
	if pass.Status == domain.PassStatusRefunded {
		return nil, errors.Join(errBadRequest, errors.New("환불 처리된 패스에는 계약을 만들 수 없어요"))
	}
	// 탈퇴 회원 차단(v2.11 후속 차단 목록의 누락 자리 — v2.17, P40). 탈퇴가 미서명 계약을
	// 전부 voided로 종결하는 순간, 아래 "패스당 유효 계약 1건" 가드는 voided를 세지 않으므로
	// 같은 패스에 새 draft를 다시 만들 수 있게 된다 — 서명 주체가 파기돼 영원히 미서명인
	// 계약이 방금 닫은 자리에서 재생산된다. send/sign은 가드가 필요 없다: 탈퇴 회원의 잔여
	// 계약은 전부 종단 상태(signed/voided)라 전이 규칙이 이미 막는다.
	mem, err := s.store.GetMember(ctx, p.CenterID, req.MemberID)
	if err != nil {
		return nil, err
	}
	if err := guardMemberNotWithdrawn(*mem, "계약을 만들 수 없어요"); err != nil {
		return nil, err
	}
	policy, err := s.store.GetPolicy(ctx, p.CenterID)
	if err != nil {
		return nil, err
	}
	rate := policy.EffectivePenaltyRate() // buildContractForPass와 같은 규약(P14 C1)
	c := &domain.Contract{
		MemberID: req.MemberID, PassID: req.PassID, Product: pass.Product,
		PaidAmount: pass.PaidAmount, Status: domain.ContractStatusDraft,
		PenaltyRate: &rate,
	}
	// 패스당 유효(비voided) 계약 1건 불변식(v1.5) — 중복 검사와 생성을 **한 트랜잭션**으로
	// (v2.15, P36 M2). read-then-create였을 때는 동시 2건이 각자 통과할 수 있었다: 유효 계약이
	// 둘이 되는 순간 refundBasis의 단일 스냅샷 가정(위약금율을 하나만 읽는다)이 깨진다.
	id, err := s.store.CreateContractGuarded(ctx, p.CenterID, c,
		func(existing []domain.Contract) error {
			for _, ec := range existing {
				if ec.PassID == req.PassID && ec.Status != domain.ContractStatusVoided {
					return errors.Join(errBadRequest, errors.New("이 회원권에는 이미 계약이 있어요"))
				}
			}
			return nil
		})
	if err != nil {
		return nil, err
	}
	c.ID = id
	return c, nil
}

// ListContracts — GET /v1/contracts?member=&status=(계약 목록, 어드민 계약확인, v1.1 정합 패치).
// member=본인 강제, trainer=담당 회원 계약만, owner=전체.
func (s *Service) ListContracts(ctx context.Context, p Principal, memberQuery, status string) ([]domain.Contract, error) {
	memberID, err := memberScopeID(p, memberQuery)
	if err != nil {
		return nil, err
	}
	if status != "" && !domain.ValidContractStatus(status) {
		return nil, errors.Join(errBadRequest, errors.New("status는 draft|sent|signed|voided 중 하나여야 해요"))
	}
	list, err := s.store.ListContracts(ctx, p.CenterID, memberID, status)
	if err != nil {
		return nil, err
	}
	if !p.IsTrainer() {
		return list, nil
	}
	out := []domain.Contract{}
	for _, c := range list {
		owns, err := s.passBelongsToTrainer(ctx, p, c.PassID)
		if err != nil {
			return nil, err
		}
		if owns {
			out = append(out, c)
		}
	}
	return out, nil
}

// SendContract — POST /v1/contracts/{id}/send(서명 요청 (재)발송). draft의 최초 발송이거나 sent
// 상태의 재발송을 허용한다(domain.CanTransitionContract). signed 이후에는 재발송할 수 없다.
//
// 전이 판정·환불 패스 가드·first_sent_at 한 번만 기록은 전부 store.TransitionContract의 mutate
// 안(트랜잭션 내부)이다(v2.15, P37). 종전의 "저장 직전 GetContract 재확인"(P03/v1.4.1)은
// 트랜잭션 밖이라 원리적으로 창을 못 닫았다 — 재발송이 서명과 경합하면 signed 문서를 sent
// 사본으로 덮어 signed_at·signer_ip(법적 증적)를 지울 수 있었다(P36 감사 H). 트랜잭션 밖에는
// 권한 판정만 남는다(PassID·MemberID는 불변 필드라 스냅샷 판정이 안전하다).
func (s *Service) SendContract(ctx context.Context, p Principal, id string) (*domain.Contract, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	c, err := s.store.GetContract(ctx, p.CenterID, id)
	if err != nil {
		return nil, err
	}
	if p.IsTrainer() {
		owns, err := s.passBelongsToTrainer(ctx, p, c.PassID)
		if err != nil {
			return nil, err
		}
		if !owns {
			return nil, ErrForbidden
		}
	}
	// P39(계약 v2.18): 발행 래치가 켜져 있으면 send가 Vars를 **(재)확정**한다 — §D ⑤ "send
	// 시점에 Vars를 채워 두고, 서명은 그것을 확정". 재발송도 매번 재확정한다(P39 결정 2):
	// 회원이 서명 화면에서 보는 것은 저장된 Vars 렌더이므로 재확정이어야 "본 것 = 서명한 것"
	// (D-4)이 유지되고, 배포 전 sent 잔존 계약도 재발송으로 Vars를 얻는다. 조립(스토어 읽기)은
	// 전부 트랜잭션 **밖**이다(ContractMutator 순수성 — mutate 안 Store 재호출 금지). 조립
	// 재료 중 계약 필드(Product·PaidAmount·PenaltyRate)는 생성 후 불변이라 스냅샷 c로 충분하다.
	// P42: 버전 선택은 발급 경로와 같은 2중 게이트다 — 래치(읽기 없음) → 시설 신고 상태
	// (reported/exempt → 각 변형, unknown → 스킵). buildContractForPass의 게이트 주석 참고.
	var stampVersion string
	var stampVars map[string]string
	if contractStampLatchOn() {
		fac, err := s.store.GetFacility(ctx, p.CenterID)
		if err != nil {
			return nil, err
		}
		if ver, tpl, skip := contractTemplateForStatus(fac.ReportStatus); skip == contractSkipNone {
			pass, err := s.store.GetPass(ctx, p.CenterID, c.PassID)
			if err != nil && !errors.Is(err, store.ErrNotFound) {
				return nil, err // NotFound는 패스 없는 레거시·픽스처 — 패스 유래 키만 결측으로 진행
			}
			vars, _, err := s.gatherContractVars(ctx, p.CenterID, c, pass, nil, fac, tpl.requiredVarKeys)
			if err != nil {
				return nil, err
			}
			if vars != nil {
				stampVersion, stampVars = ver, vars
			}
		}
	}
	now := time.Now().UTC()
	return s.store.TransitionContract(ctx, p.CenterID, id,
		func(fresh *domain.Contract, pass *domain.Pass) error {
			if err := domain.CanTransitionContract(fresh.Status, domain.ContractStatusSent); err != nil {
				return errors.Join(errBadRequest, err)
			}
			if pass != nil && pass.Status == domain.PassStatusRefunded {
				return errors.Join(errBadRequest, errors.New("환불 처리된 거래의 계약은 발송할 수 없어요"))
			}
			fresh.Status = domain.ContractStatusSent
			fresh.SentAt = &now
			if fresh.FirstSentAt == nil {
				fresh.FirstSentAt = &now // 최초 고지 시각은 한 번만(v1.5 — 재발송이 증적을 지우지 않게)
			}
			if stampVars != nil {
				// 재할당만 한다(ContractMutator 규약 — 포인터와 같은 이유로 맵도 제자리
				// 쓰기 금지: Memory의 얕은 사본 롤백이 오염된다). 캡처만 읽으므로
				// 트랜잭션 재시도에도 순수하다.
				fresh.TemplateVersion = stampVersion
				fresh.Vars = stampVars
			}
			// stampVars가 nil이면(시설 미선언·조립 불완전, 또는 래치를 되돌린 구성) 기존
			// 스탬프를 **건드리지 않는다**:
			// 이미 완전한 문서를 받아 본 회원의 열람물을, 나중의 조립 불가능해진 재발송이
			// 파괴하면 안 된다 — 마지막 완전 스탬프가 살아남는 것이 규약이다(계약 v2.18.
			// 이때 회원이 보는 문서는 그 마지막 스탬프 그대로이고, 서명도 그것을 봉인한다).
			return nil
		})
}

// SignContract — POST /v1/contracts/{id}/sign(v1.4, member 본인 전용). 자체서명(P27):
// 회원 앱에서 계약 내용 확인 + 동의 탭 → sent→signed 전이, signed_at·signer_ip는 서버가 기록.
// send가 확정해 둔 문서 스냅샷(template_version·vars)이 있으면 같은 트랜잭션에서 sha256으로
// 봉인한다(v2.18, P39 — §D ②). pdf_path는 §D (나) PDF 연동 시 채워질 자리로 남는다. 미서명
// 카운트(어드민 "해야 할 일")가 실제로 줄어들 수 있게 하는 여정의 종착 단계.
// 전이 판정·환불 패스 가드는 트랜잭션 안이다(v2.15, P37 — SendContract와 동일 구조): 환불
// 마감이 커밋된 뒤에는 어떤 서명도 성립하지 않고(해지된 거래의 사후 법적 서명 차단, P04 감사
// 실증), 반대로 서명이 먼저 커밋되면 환불의 무효화 스윕이 signed를 보존한다(CanVoidContract).
//
// signaturePNG(v2.21, P44) — 핸들러가 검증을 마친 자필 서명 PNG **원본 바이트**(없으면 nil —
// 구버전 클릭 동의 서명, 계속 유효). 있으면 signed_at·signer_ip와 같은 트랜잭션에서
// signature_png(정규 base64)·signature_sha256(원본 바이트의 해시)을 함께 기록한다. 내용 봉인
// SHA256과는 끝까지 분리된다(P44 결정 3) — 서명 이미지는 contractSeal 입력에 절대 안 들어간다.
func (s *Service) SignContract(ctx context.Context, p Principal, id, signerIP string, signaturePNG []byte) (*domain.Contract, error) {
	if !p.IsMember() || p.MemberID == "" {
		return nil, ErrForbidden
	}
	c, err := s.store.GetContract(ctx, p.CenterID, id)
	if err != nil {
		return nil, err
	}
	if c.MemberID != p.MemberID {
		return nil, ErrForbidden
	}
	// P44: 서명 이미지의 해시·정규 base64는 트랜잭션 **밖**에서 계산해 캡처한다(ContractMutator
	// 순수성 — 재시도에도 같은 값). 해시 입력은 원본 PNG 바이트다(클라이언트 base64 문자열이
	// 아니라) — 저장하는 base64도 수신 문자열 재사용이 아닌 바이트 재인코딩 정규형이라, 패딩·
	// 공백 변형이 저장값·해시를 흔들 수 없다.
	var sigB64, sigHash string
	if len(signaturePNG) > 0 {
		sum := sha256.Sum256(signaturePNG)
		sigHash = hex.EncodeToString(sum[:])
		sigB64 = base64.StdEncoding.EncodeToString(signaturePNG)
	}
	now := time.Now().UTC()
	return s.store.TransitionContract(ctx, p.CenterID, id,
		func(fresh *domain.Contract, pass *domain.Pass) error {
			if err := domain.CanTransitionContract(fresh.Status, domain.ContractStatusSigned); err != nil {
				return errors.Join(errBadRequest, err)
			}
			if pass != nil && pass.Status == domain.PassStatusRefunded {
				return errors.Join(errBadRequest, errors.New("환불 처리된 거래의 계약은 서명할 수 없어요"))
			}
			fresh.Status = domain.ContractStatusSigned
			fresh.SignedAt = &now
			fresh.SignerIP = signerIP
			// P44(계약 v2.21): 자필 서명이 있으면 서명 증적과 같은 트랜잭션에서 기록한다.
			// 재할당만 한다(ContractMutator 규약 — 캡처값 대입, 제자리 쓰기 없음). 없으면
			// 필드를 **건드리지 않는다** — 빈 값 덮어쓰기가 잔존값(손시딩·레거시)을 지우면
			// 안 된다(불완전 재발송이 마지막 스탬프를 보존하는 v2.18 규약과 같은 철학).
			if sigB64 != "" {
				fresh.SignaturePNG = sigB64
				fresh.SignatureSHA256 = sigHash
			}
			// P39(계약 v2.18): send가 확정해 둔 스냅샷을 서명과 **같은 트랜잭션**에서 봉인한다
			// (§D ② — 그래야 "서명된 순간의 내용"이다. {{계약 체결일}}이 Vars 밖(P39 결정 3)
			// 이라 signed_at 기록과 봉인 사이에 끼어들 보강 단계도 없다). Vars 없는 계약
			// (래치 OFF·레거시 — 요약 고지 서명)은 봉인하지 않는다: sha256 비어 있음 ⟺ 본문
			// 렌더 없이 진행된 서명이라는 정직한 신호(P39). 거짓 신호를 만들지 않는다.
			if fresh.TemplateVersion != "" && len(fresh.Vars) > 0 {
				fresh.SHA256 = contractSeal(fresh.TemplateVersion, fresh.Vars)
			}
			return nil
		})
}

// ---- 체형사진(P8·P37) ----

type BodyPhotoCreateRequest struct {
	MemberID    string `json:"member_id"`
	Pose        string `json:"pose"`
	Direction   string `json:"direction"`
	Date        string `json:"date"`
	StoragePath string `json:"storage_path"`
	Blurred     bool   `json:"blurred"`
}

// checkBodyPhotoAccess — P37: member=본인, trainer=담당만, owner=동의 유효할 때만
// (owner도 예외 없이 게이트되는 유일한 리소스 — §7 매트릭스: "owner 접근 불가, 단 동의 시 가능").
func (s *Service) checkBodyPhotoAccess(mem domain.Member, p Principal) error {
	switch {
	case p.IsMember():
		if mem.ID != p.MemberID {
			return ErrForbidden
		}
		return nil
	case p.IsTrainer():
		if mem.TrainerID != p.UID {
			return ErrForbidden
		}
		// **동의 검사가 여기 빠져 있었다.** 배포된 개인정보처리방침·민감정보 동의서는
		// 담당 코치에 대해서도 "동의가 유효한 동안에만 열람"이라고 적었는데, 코드는
		// owner만 검사했다. 사진 **파일**은 storage.rules가 코치에게도 동의를 걸어
		// 막고 있었으므로 새던 건 메타데이터(장수·날짜·포즈)지만, 그것도 고지와
		// 다르면 거짓 고지다(계약 문서가 이미 "남은 갭"으로 인정해 둔 자리).
		if !mem.Consent.SensitiveConsentValid() {
			return ErrForbidden
		}
		return nil
	case p.IsOwner():
		if !mem.Consent.SensitiveConsentValid() {
			return ErrForbidden
		}
		return nil
	}
	return ErrForbidden
}

// BodyPhotoMeta — 동의가 **유효하지 않은** 회원의 사진 목록을 스태프에게 줄 때의 원소(v2.28,
// P56 B1 완결). 열람은 잠그되 **파기에 필요한 최소**만 준다: 어느 사진(id)인지 사람이 알아볼
// 라벨(pose·direction·date)과, 휴지통 뷰를 위한 deleted_at. **storage_path·blurred는 없다** —
// 경로가 나가는 순간 이미지에 닿을 수 있고(서명 URL의 재료), 그러면 "열람 잠금"이 거짓이 된다.
//
// 왜 필요한가: DeleteBodyPhoto가 동의를 보지 않게 됐어도(B1) 목록이 403이면 스태프는 지울 id를
// 얻을 길이 없다 — "서버만 열린" 절반 수리다. 방침이 안내하는 경로("철회 후 데스크에 삭제 요청")는
// 데스크가 그 사진을 **가리킬 수 있어야** 실재한다. 키 집합은 테스트로 잠근다(BodyPhoto의 필드가
// 늘어도 여기로 새지 않는다 — 별도 타입인 이유).
type BodyPhotoMeta struct {
	ID        string     `json:"id"`
	MemberID  string     `json:"member_id"`
	Pose      string     `json:"pose"`
	Direction string     `json:"direction"`
	Date      string     `json:"date"`
	DeletedAt *time.Time `json:"deleted_at,omitempty"`
}

func bodyPhotoMetaOf(bp domain.BodyPhoto) BodyPhotoMeta {
	return BodyPhotoMeta{ID: bp.ID, MemberID: bp.MemberID, Pose: bp.Pose, Direction: bp.Direction, Date: bp.Date, DeletedAt: bp.DeletedAt}
}

// BodyPhotoListing — ListBodyPhotos의 결과. **둘 중 하나만** 채워진다: Locked면 Meta(잠긴 목록),
// 아니면 Full(계약 원본 BodyPhoto). 핸들러가 이 플래그로 응답 모양을 고른다 — 같은 엔드포인트가
// 동의 상태에 따라 원소 모양을 바꾸는 것이 계약이고(v2.28), 어드민은 회원의 consent로 어느 쪽인지
// 이미 안다(storage_path 키의 유무가 두 번째 판별자다).
type BodyPhotoListing struct {
	Locked bool
	Full   []domain.BodyPhoto
	Meta   []BodyPhotoMeta
}

// ListBodyPhotos — GET /v1/body-photos?member=&include_deleted=.
//
// 세 갈래(v2.28):
//   - 동의 유효(또는 회원 본인) → Full. 종전과 같다.
//   - 스태프 + 스코프 안 + 동의 **무효** → Locked=true, Meta만. 종전엔 403이었다(위 BodyPhotoMeta 주석).
//   - 스코프 밖 → 403(무변경). 동의를 안 본다는 것이 남의 회원을 본다는 뜻은 아니다.
//
// include_deleted는 **스태프 전용**이다. v2.14가 "30일 안에 복원"을 약속하는데 목록이 삭제분을
// 항상 걸러 어드민은 세션 휴지통("새로고침하면 사라져요")밖에 못 만들었다 — 삭제분(deleted_at 포함)을
// 주면 그 약속이 새로고침 뒤에도 참이 된다. 회원에게는 **403**이다(조용히 무시하지 않는다): 회원
// 화면에서 삭제분은 "즉시 사라진다"(v2.13)가 계약이라, 회원 앱이 이 파라미터를 보내는 순간 그것은
// 버그이고 버그는 크게 실패해야 보인다.
func (s *Service) ListBodyPhotos(ctx context.Context, p Principal, memberID string, includeDeleted bool) (BodyPhotoListing, error) {
	var out BodyPhotoListing
	if includeDeleted && !p.IsStaff() {
		return out, ErrForbidden
	}
	mem, err := s.store.GetMember(ctx, p.CenterID, memberID)
	if err != nil {
		return out, err
	}
	if err := s.checkBodyPhotoAccess(*mem, p); err != nil {
		// 스태프가 스코프 안에서 막힌 유일한 원인은 동의다(checkBodyPhotoAccess의 스태프 분기는
		// 스코프 → 동의 순서). 그 경우만 잠긴 목록으로 내리고, 나머지(스코프 밖·회원 타인)는 그대로 403.
		if !p.IsStaff() || s.checkMemberScope(p, *mem) != nil {
			return out, err
		}
		out.Locked = true
	}
	// 스케줄러가 없어(Cloud Scheduler API 미활성) 조회 시점에 센터 전체를 훑는다.
	// 실패해도 목록 조회를 막지 않는다 — 파기가 안 됐다고 사진을 못 보게 할 이유가 없다.
	s.sweepBodyPhotoPurge(ctx, p.CenterID)

	all, err := s.store.ListBodyPhotos(ctx, p.CenterID, memberID)
	if err != nil {
		return out, err
	}
	// 삭제 표시된 것은 **즉시 사라진다** — 유예는 되돌리기 위한 것이지 계속 보이라는 게 아니다.
	// 예외는 스태프의 include_deleted(휴지통 뷰)뿐이다.
	rows := make([]domain.BodyPhoto, 0, len(all))
	for _, bp := range all {
		if bp.IsDeleted() && !includeDeleted {
			continue
		}
		rows = append(rows, bp)
	}
	if out.Locked {
		out.Meta = make([]BodyPhotoMeta, 0, len(rows))
		for _, bp := range rows {
			out.Meta = append(out.Meta, bodyPhotoMetaOf(bp))
		}
		return out, nil
	}
	out.Full = rows
	return out, nil
}

// DeleteBodyPhoto — 체형사진 삭제(v2.13).
//
// **누가 눌렀느냐로 의미가 갈린다.**
//
//   - 회원 본인 = 정보주체의 삭제권 행사 → **즉시 완전 파기**. 배포된 개인정보처리방침이
//     "동의 철회, 삭제 요청 또는 탈퇴 시 지체 없이 파기"(민감정보)라고 약속했고,
//     계정 삭제 절차는 "정당한 사유가 없는 한 10일 이내"다. 30일간 복원 가능한 상태로
//     들고 있으면 그 약속이 거짓이 된다.
//   - 대표·코치 = 운영 오조작 → **소프트 삭제 + 유예**. 정보주체의 요청이 아니므로
//     보관 근거(원래 동의)가 그대로 살아 있고, 잘못 지운 사진은 그날의 몸이라 다시 못 찍는다.
//
// 두 경우 모두 회원·코치 화면에서는 **즉시 사라진다**.
//
// **동의(sensitive)는 보지 않는다**(v2.28, P56 B1) — DeleteInbody와 같은 판단이다: *"삭제는
// 동의 철회 이후에 더 필요한 동작이지, 동의를 전제로 하는 동작이 아니다."* 종전엔 열람용
// checkBodyPhotoAccess를 재사용해 회원이 동의를 철회하면 스태프 삭제가 403이었다. 그런데
// 배포된 개인정보처리방침이 안내하는 경로가 바로 그것이다 — *"철회 후 데스크에 삭제 요청"*.
// 열람을 막는 게이트가 파기까지 막으면, 철회한 회원의 사진은 30일 유예 스윕이 돌 때까지
// 아무도 지울 수 없고 방침의 "지체 없이"가 거짓이 된다. 열람(ListBodyPhotos)·복원(Restore)은
// 여전히 동의 게이트를 지난다 — 여기서 푸는 것은 **파기 동사 하나**뿐이다.
//
// 스코프는 그대로다(checkMemberScope: owner=전체, trainer=담당만, member=본인만). 동의를 안
// 본다는 것이 남의 회원 사진을 지울 수 있다는 뜻은 아니다.
func (s *Service) DeleteBodyPhoto(ctx context.Context, p Principal, id string) (*domain.BodyPhoto, error) {
	bp, err := s.store.GetBodyPhoto(ctx, p.CenterID, id)
	if err != nil {
		return nil, err
	}
	mem, err := s.store.GetMember(ctx, p.CenterID, bp.MemberID)
	if err != nil {
		return nil, err
	}
	if err := s.checkMemberScope(p, *mem); err != nil {
		return nil, err
	}
	if bp.IsDeleted() {
		// 이미 지운 걸 다시 지우는 건 오류가 아니다 — 재시도가 막히면 안 된다.
		return bp, nil
	}

	if p.IsMember() {
		if err := s.purgeBodyPhoto(ctx, p.CenterID, *bp); err != nil {
			return nil, err
		}
		return bp, nil
	}

	now := time.Now().UTC()
	bp.DeletedAt = &now
	if err := s.store.SaveBodyPhoto(ctx, p.CenterID, bp); err != nil {
		return nil, err
	}
	return bp, nil
}

// RestoreBodyPhoto — 유예 안에서 되돌린다(스태프 전용).
//
// 회원 경로에는 복원이 없다 — 회원의 삭제는 즉시 파기라 되돌릴 대상이 남지 않는다.
func (s *Service) RestoreBodyPhoto(ctx context.Context, p Principal, id string) (*domain.BodyPhoto, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	bp, err := s.store.GetBodyPhoto(ctx, p.CenterID, id)
	if err != nil {
		return nil, err
	}
	mem, err := s.store.GetMember(ctx, p.CenterID, bp.MemberID)
	if err != nil {
		return nil, err
	}
	if err := s.checkBodyPhotoAccess(*mem, p); err != nil {
		return nil, err
	}
	if !bp.IsDeleted() {
		return bp, nil
	}
	if bp.PurgeDue(time.Now().UTC()) {
		// 파기 기한이 지난 걸 되살리면 "30일 뒤 파기"가 거짓이 된다.
		return nil, errors.Join(errBadRequest, errors.New("파기 기한이 지난 사진이에요 — 복원할 수 없어요"))
	}
	bp.DeletedAt = nil
	if err := s.store.SaveBodyPhoto(ctx, p.CenterID, bp); err != nil {
		return nil, err
	}
	return bp, nil
}

// purgeBodyPhoto — 완전 파기. **Storage를 먼저, 메타를 나중에.**
//
// 순서가 뒤바뀌면 오브젝트가 기록 없이 버킷에 영원히 남는다 — 지웠다는 사실조차
// 추적할 수 없다. Storage 삭제가 실패하면 메타를 남겨 다음 훑기에서 다시 시도한다.
func (s *Service) purgeBodyPhoto(ctx context.Context, centerID string, bp domain.BodyPhoto) error {
	if path, ok := ownedBodyPhotoPath(bp); ok {
		if _, err := s.media.DeleteObjects(ctx, []string{path}); err != nil {
			return err
		}
	}
	return s.store.DeleteBodyPhoto(ctx, centerID, bp.ID)
}

// ownedBodyPhotoPath — 파기로 지울 파일 경로. **그 회원의 체형사진 폴더 안**일 때만 돌려준다(v2.38, P74
// 감사 후속). 생성 경로는 v2.38부터 400으로 막지만 그 전에 저장된 레코드가 남의 경로(`staff/photos/…`
// 등 — 사진 URL로 노출되는 이름)를 가리키면, 파기(회원 즉시 삭제·30일 유예 뒤·탈퇴)가 **남의 파일을
// 지우는 원시 연산**이 된다. 폴더 밖이면 파일은 두고(로그 한 줄) 메타만 지운다 — 그 파일은 버킷
// 대조(service_body_photo_reconcile — `members/{id}/body/` 아래만 나열한다)의 범위 밖이라 그대로 남고,
// 주인(다른 회원·스태프 사진)의 수명 주기를 따른다.
func ownedBodyPhotoPath(bp domain.BodyPhoto) (string, bool) {
	if bp.StoragePath == "" {
		return "", false
	}
	if !domain.BodyPhotoPathOwnedBy(bp.StoragePath, bp.MemberID) {
		log.Printf("purge: 체형사진 %s의 storage_path가 회원(%s) 폴더 밖이라 파일은 지우지 않아요: %q",
			bp.ID, bp.MemberID, bp.StoragePath)
		return "", false
	}
	return bp.StoragePath, true
}

// bodyPhotoPurgeBatch — 한 번 훑을 때 파기하는 최대 건수. 조회 요청에 얹혀 도는
// 작업이라 응답이 눈에 띄게 느려지면 안 된다 — 남은 건 다음 조회가 이어서 지운다.
const bodyPhotoPurgeBatch = 25

// sweepBodyPhotoPurge — 유예가 지난 사진을 실제로 파기한다.
//
// **스케줄러가 없어서 조회에 얹었다.** Cloud Scheduler API가 프로젝트에 활성화돼
// 있지 않고 서버에 주기 작업도 없다 — 그 상태로 "30일 뒤 삭제"를 약속하면 지켜지지
// 않는다. 회원·코치·대표 누구의 조회든 센터 전체를 훑으므로, 앱을 쓰는 한 돈다.
//
// 정식 스케줄러가 붙으면 `POST /v1/maintenance/purge`가 같은 일을 한다 — 그때
// 이 호출을 빼는 게 아니라 **둘 다 두는 게 맞다**(스케줄러가 죽어도 바닥이 남는다).
func (s *Service) sweepBodyPhotoPurge(ctx context.Context, centerID string) {
	// 읽기 요청에 얹힌 부수 작업이 요청의 **인질이 되지도, 인질로 잡지도** 않게 한다.
	// - WithoutCancel: 호출한 조회가 끝나거나 클라이언트가 끊어도 스윕은 완주한다. 요청 ctx에
	//   묶어두면 파기가 매번 중도 취소되고, 그 취소 에러가 실제 장애와 구분 안 되는 ERROR
	//   로그로 쌓인다(조회 하나 끊길 때마다 로그 오염).
	// - 3초 자체 예산: GCS가 느려도 여기서 끝난다.
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 3*time.Second)
	defer cancel()
	due, err := s.store.ListBodyPhotosPendingPurge(
		ctx, centerID, time.Now().UTC().Add(-domain.BodyPhotoPurgeAfter), bodyPhotoPurgeBatch)
	if err != nil {
		// 실패를 삼키면 30일 파기 약속이 조용히 안 지켜진다 — 조회는 막지 않되 로그는 남긴다.
		// 예산 소진(DeadlineExceeded)은 장애가 아니라 설계된 중단이라 로그를 아낀다.
		if !errors.Is(err, context.DeadlineExceeded) {
			log.Printf("body photo purge sweep: list failed: center=%s: %v", centerID, err)
		}
		return
	}
	for _, bp := range due {
		// 한 건이 실패해도 나머지는 지운다 — Storage 권한 문제로 전부 막히면 안 된다.
		if err := s.purgeBodyPhoto(ctx, centerID, bp); err != nil {
			if errors.Is(err, context.DeadlineExceeded) {
				return // 예산 소진 — 남은 건은 다음 조회가 이어서 처리한다(멱등).
			}
			log.Printf("body photo purge sweep: purge failed: center=%s photo=%s: %v", centerID, bp.ID, err)
		}
	}
}

// PurgeBodyPhotos — 명시적 파기 훑기(대표 전용). Cloud Scheduler가 붙을 자리.
func (s *Service) PurgeBodyPhotos(ctx context.Context, p Principal) (int, error) {
	if !p.IsOwner() {
		return 0, ErrForbidden
	}
	due, err := s.store.ListBodyPhotosPendingPurge(
		ctx, p.CenterID, time.Now().UTC().Add(-domain.BodyPhotoPurgeAfter), bodyPhotoPurgeBatch)
	if err != nil {
		return 0, err
	}
	n := 0
	for _, bp := range due {
		if err := s.purgeBodyPhoto(ctx, p.CenterID, bp); err == nil {
			n++
		}
	}
	return n, nil
}

// CreateBodyPhoto — 저장 전 sensitive consent 필수(P8 불변식5, 403 매핑은 errBadRequest로 400 처리 —
// "동의 없음"은 클라이언트 입력 문제로 취급, 인가 실패(ErrForbidden)와 구분).
func (s *Service) CreateBodyPhoto(ctx context.Context, p Principal, req BodyPhotoCreateRequest) (*domain.BodyPhoto, error) {
	mem, err := s.store.GetMember(ctx, p.CenterID, req.MemberID)
	if err != nil {
		return nil, err
	}
	// 쓰기도 읽기와 같은 스코프를 지켜야 한다(P08). 종전엔 동의 검사만 하고 스코프를 보지 않아,
	// 인증만 된 사용자면 **누구의 체형사진이든 기록**할 수 있었다(다른 회원인 척, 담당 아닌
	// 트레이너도). 목록(ListBodyPhotos)은 checkBodyPhotoAccess로 막고 있어 읽기/쓰기가 비대칭이었다.
	// 체형사진은 계약 P8이 민감정보로 분류한 데이터라 대칭이 아니면 안 된다.
	if err := s.checkBodyPhotoAccess(*mem, p); err != nil {
		return nil, err
	}
	if !mem.Consent.SensitiveConsentValid() {
		return nil, errors.Join(errBadRequest, errors.New("동의(sensitive)가 없거나 철회되어 저장할 수 없음(P8)"))
	}
	// pose 슬러그 검증(v2.10). 종전엔 **무검증**이라 무엇이든 저장됐다 — pose는 Storage 파일명
	// `{date}-{pose}-{direction}-{epochMs}.jpg`의 조각이라 하이픈·슬래시가 섞이면 파일명 파싱
	// (고스트가 직전 사진을 고르는 epochMs 타이브레이커)이 모호해지고 경로 세그먼트가 깨진다.
	// 레거시 4종(stand/tpose/fold/ohsquat)은 이 규칙을 통과하므로 비파괴다.
	if !domain.ValidPoseKey(req.Pose) {
		return nil, errors.Join(errBadRequest,
			errors.New("pose는 영소문자·숫자·밑줄 1~24자여야 해요"))
	}
	// storage_path가 비면 "메타데이터는 있는데 가리키는 파일이 없는" 레코드가 남는다 —
	// 타임라인이 그 자리에서 영구히 실패 타일을 그린다(삭제 API도 없다).
	if strings.TrimSpace(req.StoragePath) == "" {
		return nil, errors.Join(errBadRequest, errors.New("storage_path가 비어 있어요"))
	}
	// storage_path는 **이 회원의 폴더** 안이어야 한다(v2.38, P74). 종전엔 "비어 있지 않은가"만 봐서,
	// 레코드의 소유(member_id)는 스코프로 지키면서 그 레코드가 **가리키는 파일**은 임의 문자열을
	// 받았다 — 남의 경로를 가리키는 메타가 생기면 목록이 깨지고, 소프트 삭제 뒤 파기(purgeBodyPhoto)가
	// 남의 파일을 대상으로 DeleteObjects를 시도한다. 접두사는 storage.rules와 앱(BodyPhotoStoragePath)이
	// 공유하는 규약 그대로: members/{memberId}/body/{fileName}.
	if !domain.BodyPhotoPathOwnedBy(req.StoragePath, req.MemberID) {
		return nil, errors.Join(errBadRequest, errors.New("storage_path는 이 회원의 체형사진 폴더(members/{member_id}/body/) 안이어야 해요"))
	}
	// date·direction 검증(v2.37, P73 — CreateInbody v2.9와 같은 규칙). 종전엔 둘 다 무검증이라
	// 형식이 깨진 날짜 한 건이 회원 앱 타임라인 전체를 실패로 접었다(앱은 DateTime.parse가
	// 던지는 예외를 목록 단위로 잡는다). 앱 자체 업로드는 항상 KST 오늘을 보내므로 정상 경로엔
	// 영향이 없고, 직접 호출·마이그레이션·수기 편집만 여기서 막힌다.
	if _, err := time.Parse("2006-01-02", req.Date); err != nil {
		return nil, errors.Join(errBadRequest, errors.New("date는 YYYY-MM-DD 형식이어야 해요"))
	}
	if req.Date > today() {
		return nil, errors.Join(errBadRequest, errors.New("미래 날짜의 체형사진은 저장할 수 없어요"))
	}
	switch req.Direction {
	case domain.DirFront, domain.DirSide, domain.DirBack:
	default:
		return nil, errors.Join(errBadRequest, errors.New("direction은 front|side|back 중 하나여야 해요"))
	}
	bp := &domain.BodyPhoto{
		MemberID: req.MemberID, Pose: req.Pose, Direction: req.Direction,
		Date: req.Date, StoragePath: req.StoragePath, Blurred: req.Blurred,
	}
	id, err := s.store.CreateBodyPhoto(ctx, p.CenterID, bp)
	if err != nil {
		return nil, err
	}
	bp.ID = id
	return bp, nil
}

// ---- 인바디(P8) ----

type InbodyCreateRequest struct {
	MemberID string  `json:"member_id"`
	Date     string  `json:"date"`
	Weight   float64 `json:"weight"`
	SMM      float64 `json:"smm"`
	BFM      float64 `json:"bfm"`
	PBF      float64 `json:"pbf"`
	VFL      float64 `json:"vfl"`
	BMR      float64 `json:"bmr"`
}

func (s *Service) ListInbody(ctx context.Context, p Principal, memberID string) ([]domain.Inbody, error) {
	mem, err := s.store.GetMember(ctx, p.CenterID, memberID)
	if err != nil {
		return nil, err
	}
	if err := s.checkMemberScope(p, *mem); err != nil {
		return nil, err
	}
	return s.store.ListInbody(ctx, p.CenterID, memberID)
}

func (s *Service) CreateInbody(ctx context.Context, p Principal, req InbodyCreateRequest) (*domain.Inbody, error) {
	mem, err := s.store.GetMember(ctx, p.CenterID, req.MemberID)
	if err != nil {
		return nil, err
	}
	// 체형사진과 같은 이유로 쓰기에도 스코프를 건다(P08) — 인바디도 P8 민감정보다.
	if err := s.checkMemberScope(p, *mem); err != nil {
		return nil, err
	}
	if !mem.Consent.SensitiveConsentValid() {
		return nil, errors.Join(errBadRequest, errors.New("동의(sensitive)가 없거나 철회되어 저장할 수 없음(P8)"))
	}
	// 날짜 검증(v2.5). 여기만 검증이 없어 "2026-8-2" 같은 값이 그대로 저장됐고, 회원 앱은 그
	// 레코드를 파싱하다 던져 **기록 탭 세 개가 통째로** 죽었다(운동·인바디·체형). 앱에 스킵
	// 가드를 넣었지만 그건 불량 데이터를 감출 뿐이라 그 인바디는 회원에게 영영 안 보인다 —
	// 들어오는 자리에서 막는 게 맞다. CreateWorkoutLog·ListHomeworks와 같은 문장을 쓴다.
	if _, err := time.Parse("2006-01-02", req.Date); err != nil {
		return nil, errors.Join(errBadRequest, errors.New("date는 YYYY-MM-DD 형식이어야 해요"))
	}
	// 미래 측정일 거부(v2.9). 아직 하지 않은 측정은 존재할 수 없는 사실인데, 저장되는 순간
	// 목록의 맨 앞(최신)이 되어 앱 차트의 마지막 점 + "직전 대비 증감"의 기준이 된다 —
	// 결제의 미래 paid_at을 막는 것과 같은 이유다(클라이언트가 보낸 "사실"을 검증 없이 믿지 않는다).
	// 기준은 센터 타임존(KST) 오늘 — 날짜 문자열 비교라 시각 오차가 개입하지 않는다.
	if req.Date > today() {
		return nil, errors.Join(errBadRequest, errors.New("측정일은 미래일 수 없어요"))
	}
	// 같은 회원·같은 날 중복 차단(v2.9). 인바디는 하루 1회 측정이 전제이고, 2건이 있으면 그날의
	// 점이 둘로 갈려 "직전 대비 증감"이 어느 쪽 기준인지 알 수 없게 된다. 회원 셀프 입력에서
	// 실제로 흔한 사고는 저장 성공 응답을 놓치고 한 번 더 누르는 것이라, 막지 않으면 중복이
	// 기본값이 된다.
	//
	// 한계(계약 갭): 쓰기 직전 읽기 1회라 **동시 요청 경합은 남는다** — 같은 순간 두 요청이
	// 들어오면 둘 다 통과할 수 있다. 완전 차단은 (회원,날짜) 합성 문서 ID로 upsert를 하거나
	// 트랜잭션을 도입해야 하는데(hwChecks가 쓰는 방식), 그건 컬렉션 ID 체계 변경이라 기존
	// 문서 마이그레이션이 따라온다. v1 실사용(회원이 손으로 누르는 연타)에는 이걸로 충분하다.
	existing, err := s.store.ListInbody(ctx, p.CenterID, req.MemberID)
	if err != nil {
		return nil, err
	}
	for _, e := range existing {
		if e.Date == req.Date {
			// 문구는 호출자가 **실제로 할 수 있는 행동**을 지시해야 한다(P18 검증 지적).
			// 회원은 자기 셀프 기록만 지울 수 있다(DeleteInbody의 Source 가드) — 기존 기록이
			// 센터 입력분인데 "지우고 다시"라고 하면 403으로 가는 길을 안내하는 셈이다.
			if p.IsMember() && e.Source != domain.InbodySourceMemberSelf {
				return nil, errors.Join(ErrConflict,
					fmt.Errorf("%s 기록은 센터에서 입력한 거예요 — 정정이 필요하면 담당 코치에게 요청해주세요", req.Date))
			}
			return nil, errors.Join(ErrConflict,
				fmt.Errorf("%s 인바디 기록이 이미 있어요 — 기존 기록을 지우고 다시 저장해주세요", req.Date))
		}
	}
	rec := &domain.Inbody{
		MemberID: req.MemberID, Date: req.Date, Weight: req.Weight, SMM: req.SMM,
		BFM: req.BFM, PBF: req.PBF, VFL: req.VFL, BMR: req.BMR,
	}
	// 값 검증(v2.9). 종전엔 요청의 6개 숫자를 **한 번도 보지 않고** 그대로 저장했다 —
	// 정정 수단이 DELETE 하나뿐이라(PUT 없음) 들어오는 자리에서 막는 게 유일하게 값싼 방어다.
	if err := rec.Validate(); err != nil {
		return nil, err
	}
	// source는 요청이 아니라 Principal로 판정한다(계약 v2.9). 이 값이 곧 삭제 권한의 근거라
	// (회원은 member_self만 지울 수 있다) 클라이언트가 정할 수 있으면 안 된다.
	if p.IsMember() {
		rec.Source = domain.InbodySourceMemberSelf
	} else {
		rec.Source = domain.InbodySourceStaff
	}
	id, err := s.store.CreateInbody(ctx, p.CenterID, rec)
	if err != nil {
		return nil, err
	}
	rec.ID = id
	return rec, nil
}

// DeleteInbody — DELETE /v1/inbody/{id}(v2.9). 오입력을 되돌리는 **유일한** 수단이다.
//
// PUT을 만들지 않은 이유: 삭제 후 재입력이면 충분하고(같은 날짜 재생성은 중복 차단에 걸리지
// 않는다 — 원본이 이미 사라졌으므로), API 면적이 절반이다. 인바디는 6개 숫자짜리 레코드라
// 부분 수정의 이점이 없다.
//
// 권한: 스코프(checkMemberScope)를 통과한 뒤, **회원 본인은 자기가 넣은 기록(source=
// "member_self")만** 지울 수 있다. 코치가 기기 측정값을 옮겨 적은 기록까지 회원이 지울 수
// 있으면 마음에 안 드는 수치를 없애 상담 근거 자체가 사라진다. v2.9 이전 레코드(source="")도
// 같은 이유로 회원 삭제 대상이 아니다 — "본인이 넣었다"는 근거가 없다.
//
// 동의(sensitive)는 보지 않는다. 삭제는 동의 철회 이후에 더 필요한 동작이지, 동의를 전제로
// 하는 동작이 아니다(생성만 P8 게이트를 지난다).
func (s *Service) DeleteInbody(ctx context.Context, p Principal, id string) error {
	rec, err := s.store.GetInbody(ctx, p.CenterID, id)
	if err != nil {
		return err
	}
	mem, err := s.store.GetMember(ctx, p.CenterID, rec.MemberID)
	if err != nil {
		return err
	}
	if err := s.checkMemberScope(p, *mem); err != nil {
		return err
	}
	if p.IsMember() && rec.Source != domain.InbodySourceMemberSelf {
		return ErrForbidden
	}
	return s.store.DeleteInbody(ctx, p.CenterID, id)
}

// ---- 직원 ----

// CreateStaff — POST /v1/staff(owner 전용). 스태프 온보딩의 세 조각을 한 요청으로 묶는다:
// ① 로그인 계정(Firebase 이메일) 확보 ② Staff 레코드 ③ UserIndex(uid → role·center_id).
// 종전엔 이 경로가 없어 owner 외 전원을 Firestore 콘솔에서 손으로 심어야 했고, SetOffdays·
// UpdateStaffProfile이 GetStaff 선행이라 "이미 있는 스태프 수정"만 가능했다.
//
// v2.36: 최초 비밀번호를 **응답에 담는다**(StaffCreated.InitialPassword). 종전 설계는 난수를
// 걸고 어드민 프론트가 sendPasswordResetEmail을 보내는 것이었는데, 메일이 스팸함으로 가거나
// 도메인 메일이 막힌 헬스장에서 초대가 통째로 멈췄다. 이제 관리자가 화면에서 값을 읽어 구두로
// 전달할 수 있고, 재설정 메일 경로는 **그대로 남아 있다**(Settings.tsx 초대 모달·Login.tsx).
//
// StaffCreated — *domain.Staff 임베딩이라 JSON이 종전과 **같은 평평한 모양**을 유지한다
// (기존 필드 전부 최상위 + initial_password 한 칸 추가). 구버전 클라이언트가 그대로 파싱된다.
type StaffCreated struct {
	*domain.Staff
	// 새로 만든 계정에만 채운다. 빈 값 = 이미 있던 계정(재초대·재고용)이라 그 사람이 정한
	// 비밀번호가 살아 있다는 뜻이다 — 기본값을 적으면 관리자가 틀린 값을 불러 준다.
	InitialPassword string `json:"initial_password,omitempty"`
}

func (s *Service) CreateStaff(ctx context.Context, p Principal, req domain.StaffCreate) (*StaffCreated, error) {
	if !p.IsOwner() {
		return nil, ErrForbidden // 급여(payout)가 붙는 레코드다 — 트레이너의 동료·자기 생성 금지(P13)
	}
	req.Normalize()
	if err := req.Validate(); err != nil {
		return nil, err
	}
	// 계정 확보는 검증 통과 후에만 — 오타 하나로 Firebase에 고아 계정이 쌓이지 않게 한다.
	// 이미 그 이메일의 계정이 있으면 uid를 재사용한다(재초대: 기존 비밀번호·로그인 유지).
	uid, created, err := s.users.EnsureUser(ctx, req.Email)
	if err != nil {
		return nil, err
	}
	// 새로 만든 계정에만 최초 비밀번호를 안내한다(CenterCreated.InitialPassword와 같은 규약).
	initialPW := ""
	if created {
		initialPW = s.cfg.InitialStaffPassword
	}
	if existing, err := s.store.GetStaff(ctx, p.CenterID, uid); err == nil {
		if existing.IsActive() {
			// 덮어쓰지 않는다 — 이름·색·정산·휴무·프로필이 리셋되는 사고가 재초대 한 번으로 일어난다.
			return nil, errors.Join(ErrConflict, errors.New("이미 등록된 스태프예요"))
		}
		// 퇴사자는 이 판정에서 제외한다(계약 v2.0): 409로 막으면 **재고용이 영구 차단된다**
		// (같은 이메일 = 같은 Firebase 계정 = 같은 uid라 다른 경로가 없다). 재초대는 곧 복직이다.
		//
		// 재고용은 계정이 이미 있으므로 created=false → initialPW="" 다. 복직자는 자기가 쓰던
		// 비밀번호로 그대로 들어온다(퇴사 때 EnableUser로 잠금만 풀린다).
		rehired, err := s.rehireStaff(ctx, p, existing, req)
		if err != nil {
			return nil, err
		}
		return &StaffCreated{Staff: rehired, InitialPassword: initialPW}, nil
	} else if !errors.Is(err, store.ErrNotFound) {
		return nil, err
	}
	// 회원으로 연결된 계정을 스태프로 승격하면 한 uid가 두 역할을 갖는다 — UserIndex는 uid당
	// 1건이라 role이 덮이는 순간 그 사람의 회원 앱(내 패스·예약)이 통째로 잠긴다. 계정 분리를
	// 요구하고 여기서 막는다.
	if idx, err := s.store.GetUserIndex(ctx, uid); err == nil {
		if idx.Role == domain.RoleMember {
			return nil, errors.Join(ErrConflict, errors.New("이미 회원으로 연결된 계정이에요"))
		}
		// 교차 센터 가드(Phase A) — 종전 주석은 "다른 센터의 스태프 uid는 v1 단일 센터
		// 전제상 발생하지 않는다"였다. 센터 생성 API가 생긴 순간 그 전제가 깨진다: 다른
		// 센터에 연결된 이메일을 초대하면 인덱스가 이 센터로 덮여 **그 사람의 원래 센터
		// 접근이 통째로 사라진다**(로그인은 되는데 남의 센터로 떨어지는 사고).
		if idx.CenterID != p.CenterID {
			return nil, errors.Join(ErrConflict,
				errors.New("이미 다른 센터에 연결된 계정이에요 — 센터마다 다른 이메일을 써주세요"))
		}
	} else if !errors.Is(err, store.ErrNotFound) {
		return nil, err
	}

	color := req.Color
	if color == "" {
		existing, err := s.store.ListStaff(ctx, p.CenterID)
		if err != nil {
			return nil, err
		}
		used := make([]string, 0, len(existing))
		for _, st := range existing {
			used = append(used, st.Color)
		}
		color = domain.PickStaffColor(used) // 색이 겹치면 스케줄 그리드에서 사람 구분이 안 된다
	}
	payout := domain.DefaultPayout()
	if req.Payout != nil {
		payout = *req.Payout
	}
	st := &domain.Staff{
		UID: uid, Role: req.Role, Name: req.Name, Email: req.Email, Color: color, Payout: payout,
		Offdays: []string{},               // 직렬화 계약: 항상 배열
		Status:  domain.StaffStatusActive, // v2.0 — 신규 스태프는 항상 재직
	}
	st.Profile.Normalize() // 빈 프로필도 배열은 [](어드민 specialties.map 크래시 방지)

	// 인덱스를 먼저 쓴다. 두 쓰기를 묶는 트랜잭션이 없어서(JoinApprove와 같은 한계) 순서가
	// 복구 가능성을 가른다: 인덱스만 남은 상태는 같은 이메일로 재호출하면 그대로 이어서
	// 완성되지만(EnsureUser가 uid를 재사용), Staff만 남은 상태는 위의 409에 걸려 영영 막힌다.
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{UID: uid, Role: req.Role, CenterID: p.CenterID}); err != nil {
		return nil, err
	}
	if err := s.store.SaveStaff(ctx, p.CenterID, st); err != nil {
		return nil, err
	}
	return &StaffCreated{Staff: st, InitialPassword: initialPW}, nil
}

// ListStaff — 본인 급여(payout)만 보이고 타인 급여는 가린다(P13: 트레이너가 타인 매출을 보면 안 됨).
//
// v2.0: **inactive 스태프도 계속 반환한다**. 이름 해석을 잃으면 3계층의 uid 참조 지점이 원시
// uid·빈 문자열로 붕괴한다(회원 목록이 "미배정"으로 거짓말하고, 스케줄 그리드는 이름 자리에
// uid를 찍는다). 필터는 클라이언트가 status로 한다. 다만 role=member 응답에선 퇴사자의
// profile을 빈 객체로 마스킹한다 — 이름은 남기되 퇴사자 이력을 회원에게 계속 홍보하지는 않는다.
func (s *Service) ListStaff(ctx context.Context, p Principal) ([]domain.Staff, error) {
	list, err := s.store.ListStaff(ctx, p.CenterID)
	if err != nil {
		return nil, err
	}
	for i := range list {
		list[i].Normalize() // status 승격 + 배열 null 금지(스토어 승격과 이중 방어 — 수동 시딩 문서 대비)
	}
	if p.IsOwner() {
		return list, nil
	}
	out := make([]domain.Staff, len(list))
	for i, st := range list {
		if st.UID != p.UID {
			st.Payout = domain.Payout{}
			// 로그인 ID는 급여와 같은 선에 둔다(v2.36) — 동료의 계정 식별자를 알 이유가 없고,
			// 이 응답은 **회원 앱의 코치 소개**도 함께 쓴다.
			st.Email = ""
		}
		if p.IsMember() {
			// 회원에게는 자기 것도 없다 — 회원 uid는 스태프 uid와 겹치지 않으므로 위 분기로도
			// 지워지지만, "회원에게 스태프 이메일은 나가지 않는다"를 조건으로 못 박아 둔다.
			st.Email = ""
		}
		if p.IsMember() && !st.IsActive() {
			st.Profile = domain.StaffProfile{}
			st.Profile.Normalize() // 빈 객체여도 배열은 [](앱의 specialties.map 크래시 방지)
		}
		out[i] = st
	}
	return out, nil
}

// rehireStaff — 퇴사자 재초대(POST /v1/staff)의 재고용 경로(v2.0). 이름·역할과 명시된 색·정산은
// 새 값으로 갱신하되 **프로필(사진 제외 — 퇴사 시 파기, v2.31)·휴무는 보존**한다 — 같은 사람이므로
// 경력·자격증을 다시 입력시킬 이유가 없다. 사진은 퇴사 때 파일과 photo_url이 함께 사라져 있어
// 여기서 되살릴 것이 없다. 순서는 ReactivateStaff와 동일(권한을 늘리는 쓰기는 마지막).
func (s *Service) rehireStaff(ctx context.Context, p Principal, st *domain.Staff, req domain.StaffCreate) (*domain.Staff, error) {
	// 신규 경로의 "이미 회원으로 연결된 계정" 가드는 재고용에도 그대로 적용된다(퇴사 강등으로
	// role=member가 된 계정은 member_id가 없어 통과한다 — 그래야 재고용이 막히지 않는다).
	if err := s.guardIndexNotLinkedMember(ctx, st.UID); err != nil {
		return nil, err
	}
	st.Name = req.Name
	st.Role = req.Role
	// 재고용도 이메일을 갱신한다(v2.36): 같은 계정으로 돌아오는 경로라 값은 같지만, v2.36
	// 이전에 만들어져 email이 빈 레코드가 이 경로로 **채워진다**. 백필 수단이 따로 없다.
	st.Email = req.Email
	if req.Color != "" {
		st.Color = req.Color
	}
	if req.Payout != nil {
		st.Payout = *req.Payout
	}
	st.Status = domain.StaffStatusActive
	st.LeftAt = nil
	st.Normalize()
	if err := s.store.SaveStaff(ctx, p.CenterID, st); err != nil {
		return nil, err
	}
	if err := s.saveStaffIndexRole(ctx, p.CenterID, st.UID, st.Role); err != nil {
		return nil, err
	}
	if err := s.users.EnableUser(ctx, st.UID); err != nil {
		return nil, err
	}
	return st, nil
}

// UpdateStaffProfile — PUT /v1/staff/{uid}/profile(v1.6, P05 트레이너 프로필). 권한은 offdays와
// 동일: owner 또는 본인 trainer(member 403). 시맨틱은 "통 교체" — 프로필 폼은 항상 전 필드를
// 제출하는 단일 문서라 머지보다 예측 가능하고, 빈 값으로 지우기도 자연스럽다(계약 명시).
func (s *Service) UpdateStaffProfile(ctx context.Context, p Principal, uid string, profile domain.StaffProfile) (*domain.Staff, error) {
	if p.IsMember() {
		return nil, ErrForbidden
	}
	if !p.IsOwner() && p.UID != uid {
		return nil, ErrForbidden
	}
	profile.Normalize()
	if err := profile.Validate(); err != nil {
		return nil, err
	}
	st, err := s.store.GetStaff(ctx, p.CenterID, uid)
	if err != nil {
		return nil, err
	}
	// 사진 포인터가 우리 파일(이 uid 명의 `staff/photos/{uid}-…`)에서 **다른 곳**(빈 값·외부 URL)으로
	// 옮겨가면 이전 파일을 지운다(v2.31). 어드민 [사진 지우기]가 바로 이 경로(빈 photo_url PUT)인데,
	// 종전엔 포인터만 비워 파일이 발견 경로 없는 고아가 됐다. 통 교체라 어드민은 같은 URL을 그대로
	// 되돌려 보내므로 prev == next → 삭제 없음(트레이너 본인 편집도 사진 값을 손대지 않고 되보낸다).
	// 저장 **전**에 지우고 실패는 전파한다 — 실패하면 프로필은 아무것도 바뀌지 않은 채 재시도되고,
	// 저장이 실패한 경우엔 URL이 죽은 링크로 남지만 재시도의 삭제가 ErrObjectNotExist를 성공으로 세어
	// 수렴한다(DeactivateStaff ③과 같은 순서·같은 근거). 다른 uid 명의·다른 버킷 URL은 외부 URL과 같다.
	prev, next := s.ownedStaffPhotoPath(uid, st.Profile.PhotoURL), s.ownedStaffPhotoPath(uid, profile.PhotoURL)
	// **이 PUT은 우리 파일 포인터를 새로 만들 수 없다** — 우리 파일을 가리키는 URL은 업로드 엔드포인트만
	// 박는다(통 교체 시맨틱의 유일한 예외, v2.31). next가 우리 파일인데 prev와 다르면 그 URL은 stale이다:
	// 이 화면이 열린 뒤 다른 창에서 사진이 교체·삭제됐다. 그대로 받으면 (a) 현재 파일(prev)을 지우고
	// (b) 이미 없는 옛 파일의 URL을 박아 죽은 링크가 되거나, (c) 퇴사가 파기한 URL이 되살아난다.
	// 400이 아니라 409인 이유: 요청 모양은 옳고 **서버 상태가 그 사이 바뀐 것**이다 — 어드민의 409
	// 폴백 문구("다른 곳에서 먼저 바뀌었어요 — 새로고침")와 같은 뜻이고, 서버 문구가 그것을 그대로 말한다.
	if next != "" && next != prev {
		return nil, errors.Join(ErrConflict, errors.New("사진이 그 사이 바뀌었어요 — 새로고침 후 다시 저장해주세요"))
	}
	if prev != "" && prev != next {
		// purger 미구성이면 지우지 않고 **포인터도 유지**한다(purgeStaffPhoto) — 파일이 남는데 URL만
		// 비우면 고아다. 어드민의 [사진 지우기]는 그 환경에서 사진이 그대로인 것으로 보이고, 나머지
		// 칸은 저장된다. 서버 로그가 그 사실을 말한다(요청당 한 줄).
		deleted, err := s.purgeStaffPhoto(ctx, uid, prev, "프로필 편집 — 사진 지우기/교체")
		if err != nil {
			return nil, err
		}
		if !deleted {
			profile.PhotoURL = st.Profile.PhotoURL
		}
	}
	st.Profile = profile
	if err := s.store.SaveStaff(ctx, p.CenterID, st); err != nil {
		return nil, err
	}
	if st.Offdays == nil {
		st.Offdays = []string{}
	}
	return st, nil
}

func (s *Service) SetOffdays(ctx context.Context, p Principal, uid string, offdays []string) (*domain.Staff, error) {
	if p.IsMember() {
		return nil, ErrForbidden // 명시적 role 게이트(member는 uid가 우연히 겹쳐도 차단)
	}
	if !p.IsOwner() && p.UID != uid {
		return nil, ErrForbidden
	}
	for _, d := range offdays {
		if _, err := time.Parse("2006-01-02", d); err != nil {
			// 형식이 틀리면 recurring의 휴무 제외가 조용히 무효가 된다 — 저장 전에 거부.
			return nil, errors.Join(errBadRequest, errors.New("휴무 날짜는 YYYY-MM-DD 형식이어야 해요: "+d))
		}
	}
	if offdays == nil {
		offdays = []string{}
	}
	st, err := s.store.GetStaff(ctx, p.CenterID, uid)
	if err != nil {
		return nil, err
	}
	st.Offdays = offdays
	if err := s.store.SaveStaff(ctx, p.CenterID, st); err != nil {
		return nil, err
	}
	return st, nil
}

// ---- 센터(GET /v1/center, v1.1 정합 패치) ----

// CenterResponse — GET /v1/center 응답: 센터 식별자 + 정책(설정값, P6) + 사업자 정보(v2.13).
//
// business를 policy 안이 아니라 **옆에** 둔 이유는 domain/business.go 주석에 있다 — 요약하면
// 운영 다이얼과 법적 신원은 바뀌는 이유·주기·권한·공개 범위가 전부 다르고, 특히 **무인증 공개
// 응답에서 정책을 걷어내는 일**을 매번 손으로 하게 만들면 언젠가 연 매출 목표가 익명에게 나간다.
type CenterResponse struct {
	CenterID string `json:"center_id"`
	// Name — 센터 상호(멀티센터 Phase A). 미등록(기존 rise처럼 신원 없는 센터)이면 빈 문자열 —
	// 클라이언트는 빈 값이면 기존 하드코딩 상호로 폴백한다(하위호환: 서버 먼저 배포).
	//
	// v2.27에서 아래 Center 블록이 생긴 뒤에도 **이 칸은 남는다.** 앱·어드민이 이미 읽고 있는
	// 키라 지우면 배포 순서가 강제되고(서버 먼저 → 클라이언트 나중이 아니라 그 반대가 된다),
	// 상호 하나만 필요한 화면이 블록을 파고들 이유가 없다. Center.Name과 항상 같은 값이다.
	Name string `json:"name"`
	// Center — 센터 신원 3칸(v2.27). 상호만 top-level에 있어서 **저장한 전화·주소를 되읽을
	// 경로가 없었다** — 어드민이 저장 후 새로고침하면 그 두 칸이 빈 폼으로 돌아온다.
	//
	// domain.Center를 그대로 싣지 않는 이유는 요청 쪽(centerIdentityPatch)과 같다: id·status·
	// created_at은 이 엔드포인트가 편집하지 않는 값이고, 응답에 실으면 다음 사람이 "그럼 보낼
	// 수도 있겠지"로 읽는다. 요청과 응답의 키 집합을 같게 유지하는 편이 폼을 그대로 재장전하는
	// 어드민에게도 맞는다(UpdateCenterFacility 응답이 3키인 것과 같은 규율).
	//
	// 세 칸 모두 omitempty가 **아니다** — 빈 값도 키로 나가야 폼이 "아직 안 적음"과 "키 없음"을
	// 구별하지 않고 그대로 재장전한다(BusinessView가 12칸을 늘 내려보내는 것과 같은 이유).
	Center   CenterIdentityView `json:"center"`
	Policy   domain.Policy      `json:"policy"`
	Business BusinessView       `json:"business"`
	// Facility — 시설 신고 상태 선언(P42, v2.19). 역할별로 가리지 않는다(Business와 같은
	// 이유 — 계약서에 그대로 인쇄되는 값이라 민감 정보가 아니다). 미선언이면 기본값
	// {unknown,"",""} — 스토어 읽기 규약이 보장한다. 공개 응답(GET /v1/public/business)
	// 에는 싣지 않는다 — 그쪽 키 집합은 전용 타입(BusinessView)으로 고정돼 있다.
	Facility domain.Facility `json:"facility"`
}

// CenterIdentityView — 센터 신원 응답 3칸(v2.27). PUT /v1/center의 `center` 덩어리가 받는
// 키 집합과 **정확히 같다** — 어드민이 GET으로 폼을 채우고 그 모양 그대로 PUT한다.
type CenterIdentityView struct {
	Name    string `json:"name"`
	Phone   string `json:"phone"`
	Address string `json:"address"`
}

func centerIdentityView(c domain.Center) CenterIdentityView {
	return CenterIdentityView{Name: c.Name, Phone: c.Phone, Address: c.Address}
}

// BusinessView — 사업자 정보 응답. domain.Business 12칸을 그대로 펼치고 파생값 complete를 얹는다.
//
// complete를 **서버가 계산해 내려보내는** 이유: 이 판정 하나로 법정 문서 5장이 "시행 중"과
// "초안" 사이를 오간다. 층마다 다시 세면 어느 문서는 시행 중이고 어느 문서는 초안인 상태가
// 만들어진다 — 위약금율이 네 자리에서 다른 숫자를 말하던 P14 C1과 같은 모양의 결함이다.
// 저장하지는 않는다(파생값을 저장하면 칸이 바뀐 뒤에도 굳은 거짓말이 남는다 — Pass.status v2.12와 같은 자리).
type BusinessView struct {
	domain.Business
	Complete bool `json:"complete"`
}

// businessView — 저장값을 응답 모양으로. Normalize를 응답 직전에도 한 번 더 태워, 검증을 지나지
// 않은 값(손으로 고친 Firestore 문서)이 문서에 그대로 인쇄되지 않게 한다(Policy.Normalize와 같은 규약).
func businessView(b domain.Business) BusinessView {
	b.Normalize()
	return BusinessView{Business: b, Complete: b.IsComplete()}
}

// GetCenter — GET /v1/center. v1.4: member에게도 공개한다 — 회원 앱이 취소 컷오프·홀딩 상한을
// 하드코딩 문구가 아닌 실정책 값으로 표시하기 위함(정책이 편집 가능해진 순간 하드코딩은 거짓말이
// 된다). 단 매출 목표(금액)는 owner 전용(P13)이라 비운다.
//
// penalty_rate는 GetPolicy(Normalize)를 거쳐 **실제로 공제되는 값**으로 내려간다 — 종전엔
// 상한을 넘는 설정값이 그대로 회원 앱까지 갔다(P14 C1: 정책 0.3 저장 → 앱도 0.3 → 실공제 10%).
func (s *Service) GetCenter(ctx context.Context, p Principal) (CenterResponse, error) {
	policy, err := s.store.GetPolicy(ctx, p.CenterID)
	if err != nil {
		return CenterResponse{}, err
	}
	pol := *policy
	if !p.IsOwner() {
		pol.RevenueTarget = 0
	}
	// 사업자 정보는 역할별로 가리지 않는다 — 애초에 법정 고지 대상이라 무인증 공개 경로
	// (PublicBusiness)로도 나가는 값이다. 여기서만 가리면 화면마다 다른 답이 된다.
	biz, err := s.store.GetBusiness(ctx, p.CenterID)
	if err != nil {
		return CenterResponse{}, err
	}
	center, err := s.store.GetCenter(ctx, p.CenterID)
	if err != nil {
		return CenterResponse{}, err
	}
	fac, err := s.store.GetFacility(ctx, p.CenterID)
	if err != nil {
		return CenterResponse{}, err
	}
	return CenterResponse{
		CenterID: p.CenterID, Name: center.Name, Center: centerIdentityView(*center),
		Policy: pol, Business: businessView(*biz), Facility: *fac,
	}, nil
}

// UpdateCenterPolicy — PUT /v1/center {policy}(v1.4, owner 전용). 설계00 §3.1 "정책은 설정값
// (하드코딩 금지)"의 마지막 조각 — 용량·컷오프·위약금율·홀딩 상한·매출 목표를 대표가 직접 바꾼다.
// 머지 시맨틱(P03): 기존 정책 위에 보낸 필드만 덮어쓴다 — 클라이언트가 필드를 빠뜨려도
// grace_once/revenue_target이 조용히 false/0으로 초기화되지 않는다(UpdateMember와 동일 패턴).
func (s *Service) UpdateCenterPolicy(ctx context.Context, p Principal, rawPolicy []byte) (CenterResponse, error) {
	if !p.IsOwner() {
		return CenterResponse{}, ErrForbidden
	}
	existing, err := s.store.GetPolicy(ctx, p.CenterID)
	if err != nil {
		return CenterResponse{}, err
	}
	pol := *existing
	if err := strictUnmarshal(rawPolicy, &pol); err != nil {
		return CenterResponse{}, err
	}
	if err := pol.Validate(); err != nil {
		return CenterResponse{}, err
	}
	if err := s.store.SavePolicy(ctx, p.CenterID, &pol); err != nil {
		return CenterResponse{}, err
	}
	// 센터 신원을 여기서도 채운다 — GetCenter 응답에만 있으면 정책 저장 응답이 화면의 상호를
	// 빈 값으로 되돌려 깜빡인다(응답으로 캐시를 갱신하는 클라이언트 패턴 전제). v2.27에서
	// 전화·주소가 같은 블록에 생겼으므로 그 셋을 함께 싣는다 — 하나만 채우면 같은 깜빡임이
	// 나머지 두 칸에서 되풀이된다.
	center, err := s.store.GetCenter(ctx, p.CenterID)
	if err != nil {
		return CenterResponse{}, err
	}
	return CenterResponse{
		CenterID: p.CenterID, Name: center.Name, Center: centerIdentityView(*center), Policy: pol,
	}, nil
}

// centerIdentityPatch — PUT /v1/center {center} 의 수용 필드(v2.27). **세 칸뿐이다.**
//
// domain.Center를 그대로 받지 않는 이유가 여기서는 보안이다: 그 구조체엔 id·status·created_at이
// 함께 있고, strictUnmarshal은 json 태그가 있는 필드를 전부 받아들인다. `{"id":"other-center"}`
// 하나면 SaveCenter가 **다른 센터의 문서**에 쓴다(Firestore는 f.center(c.ID), Memory는
// m.centers[c.ID] — 두 구현 모두 c.ID를 키로 쓴다). 대표가 자기 센터를 편집하는 폼이
// 남의 센터를 덮어쓰는 경로가 되면 안 된다. 여기 없는 키는 decodeJSON/strictUnmarshal의
// DisallowUnknownFields가 400으로 되돌린다 — 실수든 시도든 조용히 통과하지 않는다.
//
// 포인터인 이유는 부분 갱신 규약이다(policy 덩어리와 같은 시맨틱): **보내지 않은 칸은 그대로
// 두고, 보낸 칸은 빈 문자열이어도 반영한다.** 값 타입이었다면 이름만 고치는 요청이 전화번호·
// 주소를 조용히 지운다(v2.13이 policy를 머지로 만든 그 이유 — P03·P27·P49가 반복해서 배운 것).
// 동시에 "잘못 적은 주소를 비워서 지우기"도 열려 있다(business가 통 교체로 얻은 성질을,
// 머지에서 명시적 빈 값으로 얻는다).
type centerIdentityPatch struct {
	Name    *string `json:"name"`
	Phone   *string `json:"phone"`
	Address *string `json:"address"`
}

// UpdateCenterIdentity — PUT /v1/center {center}(v2.27, owner 전용). 센터 상호·전화·주소 등록.
//
// 왜 이제야: 센터 신원(domain.Center)은 v2.16이 superadmin의 POST /v1/admin/centers와 함께
// 만들었는데, **그 경로로 만들어지지 않은 센터**(라이즈처럼 v1부터 지연 시딩으로 존재해 온
// 문서)는 신원을 입력할 자리가 어디에도 없었다. 결과가 눈에 보이는 세 곳이었다:
// ① GET /v1/center의 name이 빈 문자열이라 앱이 상호를 빌드 상수로 들고 있었고(배포로만 고칠
// 수 있는 값이 되어 있었다), ② ListCenters가 `name == ""`를 유령 문서로 걸러 운영 센터가
// 관리 평면 목록에 뜨지 않았고, ③ 회원의 센터 선택(JoinRequestCreate 봉인 주석)을 열 수
// 없었다 — 목록에 넣을 센터가 없으니까.
//
// superadmin 전용이 아니라 owner 전용인 이유: 상호·전화·주소는 **일상 운영 정보**다(이전·개명·
// 번호 변경이 실제로 일어난다). 센터를 만들고 없애는 것은 관리 평면의 일이지만, 자기 센터의
// 이름을 고치는 것은 정책·사업자 정보와 같은 선에 있다. 반대로 ID·상태·생성시각은 여기서
// 손댈 수 없다(centerIdentityPatch 주석) — 그쪽이 관리 평면의 몫이다.
func (s *Service) UpdateCenterIdentity(ctx context.Context, p Principal, rawCenter []byte) (domain.Center, error) {
	if !p.IsOwner() {
		return domain.Center{}, ErrForbidden
	}
	var patch centerIdentityPatch
	if err := strictUnmarshal(rawCenter, &patch); err != nil {
		return domain.Center{}, err
	}
	// 기존 값 위에 보낸 칸만 얹는다. GetCenter는 미등록 센터에도 ErrNotFound가 아니라
	// **빈 값**(ID만 채움)을 돌려주므로(스토어 규약), 최초 등록과 수정이 같은 코드를 탄다.
	existing, err := s.store.GetCenter(ctx, p.CenterID)
	if err != nil {
		return domain.Center{}, err
	}
	c := *existing
	// 문서 키가 진실 — 스토어가 c.ID를 쓰기 대상 키로 삼으므로 여기서 못 박는다(GetCenter가
	// 이미 채워 주지만, 손편집된 문서의 어긋난 id가 흘러들 여지를 남기지 않는다).
	c.ID = p.CenterID
	if patch.Name != nil {
		c.Name = *patch.Name
	}
	if patch.Phone != nil {
		c.Phone = *patch.Phone
	}
	if patch.Address != nil {
		c.Address = *patch.Address
	}
	// 최초 등록이면 생성 시각을 여기서 박는다 — 지연 시딩으로 생긴 문서엔 없다.
	if c.CreatedAt.IsZero() {
		c.CreatedAt = time.Now().UTC()
	}
	// 검증 **전에** 정규화(UpdateCenterBusiness·UpdateCenterFacility와 같은 이유 — 붙여넣기로
	// 딸려 온 공백 때문에 400이 나면 무엇이 틀렸는지 눈에 보이지 않는다). 빈 Status는
	// Normalize가 active로 접는다.
	c.Normalize()
	if err := c.Validate(); err != nil {
		return domain.Center{}, err
	}
	// SaveCenter는 두 구현 모두 센터 문서의 `center` 절만 머지로 쓴다 — Policy·Business·
	// Facility·CheckinQR은 건드리지 않는다(P27 SavePolicy 교훈, 스토어 규약).
	if err := s.store.SaveCenter(ctx, &c); err != nil {
		return domain.Center{}, err
	}
	return c, nil
}

// UpdateCenterBusiness — PUT /v1/center {business}(v2.13, owner 전용). 법정 고지 기재사항 등록.
//
// **머지가 아니라 통 교체다**(정책 PUT과 반대). 근거는 UpdateStaffProfile과 같다: 폼이 늘 12칸
// 전부를 제출하고, 잘못 적은 칸을 **비워서 지우는 일**이 실제로 필요하다 — 머지면 한 번 들어간
// 오타를 지울 방법이 없다. 정책 쪽이 머지인 이유는 그쪽이 자주 만지는 운영 다이얼이라 동시 편집
// 충돌이 실재하기 때문인데, 사업자 정보는 개업 때 한 번 넣고 상호·주소가 바뀔 때만 손대는 값이다.
//
// 미완성 저장을 허용한다(domain.Business.Validate는 채워진 칸의 형식만 본다) — 대표가 아는
// 칸부터 채워 나가는 동선을 막지 않되, 문서 게시는 complete일 때만 열린다.
func (s *Service) UpdateCenterBusiness(ctx context.Context, p Principal, rawBusiness []byte) (BusinessView, error) {
	if !p.IsOwner() {
		return BusinessView{}, ErrForbidden
	}
	var biz domain.Business
	if err := strictUnmarshal(rawBusiness, &biz); err != nil {
		return BusinessView{}, err
	}
	// 검증 **전에** 정규화한다 — 붙여넣기로 딸려 온 공백 때문에 400이 나면 대표는 무엇이
	// 틀렸는지 알 수 없다(눈에 보이지 않는 문자가 원인이라서).
	biz.Normalize()
	if err := biz.Validate(); err != nil {
		return BusinessView{}, err
	}
	if err := s.store.SaveBusiness(ctx, p.CenterID, &biz); err != nil {
		return BusinessView{}, err
	}
	return businessView(biz), nil
}

// PublicBusiness — GET /v1/public/business(무인증, v2.13). 법정 고지 HTML 5장이 익명으로 읽는다.
//
// **센터를 인자로 받지 않는다.** 익명 호출자가 center_id를 고를 수 있으면 그 자체로 센터 존재
// 여부를 훑는 수단이 된다. v1은 단일 센터 전제라(config.DefaultCenterID) 고를 것도 없다 —
// 다센터가 되면 그때는 호스트명·문서 경로처럼 **요청자가 정하지 않는 축**으로 갈라야 한다.
//
// 응답에 실리는 건 BusinessView 뿐이다: 정책(연 매출 목표·위약금율·용량)도, center_id도,
// 회원·직원 수도 나가지 않는다. "필요한 것만 담는 전용 응답 타입"이라 GET /v1/center에 필드가
// 늘어도 여기로 새지 않는다 — 마스킹 목록을 관리하는 방식이었다면 언젠가 하나를 빠뜨린다.
// PublicBusiness — 법정 문서가 인쇄할 사업자 정보. [centerID]가 비면 기본 센터(구 링크 호환),
// 값이 있으면 그 센터 — 모르는 센터면 404다(계약 v2.33, `resolvePublicCenter`).
//
// **센터별로 갈라야 하는 이유**: 이 응답이 개인정보처리방침의 "개인정보처리자"와 계정 삭제
// 안내의 접수 창구로 인쇄된다. 센터가 둘인데 한 센터의 사업자 정보를 모두에게 보여주면
// 나머지 센터의 법정 고지가 통째로 거짓이 된다.
func (s *Service) PublicBusiness(ctx context.Context, centerID string) (BusinessView, error) {
	id, err := s.resolvePublicCenter(ctx, centerID)
	if err != nil {
		return BusinessView{}, err
	}
	b, err := s.store.GetBusiness(ctx, id)
	if err != nil {
		return BusinessView{}, err
	}
	return businessView(*b), nil
}

// PublicCenter — GET /v1/public/center(**무인증**, v2.29). 회원 앱의 **센터 연결 화면(대기실)**이
// 읽는다: 전화 인증만 끝난 미연결 사용자는 Principal에 센터가 없어 GET /v1/center를 못 부르는데,
// 그 화면이 보여줘야 하는 것이 정확히 센터 상호·전화·주소다(P55). 이 경로가 없던 동안 앱은
// 상호를 로컬 상수로 찍고 전화·주소는 사업자 정보에서 읽었다 — 어드민 "센터 신원" 폼이
// "회원 앱에 이 이름으로 뜬다"고 약속했지만 앱은 그 값을 **어디서도 읽지 않았다**(P56 L10).
//
// 응답은 CenterIdentityView 3칸으로 **고정**한다 — PUT /v1/center {center}가 받는 키 집합과 같다.
// domain.Center의 id·status·created_at은 싣지 않는다(익명에게 내부 식별자를 줄 이유가 없고,
// BusinessView가 키 집합을 전용 타입으로 잠근 것과 같은 규율).
//
// **전화·주소는 사업자 정보로 폴백한다**, 상호는 폴백하지 않는다. 대표가 법정 고지 때문에
// 사업자 정보 12칸은 채우고 센터 신원 3칸은 비워 두는 순서가 자연스러운데, 그때 대기실의
// "센터에 전화하기"가 죽어 있으면 안 된다 — 두 번호 모두 이미 공개 값이라(GET /v1/public/business)
// 새로 노출되는 것은 없다. 상호는 폴백하지 않는다: 사업자명(법인명)과 센터 상호는 다른 값이고
// (어드민 폼이 두 칸을 나눠 둔 이유), 빈 상호는 클라이언트가 자기 임시 상수로 채운다
// (CenterResponse.Name의 하위호환 규약과 같다). 폴백은 **서버 한 곳**에서 한다 — 앱·어드민이
// 각자 합치면 어느 화면은 센터 번호를, 어느 화면은 사업자 번호를 보여주는 자기모순이 생긴다.
//
// v2.34(P69): 응답에 **수업 시간**(`open_hour`·`close_hour`)이 얹힌다 — 대기실 센터 카드가 그린다.
// 별도 타입([PublicCenterView])인 이유: [CenterIdentityView] 3칸은 `PUT /v1/center`의 `center`
// 덩어리·JoinMatch.center와 공용이라 거기에 시간을 섞으면 대표의 편집 폼이 시간 칸을 되돌려
// 보내게 된다. 운영시간은 간판·지도에 공개되는 값이라 익명 노출에 거절 논거가 없고, 정책의
// 나머지(용량·위약금율·매출 목표)는 여전히 나가지 않는다(키 집합 잠금 테스트).
func (s *Service) PublicCenter(ctx context.Context, centerID string) (PublicCenterView, error) {
	id, err := s.resolvePublicCenter(ctx, centerID)
	if err != nil {
		return PublicCenterView{}, err
	}
	c, err := s.store.GetCenter(ctx, id)
	if err != nil {
		return PublicCenterView{}, err
	}
	view := centerIdentityView(*c)
	if strings.TrimSpace(view.Phone) == "" || strings.TrimSpace(view.Address) == "" {
		b, err := s.store.GetBusiness(ctx, id)
		if err != nil {
			return PublicCenterView{}, err
		}
		b.Normalize()
		if strings.TrimSpace(view.Phone) == "" {
			view.Phone = b.Phone
		}
		if strings.TrimSpace(view.Address) == "" {
			view.Address = b.Address
		}
	}
	// GetPolicy는 문서 부재 시 기본 정책을 지연 시딩한다(쓰기). 여기 도달한 id는
	// resolvePublicCenter가 실재 센터로 확인한 것이라 그 시딩은 인증된 GET /v1/center가 어차피
	// 한 번은 할 일과 같다 — 익명 경로가 임의 문서를 만들 수는 없다.
	pol, err := s.store.GetPolicy(ctx, id)
	if err != nil {
		return PublicCenterView{}, err
	}
	pol.Normalize() // 손으로 고친 문서의 잘못된 값이 그대로 인쇄되지 않게(v2.24 규약)
	return PublicCenterView{CenterIdentityView: view, OpenHour: pol.OpenHour, CloseHour: pol.CloseHour}, nil
}

// PublicCenterView — `GET /v1/public/center` 응답(v2.34). 신원 3칸 + 수업 시간 2칸.
// 시간 두 값은 GET /v1/center의 policy와 같은 의미(첫 슬롯 시작·마지막 슬롯 시작, 양끝 포함)다 —
// 앱이 "09:00–22:00"으로 그리려면 close_hour+1을 써야 한다(domain.Policy 주석).
type PublicCenterView struct {
	CenterIdentityView
	OpenHour  int `json:"open_hour"`
	CloseHour int `json:"close_hour"`
}
