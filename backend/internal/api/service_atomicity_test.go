package api

// 저장 계층 원자성 회귀 테스트(P13). 감사가 Firestore 에뮬레이터로 실측한 결함을 인메모리에서
// **결정적으로** 재현한다 — hookstore_test.go의 데코레이터가 창을 직접 열기 때문이다.
//
// 두 가지 축으로 본다.
//
//	① 찢어진 쓰기 스윕 — 스토어 메서드를 하나씩 실패시키면서 "전부 반영 또는 전무" 불변식을
//	   확인한다. 특정 순서를 하드코딩하지 않고 **모든 지점**을 훑기 때문에, 누군가 원자적 동사를
//	   다시 두 호출로 쪼개는 순간 그 지점에서 걸린다(뮤테이션 감지 장치).
//	② 결정적 경합 — 첫 쓰기 직전에 한 고루틴을 붙잡아 두고 상대를 통째로 실행한 뒤 놓아준다.
//	   스케줄러 운에 기대지 않아 -race와 무관하게 매번 같은 순서로 재현된다.

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// errInjected — 주입 실패(Firestore 타임아웃·권한 오류·네트워크 단절의 대역).
var errInjected = errors.New("injected store failure")

// ---- C3: 발급 3단(패스·원장 issue·계약)이 전부 반영되거나 전무여야 한다 ----
//
// 실측된 사고: 계약 자동생성만 실패하는 상황에서 발급 3회 시도가 HTTP 500 × 3을 돌려주면서
// 실제로는 패스 3개(각 20회) + 원장 issue 3건 = 60회를 지급했다. 대표 화면은 "실패"인데
// 회원 앱엔 회원권이 세 장 생긴다.
func TestIssuePassIsAllOrNothing(t *testing.T) {
	ctx := context.Background()
	for _, op := range hookedOps {
		t.Run(op, func(t *testing.T) {
			s, h := newHookedService(t)
			seedTrainerRecord(t, s, "t1", "정혜린")
			mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
				Name: "김민지", Phone: "010-1234-5678", TrainerID: "t1", Status: domain.MemberStatusActive,
			})
			if err != nil {
				t.Fatal(err)
			}
			h.reset()
			h.fail = failFirst(op, errInjected)

			req := PassCreateRequest{
				MemberID: mem.ID, TrainerID: "t1", Product: "PT 20회",
				PaidAmount: 1_000_000, TotalSessions: 20,
				ValidFrom: today(), ValidUntil: "2027-12-31",
			}
			// 감사가 실측한 사용자 행동: 500을 보고 다시 누른다.
			for range 3 {
				_, _ = s.CreatePass(ctx, ownerP(), req)
			}
			h.fail = nil

			passes, issues, contracts := issuedCounts(t, h, mem.ID)
			if !(passes == issues && issues == contracts) {
				t.Fatalf("%s 실패 주입 후 패스 %d / 원장issue %d / 계약 %d — 발급 3단이 찢어졌다",
					op, passes, issues, contracts)
			}
			if passes > 3 {
				t.Fatalf("%s: 패스 %d건(시도 3회) — 재시도가 중복 지급을 만들었다", op, passes)
			}
		})
	}
}

// issuedCounts — 훅을 우회해(내부 스토어 직접) 발급 3종의 실제 건수를 센다.
func issuedCounts(t *testing.T, h *hookStore, memberID string) (passes, issues, contracts int) {
	t.Helper()
	ctx := context.Background()
	ps, err := h.Store.ListPassesByMember(ctx, testCenter, memberID)
	if err != nil {
		t.Fatal(err)
	}
	entries, err := h.Store.ListLedger(ctx, testCenter, memberID, "")
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if e.Reason == domain.ReasonIssue {
			issues++
		}
	}
	cs, err := h.Store.ListContracts(ctx, testCenter, memberID, "")
	if err != nil {
		t.Fatal(err)
	}
	return len(ps), issues, len(cs)
}

