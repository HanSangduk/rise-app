package api

// 직원 생애주기(계약 v2.0) 회귀 테스트. 여기서 고정하는 것들의 성격이 서로 다르다:
//
//   - 락아웃 가드(자기 자신·마지막 활성 owner·강등 우회): 뚫리면 **고객이 자력으로 복구할 수
//     없다**. UserIndex를 쓰는 API가 전부 owner 전용이라 활성 owner 0명 = 영구 데드락이고,
//     남는 복구 경로는 Firestore 직접 편집뿐이다. 이 파일에서 가장 비싼 회귀 가드다.
//   - 이관→퇴사 여정: 두 기능의 "담당" 정의가 어긋나면 이관을 다 해도 퇴사가 영원히 409가 된다.
//   - status 승격: 기존 Firestore 문서를 마이그레이션하지 않고 배포한다는 전제 그 자체다.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// seedStaff — Staff 레코드 + UserIndex를 직접 심는다(초대 플로우를 거치지 않는 지름길 —
// 이 파일의 관심사는 온보딩이 아니라 그 뒤의 생애주기다).
func seedStaff(t *testing.T, s *Service, uid, role, name string) *domain.Staff {
	t.Helper()
	ctx := context.Background()
	st := &domain.Staff{
		UID: uid, Role: role, Name: name, Color: "#60a5fa",
		Status: domain.StaffStatusActive, Offdays: []string{},
	}
	if err := s.store.SaveStaff(ctx, testCenter, st); err != nil {
		t.Fatalf("SaveStaff(%s): %v", uid, err)
	}
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{UID: uid, Role: role, CenterID: testCenter}); err != nil {
		t.Fatalf("SaveUserIndex(%s): %v", uid, err)
	}
	return st
}

// seedMemberFor — 특정 트레이너 담당의 회원 + 활성 패스(원장 issue 포함).
func seedMemberFor(t *testing.T, s *Service, trainerUID, name string, sessions int) (*domain.Member, *domain.Pass) {
	t.Helper()
	ctx := context.Background()
	kst := time.Now().In(domain.KST)
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: name, Phone: "010-0000-0000", TrainerID: trainerUID, Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatalf("CreateMember: %v", err)
	}
	pass, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: trainerUID, Product: "PT", PaidAmount: 1_000_000,
		TotalSessions: sessions,
		ValidFrom:     kst.AddDate(0, 0, -1).Format("2006-01-02"),
		ValidUntil:    kst.AddDate(0, 0, 90).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatalf("CreatePass: %v", err)
	}
	return mem, pass
}

func containsID(list []string, want string) bool {
	for _, v := range list {
		if v == want {
			return true
		}
	}
	return false
}

// findBlockedBooking — blockers.bookings는 계약 v2.1부터 {id, slot_key} 객체 배열이다.
// id로 한 건을 집어 슬롯키까지 검증할 수 있게 한다.
func findBlockedBooking(list []BlockedBooking, id string) (BlockedBooking, bool) {
	for _, b := range list {
		if b.ID == id {
			return b, true
		}
	}
	return BlockedBooking{}, false
}

func putJSON(t *testing.T, r http.Handler, path, uid, role, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPut, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Dev-Uid", uid)
	req.Header.Set("X-Dev-Role", role)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

// ---- 락아웃 3중 가드 ----

// **가드가 없으면 센터가 잠긴다**: 활성 owner가 0명이 되면 UserIndex를 되돌릴 API가 owner
// 전용이라 아무도 복구할 수 없다. 비활성화·강등 두 경로 모두 같은 카운트를 봐야 한다.
func TestLastActiveOwnerCannotBeRemoved(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	// 호출자(owner1)는 인증상 owner지만 Staff 레코드가 없다(수동 시딩 환경 — auth는 UserIndex만 본다).
	// 활성 owner 레코드는 owner2 하나뿐이므로 owner2가 사라지면 활성 owner는 0명이 된다.
	seedStaff(t, s, "owner2", domain.RoleOwner, "공동대표")

	// ① 비활성화로 없애기 → 409
	if _, err := s.DeactivateStaff(ctx, ownerP(), "owner2", ""); !errors.Is(err, ErrConflict) {
		t.Fatalf("마지막 활성 owner 비활성화 err = %v, want ErrConflict(409)", err)
	}
	// ② 강등으로 우회 → 같은 카운트에 걸려 409(비활성화만 막으면 뚫리는 뒷문)
	trainer := domain.RoleTrainer
	if _, err := s.UpdateStaff(ctx, ownerP(), "owner2", domain.StaffUpdate{Role: &trainer}); !errors.Is(err, ErrConflict) {
		t.Fatalf("마지막 활성 owner 강등 err = %v, want ErrConflict(409)", err)
	}
	// 둘 다 거부됐으니 레코드도 인덱스도 그대로여야 한다(부분 적용 금지).
	st, err := s.store.GetStaff(ctx, testCenter, "owner2")
	if err != nil || st.Role != domain.RoleOwner || !st.IsActive() {
		t.Fatalf("거부됐는데 레코드가 바뀜: %+v, err=%v", st, err)
	}
	idx, err := s.store.GetUserIndex(ctx, "owner2")
	if err != nil || idx.Role != domain.RoleOwner {
		t.Fatalf("거부됐는데 UserIndex가 바뀜: %+v, err=%v", idx, err)
	}

	// 활성 owner가 둘이면 한 명은 정리할 수 있다(가드가 과하게 잠그지 않았는지 대조).
	seedStaff(t, s, "owner3", domain.RoleOwner, "또다른대표")
	if _, err := s.DeactivateStaff(ctx, ownerP(), "owner2", ""); err != nil {
		t.Fatalf("활성 owner 2명 중 1명 비활성화가 거부됨: %v", err)
	}
}

// 자기 자신은 마지막 owner가 아니어도 못 내린다 — 비활성화·강등 즉시 owner 전용 API를 잃어
// 스스로 되돌릴 수 없고, 실수를 깨달았을 땐 이미 호출 자격이 없다.
func TestOwnerCannotRemoveSelf(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "owner2", domain.RoleOwner, "공동대표") // 다른 활성 owner가 있어도 막힌다

	if _, err := s.DeactivateStaff(ctx, ownerP(), "owner1", ""); !errors.Is(err, errBadRequest) {
		t.Fatalf("본인 비활성화 err = %v, want 400", err)
	}
	trainer := domain.RoleTrainer
	if _, err := s.UpdateStaff(ctx, ownerP(), "owner1", domain.StaffUpdate{Role: &trainer}); !errors.Is(err, errBadRequest) {
		t.Fatalf("본인 강등 err = %v, want 400", err)
	}
	st, _ := s.store.GetStaff(ctx, testCenter, "owner1")
	if st.Role != domain.RoleOwner || !st.IsActive() {
		t.Fatalf("본인 레코드가 바뀜: %+v", st)
	}
	// 이름 정정 같은 본인 수정은 계속 가능해야 한다(가드가 PUT 전체를 잠그면 안 된다).
	name := "박관장(정정)"
	if got, err := s.UpdateStaff(ctx, ownerP(), "owner1", domain.StaffUpdate{Name: &name}); err != nil || got.Name != name {
		t.Fatalf("본인 이름 정정 = %+v, err = %v", got, err)
	}
}

// ---- 퇴사 선행 조건(blockers) ----

