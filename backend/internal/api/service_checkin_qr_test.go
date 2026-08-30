package api

// 데스크 체크인 QR 토큰(P49, 계약 v2.23)의 서비스/라우터 테스트.
//
// 축 여섯 개: 권한(owner 전용 — 두 엔드포인트 모두) / 발급·재발급(모양·엔트로피·issued_at) /
// 미발급 상태(issued:false, self_qr 거부) / **재발급이 옛 인쇄물을 죽인다**(이 기능의 유일한
// 보안 손잡이라 증명 없이는 약속이 아니다) / **머지 회귀**(P27) / **누출 방지**(회원·트레이너가
// 보는 응답 어디에도 토큰이 없다 — 알면 집에서 출석을 찍는 값이다).

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// seedCheckinToken — 체크인 토큰을 스토어에 직접 심는다(발급 API를 태우지 않는 픽스처).
// 종전엔 config.CheckinQRToken 한 줄이던 자리 — 토큰이 DB로 옮겨간 뒤의 대응물이다.
func seedCheckinToken(t *testing.T, s *Service, token string) {
	t.Helper()
	now := time.Now().UTC()
	if err := s.store.SaveCheckinQR(context.Background(), testCenter,
		&domain.CheckinQR{Token: token, IssuedAt: &now}); err != nil {
		t.Fatalf("SaveCheckinQR: %v", err)
	}
}

// ---- 권한: 두 엔드포인트 모두 owner 전용 ----

// 조회와 발급이 **둘 다** 막혀야 한다. 조회만 막으면 트레이너가 rotate로 새 토큰을 받아
// 그 응답에서 값을 읽는다(발급 응답에도 토큰이 실린다) — 한쪽만 잠근 문은 잠긴 문이 아니다.
//
// 트레이너를 막는 것이 과한 게 아닌 이유: 이 값은 "보는 권한"과 "가지는 권한"이 같다. 한 번
// 보면 화면을 찍어 영구 보관할 수 있고 퇴사해도 사본은 남는다. 트레이너가 회원 출석을 찍는
// 정당한 경로는 이미 tap 체크인으로 따로 있다.
func TestCheckinQROwnerOnly(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	for _, p := range []Principal{trainerP(), memberP("m1")} {
		if _, err := s.GetCheckinQR(ctx, p); !errors.Is(err, ErrForbidden) {
			t.Errorf("%s의 체크인 토큰 조회가 통과: %v", p.Role, err)
		}
		if _, err := s.RotateCheckinQR(ctx, p); !errors.Is(err, ErrForbidden) {
			t.Errorf("%s의 체크인 토큰 발급이 통과: %v", p.Role, err)
		}
	}

	// 거부된 rotate가 **아무것도 쓰지 않았는지**까지 본다. 권한 검사 뒤에 저장이 남아 있으면
	// 403을 받은 트레이너가 데스크의 멀쩡한 QR을 무효로 만들 수 있다(값은 못 봐도 파괴는 된다).
	if got, err := s.GetCheckinQR(ctx, ownerP()); err != nil || got.Issued {
		t.Errorf("403 뒤 상태 = %+v(err=%v), want 미발급 — 거부된 발급이 토큰을 갈아치웠다", got, err)
	}
}

// ---- 발급·재발급 ----