// ---- C2: 환불 마감(원장 refund + status=refunded)이 찢어지지 않아야 한다 ----
//
// 실측된 사고: UpdatePass만 실패 → 500 응답 + 원장엔 refund 1건 + 패스는 active/remaining=0.
// 회원 앱에는 "유효기간 남음 · 잔여 0회"인 살아 있는 회원권으로 보이고(환불 표시 없음),
// 새 예약은 400, 담당 코치는 퇴사 선행 조건에 걸려 409 — 되돌리는 라우트가 없어 영구 고착된다.
func TestRefundIsAllOrNothing(t *testing.T) {
	ctx := context.Background()
	for _, op := range hookedOps {
		t.Run(op, func(t *testing.T) {
			s, h := newHookedService(t)
			mem, pass := seedMemberWithPass(t, s, 10)
			h.reset()
			h.fail = failFirst(op, errInjected)

			// 대표는 실패를 보면 다시 누른다 — 재시도가 원장을 음수로 끌어내리면 안 된다.
			for range 2 {
				_, _, _ = s.RefundPass(ctx, ownerP(), pass.ID, 0)
			}
			h.fail = nil

			saved, err := h.Store.GetPass(ctx, testCenter, pass.ID)
			if err != nil {
				t.Fatal(err)
			}
			entries, err := h.Store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
			if err != nil {
				t.Fatal(err)
			}
			refunds := 0
			for _, e := range entries {
				if e.Reason == domain.ReasonRefund {
					refunds++
				}
			}
			refunded := saved.Status == domain.PassStatusRefunded
			if refunded != (refunds == 1) {
				t.Fatalf("%s 실패 주입 후 status=%s인데 refund 원장 %d건 — 패스와 원장이 서로 다른 말을 한다",
					op, saved.Status, refunds)
			}
			if refunds > 1 {
				t.Fatalf("%s: refund 원장 %d건 — 재시도가 이중 마감했다", op, refunds)
			}
			if sum := domain.Sum(entries); sum < 0 {
				t.Fatalf("%s: 원장 합 %d — 음수(이중 차감)", op, sum)
			}
			if refunded && saved.Remaining != 0 {
				t.Fatalf("%s: refunded인데 remaining=%d", op, saved.Remaining)
			}
			// v2.15(P37): 미서명 계약 무효화가 마감과 **한 트랜잭션**이다 — 마감됐으면 sent
			// 계약도 반드시 voided, 마감 전이면 계약은 그대로 sent여야 한다. 찢어지면 refunded
			// 패스에 sent 계약이 잔존하거나(옛 루프의 중간 실패), 마감 없이 계약만 죽는다.
			cs, err := h.Store.ListContracts(ctx, testCenter, mem.ID, "")
			if err != nil {
				t.Fatal(err)
			}
			for _, c := range cs {
				if c.PassID != pass.ID {
					continue
				}
				wantStatus := domain.ContractStatusSent
				if refunded {
					wantStatus = domain.ContractStatusVoided
				}
				if c.Status != wantStatus {
					t.Fatalf("%s 실패 주입 후 패스=%s인데 계약=%s — 마감과 무효화가 찢어졌다",
						op, saved.Status, c.Status)
				}
			}
		})
	}
}

// ---- M4: 컷오프 내 취소의 페널티가 취소와 함께 반영되거나 둘 다 안 돼야 한다 ----
//
// 실측된 사고: 원장 적재만 실패 → 취소 500인데 예약은 이미 cancelled 확정, 페널티 원장 없음.
// 재시도는 "confirmed 상태의 예약만 취소할 수 있어요"(400)로 막혀 **페널티가 영구 소실**된다.
// complete/noshow는 처음부터 한 트랜잭션이었는데 취소만 두 호출로 쪼개져 있었다.
func TestCancelPenaltyIsAllOrNothing(t *testing.T) {
	ctx := context.Background()
	for _, op := range hookedOps {
		t.Run(op, func(t *testing.T) {
			s, h := newHookedService(t)
			mem, pass := seedMemberWithPass(t, s, 10)
			// 컷오프를 넉넉히 잡아 내일 수업이 "컷오프 이내"가 되게 한다(페널티 경로 진입).
			policy := domain.DefaultPolicy()
			policy.CancelCutoffHours = 168
			if err := h.Store.SavePolicy(ctx, testCenter, &policy); err != nil {
				t.Fatal(err)
			}
			b, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
				SlotKey: slotKeyDaysAhead(1, 15), MemberID: mem.ID, PassID: pass.ID,
			})
			if err != nil {
				t.Fatal(err)
			}
			h.reset()
			h.fail = failFirst(op, errInjected)

			for range 2 { // 실패 → 재시도
				_ = s.CancelBooking(ctx, ownerP(), b.ID, false)
			}
			h.fail = nil

			saved, err := h.Store.GetBooking(ctx, testCenter, b.ID)
			if err != nil {
				t.Fatal(err)
			}
			entries, err := h.Store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
			if err != nil {
				t.Fatal(err)
			}
			penalties := 0
			for _, e := range entries {
				if e.Reason == domain.ReasonNoshow || e.Reason == domain.ReasonNoshowWaive {
					penalties++
				}
			}
			cancelled := saved.Status == domain.BookingCancelled
			if cancelled != (penalties == 1) {
				t.Fatalf("%s 실패 주입 후 예약=%s인데 페널티 원장 %d건 — 취소와 페널티가 찢어졌다",
					op, saved.Status, penalties)
			}
			if penalties > 1 {
				t.Fatalf("%s: 페널티 원장 %d건 — 재시도가 이중 차감했다", op, penalties)
			}
		})
	}
}