// 담당 회원·활성 패스·미만료 고정스케줄·미래 예약이 남아 있으면 409 + blockers에 **실제 ID**.
// 이관 없이 비활성화하면 담당 회원이 "목록엔 미배정으로 보이는데 미배정 필터·KPI엔 잡히지 않는"
// 발견 불가능 상태가 된다.
func TestDeactivateBlockedByAssignments(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")

	mem, pass := seedMemberFor(t, s, "t1", "김민지", 10)
	recID, err := s.store.CreateRecurring(ctx, testCenter, &domain.Recurring{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID, Days: []string{"mon"}, Hour: 10,
	})
	if err != nil {
		t.Fatal(err)
	}
	bk, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(3, 10), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}

	_, err = s.DeactivateStaff(ctx, ownerP(), "t1", "")
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("선행 조건 위반 err = %v, want ErrConflict(409)", err)
	}
	var blocked *staffBlockedError
	if !errors.As(err, &blocked) {
		t.Fatalf("blockers를 실은 에러가 아님: %T %v", err, err)
	}
	b := blocked.blockers
	if !containsID(b.Members, mem.ID) {
		t.Errorf("blockers.members = %v, want %s 포함", b.Members, mem.ID)
	}
	if !containsID(b.Passes, pass.ID) {
		t.Errorf("blockers.passes = %v, want %s 포함", b.Passes, pass.ID)
	}
	if !containsID(b.Recurrings, recID) {
		t.Errorf("blockers.recurrings = %v, want %s 포함", b.Recurrings, recID)
	}
	// v2.1: bookings는 {id, slot_key} — 어드민이 "언제 수업인지"를 재조회 없이 그린다.
	blockedBk, ok := findBlockedBooking(b.Bookings, bk.ID)
	if !ok {
		t.Errorf("blockers.bookings = %+v, want %s 포함", b.Bookings, bk.ID)
	} else if blockedBk.SlotKey != bk.SlotKey {
		t.Errorf("blockers.bookings[%s].slot_key = %q, want %q", bk.ID, blockedBk.SlotKey, bk.SlotKey)
	}
	// 409였으니 상태는 그대로 재직이어야 한다.
	if st, _ := s.store.GetStaff(ctx, testCenter, "t1"); !st.IsActive() {
		t.Errorf("409인데 inactive로 바뀜: %+v", st)
	}
}

// 만료·환불된 패스와 지난 고정 스케줄은 퇴사를 막지 않는다 — 미래 의무가 없고, 이관 대상에
// 넣으면 과거 정산 귀속(by_trainer revenue는 Pass.trainer_id를 탄다)이 소급 이전된다.
func TestDeactivateIgnoresSettledHistory(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	mem, pass := seedMemberFor(t, s, "t1", "김민지", 10)

	// 담당 해제 + 패스는 만료 처리 + 이미 끝난 고정 스케줄만 남긴다.
	mem.TrainerID = ""
	if _, err := s.store.SaveMember(ctx, testCenter, mem); err != nil {
		t.Fatal(err)
	}
	pass.Status = domain.PassStatusExpired
	if err := s.store.UpdatePass(ctx, testCenter, pass); err != nil {
		t.Fatal(err)
	}
	past := time.Now().In(domain.KST).AddDate(0, 0, -10).Format("2006-01-02")
	if _, err := s.store.CreateRecurring(ctx, testCenter, &domain.Recurring{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID, Days: []string{"mon"}, Hour: 10, Until: past,
	}); err != nil {
		t.Fatal(err)
	}

	st, err := s.DeactivateStaff(ctx, ownerP(), "t1", "")
	if err != nil {
		t.Fatalf("정산 끝난 이력만 남았는데 퇴사가 막힘: %v", err)
	}
	if st.Status != domain.StaffStatusInactive || st.LeftAt == nil {
		t.Fatalf("staff = %+v, want inactive + left_at", st)
	}
	// 과거 패스의 담당은 그대로 t1이어야 한다(정산 비교표 보존).
	got, _ := s.store.GetPass(ctx, testCenter, pass.ID)
	if got.TrainerID != "t1" {
		t.Errorf("만료 패스의 담당이 바뀜: %s", got.TrainerID)
	}
}

// ---- 이관 → 퇴사 전체 여정 ----

// 계약 v2.0의 핵심 동선: 이관 한 번으로 네 가지 선행 조건이 전부 비고, 그다음 퇴사가 통과한다.
// 두 기능의 "담당" 정의가 어긋나면 이관을 다 해도 퇴사가 영원히 409가 된다.
func TestTransferThenDeactivateJourney(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	seedStaff(t, s, "t2", domain.RoleTrainer, "김태오")

	mem, pass := seedMemberFor(t, s, "t1", "김민지", 10)
	if _, err := s.store.CreateRecurring(ctx, testCenter, &domain.Recurring{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID, Days: []string{"mon"}, Hour: 10,
	}); err != nil {
		t.Fatal(err)
	}
	bk, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(3, 10), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}

	to := "t2"
	res, err := s.TransferStaff(ctx, ownerP(), "t1", &to)
	if err != nil {
		t.Fatalf("TransferStaff: %v", err)
	}
	want := StaffTransferMoved{Members: 1, Passes: 1, Recurrings: 1, Bookings: 1}
	if res.Moved != want {
		t.Fatalf("moved = %+v, want %+v", res.Moved, want)
	}
	if len(res.Conflicts) != 0 {
		t.Fatalf("conflicts = %+v, want []", res.Conflicts)
	}

	// 네 축이 전부 인수자에게 넘어갔다(슬롯 teams 사본까지).
	if got, _ := s.store.GetMember(ctx, testCenter, mem.ID); got.TrainerID != "t2" {
		t.Errorf("member.trainer_id = %q", got.TrainerID)
	}
	if got, _ := s.store.GetPass(ctx, testCenter, pass.ID); got.TrainerID != "t2" {
		t.Errorf("pass.trainer_id = %q", got.TrainerID)
	}
	if got, _ := s.store.GetBooking(ctx, testCenter, bk.ID); got.TrainerID != "t2" {
		t.Errorf("booking.trainer_id = %q", got.TrainerID)
	}
	slot, err := s.store.GetSlot(ctx, testCenter, bk.SlotKey)
	if err != nil {
		t.Fatal(err)
	}
	for _, team := range slot.Teams {
		if team.BookingID == bk.ID && team.TrainerID != "t2" {
			t.Errorf("slot.teams 사본이 안 따라옴: %+v", team)
		}
	}
	recs, _ := s.store.ListRecurrings(ctx, testCenter)
	for _, r := range recs {
		if r.TrainerID != "t2" {
			t.Errorf("recurring.trainer_id = %q", r.TrainerID)
		}
	}

	// 그리고 퇴사가 통과한다.
	st, err := s.DeactivateStaff(ctx, ownerP(), "t1", "")
	if err != nil {
		t.Fatalf("이관 후에도 퇴사가 막힘: %v", err)
	}
	if st.Status != domain.StaffStatusInactive || st.LeftAt == nil {
		t.Fatalf("staff = %+v, want inactive + left_at", st)
	}
	// 즉시 차단: 인증이 요청마다 읽는 UserIndex가 강등돼 있어야 한다(캐시가 없다).
	idx, err := s.store.GetUserIndex(ctx, "t1")
	if err != nil || idx.Role != domain.RoleMember {
		t.Fatalf("UserIndex = %+v, err = %v — 강등 안 됨(즉시 차단 실패)", idx, err)
	}
	// 목록에선 계속 보인다(이름 해석을 잃으면 3계층 uid 참조가 붕괴한다).
	list, _ := s.ListStaff(ctx, ownerP())
	found := false
	for _, item := range list {
		if item.UID == "t1" {
			found = true
			if item.Status != domain.StaffStatusInactive {
				t.Errorf("목록의 status = %q", item.Status)
			}
		}
	}
	if !found {
		t.Errorf("GET /v1/staff에서 퇴사자가 사라짐 — 이름 해석 붕괴")
	}
}

