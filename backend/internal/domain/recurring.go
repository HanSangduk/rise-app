package domain

import (
	"fmt"
	"strings"
	"time"
)

// Recurring — 고정 스케줄(API계약 v1, P47). 매주 지정 요일·시간에 슬롯을 선행 생성한다.
type Recurring struct {
	ID        string   `json:"id"`
	MemberID  string   `json:"member_id"`
	TrainerID string   `json:"trainer_id"`
	PassID    string   `json:"pass_id"`
	Days      []string `json:"days"` // "mon".."sun"
	Hour      int      `json:"hour"`
	Until     string   `json:"until"` // "YYYY-MM-DD"
}

var weekdayNames = map[string]time.Weekday{
	"sun": time.Sunday, "mon": time.Monday, "tue": time.Tuesday, "wed": time.Wednesday,
	"thu": time.Thursday, "fri": time.Friday, "sat": time.Saturday,
}

// ExpandSlotKeys — from(자정 KST)부터 weeks주 앞까지, 이 반복규칙이 생성해야 할 슬롯키 목록을
// 날짜 오름차순으로 반환한다(P47). offdays에 있는 날짜(트레이너 휴무)는 제외한다.
// r.Until 이후 날짜도 생성하지 않는다.
func ExpandSlotKeys(r Recurring, from time.Time, weeks int, offdays map[string]bool) []string {
	want := map[time.Weekday]bool{}
	for _, d := range r.Days {
		if wd, ok := weekdayNames[strings.ToLower(strings.TrimSpace(d))]; ok {
			want[wd] = true
		}
	}
	if len(want) == 0 || weeks <= 0 {
		return nil
	}
	start := time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, KST)
	end := start.AddDate(0, 0, 7*weeks)

	var out []string
	for d := start; d.Before(end); d = d.AddDate(0, 0, 1) {
		if !want[d.Weekday()] {
			continue
		}
		dateStr := d.Format(dateLayout)
		if r.Until != "" && dateStr > r.Until {
			continue
		}
		if offdays[dateStr] {
			continue
		}
		out = append(out, fmt.Sprintf("%s-%02d", d.Format("20060102"), r.Hour))
	}
	return out
}
