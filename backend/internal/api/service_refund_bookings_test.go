package api

import (
	"context"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

// 환불이 예약을 함께 지운다는 사실을 **누르기 전에** 알린다(v2.14).
//
// 종전 어드민 확인 문구는 "원장에 refund 기록이 남고 되돌릴 수 없어요"까지였고,
// 완료 화면도 부수효과 셋 중 둘(미납 청구 종결·미서명 계약 무효)만 적었다 —
// 예약 취소가 빠진 채 목록이 완결돼 보여 누락이 더 위험했다. 서버에 푸시가 없어
// 회원은 앱을 열어야 사라진 걸 안다.

func TestRefundReportsCancelledBookings(t *testing.T) {
	ctx := context.Background()
	s := newTestService()
	mem, pass := seedMemberWithPass(t, s, 20)

	// 미래 확정 예약 2건.
	for _, days := range []int{3, 10} {
		if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
			MemberID: mem.ID, PassID: pass.ID, SlotKey: slotKeyDaysAhead(days, 10),
		}); err != nil {
			t.Fatalf("CreateBooking(+%dd): %v", days, err)
		}
	}
	// **걸러져야 할 예약**을 하나 심는다. 이게 없으면 필터를 통째로 풀어도(= 이 패스의
	// 모든 예약을 세도) 같은 수가 나와 테스트가 아무것도 검증하지 못한다
	// — 실제로 뮤테이션에서 살아남았다.
	extra, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, SlotKey: slotKeyDaysAhead(20, 10),
	})
	if err != nil {
		t.Fatalf("CreateBooking(+20d): %v", err)
	}
	if err := s.CancelBooking(ctx, ownerP(), extra.ID, true); err != nil {
		t.Fatalf("CancelBooking: %v", err)
	}

	t.Run("견적이 취소될 건수를 미리 말한다", func(t *testing.T) {
		q, err := s.RefundQuote(ctx, ownerP(), pass.ID, 0)
		if err != nil {
			t.Fatalf("RefundQuote: %v", err)
		}
		if q.CancelledBookings != 2 {
			t.Fatalf("견적 취소 예정 = %d, want 2 — 누르기 전에 알아야 한다", q.CancelledBookings)
		}
	})

	t.Run("실행 결과가 견적과 같은 수를 돌려준다", func(t *testing.T) {
		// 두 곳이 다른 규칙으로 세면 "2건 취소됩니다"라 예고하고 다른 수를 지운다.
		_, res, err := s.RefundPass(ctx, ownerP(), pass.ID, 0)
		if err != nil {
			t.Fatalf("RefundPass: %v", err)
		}
		if res.CancelledBookings != 2 {
			t.Fatalf("실행 취소 = %d, want 2", res.CancelledBookings)
		}
	})

	t.Run("실제로 취소됐다 — 숫자만 세고 지나가지 않았다", func(t *testing.T) {
		bookings, err := s.store.ListBookingsByMember(ctx, testCenter, mem.ID)
		if err != nil {
			t.Fatalf("ListBookingsByMember: %v", err)
		}
		for _, b := range bookings {
			if b.PassID == pass.ID && b.Status == domain.BookingConfirmed {
				t.Fatalf("환불했는데 확정 예약이 남았다: %s", b.SlotKey)
			}
		}
	})
}

func TestRefundQuoteZeroWhenNoBookings(t *testing.T) {
	// 예약이 없으면 0이어야 한다 — 0인데 "예약이 취소됩니다"라고 겁주면 안 된다.
	ctx := context.Background()
	s := newTestService()
	_, pass := seedMemberWithPass(t, s, 20)

	q, err := s.RefundQuote(ctx, ownerP(), pass.ID, 0)
	if err != nil {
		t.Fatalf("RefundQuote: %v", err)
	}
	if q.CancelledBookings != 0 {
		t.Fatalf("취소 예정 = %d, want 0", q.CancelledBookings)
	}
}
