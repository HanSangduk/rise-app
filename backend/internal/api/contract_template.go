package api

// 계약서 템플릿 레지스트리 + Vars 조립 + canonical_json 봉인(P39, 계약 v2.18 → v2.19 변형
// 2종 → **v2.22 발행 래치 ON**, P48 — contractTemplates 위 블록이 그 결정의 본문이다).
//
// **여기가 api 레이어인 이유(레이어링 결정)**: 레지스트리(버전별 요구 슬롯 목록 + 발행 래치)는
// "서버가 어떤 문서를 발행할 수 있는가"라는 **발행 정책**이고, Vars 조립은 Pass·Member·Policy·
// Payment·Business 다섯 엔티티의 조인이다 — 도메인의 단일 엔티티 파일이 하지 않는 일이고,
// 같은 조인을 이미 buildContractForPass(서비스)가 한다. domain에는 엔티티 의미(contract.go의
// 필드 주석)만 남기고, 무엇을 요구하고 언제 발행하는가는 이 파일이 답한다.
//
// **레지스트리는 템플릿 원문을 들지 않는다** — 렌더링은 클라이언트 몫이고(§D ④ 앱 자산 번들),
// 서버는 완전성 판정(요구 슬롯 전부 조립 가능한가)과 해시 봉인에 쓸 키 목록만 필요하다.

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// PT 이용계약 v1의 두 변형(P42 — docs/계약서_PT이용계약_v1.md :818의 갈래를 구현): 센터의
// 체육시설업 신고 상태가 버전을 가른다. reported는 당사자 표에 신고번호 행이 있고, exempt는
// 그 행이 없다(신고 대상 아님 — 유권해석·기구 미비치 강습 전용. "신고 대상이 아니라는
// 유권해석을 받았다면 이 행을 뺀다"는 계약서doc 자신의 지시다). 실서명 0건인 동안 템플릿
// 교체가 자유라(P39 목표) 종전 단일 버전 pt-v1은 폐기했다 — contractTemplates 주석 참고.
const (
	contractTemplatePTv1Reported = "pt-v1-reported"
	contractTemplatePTv1Exempt   = "pt-v1-exempt"
)

// contractTermsURL — {{약관 게시 주소}}에 얼리는 서버 상수(P42). 제23조②(계약서의 교부와
// 약관)가 가리키는 게시 위치 = P27 §F가 배포한 Hosting 법정 문서 URL이고, 앱 legal_links
// (이용약관)와 동일 원천이다. 센터 입력이 아닌 이유: 약관을 게시하는 주체가 시스템이라
// 센터마다 다를 수 있는 값이 아니고, 입력 칸을 만들면 틀린 주소가 계약서에 인쇄될 자유만
// 생긴다. 값 자체는 테스트가 리터럴로 고정한다(오타 재배포 사고 방지).
const contractTermsURL = "https://rize-218c1.web.app/legal/terms.html"

// contractInsuranceNone — {{보증보험 종류·보장내용}}의 빈 값 표기. 제20조③이 **스스로**
// 설계한 결측 표현이다("가입하지 않은 경우 '가입하지 않았습니다'로 기재합니다") — 미가입은
// 숨길 결측이 아니라 그 자체로 고지해야 하는 계약 내용이라, 유일하게 빈 값이 스탬프를 막지
// 않는 슬롯이 된다(전부-아니면-전무의 예외가 아니라, 빈 값의 정직한 값이 정의된 경우).
const contractInsuranceNone = "가입하지 않았습니다"

// contractVariantByStatus — 시설 신고 상태 → 스탬프 버전(P42). 종전의 단일 "현재 버전"
// 포인터(contractCurrentTemplate)를 대체한다: 버전 선택이 취향이 아니라 **신고 상태 선언의
// 함수**가 됐다. unknown 키는 아예 없다 — 스킵을 0값 폴백이 아니라 부재로 표현한다(모르는
// 상태로 문서를 만들지 않는다). var인 이유는 종전과 같다: 테스트가 픽스처 버전으로 latch-on
// 경로를 검증한다(withIssuableContractVariants). 프로덕션에서 바꾸는 일은 새 템플릿 버전
// 등록과 함께 오는 코드 변경이다(런타임 설정이 아니다 — §D ① "버전 고정").
var contractVariantByStatus = map[string]string{
	domain.FacilityStatusReported: contractTemplatePTv1Reported,
	domain.FacilityStatusExempt:   contractTemplatePTv1Exempt,
}

