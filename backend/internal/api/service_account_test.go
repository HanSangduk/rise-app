package api

// 회원탈퇴(계약 v2.11) 회귀 테스트.
//
// 이 파일이 지키는 것은 성격이 셋으로 갈린다:
//
//   - **파기 완전성**: 지운다고 고지한 것이 실제로 사라져야 한다. 하나라도 남으면 앱 확인
//     화면의 문구가 그 순간 거짓말이 된다(P14·P15가 두 번 고쳤던 종류의 결함).
//   - **보존 무결성**: 원장은 append-only이고 잔여 세션의 유일한 출처다. 여기서 한 줄이라도
//     사라지면 5년 보존하기로 한 계약·결제 기록이 근거를 잃는다.
//   - **재가입 차단**: 번호가 남으면 같은 사람이 다시 가입할 때 join/match가 탈퇴 레코드로
//     되돌려 붙인다 — 탈퇴가 조용히 무효화되는 유일한 경로다.

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// recordingProvisioner — UserProvisioner 호출을 기록하는 스파이. Firebase 계정 삭제는 네트워크
// 너머의 일이라 "정말 불렀는가"를 여기서만 확인할 수 있다 — 안 부르면 탈퇴자가 같은 번호로
// 다시 로그인해 같은 uid를 받는다.
type recordingProvisioner struct {
	devUserProvisioner
	deleted  []string
	failWith error
}

func (r *recordingProvisioner) DeleteUser(_ context.Context, uid string) error {
	if r.failWith != nil {
		return r.failWith
	}
	r.deleted = append(r.deleted, uid)
	return nil
}

// recordingMedia — MediaPurger 스파이. Storage 원본 파일 파기는 v2.9가 "파기 수단이 0"이라고
// 명시했던 갭이라, 경로가 실제로 넘어가는지가 이 기능의 핵심 증거다.
type recordingMedia struct {
	objects  []string
	paths    []string
	failWith error
}

// 이 스위트는 훑기를 쓰지 않는다 — 버킷에 아무것도 없다고 답한다.
func (r *recordingMedia) ListObjects(_ context.Context, _ string) ([]string, error) {
	return r.objects, nil
}

func (r *recordingMedia) DeleteObjects(_ context.Context, paths []string) (int, error) {
	if r.failWith != nil {
		return 0, r.failWith
	}
	r.paths = append(r.paths, paths...)
	return len(paths), nil
}

// seedWithdrawableMember — 탈퇴 대상 회원 하나에 "지워야 할 것"과 "남겨야 할 것"을 모두 심는다.
func seedWithdrawableMember(t *testing.T, s *Service) (*domain.Member, *domain.Pass) {
	t.Helper()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)

	// 로그인 매핑(인증이 member_id를 복원하는 문서).
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{
		UID: "u-" + mem.ID, Role: domain.RoleMember, CenterID: testCenter, MemberID: mem.ID,
	}); err != nil {
		t.Fatalf("SaveUserIndex: %v", err)
	}

	// 파기 대상 — 건강·이용 기록.
	if _, err := s.store.CreateBodyPhoto(ctx, testCenter, &domain.BodyPhoto{
		MemberID: mem.ID, Pose: "stand", Direction: "front", Date: "2026-08-20",
		StoragePath: "members/" + mem.ID + "/body/20260820-stand-front-1755000000000.jpg",
	}); err != nil {
		t.Fatalf("CreateBodyPhoto: %v", err)
	}
	if _, err := s.store.CreateInbody(ctx, testCenter, &domain.Inbody{
		MemberID: mem.ID, Date: "2026-08-20", Weight: 70.5, SMM: 32.1, BFM: 12.8,
		PBF: 18.4, VFL: 6, BMR: 1560, Source: domain.InbodySourceMemberSelf,
	}); err != nil {
		t.Fatalf("CreateInbody: %v", err)
	}
	if _, err := s.store.CreateWorkoutLog(ctx, testCenter, &domain.WorkoutLog{
		MemberID: mem.ID, TrainerID: "t1", Date: "2026-08-20", Title: "1:1 PT",
		CoachNote: "어깨 각도 주의",
	}); err != nil {
		t.Fatalf("CreateWorkoutLog: %v", err)
	}
	if err := s.store.SaveHwCheck(ctx, testCenter, &domain.HwCheck{
		MemberID: mem.ID, HwID: "hw1", Date: "2026-08-20", Done: []bool{true},
	}); err != nil {
		t.Fatalf("SaveHwCheck: %v", err)
	}

	// 보존 대상 — 결제·계약(패스와 원장 issue는 seedMemberWithPass가 이미 만들었다).
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 1_000_000,
	}); err != nil {
		t.Fatalf("CreatePayment: %v", err)
	}
	return mem, pass
}

