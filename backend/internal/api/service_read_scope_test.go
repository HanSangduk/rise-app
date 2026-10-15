package api

import (
	"context"
	"errors"
	"io"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// 읽기 범위(v2.38, P74) — "회원 1명 조회가 센터 전체를 읽지 않는다"를 **스토어 호출 횟수**로 잰다.
// 함수가 맞는 답을 내는지는 다른 시험이 보고, 여기서는 **어느 컬렉션을 얼마나 읽었는지**만 본다 —
// 그것이 규모가 커질 때 비용·지연을 결정하는 유일한 변수라서다.

// 회원 2명 · 배정 1건(둘 다 대상) · 회원 A만 체크 1건.
func seedHomeworkPair(t *testing.T, s *Service) (a, b *domain.Member, hwID string) {
	t.Helper()
	ctx := context.Background()
	seedTrainerRecord(t, s, "t1", "정혜린")
	var err error
	a, err = s.CreateMember(ctx, ownerP(), &domain.Member{Name: "김민지", Phone: "010-1234-5678", TrainerID: "t1", Status: domain.MemberStatusActive})
	if err != nil {
		t.Fatal(err)
	}
	b, err = s.CreateMember(ctx, ownerP(), &domain.Member{Name: "박현우", Phone: "010-2345-6789", TrainerID: "t1", Status: domain.MemberStatusActive})
	if err != nil {
		t.Fatal(err)
	}
	hw, err := s.CreateHomework(ctx, ownerP(), HomeworkCreateRequest{
		TrainerID: "t1", Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{a.ID, b.ID},
		Items:    []domain.HwItem{{Name: "스쿼트", Sets: 3, Reps: "12"}},
		Schedule: domain.HwSchedule{Type: "weekly", Days: []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateHwCheck(ctx, memberP(a.ID), HwCheckRequest{HwID: hw.ID, Date: today(), Done: []bool{true}}); err != nil {
		t.Fatal(err)
	}
	return a, b, hw.ID
}

func TestListHwChecksForOneMemberDoesNotScanCenter(t *testing.T) {
	s, h := newHookedService(t)
	ctx := context.Background()
	a, b, hwID := seedHomeworkPair(t, s)
	h.reset()

	// 회원 본인 조회(앱 홈 탭이 매일 타는 경로) — 회원 필터 읽기만, 전량 읽기 0회.
	got, err := s.ListHwChecks(ctx, memberP(a.ID), "", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].HwID != hwID || got[0].MemberID != a.ID {
		t.Fatalf("회원 A 체크 = %+v, want 본인 1건", got)
	}
	if n := h.callCount("ListHwChecks"); n != 0 {
		t.Errorf("회원 1명 조회가 센터 전체 hwChecks를 %d회 읽었다 — 회원 수×배정×날짜에 비례해 커지는 자리", n)
	}
	if n := h.callCount("ListHwChecksByMember"); n != 1 {
		t.Errorf("ListHwChecksByMember 호출 %d회, want 1", n)
	}

	// 체크가 없는 회원 B — 빈 목록이고, 역시 전량을 읽지 않는다.
	h.reset()
	got, err = s.ListHwChecks(ctx, memberP(b.ID), "", "", "")
	if err != nil || len(got) != 0 {
		t.Fatalf("회원 B 체크 = %v, %v, want 빈 목록", got, err)
	}
	if n := h.callCount("ListHwChecks"); n != 0 {
		t.Errorf("빈 결과인데도 센터 전체를 %d회 읽었다", n)
	}

	// owner가 member= 없이 hw_id로만 보는 경로는 종전대로 전량(회원을 모르니 거를 수 없다).
	h.reset()
	got, err = s.ListHwChecks(ctx, ownerP(), hwID, "", "")
	if err != nil || len(got) != 1 {
		t.Fatalf("owner hw_id 조회 = %v, %v, want 1건", got, err)
	}
	if n := h.callCount("ListHwChecks"); n != 1 {
		t.Errorf("owner 무회원 조회의 전량 읽기 %d회, want 1", n)
	}
	// owner가 member=를 지정하면 그 회원 것만 읽는다(어드민 Home Work 탭의 회원 선택).
	h.reset()
	if _, err := s.ListHwChecks(ctx, ownerP(), "", a.ID, ""); err != nil {
		t.Fatal(err)
	}
	if h.callCount("ListHwChecks") != 0 || h.callCount("ListHwChecksByMember") != 1 {
		t.Errorf("owner member= 조회: 전량 %d회 / 회원 %d회, want 0 / 1", h.callCount("ListHwChecks"), h.callCount("ListHwChecksByMember"))
	}
}

// 통계의 HW 완료율은 **활성 배정의 대상 회원만**, 회원당 한 번씩 읽는다(v2.38, P74 정정).
// HEAD는 배정×대상회원 조합마다 그 회원 것을 다시 읽었고(N+1, 트레이너별 표가 한 번 더), P74 1차는
// 센터 hwChecks 전량을 매번 읽었다(회원 수×날짜로 자라는 컬렉션 — 배정이 없는 트레이너도 전량).
func TestStatsReadsOnlyActiveTargetMembersHwChecks(t *testing.T) {
	s, h := newHookedService(t)
	ctx := context.Background()
	a, b, hwID := seedHomeworkPair(t, s)
	// B는 체크 문서가 있지만 전부 false — "한 번이라도 체크"가 아니다(분자에 들면 안 된다).
	if _, err := s.CreateHwCheck(ctx, memberP(b.ID), HwCheckRequest{HwID: hwID, Date: today(), Done: []bool{false}}); err != nil {
		t.Fatal(err)
	}
	h.reset()

	st, err := s.Stats(ctx, ownerP(), "", "center")
	if err != nil {
		t.Fatal(err)
	}
	// 답은 그대로: 대상 2명 중 A만 완료 → 1/2. 트레이너 표도 같은 인덱스로 같은 값.
	if st.HwD != 2 || st.HwRate != domain.Rate(1, 2) {
		t.Errorf("hw = %.3f (d=%d), want 1/2 — 전부 false인 체크가 완료로 셌거나 A가 빠졌다", st.HwRate, st.HwD)
	}
	var t1 *domain.TrainerStats
	for i := range st.ByTrainer {
		if st.ByTrainer[i].UID == "t1" {
			t1 = &st.ByTrainer[i]
		}
	}
	if t1 == nil || t1.HwD != 2 || t1.HwRate != domain.Rate(1, 2) {
		t.Errorf("by_trainer[t1].hw = %+v, want 1/2", t1)
	}
	if n := h.callCount("ListHwChecks"); n != 0 {
		t.Errorf("Stats가 센터 hwChecks 전량을 %d회 읽었다, want 0 — 회원 수×날짜에 비례해 자라는 자리", n)
	}
	if n := h.callCount("ListHwChecksByMember"); n != 2 {
		t.Errorf("회원별 읽기 %d회, want 2(대상 A·B 한 번씩 — 트레이너 표가 다시 읽지 않는다)", n)
	}

	// 같은 두 회원을 대상으로 배정이 하나 더 — 분모는 4로 늘지만 읽기는 여전히 회원당 1회.
	if _, err := s.CreateHomework(ctx, ownerP(), HomeworkCreateRequest{
		TrainerID: "t1", Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{a.ID, b.ID},
		Items:    []domain.HwItem{{Name: "런지", Sets: 3, Reps: "10"}},
		Schedule: domain.HwSchedule{Type: "weekly", Days: []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}},
	}); err != nil {
		t.Fatal(err)
	}
	h.reset()
	st, err = s.Stats(ctx, ownerP(), "", "center")
	if err != nil {
		t.Fatal(err)
	}
	if st.HwD != 4 || st.HwRate != domain.Rate(1, 4) {
		t.Errorf("배정 2건: hw = %.3f (d=%d), want 1/4", st.HwRate, st.HwD)
	}
	if n := h.callCount("ListHwChecksByMember"); n != 2 {
		t.Errorf("배정 2건 × 대상 2명: 회원별 읽기 %d회, want 2(같은 회원을 배정 수만큼 다시 읽지 않는다)", n)
	}

	// 배정이 하나도 없는 트레이너의 scope=me — 읽을 대상이 없으니 hwChecks를 전혀 읽지 않는다.
	seedTrainerRecord(t, s, "t2", "김도윤")
	h.reset()
	st, err = s.Stats(ctx, Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}, "", "me")
	if err != nil {
		t.Fatal(err)
	}
	if st.HwD != 0 {
		t.Errorf("배정 없는 트레이너의 hw_d = %d, want 0", st.HwD)
	}
	if h.callCount("ListHwChecks")+h.callCount("ListHwChecksByMember") != 0 {
		t.Errorf("배정 없는 트레이너가 hwChecks를 읽었다(전량 %d · 회원 %d), want 0", h.callCount("ListHwChecks"), h.callCount("ListHwChecksByMember"))
	}
}

// 한 회원의 hwChecks 조회가 실패하면 **그 회원만** 분자에서 빠진다(HEAD와 같은 단위) — 통계 전체가
// 실패하거나(500) 완료율 전체가 조용히 0이 되면 안 된다(P74 1차는 전량 읽기 한 번의 실패가 0%였다).
func TestStatsHwReadFailureDropsOnlyThatMember(t *testing.T) {
	s, h := newHookedService(t)
	ctx := context.Background()
	_, b, hwID := seedHomeworkPair(t, s)
	// 두 회원 모두 완료 — 어느 쪽 조회가 먼저 실패하든 결과는 1/2로 정해진다.
	if _, err := s.CreateHwCheck(ctx, memberP(b.ID), HwCheckRequest{HwID: hwID, Date: today(), Done: []bool{true}}); err != nil {
		t.Fatal(err)
	}
	h.reset()
	h.fail = func(op string, n int) error {
		if op == "ListHwChecksByMember" && n == 1 {
			return errors.New("firestore unavailable")
		}
		return nil
	}
	defer func() { h.fail = nil }()

	st, err := s.Stats(ctx, ownerP(), "", "center")
	if err != nil {
		t.Fatalf("한 회원의 HW 조회 실패가 통계 전체를 실패시켰다: %v", err)
	}
	if st.HwD != 2 || st.HwRate != domain.Rate(1, 2) {
		t.Errorf("hw = %.3f (d=%d), want 1/2 — 실패한 회원만 빠져야 한다(0이면 전체가 조용히 사라진 것)", st.HwRate, st.HwD)
	}
}

// 환불 견적·집행은 **그 패스의 결제만** 읽는다 — 종전엔 센터 전체 결제를 읽고 Go에서 걸렀다.
func TestRefundReadsOnlyThatPassPayments(t *testing.T) {
	s, h := newHookedService(t)
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 10)
	paidAt := time.Now().UTC().Add(-time.Hour)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 1_000_000,
		Installments: []domain.Installment{{Due: "2026-08-01", Amount: 1_000_000, PaidAt: &paidAt}},
	}); err != nil {
		t.Fatal(err)
	}
	// 같은 센터의 **다른** 패스 결제 — 정산에 섞이면 안 되고, 읽혀서도 안 된다.
	other, otherPass := seedMemberWithPass(t, s, 20)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: other.ID, PassID: otherPass.ID, Method: "cash", Total: 700_000,
	}); err != nil {
		t.Fatal(err)
	}
	h.reset()

	quote, err := s.RefundQuote(ctx, ownerP(), pass.ID, 0)
	if err != nil {
		t.Fatal(err)
	}
	if quote.PaidSum != 1_000_000 {
		t.Errorf("paid_sum = %d, want 1,000,000 (다른 패스 결제가 섞이거나 빠졌다)", quote.PaidSum)
	}
	if n := h.callCount("ListPayments"); n != 0 {
		t.Errorf("환불 견적이 센터 전체 결제를 %d회 읽었다 — 누적 결제 수에 비례해 커지는 자리", n)
	}
	if n := h.callCount("ListPaymentsByPass"); n != 1 {
		t.Errorf("ListPaymentsByPass 호출 %d회, want 1", n)
	}

	// 실제 환불 집행도 같은 규약(정산 1회 + 마감 후 미납 회차 종결이 패스 결제만 본다).
	h.reset()
	if _, _, err := s.RefundPass(ctx, ownerP(), pass.ID, 0); err != nil {
		t.Fatal(err)
	}
	if n := h.callCount("ListPayments"); n != 0 {
		t.Errorf("환불 집행이 센터 전체 결제를 %d회 읽었다", n)
	}
}

