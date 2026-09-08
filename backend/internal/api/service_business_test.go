package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

const completeBusinessJSON = `{
  "biz_name":"라이즈 컨디셔닝","ceo_name":"김대표","biz_reg_no":"123-45-67890",
  "address":"서울특별시 강남구 테헤란로 123, 4층","phone":"02-1234-5678","email":"hello@rise.kr",
  "privacy_officer_name":"김대표","privacy_officer_title":"대표","privacy_officer_email":"privacy@rise.kr",
  "privacy_dept":"고객지원팀","privacy_manager":"박담당","effective_date":"2026-09-01"
}`

// PUT 헬퍼는 service_staff_test.go의 putJSON을 재사용한다(같은 패키지).

// 사업자 정보 편집은 owner 전용이다(정책 편집과 같은 권한). 트레이너가 법정 고지 기재사항을
// 바꿀 수 있으면 약관·처리방침의 책임 주체가 바뀐다.
func TestUpdateCenterBusinessOwnerOnly(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	for _, p := range []Principal{trainerP(), memberP("m1")} {
		if _, err := s.UpdateCenterBusiness(ctx, p, []byte(completeBusinessJSON)); !errors.Is(err, ErrForbidden) {
			t.Errorf("%s의 사업자 정보 편집이 통과: %v", p.Role, err)
		}
	}
	view, err := s.UpdateCenterBusiness(ctx, ownerP(), []byte(completeBusinessJSON))
	if err != nil {
		t.Fatalf("owner 저장 실패: %v", err)
	}
	if !view.Complete {
		t.Errorf("12칸을 다 채웠는데 complete=false — 미기재: %v", view.MissingFields())
	}
}