// contractTemplate — 버전 하나의 발행 정책. requiredVarKeys는 **전부-아니면-전무**의 분모다:
// 하나라도 조립 불가면 스탬프 자체를 하지 않는다(P39 결정 1 — "(미정)"이 인쇄된 계약서도,
// 발급 차단도 아닌 제3의 길).
type contractTemplate struct {
	requiredVarKeys []string
	// issuable — 발행 래치(P39 결정 1). **2026-08-30 대표 결정으로 두 변형 모두 ON**(P48,
	// 계약 v2.22 — 아래 contractTemplates 참고). false인 동안에는 send/발급이 TemplateVersion·
	// Vars를 **아예 스탬프하지 않아** 다운스트림 전부가 종전 동작 그대로였다(요약 고지 서명 =
	// P28이 적법화한 기준선).
	//
	// 켜진 뒤에도 필드를 남겨 두는 이유는 되돌림이 한 줄이어야 해서다 — 사고 시 배포 롤백보다
	// 스위치가 빠르다. 래치 OFF **구성**의 불변("꺼져 있으면 facility 읽기조차 없다 — 스토어
	// 접근 횟수까지 종전과 동일")은 지금도 테스트가 픽스처로 증명한다
	// (withLatchOffContractVariants — service_contract_stamp_test.go).
	issuable bool
}

// contractPTv1BaseVarKeys — 두 변형이 **공유하는** 슬롯 22종(P39 착수 시점의 조립 가능
// 전체 — 종전 pt-v1의 requiredVarKeys 그대로). 키는 계약서doc §C의 {{...}} 슬롯명
// **그대로**(바이트 단위 일치 — 앱에 번들되는 템플릿 자산의 슬롯과 맞아야 렌더가 성립한다).
//
// P42가 슬롯 갭을 종결해, §C 기준으로 목록 밖에 남는 것은 두 갈래뿐이다:
//
//	{{계약 체결일}}                 엔티티 렌더(P39 결정 3 — send 시점엔 SignedAt이 없다.
//	                               signed_at·미서명이면 first_sent_at에서 클라이언트가 렌더)
//	{{부가상품 목록}} 외 부가상품 3종    슬롯 자체가 소멸(P42) — 시스템이 부가상품을 팔 수
//	                               없으므로(Pass 모델에 부가상품 부재) 조문을 통째로
//	                               대체했다(:1275 "없으면 빈 표 금지", P28 "코드가 하는
//	                               것만 약속"). 도입하면 새 템플릿 버전으로 온다.
//
// 신규 3종({{약관 게시 주소}}·{{보증보험 종류·보장내용}}·{{체육시설업 신고번호}})은 변형별
// 목록(아래 contractPTv1ExemptVarKeys/contractPTv1ReportedVarKeys)이 담는다 — P39 결정 6이
// 미뤘던 자리를 Business 밖의 facility 절이 채웠다(IsComplete 회귀 없이).
//
// 키 → 출처 필드 매핑:
//
//	── C-1 계약·패스·회원·결제 (11) ──────────────────────────────────────────────
//	상품명            Contract.Product
//	계약금액          Contract.PaidAmount        → 콤마 3자리 구분(어드민 KRW 표기 관례)
//	위약금율          Contract.PenaltyRate × 100 → 정수면 소수점 없이, 아니면 1자리(앱 계약
//	                                             시트 표기와 동일 정밀도). nil이면 결측
//	                                             (v1.5 이전 레거시 — "모름", 렌더 금지 §C)
//	총 회차           Pass.TotalSessions
//	유효기간 시작일    Pass.ValidFrom
//	유효기간 종료일    Pass.ValidUntil            (일시정지로 변한다 — 그래서 얼린다)
//	담당 트레이너명    Pass.TrainerID → Staff.Name
//	회원명            Member.Name
//	회원 전화번호      Member.Phone
//	결제방법          Payment.Method              → 카드/현금/계좌이체, 복수 결제는 canonical
//	                                             순서(card→cash→transfer) "·" 결합
//	납부일정          Payment.Installments[]      → contractScheduleVar(포맷은 v2.18에 동결)
//	── C-2 센터 정책 (5) ────────────────────────────────────────────────────────
//	취소 마감 시간     Policy.CancelCutoffHours
//	노쇼 유예 적용 여부 Policy.GraceOnce           → "적용"/"미적용"
//	홀딩 최대 횟수     Policy.MaxHoldsPerPass      → -1은 "무제한"
//	홀딩 최대 일수     Policy.MaxHoldTotalDays     → -1은 "무제한"
//	슬롯 정원          Policy.SlotCapacity
//	── C-3 사업자 (6, P27 Business — Vars에 얼린다: D-4 재현성) ──────────────────
//	사업자명          Business.BizName
//	대표자명          Business.CeoName
//	사업자등록번호     Business.BizRegNo
//	사업장 주소        Business.Address
//	대표 전화          Business.Phone
//	대표 이메일        Business.Email
var contractPTv1BaseVarKeys = []string{
	"상품명", "계약금액", "위약금율", "총 회차", "유효기간 시작일", "유효기간 종료일",
	"담당 트레이너명", "회원명", "회원 전화번호", "결제방법", "납부일정",
	"취소 마감 시간", "노쇼 유예 적용 여부", "홀딩 최대 횟수", "홀딩 최대 일수", "슬롯 정원",
	"사업자명", "대표자명", "사업자등록번호", "사업장 주소", "대표 전화", "대표 이메일",
}

