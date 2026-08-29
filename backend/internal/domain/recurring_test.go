package domain

import (
	"testing"
	"time"
)

// 2026-08-17은 월요일(달력 확인됨). 화·금 20시 반복, 2주 선행 생성 기대값을 날짜순으로 고정한다.
func TestExpandSlotKeysBasic(t *testing.T) {
	r := Recurring{Days: []string{"tue", "fri"}, Hour: 20, Until: "2026-12-31"}
	from := time.Date(2026, 8, 17, 0, 0, 0, 0, KST) // 월요일
	got := ExpandSlotKeys(r, from, 2, nil)
	want := []string{"20260818-20", "20260821-20", "20260825-20", "20260828-20"}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("[%d] = %s, want %s", i, got[i], want[i])
		}
	}
}

func TestExpandSlotKeysSkipsOffdays(t *testing.T) {
	r := Recurring{Days: []string{"tue"}, Hour: 20, Until: "2026-12-31"}
	from := time.Date(2026, 8, 17, 0, 0, 0, 0, KST)
	offdays := map[string]bool{"2026-08-18": true}
	got := ExpandSlotKeys(r, from, 1, offdays)
	if len(got) != 0 {
		t.Errorf("휴무일(화요일)이 제외되어야 함, got %v", got)
	}
}

func TestExpandSlotKeysRespectsUntil(t *testing.T) {
	r := Recurring{Days: []string{"tue"}, Hour: 20, Until: "2026-08-19"} // 첫 화요일(18일)까지만
	from := time.Date(2026, 8, 17, 0, 0, 0, 0, KST)
	got := ExpandSlotKeys(r, from, 4, nil)
	if len(got) != 1 || got[0] != "20260818-20" {
		t.Errorf("until 이후는 배제되어야 함: got %v", got)
	}
}

func TestExpandSlotKeysNoDaysMatched(t *testing.T) {
	r := Recurring{Days: []string{"invalid-day"}, Hour: 20}
	from := time.Date(2026, 8, 17, 0, 0, 0, 0, KST)
	if got := ExpandSlotKeys(r, from, 2, nil); got != nil {
		t.Errorf("알 수 없는 요일 문자열이면 빈 결과, got %v", got)
	}
}
