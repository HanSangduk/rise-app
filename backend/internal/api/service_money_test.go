package api

// 돈 계산 회귀(P12 감사 — 환불·결제·발급). curl 실측으로 재현된 CRITICAL 2건(환불 지급액 배가·
// 일시불 0원 환불)과 HIGH/MEDIUM 2건(발급 금액 무검증·미래 paid_at 수용)을 **실제 금액**으로
// 고정한다. 파일을 나눈 이유: 네 건은 "돈이 잘못 나간다"는 한 사건이고, 회귀했을 때 어디를
// 봐야 하는지 파일 이름이 먼저 답하게 하려는 것이다.

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// seedMemberWithPricedPass — 계약가·횟수를 지정해 회원+패스를 만든다(seedMemberWithPass는
// 1,000,000원 20회 고정이라 단가가 다른 정산 골든값을 만들 수 없다).
func seedMemberWithPricedPass(t *testing.T, s *Service, name, phone string, paid, sessions int) (*domain.Member, *domain.Pass) {
	t.Helper()
	ctx := context.Background()
	kst := time.Now().In(domain.KST)
	seedTrainerRecord(t, s, "t1", "정혜린")
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: name, Phone: phone, TrainerID: "t1", Status: domain.MemberStatusActive,
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatalf("CreateMember: %v", err)
	}
	pass, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: "그룹 12회",
		PaidAmount: paid, TotalSessions: sessions,
		ValidFrom:  kst.AddDate(0, 0, -1).Format("2006-01-02"),
		ValidUntil: kst.AddDate(0, 0, 90).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatalf("CreatePass: %v", err)
	}
	return mem, pass
}

// C1 — 결제 기록이 중복되면 환불 지급액이 그대로 배가됐다(실측: 1,000,000 패스에 결제 2건 →
// paid_sum 2,000,000 / refund 1,550,000). 도달 경로는 어드민의 "결제만 재시도"(서버 성공 +
// 응답 유실을 구분 못 함)라, 서버에 방어선이 둘 다 있어야 한다:
// ① 쓰기 — 계약가를 넘는 결제 기록 자체를 거부 ② 읽기 — 이미 박힌 중복도 정산 기준을 못 넘김.
func TestRefundBasisCappedAtContractPrice(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20) // 계약가 1,000,000원 / 20회
	paidAt := time.Now().UTC().Add(-24 * time.Hour)
	firstPayment := PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 1_000_000,
		Installments: []domain.Installment{{Due: "2026-08-01", Amount: 1_000_000, PaidAt: &paidAt}},
	}
	if _, err := s.CreatePayment(ctx, ownerP(), firstPayment); err != nil {
		t.Fatalf("정상 결제 기록 실패: %v", err)
	}

	// ① 쓰기 방어선: 같은 패스에 계약가를 넘는 결제를 또 기록할 수 없다.
	if _, err := s.CreatePayment(ctx, ownerP(), firstPayment); !errors.Is(err, errBadRequest) {
		t.Fatalf("중복 결제 재기록 err = %v, want 400(계약가 1,000,000 초과)", err)
	}
	// 완납된 패스에는 1원도 더 붙지 않는다(초과분만 막는 게 아니라 초과 자체를 막는다).
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "cash", Total: 1,
	}); !errors.Is(err, errBadRequest) {
		t.Fatalf("완납 패스에 1원 추가 기록 err = %v, want 400", err)
	}

	// ② 읽기 방어선: 쓰기 게이트 이전에 이미 박힌 중복(감사가 프로덕션에 남긴 레코드)을
	//    스토어 직접 삽입으로 재현한다 — 원장은 append-only라 지울 수 없고, 정산만 막을 수 있다.
	if _, err := s.store.CreatePayment(ctx, testCenter, &domain.Payment{
		MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 1_000_000,
		Installments: []domain.Installment{{Due: "2026-08-01", Amount: 1_000_000, PaidAt: &paidAt}},
	}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 7; i++ {
		if _, err := s.store.AppendLedger(ctx, testCenter, &domain.Ledger{
			PassID: pass.ID, MemberID: mem.ID, Delta: -1, Reason: domain.ReasonComplete,
			By: "t1", At: time.Now().UTC(),
		}); err != nil {
			t.Fatal(err)
		}
	}

	quote, err := s.RefundQuote(ctx, ownerP(), pass.ID, 7)
	if err != nil {
		t.Fatal(err)
	}
	// 계약가 1,000,000 · 20회 · 7회 사용 · 10% → per 50,000 / usage 350,000 / penalty 100,000
	// → refund 550,000(계약 골든값). 상한이 없으면 실수납 2,000,000 기준 1,550,000이 나간다.
	if quote.PaidSum != 1_000_000 || quote.Refund != 550_000 {
		t.Fatalf("견적 = %+v, want paid_sum 1,000,000 / refund 550,000(중복 합산 시 1,550,000)", quote)
	}
	_, settled, err := s.RefundPass(ctx, ownerP(), pass.ID, 7)
	if err != nil {
		t.Fatal(err)
	}
	if settled.Refund != 550_000 || settled.PaidSum != 1_000_000 {
		t.Fatalf("실행 정산 = %+v, want 견적과 동일(550,000)", settled)
	}
}

