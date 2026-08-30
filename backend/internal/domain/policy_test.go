package domain

import (
	"errors"
	"fmt"
	"strings"
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
//
//	① 초과값이 그대로 계약 스냅샷·회원앱으로 새어나간다(고치려던 결함 그대로).
//	② 머지 시맨틱 PUT이 초과값을 그대로 이어받아 Validate에 걸려 **다른 필드 수정까지 400**이 된다
//	   (용량만 바꾸려 해도 저장이 안 되는 잠금 상태).
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

// ---- 운영시간(v2.24, P51) ----

// 경계 표. `0 <= open_hour < close_hour <= 23`이 전부인데, 그 "전부"가 실제로 전부인지를
// 한 표로 잠근다 — 특히 **0시가 합법**이라는 것과 **open==close가 불법**이라는 것.
func TestPolicyValidateHours(t *testing.T) {
	cases := []struct {
		name       string
		open, clos int
		ok         bool
	}{
		{"기본값 9~21", 9, 21, true},
		{"자정 개점(0시는 실제 여는 시각)", 0, 23, true},
		{"이른 개점", 6, 22, true},
		{"최소 폭(한 칸 차이 = 슬롯 2개)", 9, 10, true},
		{"끝값 23", 22, 23, true},
		{"open == close", 9, 9, false},
		{"open > close", 21, 9, false},
		{"close 24(경계 밖)", 9, 24, false},
		{"open 음수", -1, 21, false},
		{"close 음수", 9, -1, false},
		{"open 24", 24, 24, false},
		{"둘 다 0(부재 서명 — 쓰기로는 불법)", 0, 0, false},
	}
	for _, c := range cases {
		p := DefaultPolicy()
		p.OpenHour, p.CloseHour = c.open, c.clos
		err := p.Validate()
		if c.ok && err != nil {
			t.Errorf("%s: %d~%d가 거부됐다: %v", c.name, c.open, c.clos, err)
		}
		if !c.ok {
			if !errors.Is(err, ErrInvalidPolicy) {
				t.Errorf("%s: %d~%d가 통과했다: %v", c.name, c.open, c.clos, err)
				continue
			}
			// 문구가 두 숫자를 모두 말해야 한다 — 폼이 두 칸인데 어느 칸이 틀렸는지 못 알려주면
			// 대표는 같은 400을 반복해서 만난다.
			msg := err.Error()
			if !strings.Contains(msg, fmt.Sprintf("%d시", c.open)) || !strings.Contains(msg, fmt.Sprintf("%d시", c.clos)) {
				t.Errorf("%s: 에러 문구에 두 숫자가 없다: %q", c.name, msg)
			}
		}
	}
}

// 운영시간을 건드리지 않은 정상 정책이 운영시간 때문에 거부되면 **정책 편집 전체가 잠긴다**
// (머지 PUT이 기존 값을 이어받으므로 용량 하나 바꾸려 해도 400) — P14 C1과 같은 모양의 사고.
func TestPolicyValidateDefaultHoursPass(t *testing.T) {
	if err := DefaultPolicy().Validate(); err != nil {
		t.Fatalf("기본 정책이 Validate를 통과하지 못한다: %v", err)
	}
}

// 부재 승격: (0,0) **쌍**만 부재로 읽는다. 0시를 필드 단위 부재로 읽으면 24시간 헬스장의
// 자정 개점이 표현 불가능해진다 — 그 표현 가능성이 이 설계의 값이다.
func TestPolicyNormalizeHours(t *testing.T) {
	cases := []struct {
		name               string
		open, clos         int
		wantOpen, wantClos int
	}{
		{"필드 부재(구문서) → 기본값", 0, 0, 9, 21},
		{"자정 개점은 승격 대상이 아니다", 0, 22, 0, 22},
		{"명시값은 그대로", 6, 23, 6, 23},
		{"기본값 그대로", 9, 21, 9, 21},
		// close만 0인 조합은 정상 경로로는 저장될 수 없다(Validate가 막는다). 손으로 고친
		// 문서라면 승격하지 않고 그대로 둔다 — 조용히 고치면 무엇이 잘못됐는지 아무도 모른다.
		{"손상 문서(close만 0)는 승격하지 않는다", 9, 0, 9, 0},
	}
	for _, c := range cases {
		p := DefaultPolicy()
		p.OpenHour, p.CloseHour = c.open, c.clos
		p.Normalize()
		if p.OpenHour != c.wantOpen || p.CloseHour != c.wantClos {
			t.Errorf("%s: Normalize(%d,%d) = (%d,%d), want (%d,%d)",
				c.name, c.open, c.clos, p.OpenHour, p.CloseHour, c.wantOpen, c.wantClos)
		}
	}
}

// **오프바이원 잠금.** 9~21은 13칸이고 마지막 칸은 21시에 시작한다. 이 한 줄이 틀리면
// 영업 한 시간이 조용히 사라지거나 없던 한 시간이 생긴다.
func TestPolicySlotHoursInclusive(t *testing.T) {
	p := DefaultPolicy()
	hours := p.SlotHours()
	if len(hours) != 13 {
		t.Fatalf("9~21 슬롯 수 = %d, want 13 — 양끝 포함(h <= close)이다", len(hours))
	}
	if hours[0] != 9 {
		t.Errorf("첫 슬롯 = %d시, want 9시", hours[0])
	}
	if last := hours[len(hours)-1]; last != 21 {
		t.Errorf("마지막 슬롯 = %d시, want 21시 — 21시에 **시작하는** 수업이 마지막이다", last)
	}
	if !p.IsOpenHour(9) || !p.IsOpenHour(21) {
		t.Error("양끝(9시·21시)이 운영시간 밖으로 판정됐다")
	}
	if p.IsOpenHour(8) || p.IsOpenHour(22) {
		t.Error("운영시간 밖(8시·22시)이 안으로 판정됐다")
	}
	// 24시간 개점: 0~23은 24칸.
	full := DefaultPolicy()
	full.OpenHour, full.CloseHour = 0, 23
	if got := len(full.SlotHours()); got != 24 {
		t.Errorf("0~23 슬롯 수 = %d, want 24", got)
	}
	// 손상 범위는 빈 목록(패닉·역순 루프 금지).
	bad := DefaultPolicy()
	bad.OpenHour, bad.CloseHour = 21, 9
	if got := bad.SlotHours(); len(got) != 0 {
		t.Errorf("역순 범위 SlotHours = %v, want 빈 목록", got)
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