// 변형별 추가 슬롯(P42) — 키 → 출처 매핑(위 표의 연장):
//
//	── C-4 시설·약관 게시 (P42 — facility 절 + 서버 상수) ────────────────────────
//	약관 게시 주소            contractTermsURL 서버 상수    (제23조② — P27 §F 배포 URL)
//	보증보험 종류·보장내용     Facility.Insurance            → 빈 값이면 contractInsuranceNone
//	                                                       (제20조③의 자체 결측 설계)
//	체육시설업 신고번호        Facility.ReportNo             reported 변형 전용 — exempt는
//	                                                       §A에서 행 자체를 뺀다(:818)

// contractPTv1ExemptVarKeys — pt-v1-exempt가 요구하는 슬롯 24종 = 공유 22종 + 약관 게시
// 주소·보증보험. 신고번호 키가 **없다** — 결측 허용이 아니라 요구 자체가 없는 것이다
// (전부-아니면-전무의 분모에서 빠져, 미신고 센터도 완전 스탬프가 성립한다).
var contractPTv1ExemptVarKeys = append(append([]string{}, contractPTv1BaseVarKeys...),
	"약관 게시 주소", "보증보험 종류·보장내용")

// contractPTv1ReportedVarKeys — pt-v1-reported가 요구하는 슬롯 25종 = exempt 24종 + 신고번호.
var contractPTv1ReportedVarKeys = append(append([]string{}, contractPTv1ExemptVarKeys...),
	"체육시설업 신고번호")

// contractTemplates — 버전 → 발행 정책. 지난 버전은 지우지 않는다(§D ① — 봉인 검증·재현에
// 버전 문자열이 계속 쓰인다. 단 봉인 자체는 레지스트리를 보지 않는다 — contractSeal 참고).
//
// **pt-v1(P39 단일 버전)은 예외로 삭제했다(P42)**: 발행 래치가 한 번도 켜진 적 없어 이
// 버전으로 스탬프·봉인된 계약이 0건이다 — "지난 버전 보존" 규칙이 지키려는 대상(스탬프된
// 문서의 재현·검증)이 존재하지 않는다. 만에 하나 저장된 계약이 버전 문자열을 갖더라도 렌더
// 가능 여부는 앱의 버전 표가 답한다(§D ① — 레지스트리는 발행 정책이지 렌더 정책이 아니다).
//
// ─── 발행 래치 ON (2026-08-30, P48 — 계약 v2.22가 v2.18 "래치 OFF로 배포된다"를 대체) ───
//
// 대표(센터장) 명시 결정으로 두 변형 모두 issuable=true다. **이 줄이 스탬프를 시작시키지는
// 않는다** — 래치는 세 게이트 중 첫 번째일 뿐이고, 나머지 둘이 그대로 살아 있다:
//
//	① 래치(여기)            — 이제 열려 있다. 스토어를 읽지 않는 순수 사전 게이트.
//	② facility 신고 상태 선언 — contractTemplateForStatus. unknown(=미선언 기본값)이면 스킵,
//	                          모르는 상태로 문서를 만들지 않는다(P42). 프로덕션 센터는 아직
//	                          미선언이라 unknown으로 읽힌다(절이 없어도 읽기 기본값이 unknown).
//	③ 전부-아니면-전무 조립   — 요구 슬롯(24/25종) 중 하나라도 못 채우면 스탬프 자체를 안 한다.
//	                          프로덕션에는 Business(사업자 6칸)가 미등록이라 ②를 통과해도
//	                          여기서 걸린다.
//
// 즉 **오늘 이 시점의 관측 가능한 동작 변화는 0이다**(②·③이 모두 막고 있다). 그러나 이건
// "안전하니 아무 일도 없다"가 아니라 **잠금 해제**다: 대표가 어드민에서 사업자 정보를 등록
// 하고 시설 신고 상태를 선언하는 순간 — 그 두 저장 말고 다른 배포·승인 없이 — 다음 발급·
// 재발송부터 template_version·vars가 실제로 찍히고, 그 뒤 서명은 sha256으로 봉인된다.
// 회원이 앱에서 보는 것도 요약 고지에서 **계약서 본문 렌더**로 바뀐다.
//
// 그래서 지금부터는 §D ①의 버전 규율이 실질적 구속이 된다: **첫 서명 전까지는 템플릿 교체가
// 자유**(스탬프·봉인된 문서가 0건이라 재현 대상이 없다 — P42가 pt-v1을 지운 근거)지만,
// **한 건이라도 서명되면 그 버전은 동결**이고 문구 변경은 새 버전 키로 온다(봉인 검증이
// 버전 문자열에 매달려 있다). pt-v1-reported/pt-v1-exempt는 지금 그 경계 위에 있다.
var contractTemplates = map[string]contractTemplate{
	contractTemplatePTv1Reported: {requiredVarKeys: contractPTv1ReportedVarKeys, issuable: true},
	contractTemplatePTv1Exempt:   {requiredVarKeys: contractPTv1ExemptVarKeys, issuable: true},
}

