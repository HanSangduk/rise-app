package api

import (
	"context"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// 회원권 상태를 응답에서 오늘 날짜로 확정한다(P25).
//
// 종전에는 저장된 Status가 언제나 "active"였다 — expired·scheduled를 대입하는 코드가
// 프로덕션에 한 줄도 없었다. 앱·어드민은 두 상태의 라벨·필터를 **이미 갖고 있었는데**
// 값이 오지 않아 죽은 분기였고, 만료된 회원권이 영원히 "이용 중"으로 보였다.

func day(offset int) string {
	return time.Now().In(domain.KST).AddDate(0, 0, offset).Format("2006-01-02")
}

// makePassWithPeriod — 기간을 지정해 회원권 하나를 만든다. CreatePass는 기간 검증만 하고
// Status는 무조건 active로 저장하므로, 여기서 만든 건 전부 저장상 active다.
func makePassWithPeriod(t *testing.T, s *Service, from, until string) (*domain.Member, *domain.Pass) {
	t.Helper()
	ctx := context.Background()
	seedTrainerRecord(t, s, "t1", "정혜린")
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "김민지", Phone: "010-1234-5678", TrainerID: "t1", Status: domain.MemberStatusActive,
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatalf("CreateMember: %v", err)
	}
	pass, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: "PT 20회",
		PaidAmount: 1_000_000, TotalSessions: 20,
		ValidFrom: from, ValidUntil: until,
	})
	if err != nil {
		t.Fatalf("CreatePass: %v", err)
	}
	return mem, pass
}

func TestListPassesReportsExpiredAndScheduled(t *testing.T) {
	ctx := context.Background()

	t.Run("유효기간이 지난 회원권은 expired로 내려간다", func(t *testing.T) {
		s := newTestService()
		mem, _ := makePassWithPeriod(t, s, day(-90), day(-1))

		list, err := s.ListPasses(ctx, ownerP(), mem.ID)
		if err != nil {
			t.Fatalf("ListPasses: %v", err)
		}
		if len(list) != 1 {
			t.Fatalf("패스 %d건", len(list))
		}
		if list[0].Status != domain.PassStatusExpired {
			t.Fatalf("status=%s, want expired — 만료된 회원권이 '이용 중'으로 보인다", list[0].Status)
		}
	})

	t.Run("아직 시작 전이면 scheduled로 내려간다", func(t *testing.T) {
		s := newTestService()
		mem, _ := makePassWithPeriod(t, s, day(7), day(97))

		list, err := s.ListPasses(ctx, ownerP(), mem.ID)
		if err != nil {
			t.Fatalf("ListPasses: %v", err)
		}
		if list[0].Status != domain.PassStatusScheduled {
			t.Fatalf("status=%s, want scheduled", list[0].Status)
		}
	})

	t.Run("발급 응답도 목록과 같은 값이다", func(t *testing.T) {
		// 갈리면 방금 만든 화면에서는 "이용 중", 새로고침하면 "예정"으로 보인다.
		s := newTestService()
		_, pass := makePassWithPeriod(t, s, day(7), day(97))
		if pass.Status != domain.PassStatusScheduled {
			t.Fatalf("CreatePass 응답 status=%s, want scheduled", pass.Status)
		}
	})
}

// 파생 상태는 **저장을 건드리지 않는다**. 저장으로 새어 들어가면 홀딩이 유효기간을
// 늘렸을 때 굳어버린 expired가 되살아나지 않는다.
func TestEffectiveStatusDoesNotPersist(t *testing.T) {
	ctx := context.Background()
	s := newTestService()
	mem, pass := makePassWithPeriod(t, s, day(-90), day(-1))

	if _, err := s.ListPasses(ctx, ownerP(), mem.ID); err != nil {
		t.Fatalf("ListPasses: %v", err)
	}

	stored, err := s.store.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatalf("GetPass: %v", err)
	}
	if stored.Status != domain.PassStatusActive {
		t.Fatalf("저장된 status가 %s로 바뀌었다 — 응답 사본에만 찍어야 한다", stored.Status)
	}
}

// 환불은 저장된 종단 상태 — 날짜로 되살아나면 안 된다.
func TestRefundedPassStaysRefundedInResponse(t *testing.T) {
	ctx := context.Background()
	s := newTestService()
	mem, pass := makePassWithPeriod(t, s, day(-1), day(90)) // 기간은 아직 유효
	if _, _, err := s.RefundPass(ctx, ownerP(), pass.ID, 0); err != nil {
		t.Fatalf("RefundPass: %v", err)
	}

	list, err := s.ListPasses(ctx, ownerP(), mem.ID)
	if err != nil {
		t.Fatalf("ListPasses: %v", err)
	}
	if list[0].Status != domain.PassStatusRefunded {
		t.Fatalf("status=%s — 환불한 회원권이 기간이 남았다고 되살아났다", list[0].Status)
	}
}

// 예약 게이트는 scheduled를 통과시키고 expired를 막는다.
//
// 게이트가 종전엔 `Status != active`였는데 바로 아래 주석은 "valid_from이 미래인 재등록
// 패스도 선예약 허용"이라 서로 모순이었다 — 저장된 Status가 늘 active라 드러나지 않았다.
func TestBookingGateAllowsScheduledRejectsExpired(t *testing.T) {
	ctx := context.Background()

	t.Run("시작 전 회원권도 유효기간 안 슬롯이면 선예약된다", func(t *testing.T) {
		s := newTestService()
		mem, pass := makePassWithPeriod(t, s, day(7), day(97))
		bk, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
			MemberID: mem.ID, PassID: pass.ID, SlotKey: slotKeyDaysAhead(10, 10),
		})
		if err != nil {
			t.Fatalf("선예약이 거부됨: %v", err)
		}
		if bk == nil {
			t.Fatal("예약이 nil")
		}
	})

	t.Run("만료된 회원권으로는 예약할 수 없다", func(t *testing.T) {
		s := newTestService()
		mem, pass := makePassWithPeriod(t, s, day(-90), day(-1))
		_, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
			MemberID: mem.ID, PassID: pass.ID, SlotKey: slotKeyDaysAhead(3, 10),
		})
		if err == nil {
			t.Fatal("만료된 회원권으로 예약이 잡혔다")
		}
	})
}
