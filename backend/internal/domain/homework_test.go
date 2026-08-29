package domain

import "testing"

func TestResolveTargetsExcludesInjuryForMyMembers(t *testing.T) {
	members := []Member{
		{ID: "m1", Flags: []MemberFlag{{Type: FlagInjury, Note: "무릎"}}},
		{ID: "m2"},
	}
	targets, excluded := ResolveTargets(HwScopeMyMembers, []string{"m1", "m2"}, members, nil)
	if len(targets) != 1 || targets[0] != "m2" {
		t.Errorf("targets = %v, want [m2]", targets)
	}
	if len(excluded) != 1 || excluded[0] != "m1" {
		t.Errorf("excluded = %v, want [m1]", excluded)
	}
}

func TestResolveTargetsOverrideIncludesInjured(t *testing.T) {
	members := []Member{{ID: "m1", Flags: []MemberFlag{{Type: FlagInjury}}}}
	targets, excluded := ResolveTargets(HwScopeMyMembers, []string{"m1"}, members, map[string]bool{"m1": true})
	if len(targets) != 1 || len(excluded) != 0 {
		t.Errorf("수동 포함 오버라이드가 반영되어야 함: targets=%v excluded=%v", targets, excluded)
	}
}

func TestResolveTargetsIndividualSkipsInjuryFilter(t *testing.T) {
	members := []Member{{ID: "m1", Flags: []MemberFlag{{Type: FlagInjury}}}}
	targets, excluded := ResolveTargets(HwScopeIndividual, []string{"m1"}, members, nil)
	if len(targets) != 1 || len(excluded) != 0 {
		t.Errorf("individual 배정은 부상 필터 미적용: targets=%v excluded=%v", targets, excluded)
	}
}

func TestResolveTargetsCenterNoticeExcludesInjury(t *testing.T) {
	members := []Member{
		{ID: "m1", Flags: []MemberFlag{{Type: FlagInjury}}},
		{ID: "m2"}, {ID: "m3"},
	}
	targets, excluded := ResolveTargets(HwScopeCenterNotice, []string{"m1", "m2", "m3"}, members, nil)
	if len(excluded) != 1 || excluded[0] != "m1" {
		t.Errorf("center_notice도 부상 제외를 유지해야 함(R5): excluded=%v", excluded)
	}
	if len(targets) != 2 {
		t.Errorf("targets = %v, want 2명", targets)
	}
}
