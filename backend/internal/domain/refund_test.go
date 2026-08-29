package domain

import "testing"

// 골든값 출처: /Users/straram/development/2026-06-workout-app/ptdesk/docs/API계약_v1.md
// "환불 1,000,000·20회·7회사용·10% → per 50,000 / usage 350,000 / penalty 100,000 / refund 550,000".
func TestRefundQuoteGolden(t *testing.T) {
	got := RefundQuote(1_000_000, 20, 7, 0.10)
	want := RefundResult{PerSession: 50_000, Usage: 350_000, Penalty: 100_000, PaidSum: 1_000_000, Refund: 550_000}
	if got != want {
		t.Errorf("RefundQuote(1000000,20,7,0.10) = %+v, want %+v", got, want)
	}
}

func TestRefundQuotePenaltyRateCappedAt10Percent(t *testing.T) {
	// 센터가 위약금율을 20%로 잘못 설정해도 상한 10%로 강제 캡(설계00 P6: "10%는 상한").
	got := RefundQuote(1_000_000, 20, 7, 0.20)
	if got.Penalty != 100_000 {
		t.Errorf("penalty = %d, want 100000(10%% 상한 강제)", got.Penalty)
	}
}

func TestRefundQuoteLowerRateHonored(t *testing.T) {
	// 상한보다 낮게 설정된 위약금율은 그대로 적용(P6: "더 낮게 설정 가능").
	got := RefundQuote(1_000_000, 20, 7, 0.05)
	if got.Penalty != 50_000 {
		t.Errorf("penalty = %d, want 50000(5%% 그대로)", got.Penalty)
	}
}

func TestRefundQuoteNoUsageBeforeStart(t *testing.T) {
	// 개시 전(사용 0회) 해제 — 위약금 10%만 공제(설계00 §3 정정1).
	got := RefundQuote(1_000_000, 20, 0, 0.10)
	if got.Usage != 0 || got.Penalty != 100_000 || got.Refund != 900_000 {
		t.Errorf("got %+v, want usage=0 penalty=100000 refund=900000", got)
	}
}

func TestRefundQuoteZeroTotalSessionsSafe(t *testing.T) {
	got := RefundQuote(500_000, 0, 0, 0.10)
	if got.PerSession != 0 {
		t.Errorf("total=0일 때 per_session=%d, want 0(0으로 나누기 방지)", got.PerSession)
	}
}

func TestRefundQuoteNeverNegative(t *testing.T) {
	// 이용분+위약금이 실결제액을 넘어도(다회 사용 후 늦은 해지) refund는 0 미만으로 내려가지 않는다.
	got := RefundQuote(100_000, 10, 10, 0.10)
	if got.Refund < 0 {
		t.Errorf("refund = %d, 음수 불가", got.Refund)
	}
	if got.Refund != 0 {
		t.Errorf("refund = %d, want 0(전액 소진 후 위약금까지 더하면 0으로 clamp)", got.Refund)
	}
}

// TestSettleRefundCapsPaidSumAtContractPrice — 정산 기준액(실수납)의 상한은 계약가다(P12 감사 C1).
// 결제 기록이 중복되면 실수납 합이 계약가를 넘고, 상한이 없으면 그 초과분이 그대로 환불로
// 나갔다(실측: 1,000,000 패스에 1,000,000 결제 2건 → 환불 1,550,000). MaxPenaltyRate와 같은
// 자리의 방어선이다 — 설정·입력이 무엇이든 도메인이 마지막으로 캡핑한다.
func TestSettleRefundCapsPaidSumAtContractPrice(t *testing.T) {
	got := SettleRefund(1_000_000, 20, 7, 0.10, 2_000_000)
	if got.PaidSum != 1_000_000 || got.Refund != 550_000 {
		t.Errorf("SettleRefund(실수납 2,000,000) = %+v, want paid_sum 1,000,000 / refund 550,000", got)
	}
	// 음수 실수납(데이터 이상)도 0으로 clamp — 환불액이 공제만 남아 음수로 내려가지 않게.
	if r := SettleRefund(1_000_000, 20, 0, 0.10, -100_000); r.PaidSum != 0 || r.Refund != 0 {
		t.Errorf("SettleRefund(실수납 음수) = %+v, want paid_sum 0 / refund 0", r)
	}
}

// v1.5 정산 골든: 분할 1차 500,000원만 수납된 20회 패스, 7회 사용, 10% —
// 이용 350,000 + 위약 100,000 > 실수납 500,000 → 환불 50,000 (계약가 기준 550,000이 아님).
func TestSettleRefundPartialPaid(t *testing.T) {
	got := SettleRefund(1_000_000, 20, 7, 0.10, 500_000)
	if got.Refund != 50_000 || got.PaidSum != 500_000 {
		t.Errorf("SettleRefund = %+v, want refund 50,000 / paid_sum 500,000", got)
	}
	// 실수납 < 공제액이면 환불 0(음수 금지).
	if r := SettleRefund(1_000_000, 20, 10, 0.10, 300_000); r.Refund != 0 {
		t.Errorf("과소 수납 환불 = %d, want 0", r.Refund)
	}
	// 완납이면 기존 골든과 동일.
	if r := SettleRefund(1_000_000, 20, 7, 0.10, 1_000_000); r.Refund != 550_000 {
		t.Errorf("완납 환불 = %d, want 550,000", r.Refund)
	}
}
