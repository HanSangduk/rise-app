package domain

import (
	"errors"
	"fmt"
	"time"
)

// KST — 센터 운영 타임존(v1=Asia/Seoul 고정). 고정 오프셋을 써서 시스템 tzdata 유무에 의존하지 않는다
// (Cloud Run의 최소 이미지에도 안전, 컨테이너에 IANA 타임존 DB가 없어도 항상 동일하게 동작).
var KST = time.FixedZone("KST", 9*60*60)

// Slot — 특정 시간대의 팀 슬롯(API계약 v1, 설계03 §5 P35). SlotKey="20260814-20"(YYYYMMDD-HH).
type Slot struct {
	SlotKey  string `json:"slot_key"`
	Capacity int    `json:"capacity"`
	Teams    []Team `json:"teams"`
}

// Team — 슬롯에 배정된 한 팀. 1:1도 팀 1개로 취급한다(R1: "팀 = 동시 진행 세션 1개").
// Status는 Booking.Status와 값 집합을 공유한다(confirmed|completed|noshow, v1.1 정합 패치) —
// cancelled는 팀 자체가 slot.teams에서 제거되므로(CancelAtomic) Team.Status로 나타나지 않는다.
type Team struct {
	BookingID string `json:"booking_id"`
	TrainerID string `json:"trainer_id"`
	MemberID  string `json:"member_id"`
	Kind      string `json:"kind"`   // pt|group|ot
	Status    string `json:"status"` // confirmed|completed|noshow(v1.1 정합 패치)
}

// Booking — 예약(API계약 v1).
type Booking struct {
	ID          string    `json:"id"`
	SlotKey     string    `json:"slot_key"`
	MemberID    string    `json:"member_id"`
	TrainerID   string    `json:"trainer_id"`
	PassID      string    `json:"pass_id"`
	Kind        string    `json:"kind"`
	Status      string    `json:"status"`
	RecurringID string    `json:"recurring_id,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

// Booking.Kind 값.
const (
	BookingKindPT    = "pt"
	BookingKindGroup = "group"
	BookingKindOT    = "ot"
)

// Booking.Status 값.
const (
	BookingConfirmed = "confirmed"
	BookingWaitlist  = "waitlist"
	BookingCancelled = "cancelled"
	BookingNoshow    = "noshow"
	BookingCompleted = "completed"
)

var (
	// ErrSlotFull — 슬롯 용량 초과(P35 조건①).
	ErrSlotFull = errors.New("domain: slot at capacity")
	// ErrTrainerBusy — 같은 트레이너가 이미 이 슬롯에 배정됨(P35 조건②, R2: 트레이너당 동시 1팀).
	ErrTrainerBusy = errors.New("domain: trainer already booked this slot")
	// ErrMemberBusy — 같은 회원이 이미 이 슬롯에 예약됨(v1.5 — 코치가 다른 패스 2개로 같은
	// 시간 2팀을 점유하는 이중 예약 차단, P04 감사 실증).
	ErrMemberBusy = errors.New("domain: member already booked this slot")
	// ErrInvalidSlotKey — slot_key가 "YYYYMMDD-HH" 형식이 아님.
	ErrInvalidSlotKey = errors.New("domain: invalid slot key")
	// ErrNoSessionsLeft — 잔여 청구권 소진(P13 H1). "잔여"는 원장 합(Sum)이지만 차감은 완료
	// 시점이므로(P4), 이미 잡혀 있는 confirmed 예약 하나하나가 잔여에 대한 청구권이다.
	// 예약 가능 여부는 `Σdelta − confirmed건수 > 0`이며, 이 뺄셈을 빼먹으면 잔여 2회짜리 패스에
	// 예약을 무한히 잡을 수 있다(실측: 4건 예약 → 4건 완료 → remaining −2).
	// 스토어가 **예약 생성 트랜잭션 안에서** 이 규칙을 다시 판정한다(BookAtomic).
	ErrNoSessionsLeft = errors.New("domain: no sessions left on pass")
)

// CanBook — 슬롯 예약 가능 여부(P35, R2 + v1.5): 용량 미달 AND 트레이너 동시 1팀 AND
// 회원 동시 1팀. 패스 잔여·유효기간·시간축 검사는 서비스 레이어가 별도로 담당한다(관심사 분리) —
// 이 검사들을 하나의 스토어 트랜잭션(BookAtomic) 안에서 적용하는 것은 스토어 구현의 책임이다.
// trainerID가 빈 값(미배정 담당)이면 트레이너 규칙은 건너뛴다 — ""=="" 매칭으로 서로 무관한
// 미배정 예약 2건이 오거부되는 것 방지(P04 L7).
func CanBook(slot Slot, trainerID, memberID string) error {
	if len(slot.Teams) >= slot.Capacity {
		return ErrSlotFull
	}
	for _, t := range slot.Teams {
		if trainerID != "" && t.TrainerID == trainerID {
			return ErrTrainerBusy
		}
		if memberID != "" && t.MemberID == memberID {
			return ErrMemberBusy
		}
	}
	return nil
}

// SlotStart — slotKey("20260814-20")를 KST 시각으로 파싱한다.
func SlotStart(slotKey string) (time.Time, error) {
	if len(slotKey) != 11 || slotKey[8] != '-' {
		return time.Time{}, ErrInvalidSlotKey
	}
	t, err := time.ParseInLocation("20060102-15", slotKey, KST)
	if err != nil {
		return time.Time{}, ErrInvalidSlotKey
	}
	return t, nil
}

// SlotDate — slotKey의 날짜 부분을 "YYYY-MM-DD"(KST)로 반환한다. 예약 시점 검사(패스 유효기간·
// 홀딩 구간과의 대조)는 "오늘"이 아니라 슬롯 날짜 기준이어야 한다 — 세션이 실제로 일어나는 날.
func SlotDate(slotKey string) (string, error) {
	t, err := SlotStart(slotKey)
	if err != nil {
		return "", err
	}
	return t.In(KST).Format(dateLayout), nil
}

// SlotKeyFor — 날짜("YYYY-MM-DD")와 시(0~23)로 슬롯키를 만든다.
func SlotKeyFor(date string, hour int) (string, error) {
	d, err := time.ParseInLocation(dateLayout, date, KST)
	if err != nil {
		return "", ErrInvalidSlotKey
	}
	return fmt.Sprintf("%s-%02d", d.Format("20060102"), hour), nil
}

// WithinCancelCutoff — 지금이 슬롯 시작 cutoffHours 이내(=취소 마감을 지남)인지(계약 DELETE /bookings/{id}).
// true면 취소 시 노쇼에 준하는 페널티 정책 적용 대상, false면 무료 취소(설계00 P7).
func WithinCancelCutoff(slotKey string, now time.Time, cutoffHours int) (bool, error) {
	start, err := SlotStart(slotKey)
	if err != nil {
		return false, err
	}
	return now.After(start.Add(-time.Duration(cutoffHours) * time.Hour)), nil
}
