package domain

import (
	"errors"
	"fmt"
)

// ErrInvalidPolicy — 정책 값 범위 위반(400 매핑, PUT /v1/center v1.4).
var ErrInvalidPolicy = errors.New("domain: invalid policy")

// errPolicy — ErrInvalidPolicy에 사용자향 사유를 결합한다(errors.Is 판별 + 한국어 메시지).
func errPolicy(msg string) error { return errors.Join(ErrInvalidPolicy, errors.New(msg)) }

// Policy — 센터 운영 정책(P6: "설정값으로 빼야 하는 것" — 하드코딩 금지 대상).
// API계약 v1에는 정책을 읽고 쓰는 전용 엔드포인트가 없다(v1 갭 — README 참고).
// 예약 용량·취소 컷오프·노쇼 유예·위약금율·통계 임계값 전반에서 서비스 레이어가 참조한다.
type Policy struct {
	SlotCapacity      int     `json:"slot_capacity"`       // 시간당 최대 팀 수(라이즈=3, P35)
	CancelCutoffHours int     `json:"cancel_cutoff_hours"` // 취소 마감(기본 24h, P7). **즉시·소급** — 이미 잡힌 예약의 취소에도 적용된다
	GraceOnce         bool    `json:"grace_once"`          // 노쇼 최초 1회 유예(P7)
	PenaltyRate       float64 `json:"penalty_rate"`        // 위약금율(0 ~ MaxPenaltyRate). 계약 생성 시점에 스냅샷되어 그 패스의 환불에 쓰인다
	RevenueTarget     int     `json:"revenue_target"`      // 연 매출 목표(§8 target)
	ReregWindowDays   int     `json:"rereg_window_days"`   // 재등록 인정 기간(만료 후 N일, §8 기본 90)
	LongAbsentDays    int     `json:"long_absent_days"`    // 장기미출석 기준일(§8 기본 60)
	ExpiringDays      int     `json:"expiring_days"`       // 만료임박 기준일(기본 7)
	MaxHoldsPerPass   int     `json:"max_holds_per_pass"`  // 패스당 홀딩 최대 횟수(P46 "최대 2회" — 회원 셀프 홀딩에 강제). -1=명시적 무제한, 0=필드 부재(NormalizeHoldLimits가 기본값 승격)
	MaxHoldTotalDays  int     `json:"max_hold_total_days"` // 패스당 홀딩 총 일수 상한(P46 "총 30일"). -1=무제한, 0=부재→기본값

	// OpenHour / CloseHour — 센터 운영시간(v2.24, P51). **둘 다 "슬롯 시작 시각"이고 양끝
	// 포함이다**: 9~21은 09:00 시작 슬롯부터 21:00 시작 슬롯까지 **13칸**을 뜻한다
	// (21:00 수업이 끝나는 22:00이 아니라, 21:00에 **시작하는** 수업이 마지막이라는 뜻).
	//
	// 이 한 줄을 잘못 읽으면 영업 한 시간이 조용히 사라지거나 없던 한 시간이 생긴다 —
	// `for h := open; h <= close; h++`가 맞고 `h < close`는 마지막 수업을 지운다.
	OpenHour  int `json:"open_hour"`  // 첫 슬롯 시작 시각(0~23). 기본 9
	CloseHour int `json:"close_hour"` // 마지막 슬롯 시작 시각(0~23, 포함). 기본 21
}

