package domain

import "testing"

func TestApplyHoldExtendsValidUntil(t *testing.T) {
	h := Hold{From: "2026-09-01", To: "2026-09-10", Reason: "여행"}
	newUntil, days, err := ApplyHold("2026-12-31", h)
	if err != nil {
		t.Fatal(err)
	}
	if days != 10 {
		t.Errorf("days = %d, want 10(양끝포함)", days)
	}
	if newUntil != "2027-01-10" {
		t.Errorf("newUntil = %s, want 2027-01-10", newUntil)
	}
}

func TestApplyHoldInvalidRange(t *testing.T) {
	h := Hold{From: "2026-09-10", To: "2026-09-01"} // to가 from보다 앞섬
	if _, _, err := ApplyHold("2026-12-31", h); err != ErrInvalidHoldRange {
		t.Errorf("err = %v, want ErrInvalidHoldRange", err)
	}
}

func TestResumeHoldEarlyGivesBackUnusedDays(t *testing.T) {
	holds := []Hold{{From: "2026-09-01", To: "2026-09-10", Reason: "여행"}}
	updated, newUntil, err := ResumeHold(holds, "2027-01-10", "2026-09-05")
	if err != nil {
		t.Fatal(err)
	}
	if updated[0].To != "2026-09-05" {
		t.Errorf("holds[0].To = %s, want 2026-09-05(조기종료)", updated[0].To)
	}
	// 원래 10일 연장 중 09-01~09-05(5일)만 사용 -> 5일 반환 -> 2027-01-10 - 5일 = 2027-01-05.
	if newUntil != "2027-01-05" {
		t.Errorf("newUntil = %s, want 2027-01-05", newUntil)
	}
}

func TestResumeHoldNoActiveHold(t *testing.T) {
	_, _, err := ResumeHold(nil, "2027-01-10", "2026-09-05")
	if err != ErrNoActiveHold {
		t.Errorf("err = %v, want ErrNoActiveHold", err)
	}
}

func TestValidateNewHoldLimits(t *testing.T) {
	ten := Hold{From: "2026-09-01", To: "2026-09-10"} // 10일
	cases := []struct {
		name     string
		existing []Hold
		next     Hold
		maxCount int
		maxDays  int
		wantErr  error
	}{
		{"첫 홀딩 10일 통과", nil, ten, 2, 30, nil},
		{"2회째 통과", []Hold{ten}, Hold{From: "2026-10-01", To: "2026-10-05"}, 2, 30, nil},
		{"3회째는 횟수 초과", []Hold{ten, ten}, ten, 2, 30, ErrHoldLimitExceeded},
		{"총 일수 초과(10+10+11=31>30)", []Hold{ten, ten}, Hold{From: "2026-11-01", To: "2026-11-11"}, 3, 30, ErrHoldLimitExceeded},
		{"경계값: 정확히 30일은 통과(10+10+10)", []Hold{ten, ten}, Hold{From: "2026-11-01", To: "2026-11-10"}, 3, 30, nil},
		{"상한 0 이하 = 무제한", []Hold{ten, ten, ten}, ten, 0, 0, nil},
		{"구간 자체가 깨지면 범위 에러", nil, Hold{From: "2026-09-10", To: "2026-09-01"}, 2, 30, ErrInvalidHoldRange},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := ValidateNewHold(c.existing, c.next, c.maxCount, c.maxDays)
			if c.wantErr == nil && err != nil {
				t.Fatalf("err = %v, want nil", err)
			}
			if c.wantErr != nil && err != c.wantErr {
				t.Fatalf("err = %v, want %v", err, c.wantErr)
			}
		})
	}
}

func TestValidateHoldWindow(t *testing.T) {
	existing := []Hold{{From: "2026-09-01", To: "2026-09-10"}}
	cases := []struct {
		name    string
		next    Hold
		wantErr bool
	}{
		{"과거 시작 거부(공짜 연장 방지)", Hold{From: "2026-08-01", To: "2026-08-05"}, true},
		{"유효기간 밖 시작 거부(만료 부활 방지)", Hold{From: "2027-01-01", To: "2027-01-05"}, true},
		{"기존 구간과 겹침 거부", Hold{From: "2026-09-05", To: "2026-09-12"}, true},
		{"경계 접촉(다음날 시작)은 허용", Hold{From: "2026-09-11", To: "2026-09-15"}, false},
		{"정상 미래 구간 허용", Hold{From: "2026-10-01", To: "2026-10-05"}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := ValidateHoldWindow(existing, c.next, "2026-08-17", "2026-12-31")
			if c.wantErr && err == nil {
				t.Fatal("err = nil, want error")
			}
			if !c.wantErr && err != nil {
				t.Fatalf("err = %v, want nil", err)
			}
		})
	}
}

func TestNormalizeHoldLimits(t *testing.T) {
	// v1.2 이전 문서(필드 부재 → 0)는 기본값으로 승격, -1(명시적 무제한)·양수는 유지.
	p := Policy{}
	p.NormalizeHoldLimits()
	if p.MaxHoldsPerPass != 2 || p.MaxHoldTotalDays != 30 {
		t.Errorf("0 승격 실패: %+v", p)
	}
	p = Policy{MaxHoldsPerPass: -1, MaxHoldTotalDays: 45}
	p.NormalizeHoldLimits()
	if p.MaxHoldsPerPass != -1 || p.MaxHoldTotalDays != 45 {
		t.Errorf("명시값이 훼손됨: %+v", p)
	}
}
