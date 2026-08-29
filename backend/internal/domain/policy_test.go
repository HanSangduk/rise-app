package domain

import (
	"errors"
	"testing"
)

// P14 C1 — 위약금율의 **정책 상한과 집행 상한이 같은 숫자**여야 한다.
//
// 종전: Validate가 0~1을 전부 통과시키고(30% 저장 성공) RefundQuote만 10%로 캡했다.
// 그 사이에 계약 스냅샷(service.buildContractForPass)이 끼어 있어 **회원은 30% 조항에
// 서명하는데 실제 공제는 10%**였다. 어느 쪽이 진짜 정책인지 코드가 두 답을 냈다.
// 상한이 진짜 정책이므로 저장 단계에서 거부한다 — 집행하지 않을 조항을 발행하지 않는다.
func TestPolicyValidateRejectsPenaltyRateAboveCap(t *testing.T) {
	base := DefaultPolicy()

	over := base
	over.PenaltyRate = 0.30
	if err := over.Validate(); !errors.Is(err, ErrInvalidPolicy) {
		t.Errorf("penalty_rate 0.30이 통과했다: %v — 상한 %.2f를 넘는 값은 저장 전에 거부해야 한다",
			err, MaxPenaltyRate)
	}
	// 상한 바로 위(부동소수 경계)도 거부.
	if p := base; func() bool { p.PenaltyRate = 0.1001; return !errors.Is(p.Validate(), ErrInvalidPolicy) }() {
		t.Error("penalty_rate 0.1001이 통과했다 — 상한은 포함(<=)이지 근사가 아니다")
	}

	at := base
	at.PenaltyRate = MaxPenaltyRate
	if err := at.Validate(); err != nil {
		t.Errorf("상한값 정확히 %.2f가 거부됐다: %v", MaxPenaltyRate, err)
	}
	lower := base
	lower.PenaltyRate = 0.05
	if err := lower.Validate(); err != nil {
		t.Errorf("상한보다 낮은 0.05가 거부됐다: %v — 더 낮게 정하는 것은 언제나 허용", err)
	}
	neg := base
	neg.PenaltyRate = -0.01
	if err := neg.Validate(); !errors.Is(err, ErrInvalidPolicy) {
		t.Errorf("음수 위약금율이 통과했다: %v", err)
	}
}

// 이미 저장된 초과 문서(이번 변경 전에 30%로 저장된 센터·손으로 고친 Firestore 문서)는
// 읽는 순간 상한으로 접힌다. 접지 않으면 두 가지가 동시에 깨진다:
//   ① 초과값이 그대로 계약 스냅샷·회원앱으로 새어나간다(고치려던 결함 그대로).
//   ② 머지 시맨틱 PUT이 초과값을 그대로 이어받아 Validate에 걸려 **다른 필드 수정까지 400**이 된다
//      (용량만 바꾸려 해도 저장이 안 되는 잠금 상태).
func TestPolicyNormalizeClampsLegacyPenaltyRate(t *testing.T) {
	// 30%로 저장된 실제 구문서 모양(다른 필드는 정상) — 홀딩 상한 필드는 없다(v1.2 이전).
	p := DefaultPolicy()
	p.PenaltyRate = 0.30
	p.MaxHoldsPerPass, p.MaxHoldTotalDays = 0, 0
	p.Normalize()
	if p.PenaltyRate != MaxPenaltyRate {
		t.Errorf("정규화 후 penalty_rate = %v, want %v", p.PenaltyRate, MaxPenaltyRate)
	}
	if err := p.Validate(); err != nil {
		t.Errorf("정규화한 구문서가 Validate를 통과하지 못한다: %v — 머지 PUT이 잠긴다", err)
	}
	// 기존 NormalizeHoldLimits 책임도 그대로 수행한다(0 = 필드 부재 → 기본값 승격).
	def := DefaultPolicy()
	if p.MaxHoldsPerPass != def.MaxHoldsPerPass || p.MaxHoldTotalDays != def.MaxHoldTotalDays {
		t.Errorf("홀딩 상한 승격이 사라졌다: %+v", p)
	}
	// 상한 이하 값은 손대지 않는다.
	q := Policy{PenaltyRate: 0.05}
	q.Normalize()
	if q.PenaltyRate != 0.05 {
		t.Errorf("정규화가 정상값을 바꿨다: %v, want 0.05", q.PenaltyRate)
	}
	// 음수(데이터 이상)는 0으로 — 음수 위약금은 환불 과대 지급이다.
	r := Policy{PenaltyRate: -0.5}
	r.Normalize()
	if r.PenaltyRate != 0 {
		t.Errorf("음수 위약금율 정규화 = %v, want 0", r.PenaltyRate)
	}
}

// EffectivePenaltyRate — "계약서에 인쇄되고 실제로 공제되는" 단일 값. 계약 스냅샷·환불·
// 회원앱 응답이 전부 이 함수를 지나야 네 자리가 같은 숫자를 말한다.
func TestPolicyEffectivePenaltyRate(t *testing.T) {
	cases := []struct{ in, want float64 }{
		{0.30, MaxPenaltyRate},
		{MaxPenaltyRate, MaxPenaltyRate},
		{0.05, 0.05},
		{0, 0},
		{-1, 0},
	}
	for _, c := range cases {
		if got := (Policy{PenaltyRate: c.in}).EffectivePenaltyRate(); got != c.want {
			t.Errorf("EffectivePenaltyRate(%v) = %v, want %v", c.in, got, c.want)
		}
	}
}