// 핵심 시나리오: 파기 대상은 전부 사라지고, 보존 대상은 전부 남고, 번호로 다시 찾아지지 않는다.
func TestDeleteMyAccountPurgesAndRetains(t *testing.T) {
	s := newTestService()
	users := &recordingProvisioner{}
	media := &recordingMedia{}
	s.users = users
	s.WithMediaPurger(media)
	ctx := context.Background()
	mem, pass := seedWithdrawableMember(t, s)

	// 미래 예약 1건 — 무차감 취소돼야 한다(슬롯이 비어야 다른 회원이 그 자리를 쓴다).
	booking, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(3, 19), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatalf("CreateBooking: %v", err)
	}

	ledgerBefore, err := s.store.ListLedger(ctx, testCenter, mem.ID, "")
	if err != nil {
		t.Fatal(err)
	}

	res, err := s.DeleteMyAccount(ctx, memberP(mem.ID))
	if err != nil {
		t.Fatalf("DeleteMyAccount: %v", err)
	}
	if !res.Deleted || res.MemberID != mem.ID {
		t.Fatalf("응답 = %+v", res)
	}

	// ---- 파기: 건강·이용 기록 ----
	if got := res.Purged; got.BodyPhotos != 1 || got.Inbody != 1 || got.WorkoutLogs != 1 || got.HwChecks != 1 {
		t.Errorf("purged = %+v — 6종 중 0인 항목은 스토어의 컬렉션 이름을 의심하라", got)
	}
	if photos, _ := s.store.ListBodyPhotos(ctx, testCenter, mem.ID); len(photos) != 0 {
		t.Errorf("체형사진이 %d건 남았다", len(photos))
	}
	if rows, _ := s.store.ListInbody(ctx, testCenter, mem.ID); len(rows) != 0 {
		t.Errorf("인바디가 %d건 남았다", len(rows))
	}
	if rows, _ := s.store.ListWorkoutLogs(ctx, testCenter, mem.ID); len(rows) != 0 {
		t.Errorf("수업기록(코치 메모 포함)이 %d건 남았다", len(rows))
	}
	if rows, _ := s.store.ListHwChecksByMember(ctx, testCenter, mem.ID); len(rows) != 0 {
		t.Errorf("홈워크 체크가 %d건 남았다", len(rows))
	}

	// ---- 파기: Storage 원본 파일 ----
	// v2.9가 "동의 철회·탈퇴 시 파기 수단이 0"이라 적었던 갭. 메타만 지우면 원본이 버킷에
	// 영영 남고, 경로를 아는 문서가 사라져 **발견조차 불가능**해진다.
	if len(media.paths) != 1 {
		t.Fatalf("Storage 파기 요청 경로 = %v, want 1건 — 사진 원본이 버킷에 남는다", media.paths)
	}
	if media.paths[0] != "members/"+mem.ID+"/body/20260820-stand-front-1755000000000.jpg" {
		t.Errorf("파기 경로가 메타의 storage_path와 다르다: %q", media.paths[0])
	}

	// ---- 파기: 로그인 수단 ----
	if len(users.deleted) != 1 || users.deleted[0] != "u-"+mem.ID {
		t.Errorf("Firebase 계정 삭제 호출 = %v — 계정이 남으면 같은 번호로 다시 로그인해 같은 uid를 받는다", users.deleted)
	}
	if _, err := s.store.GetUserIndex(ctx, "u-"+mem.ID); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("UserIndex가 남았다(%v) — 인증이 옛 member_id를 그대로 복원한다", err)
	}

	// ---- 파기: 식별자 ----
	after, err := s.store.GetMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatalf("회원 문서가 통째로 사라졌다(%v) — 보존 기록의 조인 대상이다", err)
	}
	if after.Name != domain.WithdrawnMemberName || after.Phone != "" || !after.IsWithdrawn() {
		t.Errorf("가명화가 저장되지 않았다: %+v", after)
	}
	if after.WithdrawnAt == nil {
		t.Error("withdrawn_at이 비었다 — 보존기간(5년)의 기산점이다")
	}

	// **재가입 차단** — 이 검사가 이번 기능의 급소다.
	if found, err := s.store.FindMemberByPhone(ctx, testCenter, "010-1234-5678"); err == nil {
		t.Errorf("탈퇴한 번호가 여전히 매칭된다: %+v — 재가입이 탈퇴를 되돌린다", found)
	}

	// ---- 보존: 원장(append-only) ----
	ledgerAfter, err := s.store.ListLedger(ctx, testCenter, mem.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(ledgerAfter) != len(ledgerBefore) {
		t.Errorf("원장 = %d건, 탈퇴 전 %d건 — 원장을 지우면 잔여 세션의 유일한 출처가 무너진다",
			len(ledgerAfter), len(ledgerBefore))
	}
	if domain.Sum(ledgerAfter) != 20 {
		t.Errorf("원장 합 = %d, want 20", domain.Sum(ledgerAfter))
	}

	// ---- 보존: 계약·결제 5년(전자상거래법 시행령 §6①) ----
	if res.Retained.Passes != 1 || res.Retained.Payments != 1 || res.Retained.Contracts != 1 {
		t.Errorf("retained = %+v, want passes/payments/contracts 각 1", res.Retained)
	}
	if passes, _ := s.store.ListPassesByMember(ctx, testCenter, mem.ID); len(passes) != 1 {
		t.Errorf("회원권이 %d건 — 계약 기록은 5년 보존 대상이다", len(passes))
	}
	if contracts, _ := s.store.ListContracts(ctx, testCenter, mem.ID, ""); len(contracts) != 1 {
		t.Errorf("계약이 %d건 — 5년 보존 대상이다", len(contracts))
	}

	// ---- 미래 예약은 무차감 취소 ----
	if res.CancelledBookings != 1 {
		t.Errorf("cancelled_bookings = %d, want 1", res.CancelledBookings)
	}
	b, err := s.store.GetBooking(ctx, testCenter, booking.ID)
	if err != nil {
		t.Fatal(err)
	}
	if b.Status != domain.BookingCancelled {
		t.Errorf("예약 상태 = %q, want cancelled — 슬롯이 비어야 다른 회원이 쓴다", b.Status)
	}
	// 페널티 원장이 붙지 않았는지(탈퇴는 노쇼가 아니다).
	for _, e := range ledgerAfter {
		if e.Reason == domain.ReasonNoshow || e.Reason == domain.ReasonNoshowWaive {
			t.Errorf("탈퇴 정리 취소에 페널티 원장이 붙었다: %+v", e)
		}
	}

	// ---- 잔여 회차 고지 ----
	if res.RemainingSessions != 20 {
		t.Errorf("remaining_sessions = %d, want 20 — 앱이 '정산은 센터와 별도'를 사실대로 띄우는 근거다",
			res.RemainingSessions)
	}
}

