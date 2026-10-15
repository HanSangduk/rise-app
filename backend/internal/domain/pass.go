package domain

import (
	"errors"
	"time"
)

// Pass — 회원권(API계약 v1). Remaining은 파생값이다 — Ledger.Sum()의 캐시일 뿐,
// 필드를 직접 수정하지 않는다(불변식2, P3). 서비스 레이어가 원장 합산 후 채워 넣는다.
type Pass struct {
	ID            string `json:"id"`
	MemberID      string `json:"member_id"`
	TrainerID     string `json:"trainer_id"`
	Product       string `json:"product"`
	PaidAmount    int    `json:"paid_amount"` // 원(정수). 실결제가 — 환불 계산의 기준(P5)
	TotalSessions int    `json:"total_sessions"`
	Remaining     int    `json:"remaining"`
	ValidFrom     string `json:"valid_from"`  // "2026-08-14"
	ValidUntil    string `json:"valid_until"` // "2026-08-14"
	Status        string `json:"status"`      // active|scheduled|expired|refunded
	Holds         []Hold `json:"holds"`

	// RefundedAmount / RefundedAt — 환불 마감이 정산한 **실제 환불액(원)**과 마감 시각(v2.37, P73).
	// 종전엔 이 금액이 RefundResult(HTTP 응답)에만 있었다: 돈이 **나가는** 유일한 사건의 액수가
	// 응답 창을 닫는 순간 어디에도 남지 않아, "이 회원에게 얼마를 돌려줬나"를 나중에 원장·결제·
	// 계약을 손으로 합쳐 SettleRefund를 재실행해야만 복원할 수 있었다. 마감 트랜잭션 안에서
	// status=refunded와 함께 쓰므로 둘이 어긋날 수 없다. 환불 전엔 nil(omitempty).
	// 포인터인 이유: 정산이 정확히 0원으로 끝나는 환불이 실재한다(사용분+위약금 ≥ 실수납 —
	// SettleRefund가 0으로 접는다). int+omitempty면 그 "0원 환불"과 "환불 전·구버전 문서"가 와이어에서
	// 같은 모양이 된다. nil = 모름(환불 전·v2.37 이전 환불), &0 = 0원 환불.
	RefundedAmount *int       `json:"refunded_amount,omitempty"`
	RefundedAt     *time.Time `json:"refunded_at,omitempty"`
}

// Pass.Status 값.
const (
	PassStatusActive    = "active"
	PassStatusScheduled = "scheduled"
	PassStatusExpired   = "expired"
	PassStatusRefunded  = "refunded"
)

// EffectiveStatus — 오늘(KST, "YYYY-MM-DD") 기준의 실제 회원권 상태.
//
// **저장된 Status를 그대로 믿으면 안 된다.** CreatePass는 무조건 active를 박고,
// expired·scheduled를 대입하는 코드는 프로덕션에 한 줄도 없다(P25). 그래서 유효기간이
// 지난 회원권이 앱·어드민에서 영원히 "이용 중"으로 보였고, 재등록률(§8)은 분모가
// `status=expired` 개수라 영구 0이었다.
//
// 배치 잡으로 뒤집지 않고 읽는 시점에 계산하는 이유: Remaining이 이미 같은 방식
// (원장 합산의 캐시)이고, 잡은 "안 돌면 조용히 틀린다"는 실패 모드를 새로 만든다.
// 여기서 만든 값은 **응답에만** 싣고 저장하지 않는다.
//
// refunded는 저장된 종단 상태라 날짜보다 우선한다 — 환불한 회원권이 기간이 남았다는
// 이유로 되살아나면 잔여·예약 표시가 전부 거짓이 된다.
//
// 날짜가 비었거나 형식이 틀린 레코드는 **추측하지 않고 저장값을 그대로 돌려준다**.
// 빈 ValidUntil을 문자열 비교하면 어떤 today보다도 작아 전부 expired로 뒤집힌다 —
// 멀쩡히 쓰던 회원권이 하루아침에 "만료"로 보이는 쪽이 더 나쁘다.
//
// 경계는 예약 검사(`slotDate < ValidFrom || slotDate > ValidUntil`)와 **같다** —
// 시작일·종료일 당일은 유효하다. 두 판정이 갈리면 "이용 중인데 예약이 안 되는" 날이 생긴다.
func (p Pass) EffectiveStatus(today string) string {
	if p.Status == PassStatusRefunded {
		return p.Status
	}
	if !validDate(p.ValidFrom) || !validDate(p.ValidUntil) || !validDate(today) {
		return p.Status
	}
	switch {
	case today < p.ValidFrom:
		return PassStatusScheduled
	case today > p.ValidUntil:
		return PassStatusExpired
	default:
		return PassStatusActive
	}
}

