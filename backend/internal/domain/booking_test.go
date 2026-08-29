package domain

import (
	"testing"
	"time"
)

// 골든값: "슬롯 용량 3, 동일 트레이너 중복 예약 거부"(API계약_v1.md 핵심 골든값).
func TestCanBookCapacityRejection(t *testing.T) {
	slot := Slot{SlotKey: "20260814-20", Capacity: 3, Teams: []Team{
		{BookingID: "b1", TrainerID: "t1", MemberID: "m1"},
		{BookingID: "b2", TrainerID: "t2", MemberID: "m2"},
		{BookingID: "b3", TrainerID: "t3", MemberID: "m3"},
	}}
	if err := CanBook(slot, "t4", "m9"); err != ErrSlotFull {
		t.Errorf("capacity 3에 3팀 찬 슬롯 = %v, want ErrSlotFull", err)
	}
}

func TestCanBookSameTrainerRejected(t *testing.T) {
	slot := Slot{SlotKey: "20260814-20", Capacity: 3, Teams: []Team{
		{BookingID: "b1", TrainerID: "t1", MemberID: "m1"},
	}}
	if err := CanBook(slot, "t1", "m9"); err != ErrTrainerBusy {
		t.Errorf("동일 트레이너 중복 예약 = %v, want ErrTrainerBusy", err)
	}
}

func TestCanBookAllowsWhenRoomAndDifferentTrainer(t *testing.T) {
	slot := Slot{SlotKey: "20260814-20", Capacity: 3, Teams: []Team{
		{BookingID: "b1", TrainerID: "t1", MemberID: "m1"},
	}}
	if err := CanBook(slot, "t2", "m9"); err != nil {
		t.Errorf("여유 있고 다른 트레이너 = %v, want nil", err)
	}
}

func TestSlotStartParsesKST(t *testing.T) {
	start, err := SlotStart("20260814-20")
	if err != nil {
		t.Fatal(err)
	}
	if start.Hour() != 20 || start.Day() != 14 || int(start.Month()) != 8 || start.Year() != 2026 {
		t.Errorf("SlotStart = %v, 예상 2026-08-14 20:00 KST", start)
	}
	if _, off := start.Zone(); off != 9*60*60 {
		t.Errorf("타임존 오프셋 = %d, want +9h(KST)", off)
	}
}

func TestSlotStartInvalidFormat(t *testing.T) {
	if _, err := SlotStart("not-a-slot"); err != ErrInvalidSlotKey {
		t.Errorf("err = %v, want ErrInvalidSlotKey", err)
	}
}

func TestSlotKeyForRoundTrips(t *testing.T) {
	key, err := SlotKeyFor("2026-08-14", 20)
	if err != nil {
		t.Fatal(err)
	}
	if key != "20260814-20" {
		t.Errorf("SlotKeyFor = %s, want 20260814-20", key)
	}
}

func TestWithinCancelCutoff(t *testing.T) {
	start, _ := SlotStart("20260814-20")
	before, err := WithinCancelCutoff("20260814-20", start.Add(-25*time.Hour), 24)
	if err != nil {
		t.Fatal(err)
	}
	if before {
		t.Error("25시간 전은 컷오프(24h) 밖이어야 함(무료 취소)")
	}
	within, err := WithinCancelCutoff("20260814-20", start.Add(-12*time.Hour), 24)
	if err != nil {
		t.Fatal(err)
	}
	if !within {
		t.Error("12시간 전은 컷오프(24h) 안이어야 함(페널티 대상)")
	}
}

func TestCanBookRejectsSameMember(t *testing.T) {
	slot := Slot{SlotKey: "20260901-10", Capacity: 3, Teams: []Team{
		{BookingID: "b1", TrainerID: "t1", MemberID: "m1", Kind: "pt"},
	}}
	// 같은 회원이 다른 코치 패스로 같은 슬롯 재점유 → 거부(v1.5 — P04 이중 예약 실증 차단).
	if err := CanBook(slot, "t2", "m1"); err != ErrMemberBusy {
		t.Errorf("err = %v, want ErrMemberBusy", err)
	}
	// 미배정 담당("")끼리는 트레이너 규칙을 건너뛴다(P04 L7).
	slot2 := Slot{SlotKey: "20260901-11", Capacity: 3, Teams: []Team{
		{BookingID: "b2", TrainerID: "", MemberID: "m1", Kind: "ot"},
	}}
	if err := CanBook(slot2, "", "m2"); err != nil {
		t.Errorf("미배정 2건 오거부: %v", err)
	}
}
