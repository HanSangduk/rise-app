package domain

import (
	"math"
	"testing"
	"time"
)

// 골든값(API계약_v1.md·설계03 §14 R10): 재등록 2/8+1/6+1/6=4/20=20%.
func TestCombineReregGolden(t *testing.T) {
	n, d := CombineRereg([2]int{2, 8}, [2]int{1, 6}, [2]int{1, 6})
	if n != 4 || d != 20 {
		t.Fatalf("CombineRereg = (%d,%d), want (4,20)", n, d)
	}
	if rate := Rate(n, d); math.Abs(rate-0.20) > 1e-9 {
		t.Errorf("Rate(4,20) = %v, want 0.20", rate)
	}
}

func TestRateZeroDenominatorSafe(t *testing.T) {
	if Rate(5, 0) != 0 {
		t.Error("분모 0이면 0을 반환해야 함(안전)")
	}
}

func TestLongAbsent(t *testing.T) {
	now := time.Date(2026, 8, 17, 0, 0, 0, 0, KST)
	old := now.AddDate(0, 0, -61)
	if !LongAbsent(&old, now, 60) {
		t.Error("61일 전 방문 = 장기미출석(60일 기준)이어야 함")
	}
	recent := now.AddDate(0, 0, -10)
	if LongAbsent(&recent, now, 60) {
		t.Error("10일 전 방문 = 장기미출석 아니어야 함")
	}
	if !LongAbsent(nil, now, 60) {
		t.Error("방문기록 없음도 장기미출석 취급해야 함")
	}
}

func TestExpiringSoon(t *testing.T) {
	now := time.Date(2026, 8, 17, 0, 0, 0, 0, KST)
	if !ExpiringSoon("2026-08-20", now, 7) {
		t.Error("3일 후 만료는 7일 이내 임박이어야 함")
	}
	if ExpiringSoon("2026-09-30", now, 7) {
		t.Error("40일 넘게 남은 건 임박 아님")
	}
	if ExpiringSoon("2026-08-10", now, 7) {
		t.Error("이미 만료된 건 '임박'이 아님(별도 만료 처리 대상)")
	}
}
