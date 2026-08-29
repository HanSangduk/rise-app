package api

// 고정 스케줄(P47) · Home Work 스케줄 판정(P39) 회귀 테스트 — P12 감사에서 실측 재현된
// 결함들(고정 스케줄 잔여 캡 무력화 / 규칙 삭제 시 예약 잔존 / 과거 until 유령 규칙 /
// HwSchedule 미판정)을 고정한다.

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

var allWeekdays = []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}

// weekdayWire — time.Weekday → 계약 요일 문자열("mon".."sun").
func weekdayWire(t time.Time) string {
	return []string{"sun", "mon", "tue", "wed", "thu", "fri", "sat"}[int(t.Weekday())]
}

// countConfirmedForPass — 이 패스로 살아있는(confirmed) 예약 수.
func countConfirmedForPass(t *testing.T, s *Service, memberID, passID string) int {
	t.Helper()
	bookings, err := s.store.ListBookingsByMember(context.Background(), testCenter, memberID)
	if err != nil {
		t.Fatalf("ListBookingsByMember: %v", err)
	}
	n := 0
	for _, b := range bookings {
		if b.PassID == passID && b.Status == domain.BookingConfirmed {
			n++
		}
	}
	return n
}

// H4 회귀: 잔여 캡이 "이 호출에서 만든 건수"가 아니라 "이 패스의 살아있는 예약 총량" 기준이어야
// 한다. 규칙을 두 번 만들면 캡이 통째로 무력화돼(잔여 10 → confirmed 20) 슬롯 정원과 코치
// 일정이 실제 팔린 세션의 2배로 잠기고, 완료 처리 시 원장이 음수로 내려간다.
func TestRecurringCapCountsExistingConfirmedBookings(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 10)
	until := time.Now().In(domain.KST).AddDate(0, 0, 60).Format("2006-01-02")

	if _, err := s.CreateRecurring(ctx, trainerP(), RecurringCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
		Days: allWeekdays, Hour: 19, Until: until,
	}); err != nil {
		t.Fatalf("첫 규칙: %v", err)
	}
	if got := countConfirmedForPass(t, s, mem.ID, pass.ID); got != 10 {
		t.Fatalf("첫 규칙 후 confirmed = %d, want 10(잔여 캡)", got)
	}

	// 두 번째 규칙 — 잔여는 완료 시점에 차감되므로(P4) 여전히 10이다. 캡이 이 호출의 생성
	// 건수만 세면 여기서 10건이 더 생긴다.
	_, err := s.CreateRecurring(ctx, trainerP(), RecurringCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
		Days: allWeekdays, Hour: 18, Until: until,
	})
	if !errors.Is(err, errBadRequest) {
		t.Errorf("잔여를 이미 채운 상태의 두 번째 규칙 err = %v, want 400", err)
	}
	if got := countConfirmedForPass(t, s, mem.ID, pass.ID); got > 10 {
		t.Errorf("confirmed = %d, want <= 10(잔여) — 고정 스케줄이 예약 규칙의 우회로가 됐다", got)
	}
}

// H4 회귀(부분 캡): 수동 예약이 이미 잔여 일부를 점유하고 있으면 고정 스케줄은 그 나머지만
// 채워야 한다.
func TestRecurringCapLeavesRoomForExistingBookings(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 4)

	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 7), MemberID: mem.ID, PassID: pass.ID,
	}); err != nil {
		t.Fatalf("수동 예약: %v", err)
	}
	if _, err := s.CreateRecurring(ctx, trainerP(), RecurringCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
		Days: allWeekdays, Hour: 20,
		Until: time.Now().In(domain.KST).AddDate(0, 0, 60).Format("2006-01-02"),
	}); err != nil {
		t.Fatalf("CreateRecurring: %v", err)
	}
	if got := countConfirmedForPass(t, s, mem.ID, pass.ID); got != 4 {
		t.Errorf("confirmed = %d, want 4(수동1 + 고정3 = 잔여4)", got)
	}
}

// M2 회귀: until이 이미 지난 규칙은 예약을 한 건도 만들지 못하면서 목록에서도 숨겨져(v1.5)
// UI로 지울 수 없는 유령 문서가 된다 — 생성 자체를 막는다.
func TestRecurringRejectsPastUntil(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 10)

	_, err := s.CreateRecurring(ctx, trainerP(), RecurringCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
		Days: allWeekdays, Hour: 19, Until: "2020-01-01",
	})
	if !errors.Is(err, errBadRequest) {
		t.Fatalf("과거 until err = %v, want 400", err)
	}
	all, err := s.store.ListRecurrings(ctx, testCenter)
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 0 {
		t.Errorf("거부된 요청이 규칙 %d건을 남겼다(유령 규칙): %+v", len(all), all)
	}
}

