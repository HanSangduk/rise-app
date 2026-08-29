package domain

import (
	"errors"
	"strings"
	"time"
)

// Homework — Home Work(오늘의 운동) 배정(API계약 v1, P39, 설계03 §10).
type Homework struct {
	ID              string     `json:"id"`
	TrainerID       string     `json:"trainer_id"`
	Scope           string     `json:"scope"` // individual|my_members|center_notice
	TargetMemberIDs []string   `json:"target_member_ids"`
	Excluded        []string   `json:"excluded"`
	Items           []HwItem   `json:"items"`
	Schedule        HwSchedule `json:"schedule"`
}

// Homework.Scope 값.
const (
	HwScopeIndividual   = "individual"
	HwScopeMyMembers    = "my_members"
	HwScopeCenterNotice = "center_notice"
)

// HwItem — 처방 운동 한 항목. Reps는 문자열이다(v1.3 확정) — 현장 표기가 "10-12"·"30초"·
// "각 15회"처럼 숫자가 아니고, 앱·어드민 클라이언트 모두 string으로 취급한다(int면 배정 400).
type HwItem struct {
	Name string `json:"name"`
	Sets int    `json:"sets"`
	Reps string `json:"reps"`
	Note string `json:"note"`
}

// HwSchedule — 배정 스케줄.
type HwSchedule struct {
	Type string   `json:"type"` // once|weekly
	Days []string `json:"days"`
	From string   `json:"from"`
	To   string   `json:"to"`
}

// HwSchedule.Type 값.
const (
	HwScheduleOnce   = "once"
	HwScheduleWeekly = "weekly"
)

// ---- 스케줄 판정(P12) ----
//
// v2.3 이전에는 이 구조체를 **읽는 코드가 어디에도 없었다** — 저장만 하고 아무도 보지 않아
// ① once 배정이 영구히 "오늘의 운동"에 남고 ② days:[mon,wed,fri]도 매일 뜨고 ③ to가 지나도
// 사라지지 않아 stats.hw_rate 분모가 단조 증가했다(완료율이 시간이 갈수록 구조적으로 하락).
//
// 판정 규칙은 이미 출시된 회원 앱의 순수 함수
// (app/lib/features/home/domain/homework_schedule_rules.dart)와 **같은 규칙**이다 — 서버가
// 다른 해석을 들고 오면 같은 배정이 앱과 어드민에서 다르게 보인다. 세 레이어가 한 규칙을
// 공유하도록 그쪽 의미론을 그대로 채택하고, 여기(서버)를 진실의 정의로 삼는다.

// hwWeekdayWire — time.Weekday → 계약 요일 문자열. Recurring.Days와 같은 표기("mon".."sun").
var hwWeekdayWire = [7]string{"sun", "mon", "tue", "wed", "thu", "fri", "sat"}

// endDate — 배정이 끝나는 날("" = 무기한).
// once는 to가 없으면 from 당일로 끝난다 — "한 번만 하는 과제"가 기한 없이 남지 않게 하는
// 유일한 장치다(그 외 타입은 to가 유일한 종료 근거).
func (s HwSchedule) endDate() string {
	if s.Type == HwScheduleOnce && s.To == "" {
		return s.From
	}
	return s.To
}

// IsEndedOn — date("YYYY-MM-DD") 시점에 이 배정의 기간이 끝났는가.
//
// IsActiveOn과 나눠 둔 이유(통계용): 주3회(mon/wed/fri) 배정은 화요일에 IsActiveOn=false지만
// **여전히 진행 중인 배정**이다. 통계 분모에 IsActiveOn을 쓰면 hw_rate가 요일마다 출렁인다
// (화요일엔 주3회 배정이 통째로 분모에서 빠진다). 분모는 "끝났는가"로, 목록은 "오늘 하는가"로
// 가른다 — 판정 근거(from/to/type)는 두 함수가 공유한다.
func (s HwSchedule) IsEndedOn(date string) bool {
	end := s.endDate()
	return end != "" && date > end // 날짜는 zero-padded ISO라 문자열 비교 = 시간 비교
}

