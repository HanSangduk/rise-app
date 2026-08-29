package domain

import (
	"errors"
	"time"
)

// CheckinWindow — 셀프체크인 허용 시간창(P44): 예약 슬롯 시작 기준 ±30분.
const CheckinWindow = 30 * time.Minute

// ErrOutsideCheckinWindow — 시간창(±30분) 밖의 셀프체크인 시도.
var ErrOutsideCheckinWindow = errors.New("domain: outside check-in window")

// ValidateSelfCheckin — 셀프체크인 시간창 검증(P44). "예약 존재" 자체는 호출측(store 조회)이
// 이미 확인했다고 가정한다 — 여기서는 순수하게 slotKey 기준 시간창만 판정한다.
//
// R10 근거: 인쇄 QR을 사진 찍어 원격에서 스캔해도 시간창 밖이면 거부되고, 세션 차감 자체는
// 어차피 트레이너의 완료 처리(P4)가 기준이라 이 검증을 우회해도 부정 이득이 없다.
func ValidateSelfCheckin(slotKey string, now time.Time) error {
	start, err := SlotStart(slotKey)
	if err != nil {
		return err
	}
	if now.Before(start.Add(-CheckinWindow)) || now.After(start.Add(CheckinWindow)) {
		return ErrOutsideCheckinWindow
	}
	return nil
}
