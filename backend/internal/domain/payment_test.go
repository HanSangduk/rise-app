package domain

import (
	"testing"
	"time"
)

func TestPaymentOutstandingSumsUnpaidInstallments(t *testing.T) {
	paid := time.Date(2026, 8, 1, 0, 0, 0, 0, KST)
	p := Payment{Total: 900_000, Installments: []Installment{
		{Due: "2026-08-01", Amount: 300_000, PaidAt: &paid},
		{Due: "2026-09-01", Amount: 300_000, PaidAt: nil},
		{Due: "2026-10-01", Amount: 300_000, PaidAt: nil},
	}}
	if got := p.Outstanding(); got != 600_000 {
		t.Errorf("Outstanding = %d, want 600000(미납 2회분)", got)
	}
}

func TestPaymentOutstandingAllPaidIsZero(t *testing.T) {
	paid := time.Date(2026, 8, 1, 0, 0, 0, 0, KST)
	p := Payment{Installments: []Installment{{Amount: 500_000, PaidAt: &paid}}}
	if got := p.Outstanding(); got != 0 {
		t.Errorf("Outstanding = %d, want 0(전액 완납)", got)
	}
}

func TestPaymentOutstandingNoInstallmentsIsZero(t *testing.T) {
	p := Payment{Total: 500_000} // 일시불(분할 없음)
	if got := p.Outstanding(); got != 0 {
		t.Errorf("Outstanding = %d, want 0(분할 없음)", got)
	}
}

// TestPaidSumLumpSumIsFullTotal — 분할 회차가 없는 결제는 **일시불 완납**이다(P12 감사 C2).
// 같은 레코드에 대해 Outstanding()은 이미 0(낼 것 없음)을 반환하는데 PaidSum()만 0(받은 적
// 없음)을 반환하면, 전액 납부한 회원의 환불 기준액이 0원이 된다(실측: 360,000 완납 → 환불 0원).
// 불변식: 회차 없는 결제는 PaidSum + Outstanding == Total.
func TestPaidSumLumpSumIsFullTotal(t *testing.T) {
	now := time.Now()
	p := Payment{Total: 360_000} // 일시불(분할 없음)
	if got := p.PaidSum(now); got != 360_000 {
		t.Errorf("PaidSum = %d, want 360000(일시불 완납)", got)
	}
	if got := p.PaidSum(now) + p.Outstanding(); got != p.Total {
		t.Errorf("PaidSum+Outstanding = %d, want %d(불변식)", got, p.Total)
	}
}

// TestPaidSumExcludesFuturePaidAt — 미래 시각의 paid_at은 실수납으로 세지 않는다(P12 감사 M5).
// paid_at은 클라이언트가 보내는 값이라 게이트 이전엔 미래 시각도 저장됐고, 그 즉시 "아직 들어오지
// 않은 돈"이 환불 기준액이 됐다.
func TestPaidSumExcludesFuturePaidAt(t *testing.T) {
	now := time.Now()
	past := now.Add(-24 * time.Hour)
	future := now.Add(24 * time.Hour)
	p := Payment{Total: 1_000_000, Installments: []Installment{
		{Due: "2026-08-01", Amount: 400_000, PaidAt: &past},
		{Due: "2026-09-01", Amount: 600_000, PaidAt: &future},
	}}
	if got := p.PaidSum(now); got != 400_000 {
		t.Errorf("PaidSum = %d, want 400000(미래 납부 600,000 제외)", got)
	}
}

// TestPaidSumWithInstallmentsCountsOnlyPaid — 회차가 있으면 종전대로 납부된 회차만 센다
// (일시불 폴백이 분할 미완납까지 완납으로 만들지 않는지 — v1.5 정산 골든과 충돌 금지).
func TestPaidSumWithInstallmentsCountsOnlyPaid(t *testing.T) {
	paid := time.Date(2026, 8, 1, 0, 0, 0, 0, KST)
	p := Payment{Total: 1_000_000, Installments: []Installment{
		{Due: "2026-08-01", Amount: 500_000, PaidAt: &paid},
		{Due: "2026-09-01", Amount: 500_000},
	}}
	if got := p.PaidSum(time.Now()); got != 500_000 {
		t.Errorf("PaidSum = %d, want 500000(납부 1회분만)", got)
	}
}

// TestTotalOutstandingAcrossPayments — GET /v1/payments?member= 목록에서 여러 건의 미수금을
// 한 번에 합산하는 용도(v1.1 정합 패치 "결제 목록... 분할·미수 확인").
func TestTotalOutstandingAcrossPayments(t *testing.T) {
	paid := time.Date(2026, 8, 1, 0, 0, 0, 0, KST)
	payments := []Payment{
		{Installments: []Installment{{Amount: 100_000, PaidAt: nil}}},
		{Installments: []Installment{{Amount: 200_000, PaidAt: &paid}, {Amount: 50_000, PaidAt: nil}}},
	}
	if got := TotalOutstanding(payments); got != 150_000 {
		t.Errorf("TotalOutstanding = %d, want 150000", got)
	}
}

func TestTotalOutstandingEmpty(t *testing.T) {
	if got := TotalOutstanding(nil); got != 0 {
		t.Errorf("TotalOutstanding(nil) = %d, want 0", got)
	}
}
