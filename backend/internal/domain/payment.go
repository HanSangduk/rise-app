package domain

import "time"

// Payment — 결제 기록(API계약 v1). PG 연동은 v1 OUT — 사장님이 입력하는 기록만(P19).
type Payment struct {
	ID           string        `json:"id"`
	MemberID     string        `json:"member_id"`
	PassID       string        `json:"pass_id"`
	Method       string        `json:"method"` // card|cash|transfer
	Total        int           `json:"total"`
	Installments []Installment `json:"installments"`
	Channel      string        `json:"channel"`
}

// Payment.Method 값.
const (
	PayMethodCard     = "card"
	PayMethodCash     = "cash"
	PayMethodTransfer = "transfer"
)

// Installment — 분할납부 회차(P40 R7: 미수금 관리는 경쟁 제품이 1급으로 다루는 현장 필수 기능).
type Installment struct {
	Due    string     `json:"due"` // "YYYY-MM-DD"
	Amount int        `json:"amount"`
	PaidAt *time.Time `json:"paid_at"`
	// WaivedAt — 청구 종결 시각(v1.5): 패스 환불로 거래가 정산 종료돼 더 이상 수납하지 않는
	// 회차. 삭제가 아니라 표식(원장주의 P3와 동일 철학 — 기록은 남기고 의미만 바꾼다).
	WaivedAt *time.Time `json:"waived_at,omitempty"`
}

// open — 아직 살아있는 청구(미납이고 종결되지 않음).
func (i Installment) open() bool { return i.PaidAt == nil && i.WaivedAt == nil }

// Outstanding — 미납 잔액 합계(미납·미종결 회차의 amount 합 — 연체 여부 무관).
func (p Payment) Outstanding() int {
	total := 0
	for _, i := range p.Installments {
		if i.open() {
			total += i.Amount
		}
	}
	return total
}

// OverdueOutstanding — 연체 미수금(v1.5): due가 지난(오늘 미포함 — due 당일은 아직 연체 아님)
// 미납·미종결 회차의 합. §8 "미수금"의 시장 용례(납부기한 경과)와 일치시키는 재정의.
func (p Payment) OverdueOutstanding(today string) int {
	total := 0
	for _, i := range p.Installments {
		if i.open() && i.Due < today {
			total += i.Amount
		}
	}
	return total
}

// UpcomingOutstanding — 미도래 미납(v1.5): due가 아직 안 지난 미납·미종결 회차의 합.
func (p Payment) UpcomingOutstanding(today string) int {
	total := 0
	for _, i := range p.Installments {
		if i.open() && i.Due >= today {
			total += i.Amount
		}
	}
	return total
}

// PaidSum — 실수납 합계(v1.5): 납부 완료된 회차의 amount 합 — 환불 정산의 기준(P5 "실결제가").
//
// 분할 회차가 없는 결제는 **일시불 완납**으로 센다(v2.3, P12 감사 C2). installments는
// "나눠 받기로 한 일정"이고, 그 일정이 없다는 건 나눌 것이 없었다 — 그 자리에서 전액
// 수납했다는 뜻이다. Outstanding()이 이미 같은 전제로 0(낼 것 없음)을 돌려주는데 여기서만
// 0(받은 적 없음)을 돌려주면 한 레코드가 정반대 두 사실을 말하게 되고, 전액 납부한 회원의
// 환불 기준액이 0원이 된다(실측: 360,000 완납 → refund-quote 0원 → 환불 확정, 복구 API 없음).
// 불변식: 회차 없는 결제는 PaidSum + Outstanding == Total.
//
// asOf — "언제까지 들어온 돈인가"의 기준 시각(보통 time.Now()). **미래의 paid_at은 세지
// 않는다**(v2.3, P12 감사 M5): paid_at은 클라이언트가 보내는 값이라 미래 시각도 저장될 수
// 있었고, 그 순간 아직 들어오지도 않은 돈이 환불 기준액에 잡혀 그대로 지급됐다. 생성 게이트가
// 미래 paid_at을 막지만(CreatePayment), 게이트 이전에 박힌 레코드는 원장주의(P3)상 지우지
// 않으므로 정산 쪽에서 한 번 더 거른다 — C1의 계약가 상한과 같은 "쓰기+읽기 이중 방어" 구조다.
func (p Payment) PaidSum(asOf time.Time) int {
	if len(p.Installments) == 0 {
		return p.Total
	}
	total := 0
	for _, i := range p.Installments {
		if i.PaidAt != nil && !i.PaidAt.After(asOf) {
			total += i.Amount
		}
	}
	return total
}

// TotalOutstanding — 여러 결제 건의 미납 잔액 합계(GET /v1/payments?member= 목록에서 분할납부
// 현황을 한 번에 보기 위함, v1.1 정합 패치).
func TotalOutstanding(payments []Payment) int {
	total := 0
	for _, p := range payments {
		total += p.Outstanding()
	}
	return total
}

// ValidPayMethod — method가 계약 3종(card|cash|transfer)인지(v1.5 — CreatePayment 검증 게이트).
func ValidPayMethod(m string) bool {
	return m == PayMethodCard || m == PayMethodCash || m == PayMethodTransfer
}