// 스태프는 이 경로를 쓸 수 없다. 뚫리면 대표의 UserIndex가 사라져 **센터가 영구히 잠긴다**
// (owner 전용 API가 전부 막히고 Firestore 직접 편집 외에 복구 경로가 없다 — v2.0 락아웃 가드).
func TestDeleteMyAccountRejectsStaff(t *testing.T) {
	s := newTestService()
	for _, p := range []Principal{ownerP(), trainerP()} {
		if _, err := s.DeleteMyAccount(context.Background(), p); !errors.Is(err, ErrForbidden) {
			t.Errorf("role=%s DeleteMyAccount = %v, want ErrForbidden", p.Role, err)
		}
	}
}

// 가입 매칭 전(member_id 미연결) 계정은 지울 회원 레코드가 없다 → 404.
// 200을 돌려주면 "탈퇴했다"는 응답이 실제로는 아무것도 하지 않은 응답이 된다.
func TestDeleteMyAccountRequiresLinkedMember(t *testing.T) {
	s := newTestService()
	p := Principal{UID: "u-new", Role: domain.RoleMember, CenterID: testCenter}
	if _, err := s.DeleteMyAccount(context.Background(), p); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("미연결 계정 DeleteMyAccount = %v, want ErrNotFound", err)
	}
}