// 이관은 패스마다 원장에 reason="transfer"를 남기고, **delta 0이라 잔여 세션은 변하지 않는다**
// (설계03 §9 — "왜 이 패스의 담당이 바뀌었나"에 원장이 답한다).
func TestTransferWritesLedgerWithoutChangingRemaining(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	seedStaff(t, s, "t2", domain.RoleTrainer, "김태오")

	memA, passA := seedMemberFor(t, s, "t1", "회원A", 10)
	_, passB := seedMemberFor(t, s, "t1", "회원B", 4)

	// 한 건은 미리 소진해 둔다 — 잔여가 총회차와 같은 값이라 "안 변했다"가 우연히 맞는 것을 막는다.
	bk, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 9), MemberID: memA.ID, PassID: passA.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteBooking(ctx, ownerP(), bk.ID); err != nil {
		t.Fatal(err)
	}
	before := map[string]int{}
	for _, ps := range []*domain.Pass{passA, passB} {
		cp := *ps
		if err := s.hydratePassRemaining(ctx, testCenter, &cp); err != nil {
			t.Fatal(err)
		}
		before[ps.ID] = cp.Remaining
	}
	if before[passA.ID] != 9 || before[passB.ID] != 4 {
		t.Fatalf("사전 조건 어긋남: %+v", before)
	}

	to := "t2"
	res, err := s.TransferStaff(ctx, ownerP(), "t1", &to)
	if err != nil {
		t.Fatal(err)
	}
	if res.Moved.Passes != 2 {
		t.Fatalf("moved.passes = %d, want 2", res.Moved.Passes)
	}

	for _, ps := range []*domain.Pass{passA, passB} {
		entries, err := s.store.ListLedger(ctx, testCenter, ps.MemberID, ps.ID)
		if err != nil {
			t.Fatal(err)
		}
		transfers := 0
		for _, e := range entries {
			if e.Reason != domain.ReasonTransfer {
				continue
			}
			transfers++
			if e.Delta != 0 {
				t.Errorf("transfer 원장의 delta = %d, want 0(잔여를 건드리면 안 된다)", e.Delta)
			}
			if e.By != "owner1" {
				t.Errorf("transfer 원장의 by = %q, want owner1(행위자 기록)", e.By)
			}
		}
		if transfers != 1 {
			t.Errorf("패스 %s의 transfer 원장 = %d건, want 1", ps.ID, transfers)
		}
		if got := domain.Sum(entries); got != before[ps.ID] {
			t.Errorf("패스 %s 잔여 = %d, want %d(이관은 잔여를 바꾸지 않는다)", ps.ID, got, before[ps.ID])
		}
	}
}

// 인수자가 같은 슬롯에 이미 수업이 있으면 그 예약은 **옮기지 않고** conflicts로 보고한다 —
// 트레이너 동시 1건 규칙(R2)을 이관이 우회하면 슬롯 그리드가 이중 배정으로 깨진다.
// 남은 예약은 그대로 퇴사를 계속 막는다.
func TestTransferReportsSlotConflictsInsteadOfDoubleBooking(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	seedStaff(t, s, "t2", domain.RoleTrainer, "김태오")

	memA, passA := seedMemberFor(t, s, "t1", "회원A", 10)
	memB, passB := seedMemberFor(t, s, "t2", "회원B", 10)

	slot := slotKeyDaysAhead(2, 19)
	conflicting, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slot, MemberID: memA.ID, PassID: passA.ID, // t1 수업
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slot, MemberID: memB.ID, PassID: passB.ID, // 같은 슬롯의 t2 수업
	}); err != nil {
		t.Fatal(err)
	}
	// 충돌하지 않는 예약도 하나 — 충돌 하나 때문에 전체가 멈추면 안 된다.
	safe, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(2, 20), MemberID: memA.ID, PassID: passA.ID,
	})
	if err != nil {
		t.Fatal(err)
	}

	to := "t2"
	res, err := s.TransferStaff(ctx, ownerP(), "t1", &to)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Conflicts) != 1 || res.Conflicts[0].BookingID != conflicting.ID || res.Conflicts[0].SlotKey != slot {
		t.Fatalf("conflicts = %+v, want [{%s %s}]", res.Conflicts, conflicting.ID, slot)
	}
	if res.Moved.Bookings != 1 {
		t.Errorf("moved.bookings = %d, want 1(충돌 1건 제외)", res.Moved.Bookings)
	}
	if got, _ := s.store.GetBooking(ctx, testCenter, conflicting.ID); got.TrainerID != "t1" {
		t.Errorf("충돌 예약이 옮겨짐: trainer_id = %q(동시 1건 규칙 우회)", got.TrainerID)
	}
	if got, _ := s.store.GetBooking(ctx, testCenter, safe.ID); got.TrainerID != "t2" {
		t.Errorf("충돌 아닌 예약이 안 옮겨짐: trainer_id = %q", got.TrainerID)
	}
	// 슬롯에 t2가 두 팀 들어가 있으면 안 된다.
	sl, _ := s.store.GetSlot(ctx, testCenter, slot)
	t2Teams := 0
	for _, team := range sl.Teams {
		if team.TrainerID == "t2" {
			t2Teams++
		}
	}
	if t2Teams != 1 {
		t.Errorf("슬롯 %s의 t2 팀 수 = %d, want 1(이중 배정)", slot, t2Teams)
	}
	// 남은 예약이 퇴사를 계속 막는다.
	_, err = s.DeactivateStaff(ctx, ownerP(), "t1", "")
	var blocked *staffBlockedError
	if !errors.As(err, &blocked) {
		t.Fatalf("남은 충돌 예약이 퇴사를 못 막음: err = %v", err)
	}
	left, ok := findBlockedBooking(blocked.blockers.Bookings, conflicting.ID)
	if !ok || left.SlotKey != slot {
		t.Fatalf("blockers.bookings = %+v, want {%s %s} 포함", blocked.blockers.Bookings, conflicting.ID, slot)
	}
}

// to_uid=""는 "미배정으로 회수"라는 1급 상태다. 반대로 **필드 누락**은 거부한다 —
// 빈 바디 하나로 담당이 통째로 날아가면 안 된다.
func TestTransferToUnassignedAndMissingField(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	seedStaff(t, s, "t9", domain.RoleTrainer, "퇴사자")
	mem, pass := seedMemberFor(t, s, "t1", "김민지", 10)

	if _, err := s.TransferStaff(ctx, ownerP(), "t1", nil); !errors.Is(err, errBadRequest) {
		t.Fatalf("to_uid 누락 err = %v, want 400", err)
	}
	self := "t1"
	if _, err := s.TransferStaff(ctx, ownerP(), "t1", &self); !errors.Is(err, errBadRequest) {
		t.Fatalf("자기 자신에게 이관 err = %v, want 400", err)
	}
	// 인수자가 퇴사자면 409 — 문제를 옆으로 옮길 뿐이다.
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t9", ""); err != nil {
		t.Fatal(err)
	}
	gone := "t9"
	if _, err := s.TransferStaff(ctx, ownerP(), "t1", &gone); !errors.Is(err, ErrConflict) {
		t.Fatalf("퇴사자에게 이관 err = %v, want 409", err)
	}
	ghost := "nope"
	if _, err := s.TransferStaff(ctx, ownerP(), "t1", &ghost); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("없는 인수자 err = %v, want 404", err)
	}
	// 아무것도 이관되지 않았어야 한다(거부 경로가 부분 적용을 남기지 않는다).
	if got, _ := s.store.GetMember(ctx, testCenter, mem.ID); got.TrainerID != "t1" {
		t.Fatalf("거부됐는데 담당이 바뀜: %q", got.TrainerID)
	}

	// 미배정 회수는 통과한다.
	empty := ""
	res, err := s.TransferStaff(ctx, ownerP(), "t1", &empty)
	if err != nil {
		t.Fatalf("미배정 회수: %v", err)
	}
	if res.Moved.Members != 1 || res.Moved.Passes != 1 {
		t.Fatalf("moved = %+v", res.Moved)
	}
	if got, _ := s.store.GetMember(ctx, testCenter, mem.ID); got.TrainerID != "" {
		t.Errorf("member.trainer_id = %q, want \"\"(미배정)", got.TrainerID)
	}
	if got, _ := s.store.GetPass(ctx, testCenter, pass.ID); got.TrainerID != "" {
		t.Errorf("pass.trainer_id = %q, want \"\"", got.TrainerID)
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); err != nil {
		t.Fatalf("미배정 회수 후 퇴사가 막힘: %v", err)
	}
}

// ---- 발급(POST /v1/passes)도 담당 코치의 실존·재직을 본다(계약 v2.1) ----

