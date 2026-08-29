package domain

import "time"

// Rate — 일반 비율 계산(분모 0 안전). noshow_rate·hw_rate·rereg_rate 등에 공용으로 쓴다.
func Rate(n, d int) float64 {
	if d == 0 {
		return 0
	}
	return float64(n) / float64(d)
}

// CombineRereg — 트레이너별 (재등록n, 만료대상d) 쌍을 센터 합산 (n,d)로 합친다.
// 센터 유지율 = Σ트레이너 재등록 / Σ트레이너 만료대상(P45).
// 골든값(설계03 §14 R10 데모수치): 정혜린(2,8) + 김태오(1,6) + 이준호(1,6) = (4,20) = 20%.
func CombineRereg(pairs ...[2]int) (n, d int) {
	for _, p := range pairs {
		n += p[0]
		d += p[1]
	}
	return n, d
}

// LongAbsent — 마지막 방문이 thresholdDays일 이상 지났는지(§8 장기미출석). 방문 기록이
// 아예 없는 회원도 장기미출석으로 취급한다(등록만 하고 한 번도 안 온 케이스를 놓치지 않기 위함).
func LongAbsent(lastVisit *time.Time, now time.Time, thresholdDays int) bool {
	if lastVisit == nil {
		return true
	}
	return now.Sub(*lastVisit) >= time.Duration(thresholdDays)*24*time.Hour
}

// ExpiringSoon — 회원권 만료가 withinDays일 이내로 임박했는지(§8). 이미 만료된 건(음수 차이)은
// "임박"이 아니라 별도의 만료 처리 대상이므로 false를 반환한다.
func ExpiringSoon(validUntil string, now time.Time, withinDays int) bool {
	until, err := time.ParseInLocation(dateLayout, validUntil, KST)
	if err != nil {
		return false
	}
	d := until.Sub(now)
	return d >= 0 && d <= time.Duration(withinDays)*24*time.Hour
}

// MonthlyPoint — 월별 매출 포인트(API계약 v1 Stats.monthly).
type MonthlyPoint struct {
	Month  string `json:"month"` // "2026-08"
	Amount int    `json:"amount"`
}

// TrainerStats — 트레이너별 지표 한 행(owner 전용, P13·P45).
//
// 비율 3종이 모두 분모를 동반한다(계약 v2.1). 행 단위에서 분모는 top-level보다 더 자주 0이 된다
// — 이번 기간에 수업이 없었던 코치가 그렇다. 분모가 없으면 그 행이 "노쇼 0.0%"로 최우수처럼
// 정렬되어, 실제로는 비교 불가인 코치가 표의 1등이 된다. **json 키는 top-level Stats와 동일**해야
// 클라이언트가 행과 센터 합계에 같은 "분모 0이면 —" 규칙을 한 벌로 적용할 수 있다.
type TrainerStats struct {
	UID string `json:"uid"`
	// Status — active|inactive(v2.0). 퇴사자 행이 왜 아직 보이는지를 표가 스스로 설명한다.
	Status     string  `json:"status"`
	Name       string  `json:"name"`
	Revenue    int     `json:"revenue"`
	Sessions   int     `json:"sessions"`
	ReregRate  float64 `json:"rereg_rate"`
	ReregN     int     `json:"rereg_n"`
	ReregD     int     `json:"rereg_d"`
	NoshowRate float64 `json:"noshow_rate"`
	NoshowD    int     `json:"noshow_d"` // 노쇼율 분모 = 이 코치의 집계 대상 예약 수(완료+노쇼, v2.1)
	HwRate     float64 `json:"hw_rate"`
	HwD        int     `json:"hw_d"` // 홈워크 완료율 분모 = 이 코치가 배정한 대상 수(v2.1)
}

// Stats — 통계 응답(API계약 v1). ByTrainer는 owner 전용(scope=center일 때만 채워짐).
//
// 비율 지표는 **분모를 함께 싣는다**(rereg_n/rereg_d의 선례를 noshow·hw로 확장, 계약 v2.1).
// Rate()가 분모 0에 0을 돌려주므로 비율만 보면 "성과 0"과 "모수 없음"이 같은 0%로 보이는데,
// 그 둘은 화면에서 정반대 뜻이다 — 신규 센터의 "아직 집계할 게 없음"이 성과 실패로 읽힌다.
// 클라이언트는 분모가 0이면 "0%"가 아니라 "—"를 표시한다.
type Stats struct {
	ActiveMembers int            `json:"active_members"`
	Registered    int            `json:"registered"`
	ReregRate     float64        `json:"rereg_rate"`
	ReregN        int            `json:"rereg_n"`
	ReregD        int            `json:"rereg_d"`
	Unassigned    int            `json:"unassigned"`
	LongAbsent    int            `json:"long_absent"`
	Expiring      int            `json:"expiring"`
	Monthly       []MonthlyPoint `json:"monthly"`
	YTD           int            `json:"ytd"`
	Target        int            `json:"target"`
	NoshowRate    float64        `json:"noshow_rate"`
	NoshowD       int            `json:"noshow_d"` // 노쇼율 분모 = 집계 대상 예약 수(완료+노쇼, v2.1)
	HwRate        float64        `json:"hw_rate"`
	HwD           int            `json:"hw_d"`           // 홈워크 완료율 분모 = 집계 대상 배정 수(v2.1)
	Sessions      int            `json:"sessions"`       // 완료 세션 수(스코프 내 — 트레이너 scope=me면 본인 정산 근거, v1.4)
	UnpaidTotal   int            `json:"unpaid_total"`   // 연체 미수금(원, owner 전용 — due 경과 미납 회차 합, v1.5 재정의)
	UnpaidCount   int            `json:"unpaid_count"`   // 연체 회차가 있는 결제 건수(owner 전용)
	UpcomingTotal int            `json:"upcoming_total"` // 미도래 미납 합계(due 전 — 연체 아님, owner 전용, v1.5)
	ByTrainer     []TrainerStats `json:"by_trainer,omitempty"`
}
