package domain

import "testing"

// 2026-08-17은 월요일, 08-18 화요일, 08-19 수요일, 08-23 일요일.
func TestHwScheduleIsActiveOn(t *testing.T) {
	weekly := HwSchedule{Type: HwScheduleWeekly, Days: []string{"mon", "wed", "fri"},
		From: "2026-08-01", To: "2026-08-31"}

	cases := []struct {
		name string
		s    HwSchedule
		date string
		want bool
	}{
		{"weekly 대상 요일(월)", weekly, "2026-08-17", true},
		{"weekly 비대상 요일(화)", weekly, "2026-08-18", false},
		{"weekly from 이전", weekly, "2026-07-31", false},
		{"weekly to 이후(대상 요일이어도)", weekly, "2026-09-02", false},
		{"weekly days 비면 매일", HwSchedule{Type: HwScheduleWeekly, From: "2026-08-01", To: "2026-08-31"}, "2026-08-18", true},
		{"weekly 대소문자·공백 허용", HwSchedule{Type: HwScheduleWeekly, Days: []string{" MON "}}, "2026-08-17", true},
		{"once 당일", HwSchedule{Type: HwScheduleOnce, From: "2026-08-17"}, "2026-08-17", true},
		{"once 다음날(to 없으면 from 당일로 끝)", HwSchedule{Type: HwScheduleOnce, From: "2026-08-17"}, "2026-08-18", false},
		{"once 구간 안", HwSchedule{Type: HwScheduleOnce, From: "2026-08-17", To: "2026-08-19"}, "2026-08-19", true},
		{"once 구간 밖", HwSchedule{Type: HwScheduleOnce, From: "2026-08-17", To: "2026-08-19"}, "2026-08-20", false},
		{"스케줄 미지정은 항상 노출", HwSchedule{}, "2026-08-18", true},
		{"알 수 없는 type은 weekly 폴백(앱과 동일)", HwSchedule{Type: "매일매일", Days: []string{"mon"}}, "2026-08-18", false},
		{"기간 무제한 weekly", HwSchedule{Type: HwScheduleWeekly, Days: []string{"sun"}}, "2026-08-23", true},
	}
	for _, c := range cases {
		if got := c.s.IsActiveOn(c.date); got != c.want {
			t.Errorf("%s: IsActiveOn(%s) = %v, want %v", c.name, c.date, got, c.want)
		}
	}
}

// IsEndedOn은 요일과 무관하게 "기간이 끝났는가"만 본다 — 통계 분모용(주3회 배정이 화요일에
// 분모에서 빠지면 hw_rate가 요일마다 출렁인다).
func TestHwScheduleIsEndedOn(t *testing.T) {
	weekly := HwSchedule{Type: HwScheduleWeekly, Days: []string{"mon", "wed", "fri"},
		From: "2026-08-01", To: "2026-08-31"}
	if weekly.IsEndedOn("2026-08-18") {
		t.Error("비대상 요일(화)이 '종료'로 판정됨 — 분모에서 빠지면 안 된다")
	}
	if weekly.IsActiveOn("2026-08-18") {
		t.Error("비대상 요일이 '오늘 노출'로 판정됨")
	}
	if !weekly.IsEndedOn("2026-09-01") {
		t.Error("to를 지난 배정이 종료로 판정되지 않음")
	}
	if (HwSchedule{Type: HwScheduleOnce, From: "2026-08-17"}).IsEndedOn("2026-08-17") {
		t.Error("once 당일이 종료로 판정됨")
	}
	if !(HwSchedule{Type: HwScheduleOnce, From: "2026-08-17"}).IsEndedOn("2026-08-18") {
		t.Error("once는 to가 없으면 from 당일로 끝나야 한다")
	}
	if (HwSchedule{Type: HwScheduleWeekly, From: "2026-08-01"}).IsEndedOn("2030-01-01") {
		t.Error("to 없는 weekly가 종료로 판정됨(무기한)")
	}
}

func TestValidateHwSchedule(t *testing.T) {
	ok := []HwSchedule{
		{},
		{Type: HwScheduleWeekly, Days: []string{"mon", "wed", "fri"}, From: "2026-08-17", To: "2026-09-13"},
		{Type: HwScheduleWeekly}, // days 비면 매일(어드민이 막지만 계약상 허용)
		{Type: HwScheduleOnce, From: "2026-08-17"},
	}
	for _, s := range ok {
		if err := ValidateHwSchedule(s); err != nil {
			t.Errorf("정상 스케줄이 거부됨 %+v: %v", s, err)
		}
	}
	bad := []struct {
		name string
		s    HwSchedule
	}{
		{"한글 type", HwSchedule{Type: "매일매일"}},
		{"한글 요일", HwSchedule{Type: HwScheduleWeekly, Days: []string{"월요일"}}},
		{"from 형식", HwSchedule{Type: HwScheduleWeekly, From: "어제"}},
		{"to 형식", HwSchedule{Type: HwScheduleWeekly, To: "내일"}},
		{"from > to", HwSchedule{Type: HwScheduleWeekly, From: "2026-09-01", To: "2026-08-01"}},
		{"once인데 from 없음", HwSchedule{Type: HwScheduleOnce, To: "2026-08-20"}},
	}
	for _, c := range bad {
		if err := ValidateHwSchedule(c.s); err == nil {
			t.Errorf("%s: 잘못된 스케줄이 통과 %+v", c.name, c.s)
		}
	}
	// 감사에서 실측된 입력 전체 — 400이어야 한다.
	if err := ValidateHwSchedule(HwSchedule{Type: "매일매일", Days: []string{"월요일"}, From: "어제", To: "내일"}); err == nil {
		t.Error("감사 재현 입력이 통과")
	}
}