// IsActiveOn — date("YYYY-MM-DD")에 이 배정이 "오늘의 운동"으로 노출돼야 하는가.
//
//	type 없음  -> 항상(스케줄 미지정 레거시 데이터 호환 — 판정 불가를 "안 보임"으로 처리하면
//	              배정이 조용히 사라진다)
//	once      -> [from, to|from] 구간(from이 없으면 경계가 없어 항상)
//	weekly    -> [from, to] 구간 안 + 오늘 요일이 days에 포함(days가 비면 매일)
//	알 수 없는 type -> weekly로 폴백(앱과 동일)
func (s HwSchedule) IsActiveOn(date string) bool {
	if s.Type == "" {
		return true
	}
	if s.IsEndedOn(date) {
		return false
	}
	if s.From != "" && date < s.From {
		return false
	}
	if s.Type == HwScheduleOnce {
		return true // 구간 검사를 이미 통과했다
	}
	if len(s.Days) == 0 {
		return true
	}
	d, err := time.ParseInLocation(dateLayout, date, KST)
	if err != nil {
		return false // 요일을 알 수 없으면 판정 불가 — 호출측이 넘긴 날짜가 계약 형식이 아니다
	}
	today := hwWeekdayWire[int(d.Weekday())]
	for _, raw := range s.Days {
		if strings.ToLower(strings.TrimSpace(raw)) == today {
			return true
		}
	}
	return false
}

// ErrInvalidHwSchedule — Home Work 스케줄 입력 값 위반(400 매핑, api/util.go의 writeErr 참고).
var ErrInvalidHwSchedule = errors.New("domain: invalid homework schedule")

func errHwSchedule(msg string) error { return errors.Join(ErrInvalidHwSchedule, errors.New(msg)) }

// ValidateHwSchedule — 배정 스케줄 값 검증(P12 M4). 검증이 없어 {"type":"매일매일",
// "days":["월요일"],"from":"어제"} 같은 값이 200으로 저장됐고, 판정 함수가 생긴 뒤에도
// 그런 값은 어떤 규칙에도 걸리지 않아 "영원히 오늘의 운동"으로 남는다.
//
// 빈 스케줄(zero value)은 통과시킨다 — schedule을 아예 안 보내는 클라이언트가 있고,
// IsActiveOn이 그것을 "항상 노출"로 이미 정의한다.
func ValidateHwSchedule(s HwSchedule) error {
	if s.Type != "" && s.Type != HwScheduleOnce && s.Type != HwScheduleWeekly {
		return errHwSchedule(`schedule.type은 "once" 또는 "weekly"여야 해요`)
	}
	for _, raw := range s.Days {
		d := strings.ToLower(strings.TrimSpace(raw))
		ok := false
		for _, w := range hwWeekdayWire {
			if d == w {
				ok = true
				break
			}
		}
		if !ok {
			return errHwSchedule("schedule.days는 mon~sun 소문자 3글자여야 해요: " + raw)
		}
	}
	for _, f := range []struct{ name, val string }{{"from", s.From}, {"to", s.To}} {
		if f.val == "" {
			continue
		}
		if _, err := time.ParseInLocation(dateLayout, f.val, KST); err != nil {
			return errHwSchedule("schedule." + f.name + "은 YYYY-MM-DD 형식이어야 해요")
		}
	}
	if s.From != "" && s.To != "" && s.From > s.To {
		return errHwSchedule("schedule.from이 to보다 늦어요")
	}
	// once에 from이 없으면 종료일을 만들 방법이 없어 "한 번만"이 영구 노출이 된다(P12 M4 ①).
	if s.Type == HwScheduleOnce && s.From == "" {
		return errHwSchedule("단발(once) 배정은 수행일(from)이 필요해요")
	}
	return nil
}

// HwCheck — 회원의 Home Work 완료 체크(API계약 v1).
type HwCheck struct {
	MemberID string `json:"member_id"`
	HwID     string `json:"hw_id"`
	Date     string `json:"date"`
	Done     []bool `json:"done"`
}

// ResolveTargets — scope별 최종 배정 대상을 계산하고 부상 플래그 회원을 자동 제외한다(P39).
// overrideInclude에 있는 member_id는 자동 제외를 뒤집어 강제 포함한다(트레이너/사장의 명시적 예외 처리).
//
//	individual    -> candidateIDs 그대로(부상 필터 미적용 — 개인 지정은 트레이너가 인지하고 고른 것으로 간주)
//	my_members    -> candidateIDs(담당 전체 후보) 중 부상 플래그 제외
//	center_notice -> candidateIDs(센터 전체 후보) 중 부상 플래그 제외(R5: 공지형으로 톤 다운돼도 제외는 유지)
func ResolveTargets(scope string, candidateIDs []string, members []Member, overrideInclude map[string]bool) (targets, excluded []string) {
	if scope == HwScopeIndividual {
		return candidateIDs, nil
	}
	injured := map[string]bool{}
	for _, m := range members {
		if m.HasInjuryFlag() {
			injured[m.ID] = true
		}
	}
	for _, id := range candidateIDs {
		if injured[id] && !overrideInclude[id] {
			excluded = append(excluded, id)
			continue
		}
		targets = append(targets, id)
	}
	return targets, excluded
}
