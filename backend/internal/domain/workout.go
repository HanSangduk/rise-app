package domain

// WorkoutLog — 수업 기록(API계약 v1.4). 코어 루프 "회원→회원권→예약→수업기록→인바디→정산"
// (설계00 §4)에서 유일하게 비어 있던 조각. 트레이너가 완료 처리 직후 30초 기록(P29 — 2안
// 수업 루프의 v1 흡수분)을 남기고, 회원 앱 기록 탭이 이를 조회한다.
type WorkoutLog struct {
	ID        string     `json:"id"`
	MemberID  string     `json:"member_id"`
	TrainerID string     `json:"trainer_id"`
	BookingID string     `json:"booking_id,omitempty"` // 연결된 예약(선택 — 예약 밖 세션도 기록 가능)
	Date      string     `json:"date"`                 // "2026-08-22"
	Title     string     `json:"title"`                // 예: "1:1 PT" (kind 라벨 기본값)
	Exercises []Exercise `json:"exercises"`
	CoachNote string     `json:"coach_note"`
}

// Exercise — 운동 한 항목. Reps는 HwItem과 동일 규약으로 문자열("10-12"·"30초"),
// WeightKG는 숫자(0 = 자중/해당 없음 — 진행 그래프 등 후속 분석을 위해 수치 유지).
type Exercise struct {
	Name     string  `json:"name"`
	Sets     int     `json:"sets"`
	Reps     string  `json:"reps"`
	WeightKG float64 `json:"weight_kg"`
	Note     string  `json:"note"`
}
