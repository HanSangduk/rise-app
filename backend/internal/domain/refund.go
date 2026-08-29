package domain

// MaxPenaltyRate — 위약금율의 정책 상한 10%(설계00 P5·P6, 팩트체크 표 #1·#3).
// 센터 설정값(policy.penalty_rate)은 이보다 낮게 정할 수 있고, **넘게는 정할 수 없다** —
// Policy.Validate가 저장 단계에서 거부하고(P14 C1), 검증을 지나지 않은 값(구문서·수동 편집)은
// Policy.Normalize가 읽는 자리에서 접는다.
//
// 그럼에도 이 캡을 남겨 두는 이유: 계약 스냅샷은 **과거에 서명된 값**이라 정책과 무관하게
// 남아 있고(P14 이전에 30%로 서명된 계약이 실재한다), 돈이 나가기 직전의 마지막 방어선은
// 코드여야 한다(약관규제법 §8 리스크 완화). 정상 경로에서는 아무것도 바꾸지 않는다.
const MaxPenaltyRate = 0.10

// RefundResult — 환불 계산 결과(API계약 v1 응답 형식 + v1.5의 paid_sum).
type RefundResult struct {
	PerSession int `json:"per_session"`
	Usage      int `json:"usage"`
	Penalty    int `json:"penalty"`
	// PaidSum — 정산 기준이 된 실수납액(v1.5). 분할납부 미완납 시 계약가와 다르다 —
	// 환불액은 "실제로 받은 돈"에서만 나갈 수 있다(P5의 실질 구현).
	PaidSum int `json:"paid_sum"`
	Refund  int `json:"refund"`

	// CancelledBookings — 환불이 **함께 취소한** 미래 예약 건수(v2.14).
	//
	// 환불은 돈만 움직이는 게 아니라 회원의 앞으로 잡힌 수업을 통째로 지운다.
	// 그런데 어드민 확인 문구는 "원장에 refund 기록이 남고 되돌릴 수 없어요"까지만
	// 말했고, 완료 화면도 부수효과 셋 중 둘(미납 청구 종결·미서명 계약 무효)만 적었다 —
	// 예약 취소가 빠진 채 목록이 완결돼 보여서 누락이 더 위험했다.
	//
	// 서버에 푸시 채널이 없어 회원은 앱을 열어야 사라진 걸 안다. 그러니 최소한
	// **누른 사람은** 몇 건이 사라지는지 알아야 한다.
	//
	// 같은 저장소의 `DELETE /v1/me`가 이미 같은 규약을 쓴다(`cancelled_bookings`를
	// 세어 응답에 싣고 앱이 그 숫자를 화면에 쓴다) — 그 패턴을 그대로 따랐다.
	CancelledBookings int `json:"cancelled_bookings"`
}

// RefundQuote — 환불 계산(순수 함수, 설계00 불변식6). 실결제가 기준(P5) — 정가 공제 옵션은 만들지 않는다.
//
//	per     = paid / total                              (회당 단가, 정수 나눗셈·원 단위 절삭)
//	usage   = per * used                                (이용분)
//	penalty = min(paid * penaltyRate, paid * MaxPenaltyRate)  (위약금, 상한 10% 강제)
//	refund  = max(paid - usage - penalty, 0)
//
// 골든값(API계약 v1): 1,000,000원·20회·7회사용·10% → per 50,000 / usage 350,000 / penalty 100,000 / refund 550,000.
func RefundQuote(paid, total, used int, penaltyRate float64) RefundResult {
	var per int
	if total > 0 {
		per = paid / total
	}
	usage := per * used

	byRate := int(float64(paid) * penaltyRate)
	byCap := int(float64(paid) * MaxPenaltyRate)
	penalty := byRate
	if penalty > byCap {
		penalty = byCap
	}
	if penalty < 0 {
		penalty = 0
	}

	refund := paid - usage - penalty
	if refund < 0 {
		refund = 0
	}
	return RefundResult{PerSession: per, Usage: usage, Penalty: penalty, PaidSum: paid, Refund: refund}
}

// SettleRefund — 환불 "정산"(v1.5): 회당 단가·이용분·위약금은 계약가(paid) 기준으로 산출하되,
// 환불액은 실수납(paidSum)에서만 나간다 — 분할 1차만 수납된 패스를 계약가 기준으로 환불하면
// 받은 적 없는 돈을 돌려주게 된다(P04 감사 HIGH: 50만 수납 → 90만 견적 실측).
//
//	basis   = min(max(paidSum, 0), paid)              (정산 기준액 — 계약가가 상한)
//	refund  = max(basis - usage - penalty, 0)
//
// paidSum == paid(완납)이면 RefundQuote와 동일 — 골든값 550,000 유지.
//
// **계약가 상한**(v2.3, P12 감사 C1): 실수납이 계약가를 넘는 것은 언제나 데이터 이상이다
// (같은 결제가 두 번 기록되는 경로가 실재한다 — 어드민의 "결제만 재시도"가 서버 성공과 응답
// 유실을 구분하지 못한다). 상한이 없으면 그 초과분이 그대로 환불로 나갔다(실측: 1,000,000
// 패스에 1,000,000 결제 2건 → 환불 1,550,000 / 550,000 패스에 5,500,000 → 환불 5,445,000).
// 왜 도메인에서 캡핑하나: MaxPenaltyRate와 같은 자리다 — 설정·입력이 무엇이든 돈이 나가기
// 직전의 마지막 방어선은 코드여야 한다. 원장(append-only)의 결제 기록은 그대로 남는다.
// 트레이드오프: 계약가가 실제보다 낮게 잘못 입력된 패스는 덜 환불된다. 검증되지 않은 기록을
// 믿고 더 주는 쪽보다 낫고(나간 돈은 못 돌아온다), 계약가는 회당 단가·위약금의 기준이기도 해서
// 그 값이 틀렸다면 환불이 아니라 패스 자체를 정정해야 할 사안이다.
func SettleRefund(paid, total, used int, penaltyRate float64, paidSum int) RefundResult {
	r := RefundQuote(paid, total, used, penaltyRate)
	if paidSum < 0 {
		paidSum = 0 // 음수 실수납은 존재할 수 없다(데이터 이상) — 공제만 남아 음수 환불이 되지 않게
	}
	if paidSum > paid {
		paidSum = paid
	}
	r.PaidSum = paidSum
	refund := paidSum - r.Usage - r.Penalty
	if refund < 0 {
		refund = 0
	}
	r.Refund = refund
	return r
}