// ---- C1: 동시 환불 2건이 모두 성공하면 안 된다(환불금 2배 지급) ----
//
// 실측: 스토어 호출당 25ms 지연 주입 + 동시 환불 2건 → HTTP [200, 200], 환불 승인액 495,000원이
// 두 번, 원장 합 −10. 대표가 반응 없는 버튼을 한 번 더 누른 것만으로 벌어진다.
//
// 서비스 레이어의 "원장 마감 직전 GetPass 재확인"은 트랜잭션 밖이라 원리적으로 이 창을 못 닫는다.
// 이 테스트가 잡는 것이 정확히 그 지점이다 — 첫 쓰기 직전에 창을 열어 두고 상대를 통째로 태운다.
func TestConcurrentRefundPaysOnce(t *testing.T) {
	ctx := context.Background()
	s, h := newHookedService(t)
	mem, pass := seedMemberWithPass(t, s, 10)
	h.reset()

	reached, release := make(chan struct{}), make(chan struct{})
	h.before = latchOnFirstWrite(reached, release)

	type result struct {
		quote domain.RefundResult
		err   error
	}
	first := make(chan result, 1)
	go func() {
		_, q, err := s.RefundPass(ctx, ownerP(), pass.ID, 0)
		first <- result{q, err}
	}()

	<-reached // 1번 환불이 "마감 직전"에 멈춰 있다 — 여기가 실측된 창이다
	_, quote2, err2 := s.RefundPass(ctx, ownerP(), pass.ID, 0)
	close(release)
	r1 := <-first
	h.before = nil

	okCount := 0
	for _, err := range []error{r1.err, err2} {
		if err == nil {
			okCount++
			continue
		}
		if !errors.Is(err, errBadRequest) {
			t.Fatalf("실패한 환불의 에러 = %v, want errBadRequest(이미 환불 처리된 패스)", err)
		}
		if !strings.Contains(err.Error(), "이미 환불") {
			t.Errorf("에러 문구가 이유를 설명하지 않는다: %v", err)
		}
	}
	if okCount != 1 {
		t.Fatalf("성공한 환불 = %d건(승인액 %d원 / %d원) — 환불금이 두 번 지급된다",
			okCount, r1.quote.Refund, quote2.Refund)
	}

	entries, err := h.Store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	refunds := 0
	for _, e := range entries {
		if e.Reason == domain.ReasonRefund {
			refunds++
		}
	}
	if refunds != 1 {
		t.Errorf("refund 원장 = %d건, want 1", refunds)
	}
	if sum := domain.Sum(entries); sum != 0 {
		t.Errorf("원장 합 = %d, want 0(음수면 이중 환불)", sum)
	}
	saved, err := h.Store.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.PassStatusRefunded || saved.Remaining != 0 {
		t.Errorf("환불 후 패스 = %s/remaining %d, want refunded/0", saved.Status, saved.Remaining)
	}
}