// 부분 입력은 저장되지만 complete가 아니다. 이 구분이 무너지면 법정 문서가 빈칸을 품은 채
// "시행 중"으로 게시된다(도메인 테스트와 짝 — 여기서는 저장 왕복까지 확인한다).
func TestCenterBusinessPartialRoundTrip(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	partial := `{"biz_name":"라이즈 컨디셔닝","ceo_name":"김대표","effective_date":"2026-09-01"}`
	view, err := s.UpdateCenterBusiness(ctx, ownerP(), []byte(partial))
	if err != nil {
		t.Fatalf("부분 입력 저장이 거부됐다: %v — 아는 칸부터 채우는 동선을 막으면 안 된다", err)
	}
	if view.Complete {
		t.Fatal("3칸만 채웠는데 complete=true — 문서가 빈칸인 채로 시행된다")
	}
	got, err := s.GetCenter(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if got.Business.BizName != "라이즈 컨디셔닝" || got.Business.Complete {
		t.Errorf("재조회 = %+v, want 저장값 보존 + complete=false", got.Business)
	}
	if len(got.Business.MissingFields()) != 9 {
		t.Errorf("미기재 %d개, want 9개(12 - 채운 3)", len(got.Business.MissingFields()))
	}
}

// **통 교체 시맨틱**(정책의 머지와 반대) — 잘못 적은 칸을 비워서 지울 수 있어야 한다.
// 머지였다면 한 번 들어간 오타를 지울 방법이 없다.
func TestCenterBusinessReplacesNotMerges(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	if _, err := s.UpdateCenterBusiness(ctx, ownerP(), []byte(completeBusinessJSON)); err != nil {
		t.Fatal(err)
	}
	// 상호만 남기고 전부 지우는 재제출.
	if _, err := s.UpdateCenterBusiness(ctx, ownerP(), []byte(`{"biz_name":"라이즈 컨디셔닝"}`)); err != nil {
		t.Fatal(err)
	}
	got, _ := s.GetCenter(ctx, ownerP())
	if got.Business.CeoName != "" || got.Business.Email != "" {
		t.Errorf("통 교체가 아니라 머지됐다: %+v — 오타를 지울 수단이 사라진다", got.Business)
	}
	if got.Business.Complete {
		t.Error("한 칸만 남았는데 complete=true")
	}
}

// **회귀 방지의 핵심**: 정책만 저장하는 기존 어드민 호출이 사업자 정보를 지우면 안 된다.
// 지워지면 대표가 예약 용량 하나 바꾼 순간 법정 문서 5장이 동시에 초안으로 되돌아간다.
func TestPolicyUpdateDoesNotWipeBusiness(t *testing.T) {
	r, svc := newBusinessTestRouter(t)
	ctx := context.Background()

	if _, err := svc.UpdateCenterBusiness(ctx, ownerP(), []byte(completeBusinessJSON)); err != nil {
		t.Fatal(err)
	}
	rec := putJSON(t, r, "/v1/center", "owner1", domain.RoleOwner, `{"policy":{"slot_capacity":4}}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("정책 PUT = %d %s", rec.Code, rec.Body.String())
	}
	var res CenterResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatal(err)
	}
	if res.Policy.SlotCapacity != 4 {
		t.Errorf("정책이 저장되지 않았다: %+v", res.Policy)
	}
	if !res.Business.Complete || res.Business.BizName != "라이즈 컨디셔닝" {
		t.Errorf("정책 PUT이 사업자 정보를 지웠다: %+v", res.Business)
	}
	// 반대 방향도 — 사업자 정보만 보내는 PUT이 정책을 되돌리면 안 된다.
	rec = putJSON(t, r, "/v1/center", "owner1", domain.RoleOwner, `{"business":`+completeBusinessJSON+`}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("사업자 정보 PUT = %d %s", rec.Code, rec.Body.String())
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	if res.Policy.SlotCapacity != 4 {
		t.Errorf("사업자 정보 PUT이 정책을 되돌렸다: %+v", res.Policy)
	}
}

// 형식 위반은 저장 전에 400 + 한국어 문구다(Go 에러 원문·내부 마커 노출 금지 — 계약 규약).
func TestCenterBusinessValidationIsUserFacing400(t *testing.T) {
	r, _ := newBusinessTestRouter(t)

	for _, c := range []struct{ name, body, want string }{
		{"등록번호 자릿수", `{"biz_reg_no":"123-45-678"}`, "사업자등록번호"},
		{"이메일 형식", `{"email":"hello"}`, "대표 이메일"},
		{"보호책임자 이메일", `{"privacy_officer_email":"a@b"}`, "보호책임자 이메일"},
		{"시행일 형식", `{"effective_date":"2026-9-1"}`, "시행일"},
		{"없는 날짜", `{"effective_date":"2026-02-30"}`, "시행일"},
		{"대표 전화", `{"phone":"전화없음"}`, "대표 전화"},
	} {
		rec := putJSON(t, r, "/v1/center", "owner1", domain.RoleOwner, `{"business":`+c.body+`}`)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: = %d %s, want 400", c.name, rec.Code, rec.Body.String())
			continue
		}
		var e errBody
		_ = json.Unmarshal(rec.Body.Bytes(), &e)
		if !strings.Contains(e.Error, c.want) {
			t.Errorf("%s: 메시지 %q에 %q가 없다", c.name, e.Error, c.want)
		}
		if strings.Contains(e.Error, "domain:") || strings.Contains(e.Error, "api:") {
			t.Errorf("%s: 내부 마커가 노출됐다: %q", c.name, e.Error)
		}
	}

	// 아무것도 안 보낸 PUT은 400(무엇을 저장하라는 건지 알 수 없다).
	if rec := putJSON(t, r, "/v1/center", "owner1", domain.RoleOwner, `{}`); rec.Code != http.StatusBadRequest {
		t.Errorf("빈 PUT = %d, want 400", rec.Code)
	}
	// 모르는 필드는 여전히 거부된다(DisallowUnknownFields — 계약 필드명 오타를 조기에 드러낸다).
	body := `{"business":{"biz_name":"x","사업자명":"y"}}`
	if rec := putJSON(t, r, "/v1/center", "owner1", domain.RoleOwner, body); rec.Code != http.StatusBadRequest {
		t.Errorf("미지 필드 PUT = %d, want 400", rec.Code)
	}
}

// ---- 무인증 공개 경로 ----

// 법정 고지 HTML은 로그인 없이 열리는 웹 페이지다 — 두 접두사 모두에서 **인증 없이** 200이어야 한다.
// (/api/v1은 Firebase Hosting 리라이트가 접두사를 안 벗겨서 필요하다, P07.)
func TestPublicBusinessNeedsNoAuth(t *testing.T) {
	r, svc := newBusinessTestRouter(t)
	if _, err := svc.UpdateCenterBusiness(context.Background(), ownerP(), []byte(completeBusinessJSON)); err != nil {
		t.Fatal(err)
	}

	for _, path := range []string{"/v1/public/business", "/api/v1/public/business"} {
		rec := httptest.NewRecorder()
		// 인증 헤더를 **일부러 하나도 싣지 않는다**.
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("무인증 GET %s = %d %s, want 200", path, rec.Code, rec.Body.String())
		}
		var view BusinessView
		if err := json.Unmarshal(rec.Body.Bytes(), &view); err != nil {
			t.Fatalf("%s 응답 파싱: %v", path, err)
		}
		if !view.Complete || view.BizName != "라이즈 컨디셔닝" {
			t.Errorf("%s 응답 = %+v", path, view)
		}
		if cc := rec.Header().Get("Cache-Control"); !strings.Contains(cc, "max-age=") {
			t.Errorf("%s Cache-Control = %q — 무인증 경로에 캐시가 없으면 문서 조회가 그대로 DB 읽기가 된다", path, cc)
		}
	}

	// 무인증 표면은 /v1/public/business·/v1/public/center(v2.29) 둘뿐이다 — 인증 라우트가 함께 열리면 안 된다.
	for _, path := range []string{"/v1/center", "/api/v1/center", "/v1/me", "/v1/members"} {
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("무인증 GET %s = %d, want 401(공개 라우트 추가가 인증을 뚫었다)", path, rec.Code)
		}
	}
}