// Validate — 정책 편집(PUT /v1/center, v1.4)의 범위 검증. 운영을 마비시키는 값(용량 0,
// 음수 컷오프, 상한 초과 위약금율)을 저장 전에 거부한다.
//
// **위약금율 상한(P14 C1)**: 종전엔 0~1을 전부 통과시켜 30%가 저장에 성공했다. 그런데 실제
// 공제는 RefundQuote가 MaxPenaltyRate로 캡했고, 그 사이에 계약 스냅샷이 끼어 있어 **회원은
// 30% 조항에 서명하는데 공제는 10%**가 되는 세 갈래 불일치가 났다(어드민 화면 30% / 계약서
// 30% / 실제 환불 10% / 회원앱 30%). 상한이 진짜 정책이므로 상한이 정책의 언어로 말해야 한다 —
// 집행하지 않을 조항을 발행하지 않고, 발행할 조항은 반드시 집행한다.
func (p Policy) Validate() error {
	switch {
	case p.SlotCapacity < 1 || p.SlotCapacity > 10:
		return errPolicy("slot_capacity는 1~10 사이여야 해요")
	case p.CancelCutoffHours < 0 || p.CancelCutoffHours > 168:
		return errPolicy("cancel_cutoff_hours는 0~168(7일) 사이여야 해요")
	case p.PenaltyRate < 0 || p.PenaltyRate > MaxPenaltyRate:
		return errPolicy("penalty_rate는 0~0.1 사이여야 해요(상한 10% — 환불에서 실제로 공제되는 최대치)")
	case p.RevenueTarget < 0:
		return errPolicy("revenue_target은 0 이상이어야 해요")
	case p.ReregWindowDays < 0 || p.LongAbsentDays < 0 || p.ExpiringDays < 0:
		return errPolicy("기간(일) 설정은 0 이상이어야 해요")
	case p.MaxHoldsPerPass == 0 || p.MaxHoldsPerPass < -1:
		return errPolicy("max_holds_per_pass는 양수 또는 -1(무제한)이어야 해요")
	case p.MaxHoldTotalDays == 0 || p.MaxHoldTotalDays < -1:
		return errPolicy("max_hold_total_days는 양수 또는 -1(무제한)이어야 해요")
	case p.OpenHour < 0 || p.OpenHour > 23 || p.CloseHour < 0 || p.CloseHour > 23 || p.OpenHour >= p.CloseHour:
		// 두 숫자를 문구에 그대로 싣는다 — "운영시간이 올바르지 않아요"만 돌려주면 대표는
		// 어느 칸을 고쳐야 하는지 모른다(폼이 두 칸이고 틀린 쪽이 한 칸일 때가 대부분이다).
		return errPolicy(fmt.Sprintf(
			"운영시간이 올바르지 않아요 — 여는 시각(%d시)이 닫는 시각(%d시)보다 앞서야 하고, 둘 다 0~23 사이여야 해요",
			p.OpenHour, p.CloseHour))
	}
	return nil
}

// IsOpenHour — 그 시각에 시작하는 슬롯이 운영시간 안인지(양끝 포함).
func (p Policy) IsOpenHour(hour int) bool { return hour >= p.OpenHour && hour <= p.CloseHour }

// SlotHours — 운영시간의 슬롯 시작 시각 전부(오름차순). 9~21이면 13개다.
// 클라이언트가 시간 그리드를 그릴 때 세는 수와 **같은 수**를 서버가 셀 수 있어야
// 오프바이원이 테스트로 잡힌다(이 함수가 없으면 세는 곳마다 다시 틀릴 기회가 생긴다).
func (p Policy) SlotHours() []int {
	if p.OpenHour < 0 || p.CloseHour > 23 || p.OpenHour > p.CloseHour {
		return nil
	}
	out := make([]int, 0, p.CloseHour-p.OpenHour+1)
	for h := p.OpenHour; h <= p.CloseHour; h++ {
		out = append(out, h)
	}
	return out
}

// EffectivePenaltyRate — **계약서에 인쇄되고 실제로 공제되는 단 하나의 요율**(P14 C1).
// 계약 스냅샷·환불 정산·회원앱 응답이 전부 이 값을 거쳐야 네 자리가 같은 숫자를 말한다.
// Validate가 이미 상한을 강제하므로 정상 경로에서는 항등 함수다 — 손으로 고친 Firestore
// 문서처럼 검증을 지나지 않은 값이 들어왔을 때만 접힌다(RefundQuote의 캡과 같은 자리).
func (p Policy) EffectivePenaltyRate() float64 {
	switch {
	case p.PenaltyRate < 0:
		return 0
	case p.PenaltyRate > MaxPenaltyRate:
		return MaxPenaltyRate
	}
	return p.PenaltyRate
}