// BookableStatus — 이 상태의 회원권으로 예약을 잡을 수 있는가.
//
// **scheduled를 포함한다.** 아직 시작 전인 재등록 회원권으로도 유효기간 안의 슬롯이면
// 선예약이 되어야 한다(v1.3 시간축: 판정 기준은 "오늘"이 아니라 "슬롯이 일어나는 날").
// 날짜 적합성은 호출부가 슬롯별로 따로 본다(`slotDate < ValidFrom || slotDate > ValidUntil`) —
// 여기서 막을 일이 아니다.
//
// 종전 게이트는 `Status != active`였다. 바로 아래 주석이 "valid_from이 미래인 재등록
// 패스도 선예약 허용"이라고 적혀 있는데도 코드가 그 반대였는데, 저장된 Status가 늘
// active라 **드러나지 않았다**(EffectiveStatus 주석). 상태를 날짜에서 계산하기
// 시작하자마자 기존 테스트가 이 모순을 잡았다.
//
// 화이트리스트인 이유: 나중에 상태가 늘었을 때 "모르는 상태 = 예약 가능"으로
// 기울면 안 된다. 모르면 막는 쪽이 안전하다.
func (p Pass) BookableStatus() bool {
	return p.Status == PassStatusActive || p.Status == PassStatusScheduled
}

// validDate — "YYYY-MM-DD"로 파싱되는지. 형식이 맞으면 문자열 비교가 날짜 순서와 같다.
func validDate(s string) bool {
	_, err := time.ParseInLocation(dateLayout, s, KST)
	return err == nil
}

// Hold — 홀딩(일시정지) 구간(P46). from/to는 "YYYY-MM-DD".
type Hold struct {
	From   string `json:"from"`
	To     string `json:"to"`
	Reason string `json:"reason"`
}

// dateLayout — 날짜 전용 필드("valid_until" 등)의 표준 레이아웃. API계약 v1: 날짜 "2026-08-14".
const dateLayout = "2006-01-02"

var (
	// ErrInvalidHoldRange — 홀딩 구간이 날짜 형식이 아니거나 to가 from보다 앞선 경우.
	ErrInvalidHoldRange = errors.New("domain: invalid hold date range")
	// ErrNoActiveHold — 오늘 진행 중인 홀딩이 없는데 resume을 시도한 경우.
	ErrNoActiveHold = errors.New("domain: no active hold to resume")
	// ErrHoldLimitExceeded — 홀딩 정책 상한(패스당 횟수·총 일수) 초과(P46 "최대 2회·총 30일" — 정책값).
	ErrHoldLimitExceeded = errors.New("domain: hold limit exceeded")
	// ErrInvalidPassPeriod — 회원권 유효기간이 비었거나 형식이 틀렸거나 끝이 시작보다 앞선 경우.
	ErrInvalidPassPeriod = errors.New("domain: invalid pass period")
)

// ValidatePassPeriod — 발급 시 유효기간 검증(P09).
//
// 빈 값을 허용하면 **영원히 예약할 수 없는 회원권**이 조용히 만들어진다: 예약의 기간 검사가
// 문자열 비교(`slotDate > pass.ValidUntil`)라 ValidUntil이 ""면 어떤 날짜든 참이 되어 항상
// "유효기간 밖"으로 거부된다. 만료임박 KPI·홀딩 연장·월별 매출도 이 두 값을 파싱하므로
// 빈 값 하나가 여러 계산을 함께 망가뜨린다.
func ValidatePassPeriod(from, until string) error {
	f, err := time.ParseInLocation(dateLayout, from, KST)
	if err != nil {
		return errors.Join(ErrInvalidPassPeriod, errors.New("회원권 시작일을 YYYY-MM-DD 형식으로 입력해주세요"))
	}
	u, err := time.ParseInLocation(dateLayout, until, KST)
	if err != nil {
		return errors.Join(ErrInvalidPassPeriod, errors.New("회원권 종료일을 YYYY-MM-DD 형식으로 입력해주세요"))
	}
	if u.Before(f) {
		return errors.Join(ErrInvalidPassPeriod, errors.New("회원권 종료일이 시작일보다 앞설 수 없어요"))
	}
	return nil
}

// ValidateHoldWindow — 새 홀딩 구간의 시간축 검증(P01 2R HIGH-1). 회원 셀프 홀딩이
// (a) 과거 구간으로 유효기간을 공짜 연장하거나 (b) 이미 만료된 기간 밖 구간으로 패스를
// 부활시키거나 (c) 기존 홀딩과 겹쳐 이중 연장하는 것을 막는다. 스태프는 서비스 레이어에서
// 건너뛸 수 있다(과거 정정 등 데스크 예외).
func ValidateHoldWindow(existing []Hold, next Hold, today, validUntil string) error {
	if _, err := HoldDurationDays(next); err != nil {
		return err
	}
	if next.From < today {
		return ErrInvalidHoldRange // 과거 시작 — 이미 지난 날을 "정지"할 수는 없다
	}
	if validUntil != "" && next.From > validUntil {
		return ErrInvalidHoldRange // 유효기간(연장 전) 밖에서 시작 — 만료 패스 부활 방지
	}
	for _, h := range existing {
		if next.From <= h.To && h.From <= next.To {
			return ErrInvalidHoldRange // 기존 홀딩과 겹침 — 같은 날을 두 번 연장 금지
		}
	}
	return nil
}