// v2.0은 예약·고정 스케줄만 막아 **발급 경로가 열려 있었다**: 퇴사자 담당으로 회원권을 새로
// 끊으면 그 즉시 그 사람의 퇴사 선행 조건(active 패스)이 되살아나 이관→퇴사가 무한 반복된다.
//
// 동시에 과잉 차단도 막는다 — 현직 코치와 "미배정"(빈 trainer_id, TransferStaff의 to_uid=""
// 회수가 만드는 1급 상태)은 반드시 통과해야 한다. 여기서 잘못 조이면 발급 자체가 멈춘다.
func TestCreatePassChecksTrainerExistsAndActive(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	kst := time.Now().In(domain.KST)

	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "김민지", Phone: "010-1234-5678", TrainerID: "t1", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	issue := func(trainerID string) (*domain.Pass, error) {
		return s.CreatePass(ctx, ownerP(), PassCreateRequest{
			MemberID: mem.ID, TrainerID: trainerID, Product: "PT 10회", PaidAmount: 550_000,
			TotalSessions: 10,
			ValidFrom:     kst.AddDate(0, 0, -1).Format("2006-01-02"),
			ValidUntil:    kst.AddDate(0, 0, 90).Format("2006-01-02"),
		})
	}

	// ① 현직 코치 — 통과(과잉 차단 방지).
	activePass, err := issue("t1")
	if err != nil {
		t.Fatalf("현직 코치 발급이 막힘: %v", err)
	}

	// ② 미존재 uid — 400. 404가 아니다: 없는 건 요청 대상(pass)이 아니라 그 안의 필드 값이다.
	_, err = issue("t-오타")
	if !errors.Is(err, errBadRequest) {
		t.Fatalf("미존재 코치 발급 err = %v, want 400", err)
	}
	if errors.Is(err, store.ErrNotFound) {
		t.Errorf("미존재 코치가 404로 새어나감(계약 v2.1은 400): %v", err)
	}

	// ③ 퇴사자 — 400 + **예약 거부와 같은 문구**. 3계층이 같은 상황에 다른 말을 하면 안 된다.
	st, err := s.store.GetStaff(ctx, testCenter, "t1")
	if err != nil {
		t.Fatal(err)
	}
	st.Status = domain.StaffStatusInactive
	if err := s.store.SaveStaff(ctx, testCenter, st); err != nil {
		t.Fatal(err)
	}
	_, passErr := issue("t1")
	if !errors.Is(passErr, errBadRequest) {
		t.Fatalf("퇴사자 발급 err = %v, want 400", passErr)
	}
	_, bookErr := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(4, 9), MemberID: mem.ID, PassID: activePass.ID,
	})
	if !errors.Is(bookErr, errBadRequest) {
		t.Fatalf("퇴사자 예약 err = %v, want 400(대칭 비교의 기준)", bookErr)
	}
	if userMessage(passErr) != userMessage(bookErr) {
		t.Errorf("거부 문구가 갈림: 발급 %q vs 예약 %q", userMessage(passErr), userMessage(bookErr))
	}

	// ④ 빈 trainer_id는 "미배정"이지 오타가 아니다 — 담당 없는 패스는 누구의 퇴사도 막지 않는다.
	if _, err := issue(""); err != nil {
		t.Fatalf("미배정 발급이 막힘(TransferStaff의 회수 상태와 모순): %v", err)
	}

	// ⑤ 거부된 발급이 고아 패스·계약을 남기면 안 된다(통과한 것은 ①·④ 두 건뿐).
	passes, err := s.store.ListPasses(ctx, testCenter)
	if err != nil {
		t.Fatal(err)
	}
	if len(passes) != 2 {
		t.Errorf("패스 %d건, want 2(거부된 발급이 저장됨): %+v", len(passes), passes)
	}
	contracts, err := s.store.ListContracts(ctx, testCenter, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(contracts) != 2 {
		t.Errorf("계약 %d건, want 2(거부된 발급의 유령 계약)", len(contracts))
	}
}

// ---- 회원 등록·담당 변경(POST/PUT /v1/members)도 같은 검증을 받는다(계약 v2.1) ----

// 발급만 막으면 루프는 안 닫힌다. 퇴사 선행 조건 ①이 "담당 회원 없음"이라 **회원 축이 더 싸고
// 앞선 우회로**다: 퇴사자에게 회원 한 명만 붙이면(돈도 안 든다) 이관→퇴사 여정이 처음으로
// 되돌아간다. 세 진입점(회원·발급·예약)이 같은 함수를 쓰는지, 거부 문구까지 같은지 본다.
//
// 함께 고정하는 것 — 과잉 차단 금지: 미배정("")은 1급 상태라 통과해야 하고, 트레이너의 자기
// 담당 강제도 그대로 살아 있어야 한다(강제 **뒤에** 검사하므로 검사 대상은 저장될 값이다.
// 그래서 트레이너 본인의 Staff 레코드는 실존해야 한다 — 발급 경로와 같은 전제다).
func TestMemberAssignmentChecksTrainer(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	seedStaff(t, s, "gone", domain.RoleTrainer, "김태오")
	if _, err := s.DeactivateStaff(ctx, ownerP(), "gone", ""); err != nil {
		t.Fatalf("담당 없는 코치 퇴사가 막힘: %v", err)
	}

	create := func(name, phone, trainerID string) (*domain.Member, error) {
		return s.CreateMember(ctx, ownerP(), &domain.Member{
			Name: name, Phone: phone, TrainerID: trainerID, Status: domain.MemberStatusActive,
		})
	}

	// ① 현직 코치 · ② 미배정("") — 둘 다 통과해야 한다(잘못 조이면 등록 자체가 멈춘다).
	mem, err := create("김민지", "010-1234-5678", "t1")
	if err != nil {
		t.Fatalf("현직 코치 담당 등록이 막힘: %v", err)
	}
	if _, err := create("미배정회원", "010-2222-3333", ""); err != nil {
		t.Fatalf("미배정 등록이 막힘(회수 상태와 모순): %v", err)
	}

	// ③ 미존재 uid — 400(404 아님: 없는 건 요청 대상이 아니라 그 안의 필드 값이다).
	_, err = create("오타회원", "010-4444-5555", "t-오타")
	if !errors.Is(err, errBadRequest) {
		t.Fatalf("미존재 코치 담당 등록 err = %v, want 400", err)
	}
	if errors.Is(err, store.ErrNotFound) {
		t.Errorf("미존재 코치가 404로 새어나감(계약 v2.1은 400): %v", err)
	}

	// ④ 퇴사자 — 400 + **발급 거부와 같은 문구**(같은 함수를 쓰는지의 실질 증거).
	_, memberErr := create("되살리기", "010-6666-7777", "gone")
	if !errors.Is(memberErr, errBadRequest) {
		t.Fatalf("퇴사자 담당 등록 err = %v, want 400 — 회원 축으로 루프가 열려 있다", memberErr)
	}
	_, passErr := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "gone", Product: "PT 10회", PaidAmount: 550_000, TotalSessions: 10,
		ValidFrom:  time.Now().In(domain.KST).AddDate(0, 0, -1).Format("2006-01-02"),
		ValidUntil: time.Now().In(domain.KST).AddDate(0, 0, 90).Format("2006-01-02"),
	})
	if userMessage(memberErr) != userMessage(passErr) {
		t.Errorf("거부 문구가 갈림: 회원 %q vs 발급 %q", userMessage(memberErr), userMessage(passErr))
	}

	// ⑤ 거부가 실제로 선행 조건을 막았는지 — 퇴사자 담당 회원이 하나도 남지 않아야 한다.
	assigned, err := s.store.ListMembers(ctx, testCenter, "gone", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(assigned) != 0 {
		t.Fatalf("퇴사자 담당 회원 %d명 — 퇴사 선행 조건이 되살아났다: %+v", len(assigned), assigned)
	}

	// ⑥ PUT 담당 변경도 같은 검사를 받는다(owner 경로).
	if _, err := s.UpdateMember(ctx, ownerP(), mem.ID, []byte(`{"trainer_id":"gone"}`)); !errors.Is(err, errBadRequest) {
		t.Fatalf("PUT으로 퇴사자 담당 지정 err = %v, want 400", err)
	}
	if _, err := s.UpdateMember(ctx, ownerP(), mem.ID, []byte(`{"trainer_id":"t-오타"}`)); !errors.Is(err, errBadRequest) {
		t.Fatalf("PUT으로 미존재 담당 지정 err = %v, want 400", err)
	}

	// ⑦ **담당이 안 바뀌는 PUT은 통과한다** — 머지 PUT이라 이름만 고치는 요청에도 기존
	// trainer_id가 실려 온다. 이미 어긋난 레코드(아래에서 t1을 강제로 inactive로 만든다)의
	// 이름조차 못 고치게 되면, 그 상태를 푸는 유일한 수단인 담당 변경 PUT까지 함께 막힌다.
	st, err := s.store.GetStaff(ctx, testCenter, "t1")
	if err != nil {
		t.Fatal(err)
	}
	st.Status = domain.StaffStatusInactive
	if err := s.store.SaveStaff(ctx, testCenter, st); err != nil { // 이관 누락으로 남은 상태를 재현
		t.Fatal(err)
	}
	got, err := s.UpdateMember(ctx, ownerP(), mem.ID, []byte(`{"name":"김민지(정정)"}`))
	if err != nil {
		t.Fatalf("담당 그대로인 이름 정정이 막힘 — 복구 경로가 닫힌다: %v", err)
	}
	if got.Name != "김민지(정정)" || got.TrainerID != "t1" {
		t.Errorf("머지 PUT 결과 = %+v", got)
	}
	// 그 상태에서 **현직 코치로 옮기는** 것은 언제나 가능해야 한다(이게 복구 그 자체다).
	seedStaff(t, s, "t2", domain.RoleTrainer, "이준호")
	if got, err := s.UpdateMember(ctx, ownerP(), mem.ID, []byte(`{"trainer_id":"t2"}`)); err != nil || got.TrainerID != "t2" {
		t.Fatalf("현직 코치로 이관 = %+v, err = %v", got, err)
	}

	// ⑧ 트레이너의 자기 담당 강제는 그대로다(바디의 다른 uid를 무시하고 본인으로 저장).
	self, err := s.CreateMember(ctx, Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter},
		&domain.Member{Name: "내회원", Phone: "010-8888-9999", TrainerID: "gone", Status: domain.MemberStatusActive})
	if err != nil {
		t.Fatalf("트레이너 본인 등록이 막힘: %v", err)
	}
	if self.TrainerID != "t2" {
		t.Errorf("trainer_id = %q, want t2(본인 강제) — 강제가 검증보다 앞서야 한다", self.TrainerID)
	}
}

