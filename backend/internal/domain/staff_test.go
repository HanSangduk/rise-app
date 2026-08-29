package domain

import (
	"errors"
	"strings"
	"testing"
	"time"
)

// v2.0의 배포 전제 그 자체: 기존 Firestore 문서에는 status가 없다. 로드 시 active로 승격되지
// 않으면 배포 순간 전 스태프가 퇴사자가 되고 예약·고정 스케줄 생성이 통째로 막힌다
// (v1.3 Policy.NormalizeHoldLimits와 같은 규약 — 마이그레이션 없이 동작해야 한다).
func TestStaffNormalizePromotesLegacyDocument(t *testing.T) {
	var legacy Staff // status·offdays·profile 전부 부재
	legacy.Normalize()

	if legacy.Status != StaffStatusActive {
		t.Errorf("status = %q, want active", legacy.Status)
	}
	if legacy.Offdays == nil || legacy.Profile.Specialties == nil ||
		legacy.Profile.Certifications == nil || legacy.Profile.Awards == nil {
		t.Errorf("배열 null 금지 규약 위반: %+v", legacy)
	}

	// 명시적 inactive는 그대로 유지된다 — 승격이 퇴사를 되돌리면 안 된다.
	now := time.Now().UTC()
	gone := Staff{Status: StaffStatusInactive, LeftAt: &now}
	gone.Normalize()
	if gone.Status != StaffStatusInactive || gone.LeftAt == nil {
		t.Errorf("inactive가 승격됨: %+v", gone)
	}
	// active인데 left_at이 남은 모순은 로드 시점에 정리한다.
	weird := Staff{Status: StaffStatusActive, LeftAt: &now}
	weird.Normalize()
	if weird.LeftAt != nil {
		t.Errorf("active인데 left_at이 남음: %+v", weird)
	}
}

// IsActive는 Normalize를 거치지 않은 값도 안전하게 읽어야 한다("inactive"만이 명시적 퇴사).
func TestStaffIsActiveTreatsMissingStatusAsActive(t *testing.T) {
	cases := map[string]bool{"": true, StaffStatusActive: true, StaffStatusInactive: false}
	for status, want := range cases {
		if got := (Staff{Status: status}).IsActive(); got != want {
			t.Errorf("IsActive(%q) = %v, want %v", status, got, want)
		}
	}
}

// 정정 요청은 "안 보냄"과 "빈 값"을 구분한다 — 이름만 고치는 요청이 정산 조건을 0으로
// 초기화하면 안 된다. 검증은 보낸 필드에만 건다.
func TestStaffUpdateValidate(t *testing.T) {
	str := func(v string) *string { return &v }

	valid := []StaffUpdate{
		{}, // 빈 요청 자체는 형식 위반이 아니다(호출부가 IsEmpty로 거른다)
		{Name: str("정혜린")},
		{Color: str("#abcdef")},
		{Role: str(RoleOwner)},
		{Payout: &Payout{Type: PayoutRate, Value: 0.5}},
	}
	for _, u := range valid {
		u.Normalize()
		if err := u.Validate(); err != nil {
			t.Errorf("정상 입력이 거부됨 %+v: %v", u, err)
		}
	}

	invalid := map[string]StaffUpdate{
		"이름 공백":       {Name: str("   ")},
		"이름 초과":       {Name: str(strings.Repeat("가", 41))},
		"색 형식":        {Color: str("red")},
		"색 대문자 아님":    {Color: str("#GGGGGG")},
		"색 빈 값":       {Color: str("")}, // 색은 지울 수 없다 — 그리드가 그릴 수 없다
		"role member": {Role: str(RoleMember)},
		"role 오타":     {Role: str("Owner")},
		"payout 범위":   {Payout: &Payout{Type: PayoutRate, Value: 1.5}},
	}
	for name, u := range invalid {
		u.Normalize()
		if err := u.Validate(); !errors.Is(err, ErrInvalidStaff) {
			t.Errorf("%s: err = %v, want ErrInvalidStaff", name, err)
		}
	}

	// Normalize가 표기를 접는다(StaffCreate와 같은 규칙) — "#ABCDEF"는 유효한 입력이다.
	u := StaffUpdate{Name: str("  정혜린  "), Color: str("#ABCDEF"), Role: str(" trainer ")}
	u.Normalize()
	if err := u.Validate(); err != nil {
		t.Fatalf("Normalize 후에도 거부됨: %v", err)
	}
	if *u.Name != "정혜린" || *u.Color != "#abcdef" || *u.Role != RoleTrainer {
		t.Errorf("Normalize 결과 = %q/%q/%q", *u.Name, *u.Color, *u.Role)
	}
	if u.IsEmpty() {
		t.Error("IsEmpty가 채워진 요청을 빈 것으로 봄")
	}
	if !(StaffUpdate{}).IsEmpty() {
		t.Error("IsEmpty가 빈 요청을 못 알아봄")
	}
}