// EnableContractTemplatesForDemo — **데모 전용** 발행 래치 ON(P43). 호출자는 main의
// 인메모리+DEV_SEED 블록 하나뿐이고(서빙 시작 전 1회 — 경합 없음), 프로덕션은 Firestore
// 모드라 그 블록에 도달할 수 없다(config.DevSeed 주석: "Firestore 모드에선 무시").
//
// **래치 ON 이후 이 함수는 사실상 no-op이다**(이미 true인 엔트리를 true로 쓴다). 그래도
// 지우지 않는 이유 둘: ① 래치를 다시 내리면(사고 롤백) 데모 경로가 조용히 요약 고지로
// 퇴행하는 대신 그대로 켜진 채 남는다 — 데모의 정직함이 프로덕션 스위치에 인질로 잡히지
// 않는다 ② 이 훅을 호출하는 통합 테스트(service_demo_seed_test.go)가 호출 **전에** 레지스트리
// 리터럴 상태를 단언해, 리터럴이 실수로 뒤집히는 뮤테이션을 잡는 고정점 역할을 계속 한다.
// 테스트가 쓰면 반드시 원복한다(service_contract_stamp_test.go의 픽스처 규약과 동일).
func EnableContractTemplatesForDemo() {
	for ver, tpl := range contractTemplates {
		tpl.issuable = true
		contractTemplates[ver] = tpl
	}
}

// contractStampSkipReason — 스탬프를 하지 않은 판정의 이름(P42). P39의 두 스킵(래치 OFF·
// 요구 키 결측)에 세 번째 갈래(신고 상태 미선언)가 생기면서, "왜 안 찍었나"를 호출측·테스트가
// 이름으로 다룰 수 있어야 한다. 계약 문서에 저장하지는 않는다 — 스킵된 계약은 오늘 경로
// 그대로가 규약이라(latch-off 불변) 사유 필드를 늘리지 않는다.
type contractStampSkipReason string

const (
	contractSkipNone     contractStampSkipReason = ""          // 스킵 아님 — 스탬프 진행
	contractSkipLatchOff contractStampSkipReason = "latch_off" // 발행 래치 OFF(P39 결정 1).
	// 래치 ON(P48) 이후 프로덕션에서는 나오지 않는 사유다 — 미등록 버전(레지스트리에 없는
	// 변형 키)과 래치를 되돌린 구성에서만 관측된다. 지우지 않는 이유는 issuable 필드와 같다.
	contractSkipFacilityUnknown contractStampSkipReason = "facility_report_status_unknown"
)

// contractStampLatchOn — 발행 래치 **사전** 게이트(종전 currentIssuableContractTemplate의
// 후속 중 읽기 없는 절반). 상태 변형 중 하나라도 발행 가능이면 true — 그때부터의 버전 선택은
// contractTemplateForStatus가 한다. **스토어를 읽지 않는다**: false면 호출측은 facility
// 읽기조차 없이 종전 경로 그대로다(latch-off 불변 — 발급·send의 스토어 접근 횟수까지 동일.
// hookStore 카운트 테스트가 픽스처로 고정한다).
//
// P48 이후 프로덕션 구성에서는 항상 true다 — 이 함수의 값어치는 "래치가 게이트 순서의 맨
// 앞이고 스토어를 읽지 않는다"는 구조를 유지하는 데 있다(되돌림 한 줄로 종전 경로 복귀).
func contractStampLatchOn() bool {
	for _, ver := range contractVariantByStatus {
		if tpl, ok := contractTemplates[ver]; ok && tpl.issuable {
			return true
		}
	}
	return false
}

// contractTemplateForStatus — 시설 신고 상태 → (버전, 발행 정책, 스킵 사유). 순수 함수 —
// 게이트 판정을 스토어 없이 단언할 수 있다. 두 게이트가 **합성**된다(P42가 P39를 대체하지
// 않는다): ① 상태가 변형을 가리키는가 — unknown(및 미지 값)은 미선언 스킵, **모르는 상태로
// 문서를 만들지 않는다**(P39 래치와 같은 철학의 두 번째 게이트) ② 그 변형의 래치가 켜져
// 있는가(P39 결정 1 — P48로 ON. 이제 프로덕션에서 실제로 문서 발행을 막는 것은 ①과
// 전부-아니면-전무 조립이다).
func contractTemplateForStatus(status string) (string, contractTemplate, contractStampSkipReason) {
	ver, ok := contractVariantByStatus[status]
	if !ok {
		return "", contractTemplate{}, contractSkipFacilityUnknown
	}
	tpl, ok := contractTemplates[ver]
	if !ok || !tpl.issuable {
		return "", contractTemplate{}, contractSkipLatchOff
	}
	return ver, tpl, contractSkipNone
}