// ---- inactive 스태프 앞으로는 새 일정을 잡을 수 없다 ----

// 없으면 퇴사 처리로 비운 선행 조건이 곧바로 다시 채워져 이관→퇴사 여정이 무한 반복된다
// (휴무일 거부와 같은 자리, 계약 v2.0).
func TestInactiveTrainerRejectsNewSchedule(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	mem, pass := seedMemberFor(t, s, "t1", "김민지", 10)

	// 담당을 비우고 퇴사 처리(정상 여정)한 뒤에도 패스에는 t1이 남을 수 있는 상황을 만든다:
	// 여기서는 퇴사만 시키고 패스의 담당은 t1 그대로 둔다(직접 상태 전이).
	st, err := s.store.GetStaff(ctx, testCenter, "t1")
	if err != nil {
		t.Fatal(err)
	}
	st.Status = domain.StaffStatusInactive
	if err := s.store.SaveStaff(ctx, testCenter, st); err != nil {
		t.Fatal(err)
	}

	_, err = s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(3, 11), MemberID: mem.ID, PassID: pass.ID,
	})
	if !errors.Is(err, errBadRequest) {
		t.Fatalf("퇴사자 예약 err = %v, want 400", err)
	}
	_, err = s.CreateRecurring(ctx, ownerP(), RecurringCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID, Days: []string{"mon"}, Hour: 11,
	})
	if !errors.Is(err, errBadRequest) {
		t.Fatalf("퇴사자 고정 스케줄 err = %v, want 400", err)
	}
	// 거부된 고정 스케줄이 유령 규칙으로 남으면 안 된다(규칙 저장 전에 막아야 한다).
	recs, _ := s.store.ListRecurrings(ctx, testCenter)
	if len(recs) != 0 {
		t.Errorf("400인데 규칙이 저장됨: %+v", recs)
	}

	// 복직하면 다시 잡힌다.
	if _, err := s.ReactivateStaff(ctx, ownerP(), "t1"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(3, 11), MemberID: mem.ID, PassID: pass.ID,
	}); err != nil {
		t.Fatalf("복직 후 예약이 막힘: %v", err)
	}
}

// ---- 재고용(퇴사자 재초대) ----

// 같은 이메일 = 같은 Firebase 계정 = 같은 uid라 재초대가 409로 막히면 **재고용이 영구 차단된다**.
// inactive는 "이미 등록된 스태프" 판정에서 제외한다(계약 v2.0).
func TestRehireInactiveStaffViaInvite(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")

	first, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
		Name: "정혜린", Email: "hyerin@rise.kr", Role: domain.RoleTrainer,
		Payout: &domain.Payout{Type: domain.PayoutRate, Value: 0.5},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), first.UID, domain.StaffProfile{Title: "퍼포먼스 트레이너", CareerYears: 7}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), first.UID, ""); err != nil {
		t.Fatal(err)
	}
	// 재직 중 재초대는 여전히 409여야 한다(가드가 통째로 풀린 게 아니다) — 아래에서 대조한다.

	again, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
		Name: "정혜린", Email: "Hyerin@Rise.KR", Role: domain.RoleTrainer, // 대소문자만 달라도 같은 계정
	})
	if err != nil {
		t.Fatalf("퇴사자 재초대가 거부됨(재고용 영구 차단): %v", err)
	}
	if again.UID != first.UID {
		t.Fatalf("uid = %q, want %q(같은 계정 재사용)", again.UID, first.UID)
	}
	if again.Status != domain.StaffStatusActive || again.LeftAt != nil {
		t.Fatalf("재고용 결과 = %+v, want active + left_at 없음", again)
	}
	if again.Profile.Title != "퍼포먼스 트레이너" {
		t.Errorf("프로필이 초기화됨: %+v(같은 사람인데 경력을 다시 입력시킬 이유가 없다)", again.Profile)
	}
	idx, err := s.store.GetUserIndex(ctx, again.UID)
	if err != nil || idx.Role != domain.RoleTrainer {
		t.Fatalf("UserIndex = %+v, err = %v — 복직인데 권한이 안 돌아옴", idx, err)
	}
	// 재직 중 재초대는 그대로 409.
	if _, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
		Name: "정혜린", Email: "hyerin@rise.kr", Role: domain.RoleTrainer,
	}); !errors.Is(err, ErrConflict) {
		t.Fatalf("재직자 재초대 err = %v, want ErrConflict(409)", err)
	}
}

// 퇴사자가 그 뒤 본인 명의로 회원 등록까지 마쳤다면 복직·재고용이 그 연결을 지운다
// (UserIndex는 uid당 1건 — member_id가 날아가면 회원 앱이 통째로 잠긴다). 조용히 깨뜨리는
// 대신 409로 알린다. 반대로 **퇴사 강등만 된 계정**(member_id 없음)은 반드시 통과해야 한다 —
// 그러지 않으면 재고용이 영구 차단된다.
func TestRehireBlockedWhenAccountBecameLinkedMember(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	st, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
		Name: "정혜린", Email: "hyerin@rise.kr", Role: domain.RoleTrainer,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), st.UID, ""); err != nil {
		t.Fatal(err)
	}
	// 강등만 된 상태(member_id 없음)에서는 복직이 열려 있어야 한다.
	if _, err := s.ReactivateStaff(ctx, ownerP(), st.UID); err != nil {
		t.Fatalf("퇴사 강등 계정의 복직이 막힘(재고용 영구 차단): %v", err)
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), st.UID, ""); err != nil {
		t.Fatal(err)
	}

	// 퇴사 후 본인이 회원으로 연결됐다면(join 플로우) 이야기가 다르다.
	mem, _ := seedMemberFor(t, s, "", "정혜린(회원)", 5)
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{
		UID: st.UID, Role: domain.RoleMember, CenterID: testCenter, MemberID: mem.ID,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ReactivateStaff(ctx, ownerP(), st.UID); !errors.Is(err, ErrConflict) {
		t.Errorf("회원 연결 계정 복직 err = %v, want 409", err)
	}
	if _, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
		Name: "정혜린", Email: "hyerin@rise.kr", Role: domain.RoleTrainer,
	}); !errors.Is(err, ErrConflict) {
		t.Errorf("회원 연결 계정 재초대 err = %v, want 409", err)
	}
	idx, _ := s.store.GetUserIndex(ctx, st.UID)
	if idx.MemberID != mem.ID {
		t.Fatalf("409인데 회원 연결이 훼손됨: %+v", idx)
	}
}

