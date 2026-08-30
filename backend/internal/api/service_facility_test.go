package api

// 시설 신고 상태 선언(P42, 계약 v2.19)의 서비스/라우터 테스트. 축 네 개: 권한(owner 전용) /
// 검증(enum·reported⇒번호) / 왕복·기본값(unknown) / **머지 회귀**(facility 저장이 Policy·
// Business를 지우지 않는다 — P27 SavePolicy 사고의 세 번째 절 재발 방지).

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

// 신고 상태 선언은 owner 전용이다 — 계약서에 인쇄되는 법적 선언이라 정책·사업자 정보와 같은
// 권한 선을 쓴다. 트레이너가 상태를 바꿀 수 있으면 계약서 템플릿(신고번호 행 유무)이 바뀐다.
func TestUpdateCenterFacilityOwnerOnly(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	fac := domain.Facility{ReportStatus: domain.FacilityStatusReported, ReportNo: "제2026-강남-0001호"}

	for _, p := range []Principal{trainerP(), memberP("m1")} {
		if _, err := s.UpdateCenterFacility(ctx, p, fac); !errors.Is(err, ErrForbidden) {
			t.Errorf("%s의 시설 신고 상태 편집이 통과: %v", p.Role, err)
		}
	}
	saved, err := s.UpdateCenterFacility(ctx, ownerP(), fac)
	if err != nil {
		t.Fatalf("owner 저장 실패: %v", err)
	}
	if saved.ReportStatus != domain.FacilityStatusReported || saved.ReportNo != "제2026-강남-0001호" {
		t.Errorf("저장 응답 = %+v, want 입력 그대로", saved)
	}
}

// 검증 게이트: 상태는 3값 enum이고, reported는 신고번호가 필수다(번호 없는 "신고했음"은
// 검증 불가능한 주장 — unknown 스킵 게이트를 우회하는 구멍이 된다). exempt·unknown은 번호
// 없이 저장된다(그게 정상 상태다).
func TestUpdateCenterFacilityValidation(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	for _, c := range []struct {
		name string
		fac  domain.Facility
	}{
		{"미지 상태", domain.Facility{ReportStatus: "studio"}},
		{"reported인데 번호 없음", domain.Facility{ReportStatus: domain.FacilityStatusReported}},
		{"reported인데 번호가 공백뿐", domain.Facility{ReportStatus: domain.FacilityStatusReported, ReportNo: "   "}},
	} {
		if _, err := s.UpdateCenterFacility(ctx, ownerP(), c.fac); !errors.Is(err, domain.ErrInvalidFacility) {
			t.Errorf("%s: err = %v, want ErrInvalidFacility(400)", c.name, err)
		}
	}
	for _, c := range []domain.Facility{
		{ReportStatus: domain.FacilityStatusExempt},
		{ReportStatus: domain.FacilityStatusUnknown},
		{ReportStatus: ""}, // 빈 상태는 unknown으로 접힌다(Normalize) — 되돌리기 손잡이
		{ReportStatus: domain.FacilityStatusExempt, Insurance: "서울보증 1억"},
	} {
		if _, err := s.UpdateCenterFacility(ctx, ownerP(), c); err != nil {
			t.Errorf("정상 입력 %+v이 거부됐다: %v", c, err)
		}
	}
}