// M1 회귀: 규칙 삭제는 그 규칙이 만든 **미래** 예약을 함께 정리해야 한다. 남겨두면 대표는
// "해제"를 눌렀는데 회원 앱엔 4주치가 그대로 뜨고, 수동 취소는 컷오프 24h 이내일 때 회원의
// 노쇼 유예를 소진한다.
func TestDeleteRecurringCancelsFutureBookings(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 5)

	r, err := s.CreateRecurring(ctx, trainerP(), RecurringCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
		Days: allWeekdays, Hour: 11,
		Until: time.Now().In(domain.KST).AddDate(0, 0, 60).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatal(err)
	}
	before := countConfirmedForPass(t, s, mem.ID, pass.ID)
	if before == 0 {
		t.Fatal("선행 예약이 생성되지 않아 삭제 시나리오를 검증할 수 없음")
	}

	res, err := s.DeleteRecurring(ctx, ownerP(), r.ID, false)
	if err != nil {
		t.Fatalf("DeleteRecurring: %v", err)
	}
	if res.Cancelled != before {
		t.Errorf("cancelled = %d, want %d", res.Cancelled, before)
	}
	if got := countConfirmedForPass(t, s, mem.ID, pass.ID); got != 0 {
		t.Errorf("규칙 삭제 후에도 confirmed 예약 %d건 잔존", got)
	}
	// 유예 소진 금지 — 운영 사유 정리이므로 노쇼 원장이 붙으면 안 된다(waive와 같은 취급).
	ledger, err := s.store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range ledger {
		if e.Reason == domain.ReasonNoshow || e.Reason == domain.ReasonNoshowWaive {
			t.Errorf("규칙 삭제가 노쇼 원장을 남겼다: %+v", e)
		}
	}
}

// M1: 이미 지난 회차와 keep_bookings=true 요청은 건드리지 않는다(이력 보존 · 해제 후 잔여
// 회차를 그대로 쓰려는 운영 케이스).
func TestDeleteRecurringKeepsPastAndOptOut(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	// 회차 8 + 주1회 규칙 = 선행 생성이 잔여를 다 먹지 않는다. 여유가 필요한 이유(P13 H1):
	// BookAtomic이 트랜잭션 안에서 "잔여 − 이미 잡힌 confirmed"를 재판정하므로, 잔여를 꽉 채운
	// 상태에서는 **스토어에 직접 심는 픽스처도** 더 이상 만들 수 없다(그게 정확히 막으려던 상태다).
	mem, pass := seedMemberWithPass(t, s, 8)

	r, err := s.CreateRecurring(ctx, trainerP(), RecurringCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
		Days: []string{"mon"}, Hour: 11,
		Until: time.Now().In(domain.KST).AddDate(0, 0, 60).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatal(err)
	}
	// 지난 회차 1건을 규칙 소속으로 심는다(정상 경로로는 만들 수 없다 — 스토어에 직접).
	past := &domain.Booking{
		SlotKey: slotKeyDaysAhead(-3, 11), MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
		Kind: domain.BookingKindPT, Status: domain.BookingConfirmed, RecurringID: r.ID,
	}
	if err := s.store.BookAtomic(ctx, testCenter, past.SlotKey, 3, past); err != nil {
		t.Fatal(err)
	}

	res, err := s.DeleteRecurring(ctx, ownerP(), r.ID, true)
	if err != nil {
		t.Fatal(err)
	}
	if res.Cancelled != 0 {
		t.Errorf("keep_bookings=true인데 %d건 취소됨", res.Cancelled)
	}
	if got := countConfirmedForPass(t, s, mem.ID, pass.ID); got == 0 {
		t.Error("keep_bookings=true인데 예약이 사라졌다")
	}
	b, err := s.store.GetBooking(ctx, testCenter, past.ID)
	if err != nil {
		t.Fatal(err)
	}
	if b.Status != domain.BookingConfirmed {
		t.Errorf("지난 회차 status = %s, want confirmed(이력 보존)", b.Status)
	}
}

// M2: 만료된 규칙도 include_expired=true면 조회할 수 있어야 한다 — 숨기기만 하면 UI가
// 지울 방법이 없다.
func TestListRecurringsIncludeExpired(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 5)

	// 자연 만료 규칙(생성 검증을 통과한 뒤 시간이 지난 상태)을 스토어에 직접 심는다.
	id, err := s.store.CreateRecurring(ctx, testCenter, &domain.Recurring{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
		Days: []string{"mon"}, Hour: 19, Until: "2020-01-01",
	})
	if err != nil {
		t.Fatal(err)
	}
	if list, err := s.ListRecurrings(ctx, ownerP(), false); err != nil || len(list) != 0 {
		t.Errorf("기본 목록에 만료 규칙 노출: %v %v", list, err)
	}
	list, err := s.ListRecurrings(ctx, ownerP(), true)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != id {
		t.Errorf("include_expired 목록 = %+v, want 만료 규칙 1건", list)
	}
}