// 발급 토큰의 모양과 엔트로피. 앱은 스캔한 문자열을 가공 없이 보내고 서버가 바이트로 비교하므로,
// 인코딩 왕복에서 변형될 수 있는 문자가 하나라도 들어가면 실기기에서만 실패한다.
func TestRotateCheckinQRTokenShape(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	seen := map[string]bool{}
	for i := 0; i < 50; i++ {
		got, err := s.RotateCheckinQR(ctx, ownerP())
		if err != nil {
			t.Fatalf("발급 %d회차: %v", i, err)
		}
		if !got.Issued {
			t.Fatalf("발급 직후 issued=false: %+v", got)
		}
		if len(got.Token) != domain.CheckinQRTokenLen {
			t.Fatalf("토큰 길이 = %d, want %d", len(got.Token), domain.CheckinQRTokenLen)
		}
		// URL-safe base64(RawURLEncoding) 문자셋만 — 전부 ASCII. QR 바이트 모드에 그대로 실린다.
		for _, r := range got.Token {
			ok := (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' || r == '_'
			if !ok {
				t.Fatalf("토큰에 URL-safe base64 밖 문자 %q: %q — 스캔값이 왕복에서 변형될 수 있다", r, got.Token)
			}
		}
		if seen[got.Token] {
			t.Fatalf("토큰 중복 발급(%d회차): %q — 난수원이 죽었다", i, got.Token)
		}
		seen[got.Token] = true
	}
}

// 재발급은 값을 바꾸고, 저장되고, issued_at을 갱신한다. issued_at이 안 움직이면 어드민은
// 데스크에 붙은 종이가 최신인지 판단할 근거를 잃는다(그 값이 유일한 근거다).
func TestRotateCheckinQRPersistsAndStampsTime(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	before := time.Now().UTC().Add(-time.Second)
	first, err := s.RotateCheckinQR(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if first.IssuedAt == nil || first.IssuedAt.Before(before) {
		t.Fatalf("issued_at = %v, want 발급 시각", first.IssuedAt)
	}

	// 재조회가 같은 값을 준다(저장됐다).
	reread, err := s.GetCheckinQR(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if reread.Token != first.Token || reread.IssuedAt == nil || !reread.IssuedAt.Equal(*first.IssuedAt) {
		t.Fatalf("재조회 = %+v, want %+v — 발급이 저장되지 않았다", reread, first)
	}

	second, err := s.RotateCheckinQR(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if second.Token == first.Token {
		t.Fatal("재발급이 같은 토큰을 돌려줬다 — 유출 시 되돌릴 수단이 없어진다")
	}
	if second.IssuedAt == nil || second.IssuedAt.Before(*first.IssuedAt) {
		t.Errorf("재발급 issued_at = %v, want 1차(%v) 이후", second.IssuedAt, first.IssuedAt)
	}
	// 절 통 교체 — 이전 토큰이 유령으로 남으면 옛 인쇄물이 계속 통과한다.
	after, _ := s.GetCheckinQR(ctx, ownerP())
	if after.Token != second.Token {
		t.Fatalf("재발급 후 저장값 = %q, want %q", after.Token, second.Token)
	}
}

// 미발급 센터의 조회는 200 + {issued:false, token:"", issued_at:null}이다(404가 아니다) —
// 어드민이 "아직 발급 안 됨" 화면을 그리는 정상 상태다. 404로 만들면 진짜 오류와 구분이 사라진다.
func TestGetCheckinQRBeforeIssue(t *testing.T) {
	s := newTestService()

	got, err := s.GetCheckinQR(context.Background(), ownerP())
	if err != nil {
		t.Fatalf("미발급 조회가 오류: %v — 미발급은 오류가 아니라 상태다", err)
	}
	if got.Issued || got.Token != "" || got.IssuedAt != nil {
		t.Fatalf("미발급 조회 = %+v, want {false,\"\",nil}", got)
	}
}

// ---- 체크인 대조 ----

// 이 작업의 핵심 보장 두 개를 한 자리에서 본다:
//
//	① 저장된 토큰으로 체크인이 된다(환경변수 폴백 없이도 실제로 동작한다).
//	② **재발급하면 직전 토큰이 즉시 죽는다** — 어드민이 "옛 인쇄물이 무효가 됩니다"라고
//	   경고할 근거이자, 토큰이 샜을 때 대표가 스스로 되돌릴 수 있는 유일한 수단이다.
//	   증명이 없으면 그 경고는 약속이 아니라 희망이다.
func TestSelfQRCheckinUsesStoredTokenAndRotationKillsOldPrints(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	seedBookingInCheckinWindow(t, s, mem, pass)

	issued, err := s.RotateCheckinQR(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	p := memberP(mem.ID)

	if _, err := s.Checkin(ctx, p, CheckinRequest{Source: "self_qr", QRToken: "wrong"}); err == nil {
		t.Error("잘못된 qr_token이 통과")
	}
	if _, err := s.Checkin(ctx, p, CheckinRequest{Source: "self_qr", QRToken: issued.Token}); err != nil {
		t.Fatalf("발급된 토큰으로 체크인 실패: %v", err)
	}

	// 재발급 — 데스크에 붙은 종이(= issued.Token)가 이 순간 죽어야 한다.
	rotated, err := s.RotateCheckinQR(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.Checkin(ctx, p, CheckinRequest{Source: "self_qr", QRToken: issued.Token}); err == nil {
		t.Fatal("재발급 뒤에도 옛 토큰이 통과 — '재발급하면 옛 인쇄물이 무효'가 거짓이 된다")
	}
	if _, err := s.Checkin(ctx, p, CheckinRequest{Source: "self_qr", QRToken: rotated.Token}); err != nil {
		t.Fatalf("새 토큰으로 체크인 실패: %v", err)
	}
}

// 미발급 센터의 self_qr은 **거부**된다(폴백 없음). 그리고 거부 문구가 대표에게 무엇을 해야
// 하는지 말해야 한다 — "qr_token이 유효하지 않음"만 나오면 대표는 QR 인쇄물이나 앱을 의심하며
// 영원히 헤맨다(고칠 곳은 어드민 설정이다).
//
// 여기에 어떤 폴백이라도 두는 순간 "발급 안 한 센터가 사실은 열려 있다"는 조용한 구멍이 된다.
func TestSelfQRCheckinRejectedWhenNeverIssued(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	seedBookingInCheckinWindow(t, s, mem, pass)

	// 종전 공개 기본값을 포함해 무엇을 보내도 통과하면 안 된다.
	for _, tok := range []string{"", "rise-desk-checkin", "test-qr-token"} {
		_, err := s.Checkin(ctx, memberP(mem.ID), CheckinRequest{Source: "self_qr", QRToken: tok})
		if err == nil {
			t.Fatalf("미발급 센터에서 qr_token=%q가 통과 — 발급 안 한 센터가 열려 있다", tok)
		}
		if !errors.Is(err, errBadRequest) {
			t.Errorf("qr_token=%q: err = %v, want 400", tok, err)
		}
		if !strings.Contains(err.Error(), "발급") {
			t.Errorf("qr_token=%q 거부 문구에 조치 안내가 없다: %v", tok, err)
		}
	}
}

// ---- 누출 방지 ----

// **토큰은 회원·트레이너가 보는 어떤 응답에도 없다.** 회원 한 명이 이 값을 알면 그 순간
// 집에서 출석을 찍는다 — 이 기능의 위협 모델 전부가 이 한 줄이다.
//
// 필드 유무가 아니라 **키 집합**을 고정하는 이유: `token`이라는 이름으로 새는 것만 막으면
// 다음에 누가 `checkin_qr` 맵을 통째로 얹었을 때 통과한다. 응답에 담기는 것을 손으로 적어야만
// 늘어나게 하고, 늘어나면 이 테스트가 먼저 깨지게 한다.
func TestCheckinTokenNeverLeaksToSharedResponses(t *testing.T) {
	r := newTestRouter(t)

	// 발급해 둔다 — 값이 없으면 "안 샌다"가 공허하게 통과한다.
	rot := postJSON(t, r, "/v1/center/checkin-qr/rotate", "owner1", domain.RoleOwner, "")
	if rot.Code != http.StatusOK {
		t.Fatalf("발급 = %d body=%s", rot.Code, rot.Body.String())
	}
	var issued CheckinQRView
	if err := json.Unmarshal(rot.Body.Bytes(), &issued); err != nil {
		t.Fatal(err)
	}
	if issued.Token == "" {
		t.Fatal("발급 응답에 토큰이 없다")
	}

	// GET /v1/center — 세 역할 전부. 키 집합을 못 박는다(v2.23 기준 5키).
	for _, role := range []struct{ uid, role string }{
		{"owner1", domain.RoleOwner}, {"t1", domain.RoleTrainer}, {"member1", domain.RoleMember},
	} {
		rec := getJSON(t, r, "/v1/center", role.uid, role.role)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s GET /v1/center = %d", role.role, rec.Code)
		}
		var m map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &m); err != nil {
			t.Fatal(err)
		}
		assertKeySet(t, role.role+" GET /v1/center", m,
			[]string{"center_id", "name", "policy", "business", "facility"})
		// 본문 전체를 문자열로도 훑는다 — 어떤 키 아래 중첩돼도 잡힌다(키 집합만 보면
		// policy·business 안에 얹힌 값은 통과한다).
		if strings.Contains(rec.Body.String(), issued.Token) {
			t.Fatalf("%s GET /v1/center 본문에 체크인 토큰이 있다 — 회원이 집에서 출석을 찍는다", role.role)
		}
	}

	// 무인증 공개 엔드포인트 — 여기로 새면 로그인조차 필요 없어진다.
	pub := getJSON(t, r, "/v1/public/business", "", "")
	if pub.Code != http.StatusOK {
		t.Fatalf("GET /v1/public/business = %d", pub.Code)
	}
	if strings.Contains(pub.Body.String(), issued.Token) {
		t.Fatal("무인증 공개 응답에 체크인 토큰이 있다")
	}
	var pm map[string]any
	if err := json.Unmarshal(pub.Body.Bytes(), &pm); err != nil {
		t.Fatal(err)
	}
	for _, banned := range []string{"token", "checkin_qr", "issued", "issued_at"} {
		if _, ok := pm[banned]; ok {
			t.Errorf("공개 응답에 %q 키가 있다", banned)
		}
	}
}

// ---- 머지 회귀(P27의 네 번째 절) ----

// 토큰 발급이 같은 centers 문서에 동거하는 Policy·Business·Facility를 지우면 안 되고,
// 반대 방향(정책·사업자·시설 저장)도 토큰을 지우면 안 된다.
//
// 반대 방향이 특히 위험하다: 토큰이 지워지면 증상이 "체크인이 안 돼요"로만 보이고, 대표는
// 재발급을 눌러 데스크 인쇄물을 다시 뽑는다 — 원인은 그대로 남아 다음 정책 저장에서 재발한다.
func TestCheckinQRSaveKeepsOtherCenterSections(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	if _, err := s.UpdateCenterBusiness(ctx, ownerP(), []byte(completeBusinessJSON)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"slot_capacity":4}`)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterFacility(ctx, ownerP(), domain.Facility{
		ReportStatus: domain.FacilityStatusReported, ReportNo: "제2026-강남-0001호",
	}); err != nil {
		t.Fatal(err)
	}

	issued, err := s.RotateCheckinQR(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}

	got, err := s.GetCenter(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if !got.Business.Complete || got.Business.BizName != "라이즈 컨디셔닝" {
		t.Errorf("토큰 발급 후 사업자 정보 = %+v — 법정 문서가 초안으로 되돌아간다(P27 재발)", got.Business)
	}
	if got.Policy.SlotCapacity != 4 {
		t.Errorf("토큰 발급 후 slot_capacity = %d, want 4 — 정책이 덮였다", got.Policy.SlotCapacity)
	}
	if got.Facility.ReportStatus != domain.FacilityStatusReported {
		t.Errorf("토큰 발급 후 facility = %+v — 신고 선언이 지워지면 스탬프가 조용히 꺼진다", got.Facility)
	}

	// 반대 방향 — 이웃 절 저장이 토큰을 지우면 체크인이 조용히 죽는다.
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"slot_capacity":5}`)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterBusiness(ctx, ownerP(), []byte(completeBusinessJSON)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterFacility(ctx, ownerP(), domain.Facility{ReportStatus: domain.FacilityStatusExempt}); err != nil {
		t.Fatal(err)
	}
	after, err := s.GetCheckinQR(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if after.Token != issued.Token {
		t.Errorf("정책·사업자·시설 저장 후 토큰 = %q, want %q — 데스크 QR이 조용히 죽었다", after.Token, issued.Token)
	}
}

// ---- 라우터: 경로·메서드·상태코드·와이어 키 ----

// 서비스 호출 테스트는 Go 필드를 보므로 `json:"issued_at"`이 오타 나도 초록이다. 그 오타 하나면
// 어드민이 발급 시각을 영영 못 읽는다 — 와이어 키는 라우터에 태워 고정한다(v2.1 검증 규약).
func TestCheckinQREndpoints(t *testing.T) {
	r := newTestRouter(t)

	// 권한: 두 경로 × 두 역할 = 403 네 번.
	for _, role := range []struct{ uid, role string }{
		{"t1", domain.RoleTrainer}, {"member1", domain.RoleMember},
	} {
		if rec := getJSON(t, r, "/v1/center/checkin-qr", role.uid, role.role); rec.Code != http.StatusForbidden {
			t.Errorf("%s GET = %d, want 403", role.role, rec.Code)
		}
		if rec := postJSON(t, r, "/v1/center/checkin-qr/rotate", role.uid, role.role, ""); rec.Code != http.StatusForbidden {
			t.Errorf("%s POST rotate = %d, want 403", role.role, rec.Code)
		}
	}

	// 미발급 조회: 200 + 3키(404가 아니다).
	rec := getJSON(t, r, "/v1/center/checkin-qr", "owner1", domain.RoleOwner)
	if rec.Code != http.StatusOK {
		t.Fatalf("미발급 GET = %d, want 200 — 미발급은 오류가 아니다", rec.Code)
	}
	assertCheckinQRWireKeys(t, rec.Body.Bytes(), false)

	// 발급: 200(201 아님 — 새 리소스가 아니라 같은 리소스의 새 값이다) + 같은 3키.
	rot := postJSON(t, r, "/v1/center/checkin-qr/rotate", "owner1", domain.RoleOwner, "")
	if rot.Code != http.StatusOK {
		t.Fatalf("발급 POST = %d body=%s", rot.Code, rot.Body.String())
	}
	tok := assertCheckinQRWireKeys(t, rot.Body.Bytes(), true)

	// 발급 후 조회가 같은 값을 준다.
	rec2 := getJSON(t, r, "/v1/center/checkin-qr", "owner1", domain.RoleOwner)
	if got := assertCheckinQRWireKeys(t, rec2.Body.Bytes(), true); got != tok {
		t.Errorf("발급 후 조회 토큰 = %q, want %q", got, tok)
	}

	// GET에 rotate를 걸어 두지 않았다(브라우저 프리페치·재시도가 인쇄물을 죽이면 안 된다).
	if bad := getJSON(t, r, "/v1/center/checkin-qr/rotate", "owner1", domain.RoleOwner); bad.Code != http.StatusMethodNotAllowed {
		t.Errorf("GET rotate = %d, want 405 — 파괴적 동사가 GET에 있으면 안 된다", bad.Code)
	}
}

// assertCheckinQRWireKeys — 와이어 3키(issued/token/issued_at)를 고정하고 토큰을 돌려준다.
func assertCheckinQRWireKeys(t *testing.T, body []byte, wantIssued bool) string {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(body, &m); err != nil {
		t.Fatalf("응답 파싱: %v — body=%s", err, body)
	}
	if len(m) != 3 {
		t.Fatalf("응답 키 %d개 %v, want 3(issued/token/issued_at)", len(m), m)
	}
	issued, ok := m["issued"].(bool)
	if !ok {
		t.Fatalf("issued = %v(%T), want bool", m["issued"], m["issued"])
	}
	if issued != wantIssued {
		t.Fatalf("issued = %v, want %v", issued, wantIssued)
	}
	token, ok := m["token"].(string)
	if !ok {
		t.Fatalf("token = %v(%T), want string(미발급이면 \"\")", m["token"], m["token"])
	}
	if !wantIssued {
		if token != "" {
			t.Fatalf("미발급 token = %q, want \"\"", token)
		}
		if m["issued_at"] != nil {
			t.Fatalf("미발급 issued_at = %v, want null", m["issued_at"])
		}
		return ""
	}
	if len(token) != domain.CheckinQRTokenLen {
		t.Fatalf("token 길이 = %d, want %d", len(token), domain.CheckinQRTokenLen)
	}
	at, ok := m["issued_at"].(string)
	if !ok {
		t.Fatalf("issued_at = %v(%T), want RFC3339 문자열", m["issued_at"], m["issued_at"])
	}
	if _, err := time.Parse(time.RFC3339, at); err != nil {
		t.Fatalf("issued_at %q 파싱 실패: %v — 어드민이 발급 시각을 못 읽는다", at, err)
	}
	return token
}

// ---- 데모 시드 ----

// DEV_SEED 데모는 **고정 토큰**을 심는다 — 앱의 dart-define 폴백과 값이 같아야 카메라 없는
// 시뮬레이터·CI가 셀프 체크인을 끝까지 돌려볼 수 있다. 실발급(crypto/rand)이면 매 구동마다
// 값이 달라져 그 통로가 사라진다.
func TestSeedDemoIssuesKnownCheckinToken(t *testing.T) {
	st := store.NewMemory()
	if err := store.SeedDemo(context.Background(), st, testCenter); err != nil {
		t.Fatal(err)
	}
	got, err := st.GetCheckinQR(context.Background(), testCenter)
	if err != nil {
		t.Fatal(err)
	}
	if got.Token != store.DemoCheckinQRToken {
		t.Fatalf("시드 토큰 = %q, want %q — 앱 dart-define 폴백과 어긋나면 데모 체크인이 죽는다",
			got.Token, store.DemoCheckinQRToken)
	}
	if !got.Issued() || got.IssuedAt == nil {
		t.Errorf("시드 상태 = %+v, want 발급됨 — 어드민 데모가 '미발급' 화면으로 뜬다", got)
	}
}

// seedBookingInCheckinWindow — 체크인 시간창(±30분) 안의 confirmed 예약을 스토어에 직접 심는다.
// 현재 정시는 "지난 시간" 예약 거부(v1.3)에 걸리므로 서비스 경로로는 만들 수 없다
// (실플로우: 예약은 며칠 전, 체크인은 수업 시각 — 생성 시점 검증과 무관).
func seedBookingInCheckinWindow(t *testing.T, s *Service, mem *domain.Member, pass *domain.Pass) string {
	t.Helper()
	// 분<30이면 현재 정시, 아니면 다음 정시(경계 :30:xx flaky 방지 — 2R).
	now := time.Now().In(domain.KST)
	slotHour := now
	if now.Minute() >= 30 {
		slotHour = now.Add(time.Hour)
	}
	slotKey := slotHour.Format("20060102") + fmt.Sprintf("-%02d", slotHour.Hour())
	if err := s.store.BookAtomic(context.Background(), testCenter, slotKey, 3, &domain.Booking{
		SlotKey: slotKey, MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
		Kind: domain.BookingKindPT, Status: domain.BookingConfirmed,
	}); err != nil {
		t.Fatal(err)
	}
	return slotKey
}
