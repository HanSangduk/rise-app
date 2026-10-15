package api

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// 가드가 **조용히 꺼지지 않는다**(P56).
//
// 종전 패턴은 `if x, err := s.store.GetPass(...); err == nil && <조건> { 거부 }` 였다.
// 스토어가 순단하면 `err != nil`이라 조건 자체가 평가되지 않고 **가드가 통째로 사라진다**.
// 방어가 약해지는 게 아니라 없어지는 것이고, 로그에도 남지 않으며, 이 저장소는 다른 곳에서
// 이미 옳은 형(`else if !errors.Is(err, store.ErrNotFound)`)을 쓰고 있었다.
//
// 여기서 고정하는 것은 "거부 사유가 성립하는지"가 아니라 **"조회가 실패하면 진행하지 않는다"**다.
// 그래서 픽스처는 정상 상태로 두고 조회만 실패시킨다 — 가드가 살아 있으면 5xx로 멈추고,
// 꺼지면 요청이 **성공한다**(그게 회귀의 모양이다).
func TestGuardsDoNotSilentlyOpenOnStoreFailure(t *testing.T) {
	boom := errors.New("store unavailable")

	t.Run("PayInstallment — 납부는 되돌릴 수단이 없다", func(t *testing.T) {
		s, h := newHookedService(t)
		ctx := context.Background()
		owner := ownerP()

		_, pass := seedMemberWithPass(t, s, 10)
		mem, pass := seedMemberWithPass(t, s, 10)
		pay, err := s.CreatePayment(ctx, owner, PaymentCreateRequest{
			MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 1_000_000,
			Installments: []domain.Installment{{Due: "2026-09-30", Amount: 1_000_000}},
		})
		if err != nil {
			t.Fatalf("결제 시드 실패: %v", err)
		}

		h.reset()
		h.fail = func(op string, _ int) error {
			if op == "GetPass" {
				return boom
			}
			return nil
		}
		if _, err := s.PayInstallment(ctx, owner, pay.ID, 0); err == nil {
			t.Fatal("GetPass가 실패했는데 납부가 통과했다 — 환불 차단과 트레이너 스코프가 함께 꺼졌다")
		} else if !errors.Is(err, boom) {
			t.Fatalf("인프라 에러가 그대로 올라와야 한다: %v", err)
		}
	})

	t.Run("JoinApprove — P55 C-2 방어선(회원 기록 전부 상실)", func(t *testing.T) {
		s, h := newHookedService(t)
		ctx := context.Background()
		owner := ownerP()

		jr, err := s.JoinRequestCreate(ctx, Principal{UID: "newbie", Role: domain.RoleMember, CenterID: testCenter}, JoinRequestBody{
			Name: "람", Phone: "010-1234-5678",
		})
		if err != nil {
			t.Fatalf("가입 요청 시드 실패: %v", err)
		}

		h.reset()
		h.fail = func(op string, _ int) error {
			if op == "GetUserIndex" {
				return boom
			}
			return nil
		}
		if _, err := s.JoinApprove(ctx, owner, jr.ID); err == nil {
			t.Fatal("GetUserIndex가 실패했는데 승인이 통과했다 — 좀비 승인 방어선이 꺼졌다")
		} else if !errors.Is(err, boom) && !strings.Contains(err.Error(), "store unavailable") {
			t.Fatalf("인프라 에러가 그대로 올라와야 한다: %v", err)
		}
	})

	// v2.37(P73) — 예약 생성 경로 2곳에 같은 형(`err == nil`)이 남아 있었다. 퇴사자·휴무일 거부는
	// "스태프 레코드가 없는 미시딩 dev"를 통과시키려는 것이지 스토어 장애를 통과시키려는 것이
	// 아니다. 픽스처는 정상(현직 코치)이고 조회만 실패시킨다 — 가드가 살아 있으면 멈추고,
	// 꺼져 있으면 예약이 **성공한다**.
	t.Run("CreateBooking — 퇴사자·휴무일 방어선", func(t *testing.T) {
		s, h := newHookedService(t)
		ctx := context.Background()
		mem, pass := seedMemberWithPass(t, s, 10)

		h.reset()
		h.fail = func(op string, _ int) error {
			if op == "GetStaff" {
				return boom
			}
			return nil
		}
		_, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
			SlotKey: slotKeyDaysAhead(1, 9), MemberID: mem.ID, PassID: pass.ID,
		})
		if err == nil {
			t.Fatal("GetStaff가 실패했는데 예약이 성립했다 — 퇴사자·휴무일 거부가 함께 꺼졌다")
		} else if !errors.Is(err, boom) {
			t.Fatalf("인프라 에러가 그대로 올라와야 한다: %v", err)
		}
		if got := countConfirmedForPass(t, s, mem.ID, pass.ID); got != 0 {
			t.Fatalf("실패한 요청이 예약 %d건을 남겼다", got)
		}
	})

	t.Run("CreateRecurring — 규칙 저장 전 방어선(유령 규칙 없음)", func(t *testing.T) {
		s, h := newHookedService(t)
		ctx := context.Background()
		mem, pass := seedMemberWithPass(t, s, 10)
		until := time.Now().In(domain.KST).AddDate(0, 0, 60).Format("2006-01-02")

		h.reset()
		h.fail = func(op string, _ int) error {
			if op == "GetStaff" {
				return boom
			}
			return nil
		}
		_, err := s.CreateRecurring(ctx, ownerP(), RecurringCreateRequest{
			MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
			Days: []string{"mon", "wed"}, Hour: 19, Until: until,
		})
		if err == nil {
			t.Fatal("GetStaff가 실패했는데 고정 스케줄이 성립했다")
		} else if !errors.Is(err, boom) {
			t.Fatalf("인프라 에러가 그대로 올라와야 한다: %v", err)
		}
		// 방어선은 규칙 저장 **앞**에 있어야 한다 — 뒤면 예약 0건의 유령 규칙이 남는다.
		rules, err := s.store.ListRecurrings(ctx, testCenter)
		if err != nil {
			t.Fatal(err)
		}
		if len(rules) != 0 {
			t.Fatalf("실패한 요청이 규칙 %d건을 남겼다(유령 규칙)", len(rules))
		}
	})
}