// 외부 호출(Storage·Firebase)이 실패하면 **DB는 손대지 않고** 500으로 멈춘다.
// 단계 순서의 존재 이유 그 자체다: 같은 ID 토큰이 아직 살아 있어 재시도가 가능해야 한다.
func TestDeleteMyAccountLeavesDataIntactWhenExternalPurgeFails(t *testing.T) {
	boom := errors.New("storage unavailable")

	for _, tc := range []struct {
		name  string
		setup func(s *Service)
	}{
		{"Storage 파기 실패", func(s *Service) { s.WithMediaPurger(&recordingMedia{failWith: boom}) }},
		{"Firebase 계정 삭제 실패", func(s *Service) { s.users = &recordingProvisioner{failWith: boom} }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newTestService()
			ctx := context.Background()
			mem, _ := seedWithdrawableMember(t, s)
			tc.setup(s)

			if _, err := s.DeleteMyAccount(ctx, memberP(mem.ID)); !errors.Is(err, boom) {
				t.Fatalf("DeleteMyAccount = %v, want %v", err, boom)
			}
			after, err := s.store.GetMember(ctx, testCenter, mem.ID)
			if err != nil {
				t.Fatal(err)
			}
			if after.IsWithdrawn() || after.Phone == "" {
				t.Errorf("외부 파기 실패인데 회원이 이미 가명화됐다: %+v — 재시도할 자격을 잃는다", after)
			}
			if photos, _ := s.store.ListBodyPhotos(ctx, testCenter, mem.ID); len(photos) != 1 {
				t.Errorf("체형사진 메타가 %d건 — 원본이 남았는데 경로를 아는 문서를 지웠다", len(photos))
			}
			if _, err := s.store.GetUserIndex(ctx, "u-"+mem.ID); err != nil {
				t.Errorf("UserIndex가 사라졌다(%v) — 호출자가 자기 탈퇴를 마저 끝낼 수 없다", err)
			}
		})
	}
}

// 잔여 회차가 남아 있어도 **막지 않는다**(Guideline 5.1.1(v)). 대신 응답이 그 사실을 싣는다.
func TestDeleteMyAccountAllowedWithRemainingSessions(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedWithdrawableMember(t, s)

	res, err := s.DeleteMyAccount(ctx, memberP(mem.ID))
	if err != nil {
		t.Fatalf("잔여 20회 회원의 탈퇴가 막혔다: %v — 사업상 상태로 앱 내 삭제를 막을 수 없다", err)
	}
	if res.RemainingSessions <= 0 {
		t.Errorf("remaining_sessions = %d, want > 0", res.RemainingSessions)
	}
}