// C1 과잉 차단 방지: 계약가 상한은 "패스당 결제 1건"이 아니다 — 카드 일부 + 현금 일부처럼
// 여러 건으로 나눠 기록하는 정상 영업 흐름은 합계가 계약가 이내인 한 그대로 통과해야 한다.
func TestSplitPaymentRecordsWithinContractPriceAllowed(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20) // 계약가 1,000,000원
	for _, c := range []struct {
		method string
		total  int
	}{{"card", 600_000}, {"cash", 400_000}} {
		if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
			MemberID: mem.ID, PassID: pass.ID, Method: c.method, Total: c.total,
		}); err != nil {
			t.Fatalf("%s %d원 분할 기록 실패: %v", c.method, c.total, err)
		}
	}
	quote, err := s.RefundQuote(ctx, ownerP(), pass.ID, 0)
	if err != nil {
		t.Fatal(err)
	}
	if quote.PaidSum != 1_000_000 || quote.Refund != 900_000 {
		t.Fatalf("분할 기록 견적 = %+v, want paid_sum 1,000,000 / refund 900,000", quote)
	}
}

// C2 — installments를 안 적은 일시불 결제가 "받은 적 없는 돈"으로 계산돼 전액 납부 회원의
// 환불액이 0원이 됐다(실측: 360,000 완납 → refund-quote 0원 → 환불 확정, 되돌릴 API 없음).
// 같은 레코드가 미수금 집계에서는 이미 "낼 것 없음"(Outstanding=0)이었다 — 두 계산이 한
// 레코드를 두고 정반대를 말하던 것이 결함의 본체다.
func TestLumpSumPaymentSettlesAtFullAmount(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPricedPass(t, s, "박서연", "010-2222-3333", 360_000, 12)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "cash", Total: 360_000, // 일시불 — installments 미기재
	}); err != nil {
		t.Fatal(err)
	}

	quote, err := s.RefundQuote(ctx, ownerP(), pass.ID, 0)
	if err != nil {
		t.Fatal(err)
	}
	// 360,000 · 12회 · 0회 사용 · 10% → per 30,000 / usage 0 / penalty 36,000 / refund 324,000.
	if quote.PaidSum != 360_000 || quote.Refund != 324_000 {
		t.Fatalf("일시불 견적 = %+v, want paid_sum 360,000 / refund 324,000(실측 결함은 0원)", quote)
	}
	// 미수금에도 잡히지 않는다(수납으로 세는 쪽과 청구로 세는 쪽이 같은 레코드를 같게 봐야 한다).
	stats, err := s.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	if stats.UnpaidTotal != 0 || stats.UpcomingTotal != 0 {
		t.Errorf("일시불 결제 후 미수 = 연체 %d / 미도래 %d, want 0/0", stats.UnpaidTotal, stats.UpcomingTotal)
	}
	_, settled, err := s.RefundPass(ctx, ownerP(), pass.ID, 0)
	if err != nil {
		t.Fatal(err)
	}
	if settled.Refund != 324_000 {
		t.Fatalf("일시불 환불 실행 = %+v, want 324,000", settled)
	}
}

// H5 — 발급이 total_sessions/paid_amount를 검증하지 않아 0회·음수 회차 패스가 원장에 박혔다
// (0회 → 영원히 예약 불가, -5회 → {"delta":-5,"reason":"issue"}가 append-only로 남아 복구 불가).
// CreatePayment는 total<=0을 막는데 발급만 열려 있던 비대칭을 닫는다.
func TestCreatePassRejectsInvalidAmounts(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedTrainerRecord(t, s, "t1", "정혜린")
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "금액검증", Phone: "010-5555-6666", TrainerID: "t1", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	kst := time.Now().In(domain.KST)
	base := PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: "PT 10회",
		ValidFrom:  kst.Format("2006-01-02"),
		ValidUntil: kst.AddDate(0, 3, 0).Format("2006-01-02"),
	}

	bad := []struct {
		name           string
		paid, sessions int
	}{
		{"0회 발급(영원히 예약 불가)", 500_000, 0},
		{"음수 회차(원장에 -5 issue)", 500_000, -5},
		{"음수 금액", -1, 10},
		{"음수 금액 + 음수 회차", -500_000, -1},
	}
	for _, c := range bad {
		req := base
		req.PaidAmount, req.TotalSessions = c.paid, c.sessions
		if _, err := s.CreatePass(ctx, ownerP(), req); !errors.Is(err, errBadRequest) {
			t.Errorf("%s: err = %v, want 400", c.name, err)
		}
	}
	// 거부는 원장에도 흔적을 남기지 않아야 한다 — 발급 원장은 append-only라 잘못 적재되면
	// 되돌릴 수 없다(감사에서 실제로 -5가 박혔다).
	entries, err := s.store.ListLedger(ctx, testCenter, mem.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("거부된 발급이 원장에 %d건 적재: %+v", len(entries), entries)
	}
	passes, err := s.ListPasses(ctx, ownerP(), mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(passes) != 0 {
		t.Fatalf("거부된 발급이 패스로 저장됨: %d건", len(passes))
	}

	// 0원 패스는 허용한다 — 무료 체험권·서비스 제공은 실제 영업 조건이고, 금액 0은 "잘못된 값"이
	// 아니라 "받을 돈이 없다"는 정상 상태다(회차 0과 달리 어떤 계산도 망가뜨리지 않는다).
	req := base
	req.PaidAmount, req.TotalSessions = 0, 1
	free, err := s.CreatePass(ctx, ownerP(), req)
	if err != nil {
		t.Fatalf("0원 체험권 발급 실패: %v", err)
	}
	if free.Remaining != 1 {
		t.Errorf("0원 체험권 잔여 = %d, want 1", free.Remaining)
	}
}