// gatherContractVars — Vars 조립에 필요한 주변 문서를 읽어(스토어 접근은 전부 여기 —
// **트랜잭션 밖 전용**, ContractMutator 순수성 규약) 순수 조립기에 넘긴다.
//
// ErrNotFound는 "그 키가 빈다"로 접는다(회원·스태프·패스 문서가 없는 레거시/픽스처에서도
// send 자체는 오늘처럼 성립해야 한다 — 스탬프만 건너뛴다). 그 외 에러는 그대로 올린다 —
// 인프라 실패를 "결측"으로 오독하면 조용한 스킵이 장애를 가린다.
//
// pol·fac은 호출측이 이미 읽었으면 재사용(스탬프 경로는 버전 선택 때 읽은 facility를 그대로
// 넘긴다 — 같은 문서를 두 번 읽으면 선택된 변형과 스탬프된 신고번호 사이에 저장이 끼어들 수
// 있다), nil이면 여기서 읽는다.
func (s *Service) gatherContractVars(ctx context.Context, centerID string, c *domain.Contract, pass *domain.Pass, pol *domain.Policy, fac *domain.Facility, required []string) (map[string]string, []string, error) {
	var mem *domain.Member
	if c.MemberID != "" {
		m, err := s.store.GetMember(ctx, centerID, c.MemberID)
		switch {
		case err == nil:
			mem = m
		case errors.Is(err, store.ErrNotFound):
		default:
			return nil, nil, err
		}
	}
	var trainer *domain.Staff
	if pass != nil && pass.TrainerID != "" {
		st, err := s.store.GetStaff(ctx, centerID, pass.TrainerID)
		switch {
		case err == nil:
			trainer = st
		case errors.Is(err, store.ErrNotFound):
		default:
			return nil, nil, err
		}
	}
	if pol == nil {
		p, err := s.store.GetPolicy(ctx, centerID)
		if err != nil {
			return nil, nil, err
		}
		pol = p
	}
	if fac == nil {
		f, err := s.store.GetFacility(ctx, centerID)
		if err != nil {
			return nil, nil, err
		}
		fac = f
	}
	// 결제는 이 패스의 것만(recordedPaymentTotal과 같은 센터 전체 조회 + 필터 패턴).
	// c.PassID가 비면(발급 조립 시점 — IssuePass가 아직 ID를 안 채웠다) 결제 0건으로 간다 —
	// 빈 PassID 매칭으로 엉뚱한 레코드를 집어가지 않기 위한 가드.
	pays := []domain.Payment{}
	if c.PassID != "" {
		all, err := s.store.ListPayments(ctx, centerID)
		if err != nil {
			return nil, nil, err
		}
		for _, pay := range all {
			if pay.PassID == c.PassID {
				pays = append(pays, pay)
			}
		}
	}
	biz, err := s.store.GetBusiness(ctx, centerID)
	if err != nil {
		return nil, nil, err
	}
	vars, missing := assembleContractVars(c, pass, mem, trainer, pol, pays, biz, fac, required)
	return vars, missing, nil
}

// assembleContractVars — 순수 조립기: 요구 슬롯 전부를 채울 수 있으면 (완성 맵, nil),
// 하나라도 못 채우면 (nil, 결측 키 목록 — required 순서). **전부-아니면-전무**를 반환형으로
// 강제한다: 부분 맵을 아예 돌려주지 않아 호출측이 실수로도 부분 스탬프를 못 만든다(P39 결정 1
// — 미완성 값이 인쇄된 계약서는 방판법 §30 기재 누락이다).
func assembleContractVars(c *domain.Contract, pass *domain.Pass, mem *domain.Member, trainer *domain.Staff, pol *domain.Policy, pays []domain.Payment, biz *domain.Business, fac *domain.Facility, required []string) (map[string]string, []string) {
	vars := make(map[string]string, len(required))
	var missing []string
	for _, key := range required {
		v, ok := contractVarValue(key, c, pass, mem, trainer, pol, pays, biz, fac)
		if !ok {
			missing = append(missing, key)
			continue
		}
		vars[key] = v
	}
	if len(missing) > 0 {
		return nil, missing
	}
	return vars, nil
}