// M4 회귀: 오늘이 대상 요일이 아니면 "오늘의 운동"에 뜨면 안 된다(days:[mon,wed,fri]가 매일
// 떴다) + to가 지난 배정은 사라져야 한다(once가 영구히 남았다).
func TestListHomeworksFiltersBySchedule(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 5)
	kst := time.Now().In(domain.KST)
	todayStr := kst.Format("2006-01-02")

	mk := func(sc domain.HwSchedule) string {
		t.Helper()
		hw, err := s.CreateHomework(ctx, ownerP(), HomeworkCreateRequest{
			TrainerID: "t1", Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{mem.ID},
			Items: []domain.HwItem{{Name: "스쿼트", Sets: 3, Reps: "15"}}, Schedule: sc,
		})
		if err != nil {
			t.Fatal(err)
		}
		return hw.ID
	}
	// ① 내일 요일만 반복 → 오늘은 안 뜬다.
	mk(domain.HwSchedule{Type: "weekly", Days: []string{weekdayWire(kst.AddDate(0, 0, 1))},
		From: kst.AddDate(0, 0, -7).Format("2006-01-02"), To: kst.AddDate(0, 0, 27).Format("2006-01-02")})
	// ② 어제로 끝난 단발 배정 → 안 뜬다.
	mk(domain.HwSchedule{Type: "once", From: kst.AddDate(0, 0, -1).Format("2006-01-02"),
		To: kst.AddDate(0, 0, -1).Format("2006-01-02")})
	// ③ 오늘 요일 포함 → 뜬다.
	want := mk(domain.HwSchedule{Type: "weekly", Days: []string{weekdayWire(kst)},
		From: kst.AddDate(0, 0, -7).Format("2006-01-02"), To: kst.AddDate(0, 0, 27).Format("2006-01-02")})

	list, err := s.ListHomeworks(ctx, memberP(mem.ID), "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != want {
		ids := make([]string, 0, len(list))
		for _, hw := range list {
			ids = append(ids, hw.ID)
		}
		t.Errorf("회원 목록 = %v, want [%s](오늘 대상만)", ids, want)
	}
	// 스태프는 관리 화면이라 전체가 보인다 — date를 주면 같은 판정이 걸린다.
	if all, err := s.ListHomeworks(ctx, ownerP(), mem.ID, ""); err != nil || len(all) != 3 {
		t.Errorf("스태프 기본 목록 = %d건(err=%v), want 3(전체)", len(all), err)
	}
	if filtered, err := s.ListHomeworks(ctx, ownerP(), mem.ID, todayStr); err != nil || len(filtered) != 1 {
		t.Errorf("스태프 date 필터 = %d건(err=%v), want 1", len(filtered), err)
	}
	if _, err := s.ListHomeworks(ctx, ownerP(), mem.ID, "어제"); !errors.Is(err, errBadRequest) {
		t.Errorf("date 형식 오류 err = %v, want 400", err)
	}
}

// M4 회귀: 종료된 배정은 hw_rate 분모에서 빠져야 한다. 안 빠지면 분모가 단조 증가해
// 완료율이 시간이 갈수록 구조적으로 하락한다.
func TestHwRateExcludesEndedAssignments(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 5)
	kst := time.Now().In(domain.KST)

	// 종료된 배정(to = 어제).
	if _, err := s.CreateHomework(ctx, ownerP(), HomeworkCreateRequest{
		TrainerID: "t1", Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{mem.ID},
		Items: []domain.HwItem{{Name: "런지"}},
		Schedule: domain.HwSchedule{Type: "weekly", Days: allWeekdays,
			From: kst.AddDate(0, 0, -30).Format("2006-01-02"), To: kst.AddDate(0, 0, -1).Format("2006-01-02")},
	}); err != nil {
		t.Fatal(err)
	}
	// 진행 중 배정.
	if _, err := s.CreateHomework(ctx, ownerP(), HomeworkCreateRequest{
		TrainerID: "t1", Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{mem.ID},
		Items: []domain.HwItem{{Name: "스쿼트"}},
		Schedule: domain.HwSchedule{Type: "weekly", Days: allWeekdays,
			From: kst.AddDate(0, 0, -1).Format("2006-01-02"), To: kst.AddDate(0, 0, 27).Format("2006-01-02")},
	}); err != nil {
		t.Fatal(err)
	}

	got, err := s.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	if got.HwD != 1 {
		t.Errorf("hw_d = %d, want 1(진행 중 배정만) — 종료된 배정이 분모에 남아 완료율이 구조적으로 하락한다", got.HwD)
	}
}
