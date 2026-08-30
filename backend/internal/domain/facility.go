package domain

import (
	"errors"
	"strings"
)

// ErrInvalidFacility — 시설 신고 상태 입력 위반(400 매핑, PUT /v1/center/facility v2.19).
var ErrInvalidFacility = errors.New("domain: invalid facility")

func errFacility(msg string) error { return errors.Join(ErrInvalidFacility, errors.New(msg)) }

// 시설 신고 상태 3단(P42). "서식 취향"이 아니라 **법적 사실의 선언**이다 — 계약서 템플릿
// 2종(pt-v1-reported / pt-v1-exempt) 중 무엇으로 스탬프할지가 이 값의 함수다(api 레지스트리).
const (
	// FacilityStatusUnknown — 아직 선언하지 않음(기본값). 이 상태에서는 계약서 스탬프가
	// 스킵된다 — 모르는 상태로 문서를 만들지 않는다(P39 래치와 같은 철학, P42).
	FacilityStatusUnknown = "unknown"
	// FacilityStatusReported — 체육시설업(체력단련장업) 신고 완료. 신고번호가 계약서
	// 당사자 표에 인쇄된다(체육시설법 제10조 제1항 제2호 — 신고 체육시설업).
	FacilityStatusReported = "reported"
	// FacilityStatusExempt — 신고 대상 아님을 **확인했다**는 선언(지자체 유권해석·기구
	// 미비치 강습 전용 — 계약서doc :812 각주: 시행규칙 별표4에 면적 하한이 없어 "소규모라
	// 면제"는 성립하지 않고, 기구 없는 순수 PT룸의 포섭 여부만 유권해석 영역이다). 계약서
	// 에서 신고번호 행이 빠진다(:818 "신고 대상이 아니라는 유권해석을 받았다면 이 행을 뺀다").
	FacilityStatusExempt = "exempt"
)

// 자유 입력 칸 길이 상한(Business의 칸 상한과 같은 취지 — 계약서에 그대로 인쇄되는 값이라
// 레이아웃을 깨는 길이를 막는다).
const (
	facilityReportNoMax  = 40  // 신고번호(예: "제2026-000000호" — 지자체 표기 편차 여유)
	facilityInsuranceMax = 200 // 보증보험 종류·보장내용(자유 서술 한 줄)
)

// Facility — 센터의 체육시설업 신고 상태 선언 + 그에 딸린 계약서 기재값(P42).
//
// **Business 밖에 두는 이유**(P42 결정 — P39 결정 6의 연장): Business에 칸을 늘리면
// IsComplete(12칸 전부) 판정에 끼어들어 법정 문서 4장이 초안 배너로 되돌아간다 — 신고
// 대상이 아닌 센터는 신고번호를 영원히 못 채우므로 영원히 "미완성"이 된다. 신고 상태는
// 완성도가 아니라 **3값 선언**이고, 그 선언은 문서 게시가 아니라 계약서 템플릿 선택을
// 바꾼다 — 바뀌는 이유·주기·소비자가 전부 달라 절이 다르다.
//
// 저장은 centers/{id} 문서의 `facility` 맵이다(center·business와 같은 네스팅 규약 +
// 머지 쓰기 — P27 SavePolicy 교훈: 통 Set은 같은 문서의 동거 절을 지운다).
type Facility struct {
	// ReportStatus — unknown / reported / exempt. 빈 값은 Normalize가 unknown으로 접는다
	// (facility 절이 아예 없던 구 문서도 "모름"이 정직한 기본값이다).
	ReportStatus string `json:"report_status"`
	// ReportNo — 체육시설업 신고번호. reported일 때 필수(계약서 당사자 표에 인쇄된다).
	// 다른 상태에서의 저장은 막지 않는다 — 저장과 판정을 분리하는 Business.Validate와 같은
	// 태도이고, 값의 소비(스탬프)는 어차피 reported 변형만 한다(exempt 키 목록에 이 슬롯이 없다).
	ReportNo string `json:"report_no"`
	// Insurance — 보증보험 종류·보장내용(자유 서술). 빈 값 = 미가입이며 **그 자체로 정직한
	// 계약 내용**이다 — 계약서에는 제20조③의 자체 설계대로 "가입하지 않았습니다"로 찍힌다
	// (변환은 조립기(api contractVarValue) 몫 — 저장은 입력 사실 그대로).
	Insurance string `json:"insurance"`
}

// Normalize — 저장·응답 직전 표기 정리(Business.Normalize와 같은 규약). 빈 상태는 unknown
// 으로 접는다 — 어느 경로로 읽든 응답·스탬프 게이트가 늘 3값 중 하나를 본다.
func (f *Facility) Normalize() {
	f.ReportStatus = strings.TrimSpace(f.ReportStatus)
	if f.ReportStatus == "" {
		f.ReportStatus = FacilityStatusUnknown
	}
	f.ReportNo = strings.TrimSpace(f.ReportNo)
	f.Insurance = strings.TrimSpace(f.Insurance)
}

// Validate — 상태 enum + reported⇒신고번호 필수 + 길이 상한.
//
// reported⇒번호 필수를 저장 게이트에서 강제하는 것은 Business(미완성 저장 허용)와 다른
// 선택이다. 이유: 이 값은 "아는 칸부터 채우는" 진행형 입력이 아니라 **한 번의 선언**이고,
// 번호 없는 "신고했음"은 중간 상태가 아니라 검증 불가능한 주장이라 — 허용하면 계약서
// 게이트(unknown 스킵)를 번호 없이 통과해 신고번호 슬롯 결측으로만 표면화되는 구멍이 된다.
func (f Facility) Validate() error {
	f.Normalize() // 값 복사본 — 호출자의 공백 유무가 판정을 가르지 않게 같은 모양에서 본다
	switch f.ReportStatus {
	case FacilityStatusUnknown, FacilityStatusReported, FacilityStatusExempt:
	default:
		return errFacility("report_status는 unknown/reported/exempt 중 하나여야 해요")
	}
	if f.ReportStatus == FacilityStatusReported && f.ReportNo == "" {
		return errFacility("신고 완료로 선택하면 체육시설업 신고번호를 입력해야 해요")
	}
	if len([]rune(f.ReportNo)) > facilityReportNoMax {
		return errFacility("체육시설업 신고번호는 " + itoa(facilityReportNoMax) + "자까지예요")
	}
	if len([]rune(f.Insurance)) > facilityInsuranceMax {
		return errFacility("보증보험 종류·보장내용은 " + itoa(facilityInsuranceMax) + "자까지예요")
	}
	return nil
}
