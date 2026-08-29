package domain

import "time"

// Ledger — 원장(append-only, API계약 v1). 잔여 세션은 이 합산으로만 파생된다(불변식2, P3).
// Pass.Remaining 필드를 직접 수정하는 코드는 어디에도 있어서는 안 된다 — 항상 Sum()을 거친다.
type Ledger struct {
	ID           string    `json:"id"`
	PassID       string    `json:"pass_id"`
	MemberID     string    `json:"member_id"`
	Delta        int       `json:"delta"`
	Reason       string    `json:"reason"`
	RefBookingID string    `json:"ref_booking_id,omitempty"`
	By           string    `json:"by"`
	At           time.Time `json:"at"`
}

// Ledger.Reason 값(API계약 v1).
const (
	ReasonIssue       = "issue"         // 발급
	ReasonComplete    = "complete"      // 수업 완료 차감(P4: 예약 시점이 아니라 완료 시점)
	ReasonNoshow      = "noshow"        // 노쇼 차감
	ReasonNoshowWaive = "noshow_waived" // 노쇼 최초 1회 유예(P7)
	ReasonRevert      = "revert"        // 차감 취소(관리자 정정)
	ReasonRefund      = "refund"        // 환불
	ReasonHold        = "hold"          // 홀딩 시작
	ReasonResume      = "resume"        // 홀딩 조기 종료
	ReasonTransfer    = "transfer"      // 트레이너 이관(P18)
)

// Sum — 잔여 세션 = Σ delta(불변식2, P3). 이 함수가 "잔여"의 유일한 출처다.
func Sum(entries []Ledger) int {
	total := 0
	for _, e := range entries {
		total += e.Delta
	}
	return total
}