// **노출 범위 잠금**: 공개 응답의 키 집합을 통째로 고정한다. GET /v1/center에 필드가 늘어도
// 여기로 새지 않아야 한다 — 특히 연 매출 목표(owner 전용)와 위약금율은 익명에게 나갈 값이 아니다.
// 키를 하나 늘릴 때 이 테스트가 반드시 걸리게 해서, 추가가 **의식적인 결정**이 되게 한다.
func TestPublicBusinessExposesOnlyLegalFields(t *testing.T) {
	r, svc := newBusinessTestRouter(t)
	ctx := context.Background()
	if _, err := svc.UpdateCenterBusiness(ctx, ownerP(), []byte(completeBusinessJSON)); err != nil {
		t.Fatal(err)
	}
	// 정책에 실값을 넣어 둔다 — 새면 여기서 드러난다.
	if _, err := svc.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"revenue_target":120000000}`)); err != nil {
		t.Fatal(err)
	}

	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/public/business", nil))

	var raw map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{
		"biz_name": true, "ceo_name": true, "biz_reg_no": true, "address": true,
		"phone": true, "email": true, "privacy_officer_name": true,
		"privacy_officer_title": true, "privacy_officer_email": true,
		"privacy_dept": true, "privacy_manager": true, "effective_date": true,
		"complete": true,
	}
	for k := range raw {
		if !want[k] {
			t.Errorf("공개 응답에 예정에 없던 키 %q가 있다 — 법정 기재사항만 나가야 한다", k)
		}
	}
	for k := range want {
		if _, ok := raw[k]; !ok {
			t.Errorf("공개 응답에 %q가 빠졌다 — 문서가 그 칸을 채우지 못한다", k)
		}
	}
	// 이름을 직접 짚어 한 번 더(키 집합 검사가 느슨해져도 이 셋은 남는다).
	for _, forbidden := range []string{"policy", "center_id", "revenue_target", "penalty_rate", "slot_capacity"} {
		if _, ok := raw[forbidden]; ok {
			t.Errorf("공개 응답에 %q가 노출됐다", forbidden)
		}
	}
	if strings.Contains(rec.Body.String(), "120000000") {
		t.Error("공개 응답 본문에 연 매출 목표 값이 들어 있다")
	}
}

// 미등록 센터에서도 공개 경로는 200 + 빈 값 + complete=false다(404가 아니다) — 문서가
// "불러오지 못함"과 "아직 등록 전"을 구분해 초안 배너를 유지할 수 있어야 한다.
// 그리고 **읽기가 문서를 만들지 않는다**: 익명 요청이 쓰기를 유발하면 안 된다.
func TestPublicBusinessEmptyWhenUnregistered(t *testing.T) {
	r, svc := newBusinessTestRouter(t)

	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/public/business", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("미등록 센터 = %d %s, want 200", rec.Code, rec.Body.String())
	}
	var view BusinessView
	_ = json.Unmarshal(rec.Body.Bytes(), &view)
	if view.Complete || view.BizName != "" {
		t.Errorf("미등록 응답 = %+v, want 빈 값 + complete=false", view)
	}
	// 조회 후에도 저장된 사업자 정보는 없어야 한다(지연 시딩 금지).
	got, err := svc.store.GetBusiness(context.Background(), testCenter)
	if err != nil || got.IsComplete() {
		t.Errorf("무인증 조회가 문서를 만들었다: %+v (err=%v)", got, err)
	}
}

// 공개 경로는 읽기 전용이다 — 다른 메서드로 뚫리면 안 된다.
func TestPublicBusinessIsReadOnly(t *testing.T) {
	r, _ := newBusinessTestRouter(t)
	for _, m := range []string{http.MethodPut, http.MethodPost, http.MethodDelete} {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(m, "/v1/public/business", strings.NewReader(completeBusinessJSON))
		r.ServeHTTP(rec, req)
		if rec.Code == http.StatusOK {
			t.Errorf("%s /v1/public/business가 200 — 무인증 쓰기 경로가 열렸다", m)
		}
	}
}

// newBusinessTestRouter — 라우터와 서비스를 **같은 스토어로** 함께 돌려준다. 픽스처는 서비스로
// 심고 검사는 HTTP로 하기 때문에 둘이 같은 스토어를 봐야 한다(newTestRouter는 서비스를
// 돌려주지 않아 이 파일에서 쓸 수 없다).
func newBusinessTestRouter(t *testing.T) (http.Handler, *Service) {
	t.Helper()
	svc := newTestService()
	auth, err := NewAuthenticator(context.Background(), svc.cfg, svc.store)
	if err != nil {
		t.Fatalf("NewAuthenticator: %v", err)
	}
	return NewRouter(NewHandlers(svc), auth, nil), svc
}