// M5 — installments[].paid_at을 클라이언트 값 그대로 수용해 **미래 시각**도 통과했다.
// 미래 납부는 그 즉시 환불 기준액(실수납)에 반영되므로, 아직 들어오지 않은 돈이 환불로 나간다.
func TestCreatePaymentRejectsFuturePaidAt(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	future := time.Now().UTC().Add(48 * time.Hour)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "transfer", Total: 1_000_000,
		Installments: []domain.Installment{
			{Due: "2026-09-01", Amount: 500_000},
			{Due: "2026-10-01", Amount: 500_000, PaidAt: &future},
		},
	}); !errors.Is(err, errBadRequest) {
		t.Fatalf("미래 paid_at err = %v, want 400", err)
	}
	// 거부된 결제가 기록으로 남지 않았는지 — 남으면 미수금·매출·환불 기준이 전부 오염된다.
	pays, err := s.ListPayments(ctx, ownerP(), mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(pays) != 0 {
		t.Fatalf("거부된 결제가 저장됨: %d건", len(pays))
	}

	// 과거 시각은 통과(데스크가 "지난주에 이미 받았다"를 기록하는 정상 경로).
	past := time.Now().UTC().Add(-72 * time.Hour)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "transfer", Total: 600_000,
		Installments: []domain.Installment{{Due: "2026-08-01", Amount: 600_000, PaidAt: &past}},
	}); err != nil {
		t.Fatalf("과거 paid_at 기록 실패: %v", err)
	}
	// 데스크 PC 시계가 몇 초~몇 분 앞서는 것까지 막으면 정상 입력이 랜덤하게 거부된다 —
	// 허용 오차 안(+1분)은 통과해야 한다.
	skew := time.Now().UTC().Add(1 * time.Minute)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "cash", Total: 400_000,
		Installments: []domain.Installment{{Due: "2026-08-02", Amount: 400_000, PaidAt: &skew}},
	}); err != nil {
		t.Fatalf("시계 오차 범위(+1분) paid_at 거부: %v", err)
	}
	// 오차 범위로 통과시킨 결제는 정산에서도 즉시 실수납으로 잡혀야 한다 — 게이트가 받아준
	// 돈을 정산이 몇 분간 "받은 적 없다"고 하면 그 사이의 환불액이 달라진다.
	quote, err := s.RefundQuote(ctx, ownerP(), pass.ID, 0)
	if err != nil {
		t.Fatal(err)
	}
	if quote.PaidSum != 1_000_000 {
		t.Errorf("paid_sum = %d, want 1,000,000(과거 600,000 + 오차범위 400,000)", quote.PaidSum)
	}
}

// M5 읽기 방어선 — 게이트 이전에 박힌 미래 paid_at은 정산에서 실수납으로 세지 않는다.
// 원장주의(P3)상 잘못된 결제 레코드를 지울 수 없으므로, C1(계약가 상한)과 같은 "쓰기+읽기
// 이중 방어" 구조를 M5에도 둔다.
func TestFuturePaidAtNotCountedInRefundBasis(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20) // 계약가 1,000,000원
	past := time.Now().UTC().Add(-72 * time.Hour)
	future := time.Now().UTC().Add(48 * time.Hour)
	// 스토어 직접 삽입 = 게이트 이전 레코드 재현(지금은 CreatePayment가 400으로 거부한다).
	if _, err := s.store.CreatePayment(ctx, testCenter, &domain.Payment{
		MemberID: mem.ID, PassID: pass.ID, Method: "transfer", Total: 1_000_000,
		Installments: []domain.Installment{
			{Due: "2026-08-01", Amount: 500_000, PaidAt: &past},
			{Due: "2026-09-01", Amount: 500_000, PaidAt: &future},
		},
	}); err != nil {
		t.Fatal(err)
	}
	quote, err := s.RefundQuote(ctx, ownerP(), pass.ID, 0)
	if err != nil {
		t.Fatal(err)
	}
	// 실수납 500,000(미래분 제외) - 위약금 100,000(계약가 1,000,000의 10%) = 400,000.
	// 미래분을 세면 900,000이 나간다.
	if quote.PaidSum != 500_000 || quote.Refund != 400_000 {
		t.Fatalf("견적 = %+v, want paid_sum 500,000 / refund 400,000(미래 납부분 제외)", quote)
	}
}