// 왕복 + 기본값: 미선언 센터의 GET /v1/center는 facility={unknown,"",""}를 내려보내고
// (어드민 라디오의 초기 상태), 선언 후에는 저장값이 그대로 돌아온다. 재선언은 절 통 교체다 —
// 이전 신고번호가 유령으로 남지 않는다.
func TestCenterFacilityRoundTripAndDefaults(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	got, err := s.GetCenter(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if got.Facility.ReportStatus != domain.FacilityStatusUnknown || got.Facility.ReportNo != "" || got.Facility.Insurance != "" {
		t.Fatalf("미선언 facility = %+v, want {unknown,\"\",\"\"}", got.Facility)
	}

	if _, err := s.UpdateCenterFacility(ctx, ownerP(), domain.Facility{
		ReportStatus: domain.FacilityStatusReported, ReportNo: " 제2026-강남-0001호 ", Insurance: " 서울보증 1억 ",
	}); err != nil {
		t.Fatal(err)
	}
	got, err = s.GetCenter(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	// 공백은 저장 전에 정리된다(붙여넣기 공백이 계약서에 인쇄되면 안 된다).
	if got.Facility.ReportStatus != domain.FacilityStatusReported || got.Facility.ReportNo != "제2026-강남-0001호" || got.Facility.Insurance != "서울보증 1억" {
		t.Fatalf("재조회 = %+v, want 정규화된 저장값", got.Facility)
	}

	// exempt로 재선언(번호·보험 비움) — 통 교체가 반영돼야 잘못 적은 선언을 지울 수 있다.
	if _, err := s.UpdateCenterFacility(ctx, ownerP(), domain.Facility{ReportStatus: domain.FacilityStatusExempt}); err != nil {
		t.Fatal(err)
	}
	got, _ = s.GetCenter(ctx, ownerP())
	if got.Facility.ReportStatus != domain.FacilityStatusExempt || got.Facility.ReportNo != "" {
		t.Fatalf("재선언 = %+v, want {exempt,\"\",\"\"} — 이전 신고번호가 남았다", got.Facility)
	}

	// member도 GET /v1/center에서 facility를 본다 — Business와 같은 이유(계약서에 인쇄되는
	// 값이라 민감 정보가 아니다). 역할별로 가리기 시작하면 화면마다 다른 답이 된다.
	mem, _ := seedMemberWithPass(t, s, 10)
	memGot, err := s.GetCenter(ctx, memberP(mem.ID))
	if err != nil {
		t.Fatal(err)
	}
	if memGot.Facility.ReportStatus != domain.FacilityStatusExempt {
		t.Errorf("member 조회 facility = %+v, want owner와 동일", memGot.Facility)
	}
}

// **머지 회귀(P27의 세 번째 절)**: facility 저장이 같은 centers 문서에 동거하는 Policy·
// Business를 지우면 안 되고, 반대 방향(정책·사업자 저장)도 facility를 지우면 안 된다.
// 스토어 레벨 컨포먼스(testFacilityCoexist)와 별개로 서비스 경로 전체를 태워 고정한다 —
// v2.13 배포 전 "정책 하나 바꾸면 법정 문서 5장이 초안으로"와 같은 모양의 사고 방지.
func TestCenterFacilitySaveKeepsBusinessAndPolicy(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	if _, err := s.UpdateCenterBusiness(ctx, ownerP(), []byte(completeBusinessJSON)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"slot_capacity":4}`)); err != nil {
		t.Fatal(err)
	}

	if _, err := s.UpdateCenterFacility(ctx, ownerP(), domain.Facility{
		ReportStatus: domain.FacilityStatusReported, ReportNo: "제2026-강남-0001호", Insurance: "서울보증 1억",
	}); err != nil {
		t.Fatal(err)
	}

	got, err := s.GetCenter(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if !got.Business.Complete || got.Business.BizName != "라이즈 컨디셔닝" {
		t.Errorf("facility 저장 후 사업자 정보 = %+v — 법정 문서가 초안으로 되돌아간다(P27 재발)", got.Business)
	}
	if got.Policy.SlotCapacity != 4 {
		t.Errorf("facility 저장 후 slot_capacity = %d, want 4 — 정책이 덮였다", got.Policy.SlotCapacity)
	}
	if got.Facility.ReportStatus != domain.FacilityStatusReported {
		t.Errorf("facility 자체가 저장되지 않았다: %+v", got.Facility)
	}

	// 반대 방향: 정책·사업자 저장이 신고 선언을 지우면 스탬프가 조용히 unknown 스킵으로
	// 꺼진다 — 증상이 "계약서가 안 만들어져요"로만 보이는 최악의 퇴행이라 방향도 고정한다.
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"slot_capacity":5}`)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterBusiness(ctx, ownerP(), []byte(completeBusinessJSON)); err != nil {
		t.Fatal(err)
	}
	got, _ = s.GetCenter(ctx, ownerP())
	if got.Facility.ReportStatus != domain.FacilityStatusReported || got.Facility.ReportNo == "" {
		t.Errorf("정책·사업자 저장 후 facility = %+v — 신고 선언이 지워졌다", got.Facility)
	}
}

// 라우터 레벨: 경로 등록(PUT /v1/center/facility) + 상태코드 매핑(200/403/400) + 응답 모양.
// **응답은 저장된 facility 그 자체다**(3키 — 어드민 saveFacility가 이 모양으로 폼을 재장전한다.
// 센터 캐시는 keys.center 무효화 → GET 재조회로 따로 맞추는 것이 P42 어드민 규약).
func TestCenterFacilityEndpoint(t *testing.T) {
	r := newTestRouter(t)

	if rec := putJSON(t, r, "/v1/center/facility", "t1", domain.RoleTrainer,
		`{"report_status":"exempt","report_no":"","insurance":""}`); rec.Code != http.StatusForbidden {
		t.Errorf("trainer PUT = %d, want 403", rec.Code)
	}
	if rec := putJSON(t, r, "/v1/center/facility", "owner1", domain.RoleOwner,
		`{"report_status":"reported","report_no":"","insurance":""}`); rec.Code != http.StatusBadRequest {
		t.Errorf("번호 없는 reported = %d, want 400", rec.Code)
	}
	if rec := putJSON(t, r, "/v1/center/facility", "owner1", domain.RoleOwner,
		`{"report_status":"open-soon","report_no":"","insurance":""}`); rec.Code != http.StatusBadRequest {
		t.Errorf("미지 상태 = %d, want 400", rec.Code)
	}

	rec := putJSON(t, r, "/v1/center/facility", "owner1", domain.RoleOwner,
		`{"report_status":"reported","report_no":" 제2026-강남-0001호 ","insurance":"서울보증 1억"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("owner PUT = %d body=%s", rec.Code, rec.Body.String())
	}
	var res map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("응답 파싱: %v — facility 3키 평면 객체여야 한다", err)
	}
	// 키 집합 자체를 고정한다 — policy/business가 끼어들면 어드민 재장전 파서가 깨지진 않지만
	// "이 절만 만진다"는 엔드포인트 의미가 무너지고, 언젠가 민감 필드가 무임승차한다.
	if len(res) != 3 {
		t.Fatalf("응답 키 %d개 %v, want 3(report_status/report_no/insurance)", len(res), res)
	}
	if res["report_status"] != "reported" || res["report_no"] != "제2026-강남-0001호" || res["insurance"] != "서울보증 1억" {
		t.Errorf("응답 = %v, want 정규화된 저장값(공백 정리 포함)", res)
	}

	// GET /v1/center에는 facility 절이 실려 온다(어드민 최초 로드 경로).
	req := httptest.NewRequest(http.MethodGet, "/v1/center", nil)
	req.Header.Set("X-Dev-Uid", "owner1")
	req.Header.Set("X-Dev-Role", domain.RoleOwner)
	getRec := httptest.NewRecorder()
	r.ServeHTTP(getRec, req)
	if getRec.Code != http.StatusOK {
		t.Fatalf("GET /v1/center = %d", getRec.Code)
	}
	var center struct {
		Facility domain.Facility `json:"facility"`
	}
	if err := json.Unmarshal(getRec.Body.Bytes(), &center); err != nil {
		t.Fatal(err)
	}
	if center.Facility.ReportStatus != domain.FacilityStatusReported || center.Facility.ReportNo != "제2026-강남-0001호" {
		t.Errorf("GET facility = %+v, want 저장값", center.Facility)
	}
}