// Normalize — 저장소에서 **읽어 올린 정책 문서**를 현재 계약에 맞춘다(마이그레이션 없이 동작).
// 두 가지를 한다: ① 홀딩 상한 필드 부재 승격 ② 위약금율 상한 접기.
//
// ②를 읽는 쪽에서 하는 이유(P14 C1): 이번 변경 전에 30%로 저장된 센터 문서가 실재한다.
// 접지 않으면 그 값이 계약 스냅샷·회원앱으로 그대로 새어나가고(고치려던 결함 그대로), 더 나쁘게는
// 머지 시맨틱 PUT이 초과값을 이어받아 Validate에 걸려 **용량 하나 바꾸려 해도 400**이 되는
// 잠금 상태가 된다. 저장은 이후 아무 PUT에서나 자연스럽게 정리된다.
func (p *Policy) Normalize() {
	p.NormalizeHoldLimits()
	p.NormalizeHours()
	p.PenaltyRate = p.EffectivePenaltyRate()
}

// NormalizeHours — v2.24 이전에 저장된 정책 문서(운영시간 필드 부재 → 둘 다 0)에 기존 동작
// 그대로인 기본값 9·21을 채운다. **부재 판정을 개별 필드가 아니라 (0,0) 쌍에 건다**는 것이
// 이 함수의 전부다.
//
// 홀딩 상한(NormalizeHoldLimits)은 "0 = 필드 부재"를 필드 하나씩 판정하지만, 운영시간에는
// 그 규약을 그대로 옮길 수 없다: **0시는 24시간 헬스장의 실제 여는 시각**이라, 0을 부재로
// 읽으면 자정 개점이 영원히 표현 불가능해진다(-1을 부재 센티널로 쓰는 것도 같은 문제 —
// 구문서의 제로값은 어차피 0이라 구분이 안 된다).
//
// 대신 Validate가 `open < close`를 강제하므로 **(0,0)은 애초에 저장될 수 없는 조합**이다.
// 그래서 그 쌍 하나만 "필드가 없던 문서"의 서명으로 쓸 수 있다 — open_hour=0은
// close_hour가 1 이상이기만 하면 그대로 살아남는다(자정 개점 표현 가능).
//
// 읽기는 관대하고 쓰기는 엄격하다: 저장된 (0,0)은 여기서 기본값으로 승격되지만,
// PUT /v1/center로 **명시적으로 보낸** {open_hour:0, close_hour:0}은 Validate가 400으로
// 거부한다(조용히 9~21로 바꿔 저장하면 대표가 요청한 적 없는 값이 남는다).
// NormalizeHoldLimits의 "0 읽기=기본값 승격 / 0 쓰기=400"과 정확히 같은 비대칭이다.
func (p *Policy) NormalizeHours() {
	if p.OpenHour == 0 && p.CloseHour == 0 {
		def := DefaultPolicy()
		p.OpenHour, p.CloseHour = def.OpenHour, def.CloseHour
	}
}

// NormalizeHoldLimits — v1.2 이전에 저장된 정책 문서(홀딩 상한 필드 부재 → 0)에 기본값을
// 채운다. 0을 무제한으로 해석하면 구문서에서 상한이 조용히 풀리므로, 무제한은 -1로만 표현한다.
func (p *Policy) NormalizeHoldLimits() {
	def := DefaultPolicy()
	if p.MaxHoldsPerPass == 0 {
		p.MaxHoldsPerPass = def.MaxHoldsPerPass
	}
	if p.MaxHoldTotalDays == 0 {
		p.MaxHoldTotalDays = def.MaxHoldTotalDays
	}
}

// DefaultPolicy — 라이즈 컨디셔닝 v1 기본값. 실제 값(위약금율·컷오프 등)은 친구 미팅 후
// 센터 설정으로 조정될 자리다(설계00 §8 R4 "수렴 확인" 표 — 사람/미팅이 답할 영역).
func DefaultPolicy() Policy {
	return Policy{
		SlotCapacity:      3,
		CancelCutoffHours: 24,
		GraceOnce:         true,
		PenaltyRate:       0.10,
		RevenueTarget:     0,
		ReregWindowDays:   90,
		LongAbsentDays:    60,
		ExpiringDays:      7,
		MaxHoldsPerPass:   2,
		MaxHoldTotalDays:  30,
		// 9·21은 종전 어드민·앱 하드코딩(09~21)과 **글자 그대로 같은 값**이다(v2.24).
		// 대표가 손대기 전까지 동작이 1분도 달라지지 않는 것이 이 기본값의 유일한 목적이다.
		OpenHour:  9,
		CloseHour: 21,
	}
}
