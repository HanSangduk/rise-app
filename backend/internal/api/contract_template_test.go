package api

// 계약서 템플릿 레지스트리·Vars 조립·canonical_json 봉인의 순수 함수 테스트(P39, 계약 v2.18).
// 골든 값(canonical 문자열·sha256 hex)은 **구현과 독립적으로**(python json.dumps + hashlib)
// 재도출해 박았다 — 구현이 스스로 낸 값을 스스로 확인하는 순환을 피한다.

import (
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// P39→P42→**P48**: 레지스트리는 신고 상태 2변형(reported 25종 / exempt 24종)이고, 2026-08-30
// 대표 결정으로 둘 다 **발행 래치 ON**(issuable=true, 계약 v2.22)이다. 이 단언의 방향이
// 뒤집힌 것이지 역할이 사라진 것이 아니다 — 이제는 **의도치 않은 되돌림**(누군가 false로
// 돌려놓고 배포해 계약서 발행이 조용히 멈추는 사고)을 잡는다. 래치를 실제로 내릴 때는 이
// 테스트와 계약 문서를 함께 고쳐야 한다(조용한 변경 금지).
//
// 키 목록은 계약서doc §C의 슬롯명과 바이트 단위로 같아야 한다(앱 템플릿 자산의 {{...}}와
// 매칭) — 여기 박아 고정한다. **두 목록의 차는 정확히 신고번호 한 키다**(:818 "행을 뺀다")
// — 이 단언이 변형 분리 자체의 회귀 감시다.
func TestContractVariantRegistryIssuableAndKeys(t *testing.T) {
	wantBase := []string{
		"상품명", "계약금액", "위약금율", "총 회차", "유효기간 시작일", "유효기간 종료일",
		"담당 트레이너명", "회원명", "회원 전화번호", "결제방법", "납부일정",
		"취소 마감 시간", "노쇼 유예 적용 여부", "홀딩 최대 횟수", "홀딩 최대 일수", "슬롯 정원",
		"사업자명", "대표자명", "사업자등록번호", "사업장 주소", "대표 전화", "대표 이메일",
	}
	wantExempt := append(append([]string{}, wantBase...), "약관 게시 주소", "보증보험 종류·보장내용")
	wantReported := append(append([]string{}, wantExempt...), "체육시설업 신고번호")
	if len(wantExempt) != 24 || len(wantReported) != 25 {
		t.Fatalf("기대 목록 자체가 24/25종이 아니다: %d/%d", len(wantExempt), len(wantReported)) // 테스트 오타 방지
	}
	for _, c := range []struct {
		ver  string
		want []string
	}{
		{contractTemplatePTv1Reported, wantReported},
		{contractTemplatePTv1Exempt, wantExempt},
	} {
		tpl, ok := contractTemplates[c.ver]
		if !ok {
			t.Fatalf("%s가 레지스트리에 없다", c.ver)
		}
		if !tpl.issuable {
			t.Errorf("%s issuable=false — 발행 래치는 대표 결정으로 켜져 있어야 한다(P48, 계약 v2.22). "+
				"의도적으로 내리는 것이라면 이 단언과 API계약 문서를 함께 고쳐라", c.ver)
		}
		if !reflect.DeepEqual(tpl.requiredVarKeys, c.want) {
			t.Errorf("%s 요구 슬롯이 §C와 다르다:\n got %q\nwant %q", c.ver, tpl.requiredVarKeys, c.want)
		}
	}
	// pt-v1(P39 단일 버전)은 폐기됐다 — 스탬프 이력 0건(래치가 켜진 적 없음)이라 삭제가
	// 안전하고, 남겨 두면 "레지스트리에 있는데 어느 상태도 가리키지 않는 버전"이라는 죽은
	// 상태가 생긴다.
	if _, ok := contractTemplates["pt-v1"]; ok {
		t.Error("폐기된 pt-v1이 레지스트리에 남아 있다")
	}
	if !contractStampLatchOn() {
		t.Error("프로덕션 레지스트리 상태에서 발행 사전 게이트가 닫혀 있다 — P48 래치 ON이 무력화됐다")
	}
}

// P42 버전 선택(순수 함수) — P48 래치 ON 기준으로 갱신. unknown(및 미지 값)은 여전히
// **미선언 스킵**이다: 래치가 열려도 모르는 상태로 문서를 만들지 않는다. 이 갈래가 지금
// 프로덕션에서 실제로 발행을 막고 있는 게이트다(센터 문서에 facility 절이 없어 unknown).
// reported/exempt는 이제 스킵 없이 해당 변형을 고른다.
func TestContractTemplateForStatusSkipReasons(t *testing.T) {
	for _, status := range []string{domain.FacilityStatusUnknown, "", "몰라요"} {
		if ver, _, skip := contractTemplateForStatus(status); skip != contractSkipFacilityUnknown || ver != "" {
			t.Errorf("contractTemplateForStatus(%q) = (%q, %q), want 미선언 스킵", status, ver, skip)
		}
	}
	for status, wantVer := range map[string]string{
		domain.FacilityStatusReported: contractTemplatePTv1Reported,
		domain.FacilityStatusExempt:   contractTemplatePTv1Exempt,
	} {
		ver, tpl, skip := contractTemplateForStatus(status)
		if skip != contractSkipNone || ver != wantVer {
			t.Errorf("contractTemplateForStatus(%q) = (%q, %q), want (%q, 스킵 없음) — 래치 ON(P48)", status, ver, skip, wantVer)
		}
		if len(tpl.requiredVarKeys) == 0 {
			t.Errorf("contractTemplateForStatus(%q)가 요구 슬롯 없는 정책을 돌려줬다 — 전부-아니면-전무의 분모가 빈다", status)
		}
	}
}

// 래치를 내린 구성에서는 상태를 선언해도 **래치 OFF 스킵**이다 — 선택이 래치를 대체하지 않고
// 합성된다는 P42의 규약(합성 순서: 상태 → 래치)이 롤백 구성에서도 그대로 성립하는지 고정한다.
// P48 이전에는 이게 프로덕션 진실이라 위 테스트가 겸했지만, 이제는 별도 구성이라 별도 단언이다.
func TestContractTemplateForStatusLatchOffSkips(t *testing.T) {
	withLatchOffContractVariants(t)
	for _, status := range []string{domain.FacilityStatusReported, domain.FacilityStatusExempt} {
		if ver, _, skip := contractTemplateForStatus(status); skip != contractSkipLatchOff || ver != "" {
			t.Errorf("contractTemplateForStatus(%q) = (%q, %q), want 래치 OFF 스킵", status, ver, skip)
		}
	}
	// unknown은 래치보다 앞선 게이트라 사유가 바뀌지 않는다(순서 역전 감시).
	if _, _, skip := contractTemplateForStatus(domain.FacilityStatusUnknown); skip != contractSkipFacilityUnknown {
		t.Errorf("래치 OFF에서 unknown 사유가 %q — 상태 게이트가 래치보다 먼저여야 한다", skip)
	}
}

// {{약관 게시 주소}} 상수 고정(P42): 제23조②가 가리키는 게시 위치 — P27 §F가 배포한 Hosting
// 법정 문서 URL이자 앱 legal_links와 동일 원천. 리터럴로 박는 이유: 상수 오타·실수 변경이
// 곧 계약서 전부에 틀린 주소가 인쇄되는 사고라, 구현 상수를 재인용하는 순환 단언이 아니라
// 독립 사본과 대조한다.
func TestContractTermsURLPinned(t *testing.T) {
	if contractTermsURL != "https://rize-218c1.web.app/legal/terms.html" {
		t.Errorf("약관 게시 주소 상수가 바뀌었다: %q — 앱 legal_links·P27 §F 배포 URL과 함께 움직여야 한다", contractTermsURL)
	}
	if contractInsuranceNone != "가입하지 않았습니다" {
		t.Errorf("보증보험 폴백 문구가 바뀌었다: %q — 제20조③이 지정한 표기 그대로여야 한다", contractInsuranceNone)
	}
}

// canonical_json 골든: 키 정렬(코드포인트 순) + 공백 없음 + 최소 이스케이프(JSON.stringify와
// 같은 규칙 — ", \, 제어문자만. 한글은 원문 그대로).
func TestCanonicalJSONVarsGoldenAndEscaping(t *testing.T) {
	got := canonicalJSONVars(map[string]string{
		"회원명": "김\"민지\\",
		"메모":  "줄1\n줄2",
		"제어":  "\x01",
	})
	// python: '{' + ','.join(json.dumps(k, ensure_ascii=False)+':'+json.dumps(v, ...)) + '}'
	want := `{"메모":"줄1\n줄2","제어":"\u0001","회원명":"김\"민지\\"}`
	if got != want {
		t.Errorf("canonical =\n%s\nwant\n%s", got, want)
	}
	if canonicalJSONVars(map[string]string{}) != "{}" {
		t.Errorf("빈 맵 canonical = %s, want {}", canonicalJSONVars(map[string]string{}))
	}
}

// 같은 논리 맵 → 언제나 같은 해시. Go 맵 순회는 실행마다 무작위라, 정렬을 빼면 이 반복이
// 압도적 확률로 어긋난다(뮤테이션 패스가 이 테스트로 sort 제거를 죽인다).
func TestCanonicalJSONVarsDeterministic(t *testing.T) {
	base := map[string]string{
		"상품명": "PT 10회", "계약금액": "1,000,000", "위약금율": "10",
		"회원명": "김민지", "사업자명": "라이즈", "납부일정": "일시불",
	}
	want := canonicalJSONVars(base)
	for i := 0; i < 40; i++ {
		m := map[string]string{} // 매번 새로 만들어 순회 시드를 바꾼다
		for k, v := range base {
			m[k] = v
		}
		if got := canonicalJSONVars(m); got != want {
			t.Fatalf("%d번째 재구성에서 canonical이 달라졌다:\n%s\n%s", i, got, want)
		}
	}
}

// 봉인 골든 벡터. canonical 문자열은 손으로 도출 가능한 형태로 함께 고정하고,
// hex는 python hashlib로 독립 계산해 박았다(2026-08-29):
//
//	input = "pt-v1" + "\n" + `{"계약금액":"1,000,000","상품명":"PT 10회","위약금율":"10"}`
//
// (정렬 확인: 계 U+ACC4 < 상 U+C0C1 < 위 U+C704 — 코드포인트 순)
func TestContractSealGoldenVector(t *testing.T) {
	vars := map[string]string{"위약금율": "10", "상품명": "PT 10회", "계약금액": "1,000,000"}
	wantCanon := `{"계약금액":"1,000,000","상품명":"PT 10회","위약금율":"10"}`
	if got := canonicalJSONVars(vars); got != wantCanon {
		t.Fatalf("canonical = %s, want %s", got, wantCanon)
	}
	const wantHex = "09d9adf5497b6c9d9666b834cee087cbe02b28eb441c1264b96492f211727da6"
	if got := contractSeal("pt-v1", vars); got != wantHex {
		t.Errorf("seal = %s, want %s", got, wantHex)
	}
	// 다른 버전 문자열이면 다른 해시 — 버전이 해시 입력에 실제로 들어간다.
	if contractSeal("pt-v2", vars) == wantHex {
		t.Error("template_version이 해시 입력에 반영되지 않는다")
	}
}

func TestFormatKRW(t *testing.T) {
	for _, c := range []struct {
		in   int
		want string
	}{
		{0, "0"}, {999, "999"}, {1000, "1,000"}, {500_000, "500,000"},
		{1_000_000, "1,000,000"}, {1_234_567, "1,234,567"}, {-4500, "-4,500"},
	} {
		if got := formatKRW(c.in); got != c.want {
			t.Errorf("formatKRW(%d) = %s, want %s", c.in, got, c.want)
		}
	}
}

// 앱 계약 시트와 같은 정밀도: 정수면 소수점 없이, 아니면 1자리. 0.1×100의 부동소수점 잔여
// (10.000000000000002)가 계약서에 인쇄되지 않아야 한다.
func TestFormatPercentSnapshot(t *testing.T) {
	for _, c := range []struct {
		in   float64
		want string
	}{
		{0.1, "10"}, {0.075, "7.5"}, {0, "0"}, {0.033, "3.3"}, {0.05, "5"},
	} {
		if got := formatPercentSnapshot(c.in); got != c.want {
			t.Errorf("formatPercentSnapshot(%v) = %s, want %s", c.in, got, c.want)
		}
	}
}

func TestHoldLimitVar(t *testing.T) {
	if got := holdLimitVar(-1); got != "무제한" {
		t.Errorf("holdLimitVar(-1) = %s, want 무제한", got)
	}
	if got := holdLimitVar(2); got != "2" {
		t.Errorf("holdLimitVar(2) = %s, want 2", got)
	}
}

// {{납부일정}} 직렬화 골든(P39 결정 4 — v2.18에 동결된 포맷, 해시 입력이라 사후 변경 불가).
func TestContractScheduleVar(t *testing.T) {
	paid := time.Date(2026, 9, 1, 10, 0, 0, 0, time.UTC)

	if _, ok := contractScheduleVar(nil); ok {
		t.Error("결제 0건인데 납부일정이 조립됐다 — 결측이어야 한다(§C)")
	}
	if got, ok := contractScheduleVar([]domain.Payment{{Method: "card"}}); !ok || got != "일시불" {
		t.Errorf("회차 없는 결제 = (%q, %v), want (일시불, true)", got, ok)
	}
	got, ok := contractScheduleVar([]domain.Payment{{
		Installments: []domain.Installment{
			{Due: "2026-09-01", Amount: 600_000, PaidAt: &paid},
			{Due: "2026-10-01", Amount: 400_000},
		},
	}})
	want := "1회차 600,000원 (2026-09-01 납부완료)\n2회차 400,000원 (2026-10-01 납부예정)"
	if !ok || got != want {
		t.Errorf("직렬화 =\n%q\nwant\n%q", got, want)
	}
	// 결제 여러 건이면 회차 번호는 전체 통산(결제 문서 순 × 저장된 회차 순).
	got, ok = contractScheduleVar([]domain.Payment{
		{Installments: []domain.Installment{{Due: "2026-09-01", Amount: 300_000, PaidAt: &paid}}},
		{Installments: []domain.Installment{{Due: "2026-10-01", Amount: 200_000}}},
	})
	want = "1회차 300,000원 (2026-09-01 납부완료)\n2회차 200,000원 (2026-10-01 납부예정)"
	if !ok || got != want {
		t.Errorf("복수 결제 직렬화 =\n%q\nwant\n%q", got, want)
	}
	// waived(청구 종결)는 동결 포맷이 표현하지 못한다 — 아는 척 찍지 않고 결측.
	waived := paid
	if _, ok := contractScheduleVar([]domain.Payment{{
		Installments: []domain.Installment{{Due: "2026-09-01", Amount: 100_000, WaivedAt: &waived}},
	}}); ok {
		t.Error("waived 회차가 있는데 납부일정이 조립됐다")
	}
}

// {{결제방법}}: 단건은 한글 라벨, 복수 수단은 canonical 순서(card→cash→transfer) "·" 결합 —
// 재발송 간 결정성이 해시 안정성의 전제다.
func TestContractPayMethodVar(t *testing.T) {
	if _, ok := contractPayMethodVar(nil); ok {
		t.Error("결제 0건인데 결제방법이 조립됐다")
	}
	if got, _ := contractPayMethodVar([]domain.Payment{{Method: "card"}}); got != "카드" {
		t.Errorf("card = %s, want 카드", got)
	}
	got, _ := contractPayMethodVar([]domain.Payment{{Method: "transfer"}, {Method: "card"}})
	if got != "카드·계좌이체" {
		t.Errorf("transfer+card = %s, want 카드·계좌이체(canonical 순서)", got)
	}
	if _, ok := contractPayMethodVar([]domain.Payment{{Method: ""}}); ok {
		t.Error("빈 method만 있는데 결제방법이 조립됐다")
	}
}

// 전부-아니면-전무: 완전하면 (요구 키 전부의 맵, nil), 하나라도 결측이면 (nil, 결측 목록) —
// 부분 맵은 반환형 차원에서 존재하지 않는다(P39 결정 1). P42부터 요구 목록은 변형별
// (reported 25 / exempt 24)이고, facility 유래 슬롯의 조립·폴백도 여기서 함께 고정한다.
func TestAssembleContractVarsAllOrNothing(t *testing.T) {
	rate := 0.1
	c := &domain.Contract{Product: "PT 10회", PaidAmount: 1_000_000, PenaltyRate: &rate}
	pass := &domain.Pass{TotalSessions: 10, ValidFrom: "2026-08-01", ValidUntil: "2026-11-01", TrainerID: "t1"}
	mem := &domain.Member{Name: "김민지", Phone: "010-1234-5678"}
	trainer := &domain.Staff{Name: "정혜린"}
	pol := domain.DefaultPolicy()
	pays := []domain.Payment{{Method: "card"}}
	biz := &domain.Business{
		BizName: "라이즈 컨디셔닝", CeoName: "박라이즈", BizRegNo: "123-45-67890",
		Address: "서울시 어딘가로 1", Phone: "02-1234-5678", Email: "rise@example.com",
	}
	fac := &domain.Facility{
		ReportStatus: domain.FacilityStatusReported,
		ReportNo:     "제2026-강남-0001호",
		Insurance:    "서울보증 인허가보증보험, 보장한도 1억원",
	}

	vars, missing := assembleContractVars(c, pass, mem, trainer, &pol, pays, biz, fac, contractPTv1ReportedVarKeys)
	if missing != nil {
		t.Fatalf("완전한 재료인데 결측 = %q", missing)
	}
	if len(vars) != len(contractPTv1ReportedVarKeys) {
		t.Fatalf("vars %d개, want %d", len(vars), len(contractPTv1ReportedVarKeys))
	}
	for _, kv := range [][2]string{
		{"계약금액", "1,000,000"}, {"위약금율", "10"}, {"납부일정", "일시불"}, {"결제방법", "카드"},
		{"취소 마감 시간", "24"}, {"노쇼 유예 적용 여부", "적용"}, {"홀딩 최대 횟수", "2"},
		{"홀딩 최대 일수", "30"}, {"슬롯 정원", "3"}, {"사업자등록번호", "123-45-67890"},
		{"약관 게시 주소", "https://rize-218c1.web.app/legal/terms.html"},
		{"보증보험 종류·보장내용", "서울보증 인허가보증보험, 보장한도 1억원"},
		{"체육시설업 신고번호", "제2026-강남-0001호"},
	} {
		if vars[kv[0]] != kv[1] {
			t.Errorf("vars[%s] = %q, want %q", kv[0], vars[kv[0]], kv[1])
		}
	}

	// exempt 목록은 신고번호를 **요구하지 않는다** — 번호 없는 시설 선언으로도 24종 완전
	// 스탬프가 성립하고, 맵에 신고번호 키 자체가 없다(결측 허용이 아니라 요구의 부재).
	facExempt := &domain.Facility{ReportStatus: domain.FacilityStatusExempt}
	varsEx, missingEx := assembleContractVars(c, pass, mem, trainer, &pol, pays, biz, facExempt, contractPTv1ExemptVarKeys)
	if missingEx != nil {
		t.Fatalf("exempt 완전 재료인데 결측 = %q", missingEx)
	}
	if len(varsEx) != len(contractPTv1ExemptVarKeys) {
		t.Fatalf("exempt vars %d개, want %d", len(varsEx), len(contractPTv1ExemptVarKeys))
	}
	if _, ok := varsEx["체육시설업 신고번호"]; ok {
		t.Error("exempt 조립에 신고번호가 끼었다 — :818 '행을 뺀다'가 키 목록에서 깨졌다")
	}
	// 보증보험 미가입(빈 값) → 제20조③의 자체 설계대로 "가입하지 않았습니다"가 **값**이다
	// (결측이 아니다 — 미가입은 숨길 상태가 아니라 고지 대상).
	if got := varsEx["보증보험 종류·보장내용"]; got != "가입하지 않았습니다" {
		t.Errorf("보증보험 빈 값 = %q, want 가입하지 않았습니다(제20조③)", got)
	}
	// 공백만 있는 입력도 미가입으로 접힌다(판정은 trim — nonBlank와 같은 규약).
	facBlank := &domain.Facility{ReportStatus: domain.FacilityStatusExempt, Insurance: "  "}
	varsBlank, _ := assembleContractVars(c, pass, mem, trainer, &pol, pays, biz, facBlank, contractPTv1ExemptVarKeys)
	if got := varsBlank["보증보험 종류·보장내용"]; got != "가입하지 않았습니다" {
		t.Errorf("보증보험 공백 값 = %q, want 가입하지 않았습니다", got)
	}

	// reported 목록 + 번호 없는 시설(손편집 문서 방어) → 신고번호 결측. 시설 절 자체가
	// 없으면(nil) 보증보험도 결측 — 미가입을 아는 척 찍지 않는다. 약관 게시 주소는 서버
	// 상수라 시설 없이도 조립된다.
	facNoNo := &domain.Facility{ReportStatus: domain.FacilityStatusReported}
	_, missingNoNo := assembleContractVars(c, pass, mem, trainer, &pol, pays, biz, facNoNo, contractPTv1ReportedVarKeys)
	if !slicesContains(missingNoNo, "체육시설업 신고번호") {
		t.Errorf("번호 없는 reported 조립의 결측 목록에 신고번호가 없다: %q", missingNoNo)
	}
	_, missingNilFac := assembleContractVars(c, pass, mem, trainer, &pol, pays, biz, nil, contractPTv1ReportedVarKeys)
	if !slicesContains(missingNilFac, "보증보험 종류·보장내용") || slicesContains(missingNilFac, "약관 게시 주소") {
		t.Errorf("fac nil 결측 = %q, want 보증보험 포함 + 약관 게시 주소 제외(서버 상수)", missingNilFac)
	}

	// 트레이너 결측 → 전무 + 결측 키 보고.
	vars2, missing2 := assembleContractVars(c, pass, mem, nil, &pol, pays, biz, fac, contractPTv1ReportedVarKeys)
	if vars2 != nil {
		t.Error("결측이 있는데 부분 맵이 반환됐다 — 전부-아니면-전무 위반")
	}
	if !slicesContains(missing2, "담당 트레이너명") {
		t.Errorf("결측 목록에 담당 트레이너명이 없다: %q", missing2)
	}

	// 레거시 요율(nil) → 위약금율 결측(0%가 아니라 "모름" — §C 렌더 금지).
	cLegacy := &domain.Contract{Product: "PT 10회", PaidAmount: 1_000_000}
	_, missing3 := assembleContractVars(cLegacy, pass, mem, trainer, &pol, pays, biz, fac, contractPTv1ReportedVarKeys)
	if !slicesContains(missing3, "위약금율") {
		t.Errorf("PenaltyRate nil인데 위약금율이 결측이 아니다: %q", missing3)
	}
}

// slicesContains — 테스트 전용 소도구(제네릭 slices.Contains를 문자열에 그대로 써도 되지만,
// 결측 목록 비교가 이 파일 곳곳이라 이름으로 의도를 남긴다).
func slicesContains(ss []string, want string) bool {
	for _, s := range ss {
		if s == want {
			return true
		}
	}
	return false
}

// 봉인 입력의 개행 결합이 우연이 아님을 고정: 버전과 canonical 사이 구분자가 사라지면
// ("pt-v1"+"{...}" vs "pt-v"+"1{...}") 경계 이동 위조가 가능하다.
func TestContractSealInputBoundary(t *testing.T) {
	a := contractSeal("pt-v1", map[string]string{"k": "v"})
	b := contractSeal("pt-v", map[string]string{"k": "v"})
	if a == b {
		t.Error("버전 경계가 해시를 가르지 않는다")
	}
	if len(a) != 64 || strings.ToLower(a) != a {
		t.Errorf("봉인 형식이 소문자 hex 64자가 아니다: %q", a)
	}
}