// contractVarValue — 슬롯 하나의 값. ok=false는 "지금 이 값을 정직하게 찍을 수 없다"다.
// 문자열 출처는 공백 제거 후 비어 있으면 결측, 숫자 출처는 생성 게이트가 이미 검증한 값이라
// 그대로 찍는다. 값에는 단위를 붙이지 않는다 — 단위(회·원·%·시간·일·팀)는 템플릿 문장에 있다.
func contractVarValue(key string, c *domain.Contract, pass *domain.Pass, mem *domain.Member, trainer *domain.Staff, pol *domain.Policy, pays []domain.Payment, biz *domain.Business, fac *domain.Facility) (string, bool) {
	switch key {
	// ── C-1 계약·패스·회원·결제 ──
	case "상품명":
		return nonBlank(c.Product)
	case "계약금액":
		return formatKRW(c.PaidAmount), true
	case "위약금율":
		// **스냅샷이 유일한 출처다**(§C 비고·P14): Policy.PenaltyRate를 다시 읽으면 정책
		// 변경이 재발송을 타고 소급된다. nil은 0%가 아니라 "모름"(v1.5 이전 레거시) — 결측.
		if c.PenaltyRate == nil {
			return "", false
		}
		return formatPercentSnapshot(*c.PenaltyRate), true
	case "총 회차":
		if pass == nil {
			return "", false
		}
		return strconv.Itoa(pass.TotalSessions), true
	case "유효기간 시작일":
		if pass == nil {
			return "", false
		}
		return nonBlank(pass.ValidFrom)
	case "유효기간 종료일":
		if pass == nil {
			return "", false
		}
		return nonBlank(pass.ValidUntil)
	case "담당 트레이너명":
		if trainer == nil {
			return "", false
		}
		return nonBlank(trainer.Name)
	case "회원명":
		if mem == nil {
			return "", false
		}
		return nonBlank(mem.Name)
	case "회원 전화번호":
		if mem == nil {
			return "", false
		}
		return nonBlank(mem.Phone) // 탈퇴 시 비워진다(P22) — 그 계약은 어차피 종단 상태다
	case "결제방법":
		return contractPayMethodVar(pays)
	case "납부일정":
		return contractScheduleVar(pays)
	// ── C-2 센터 정책 (send 시점 값을 얼린다 — 재발송이 재확정, P39 결정 2) ──
	case "취소 마감 시간":
		if pol == nil {
			return "", false
		}
		return strconv.Itoa(pol.CancelCutoffHours), true
	case "노쇼 유예 적용 여부":
		if pol == nil {
			return "", false
		}
		if pol.GraceOnce {
			return "적용", true
		}
		return "미적용", true
	case "홀딩 최대 횟수":
		if pol == nil {
			return "", false
		}
		return holdLimitVar(pol.MaxHoldsPerPass), true
	case "홀딩 최대 일수":
		if pol == nil {
			return "", false
		}
		return holdLimitVar(pol.MaxHoldTotalDays), true
	case "슬롯 정원":
		if pol == nil {
			return "", false
		}
		return strconv.Itoa(pol.SlotCapacity), true
	// ── C-3 사업자 (P27 Business 6칸 — 실시간 조회가 아니라 얼린다: D-4 재현성) ──
	case "사업자명":
		if biz == nil {
			return "", false
		}
		return nonBlank(biz.BizName)
	case "대표자명":
		if biz == nil {
			return "", false
		}
		return nonBlank(biz.CeoName)
	case "사업자등록번호":
		if biz == nil {
			return "", false
		}
		return nonBlank(biz.BizRegNo)
	case "사업장 주소":
		if biz == nil {
			return "", false
		}
		return nonBlank(biz.Address)
	case "대표 전화":
		if biz == nil {
			return "", false
		}
		return nonBlank(biz.Phone)
	case "대표 이메일":
		if biz == nil {
			return "", false
		}
		return nonBlank(biz.Email)
	// ── C-4 시설·약관 게시 (P42 — facility 절 + 서버 상수) ──
	case "약관 게시 주소":
		// 서버 상수(제23조② 약관 게시 위치) — 조립 재료가 필요 없어 결측이 없다. 상수를
		// Vars에 "얼리는" 이유: 훗날 호스팅 주소가 바뀌어도 이미 서명된 계약은 서명 당시
		// 회원이 안내받은 주소를 그대로 보존해야 한다(D-4 재현성 — Business 6칸과 같은 자리).
		return contractTermsURL, true
	case "보증보험 종류·보장내용":
		if fac == nil {
			return "", false // 시설 절을 읽지 못한 조립 — 미가입("가입하지 않았습니다")을 아는 척 찍지 않는다
		}
		if strings.TrimSpace(fac.Insurance) == "" {
			// 제20조③의 자체 결측 설계: "가입하지 않은 경우 '가입하지 않았습니다'로 기재".
			// 빈 값이 스탬프를 막지 않는 유일한 슬롯 — 미가입은 결측이 아니라 고지 대상이다.
			return contractInsuranceNone, true
		}
		return fac.Insurance, true
	case "체육시설업 신고번호":
		// reported 변형만 이 키를 요구한다(exempt 목록에 없음 — :818 "행을 뺀다"). 게이트가
		// reported⇒번호 필수를 저장에서 강제하지만(domain.Facility.Validate), 손편집 문서
		// 방어로 빈 값은 여전히 결측이다 — 빈 신고번호가 인쇄된 계약서는 제3의 길이 아니다.
		if fac == nil {
			return "", false
		}
		return nonBlank(fac.ReportNo)
	}
	// 레지스트리에 있는데 조립기가 모르는 키 — 찍을 수 없다(모르는 것을 아는 척하지 않는다.
	// 새 슬롯을 레지스트리에만 더하고 조립을 안 더하면 여기서 결측 = 스탬프 불가로 표면화된다).
	return "", false
}