// ---- H2: 같은 패스에 동시 홀딩 2건 — 둘 다 남아야 한다 ----
//
// 실측: 겹치지 않는 5일 홀딩 5건 동시 → HTTP 200 × 5인데 저장된 holds는 1건, 유효기간은 5일만
// 연장, 원장 hold 이벤트는 5건. "원장이 진실"이라는 설계 약속이 오히려 **양쪽 말이 다 맞는**
// 상태를 만든다 — 원장을 세면 5회, 패스를 보면 1회.
func TestConcurrentHoldsBothLand(t *testing.T) {
	ctx := context.Background()
	s, h := newHookedService(t)
	mem, pass := seedMemberWithPass(t, s, 10)
	before, err := h.Store.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	h.reset()

	reached, release := make(chan struct{}), make(chan struct{})
	h.before = latchOnFirstWrite(reached, release)

	kst := time.Now().In(domain.KST)
	holdA := HoldRequest{From: kst.AddDate(0, 0, 3).Format("2006-01-02"), To: kst.AddDate(0, 0, 7).Format("2006-01-02"), Reason: "출장"}
	holdB := HoldRequest{From: kst.AddDate(0, 0, 20).Format("2006-01-02"), To: kst.AddDate(0, 0, 24).Format("2006-01-02"), Reason: "부상"}

	done := make(chan error, 1)
	go func() {
		_, err := s.HoldPass(ctx, ownerP(), pass.ID, holdA)
		done <- err
	}()
	<-reached
	if _, err := s.HoldPass(ctx, ownerP(), pass.ID, holdB); err != nil {
		t.Fatalf("두 번째 홀딩: %v", err)
	}
	close(release)
	if err := <-done; err != nil {
		t.Fatalf("첫 번째 홀딩: %v", err)
	}
	h.before = nil

	saved, err := h.Store.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(saved.Holds) != 2 {
		t.Fatalf("저장 holds = %d건(%+v), want 2 — 동시 갱신이 서로를 조용히 덮었다", len(saved.Holds), saved.Holds)
	}
	// 유효기간도 두 구간(5일 + 5일)만큼 늘어야 한다 — holds만 맞고 날짜가 한 번만 늘면 반쪽이다.
	wantUntil := mustAddDays(t, before.ValidUntil, 10)
	if saved.ValidUntil != wantUntil {
		t.Errorf("valid_until = %s, want %s(5일 + 5일 연장)", saved.ValidUntil, wantUntil)
	}
	entries, err := h.Store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	holdEntries := 0
	for _, e := range entries {
		if e.Reason == domain.ReasonHold {
			holdEntries++
		}
	}
	if holdEntries != len(saved.Holds) {
		t.Errorf("원장 hold %d건 ≠ 패스 holds %d건 — 원장과 문서가 서로 다른 말을 한다",
			holdEntries, len(saved.Holds))
	}
}

// ---- H3: 완전히 같은 구간의 홀딩 재신청은 유효기간을 또 늘리면 안 된다 ----
//
// 실측: 스태프는 ValidateHoldWindow(겹침 금지)를 건너뛰므로 동일 from/to로 3회 순차 호출이
// 전부 200이고 유효기간이 3번 늘어났다. 재시도(원장 적재 실패 후 다시 누르기)와 구분되지 않는다.
func TestDuplicateHoldIsRejected(t *testing.T) {
	ctx := context.Background()
	s := newTestService()
	_, pass := seedMemberWithPass(t, s, 10)
	before, err := s.store.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	kst := time.Now().In(domain.KST)
	req := HoldRequest{
		From: kst.AddDate(0, 0, 3).Format("2006-01-02"),
		To:   kst.AddDate(0, 0, 7).Format("2006-01-02"), Reason: "출장",
	}
	if _, err := s.HoldPass(ctx, ownerP(), pass.ID, req); err != nil {
		t.Fatalf("첫 홀딩: %v", err)
	}
	for i := range 2 {
		_, err := s.HoldPass(ctx, ownerP(), pass.ID, req)
		if !errors.Is(err, errBadRequest) {
			t.Fatalf("%d번째 동일 구간 재신청 = %v, want 400(중복)", i+2, err)
		}
	}
	saved, err := s.store.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(saved.Holds) != 1 {
		t.Errorf("holds = %d건, want 1", len(saved.Holds))
	}
	if want := mustAddDays(t, before.ValidUntil, 5); saved.ValidUntil != want {
		t.Errorf("valid_until = %s, want %s — 재신청이 유효기간을 공짜로 늘렸다", saved.ValidUntil, want)
	}
}

// ---- H1: 잔여를 넘는 예약은 만들 수 없다 ----
//
// 실측: 잔여 2회 패스에 순차 4건 예약이 전부 성공 → 4건 완료 → remaining = −2.
// 잔여는 완료 시점에 차감되므로(P4) 예약이 늘어도 줄지 않는다 — confirmed 하나하나가 잔여에
// 대한 청구권이라는 뺄셈이 일반 예약 경로에만 빠져 있었다(고정 스케줄엔 이미 있었다).
func TestBookingCannotExceedRemaining(t *testing.T) {
	ctx := context.Background()
	s := newTestService()
	mem, pass := seedMemberWithPass(t, s, 2)

	ids := []string{}
	for i := range 2 {
		b, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
			SlotKey: slotKeyDaysAhead(i+1, 10), MemberID: mem.ID, PassID: pass.ID,
		})
		if err != nil {
			t.Fatalf("%d번째 예약 실패: %v", i+1, err)
		}
		ids = append(ids, b.ID)
	}
	_, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(3, 10), MemberID: mem.ID, PassID: pass.ID,
	})
	if !errors.Is(err, errBadRequest) {
		t.Fatalf("잔여 2회에 3번째 예약 = %v, want 400", err)
	}
	if !strings.Contains(err.Error(), "이미 잡힌 예약") {
		t.Errorf("거부 사유가 설명되지 않는다: %v", err)
	}

	// 스토어 경계도 같은 답을 내야 한다 — 서비스 가드만 있으면 동시 요청이 나란히 통과한다.
	direct := &domain.Booking{SlotKey: slotKeyDaysAhead(4, 10), MemberID: mem.ID, TrainerID: "t1",
		PassID: pass.ID, Kind: domain.BookingKindPT, Status: domain.BookingConfirmed}
	if err := s.store.BookAtomic(ctx, testCenter, direct.SlotKey, 3, direct); !errors.Is(err, domain.ErrNoSessionsLeft) {
		t.Fatalf("BookAtomic 직접 호출 = %v, want ErrNoSessionsLeft", err)
	}

	// 잡힌 2건을 완료해도 원장이 음수로 내려가지 않는다.
	for _, id := range ids {
		if _, err := s.CompleteBooking(ctx, ownerP(), id); err != nil {
			t.Fatalf("완료 처리: %v", err)
		}
	}
	entries, err := s.store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if sum := domain.Sum(entries); sum != 0 {
		t.Errorf("원장 합 = %d, want 0(음수면 초과 예약이 통과한 것)", sum)
	}
}