// reactivate는 복직 전용 동사다 — 이미 재직 중이면 400.
func TestReactivateGuards(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")

	if _, err := s.ReactivateStaff(ctx, ownerP(), "t1"); !errors.Is(err, errBadRequest) {
		t.Fatalf("재직자 복직 err = %v, want 400", err)
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); err != nil {
		t.Fatal(err)
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); !errors.Is(err, errBadRequest) {
		t.Fatalf("이미 퇴사한 스태프 재퇴사 err = %v, want 400", err)
	}
	st, err := s.ReactivateStaff(ctx, ownerP(), "t1")
	if err != nil {
		t.Fatal(err)
	}
	if st.Status != domain.StaffStatusActive || st.LeftAt != nil {
		t.Fatalf("복직 결과 = %+v", st)
	}
	idx, _ := s.store.GetUserIndex(ctx, "t1")
	if idx.Role != domain.RoleTrainer {
		t.Errorf("UserIndex.role = %q, want trainer(복직 시 권한 복원)", idx.Role)
	}
	// 전 과정이 owner 전용이다.
	for name, call := range map[string]func() error{
		"deactivate": func() error { _, e := s.DeactivateStaff(ctx, trainerP(), "t1", ""); return e },
		"reactivate": func() error { _, e := s.ReactivateStaff(ctx, trainerP(), "t1"); return e },
		"transfer":   func() error { to := ""; _, e := s.TransferStaff(ctx, trainerP(), "t1", &to); return e },
		"update": func() error {
			n := "x"
			_, e := s.UpdateStaff(ctx, trainerP(), "t1", domain.StaffUpdate{Name: &n})
			return e
		},
	} {
		if err := call(); !errors.Is(err, ErrForbidden) {
			t.Errorf("%s(trainer) err = %v, want ErrForbidden", name, err)
		}
	}
}

// ---- 정정(PUT /v1/staff/{uid}) ----

// 머지 시맨틱 + 역할 동기화. Staff.Role과 UserIndex.Role이 갈리면 "화면엔 트레이너인데 권한은
// 대표"가 조용히 생긴다(인증은 UserIndex만, 정산표·배지는 Staff.Role만 읽는다).
func TestUpdateStaffMergesAndSyncsRole(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	st := seedStaff(t, s, "t1", domain.RoleTrainer, "정헤린")
	st.Offdays = []string{"2026-12-25"}
	st.Profile = domain.StaffProfile{Title: "퍼포먼스 트레이너"}
	if err := s.store.SaveStaff(ctx, testCenter, st); err != nil {
		t.Fatal(err)
	}

	name := "정혜린" // 이름 오타 정정
	got, err := s.UpdateStaff(ctx, ownerP(), "t1", domain.StaffUpdate{Name: &name})
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != name {
		t.Fatalf("name = %q", got.Name)
	}
	// 보내지 않은 필드는 그대로(머지 — PUT /v1/members·/center와 같은 규약).
	if got.Color != "#60a5fa" || len(got.Offdays) != 1 || got.Profile.Title != "퍼포먼스 트레이너" {
		t.Fatalf("머지 위반(안 보낸 필드가 초기화됨): %+v", got)
	}

	// 역할 승격 → Staff와 UserIndex가 함께 간다.
	owner := domain.RoleOwner
	if _, err := s.UpdateStaff(ctx, ownerP(), "t1", domain.StaffUpdate{Role: &owner}); err != nil {
		t.Fatal(err)
	}
	after, _ := s.store.GetStaff(ctx, testCenter, "t1")
	idx, _ := s.store.GetUserIndex(ctx, "t1")
	if after.Role != domain.RoleOwner || idx.Role != domain.RoleOwner {
		t.Fatalf("staff.role = %q / index.role = %q — 두 출처가 갈렸다", after.Role, idx.Role)
	}
	// 강등도 함께(활성 owner가 owner1 없이도 t1 하나 더 있으니 카운트는 통과).
	seedStaff(t, s, "owner2", domain.RoleOwner, "공동대표")
	trainer := domain.RoleTrainer
	if _, err := s.UpdateStaff(ctx, ownerP(), "t1", domain.StaffUpdate{Role: &trainer}); err != nil {
		t.Fatal(err)
	}
	after, _ = s.store.GetStaff(ctx, testCenter, "t1")
	idx, _ = s.store.GetUserIndex(ctx, "t1")
	if after.Role != domain.RoleTrainer || idx.Role != domain.RoleTrainer {
		t.Fatalf("강등 후 staff.role = %q / index.role = %q", after.Role, idx.Role)
	}
}

// 퇴사자 정정은 허용하되 **UserIndex는 건드리지 않는다** — 이름 정정 한 번이 조용히 권한을
// 복구시키면 안 된다(복직은 reactivate 전용 동사만).
func TestUpdateInactiveStaffNeverRestoresAccess(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); err != nil {
		t.Fatal(err)
	}

	owner := domain.RoleOwner
	name := "정혜린(퇴사)"
	got, err := s.UpdateStaff(ctx, ownerP(), "t1", domain.StaffUpdate{Name: &name, Role: &owner})
	if err != nil {
		t.Fatalf("퇴사자 정정: %v", err)
	}
	if got.Name != name || got.Role != domain.RoleOwner {
		t.Fatalf("정정 결과 = %+v", got)
	}
	if got.Status != domain.StaffStatusInactive {
		t.Fatalf("정정이 상태를 되살림: %+v(상태 전이는 전용 동사만)", got)
	}
	idx, _ := s.store.GetUserIndex(ctx, "t1")
	if idx.Role != domain.RoleMember {
		t.Fatalf("UserIndex.role = %q — 퇴사자 정정이 권한을 복구시켰다", idx.Role)
	}
}

// 입력 검증 400 + 빈 요청 거부.
func TestUpdateStaffValidation(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")

	str := func(v string) *string { return &v }
	cases := map[string]domain.StaffUpdate{
		"이름 공백":     {Name: str("   ")},
		"이름 초과":     {Name: str(strings.Repeat("가", 41))},
		"색 형식":      {Color: str("red")},
		"색 빈 값":     {Color: str("")},
		"role 값 오류": {Role: str(domain.RoleMember)},
		"payout 범위": {Payout: &domain.Payout{Type: domain.PayoutRate, Value: 1.5}},
		"payout 방식": {Payout: &domain.Payout{Type: "bonus", Value: 1}},
	}
	for name, req := range cases {
		if _, err := s.UpdateStaff(ctx, ownerP(), "t1", req); !errors.Is(err, domain.ErrInvalidStaff) {
			t.Errorf("%s: err = %v, want ErrInvalidStaff(400)", name, err)
		}
	}
	if _, err := s.UpdateStaff(ctx, ownerP(), "t1", domain.StaffUpdate{}); !errors.Is(err, errBadRequest) {
		t.Errorf("빈 요청 err = %v, want 400", err)
	}
	if _, err := s.UpdateStaff(ctx, ownerP(), "nope", domain.StaffUpdate{Name: str("x")}); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("없는 스태프 err = %v, want 404", err)
	}
}

// ---- 마이그레이션 없는 배포: status 필드가 없는 기존 문서 ----

