package domain

import "testing"

func TestLedgerSum(t *testing.T) {
	entries := []Ledger{
		{Delta: 20, Reason: ReasonIssue},
		{Delta: -1, Reason: ReasonComplete},
		{Delta: -1, Reason: ReasonComplete},
		{Delta: 1, Reason: ReasonRevert},
	}
	if got := Sum(entries); got != 19 {
		t.Errorf("Sum = %d, want 19", got)
	}
}

func TestLedgerSumEmpty(t *testing.T) {
	if Sum(nil) != 0 {
		t.Error("빈 원장의 합은 0이어야 함")
	}
}
