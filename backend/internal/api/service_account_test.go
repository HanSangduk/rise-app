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
	// failDisable — DisableUser 실패 주입(v2.31). 퇴사 ①(계정 잠금)이 실패했을 때 ③ 사진 파기가
	// 일어나지 않아야 한다는 순서를 고정하는 유일한 수단이다 — dev 구현은 항상 nil이라 주입이 없으면
	// "③을 ① 앞으로" 뮤턴트가 모든 테스트를 통과한다.
	failDisable error
}

func (r *recordingProvisioner) DeleteUser(_ context.Context, uid string) error {
	if r.failWith != nil {
		return r.failWith
	}
	r.deleted = append(r.deleted, uid)
	return nil
}

func (r *recordingProvisioner) DisableUser(_ context.Context, _ string) error {
	return r.failDisable
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

// 구성된 버킷의 대역(recordingPurger와 같은 이유).
func (r *recordingMedia) Configured() bool { return true }

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

	// 파기 대상 — 회원발 요청 큐 2종(v2.26 · P53). 종전 픽스처에 이 둘이 없었기 때문에
	// 스위트 전체가 초록인 채로 이름·전화번호·자유 메모가 살아남았다. 스토어로 직접 심는다
	// (서비스 경로는 토큰 번호 대조·pending 중복 409를 거치는데, 여기서 검증할 것은 그 규칙이
	// 아니라 파기다 — 다른 픽스처들과 같은 방식).
	if _, err := s.store.CreateJoinRequest(ctx, &store.JoinRequest{
		CenterID: testCenter, UID: "u-" + mem.ID, Name: "김민지", Phone: "010-1234-5678",
		Status: store.JoinPending,
	}); err != nil {
		t.Fatalf("CreateJoinRequest: %v", err)
	}
	if _, err := s.store.CreateConsultRequest(ctx, testCenter, &store.ConsultRequest{
		MemberID: mem.ID, Kind: store.ConsultKindRenewal, Note: "무릎이 아파서 상담받고 싶어요",
		Status: store.ConsultPending,
	}); err != nil {
		t.Fatalf("CreateConsultRequest: %v", err)
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
		t.Errorf("purged = %+v — 0인 항목은 스토어의 컬렉션 이름을 의심하라", got)
	}
	// 요청 큐 2종(v2.26 · P53) — 여기 숫자가 0이면 이름·번호·메모가 그대로 살아 있다.
	if got := res.Purged; got.JoinRequests != 1 || got.ConsultRequests != 1 {
		t.Errorf("purged.join_requests=%d consult_requests=%d, want 1/1 — 각각 이름·전화번호와 자유 메모다",
			got.JoinRequests, got.ConsultRequests)
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
	contracts, _ := s.store.ListContracts(ctx, testCenter, mem.ID, "")
	if len(contracts) != 1 {
		t.Fatalf("계약이 %d건 — 5년 보존 대상이다", len(contracts))
	}
	// 보존은 **문서** 보존이다(v2.17): 발급 자동 계약(sent)은 서명 주체가 파기됐으므로 voided로
	// 종결된 채 남는다. sent인 채 남으면 어드민 미서명 카운트에 영원히 행동 불가능한 항목으로
	// 잡힌다(P37·P38 적대 리뷰 [H] — 이 스위트가 종전에 "건드리지 않는다"만 검사하던 자리).
	if contracts[0].Status != domain.ContractStatusVoided {
		t.Errorf("탈퇴 후 미서명 계약 = %q, want voided — '서명 대기'가 거짓으로 남는다", contracts[0].Status)
	}
	if contracts[0].SentAt == nil || contracts[0].FirstSentAt == nil {
		t.Errorf("void가 발송 증적을 지웠다: sent_at=%v first_sent_at=%v — 상태만 바뀌어야 한다",
			contracts[0].SentAt, contracts[0].FirstSentAt)
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

// 회원발 요청 큐 2종의 파기(v2.26 · P53) — 이 결함의 본체.
//
// 종전 탈퇴는 이 둘을 남긴 채 "지웠다"고 보고했다. 두 컬렉션이 각각 다른 이유로 스윕 밖에
// 있었다: join_requests는 **최상위 + uid 키**(센터 스코프 스윕이 구조적으로 닿지 못한다),
// consult_requests는 v2.11 이후에 생겨 **스윕 목록에 오르지 못했다**(닿을 수 있었는데 안 봤다).
//
// 이웃 회원·이웃 신청자를 함께 심는 이유: "전부 지운다"로 고치면 테스트는 통과하고 남의
// 데이터가 사라진다. 파기의 정확성은 남는 쪽이 함께 증명한다.
func TestDeleteMyAccountPurgesRequestQueues(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedWithdrawableMember(t, s) // 가입 요청 1 + 상담 요청 1을 품는다

	// 같은 센터의 이웃 회원 — 상담 요청 보유(탈퇴자와 무관하게 남아야 한다).
	otherID, err := s.store.SaveMember(ctx, testCenter, &domain.Member{
		Name: "이서준", Phone: "010-1234-5678", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.store.CreateConsultRequest(ctx, testCenter, &store.ConsultRequest{
		MemberID: otherID, Kind: store.ConsultKindConsult, Note: "식단 상담 원해요",
		Status: store.ConsultPending,
	}); err != nil {
		t.Fatal(err)
	}
	// 아직 회원이 아닌 이웃 신청자 — 가입 요청만 있다(member_id가 없는 사람도 남아야 한다).
	if _, err := s.store.CreateJoinRequest(ctx, &store.JoinRequest{
		CenterID: testCenter, UID: "u-applicant", Name: "박지훈", Phone: "010-7777-7777",
		Status: store.JoinPending,
	}); err != nil {
		t.Fatal(err)
	}
	// 탈퇴자의 두 번째 가입 요청(거절된 것) — 상태와 무관하게 이름·번호를 품으므로 함께 파기.
	if _, err := s.store.CreateJoinRequest(ctx, &store.JoinRequest{
		CenterID: testCenter, UID: "u-" + mem.ID, Name: "김민지", Phone: "010-1234-5678",
		Status: store.JoinRejected,
	}); err != nil {
		t.Fatal(err)
	}

	res, err := s.DeleteMyAccount(ctx, memberP(mem.ID))
	if err != nil {
		t.Fatalf("DeleteMyAccount: %v", err)
	}

	// ---- 보고한 건수가 실제와 같은가(응답을 믿지 않고 다시 읽는다) ----
	if res.Purged.JoinRequests != 2 {
		t.Errorf("purged.join_requests = %d, want 2(pending + rejected)", res.Purged.JoinRequests)
	}
	if res.Purged.ConsultRequests != 1 {
		t.Errorf("purged.consult_requests = %d, want 1", res.Purged.ConsultRequests)
	}

	// ---- 실제로 사라졌는가 ----
	jrs, err := s.store.ListJoinRequests(ctx, testCenter)
	if err != nil {
		t.Fatal(err)
	}
	for _, jr := range jrs {
		if jr.UID == "u-"+mem.ID {
			t.Errorf("탈퇴자의 가입 요청이 남았다: name=%q phone=%q — JoinApprove 한 번이면 "+
				"파기한 이름·번호가 새 회원 레코드로 되살아난다", jr.Name, jr.Phone)
		}
	}
	if rows, _ := s.store.ListConsultRequests(ctx, testCenter, mem.ID); len(rows) != 0 {
		t.Errorf("탈퇴자의 상담 요청이 %d건 남았다 — note는 회원이 직접 쓴 자유 서술이다", len(rows))
	}

	// ---- 남의 것은 온전한가 ----
	if len(jrs) != 1 || jrs[0].UID != "u-applicant" || jrs[0].Phone != "010-7777-7777" {
		t.Errorf("이웃 신청자의 가입 요청 = %+v, want u-applicant 1건 온전 — uid로 좁혀지지 않았다", jrs)
	}
	otherConsults, _ := s.store.ListConsultRequests(ctx, testCenter, otherID)
	if len(otherConsults) != 1 || otherConsults[0].Note != "식단 상담 원해요" {
		t.Errorf("이웃 회원 상담 요청 = %+v, want 1건 온전 — member_id로 좁혀지지 않았다", otherConsults)
	}
}

// ⑤단계 부분 실패 → **가명화 전에** 멈추고, 같은 토큰의 재시도가 마저 끝낸다(P22 순서 규약).
//
// 이 자리를 실측하는 이유: 가입 요청 파기가 ⑥(가명화)보다 **뒤**에 있었다면 실패한 순간
// 회원 문서는 이미 탈퇴 상태라 재시도가 "이미 탈퇴 처리된 계정이에요"(400)로 막히고,
// 이름·전화번호가 영구히 남는다 — 고치려던 결함이 형태만 바꿔 되돌아온다.
func TestDeleteMyAccountJoinPurgeFailureKeepsRetryEligible(t *testing.T) {
	ctx := context.Background()
	s, h := newHookedService(t)
	mem, _ := seedWithdrawableMember(t, s)
	h.reset()

	boom := errors.New("firestore unavailable")
	h.fail = func(op string, _ int) error {
		if op == "DeleteJoinRequestsByUID" {
			return boom
		}
		return nil
	}
	if _, err := s.DeleteMyAccount(ctx, memberP(mem.ID)); !errors.Is(err, boom) {
		t.Fatalf("DeleteMyAccount = %v, want %v", err, boom)
	}

	after, err := s.store.GetMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if after.IsWithdrawn() {
		t.Error("가입 요청 파기 실패인데 이미 가명화됐다 — ⑤가 ⑥보다 앞이어야 재시도가 400에 막히지 않는다")
	}
	if _, err := s.store.GetUserIndex(ctx, "u-"+mem.ID); err != nil {
		t.Errorf("UserIndex가 사라졌다(%v) — 호출자가 자기 탈퇴를 마저 끝낼 수 없다", err)
	}
	if rows, _ := s.store.ListConsultRequests(ctx, testCenter, mem.ID); len(rows) != 1 {
		t.Errorf("상담 요청 = %d건, want 1 — ⑥(스토어 스윕)은 아직 돌지 않았어야 한다", len(rows))
	}

	h.fail = nil
	res, err := s.DeleteMyAccount(ctx, memberP(mem.ID)) // 같은 토큰으로 재시도
	if err != nil {
		t.Fatalf("재시도: %v", err)
	}
	if res.Purged.JoinRequests != 1 || res.Purged.ConsultRequests != 1 {
		t.Errorf("재시도 purged = %+v, want join/consult 각 1 — 첫 시도가 아무것도 못 지웠으므로 전량이 여기서 잡힌다",
			res.Purged)
	}
	jrs, _ := s.store.ListJoinRequests(ctx, testCenter)
	if len(jrs) != 0 {
		t.Errorf("재시도 후에도 가입 요청이 %d건 남았다: %+v", len(jrs), jrs)
	}
	if rows, _ := s.store.ListConsultRequests(ctx, testCenter, mem.ID); len(rows) != 0 {
		t.Errorf("재시도 후에도 상담 요청이 %d건 남았다", len(rows))
	}
}

// **Contract.Vars의 이름·전화번호는 탈퇴가 지우지 않는다** — 의도된 잔존을 고정한다(P53 결정 3).
//
// 이 테스트는 "지워지는지"가 아니라 **"지우지 않기로 한 결정"**을 못박는다. 누군가 나중에
// 파기 스윕을 vars까지 넓히면 여기서 빨간불이 켜지고, 그 순간 아래 근거를 읽고 판단하게 된다:
//
//	① 봉인이 vars를 덮는다 — sha256 = SHA-256(template_version + "\n" + canonical_json(vars))
//	   (§D ②). vars에서 한 글자만 바꿔도 재계산 대조가 깨져 **서명된 계약의 사후 변조 검출이
//	   영구히 불가능**해진다. 봉인을 함께 다시 계산하는 것은 더 나쁘다 — 변조와 구별되지 않는다.
//	② 계약서의 당사자 표시는 그 문서를 계약서이게 하는 내용이다. 5년 보존(전자상거래법
//	   시행령 §6①)의 목적이 "그 거래가 있었다"의 입증인데, 당사자가 빈칸인 처분문서는 그
//	   목적을 잃는다. 같은 법 §6②는 거래기록과 함께 식별정보 보존을 **명시적으로 허용**한다.
//
// P22가 회원 문서에서 "성명 보존"을 일부러 쓰지 않은 것과 모순처럼 보이지만 아니다: 그쪽에서
// 이름은 **거래 기록을 가리키는 색인**이라 없어도 기록이 완전했고, 여기서 이름은 **문서의
// 내용**이다. 대신 이 잔존은 고지의 대상이다(개인정보처리방침·계정삭제 안내 — P53 참조).
func TestWithdrawalKeepsContractVarsIdentity(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	ver, _ := withIssuableContractVariants(t)
	seedContractBusiness(t, s)
	seedFacility(t, s, domain.FacilityStatusReported, "제2026-강남-0001호", "서울보증 인허가보증보험, 보장한도 1억원")
	mem, _ := seedWithdrawableMember(t, s) // 결제 기록까지 포함 — 스탬프 재료가 이미 완비다

	// 완전 스탬프 → 서명(봉인 생성). 서명까지 가야 sha256이 vars를 덮는다(§D ②).
	c := autoContractOf(t, s, mem.ID)
	sent, err := s.SendContract(ctx, ownerP(), c.ID)
	if err != nil {
		t.Fatalf("재발송(스탬프): %v", err)
	}
	if sent.TemplateVersion != ver || sent.Vars["회원명"] != "김민지" {
		t.Fatalf("픽스처 전제가 깨졌다: version=%q 회원명=%q", sent.TemplateVersion, sent.Vars["회원명"])
	}
	phoneInVars := sent.Vars["회원 전화번호"]
	if phoneInVars == "" {
		t.Fatal("픽스처 전제가 깨졌다: vars에 회원 전화번호가 없다")
	}
	signed, err := s.SignContract(ctx, memberP(mem.ID), c.ID, "1.2.3.4", nil)
	if err != nil {
		t.Fatalf("서명: %v", err)
	}
	sealBefore := signed.SHA256
	if sealBefore == "" {
		t.Fatal("픽스처 전제가 깨졌다: 서명했는데 봉인이 비었다")
	}

	if _, err := s.DeleteMyAccount(ctx, memberP(mem.ID)); err != nil {
		t.Fatalf("DeleteMyAccount: %v", err)
	}

	// ---- 회원 문서 쪽은 실제로 비었다(대조군 — 두 저장 위치가 다른 취급을 받는다) ----
	after, err := s.store.GetMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if after.Name != domain.WithdrawnMemberName || after.Phone != "" {
		t.Fatalf("회원 문서 가명화가 안 됐다: %+v", after)
	}

	// ---- 계약 스냅샷 쪽은 그대로다(결정 3) ----
	saved, err := s.store.GetContract(ctx, testCenter, c.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusSigned {
		t.Fatalf("서명된 계약이 무효화됐다: %q — signed는 불가침(v1.5)", saved.Status)
	}
	if saved.Vars["회원명"] != "김민지" || saved.Vars["회원 전화번호"] != phoneInVars {
		t.Errorf("계약 vars의 이름·번호가 바뀌었다: 회원명=%q 전화번호=%q\n"+
			"이 값을 지우기로 결정을 바꾼 것이라면 위 주석 ①②를 읽고 봉인 재검증 계약을 함께 설계하라",
			saved.Vars["회원명"], saved.Vars["회원 전화번호"])
	}

	// ---- 봉인이 **여전히 검증된다**(재현성·변조 검출이 살아 있다) ----
	if saved.SHA256 != sealBefore {
		t.Errorf("봉인 값이 바뀌었다: %q → %q — 탈퇴는 계약 문서를 건드리지 않아야 한다", sealBefore, saved.SHA256)
	}
	if got := contractSeal(saved.TemplateVersion, saved.Vars); got != saved.SHA256 {
		t.Errorf("봉인 재계산 불일치: %q != 저장값 %q — vars가 바뀌면 사후 변조 검출이 영구히 불가능해진다",
			got, saved.SHA256)
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
// **C-3 회귀(v2.27): 미연결 계정도 자기 이름·전화번호를 지울 수 있어야 한다.**
//
// 종전엔 이 자리가 `p.MemberID == "" → store.ErrNotFound`(404)로 **진입부터 막혀** 있었고,
// 근거는 "지울 대상이 없다"였다. 사실이 아니었다: join_requests에는 신청자가 직접 적은
// **이름·전화번호 원본**이 담기고(POST /v1/join/request), Firebase 계정에는 인증된 번호가
// 있다. v2.26이 만든 파기 경로(DeleteJoinRequestsByUID)에 도달할 길이 **회원이 된 사람에게만**
// 열려 있었던 것이다 — 개인정보보호법 §36(삭제 요구권)이 정면으로 겨냥하는 상태다.
//
// 이 테스트를 지우면 그 404가 조용히 되돌아온다. 그때 앱의 대기 화면에는 계정 삭제 버튼이
// 있고, 그 버튼이 404를 받는다.
func TestDeleteMyAccountUnlinkedPurgesJoinRequest(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	prov := &recordingProvisioner{}
	s.users = prov

	// 대기실 계정: 가입 요청만 냈고 아직 승인되지 않았다(회원 레코드·UserIndex 없음).
	applicant := Principal{UID: "u_lobby", Role: domain.RoleMember, CenterID: testCenter}
	if _, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"}); err != nil {
		t.Fatal(err)
	}
	// 이웃 신청자 — 남의 요청까지 쓸어가면 안 된다(uid 스코프).
	neighbour := Principal{UID: "u_other", Role: domain.RoleMember, CenterID: testCenter}
	if _, err := s.JoinRequestCreate(ctx, neighbour, JoinRequestBody{Name: "이서준", Phone: "010-1234-5678"}); err != nil {
		t.Fatal(err)
	}

	res, err := s.DeleteMyAccount(ctx, applicant)
	if err != nil {
		t.Fatalf("미연결 계정 탈퇴 = %v, want 성공(§36 삭제 요구권)", err)
	}
	if !res.Deleted || res.MemberID != "" {
		t.Errorf("응답 = %+v, want deleted=true member_id=\"\"", res)
	}
	if res.Purged.JoinRequests != 1 {
		t.Errorf("purged.join_requests = %d, want 1 — 이름·전화번호가 실제로 지워져야 한다", res.Purged.JoinRequests)
	}
	// ②단계(Firebase 계정)가 실제로 불렸는가 — 안 부르면 계정 안의 전화번호가 남고,
	// 같은 번호로 다시 로그인하면 같은 uid를 되받는다.
	if len(prov.deleted) != 1 || prov.deleted[0] != "u_lobby" {
		t.Errorf("Firebase DeleteUser 호출 = %v, want [u_lobby]", prov.deleted)
	}

	// 실제 저장소를 다시 읽어 대조한다(응답의 건수를 믿지 않는다).
	list, err := s.store.ListJoinRequests(ctx, testCenter)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].UID != "u_other" || list[0].Phone != "010-1234-5678" {
		t.Errorf("남은 가입 요청 = %+v, want 이웃 1건 온전 — uid로 좁혀지지 않았다", list)
	}
}

// 스태프는 미연결 분기로도 들어올 수 없다 — 가드 ①은 v2.27에서도 무변경이다.
// (owner/trainer는 member_id가 늘 비어 있어, 분기 순서가 뒤집히면 대표가 자기 계정을 지우고
// **센터가 대표를 잃는다** — 되돌릴 API가 없다.)
func TestDeleteMyAccountStaffStillForbiddenAfterUnlinkedBranch(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	for _, p := range []Principal{ownerP(), trainerP()} {
		if _, err := s.DeleteMyAccount(ctx, p); !errors.Is(err, ErrForbidden) {
			t.Errorf("%s DeleteMyAccount = %v, want ErrForbidden", p.Role, err)
		}
	}
	// superadmin도 마찬가지(IsMember가 아니다).
	if _, err := s.DeleteMyAccount(ctx, superadminP()); !errors.Is(err, ErrForbidden) {
		t.Errorf("superadmin DeleteMyAccount = %v, want ErrForbidden", err)
	}
}

// 미연결 분기의 **단계 순서**: 외부(Firebase)가 DB보다 앞이라, 파기가 중간에 실패해도 같은
// ID 토큰으로 재시도가 된다(P22 순서 규약 — 전체 흐름과 같은 이유). ⑤가 실패하면 ⑦
// (UserIndex 제거)까지 가지 않아야 한다 — 가면 호출자가 권한을 잃고 자기 탈퇴를 못 끝낸다.
func TestDeleteMyAccountUnlinkedKeepsRetryEligibleOnFailure(t *testing.T) {
	ctx := context.Background()
	s, h := newHookedService(t)
	applicant := Principal{UID: "u_lobby", Role: domain.RoleMember, CenterID: testCenter}
	if _, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"}); err != nil {
		t.Fatal(err)
	}
	// 대기실 상태로 인덱스가 심긴 계정(member_id 없이) — ⑦이 지울 대상이 실재하는 경우.
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{
		UID: "u_lobby", Role: domain.RoleMember, CenterID: testCenter,
	}); err != nil {
		t.Fatal(err)
	}
	h.reset()

	boom := errors.New("firestore unavailable")
	h.fail = func(op string, _ int) error {
		if op == "DeleteJoinRequestsByUID" {
			return boom
		}
		return nil
	}
	if _, err := s.DeleteMyAccount(ctx, applicant); !errors.Is(err, boom) {
		t.Fatalf("DeleteMyAccount = %v, want %v", err, boom)
	}
	if _, err := s.store.GetUserIndex(ctx, "u_lobby"); err != nil {
		t.Errorf("UserIndex가 사라졌다(%v) — ⑦이 ⑤보다 뒤여야 재시도가 가능하다", err)
	}

	h.fail = nil
	res, err := s.DeleteMyAccount(ctx, applicant) // 같은 토큰으로 재시도
	if err != nil {
		t.Fatalf("재시도: %v", err)
	}
	if res.Purged.JoinRequests != 1 {
		t.Errorf("재시도 purged.join_requests = %d, want 1", res.Purged.JoinRequests)
	}
	if _, err := s.store.GetUserIndex(ctx, "u_lobby"); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("재시도 후 UserIndex = %v, want ErrNotFound", err)
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
			// 계약도 무접촉이어야 한다(v2.17 자리 검증): void 스윕은 외부 파기 **뒤**다 —
			// 주체 파기가 확정되기 전에 무효화하면, 탈퇴가 좌초됐을 때 살아 있는 회원의
			// 계약이 이유 없이 voided로 남는다.
			if cs, _ := s.store.ListContracts(ctx, testCenter, mem.ID, ""); len(cs) != 1 || cs[0].Status != domain.ContractStatusSent {
				t.Errorf("외부 파기 실패인데 계약이 이미 무효화됐다(%d건, 첫 건 status 확인) — %+v", len(cs), cs)
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

// 탈퇴는 미서명 계약을 종결한다(v2.17, P40). 서명 주체(Firebase 계정)가 파기되므로 draft/sent의
// "서명 대기"는 더 이상 사실이 아니다 — 남겨두면 어드민 미서명 카운트에 영원히 행동 불가능한
// 항목으로 잡힌다(P37·P38 적대 리뷰 [H]). signed는 성립했던 거래의 법적 기록이라 불가침이고,
// 문서 수는 변하지 않는다(void는 삭제가 아니다 — 5년 보존은 문서 보존).
func TestDeleteMyAccountVoidsUnsignedContracts(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedWithdrawableMember(t, s) // 발급 자동 계약 = sent(buildContractForPass)

	// 구권 픽스처 2건 — store.CreateContract는 시딩 전용 경로(패스 문서 없는 계약도 실데이터에
	// 존재: TransitionContract가 pass=nil로 판정한다). draft는 void 대상, signed는 불가침 대조군.
	now := time.Now().UTC()
	draftID, err := s.store.CreateContract(ctx, testCenter, &domain.Contract{
		MemberID: mem.ID, PassID: "p-old-draft", Product: "PT 10회(구권)", PaidAmount: 300_000,
		Status: domain.ContractStatusDraft,
	})
	if err != nil {
		t.Fatal(err)
	}
	// v2.21(P44): 자필 서명 이미지가 있는 signed — 탈퇴 비파기가 서명 이미지까지 포함하는지
	// (계약 문서 내 저장이 5년 보존을 자동 상속하는지, P44 결정 2)를 함께 고정한다.
	signedID, err := s.store.CreateContract(ctx, testCenter, &domain.Contract{
		MemberID: mem.ID, PassID: "p-old-signed", Product: "PT 30회(구권)", PaidAmount: 1_500_000,
		Status: domain.ContractStatusSigned, SignedAt: &now, SignerIP: "1.2.3.4",
		SignaturePNG:    "aWNvbg==",
		SignatureSHA256: "2222222222222222222222222222222222222222222222222222222222222222",
	})
	if err != nil {
		t.Fatal(err)
	}

	res, err := s.DeleteMyAccount(ctx, memberP(mem.ID))
	if err != nil {
		t.Fatalf("DeleteMyAccount: %v", err)
	}
	if res.Retained.Contracts != 3 {
		t.Errorf("retained.contracts = %d, want 3 — void가 문서를 지웠다면 보존 의무 위반", res.Retained.Contracts)
	}

	contracts, err := s.store.ListContracts(ctx, testCenter, mem.ID, "")
	if err != nil || len(contracts) != 3 {
		t.Fatalf("계약 %d건(err=%v), want 3", len(contracts), err)
	}
	for _, c := range contracts {
		switch c.ID {
		case draftID:
			if c.Status != domain.ContractStatusVoided {
				t.Errorf("draft 계약 = %q, want voided", c.Status)
			}
		case signedID:
			if c.Status != domain.ContractStatusSigned || c.SignedAt == nil || c.SignerIP != "1.2.3.4" {
				t.Errorf("signed 계약이 훼손됐다: %q(signed_at=%v, ip=%q) — 법적 기록은 불가침",
					c.Status, c.SignedAt, c.SignerIP)
			}
			if c.SignaturePNG != "aWNvbg==" || c.SignatureSHA256 == "" {
				t.Errorf("탈퇴가 서명 이미지를 파기했다: png=%q hash=%q — 서명 이미지는 계약 문서의 일부로 비파기(P44)",
					c.SignaturePNG, c.SignatureSHA256)
			}
		default: // 발급 자동 계약(sent)
			if c.PassID != pass.ID {
				t.Fatalf("예상 밖의 계약: %+v", c)
			}
			if c.Status != domain.ContractStatusVoided {
				t.Errorf("sent 계약 = %q, want voided", c.Status)
			}
		}
	}
	// 어드민 "미서명" 축(sent 필터)에서 이 회원이 사라졌는지 — 이 결함의 증상 그 자체였다.
	if sent, _ := s.store.ListContracts(ctx, testCenter, mem.ID, domain.ContractStatusSent); len(sent) != 0 {
		t.Errorf("탈퇴 후 sent 계약이 %d건 — 어드민 미서명 카운트에 영원히 잡힌다", len(sent))
	}
}

// void 스윕 도중의 부분 실패는 전체를 500으로 멈추고(가명화·UserIndex 비접촉 — 재시도 자격
// 보존), 같은 토큰의 재시도는 이미 voided를 스킵하고 나머지만 마저 종결한다(멱등). P22의
// 실행 순서 규약 안에서 4단계 void가 안전한지를 결정적으로 재현한다.
func TestDeleteMyAccountVoidSweepRetryIsIdempotent(t *testing.T) {
	ctx := context.Background()
	s, h := newHookedService(t)
	mem, _ := seedWithdrawableMember(t, s) // 자동 계약(sent) — ID 오름차순으로 스윕의 1번째
	if _, err := s.store.CreateContract(ctx, testCenter, &domain.Contract{
		MemberID: mem.ID, PassID: "p-old", Status: domain.ContractStatusDraft,
	}); err != nil { // 스윕의 2번째 — 부분 실패를 만들려면 후보가 둘 필요하다
		t.Fatal(err)
	}
	h.reset()

	boom := errors.New("firestore unavailable")
	h.fail = func(op string, n int) error {
		if op == "TransitionContract" && n == 2 {
			return boom // 첫 계약은 voided로 커밋, 두 번째에서 끊는다 — 부분 성공 잔존 재현
		}
		return nil
	}
	if _, err := s.DeleteMyAccount(ctx, memberP(mem.ID)); !errors.Is(err, boom) {
		t.Fatalf("부분 실패 DeleteMyAccount = %v, want %v", err, boom)
	}
	cs, _ := s.store.ListContracts(ctx, testCenter, mem.ID, "") // ID 오름차순(ListContracts 규약)
	if len(cs) != 2 || cs[0].Status != domain.ContractStatusVoided || cs[1].Status != domain.ContractStatusDraft {
		t.Fatalf("부분 실패 상태 = %+v, want [voided, draft] — 각 void는 독립 CAS다", cs)
	}
	after, err := s.store.GetMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if after.IsWithdrawn() {
		t.Errorf("void 스윕 실패인데 이미 가명화됐다 — 스윕(4단계)이 가명화(5단계)보다 앞이어야 미완료가 보인다")
	}
	if _, err := s.store.GetUserIndex(ctx, "u-"+mem.ID); err != nil {
		t.Errorf("UserIndex가 사라졌다(%v) — 재시도 자격을 잃는다", err)
	}

	h.fail = nil
	res, err := s.DeleteMyAccount(ctx, memberP(mem.ID)) // 같은 토큰으로 재시도(P22)
	if err != nil {
		t.Fatalf("재시도: %v", err)
	}
	if !res.Deleted || res.Retained.Contracts != 2 {
		t.Errorf("재시도 응답 = %+v, want deleted + retained.contracts 2", res)
	}
	for _, c := range mustListContracts(t, s, mem.ID) {
		if c.Status != domain.ContractStatusVoided {
			t.Errorf("재시도 후 계약 %s = %q, want voided", c.ID, c.Status)
		}
	}
	// 멱등의 형태까지 고정한다: 첫 시도 2회(성공 1 + 실패 1) + 재시도 1회(남은 draft) = 총 3회.
	// 4회 이상이면 재시도가 이미 voided인 계약에 트랜잭션을 다시 열고 있다는 뜻이다(사전 판정 누락).
	if got := h.callCount("TransitionContract"); got != 3 {
		t.Errorf("TransitionContract 호출 = %d회, want 3 — 이미 voided는 스냅샷 판정에서 걸러져야 한다", got)
	}
}

func mustListContracts(t *testing.T, s *Service, memberID string) []domain.Contract {
	t.Helper()
	cs, err := s.store.ListContracts(context.Background(), testCenter, memberID, "")
	if err != nil {
		t.Fatal(err)
	}
	return cs
}

// 후보 선정 뒤·CAS 직전에 끼어든 서명은 스킵(보존)된다 — 트랜잭션 안 재판정이 sentinel
// (errWithdrawalVoidSkip)로 "쓰지 않고 통과"를 표현하는 자리(P40).
// TestRefundVoidSkipsContractSignedMidflight의 탈퇴판이다. 계약 보존은 스킵 판정이지 탈퇴의
// 실패가 아니므로 탈퇴 자체는 완주해야 한다.
func TestDeleteMyAccountVoidSkipsContractSignedMidflight(t *testing.T) {
	ctx := context.Background()
	s, h := newHookedService(t)
	mem, _ := seedWithdrawableMember(t, s)
	cs, err := s.ListContracts(ctx, ownerP(), mem.ID, "")
	if err != nil || len(cs) != 1 {
		t.Fatalf("계약 목록: %v %d건", err, len(cs))
	}
	cid := cs[0].ID
	h.reset()

	reached, release := make(chan struct{}), make(chan struct{})
	h.before = latchOnFirstWrite(reached, release)

	delErr := make(chan error, 1)
	go func() {
		_, err := s.DeleteMyAccount(ctx, memberP(mem.ID))
		delErr <- err
	}()
	select {
	case <-reached: // 스윕이 후보(sent)를 담고 첫 TransitionContract 직전에 멈춰 있다
	case <-time.After(5 * time.Second):
		// 래치가 안 열리면 스윕이 쓰기에 도달하지 않은 것이다(후보 선정 오류·스윕 소실).
		// 여기서 끊지 않으면 go test 전체 타임아웃(10분)까지 행이다 — 실패를 빨리 말한다.
		t.Fatal("void 스윕이 TransitionContract에 도달하지 않았다")
	}
	// 마지막 순간의 서명 — 계정 파기 후에도 ID 토큰은 최대 1시간 살아 있다(provision.go).
	if _, err := s.SignContract(ctx, memberP(mem.ID), cid, "1.2.3.4", nil); err != nil {
		t.Fatalf("서명: %v", err)
	}
	close(release)
	if err := <-delErr; err != nil {
		t.Fatalf("막판 서명이 탈퇴를 실패시켰다: %v — 보존은 스킵이지 에러가 아니다", err)
	}
	h.before = nil

	saved, err := h.Store.GetContract(ctx, testCenter, cid)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusSigned || saved.SignedAt == nil || saved.SignerIP != "1.2.3.4" {
		t.Fatalf("끼어든 서명이 무효화됐다: %s(signed_at=%v, ip=%q) — signed는 보존(v1.5)",
			saved.Status, saved.SignedAt, saved.SignerIP)
	}
	if after, _ := s.store.GetMember(ctx, testCenter, mem.ID); after == nil || !after.IsWithdrawn() {
		t.Errorf("탈퇴가 완주하지 못했다: %+v", after)
	}
}

// 탈퇴 회원에게 새 의무·새 데이터를 붙이지 못한다(스태프 경로 — 탈퇴자는 스스로 호출할 수 없다).
func TestWithdrawnMemberBlocksNewWrites(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	kst := time.Now().In(domain.KST)
	mem, pass := seedWithdrawableMember(t, s)
	if _, err := s.DeleteMyAccount(ctx, memberP(mem.ID)); err != nil {
		t.Fatal(err)
	}

	t.Run("계약 생성", func(t *testing.T) {
		// v2.17 급소: 탈퇴 void가 "패스당 유효 계약 1건" 가드의 분모(비voided)를 비우므로,
		// 탈퇴 가드가 없으면 같은 패스에 새 draft가 다시 생긴다 — 서명 주체가 없어 영원히
		// 미서명인 계약을 방금 닫은 자리에서 재생산하는 유일한 경로였다.
		_, err := s.CreateContract(ctx, ownerP(), ContractCreateRequest{MemberID: mem.ID, PassID: pass.ID})
		if !errors.Is(err, errBadRequest) {
			t.Errorf("탈퇴 회원 계약 생성 = %v, want 400", err)
		}
	})

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
	for _, key := range []string{
		"body_photos", "inbody", "workout_logs", "hw_checks", "checkins", "recurrings",
		"consult_requests", "join_requests", // v2.26 · P53
	} {
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

	// 탈퇴 후 같은 uid로 다시 부르면 **200 + 전부 0**이다(v2.27에서 404에서 바뀌었다).
	//
	// 왜 바뀌었나: 탈퇴는 UserIndex를 지우므로 그 토큰의 principal은 member_id가 없는 상태가
	// 된다 — 그것은 **아직 연결되지 않은 대기실 계정과 완전히 같은 모양**이다(둘 다 role=member,
	// member_id=""). 서버가 둘을 구별할 수단이 없고, 대기실 계정에는 지울 것이 실재하므로
	// (join_requests의 이름·전화번호 + Firebase 계정 — C-3의 근거) 그 경로는 반드시 열려야 한다.
	// 그래서 이쪽도 같은 경로를 탄다.
	//
	// "이미 지웠다"가 200으로 다시 보고되는 것 아닌가 — 아니다. 이 응답이 말하는 것은 "이
	// 계정에 남은 것이 없다"이고 그것은 사실이다(purged 전부 0, member_id는 빈 문자열). 실제로
	// 이 호출이 가능한 창은 Firebase 계정 삭제 후 ID 토큰이 살아 있는 최대 1시간뿐이다.
	again := deleteReq(t, r, "/v1/me", "u-app", "member")
	if again.Code != http.StatusOK {
		t.Fatalf("두 번째 DELETE /v1/me = %d %s, want 200(대기실 계정과 같은 경로)", again.Code, again.Body.String())
	}
	var second map[string]any
	if err := json.Unmarshal(again.Body.Bytes(), &second); err != nil {
		t.Fatal(err)
	}
	if second["member_id"] != "" {
		t.Errorf("두 번째 응답 member_id = %v, want \"\" — 가리킬 회원이 없다", second["member_id"])
	}
	if p, _ := second["purged"].(map[string]any); p["join_requests"] != float64(0) {
		t.Errorf("두 번째 응답 purged.join_requests = %v, want 0 — 지울 것이 남아 있지 않다", p["join_requests"])
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

// 탈퇴 회원은 **회원권·Home Work 스코프 KPI에서도** 빠진다(v2.37, P73). 종전엔 회원 루프만
// 걸렀다: 탈퇴 시 유효기간이 남은 패스는 "만료 임박(연장 제안)"에 그대로 잡혔고(연락처는 이미
// 파기됐다), 배정 대상에 남은 탈퇴자는 hw-check가 전부 삭제되므로 완료율 분모만 채웠다.
func TestWithdrawnMemberExcludedFromExpiringAndHomework(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	kst := time.Now().In(domain.KST)
	seedTrainerRecord(t, s, "t1", "정혜린")

	// 탈퇴할 회원 — 3일 뒤 만료되는 패스(정책 기본 expiring_days=7 안) + 진행 중 배정.
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "김민지", Phone: "010-1234-5678", TrainerID: "t1", Status: domain.MemberStatusActive,
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: "PT 10회", PaidAmount: 500_000, TotalSessions: 10,
		ValidFrom: kst.AddDate(0, 0, -20).Format("2006-01-02"), ValidUntil: kst.AddDate(0, 0, 3).Format("2006-01-02"),
	}); err != nil {
		t.Fatal(err)
	}
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{
		UID: "u-" + mem.ID, Role: domain.RoleMember, CenterID: testCenter, MemberID: mem.ID,
	}); err != nil {
		t.Fatal(err)
	}
	// 남는 회원 — 같은 배정의 대조군(분모 1이 남아야 한다).
	other, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "박현우", Phone: "010-2345-6789", TrainerID: "t1", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateHomework(ctx, ownerP(), HomeworkCreateRequest{
		TrainerID: "t1", Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{mem.ID, other.ID},
		Items:    []domain.HwItem{{Name: "스쿼트", Sets: 3, Reps: "12"}},
		Schedule: domain.HwSchedule{Type: "weekly", Days: []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}},
	}); err != nil {
		t.Fatal(err)
	}

	before, err := s.Stats(ctx, ownerP(), "", "center")
	if err != nil {
		t.Fatal(err)
	}
	if before.Expiring != 1 || before.HwD != 2 {
		t.Fatalf("픽스처 전제가 깨졌다: 탈퇴 전 expiring=%d hw_d=%d, want 1/2", before.Expiring, before.HwD)
	}

	if _, err := s.DeleteMyAccount(ctx, memberP(mem.ID)); err != nil {
		t.Fatal(err)
	}
	after, err := s.Stats(ctx, ownerP(), "", "center")
	if err != nil {
		t.Fatal(err)
	}
	if after.Expiring != 0 {
		t.Errorf("expiring = %d, want 0 — 탈퇴자의 남은 패스가 '연장 제안' 대상으로 잡히고 있다", after.Expiring)
	}
	if after.HwD != 1 {
		t.Errorf("hw_d = %d, want 1 — 탈퇴자가 Home Work 완료율 분모에 남아 있다", after.HwD)
	}
	// 트레이너 비교표도 같은 판정을 써야 한다(같은 헬퍼를 지나는지 배선까지 본다).
	for _, row := range after.ByTrainer {
		if row.UID == "t1" && row.HwD != 1 {
			t.Errorf("by_trainer[t1].hw_d = %d, want 1", row.HwD)
		}
	}
}