// 탈퇴 회원에게 새 의무·새 데이터를 붙이지 못한다(스태프 경로 — 탈퇴자는 스스로 호출할 수 없다).
func TestWithdrawnMemberBlocksNewWrites(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	kst := time.Now().In(domain.KST)
	mem, _ := seedWithdrawableMember(t, s)
	if _, err := s.DeleteMyAccount(ctx, memberP(mem.ID)); err != nil {
		t.Fatal(err)
	}

	t.Run("회원권 발급", func(t *testing.T) {
		_, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
			MemberID: mem.ID, TrainerID: "t1", Product: "PT 10회", PaidAmount: 500_000,
			TotalSessions: 10,
			ValidFrom:     kst.Format("2006-01-02"), ValidUntil: kst.AddDate(0, 0, 60).Format("2006-01-02"),
		})
		if !errors.Is(err, errBadRequest) {
			t.Errorf("탈퇴 회원 발급 = %v, want 400", err)
		}
	})

	t.Run("Home Work 배정", func(t *testing.T) {
		_, err := s.CreateHomework(ctx, ownerP(), HomeworkCreateRequest{
			TrainerID: "t1", Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{mem.ID},
			Items: []domain.HwItem{{Name: "스쿼트", Sets: 3, Reps: "12"}},
		})
		if !errors.Is(err, errBadRequest) {
			t.Errorf("탈퇴 회원 Home Work 배정 = %v, want 400 — 배달될 앱이 없는데 완료율 분모만 오른다", err)
		}
	})

	t.Run("가입 재연결(되살리기)", func(t *testing.T) {
		// 탈퇴 회원의 번호는 이미 비었지만, member_id를 알고 있는 호출자가 join/confirm으로
		// 그 레코드에 다시 붙는 경로를 명시적으로 막는다 — 탈퇴는 종단 상태다.
		_, err := s.JoinConfirm(ctx, Principal{UID: "u-new", Role: domain.RoleMember, CenterID: testCenter},
			JoinConfirmRequest{MemberID: mem.ID, Confirm: true, Phone: "010-1234-5678"})
		if !errors.Is(err, errBadRequest) {
			t.Errorf("탈퇴 회원 join/confirm = %v, want 400", err)
		}
		if _, err := s.store.GetUserIndex(ctx, "u-new"); !errors.Is(err, store.ErrNotFound) {
			t.Errorf("탈퇴 레코드에 새 uid가 연결됐다")
		}
	})

	t.Run("정보 수정(되살리기)", func(t *testing.T) {
		_, err := s.UpdateMember(ctx, ownerP(), mem.ID, []byte(`{"name":"김민지","phone":"010-1234-5678","status":"active"}`))
		if !errors.Is(err, errBadRequest) {
			t.Errorf("탈퇴 회원 PUT = %v, want 400 — 이 경로가 열려 있으면 파기가 조용히 무효화된다", err)
		}
		after, _ := s.store.GetMember(ctx, testCenter, mem.ID)
		if after.Phone != "" || !after.IsWithdrawn() {
			t.Errorf("탈퇴 레코드가 되살아났다: %+v", after)
		}
	})
}

// 탈퇴 회원은 어느 KPI에도 들어가지 않는다. 특히 **미배정**이 급소다 — 가명화가 trainer_id를
// ""로 회수하므로, 거르지 않으면 탈퇴자 전원이 "담당 배정이 필요한 회원"으로 잡혀 대표가
// 영원히 줄지 않는 할 일을 보게 된다.
func TestWithdrawnMemberExcludedFromStats(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedWithdrawableMember(t, s)

	before, err := s.Stats(ctx, ownerP(), "", "center")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.DeleteMyAccount(ctx, memberP(mem.ID)); err != nil {
		t.Fatal(err)
	}
	after, err := s.Stats(ctx, ownerP(), "", "center")
	if err != nil {
		t.Fatal(err)
	}

	if before.ActiveMembers != 1 {
		t.Fatalf("픽스처 전제가 깨졌다: 탈퇴 전 active_members = %d, want 1", before.ActiveMembers)
	}
	if after.ActiveMembers != 0 {
		t.Errorf("active_members = %d, want 0", after.ActiveMembers)
	}
	// 이 센터의 유일한 회원이 탈퇴했으므로 세 지표 전부 0이어야 한다. 가드가 없으면
	// **가명화가 만든 값 때문에** 오히려 늘어난다: trainer_id를 ""로 회수하니 미배정 1,
	// last_visit_at을 지웠으니 장기미방문 1. 대표가 영원히 줄지 않는 할 일을 보게 된다.
	if after.Unassigned != 0 {
		t.Errorf("unassigned = %d, want 0 — 탈퇴자가 '담당 배정 필요'로 잡히고 있다", after.Unassigned)
	}
	if after.LongAbsent != 0 {
		t.Errorf("long_absent = %d, want 0 — 탈퇴자가 '장기미방문'으로 잡히고 있다", after.LongAbsent)
	}
}

