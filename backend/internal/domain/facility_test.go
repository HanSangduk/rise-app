package domain

// 시설 신고 상태(P42) 골든값 테스트 — 검증·정규화의 가장자리를 도메인 레벨에서 고정한다
// (서비스 테스트는 경로·권한을, 여기는 판정 자체를 본다. business_test와 같은 분업).

import (
	"errors"
	"strings"
	"testing"
)

func TestFacilityNormalizeFoldsEmptyToUnknown(t *testing.T) {
	f := Facility{ReportStatus: "  ", ReportNo: " 제2026-강남-0001호 ", Insurance: " 서울보증 1억 "}
	f.Normalize()
	if f.ReportStatus != FacilityStatusUnknown {
		t.Errorf("빈 상태 = %q, want unknown — facility 절이 없던 구 문서도 3값 중 하나로 읽혀야 한다", f.ReportStatus)
	}
	if f.ReportNo != "제2026-강남-0001호" || f.Insurance != "서울보증 1억" {
		t.Errorf("공백 정리 실패: %+v", f)
	}
}

func TestFacilityValidate(t *testing.T) {
	// 통과: 3값 전부 + 빈 상태(unknown으로 접힘) + exempt는 번호 없이 정상.
	for _, f := range []Facility{
		{ReportStatus: FacilityStatusUnknown},
		{ReportStatus: ""},
		{ReportStatus: FacilityStatusExempt},
		{ReportStatus: FacilityStatusExempt, Insurance: "서울보증 인허가보증보험, 보장한도 1억원"},
		{ReportStatus: FacilityStatusReported, ReportNo: "제2026-강남-0001호"},
	} {
		if err := f.Validate(); err != nil {
			t.Errorf("Validate(%+v) = %v, want nil", f, err)
		}
	}

	// 거부: enum 밖 상태 / 번호 없는(공백뿐인) reported / 길이 상한 초과.
	for _, c := range []struct {
		name string
		f    Facility
	}{
		{"미지 상태", Facility{ReportStatus: "studio"}},
		{"대문자 상태(정규화 대상 아님 — 클라이언트 계약 위반)", Facility{ReportStatus: "Reported", ReportNo: "제1호"}},
		{"reported 번호 없음", Facility{ReportStatus: FacilityStatusReported}},
		{"reported 번호 공백뿐", Facility{ReportStatus: FacilityStatusReported, ReportNo: "   "}},
		{"번호 41자", Facility{ReportStatus: FacilityStatusReported, ReportNo: strings.Repeat("가", 41)}},
		{"보험 201자", Facility{ReportStatus: FacilityStatusExempt, Insurance: strings.Repeat("가", 201)}},
	} {
		if err := c.f.Validate(); !errors.Is(err, ErrInvalidFacility) {
			t.Errorf("%s: Validate = %v, want ErrInvalidFacility", c.name, err)
		}
	}

	// 경계값은 통과(40자 번호·200자 보험) — 상한이 하나 어긋나면 실제 지자체 표기를 막는다.
	edge := Facility{
		ReportStatus: FacilityStatusReported,
		ReportNo:     strings.Repeat("가", 40),
		Insurance:    strings.Repeat("가", 200),
	}
	if err := edge.Validate(); err != nil {
		t.Errorf("경계값 거부: %v", err)
	}

	// Validate는 값 복사본에서 정규화한다 — 호출자의 원본을 바꾸지 않는다(Business와 같은 규약).
	orig := Facility{ReportStatus: "", ReportNo: " x "}
	_ = orig.Validate()
	if orig.ReportStatus != "" || orig.ReportNo != " x " {
		t.Errorf("Validate가 원본을 고쳤다: %+v", orig)
	}
}
