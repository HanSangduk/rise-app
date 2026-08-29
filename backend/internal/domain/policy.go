package domain

import "errors"

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
	}
	return nil
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
	p.PenaltyRate = p.EffectivePenaltyRate()
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
	}
}