// 회원 결제 목록(앱 마이 탭)도 그 회원 것만 읽는다.
func TestListPaymentsForMemberDoesNotScanCenter(t *testing.T) {
	s, h := newHookedService(t)
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 10)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 300_000}); err != nil {
		t.Fatal(err)
	}
	other, otherPass := seedMemberWithPass(t, s, 20)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{MemberID: other.ID, PassID: otherPass.ID, Method: "cash", Total: 500_000}); err != nil {
		t.Fatal(err)
	}
	h.reset()

	got, err := s.ListPayments(ctx, memberP(mem.ID), "")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Total != 300_000 {
		t.Fatalf("회원 결제 = %+v, want 본인 1건(300,000)", got)
	}
	if h.callCount("ListPayments") != 0 || h.callCount("ListPaymentsByMember") != 1 {
		t.Errorf("회원 결제 조회: 전량 %d회 / 회원 %d회, want 0 / 1", h.callCount("ListPayments"), h.callCount("ListPaymentsByMember"))
	}
	// owner 무필터는 종전대로 전량.
	h.reset()
	if all, err := s.ListPayments(ctx, ownerP(), ""); err != nil || len(all) != 2 {
		t.Fatalf("owner 전체 = %v, %v, want 2건", all, err)
	}
	if h.callCount("ListPayments") != 1 {
		t.Errorf("owner 전체 조회 전량 %d회, want 1", h.callCount("ListPayments"))
	}
}