// ValidateNewHold — 새 홀딩이 정책 상한을 넘지 않는지 검증한다(P46). 회원 셀프 홀딩(신청 큐 없는
// v1 단순화)의 가드레일 — 스태프는 서비스 레이어에서 이 검증을 건너뛸 수 있다(데스크 예외 처리).
// maxCount/maxTotalDays가 0 이하면 해당 상한은 무제한으로 취급한다(정상 로드 경로에선
// Policy.NormalizeHoldLimits가 0을 기본값으로 승격하므로 무제한은 -1로만 온다).
// 참고: 조기 종료(Resume)된 홀딩도 횟수 상한에 포함된다 — "사용한 홀딩은 소진" 의도.
func ValidateNewHold(existing []Hold, next Hold, maxCount, maxTotalDays int) error {
	nextDays, err := HoldDurationDays(next)
	if err != nil {
		return err
	}
	if maxCount > 0 && len(existing)+1 > maxCount {
		return ErrHoldLimitExceeded
	}
	if maxTotalDays > 0 {
		total := nextDays
		for _, h := range existing {
			d, err := HoldDurationDays(h)
			if err != nil {
				continue // 저장된 과거 구간이 깨져 있어도 새 신청 검증은 계속한다
			}
			total += d
		}
		if total > maxTotalDays {
			return ErrHoldLimitExceeded
		}
	}
	return nil
}

// OnHold — 오늘이 홀딩 구간(양 끝 포함)에 포함되는지.
func (p Pass) OnHold(today string) bool {
	for _, h := range p.Holds {
		if today >= h.From && today <= h.To {
			return true
		}
	}
	return false
}

// HoldDurationDays — 홀딩 일수(양 끝 포함, 예: 09-01~09-10 = 10일).
func HoldDurationDays(h Hold) (int, error) {
	from, err := time.Parse(dateLayout, h.From)
	if err != nil {
		return 0, ErrInvalidHoldRange
	}
	to, err := time.Parse(dateLayout, h.To)
	if err != nil {
		return 0, ErrInvalidHoldRange
	}
	if to.Before(from) {
		return 0, ErrInvalidHoldRange
	}
	days := int(to.Sub(from).Hours()/24) + 1
	return days, nil
}

// ApplyHold — 홀딩 구간만큼 유효기간을 자동 연장한 새 valid_until을 계산한다(P46: "유효기간 자동 연장").
// 호출측(서비스 레이어)이 Pass.Holds에 h를 append하고 ValidUntil을 반환값으로 갱신한다.
func ApplyHold(validUntil string, h Hold) (newValidUntil string, days int, err error) {
	days, err = HoldDurationDays(h)
	if err != nil {
		return "", 0, err
	}
	until, err := time.Parse(dateLayout, validUntil)
	if err != nil {
		return "", 0, ErrInvalidHoldRange
	}
	return until.AddDate(0, 0, days).Format(dateLayout), days, nil
}

// ResumeHold — 오늘 진행 중인(가장 최근의) 홀딩을 오늘 날짜로 조기 종료하고,
// 단축된 일수만큼 valid_until을 되돌린다(조기 복귀 시 과잉 연장을 방지).
// 반환된 holds/validUntil을 호출측이 그대로 저장한다.
func ResumeHold(holds []Hold, validUntil string, today string) (updated []Hold, newValidUntil string, err error) {
	idx := -1
	for i := len(holds) - 1; i >= 0; i-- {
		if today >= holds[i].From && today <= holds[i].To {
			idx = i
			break
		}
	}
	if idx == -1 {
		return holds, validUntil, ErrNoActiveHold
	}
	original := holds[idx]
	originalDays, err := HoldDurationDays(original)
	if err != nil {
		return holds, validUntil, err
	}
	shortened := original
	shortened.To = today
	shortenedDays, err := HoldDurationDays(shortened)
	if err != nil {
		return holds, validUntil, err
	}
	giveBack := originalDays - shortenedDays

	until, err := time.Parse(dateLayout, validUntil)
	if err != nil {
		return holds, validUntil, ErrInvalidHoldRange
	}
	newUntil := until.AddDate(0, 0, -giveBack).Format(dateLayout)

	out := make([]Hold, len(holds))
	copy(out, holds)
	out[idx] = shortened
	return out, newUntil, nil
}
