package domain

import (
	"testing"
	"time"
)

// 탈퇴 가명화의 골든 규칙(계약 v2.11). 여기 고정된 각 필드는 "왜 지우는가/왜 남기는가"의
// 근거가 서로 다르므로 한 필드씩 따로 검사한다 — 뭉뚱그린 DeepEqual 하나로 묶으면 나중에
// 필드가 추가될 때 그 필드의 판단이 누구의 검토도 거치지 않고 통과한다.
func TestMemberAnonymized(t *testing.T) {
	visited := time.Date(2026, 8, 1, 3, 0, 0, 0, time.UTC)
	signed := time.Date(2026, 7, 1, 3, 0, 0, 0, time.UTC)
	at := time.Date(2026, 8, 25, 5, 0, 0, 0, time.UTC)

	orig := Member{
		ID:        "m_000001",
		Name:      "김민지",
		Phone:     "010-1234-5678",
		Channel:   "인스타",
		TrainerID: "t1",
		Flags:     []MemberFlag{{Type: FlagInjury, Note: "우측 어깨 회전근개"}},
		Consent: Consent{
			General: true, Sensitive: true, SignedAt: &signed,
		},
		AppLinked:   true,
		Status:      MemberStatusActive,
		LastVisitAt: &visited,
		BodyPoses:   []BodyPose{{Key: "stand", Label: "차렷"}},
	}

	got := orig.Anonymized(at)

	// ---- 보존: 원장·결제·계약이 조인하는 가명 키 ----
	if got.ID != "m_000001" {
		t.Errorf("ID는 보존해야 한다(원장·결제·계약의 조인 키 = 가명): got %q", got.ID)
	}

	// ---- 파기: 사람을 가리키는 것 ----
	if got.Name != WithdrawnMemberName {
		t.Errorf("Name = %q, want %q(고정 라벨 — 식별자가 아니다)", got.Name, WithdrawnMemberName)
	}
	// **이 검사가 이번 설계의 급소다.** 번호가 남으면 FindMemberByPhone이 계속 매칭해
	// 같은 번호로 재가입할 때 join/match가 탈퇴 레코드로 되돌려 붙인다(탈퇴 무효화).
	if got.Phone != "" {
		t.Errorf("Phone = %q, want \"\" — 번호가 남으면 재가입 시 탈퇴 레코드로 되돌아 붙는다", got.Phone)
	}
	if got.Channel != "" {
		t.Errorf("Channel = %q, want \"\"(진입경로는 보존 근거가 없다)", got.Channel)
	}
	if len(got.Flags) != 0 {
		t.Errorf("Flags = %v, want 빈 배열 — 부상 메모는 건강 관련 정보다", got.Flags)
	}
	if got.Flags == nil {
		t.Error("Flags는 nil이 아니라 []여야 한다(직렬화 계약 v1.3: 배열 필드는 항상 [])")
	}
	if got.LastVisitAt != nil {
		t.Error("LastVisitAt은 방문 이력이다 — 보존 근거가 없다")
	}
	if got.BodyPoses != nil {
		t.Error("BodyPoses는 사진과 함께 사라진다(nil = 센터 기본 — 저장 상태를 되돌린다)")
	}
	if got.AppLinked {
		t.Error("AppLinked는 false여야 한다 — 앱 연결이 끊긴 상태다")
	}

	// ---- 동의: 전이 시각까지 비운다 ----
	if got.Consent != (Consent{}) {
		t.Errorf("Consent = %+v, want 제로값 — 탈퇴가 동의 철회의 종국이다", got.Consent)
	}
	if got.Consent.SensitiveConsentValid() {
		t.Error("탈퇴 회원의 민감정보 동의가 유효로 남으면 안 된다(새 사진·인바디 쓰기가 열린다)")
	}

	// ---- 담당 회수 ----
	if got.TrainerID != "" {
		t.Errorf("TrainerID = %q, want \"\" — 탈퇴 회원이 코치의 퇴사를 막으면 안 된다", got.TrainerID)
	}

	// ---- 상태 전이 ----
	if got.Status != MemberStatusWithdrawn {
		t.Errorf("Status = %q, want %q", got.Status, MemberStatusWithdrawn)
	}
	if got.WithdrawnAt == nil || !got.WithdrawnAt.Equal(at) {
		t.Errorf("WithdrawnAt = %v, want %v(서버 기록)", got.WithdrawnAt, at)
	}

	// ---- 순수성: 원본을 건드리지 않는다 ----
	if orig.Name != "김민지" || orig.Phone != "010-1234-5678" || len(orig.Flags) != 1 {
		t.Errorf("Anonymized는 순수해야 한다 — 원본이 변형됐다: %+v", orig)
	}
	if orig.Consent.SignedAt != &signed {
		t.Error("원본 Consent의 포인터가 바뀌었다")
	}
}

// 이미 탈퇴한 회원을 다시 가명화해도 결과가 같아야 한다(재시도 멱등) — 단 WithdrawnAt은
// **최초 시각을 보존**한다. 파기 시점은 보존기간 계산의 기준이라 재시도가 미래로 밀면 안 된다.
func TestMemberAnonymizedIsIdempotent(t *testing.T) {
	first := time.Date(2026, 8, 25, 5, 0, 0, 0, time.UTC)
	second := first.Add(24 * time.Hour)

	once := Member{ID: "m_1", Name: "김민지", Phone: "010-0000-0000", Status: MemberStatusActive}.Anonymized(first)
	twice := once.Anonymized(second)

	if twice.WithdrawnAt == nil || !twice.WithdrawnAt.Equal(first) {
		t.Errorf("WithdrawnAt = %v, want %v — 재시도가 파기 시점을 미래로 밀면 보존기간 기산점이 흔들린다",
			twice.WithdrawnAt, first)
	}
	if twice.Name != WithdrawnMemberName || twice.Phone != "" || twice.Status != MemberStatusWithdrawn {
		t.Errorf("두 번째 가명화 결과가 첫 번째와 다르다: %+v", twice)
	}
}

func TestMemberIsWithdrawn(t *testing.T) {
	for _, tc := range []struct {
		status string
		want   bool
	}{
		{MemberStatusActive, false},
		{MemberStatusDormant, false},
		{MemberStatusWithdrawn, true},
		{"", false}, // 필드 부재 = 구 문서 → active 취급(v2.0 Staff.status와 동형)
	} {
		if got := (Member{Status: tc.status}).IsWithdrawn(); got != tc.want {
			t.Errorf("IsWithdrawn(status=%q) = %v, want %v", tc.status, got, tc.want)
		}
	}
}