// 계약가 상한(CreatePayment)은 **그 패스에 기록된 결제만** 합산한다 — 같은 회원의 다른 패스 결제가
// 섞이면 정상 분할 기록(카드 600,000 + 현금 400,000)이 "계약가 초과"로 거부된다.
func TestPaymentCapCountsOnlyThatPassPayments(t *testing.T) {
	s, h := newHookedService(t)
	ctx := context.Background()
	mem, passA := seedMemberWithPass(t, s, 10) // 계약가 1,000,000
	passB, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: "PT 5회", PaidAmount: 500_000, TotalSessions: 5,
		ValidFrom: passA.ValidFrom, ValidUntil: passA.ValidUntil,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{MemberID: mem.ID, PassID: passB.ID, Method: "cash", Total: 500_000}); err != nil {
		t.Fatal(err)
	}
	h.reset()

	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{MemberID: mem.ID, PassID: passA.ID, Method: "card", Total: 600_000}); err != nil {
		t.Fatalf("A 1차 600,000: %v", err)
	}
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{MemberID: mem.ID, PassID: passA.ID, Method: "cash", Total: 400_000}); err != nil {
		t.Fatalf("A 2차 400,000(합계 = 계약가)이 거부됐다 — 다른 패스(B) 결제 500,000이 상한에 섞였다: %v", err)
	}
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{MemberID: mem.ID, PassID: passA.ID, Method: "cash", Total: 1}); err == nil {
		t.Error("A 합계가 계약가를 넘는 1원이 통과했다 — 상한이 A의 결제를 세지 않는다")
	}
	if n := h.callCount("ListPayments"); n != 0 {
		t.Errorf("계약가 상한이 센터 전체 결제를 %d회 읽었다", n)
	}
}