// 기존 Firestore 문서에는 status가 없다. 로드 시 active로 승격되지 않으면 배포 순간
// 전 스태프가 퇴사자가 되고 예약·고정 스케줄 생성이 통째로 400이 된다.
func TestLegacyStaffDocumentPromotesToActive(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	legacy := &domain.Staff{UID: "t-old", Role: domain.RoleTrainer, Name: "구문서"} // status·offdays·profile 없음
	if err := s.store.SaveStaff(ctx, testCenter, legacy); err != nil {
		t.Fatal(err)
	}

	got, err := s.store.GetStaff(ctx, testCenter, "t-old")
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != domain.StaffStatusActive || !got.IsActive() {
		t.Fatalf("GetStaff status = %q, want active(승격 실패 — 배포 즉시 전원 퇴사자)", got.Status)
	}
	if got.Offdays == nil || got.Profile.Specialties == nil {
		t.Errorf("배열 null 금지 규약 위반: %+v", got)
	}
	list, err := s.store.ListStaff(ctx, testCenter)
	if err != nil {
		t.Fatal(err)
	}
	for _, st := range list {
		if st.Status != domain.StaffStatusActive {
			t.Errorf("ListStaff status = %q, want active", st.Status)
		}
	}
	// 서비스 응답에서도 마찬가지(어드민이 status로 필터한다).
	via, err := s.ListStaff(ctx, ownerP())
	if err != nil || len(via) != 1 || via[0].Status != domain.StaffStatusActive {
		t.Fatalf("ListStaff(service) = %+v, err = %v", via, err)
	}
	// 승격됐으니 예약도 정상적으로 잡힌다.
	mem, pass := seedMemberFor(t, s, "t-old", "김민지", 5)
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(2, 14), MemberID: mem.ID, PassID: pass.ID,
	}); err != nil {
		t.Fatalf("구문서 트레이너 예약이 막힘: %v", err)
	}
}

// ---- by_trainer: 퇴사자 행은 "기간 내 활동이 있을 때만" ----

// 정산 이력 보존과 현재 팀 목록 정합을 동시에 만족시킨다 — 2년 전 퇴사자가 올해 표를
// 0값 행으로 어지럽히지 않으면서, 근무분이 있는 퇴사자는 합계에서 사라지지 않는다.
func TestByTrainerKeepsInactiveOnlyWithActivity(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린") // 활동 있는 퇴사자
	seedStaff(t, s, "t2", domain.RoleTrainer, "김태오") // 활동 없는 퇴사자
	seedStaff(t, s, "t3", domain.RoleTrainer, "이준호") // 재직 중, 활동 없음

	mem, pass := seedMemberFor(t, s, "t1", "김민지", 10)
	bk, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 15), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteBooking(ctx, ownerP(), bk.ID); err != nil {
		t.Fatal(err)
	}
	for _, uid := range []string{"t1", "t2"} {
		st, _ := s.store.GetStaff(ctx, testCenter, uid)
		st.Status = domain.StaffStatusInactive
		if err := s.store.SaveStaff(ctx, testCenter, st); err != nil {
			t.Fatal(err)
		}
	}

	stats, err := s.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	rows := map[string]domain.TrainerStats{}
	for _, r := range stats.ByTrainer {
		rows[r.UID] = r
	}
	t1, ok := rows["t1"]
	if !ok {
		t.Fatalf("활동 있는 퇴사자 행이 사라짐 — 과거 정산 비교표 소급 파괴: %+v", stats.ByTrainer)
	}
	if t1.Status != domain.StaffStatusInactive {
		t.Errorf("t1.status = %q, want inactive(표가 스스로 설명해야 한다)", t1.Status)
	}
	if t1.Sessions != 1 {
		t.Errorf("t1.sessions = %d, want 1", t1.Sessions)
	}
	if _, ok := rows["t2"]; ok {
		t.Errorf("활동 없는 퇴사자가 표에 남음: %+v", rows["t2"])
	}
	t3, ok := rows["t3"]
	if !ok {
		t.Fatalf("재직 트레이너 행이 사라짐(활동 없어도 팀 목록엔 있어야 한다): %+v", stats.ByTrainer)
	}
	if t3.Status != domain.StaffStatusActive {
		t.Errorf("t3.status = %q, want active", t3.Status)
	}
	if _, ok := rows["owner1"]; ok {
		t.Errorf("owner 행이 섞임(P03 LOW-6 회귀)")
	}
}

// role=member 응답에선 퇴사자 profile을 빈 객체로 마스킹한다 — 이름은 남기되(uid 참조 해석)
// 퇴사자 이력을 회원에게 계속 홍보하지는 않는다.
func TestListStaffMasksInactiveProfileForMembers(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{
		Title: "퍼포먼스 트레이너", CareerYears: 7, Specialties: []string{"여성 근력"},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); err != nil {
		t.Fatal(err)
	}

	list, err := s.ListStaff(ctx, memberP("m1"))
	if err != nil {
		t.Fatal(err)
	}
	var got *domain.Staff
	for i := range list {
		if list[i].UID == "t1" {
			got = &list[i]
		}
	}
	if got == nil {
		t.Fatalf("퇴사자가 목록에서 사라짐(이름 해석 붕괴): %+v", list)
	}
	if got.Name != "정혜린" {
		t.Errorf("이름까지 지워짐: %q", got.Name)
	}
	if got.Profile.Title != "" || got.Profile.CareerYears != 0 {
		t.Errorf("퇴사자 프로필이 회원에게 노출됨: %+v", got.Profile)
	}
	if got.Profile.Specialties == nil {
		t.Errorf("마스킹이 배열을 null로 만듦: %+v(앱 specialties.map 크래시)", got.Profile)
	}
	// owner에게는 그대로 보인다.
	ownerList, _ := s.ListStaff(ctx, ownerP())
	for _, st := range ownerList {
		if st.UID == "t1" && st.Profile.Title != "퍼포먼스 트레이너" {
			t.Errorf("owner 응답까지 마스킹됨: %+v", st.Profile)
		}
	}
}

// ---- PUT /v1/members/{id}: 트레이너 호출은 담당을 본인으로 강제 ----

// 종전엔 권한 검사 뒤 바디의 trainer_id가 그대로 덮어써도 재검증이 없어, 트레이너가 자기 담당
// 회원을 임의 uid로 넘길 수 있었다(넘기고 나면 본인도 못 보는 회원이 된다). 담당 이관은
// owner 전용 전담 엔드포인트로만 이뤄져야 감사가 가능하다.
func TestUpdateMemberForcesTrainerToSelf(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	seedStaff(t, s, "t2", domain.RoleTrainer, "김태오")
	mem, _ := seedMemberFor(t, s, "t1", "김민지", 10)

	got, err := s.UpdateMember(ctx, trainerP(), mem.ID,
		[]byte(`{"name":"김민지","trainer_id":"t2"}`))
	if err != nil {
		t.Fatalf("UpdateMember: %v", err)
	}
	if got.TrainerID != "t1" {
		t.Fatalf("trainer_id = %q, want t1(본인으로 강제)", got.TrainerID)
	}
	if got.Name != "김민지" {
		t.Errorf("다른 필드 갱신까지 막힘: %+v", got)
	}
	stored, _ := s.store.GetMember(ctx, testCenter, mem.ID)
	if stored.TrainerID != "t1" {
		t.Fatalf("저장본 trainer_id = %q — 담당이 넘어갔다", stored.TrainerID)
	}
	// owner는 그대로 바꿀 수 있다(스태프 전용 편집 권한 — 이 강제는 트레이너에게만).
	if got, err := s.UpdateMember(ctx, ownerP(), mem.ID, []byte(`{"trainer_id":"t2"}`)); err != nil || got.TrainerID != "t2" {
		t.Fatalf("owner 담당 변경 = %+v, err = %v", got, err)
	}
}

// ---- HTTP 계약(라우터까지) ----