// ---- 취소 페널티가 정상 경로에서 실제로 붙는지(위 스윕의 전제) ----
func TestLateCancelRecordsPenaltyAtomically(t *testing.T) {
	ctx := context.Background()
	s := newTestService()
	mem, pass := seedMemberWithPass(t, s, 10)
	policy := domain.DefaultPolicy()
	policy.CancelCutoffHours = 168
	policy.GraceOnce = false // 유예를 끄고 실제 차감(-1)이 붙는지 본다
	if err := s.store.SavePolicy(ctx, testCenter, &policy); err != nil {
		t.Fatal(err)
	}
	b, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 15), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CancelBooking(ctx, ownerP(), b.ID, false); err != nil {
		t.Fatalf("CancelBooking: %v", err)
	}
	entries, err := s.store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if sum := domain.Sum(entries); sum != 9 {
		t.Errorf("원장 합 = %d, want 9(발급 10 − 컷오프 내 취소 1)", sum)
	}
	// 재취소는 상태 충돌 — 페널티가 두 번 붙지 않는다.
	if err := s.CancelBooking(ctx, ownerP(), b.ID, false); !errors.Is(err, errBadRequest) {
		t.Errorf("재취소 = %v, want 400", err)
	}
}

// ---- 스태프 이관도 원장과 담당 변경이 함께 움직인다 ----
func TestTransferPassKeepsLedgerAndOwnerTogether(t *testing.T) {
	ctx := context.Background()
	for _, op := range []string{"UpdatePassWithLedger", "AppendLedger", "UpdatePass", "SaveMember"} {
		t.Run(op, func(t *testing.T) {
			s, h := newHookedService(t)
			mem, pass := seedMemberWithPass(t, s, 10)
			seedTrainerRecord(t, s, "t2", "박서준")
			h.reset()
			h.fail = failFirst(op, errInjected)
			_, _ = s.TransferStaff(ctx, ownerP(), "t1", strptr("t2"))
			h.fail = nil

			saved, err := h.Store.GetPass(ctx, testCenter, pass.ID)
			if err != nil {
				t.Fatal(err)
			}
			entries, err := h.Store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
			if err != nil {
				t.Fatal(err)
			}
			transfers := 0
			for _, e := range entries {
				if e.Reason == domain.ReasonTransfer {
					transfers++
				}
			}
			moved := saved.TrainerID == "t2"
			if moved != (transfers == 1) {
				t.Fatalf("%s 실패 주입 후 담당=%s인데 transfer 원장 %d건 — 이관 기록과 실제 담당이 어긋났다",
					op, saved.TrainerID, transfers)
			}
		})
	}
}

func strptr(s string) *string { return &s }

// mustAddDays — "YYYY-MM-DD"에 일수를 더한다(기대값 계산용).
func mustAddDays(t *testing.T, date string, days int) string {
	t.Helper()
	d, err := time.Parse("2006-01-02", date)
	if err != nil {
		t.Fatalf("날짜 파싱 %q: %v", date, err)
	}
	return d.AddDate(0, 0, days).Format("2006-01-02")
}

// 컴파일 시점 확인: hookStore가 Store 전체를 만족한다(임베딩 덕에 자동이지만 명시해 둔다 —
// 인터페이스에 메서드가 추가되면 여기서 먼저 깨진다).
var _ store.Store = (*hookStore)(nil)