// 계약서 스탬프의 {{결제방법}}·{{납부일정}}은 **그 계약의 패스 결제만** 쓴다 — 같은 회원의 다른 패스
// 결제가 섞이면 법정 기재 사항(방판법 §30)인 결제방법이 "카드, 현금"으로 틀리게 찍힌다.
func TestContractVarsUseOnlyThatPassPayments(t *testing.T) {
	s, h := newHookedService(t)
	ctx := context.Background()
	withIssuableContractVariants(t)
	seedContractBusiness(t, s)
	seedFacility(t, s, domain.FacilityStatusReported, "제2026-강남-0001호", "서울보증 인허가보증보험, 보장한도 1억원")
	mem, passA := seedMemberWithPass(t, s, 10)
	passB, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: "PT 5회", PaidAmount: 500_000, TotalSessions: 5,
		ValidFrom: passA.ValidFrom, ValidUntil: passA.ValidUntil,
	})
	if err != nil {
		t.Fatal(err)
	}
	recordSplitPayment(t, s, mem.ID, passA.ID) // A: 카드 2회 분할
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{MemberID: mem.ID, PassID: passB.ID, Method: "cash", Total: 500_000}); err != nil {
		t.Fatal(err)
	}
	cs, err := s.ListContracts(ctx, ownerP(), mem.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	var contractA string
	for _, c := range cs {
		if c.PassID == passA.ID {
			contractA = c.ID
		}
	}
	if contractA == "" {
		t.Fatalf("패스 A의 계약이 없다: %+v", cs)
	}
	h.reset()

	resent, err := s.SendContract(ctx, ownerP(), contractA)
	if err != nil {
		t.Fatal(err)
	}
	if got := resent.Vars["결제방법"]; got != "카드" {
		t.Errorf("결제방법 = %q, want \"카드\" — 다른 패스(B, 현금)의 결제가 계약서에 섞였다", got)
	}
	if got, want := resent.Vars["납부일정"], "1회차 600,000원 (2026-09-01 납부완료)\n2회차 400,000원 (2026-10-01 납부예정)"; got != want {
		t.Errorf("납부일정 = %q, want %q", got, want)
	}
	if n := h.callCount("ListPayments"); n != 0 {
		t.Errorf("계약서 조립이 센터 전체 결제를 %d회 읽었다", n)
	}
}