// 상태코드 매핑과 409 blockers 본문 구조를 라우터에 태워 고정한다(writeErr 확장 포함).
func TestStaffLifecycleHTTPContract(t *testing.T) {
	r := newTestRouter(t)

	// 트레이너 두 명 온보딩.
	uids := map[string]string{}
	for name, email := range map[string]string{"정혜린": "hyerin@rise.kr", "김태오": "taeo@rise.kr"} {
		rec := postJSON(t, r, "/v1/staff", "owner1", domain.RoleOwner,
			fmt.Sprintf(`{"name":%q,"email":%q,"role":"trainer"}`, name, email))
		if rec.Code != http.StatusCreated {
			t.Fatalf("POST /v1/staff = %d %s", rec.Code, rec.Body.String())
		}
		var st map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &st); err != nil {
			t.Fatal(err)
		}
		if st["status"] != domain.StaffStatusActive {
			t.Errorf("신규 스태프 status = %v, want active", st["status"])
		}
		uids[name] = st["uid"].(string)
	}
	from, to := uids["정혜린"], uids["김태오"]

	// PUT 정정 — 200 / 트레이너 403 / status 필드는 미지 필드라 400.
	if rec := putJSON(t, r, "/v1/staff/"+from, "owner1", domain.RoleOwner, `{"name":"정혜린","payout":{"type":"rate","value":0.55}}`); rec.Code != http.StatusOK {
		t.Fatalf("PUT /v1/staff/{uid} = %d %s, want 200", rec.Code, rec.Body.String())
	}
	if rec := putJSON(t, r, "/v1/staff/"+from, "t9", domain.RoleTrainer, `{"name":"x"}`); rec.Code != http.StatusForbidden {
		t.Errorf("trainer 정정 = %d, want 403", rec.Code)
	}
	if rec := putJSON(t, r, "/v1/staff/"+from, "owner1", domain.RoleOwner, `{"status":"inactive"}`); rec.Code != http.StatusBadRequest {
		t.Errorf("PUT 바디의 status = %d, want 400(상태 전이는 전용 동사만)", rec.Code)
	}
	if rec := putJSON(t, r, "/v1/staff/nope", "owner1", domain.RoleOwner, `{"name":"x"}`); rec.Code != http.StatusNotFound {
		t.Errorf("없는 스태프 정정 = %d, want 404", rec.Code)
	}

	// 담당 회원을 붙이고 퇴사 시도 → 409 + blockers 구조.
	memRec := postJSON(t, r, "/v1/members", "owner1", domain.RoleOwner,
		fmt.Sprintf(`{"name":"김민지","phone":"010-1111-2222","trainer_id":%q,"status":"active"}`, from))
	if memRec.Code != http.StatusOK {
		t.Fatalf("POST /v1/members = %d %s", memRec.Code, memRec.Body.String())
	}
	var mem map[string]any
	if err := json.Unmarshal(memRec.Body.Bytes(), &mem); err != nil {
		t.Fatal(err)
	}
	memberID, _ := mem["id"].(string)

	// 미래 예약도 하나 붙인다 — blockers.bookings의 **와이어 모양**(계약 v2.1의 {id, slot_key}
	// 객체 배열)을 어드민이 소비하는 그대로 고정하기 위해서다.
	kst := time.Now().In(domain.KST)
	passRec := postJSON(t, r, "/v1/passes", "owner1", domain.RoleOwner, fmt.Sprintf(
		`{"member_id":%q,"trainer_id":%q,"product":"PT 10회","paid_amount":550000,"total_sessions":10,"valid_from":%q,"valid_until":%q}`,
		memberID, from, kst.AddDate(0, 0, -1).Format("2006-01-02"), kst.AddDate(0, 0, 90).Format("2006-01-02")))
	if passRec.Code != http.StatusOK {
		t.Fatalf("POST /v1/passes = %d %s", passRec.Code, passRec.Body.String())
	}
	var pass map[string]any
	if err := json.Unmarshal(passRec.Body.Bytes(), &pass); err != nil {
		t.Fatal(err)
	}
	slot := slotKeyDaysAhead(5, 15)
	bkRec := postJSON(t, r, "/v1/bookings", "owner1", domain.RoleOwner, fmt.Sprintf(
		`{"slot_key":%q,"member_id":%q,"pass_id":%q}`, slot, memberID, pass["id"]))
	if bkRec.Code != http.StatusOK && bkRec.Code != http.StatusCreated {
		t.Fatalf("POST /v1/bookings = %d %s", bkRec.Code, bkRec.Body.String())
	}
	var booking map[string]any
	if err := json.Unmarshal(bkRec.Body.Bytes(), &booking); err != nil {
		t.Fatal(err)
	}

	rec := postJSON(t, r, "/v1/staff/"+from+"/deactivate", "owner1", domain.RoleOwner, `{}`)
	if rec.Code != http.StatusConflict {
		t.Fatalf("담당 남은 퇴사 = %d %s, want 409", rec.Code, rec.Body.String())
	}
	// 와이어 키를 직접 본다(Go 구조체로 디코딩하면 json 태그 오타를 못 잡는다).
	var raw struct {
		Blockers struct {
			Bookings []map[string]any `json:"bookings"`
		} `json:"blockers"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	if len(raw.Blockers.Bookings) != 1 {
		t.Fatalf("blockers.bookings = %v, want 1건", raw.Blockers.Bookings)
	}
	if got := raw.Blockers.Bookings[0]; got["id"] != booking["id"] || got["slot_key"] != slot {
		t.Errorf("blockers.bookings[0] = %v, want {id:%v, slot_key:%s}", got, booking["id"], slot)
	}
	var blocked struct {
		Error    string        `json:"error"`
		Blockers StaffBlockers `json:"blockers"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &blocked); err != nil {
		t.Fatalf("409 본문 파싱 실패: %v (%s)", err, rec.Body.String())
	}
	if blocked.Error == "" || !containsID(blocked.Blockers.Members, memberID) {
		t.Fatalf("blockers 구조 = %+v, want members에 %s", blocked, memberID)
	}
	if blocked.Blockers.Passes == nil || blocked.Blockers.Recurrings == nil || blocked.Blockers.Bookings == nil {
		t.Errorf("빈 blockers가 null로 나감: %s(직렬화 계약: 항상 배열)", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "api:") || strings.Contains(rec.Body.String(), "domain:") {
		t.Errorf("에러 메시지에 내부 마커 노출: %s", rec.Body.String())
	}

	// 이관 → 200 + moved/conflicts 구조.
	rec = postJSON(t, r, "/v1/staff/"+from+"/transfer", "owner1", domain.RoleOwner, fmt.Sprintf(`{"to_uid":%q}`, to))
	if rec.Code != http.StatusOK {
		t.Fatalf("POST transfer = %d %s, want 200", rec.Code, rec.Body.String())
	}
	var moved struct {
		Moved     StaffTransferMoved      `json:"moved"`
		Conflicts []StaffTransferConflict `json:"conflicts"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &moved); err != nil {
		t.Fatal(err)
	}
	if moved.Moved.Members != 1 || moved.Conflicts == nil {
		t.Fatalf("transfer 응답 = %s", rec.Body.String())
	}

	// 퇴사 → 200(바디 없는 호출도 정상 경로), 그다음 복직 → 200.
	rec = postJSON(t, r, "/v1/staff/"+from+"/deactivate", "owner1", domain.RoleOwner, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("이관 후 퇴사 = %d %s, want 200", rec.Code, rec.Body.String())
	}
	var st map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &st); err != nil {
		t.Fatal(err)
	}
	if st["status"] != domain.StaffStatusInactive || st["left_at"] == nil {
		t.Fatalf("퇴사 응답 = %v, want status=inactive + left_at", st)
	}
	// 퇴사자는 즉시 차단된다 — 인증이 UserIndex를 다시 읽어 owner 권한이 사라진다.
	if rec := postJSON(t, r, "/v1/staff", from, domain.RoleOwner, `{"name":"x","email":"x@rise.kr","role":"trainer"}`); rec.Code != http.StatusForbidden {
		t.Errorf("퇴사자의 owner 호출 = %d, want 403(UserIndex 강등이 즉시 먹어야 한다)", rec.Code)
	}
	if rec := postJSON(t, r, "/v1/staff/"+from+"/reactivate", "owner1", domain.RoleOwner, ""); rec.Code != http.StatusOK {
		t.Fatalf("복직 = %d %s, want 200", rec.Code, rec.Body.String())
	}
	if rec := postJSON(t, r, "/v1/staff/"+from+"/reactivate", "owner1", domain.RoleOwner, ""); rec.Code != http.StatusBadRequest {
		t.Errorf("재직자 복직 = %d, want 400", rec.Code)
	}
}