// ---- 와이어 형태(라우터를 태워 JSON 키로) ----
//
// 계약 v2.1의 검증 규약: "와이어 형태는 라우터를 태워 JSON 키로 검증한다. Go 구조체로
// 디코딩하는 테스트는 json 태그 오타를 잡지 못한다." 앱의 완료 화면이 이 키들을 그대로 읽는다.
func TestDeleteMeWireContract(t *testing.T) {
	r := newTestRouter(t)

	// 회원 레코드 + UserIndex를 라우터가 쓰는 스토어에 심는다.
	created := postJSON(t, r, "/v1/members", "owner1", "owner", `{"name":"김민지","phone":"010-1234-5678","status":"active"}`)
	if created.Code != http.StatusOK && created.Code != http.StatusCreated {
		t.Fatalf("회원 생성 = %d %s", created.Code, created.Body.String())
	}
	var mem struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(created.Body.Bytes(), &mem); err != nil {
		t.Fatal(err)
	}
	match := postJSON(t, r, "/v1/join/match", "u-app", "member", `{"phone":"010-1234-5678"}`)
	if match.Code != http.StatusOK {
		t.Fatalf("join/match = %d %s", match.Code, match.Body.String())
	}
	confirm := postJSON(t, r, "/v1/join/confirm", "u-app", "member",
		`{"member_id":"`+mem.ID+`","confirm":true,"phone":"010-1234-5678"}`)
	if confirm.Code != http.StatusOK {
		t.Fatalf("join/confirm = %d %s", confirm.Code, confirm.Body.String())
	}

	// 스태프는 403(상태코드 매핑까지 고정 — writeErr를 함께 태운다).
	if rec := deleteReq(t, r, "/v1/me", "owner1", "owner"); rec.Code != http.StatusForbidden {
		t.Errorf("owner DELETE /v1/me = %d, want 403", rec.Code)
	}

	rec := deleteReq(t, r, "/v1/me", "u-app", "member")
	if rec.Code != http.StatusOK {
		t.Fatalf("DELETE /v1/me = %d %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("응답 파싱: %v (%s)", err, rec.Body.String())
	}
	for _, key := range []string{
		"deleted", "member_id", "withdrawn_at", "purged", "retained",
		"cancelled_bookings", "remaining_sessions",
	} {
		if _, ok := body[key]; !ok {
			t.Errorf("응답에 %q 키가 없다 — 앱 완료 화면이 이 값을 읽는다", key)
		}
	}
	purged, _ := body["purged"].(map[string]any)
	for _, key := range []string{"body_photos", "inbody", "workout_logs", "hw_checks", "checkins", "recurrings"} {
		if _, ok := purged[key]; !ok {
			t.Errorf("purged에 %q 키가 없다", key)
		}
	}
	retained, _ := body["retained"].(map[string]any)
	for _, key := range []string{"passes", "payments", "contracts", "ledger", "bookings"} {
		if _, ok := retained[key]; !ok {
			t.Errorf("retained에 %q 키가 없다", key)
		}
	}

	// 탈퇴 후 같은 uid로 다시 부르면 404다(UserIndex가 사라져 member_id를 잃는다) —
	// "이미 지웠다"가 200으로 다시 보고되지 않는다.
	if again := deleteReq(t, r, "/v1/me", "u-app", "member"); again.Code != http.StatusNotFound {
		t.Errorf("두 번째 DELETE /v1/me = %d, want 404", again.Code)
	}
}

func deleteReq(t *testing.T, r http.Handler, path, uid, role string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodDelete, path, nil)
	req.Header.Set("X-Dev-Uid", uid)
	req.Header.Set("X-Dev-Role", role)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}