// nonBlank — 공백 제거 후 비어 있으면 결측. 값 자체는 저장된 원형 그대로 얼린다
// (다른 화면이 보여주는 값과 같아야 한다 — 판정만 trim).
func nonBlank(s string) (string, bool) {
	if strings.TrimSpace(s) == "" {
		return "", false
	}
	return s, true
}

// contractPayMethodVar — {{결제방법}}. 결제 0건이면 결측(§C "결제 기록이 없을 수 있음" —
// 실무에서 발급 직후가 이 상태고, 그래서 첫 완전 스탬프는 결제 기록 후 재발송에서 찍힌다).
// 한 패스에 결제 여러 건은 정상 영업이라(카드 일부 + 현금 일부 — CreatePayment 상한 주석)
// 서로 다른 수단은 canonical 순서(card→cash→transfer)로 "·" 결합한다 — 결정적이어야
// 재발송 해시가 흔들리지 않는다. 게이트(ValidPayMethod) 밖 값은 이론상 없지만, 있으면
// 알려진 수단 뒤에 사전순으로 원문 그대로 붙인다(앱 methodLabel의 폴백과 같은 태도).
func contractPayMethodVar(pays []domain.Payment) (string, bool) {
	if len(pays) == 0 {
		return "", false
	}
	seen := map[string]bool{}
	for _, p := range pays {
		if p.Method != "" {
			seen[p.Method] = true
		}
	}
	labels := []string{}
	for _, m := range []string{domain.PayMethodCard, domain.PayMethodCash, domain.PayMethodTransfer} {
		if seen[m] {
			labels = append(labels, payMethodKo(m))
			delete(seen, m)
		}
	}
	unknown := make([]string, 0, len(seen))
	for m := range seen {
		unknown = append(unknown, m)
	}
	sort.Strings(unknown)
	labels = append(labels, unknown...)
	if len(labels) == 0 {
		return "", false
	}
	return strings.Join(labels, "·"), true
}

// payMethodKo — 계약서에 인쇄되는 한글 라벨. 앱(my_models methodLabel)·어드민
// (PAYMENT_METHOD_LABEL)과 같은 세 값이다 — 세 자리가 같은 말을 해야 한다.
func payMethodKo(m string) string {
	switch m {
	case domain.PayMethodCard:
		return "카드"
	case domain.PayMethodCash:
		return "현금"
	case domain.PayMethodTransfer:
		return "계좌이체"
	}
	return m
}

// contractScheduleVar — {{납부일정}} 직렬화(P39 결정 4 — **v2.18에 동결된 포맷**, 해시
// 입력이라 사후 변경 불가):
//
//	"n회차 {금액}원 ({YYYY-MM-DD} 납부예정|납부완료)" 행을 "\n" 결합
//
// 금액은 콤마 3자리 구분(formatKRW). 회차 번호는 결제 문서 순(스토어 목록 = 문서 ID 순) ×
// 저장된 회차 순으로 전체 통산 — 앱 결제 화면이 보여주는 순서와 같다. 분할 회차가 하나도
// 없으면 "일시불"(§C). waived(청구 종결) 회차가 있으면 결측 — 동결된 포맷이 표현하지 못하는
// 상태를 아는 척 찍지 않는다(실무 도달 불가: waived는 환불 정산의 결과인데 환불 패스의 send는
// 트랜잭션 안 가드가 막는다 — 순수 함수의 전함수성을 위한 가지다).
func contractScheduleVar(pays []domain.Payment) (string, bool) {
	if len(pays) == 0 {
		return "", false
	}
	lines := []string{}
	n := 0
	for _, p := range pays {
		for _, ins := range p.Installments {
			if ins.WaivedAt != nil {
				return "", false
			}
			n++
			status := "납부예정"
			if ins.PaidAt != nil {
				status = "납부완료"
			}
			lines = append(lines, fmt.Sprintf("%d회차 %s원 (%s %s)", n, formatKRW(ins.Amount), ins.Due, status))
		}
	}
	if len(lines) == 0 {
		return "일시불", true
	}
	return strings.Join(lines, "\n"), true
}

// formatKRW — 콤마 3자리 구분(어드민 lib/format.ts의 ko-KR KRW 표기와 같은 그룹핑).
// 원 단위·통화 기호는 붙이지 않는다 — 템플릿이 "{{계약금액}}원"으로 단위를 든다.
func formatKRW(n int) string {
	sign := ""
	if n < 0 { // 계약가·회차 금액은 게이트가 음수를 막지만, 전함수로 둔다
		sign, n = "-", -n
	}
	s := strconv.Itoa(n)
	if len(s) <= 3 {
		return sign + s
	}
	var b strings.Builder
	head := len(s) % 3
	if head == 0 {
		head = 3
	}
	b.WriteString(s[:head])
	for i := head; i < len(s); i += 3 {
		b.WriteByte(',')
		b.WriteString(s[i : i+3])
	}
	return sign + b.String()
}

