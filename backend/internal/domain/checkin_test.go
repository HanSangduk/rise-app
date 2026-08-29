package domain

import (
	"testing"
	"time"
)

func TestValidateSelfCheckinWindow(t *testing.T) {
	start, err := SlotStart("20260814-20")
	if err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name string
		now  time.Time
		ok   bool
	}{
		{"정시", start, true},
		{"29분 전", start.Add(-29 * time.Minute), true},
		{"29분 후", start.Add(29 * time.Minute), true},
		{"정확히 30분 전(경계 포함)", start.Add(-30 * time.Minute), true},
		{"정확히 30분 후(경계 포함)", start.Add(30 * time.Minute), true},
		{"31분 전", start.Add(-31 * time.Minute), false},
		{"31분 후", start.Add(31 * time.Minute), false},
	}
	for _, c := range cases {
		err := ValidateSelfCheckin("20260814-20", c.now)
		if (err == nil) != c.ok {
			t.Errorf("%s: err=%v, want ok=%v", c.name, err, c.ok)
		}
	}
}