// 탈퇴 보존 집계(retained.payments)는 탈퇴자 결제만 읽는다 — 이웃 회원 결제는 세지도, 읽지도 않는다.
func TestWithdrawalRetainedCountsReadOnlyMemberPayments(t *testing.T) {
	ctx := context.Background()
	s, h := newHookedService(t)
	mem, _ := seedWithdrawableMember(t, s)
	other, otherPass := seedMemberWithPass(t, s, 20)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{MemberID: other.ID, PassID: otherPass.ID, Method: "cash", Total: 300_000}); err != nil {
		t.Fatal(err)
	}
	before, err := s.store.ListPaymentsByMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	h.reset()

	res, err := s.DeleteMyAccount(ctx, memberP(mem.ID))
	if err != nil {
		t.Fatalf("DeleteMyAccount: %v", err)
	}
	if res.Retained.Payments != len(before) {
		t.Errorf("retained.payments = %d, want %d(탈퇴자 본인 것만)", res.Retained.Payments, len(before))
	}
	if n := h.callCount("ListPayments"); n != 0 {
		t.Errorf("탈퇴 처리가 센터 전체 결제를 %d회 읽었다", n)
	}
	if n := h.callCount("ListPaymentsByMember"); n != 1 {
		t.Errorf("ListPaymentsByMember %d회, want 1", n)
	}
}

// scope는 계약대로 me|center만 받는다(P74 반박 D-A — HEAD부터 있던 결함). 종전엔 "me"가 아니면 센터 전체로
// 집계하고 금액을 비우는 조건은 scope=="center"뿐이라, 트레이너가 "all"·"ME"·"center " 같은 값을 보내면
// **센터 매출(monthly·ytd)**이 그대로 나갔다 — 어드민은 me·center만 보내지만 토큰이 있으면 API를 직접 부를 수 있다.
func TestStatsRejectsUnknownScope(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 10) // 담당 t1
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 900_000}); err != nil {
		t.Fatal(err)
	}
	for _, sc := range []string{"all", "ME", "center ", "Center", "owner"} {
		st, err := s.Stats(ctx, trainerP(), "", sc)
		if !errors.Is(err, errBadRequest) {
			t.Errorf("trainer scope=%q: err = %v (ytd=%d) — 계약 밖 scope는 400이어야 한다", sc, err, st.YTD)
		}
	}
	// 계약 안의 값은 종전 그대로: 트레이너 center는 비율만(금액 비움), 빈 값은 me.
	st, err := s.Stats(ctx, trainerP(), "", "center")
	if err != nil || st.YTD != 0 || st.Monthly != nil {
		t.Errorf("trainer center: err=%v ytd=%d monthly=%v, want 금액 비움", err, st.YTD, st.Monthly)
	}
	if _, err := s.Stats(ctx, trainerP(), "", ""); err != nil {
		t.Errorf("빈 scope(=me)가 거부됐다: %v", err)
	}
	if st, err := s.Stats(ctx, ownerP(), "", "center"); err != nil || st.YTD != 900_000 {
		t.Errorf("owner center ytd = %d (%v), want 900,000", st.YTD, err)
	}
}

// 회원별 hwChecks 조회 중 **패닉**(또는 요청 취소)이면 부분 결과를 200으로 내지 않는다(P74 반박 D-B). forEachParallel은
// 패닉을 오류로 바꾸고 나머지를 취소하므로, 그 오류를 버리면 아직 안 읽은 회원이 조용히 분자에서 빠진 완료율이
// 나갔다(회원 40명·첫 회원 패닉 → 7/40). HEAD는 같은 패닉이 recoverJSON을 거쳐 500으로 드러났다.
// 회원 한 명의 **스토어 오류**는 종전대로 그 회원만 빠진다(TestStatsHwReadFailureDropsOnlyThatMember).
func TestStatsHwWorkerPanicFailsRequestNotSilently(t *testing.T) {
	s, h := newHookedService(t)
	ctx := context.Background()
	seedHomeworkPair(t, s)
	h.reset()
	prev := parallelPanicLog
	parallelPanicLog = io.Discard
	defer func() { parallelPanicLog = prev }()
	h.before = func(op string, n int) {
		if op == "ListHwChecksByMember" && n == 1 {
			panic("boom")
		}
	}
	defer func() { h.before = nil }()

	if _, err := s.Stats(ctx, ownerP(), "", "center"); err == nil {
		t.Fatal("회원별 조회 워커가 패닉했는데 통계가 성공으로 나갔다 — 남은 회원이 조용히 빠진 부분 결과다")
	}
}