// formatPercentSnapshot — {{위약금율}}: 요율(0~0.1) × 100을 소수 첫째 자리에서 고정해,
// 정수면 소수점 없이("10"), 아니면 1자리("7.5"). 앱 계약 시트(contract_sign_sheet/
// contract_detail_sheet)의 표기 정밀도와 같다 — 회원이 화면에서 본 숫자와 문서에 얼린 숫자가
// 달라지면 안 된다. 첫째 자리 반올림을 먼저 하는 이유: 0.1×100은 이진 부동소수점에서
// 10.000000000000002라 그대로 찍으면 계약서에 그 숫자가 인쇄된다.
func formatPercentSnapshot(rate float64) string {
	pct := math.Round(rate*1000) / 10
	if pct == math.Trunc(pct) {
		return strconv.Itoa(int(pct))
	}
	return strconv.FormatFloat(pct, 'f', 1, 64)
}

// holdLimitVar — 홀딩 상한: -1은 명시적 무제한(Policy 규약)이라 "무제한"으로 찍는다.
// "-1회"는 거짓이고 결측 처리는 정당한 정책을 스탬프 불가로 만든다. "최대 무제한회" 문장이
// 어색한 것은 템플릿 최종 동결(발행 스위치 시점, P39 후속) 때 문구로 흡수한다.
func holdLimitVar(n int) string {
	if n == -1 {
		return "무제한"
	}
	return strconv.Itoa(n)
}

// ---- canonical_json + 봉인(§D ②) ----

// canonicalJSONVars — vars의 정규화 직렬화: 키 정렬(유니코드 코드포인트 순 = UTF-8 바이트 순)
// + 공백 없음 + 최소 이스케이프. 같은 입력이 언제나 같은 바이트열을 내야 해시가 성립한다.
//
// 이스케이프는 JSON이 강제하는 최소만이다: `"` `\` 제어문자(U+0000~001F — \b \f \n \r \t는
// 축약형, 나머지는 \u00xx 소문자 hex). 한글 등 비ASCII는 원문 그대로 둔다. 이 선택은
// JS `JSON.stringify`의 출력과 일치한다 — 나중에 어드민(TS)이 봉인을 재검증할 때 표준
// 직렬화기로 같은 바이트열을 만들 수 있어야 한다(Go encoding/json의 HTML 이스케이프
// < 류는 그래서 쓰지 않는다).
func canonicalJSONVars(vars map[string]string) string {
	keys := make([]string, 0, len(vars))
	for k := range vars {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	b.WriteByte('{')
	for i, k := range keys {
		if i > 0 {
			b.WriteByte(',')
		}
		writeCanonicalJSONString(&b, k)
		b.WriteByte(':')
		writeCanonicalJSONString(&b, vars[k])
	}
	b.WriteByte('}')
	return b.String()
}

func writeCanonicalJSONString(b *strings.Builder, s string) {
	const hexDigits = "0123456789abcdef"
	b.WriteByte('"')
	for i := 0; i < len(s); i++ { // 바이트 단위 — 이스케이프 대상은 전부 ASCII, UTF-8은 통과
		c := s[i]
		switch {
		case c == '"':
			b.WriteString(`\"`)
		case c == '\\':
			b.WriteString(`\\`)
		case c == '\b':
			b.WriteString(`\b`)
		case c == '\f':
			b.WriteString(`\f`)
		case c == '\n':
			b.WriteString(`\n`)
		case c == '\r':
			b.WriteString(`\r`)
		case c == '\t':
			b.WriteString(`\t`)
		case c < 0x20:
			b.WriteString(`\u00`)
			b.WriteByte(hexDigits[c>>4])
			b.WriteByte(hexDigits[c&0xf])
		default:
			b.WriteByte(c)
		}
	}
	b.WriteByte('"')
}

// contractSeal — sha256 = hex(SHA-256(template_version + "\n" + canonical_json(vars))) (§D ②).
// 레지스트리를 보지 않는다 — 봉인은 "그 계약에 스탬프된 것"을 덮는 연산이라, 스탬프 이후
// 버전이 퇴역해도 성립해야 한다. 이 해시가 하는 일: 사후 변조 검출(재계산 대조). 하지 않는
// 일: 변조 방지(§D ② — 그건 append-only 원장·외부 타임스탬프의 영역).
func contractSeal(templateVersion string, vars map[string]string) string {
	sum := sha256.Sum256([]byte(templateVersion + "\n" + canonicalJSONVars(vars)))
	return hex.EncodeToString(sum[:])
}
