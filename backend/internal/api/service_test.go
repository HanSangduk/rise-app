package api

// 서비스 오케스트레이션 통합 테스트(인메모리 스토어). domain 골든값 테스트가 못 잡는
// 레이어(스코프 강제·원장 순서·상태 전이·정합 패치 동작)를 고정한다 — P01 교차검증에서
// 발견된 CRITICAL/HIGH 버그들의 회귀 방지.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/config"
	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

const testCenter = "rise"

func newTestService() *Service {
	return NewService(store.NewMemory(), config.Config{
		DefaultCenterID: testCenter,
	}, nil) // users=nil → dev 합성 uid 프로비저너(Firebase SDK·네트워크 없이 스태프 생성 테스트)
}

// newProdModeService — FIREBASE_PROJECT가 설정된 **프로덕션 모드** 서비스. dev 모드에만 있는
// 바디 전화번호 폴백이 꺼지는 분기를 검증하기 위해 필요하다. 이 생성자가 없으면 배포된 코드의
// join 계열 인증 경로를 어떤 테스트도 지나가지 않는다(SDK는 여전히 안 붙는다 — 토큰 검증은
// Authenticator 소관이고 Service는 Principal.Phone만 본다).
func newProdModeService() *Service {
	return NewService(store.NewMemory(), config.Config{
		DefaultCenterID: testCenter,
		FirebaseProject: "rize-test",
	}, nil)
}

func ownerP() Principal {
	return Principal{UID: "owner1", Role: domain.RoleOwner, CenterID: testCenter}
}
func trainerP() Principal {
	return Principal{UID: "t1", Role: domain.RoleTrainer, CenterID: testCenter}
}
func memberP(memberID string) Principal {
	return Principal{UID: "u-" + memberID, Role: domain.RoleMember, CenterID: testCenter, MemberID: memberID}
}

// seedTrainerRecord — Staff 레코드만 심는다(멱등 upsert). **UserIndex는 건드리지 않는다** —
// join·인증 계열 테스트가 "이 uid엔 인덱스가 없다"를 전제로 하는 경우가 있어서다
// (그쪽이 필요하면 service_staff_test.go의 seedStaff를 쓴다).
//
// 계약 v2.1부터 CreatePass가 담당 코치의 실존·재직을 검사하므로, 패스를 만드는 픽스처는
// 코치를 먼저 심어야 한다. 테스트를 느슨하게 만든 게 아니라 픽스처가 실제 데이터 상태
// (코치 없이 회원권이 발급될 수 없다)를 따라간 것이다.
func seedTrainerRecord(t *testing.T, s *Service, uid, name string) {
	t.Helper()
	if err := s.store.SaveStaff(context.Background(), testCenter, &domain.Staff{
		UID: uid, Role: domain.RoleTrainer, Name: name, Color: "#f43f5e",
		Status: domain.StaffStatusActive, Offdays: []string{},
	}); err != nil {
		t.Fatalf("SaveStaff(%s): %v", uid, err)
	}
}

// seedMemberWithPass — 회원 생성 + 패스 발급(원장 issue 포함) 헬퍼.
func seedMemberWithPass(t *testing.T, s *Service, sessions int) (*domain.Member, *domain.Pass) {
	t.Helper()
	ctx := context.Background()
	kst := time.Now().In(domain.KST)
	seedTrainerRecord(t, s, "t1", "정혜린")
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "김민지", Phone: "010-1234-5678", TrainerID: "t1", Status: domain.MemberStatusActive,
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatalf("CreateMember: %v", err)
	}
	pass, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: fmt.Sprintf("PT %d회", sessions),
		PaidAmount: 1_000_000, TotalSessions: sessions,
		ValidFrom:  kst.AddDate(0, 0, -1).Format("2006-01-02"),
		ValidUntil: kst.AddDate(0, 0, 90).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatalf("CreatePass: %v", err)
	}
	return mem, pass
}

func slotKeyDaysAhead(days, hour int) string {
	return time.Now().In(domain.KST).AddDate(0, 0, days).Format("20060102") + fmt.Sprintf("-%02d", hour)
}

// newTestRouter — dev 헤더 인증이 붙은 실제 라우터(FIREBASE_PROJECT 미설정 → SDK·네트워크 불필요).
// 대부분의 테스트는 서비스를 직접 부르지만, 상태코드 매핑(201/400/403/409)까지 봐야 하는
// 경로는 라우터를 태워야 writeErr까지 함께 고정된다.
func newTestRouter(t *testing.T) http.Handler {
	t.Helper()
	st := store.NewMemory()
	cfg := config.Config{DefaultCenterID: testCenter}
	auth, err := NewAuthenticator(context.Background(), cfg, st)
	if err != nil {
		t.Fatalf("NewAuthenticator: %v", err)
	}
	return NewRouter(NewHandlers(NewService(st, cfg, auth.Provisioner())), auth, nil)
}

func postJSON(t *testing.T, r http.Handler, path, uid, role, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Dev-Uid", uid)
	req.Header.Set("X-Dev-Role", role)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

// CRITICAL-1 회귀: 발급 직후 정상 예약이 성공해야 한다(저장 스냅샷 remaining=0 버그).
func TestBookingSucceedsRightAfterPassIssue(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)

	b, err := s.CreateBooking(ctx, memberP(mem.ID), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 10), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatalf("발급 직후 예약이 실패: %v", err)
	}
	if b.TrainerID != "t1" || b.Status != domain.BookingConfirmed {
		t.Errorf("booking = %+v", b)
	}
}

// v1.2: 슬롯 날짜가 패스 유효기간 밖이면 거부(오늘 기준만 보던 갭).
func TestBookingRejectsSlotOutsideValidity(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)

	_, err := s.CreateBooking(ctx, memberP(mem.ID), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(120, 10), MemberID: mem.ID, PassID: pass.ID, // valid_until(+90d) 밖
	})
	if err == nil || !errors.Is(err, errBadRequest) {
		t.Fatalf("유효기간 밖 슬롯인데 err = %v", err)
	}
}

// HIGH-4 회귀: complete 이중 호출은 두 번째가 400, 원장 차감은 1회만.
func TestCompleteBookingIsGuardedAgainstDoubleCall(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	b, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 11), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteBooking(ctx, ownerP(), b.ID); err != nil {
		t.Fatalf("1차 complete: %v", err)
	}
	if _, err := s.CompleteBooking(ctx, ownerP(), b.ID); err == nil {
		t.Fatal("2차 complete가 통과 — 이중 차감 가드 실패")
	}
	entries, err := s.store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got := domain.Sum(entries); got != 19 {
		t.Errorf("잔여 = %d, want 19(발급 20 - 완료 1)", got)
	}
}

// HIGH-3 회귀: 노쇼 유예는 최초 1회만 — 두 번째 노쇼는 차감돼야 한다.
func TestNoshowGraceAppliesOnlyOnce(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)

	for i, wantReason := range []string{domain.ReasonNoshowWaive, domain.ReasonNoshow} {
		b, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
			SlotKey: slotKeyDaysAhead(i+1, 14), MemberID: mem.ID, PassID: pass.ID,
		})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := s.NoshowBooking(ctx, ownerP(), b.ID); err != nil {
			t.Fatal(err)
		}
		entries, _ := s.store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
		newest := entries[0] // ListLedger는 최신 먼저 정렬(store 계약)
		if newest.Reason != wantReason {
			t.Fatalf("%d번째 노쇼 reason = %s, want %s", i+1, newest.Reason, wantReason)
		}
	}
	entries, _ := s.store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if got := domain.Sum(entries); got != 19 {
		t.Errorf("잔여 = %d, want 19(1회 유예 + 1회 차감)", got)
	}
}

// CRITICAL-2 회귀: member_id가 빈 member 호출자는 목록 엔드포인트에서 403(전체 노출 차단).
func TestUnlinkedMemberCannotListAnything(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedMemberWithPass(t, s, 20)
	unlinked := Principal{UID: "rando", Role: domain.RoleMember, CenterID: testCenter} // MemberID 없음

	if _, err := s.ListPasses(ctx, unlinked, ""); !errors.Is(err, ErrForbidden) {
		t.Errorf("ListPasses err = %v, want ErrForbidden", err)
	}
	if _, err := s.ListBookings(ctx, unlinked, "다른회원id", ""); !errors.Is(err, ErrForbidden) {
		t.Errorf("ListBookings err = %v, want ErrForbidden", err)
	}
	if _, err := s.ListPayments(ctx, unlinked, ""); !errors.Is(err, ErrForbidden) {
		t.Errorf("ListPayments err = %v, want ErrForbidden", err)
	}
	if _, err := s.ListContracts(ctx, unlinked, "", ""); !errors.Is(err, ErrForbidden) {
		t.Errorf("ListContracts err = %v, want ErrForbidden", err)
	}
	if _, err := s.ListHomeworks(ctx, unlinked, "", ""); !errors.Is(err, ErrForbidden) {
		t.Errorf("ListHomeworks err = %v, want ErrForbidden", err)
	}
	if _, err := s.ListHwChecks(ctx, unlinked, "", "", ""); !errors.Is(err, ErrForbidden) {
		t.Errorf("ListHwChecks err = %v, want ErrForbidden", err)
	}
	if _, err := s.ListMembers(ctx, unlinked, "", ""); !errors.Is(err, ErrForbidden) {
		t.Errorf("ListMembers err = %v, want ErrForbidden", err)
	}
}

// member는 member= 쿼리로 타인을 지정해도 본인 것만 본다(조용한 스코프 강제 — v1.1 패턴).
func TestMemberScopeIsForcedToSelf(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	memA, passA := seedMemberWithPass(t, s, 20)
	memB, _ := seedMemberWithPass(t, s, 10)

	list, err := s.ListPasses(ctx, memberP(memA.ID), memB.ID) // 타인 지정 시도
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != passA.ID {
		t.Errorf("member가 본 패스 = %+v, want 본인(%s) 1건", list, passA.ID)
	}
}

// v1.2: member의 GET /v1/members = 본인 1건(passes 임베드) — 회원 앱 "내 프로필" 경로.
func TestMemberSeesOwnProfileViaListMembers(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)

	out, err := s.ListMembers(ctx, memberP(mem.ID), "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(out) != 1 || out[0].ID != mem.ID {
		t.Fatalf("out = %+v, want 본인 1건", out)
	}
	if len(out[0].Passes) != 1 || out[0].Passes[0].ID != pass.ID || out[0].Passes[0].Remaining != 20 {
		t.Errorf("임베드 passes = %+v, want 잔여 20 실계산 1건", out[0].Passes)
	}
}

// v1.2: member 본인 consent 갱신(PUT 머지) — 전이 시각은 서버가 기록, 다른 필드는 못 건드림.
func TestMemberConsentUpdateTransitions(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20)
	p := memberP(mem.ID)

	// 철회: sensitive true→false → revoked_at 기록 → 촬영 게이트 잠김.
	got, err := s.UpdateMember(ctx, p, mem.ID, []byte(`{"consent":{"general":true,"sensitive":false}}`))
	if err != nil {
		t.Fatal(err)
	}
	if got.Consent.RevokedAt == nil || got.Consent.SensitiveConsentValid() {
		t.Errorf("철회 후 consent = %+v, want revoked_at 설정 + invalid", got.Consent)
	}
	// 재동의: false→true → signed_at 갱신 + revoked_at 해제.
	got, err = s.UpdateMember(ctx, p, mem.ID, []byte(`{"consent":{"general":true,"sensitive":true}}`))
	if err != nil {
		t.Fatal(err)
	}
	if got.Consent.SignedAt == nil || got.Consent.RevokedAt != nil || !got.Consent.SensitiveConsentValid() {
		t.Errorf("재동의 후 consent = %+v", got.Consent)
	}
	// consent 외 필드 셀프 수정 시도는 400(미지 필드 거부).
	if _, err := s.UpdateMember(ctx, p, mem.ID, []byte(`{"name":"해커","consent":{"general":true}}`)); err == nil {
		t.Error("member가 name을 수정했는데 통과 — 셀프 권한 상승 차단 실패")
	}
	// 타인 레코드는 403.
	other, _ := seedMemberWithPass(t, s, 10)
	if _, err := s.UpdateMember(ctx, p, other.ID, []byte(`{"consent":{"general":false}}`)); !errors.Is(err, ErrForbidden) {
		t.Errorf("타인 consent 수정 err = %v, want ErrForbidden", err)
	}
}

// HIGH-9 회귀: 스태프의 부분 PUT이 보내지 않은 필드(app_linked 등)를 지우지 않는다(머지 시맨틱).
func TestStaffPartialPutMergesOntoExisting(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20)
	mem.AppLinked = true
	if _, err := s.store.SaveMember(ctx, testCenter, mem); err != nil {
		t.Fatal(err)
	}

	got, err := s.UpdateMember(ctx, ownerP(), mem.ID, []byte(`{"name":"김민지(개명)"}`))
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "김민지(개명)" {
		t.Errorf("name = %s", got.Name)
	}
	if !got.AppLinked || got.Phone != "010-1234-5678" || got.TrainerID != "t1" {
		t.Errorf("부분 PUT이 기존 필드를 지움: %+v", got)
	}
}

// v1.2: member 셀프 홀딩 — 정책 상한(2회/총 30일) 강제, 스태프는 상한 없음.
func TestMemberSelfHoldWithinPolicyLimits(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	p := memberP(mem.ID)
	kst := time.Now().In(domain.KST)
	day := func(d int) string { return kst.AddDate(0, 0, d).Format("2006-01-02") }

	if _, err := s.HoldPass(ctx, p, pass.ID, HoldRequest{From: day(10), To: day(19), Reason: "여행"}); err != nil {
		t.Fatalf("1차 셀프 홀딩(10일): %v", err)
	}
	if _, err := s.HoldPass(ctx, p, pass.ID, HoldRequest{From: day(30), To: day(39), Reason: "부상"}); err != nil {
		t.Fatalf("2차 셀프 홀딩(10일): %v", err)
	}
	if _, err := s.HoldPass(ctx, p, pass.ID, HoldRequest{From: day(50), To: day(51)}); err == nil ||
		!errors.Is(err, domain.ErrHoldLimitExceeded) {
		t.Fatalf("3차 셀프 홀딩이 상한(2회)을 통과: err = %v", err)
	}
	// 스태프는 상한 무시 가능(데스크 예외).
	if _, err := s.HoldPass(ctx, ownerP(), pass.ID, HoldRequest{From: day(50), To: day(51)}); err != nil {
		t.Fatalf("스태프 3차 홀딩: %v", err)
	}
	// 타인 패스는 403.
	other, otherPass := seedMemberWithPass(t, s, 10)
	_ = other
	if _, err := s.HoldPass(ctx, p, otherPass.ID, HoldRequest{From: day(10), To: day(11)}); !errors.Is(err, ErrForbidden) {
		t.Errorf("타인 패스 홀딩 err = %v, want ErrForbidden", err)
	}
}

// v1.2: member 본인 refund-quote 허용(마이탭 환불 계산기) — 골든값 그대로.
func TestMemberCanQuoteOwnRefund(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)

	quote, err := s.RefundQuote(ctx, memberP(mem.ID), pass.ID, 7)
	if err != nil {
		t.Fatal(err)
	}
	if quote.Refund != 550_000 || quote.PerSession != 50_000 || quote.Usage != 350_000 || quote.Penalty != 100_000 {
		t.Errorf("quote = %+v, want 골든값(550,000)", quote)
	}
}

// MEDIUM-5 회귀: recurring 선행 생성이 잔여 세션을 초과하지 않는다 + 패스 소유 검증.
func TestRecurringRespectsRemainingAndOwnership(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 2) // 잔여 2회뿐

	kst := time.Now().In(domain.KST)
	r, err := s.CreateRecurring(ctx, trainerP(), RecurringCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID,
		Days: []string{"mon", "tue", "wed", "thu", "fri"}, Hour: 9,
		Until: kst.AddDate(0, 0, 60).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatal(err)
	}
	bookings, err := s.store.ListBookingsByMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	created := 0
	for _, b := range bookings {
		if b.RecurringID == r.ID {
			created++
		}
	}
	if created > 2 {
		t.Errorf("recurring이 잔여(2)를 초과해 %d건 생성", created)
	}
	// 패스 소유가 다른 트레이너면 403.
	if _, err := s.CreateRecurring(ctx, Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter},
		RecurringCreateRequest{MemberID: mem.ID, TrainerID: "t2", PassID: pass.ID, Days: []string{"mon"}, Hour: 9}); err == nil {
		t.Error("타 트레이너 패스로 recurring 생성이 통과")
	}
}

// v1.2: 트레이너 scope=center 통계 — 금액(monthly/ytd/target)·by_trainer는 비운다(P13).
func TestTrainerCenterStatsAreRedacted(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	if err := s.store.SaveStaff(ctx, testCenter, &domain.Staff{UID: "t1", Role: domain.RoleTrainer, Name: "정혜린"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 1_000_000,
	}); err != nil {
		t.Fatal(err)
	}

	tStats, err := s.Stats(ctx, trainerP(), "ytd", "center")
	if err != nil {
		t.Fatalf("트레이너 scope=center가 403 — P45 센터 평균 비교 불가: %v", err)
	}
	if tStats.YTD != 0 || tStats.Monthly != nil || tStats.ByTrainer != nil || tStats.Target != 0 {
		t.Errorf("트레이너 center 통계에 금액/비교표가 노출: %+v", tStats)
	}
	oStats, err := s.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	if oStats.YTD != 1_000_000 || len(oStats.ByTrainer) == 0 {
		t.Errorf("owner center 통계 = ytd %d, by_trainer %d명", oStats.YTD, len(oStats.ByTrainer))
	}
}

// P44: self_qr 체크인 — qr_token 검증 + 시간창 내 예약 자동 탐색 + last_visit_at 갱신.
//
// P49(v2.23): 대조값의 출처가 환경변수에서 **센터 문서에 저장된 토큰**으로 바뀌었다. 픽스처가
// config 한 줄에서 seedCheckinToken으로 옮겨간 것이 그 차이 전부다 — 시간창 탐색·last_visit_at
// 갱신은 그대로다. 발급·재발급·누출 방지는 service_checkin_qr_test.go가 따로 본다.
func TestSelfQRCheckinFindsBookingInWindow(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	seedCheckinToken(t, s, "test-qr-token")

	// 시간창(±30분)에 확실히 들어오는 슬롯: 분<30이면 현재 정시(경계 :30:xx flaky 방지 — 2R),
	// 아니면 다음 정시. 현재 정시는 "지난 시간" 예약 거부(v1.3)에 걸리므로 스토어에 직접 심는다
	// (실플로우: 예약은 며칠 전, 체크인은 수업 시각 — 생성 시점 검증과 무관).
	slotKey := seedBookingInCheckinWindow(t, s, mem, pass)

	p := memberP(mem.ID)
	if _, err := s.Checkin(ctx, p, CheckinRequest{Source: "self_qr", QRToken: "wrong"}); err == nil {
		t.Error("잘못된 qr_token이 통과")
	}
	got, err := s.Checkin(ctx, p, CheckinRequest{Source: "self_qr", QRToken: "test-qr-token"})
	if err != nil {
		t.Fatalf("self_qr 체크인 실패: %v", err)
	}
	if got.SlotKey != slotKey {
		t.Errorf("체크인된 예약 = %s, want %s", got.SlotKey, slotKey)
	}
	saved, _ := s.store.GetMember(ctx, testCenter, mem.ID)
	if saved.LastVisitAt == nil {
		t.Error("체크인 후 last_visit_at 미갱신")
	}
}

// 2R HIGH-2 회귀: 완료/취소된 예약의 재취소 금지(상태 뒤집힘·노쇼 원장 재적재 방지).
func TestCancelBookingGuardedByStatus(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	b, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(2, 10), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteBooking(ctx, ownerP(), b.ID); err != nil {
		t.Fatal(err)
	}
	if err := s.CancelBooking(ctx, ownerP(), b.ID, false); err == nil {
		t.Fatal("완료된 예약의 취소가 통과 — 완료 소실+이중 차감 가드 실패")
	}
	entries, _ := s.store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if got := domain.Sum(entries); got != 19 {
		t.Errorf("잔여 = %d, want 19(완료 1회만 차감)", got)
	}
}

// 2R HIGH-1 회귀: member 셀프 홀딩의 시간축 검증 — 과거/겹침/유효기간 밖 거부, 스태프는 예외.
func TestMemberHoldWindowValidation(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	p := memberP(mem.ID)
	kst := time.Now().In(domain.KST)
	day := func(d int) string { return kst.AddDate(0, 0, d).Format("2006-01-02") }

	if _, err := s.HoldPass(ctx, p, pass.ID, HoldRequest{From: day(-30), To: day(-1), Reason: "과거"}); err == nil {
		t.Fatal("과거 구간 셀프 홀딩이 통과 — 공짜 연장 가드 실패")
	}
	if _, err := s.HoldPass(ctx, p, pass.ID, HoldRequest{From: day(120), To: day(121)}); err == nil {
		t.Fatal("유효기간(+90d) 밖 시작 셀프 홀딩이 통과")
	}
	if _, err := s.HoldPass(ctx, p, pass.ID, HoldRequest{From: day(10), To: day(14)}); err != nil {
		t.Fatalf("정상 홀딩 실패: %v", err)
	}
	if _, err := s.HoldPass(ctx, p, pass.ID, HoldRequest{From: day(12), To: day(16)}); err == nil {
		t.Fatal("겹치는 셀프 홀딩이 통과 — 이중 연장 가드 실패")
	}
	// 스태프는 과거 정정 허용(데스크 예외).
	if _, err := s.HoldPass(ctx, ownerP(), pass.ID, HoldRequest{From: day(-10), To: day(-8), Reason: "정정"}); err != nil {
		t.Fatalf("스태프 과거 정정 홀딩 실패: %v", err)
	}
}

// v1.3: 시간축은 슬롯 기준 — 미래 시작(scheduled 성격) 패스의 선예약 허용 + 지난 시간 거부.
func TestBookingUsesSlotTimeAxis(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	kst := time.Now().In(domain.KST)
	seedTrainerRecord(t, s, "t1", "정혜린")
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "선예약", Phone: "010-2222-3333", TrainerID: "t1", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	pass, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: "PT 10회", PaidAmount: 500_000, TotalSessions: 10,
		ValidFrom:  kst.AddDate(0, 0, 10).Format("2006-01-02"), // 열흘 뒤 시작
		ValidUntil: kst.AddDate(0, 0, 100).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatal(err)
	}
	// 시작 전인 오늘 기준으로도, 유효기간 안의 슬롯이면 선예약 성공(재등록 플로우).
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(12, 10), MemberID: mem.ID, PassID: pass.ID,
	}); err != nil {
		t.Fatalf("미래 시작 패스의 유효기간 내 선예약이 거부됨: %v", err)
	}
	// 유효기간 시작 전 날짜의 슬롯은 거부.
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(5, 10), MemberID: mem.ID, PassID: pass.ID,
	}); err == nil {
		t.Fatal("유효기간 시작 전 슬롯 예약이 통과")
	}
	// 이미 지난 시간대 거부(2R HIGH — 어제 슬롯).
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(-1, 10), MemberID: mem.ID, PassID: pass.ID,
	}); err == nil {
		t.Fatal("지난 슬롯 예약이 통과")
	}
}

// 2R HIGH-4 회귀: join/confirm은 전화번호 재대조 필수 — 유출된 member_id만으로 연결 불가.
func TestJoinConfirmRequiresPhoneMatch(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20)
	attacker := Principal{UID: "attacker", Role: domain.RoleMember, CenterID: testCenter}

	if _, err := s.JoinConfirm(ctx, attacker, JoinConfirmRequest{MemberID: mem.ID, Confirm: true}); err == nil {
		t.Fatal("전화번호 없이 confirm 통과 — 계정 탈취 체인 가드 실패")
	}
	if _, err := s.JoinConfirm(ctx, attacker, JoinConfirmRequest{MemberID: mem.ID, Confirm: true, Phone: "010-9999-9999"}); err == nil {
		t.Fatal("틀린 전화번호로 confirm 통과")
	}
	res, err := s.JoinConfirm(ctx, Principal{UID: "realuser", Role: domain.RoleMember, CenterID: testCenter},
		JoinConfirmRequest{MemberID: mem.ID, Confirm: true, Phone: "010-1234-5678"})
	if err != nil || !res.Linked {
		t.Fatalf("정상 confirm 실패: %v linked=%v", err, res.Linked)
	}
}

// P08 CRITICAL 회귀: 프로덕션(Firebase) 모드에서 **검증된 번호가 없는 계정**은 join 계열을
// 쓸 수 없다. 이 가드가 없으면 프로젝트에 이메일 계정만 만들면(자체 가입 기본 허용) 남의
// 전화번호를 바디에 실어 그 회원 레코드에 연결할 수 있었다 — 완전한 계정 탈취였다.
// 어드민(이메일 로그인) 토큰에는 phone_number 클레임이 없으므로 스태프도 같은 경로였다.
func TestJoinRequiresVerifiedPhoneInProduction(t *testing.T) {
	s := newProdModeService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20) // 김민지 010-1234-5678

	// 전화 인증을 거치지 않은 계정 — 토큰에 phone_number가 없다.
	noPhone := Principal{UID: "u_email_acct", Role: domain.RoleMember, CenterID: testCenter}

	if _, err := s.JoinMatch(ctx, noPhone, "010-1234-5678"); !errors.Is(err, ErrForbidden) {
		t.Fatalf("검증 번호 없이 match 통과 = %v, want ErrForbidden(PII 오라클)", err)
	}
	if _, err := s.JoinConfirm(ctx, noPhone,
		JoinConfirmRequest{MemberID: mem.ID, Confirm: true, Phone: "010-1234-5678"}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("검증 번호 없이 confirm 통과 = %v, want ErrForbidden(계정 탈취)", err)
	}
	// 권한 검사가 조회보다 앞이어야 한다 — 없는 member_id에도 404가 아니라 403이 나와야
	// 존재 여부를 캐낼 수 없다(프로덕션 실측에서 404가 나와 순서 결함을 찾았다).
	if _, err := s.JoinConfirm(ctx, noPhone,
		JoinConfirmRequest{MemberID: "mem_does_not_exist", Confirm: true, Phone: "010-1234-5678"}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("없는 member_id에 %v — 403이어야 한다(존재 오라클)", err)
	}
	if _, err := s.JoinRequestCreate(ctx, noPhone,
		JoinRequestBody{Name: "사칭", Phone: "010-1234-5678"}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("검증 번호 없이 가입요청 통과 = %v, want ErrForbidden", err)
	}

	// 반대로 검증된 번호가 있으면 프로덕션에서도 정상 동작해야 한다(과잉 차단 방지).
	verified := Principal{UID: "u_phone_acct", Role: domain.RoleMember, CenterID: testCenter, Phone: "+821012345678"}
	res, err := s.JoinMatch(ctx, verified, "")
	if err != nil || !res.NeedsConfirm || res.Member == nil || res.Member.ID != mem.ID {
		t.Fatalf("검증 번호로 match 실패: %v %+v", err, res)
	}
	if out, err := s.JoinConfirm(ctx, verified,
		JoinConfirmRequest{MemberID: mem.ID, Confirm: true}); err != nil || !out.Linked {
		t.Fatalf("검증 번호로 confirm 실패: %v", err)
	}
}

// P08 CRITICAL 회귀: 스태프 계정은 회원으로 연결될 수 없다. UserIndex가 역할의 단일 출처라
// role=member로 덮이면 되돌릴 API가 없고, 대상이 마지막 대표면 센터가 영구히 잠긴다.
func TestJoinNeverDemotesStaff(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20)

	// owner1을 실제 UserIndex에 심는다(운영과 동일 — enrich가 이 문서로 역할을 판정한다).
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{
		UID: "owner1", Role: domain.RoleOwner, CenterID: testCenter,
	}); err != nil {
		t.Fatal(err)
	}

	// 대표가 회원 번호를 알고 confirm을 호출 — 예전엔 200 + 본인 강등이었다.
	if _, err := s.JoinConfirm(ctx, ownerP(),
		JoinConfirmRequest{MemberID: mem.ID, Confirm: true, Phone: "010-1234-5678"}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("대표 confirm = %v, want ErrForbidden(자가 강등·센터 락아웃)", err)
	}
	idx, err := s.store.GetUserIndex(ctx, "owner1")
	if err != nil || idx.Role != domain.RoleOwner {
		t.Fatalf("대표 역할이 훼손됨: %v role=%v", err, idx)
	}

	// 가입 요청 경로도 같은 가드(승인 시점에 강등되는 우회로).
	if _, err := s.JoinRequestCreate(ctx, ownerP(),
		JoinRequestBody{Name: "대표", Phone: "010-5555-4444"}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("대표 가입요청 = %v, want ErrForbidden", err)
	}
}

// P08 회귀: 가입 승인은 멱등이다. 상태를 안 보면 두 번 눌러 같은 사람의 회원 레코드가 둘 생기고
// 먼저 만든 쪽이 고아가 된다(목록·통계엔 남는데 UserIndex는 나중 것만 가리킨다).
func TestJoinApproveIsIdempotent(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	applicant := Principal{UID: "u_new", Role: domain.RoleMember, CenterID: testCenter}

	jr, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: "신규회원", Phone: "010-7777-1111"})
	if err != nil {
		t.Fatal(err)
	}
	first, err := s.JoinApprove(ctx, ownerP(), jr.ID)
	if err != nil {
		t.Fatalf("첫 승인 실패: %v", err)
	}
	if _, err := s.JoinApprove(ctx, ownerP(), jr.ID); !errors.Is(err, ErrConflict) {
		t.Fatalf("중복 승인 = %v, want ErrConflict(회원 중복 생성)", err)
	}
	members, err := s.ListMembers(ctx, ownerP(), "", "")
	if err != nil {
		t.Fatal(err)
	}
	count := 0
	for _, m := range members {
		if m.Name == "신규회원" {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("신규회원 레코드 %d건, want 1(중복 승인이 고아 레코드를 만들었다)", count)
	}
	idx, err := s.store.GetUserIndex(ctx, "u_new")
	if err != nil || idx.MemberID != first.ID {
		t.Fatalf("UserIndex가 첫 레코드를 가리키지 않음: %v %+v", err, idx)
	}
}

// P08 회귀: 연결 전 단계 응답에 부상 메모(건강정보)·동의·방문이력이 실리면 안 된다.
// 번호만 알면 확인 1탭 전에 이것들이 통째로 노출됐다.
func TestJoinMatchOmitsSensitiveFields(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedTrainerRecord(t, s, "t1", "정혜린") // v2.1: 회원 등록도 담당 코치의 실존을 검사한다
	if _, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "부상회원", Phone: "010-8888-2222", TrainerID: "t1", Status: domain.MemberStatusActive,
		Channel: "인스타",
		Flags:   []domain.MemberFlag{{Type: domain.FlagInjury, Note: "어깨 회전근개"}},
	}); err != nil {
		t.Fatal(err)
	}
	res, err := s.JoinMatch(ctx, Principal{UID: "u_x", Role: domain.RoleMember, CenterID: testCenter},
		"010-8888-2222")
	if err != nil || res.Member == nil {
		t.Fatalf("매칭 실패: %v", err)
	}
	blob, err := json.Marshal(res)
	if err != nil {
		t.Fatal(err)
	}
	for _, leaked := range []string{"어깨 회전근개", "injury", "flags", "consent", "channel", "인스타", "last_visit_at"} {
		if strings.Contains(string(blob), leaked) {
			t.Errorf("연결 전 응답에 %q 노출: %s", leaked, blob)
		}
	}
	// 확인 1탭에 필요한 필드는 남아 있어야 한다(앱 MemberDto의 필수 필드 포함).
	for _, need := range []string{"부상회원", "010-8888-2222", "trainer_id", "status"} {
		if !strings.Contains(string(blob), need) {
			t.Errorf("확인 화면에 필요한 %q가 빠짐: %s", need, blob)
		}
	}
}

// P06 회귀: Firebase 토큰의 phone_number(E.164)가 가입 매칭의 진실 원천이다.
// 두 가지를 동시에 못박는다 — (1) 국내 표기로 저장된 회원과 E.164 토큰이 매칭될 것,
// (2) 바디의 클라이언트 제공 번호로는 타인 레코드에 닿을 수 없을 것.
func TestJoinUsesVerifiedTokenPhone(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20) // 김민지 010-1234-5678

	// 토큰 번호는 본인, 바디는 위조 — 토큰이 이기므로 본인 레코드를 찾아야 한다.
	owner := Principal{UID: "u_real", Role: domain.RoleMember, CenterID: testCenter, Phone: "+821012345678"}
	res, err := s.JoinMatch(ctx, owner, "010-9999-9999")
	if err != nil {
		t.Fatal(err)
	}
	if !res.NeedsConfirm || res.Member == nil || res.Member.ID != mem.ID {
		t.Fatalf("E.164 토큰 번호로 국내 표기 회원 매칭 실패: %+v", res)
	}

	// 공격자 토큰 + 피해자 번호를 바디에 실어도 매칭되면 안 된다.
	attacker := Principal{UID: "u_attacker", Role: domain.RoleMember, CenterID: testCenter, Phone: "+821099998888"}
	res, err = s.JoinMatch(ctx, attacker, "010-1234-5678")
	if err != nil {
		t.Fatal(err)
	}
	if res.NeedsConfirm || res.Member != nil {
		t.Fatal("바디 전화번호로 타인 매칭 성공 — 토큰 우선 규칙이 깨졌다")
	}
	if _, err := s.JoinConfirm(ctx, attacker,
		JoinConfirmRequest{MemberID: mem.ID, Confirm: true, Phone: "010-1234-5678"}); err == nil {
		t.Fatal("바디 전화번호로 confirm 통과 — 계정 탈취 체인")
	}

	// 정상 경로: 토큰 번호만으로(바디 없이) 연결된다 — 앱 실연동의 실제 호출 모양.
	confirmed, err := s.JoinConfirm(ctx, owner, JoinConfirmRequest{MemberID: mem.ID, Confirm: true})
	if err != nil || !confirmed.Linked {
		t.Fatalf("토큰 번호만으로 confirm 실패: %v linked=%v", err, confirmed.Linked)
	}
}

// P06 회귀: join/request도 토큰 번호 규칙을 따른다 — 승인 시 이 번호가 회원 레코드로 굳으므로
// 타인 번호 선점(요청 → owner 승인 → 그 번호의 회원 생성)을 입구에서 막아야 한다.
func TestJoinRequestPhoneMustMatchToken(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	p := Principal{UID: "u_new", Role: domain.RoleMember, CenterID: testCenter, Phone: "+821012345678"}

	if _, err := s.JoinRequestCreate(ctx, p, JoinRequestBody{Name: "사칭", Phone: "010-9999-8888"}); err == nil {
		t.Fatal("인증한 번호와 다른 번호로 가입 요청 통과 — 번호 선점 체인")
	}

	// 같은 번호를 국내 표기로 보내면 통과하고, 입력 표기가 그대로 보존된다(어드민 가독성).
	jr, err := s.JoinRequestCreate(ctx, p, JoinRequestBody{Name: "김민지", Phone: "010-1234-5678"})
	if err != nil {
		t.Fatalf("본인 번호 가입 요청 실패: %v", err)
	}
	if jr.Phone != "010-1234-5678" {
		t.Fatalf("입력 표기가 보존되지 않음: %q", jr.Phone)
	}

	// 번호 미입력이면 토큰의 검증된 번호로 채운다.
	jr2, err := s.JoinRequestCreate(ctx, p, JoinRequestBody{Name: "김민지"})
	if err != nil || jr2.Phone != "+821012345678" {
		t.Fatalf("미입력 시 토큰 번호 폴백 실패: %v phone=%q", err, jr2.Phone)
	}

	// dev 모드(토큰 번호 없음)는 기존 동작 유지 — 바디 값 그대로.
	dev := Principal{UID: "u_dev", Role: domain.RoleMember, CenterID: testCenter}
	jr3, err := s.JoinRequestCreate(ctx, dev, JoinRequestBody{Name: "개발", Phone: "010-5555-6666"})
	if err != nil || jr3.Phone != "010-5555-6666" {
		t.Fatalf("dev 폴백 경로 깨짐: %v phone=%q", err, jr3.Phone)
	}
}

// 감사 회귀: 가입 요청의 센터는 토큰이 정한다 — 바디의 center_id를 그대로 저장하면 존재하지
// 않는 센터로도 200이 나가고, 그 요청은 어느 owner 목록에도 뜨지 않아 영원히 pending으로 남는다.
func TestJoinRequestIgnoresBodyCenterID(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	applicant := Principal{UID: "u_new", Role: domain.RoleMember, CenterID: testCenter}

	jr, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{
		CenterID: "존재하지-않는-센터", Name: "신규회원", Phone: "010-7777-1111",
	})
	if err != nil {
		t.Fatal(err)
	}
	if jr.CenterID != testCenter {
		t.Fatalf("바디 center_id가 저장됨: %q (want %q — 센터는 토큰이 정한다)", jr.CenterID, testCenter)
	}

	// 대표의 큐에 실제로 떠야 하고(예전엔 안 떴다), 원탭 승인까지 이어져야 한다.
	list, err := s.ListJoinRequests(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, item := range list {
		if item.ID == jr.ID {
			found = true
		}
	}
	if !found {
		t.Fatalf("가입 요청이 대표 목록에 없음 — 신청자는 영원히 기다린다: %+v", list)
	}
	if _, err := s.JoinApprove(ctx, ownerP(), jr.ID); err != nil {
		t.Fatalf("승인 실패: %v (예전엔 jr.CenterID 불일치로 403이었다)", err)
	}
}

// 감사 회귀: 같은 번호를 쓰는 회원이 여럿일 때 매칭이 **결정적**이어야 한다. 부모 번호로
// 자녀 둘을 등록하는 건 흔한데, 스토어가 순서 없는 스캔의 첫 히트를 돌려줘서 같은 요청이
// 호출마다 다른 사람을 반환했다(실측 60회 중 55/5). 확인 1탭에 뜨는 이름이 그때그때 바뀌고,
// 재시도 한 번에 엉뚱한 레코드로 연결될 수 있었다.
func TestJoinMatchIsDeterministicForSharedPhone(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	const shared = "010-1234-5678"
	seedTrainerRecord(t, s, "t1", "정혜린") // v2.1: 회원 등록도 담당 코치의 실존을 검사한다

	newSharedMember := func(name, phone string) *domain.Member {
		t.Helper()
		mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
			Name: name, Phone: phone, TrainerID: "t1", Status: domain.MemberStatusActive,
		})
		if err != nil {
			t.Fatalf("CreateMember(%s): %v", name, err)
		}
		return mem
	}
	mom := newSharedMember("엄마", shared)               // 가장 먼저 등록 → ID 최소
	firstKid := newSharedMember("첫째", "+821012345678") // 표기만 다른 같은 번호
	newSharedMember("둘째", shared)

	// 엄마가 먼저 앱에 연결된다 — 이 레코드는 주인이 생겼다.
	if out, err := s.JoinConfirm(ctx, Principal{UID: "u_mom", Role: domain.RoleMember, CenterID: testCenter},
		JoinConfirmRequest{MemberID: mom.ID, Confirm: true, Phone: shared}); err != nil || !out.Linked {
		t.Fatalf("엄마 연결 실패: %v", err)
	}

	// 이후 같은 번호로 들어오는 자녀 계정은 매번 같은 레코드를 봐야 한다:
	// 미연결(app_linked=false) 우선 → 그중 ID 오름차순 = 첫째.
	applicant := Principal{UID: "u_kid", Role: domain.RoleMember, CenterID: testCenter}
	for i := range 60 {
		res, err := s.JoinMatch(ctx, applicant, shared)
		if err != nil || res.Member == nil {
			t.Fatalf("%d회차 매칭 실패: %v %+v", i, err, res)
		}
		if res.Member.ID != firstKid.ID {
			t.Fatalf("%d회차에 %s(%s) 반환 — 매칭이 비결정적이다(want %s 첫째)",
				i, res.Member.Name, res.Member.ID, firstKid.ID)
		}
	}
}

// 2R HIGH-4a 회귀: member의 홈워크 응답에서 대상/제외 명단(회원 ID·부상 명단) 제거 + 제외 회원 미배달.
func TestHomeworkRedactionForMembers(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	memA, _ := seedMemberWithPass(t, s, 20)
	memB, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "부상회원", Phone: "010-7777-8888", TrainerID: "t1", Status: domain.MemberStatusActive,
		Flags: []domain.MemberFlag{{Type: domain.FlagInjury, Note: "어깨"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateHomework(ctx, ownerP(), HomeworkCreateRequest{
		Scope: domain.HwScopeCenterNotice, TrainerID: "owner1",
		Items:    []domain.HwItem{{Name: "스트레칭"}},
		Schedule: domain.HwSchedule{Type: "weekly"},
	}); err != nil {
		t.Fatal(err)
	}
	listA, err := s.ListHomeworks(ctx, memberP(memA.ID), "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(listA) != 1 {
		t.Fatalf("공지형 홈워크가 일반 회원에게 %d건(want 1)", len(listA))
	}
	if listA[0].TargetMemberIDs != nil || listA[0].Excluded != nil {
		t.Errorf("member 응답에 대상/제외 명단 노출: %+v", listA[0])
	}
	listB, err := s.ListHomeworks(ctx, memberP(memB.ID), "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(listB) != 0 {
		t.Errorf("부상 자동제외 회원에게 공지형 홈워크 %d건 배달(want 0)", len(listB))
	}
}

// ---- v1.4 기능 회귀 ----

// v1.4: 수업 기록 — 스코프(트레이너 본인 명의 강제·member 본인만 조회)와 booking 연결 검증.
func TestWorkoutLogScopes(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	b, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 9), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	wl, err := s.CreateWorkoutLog(ctx, trainerP(), WorkoutLogCreateRequest{
		MemberID: mem.ID, BookingID: b.ID, Title: "1:1 PT",
		Exercises: []domain.Exercise{{Name: "스쿼트", Sets: 3, Reps: "12", WeightKG: 40}},
		CoachNote: "좋았음",
	})
	if err != nil {
		t.Fatalf("트레이너 수업 기록 생성 실패: %v", err)
	}
	if wl.TrainerID != "t1" {
		t.Errorf("trainer_id = %s, want t1(본인 명의 강제)", wl.TrainerID)
	}
	// member는 본인 기록만 조회(타인 지정해도 본인으로 강제).
	other, _ := seedMemberWithPass(t, s, 10)
	list, err := s.ListWorkoutLogs(ctx, memberP(mem.ID), other.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].MemberID != mem.ID {
		t.Errorf("member 조회 = %+v, want 본인 1건", list)
	}
	// member는 생성 불가.
	if _, err := s.CreateWorkoutLog(ctx, memberP(mem.ID), WorkoutLogCreateRequest{MemberID: mem.ID}); !errors.Is(err, ErrForbidden) {
		t.Errorf("member 생성 err = %v, want ErrForbidden", err)
	}
	// 타 트레이너의 예약에 기록 연결 시도 → 403.
	if _, err := s.CreateWorkoutLog(ctx, Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter},
		WorkoutLogCreateRequest{MemberID: mem.ID, BookingID: b.ID}); !errors.Is(err, ErrForbidden) {
		t.Errorf("타 트레이너 booking 연결 err = %v, want ErrForbidden", err)
	}
}

// v1.4: 환불 실행 — owner 전용, 원장 refund로 잔여 0 마감 + status 전이 + 이중 실행 가드.
func TestRefundPassExecution(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	// 7회 사용 상태 재현: complete 원장 7건 직접 적재.
	for i := 0; i < 7; i++ {
		if _, err := s.store.AppendLedger(ctx, testCenter, &domain.Ledger{
			PassID: pass.ID, MemberID: mem.ID, Delta: -1, Reason: domain.ReasonComplete, By: "t1", At: time.Now().UTC(),
		}); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := s.RefundPass(ctx, trainerP(), pass.ID, 7); !errors.Is(err, ErrForbidden) {
		t.Fatalf("트레이너 환불 실행이 통과: %v", err)
	}
	got, quote, err := s.RefundPass(ctx, ownerP(), pass.ID, 7)
	if err != nil {
		t.Fatal(err)
	}
	if quote.Refund != 550_000 {
		t.Errorf("quote.refund = %d, want 550,000(골든값)", quote.Refund)
	}
	if got.Status != domain.PassStatusRefunded || got.Remaining != 0 {
		t.Errorf("pass = status %s remaining %d, want refunded/0", got.Status, got.Remaining)
	}
	entries, _ := s.store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if sum := domain.Sum(entries); sum != 0 {
		t.Errorf("원장 합 = %d, want 0(refund 이벤트로 마감)", sum)
	}
	if entries[0].Reason != domain.ReasonRefund {
		t.Errorf("최신 원장 reason = %s, want refund", entries[0].Reason)
	}
	if _, _, err := s.RefundPass(ctx, ownerP(), pass.ID, 7); err == nil {
		t.Fatal("이중 환불 실행이 통과")
	}
}

// v1.4: 정책 편집 — owner 전용 + 범위 검증 + member의 center 조회(금액 제외) 허용.
func TestCenterPolicyEditAndVisibility(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20)

	polJSON := func(pol domain.Policy) []byte {
		b, err := json.Marshal(pol)
		if err != nil {
			t.Fatal(err)
		}
		return b
	}
	pol := domain.DefaultPolicy()
	pol.CancelCutoffHours = 12
	pol.RevenueTarget = 120_000_000
	if _, err := s.UpdateCenterPolicy(ctx, trainerP(), polJSON(pol)); !errors.Is(err, ErrForbidden) {
		t.Fatalf("트레이너 정책 편집이 통과: %v", err)
	}
	bad := pol
	bad.SlotCapacity = 0
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), polJSON(bad)); !errors.Is(err, domain.ErrInvalidPolicy) {
		t.Fatalf("용량 0 정책이 통과: %v", err)
	}
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), polJSON(pol)); err != nil {
		t.Fatal(err)
	}
	// 머지 시맨틱(P03): 일부 필드만 보내도 기존 값(grace_once·revenue_target)이 보존된다.
	partial, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"slot_capacity":4}`))
	if err != nil {
		t.Fatal(err)
	}
	if partial.Policy.SlotCapacity != 4 || !partial.Policy.GraceOnce || partial.Policy.RevenueTarget != 120_000_000 {
		t.Errorf("부분 PUT이 기존 정책을 초기화: %+v", partial.Policy)
	}
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), polJSON(pol)); err != nil {
		t.Fatal(err) // 이후 단언을 위해 원상 복구
	}
	// member 조회 허용 + 금액(revenue_target) 제외.
	res, err := s.GetCenter(ctx, memberP(mem.ID))
	if err != nil {
		t.Fatalf("member의 GET /v1/center가 거부됨(v1.4 공개): %v", err)
	}
	if res.Policy.CancelCutoffHours != 12 {
		t.Errorf("member가 본 컷오프 = %d, want 12(실정책)", res.Policy.CancelCutoffHours)
	}
	if res.Policy.RevenueTarget != 0 {
		t.Errorf("member에게 매출 목표 노출: %d", res.Policy.RevenueTarget)
	}
	own, _ := s.GetCenter(ctx, ownerP())
	if own.Policy.RevenueTarget != 120_000_000 {
		t.Errorf("owner 매출 목표 = %d", own.Policy.RevenueTarget)
	}
}

// v1.4: 계약 서명 — member 본인만, sent→signed 전이 + 서버가 signed_at/signer_ip 기록.
func TestContractSignByMember(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20) // CreatePass가 sent 계약 자동 생성
	contracts, err := s.ListContracts(ctx, ownerP(), mem.ID, "")
	if err != nil || len(contracts) == 0 {
		t.Fatalf("계약 목록: %v %d건", err, len(contracts))
	}
	cid := contracts[0].ID
	other, _ := seedMemberWithPass(t, s, 10)
	if _, err := s.SignContract(ctx, memberP(other.ID), cid, "1.2.3.4", nil); !errors.Is(err, ErrForbidden) {
		t.Fatalf("타인 계약 서명이 통과: %v", err)
	}
	signed, err := s.SignContract(ctx, memberP(mem.ID), cid, "1.2.3.4", nil)
	if err != nil {
		t.Fatal(err)
	}
	if signed.Status != domain.ContractStatusSigned || signed.SignedAt == nil || signed.SignerIP != "1.2.3.4" {
		t.Errorf("signed = %+v", signed)
	}
	if _, err := s.SignContract(ctx, memberP(mem.ID), cid, "1.2.3.4", nil); err == nil {
		t.Fatal("signed 계약 재서명이 통과")
	}
}

// v1.4: 고정 스케줄 목록 — owner 전체·trainer 본인만·member 403.
func TestListRecurringsScopes(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	kst := time.Now().In(domain.KST)
	if _, err := s.CreateRecurring(ctx, trainerP(), RecurringCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID, Days: []string{"tue"}, Hour: 20,
		Until: kst.AddDate(0, 0, 30).Format("2006-01-02"),
	}); err != nil {
		t.Fatal(err)
	}
	if list, err := s.ListRecurrings(ctx, ownerP(), false); err != nil || len(list) != 1 {
		t.Errorf("owner 목록 = %v %d건, want 1", err, len(list))
	}
	if list, err := s.ListRecurrings(ctx, Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}, false); err != nil || len(list) != 0 {
		t.Errorf("타 트레이너 목록 = %v %d건, want 0", err, len(list))
	}
	if _, err := s.ListRecurrings(ctx, memberP(mem.ID), false); !errors.Is(err, ErrForbidden) {
		t.Errorf("member 목록 err = %v, want ErrForbidden", err)
	}
}

// v1.4: 미수금(owner 전용)·세션 수 통계.
func TestStatsUnpaidAndSessions(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "transfer", Total: 1_000_000,
		Installments: []domain.Installment{
			{Due: time.Now().In(domain.KST).AddDate(0, 0, -20).Format("2006-01-02"), Amount: 600_000,
				PaidAt: func() *time.Time { t := time.Now().UTC(); return &t }()},
			// v1.5: 미수금=연체 기준이라 due를 과거로 — 이 회차가 unpaid_total에 잡혀야 한다.
			{Due: time.Now().In(domain.KST).AddDate(0, 0, -5).Format("2006-01-02"), Amount: 400_000},
		},
	}); err != nil {
		t.Fatal(err)
	}
	b, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 13), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteBooking(ctx, trainerP(), b.ID); err != nil {
		t.Fatal(err)
	}
	oStats, err := s.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	if oStats.UnpaidTotal != 400_000 || oStats.UnpaidCount != 1 {
		t.Errorf("미수금 = %d원 %d건, want 400,000원 1건", oStats.UnpaidTotal, oStats.UnpaidCount)
	}
	tStats, err := s.Stats(ctx, trainerP(), "ytd", "me")
	if err != nil {
		t.Fatal(err)
	}
	if tStats.Sessions != 1 {
		t.Errorf("트레이너 sessions = %d, want 1(본인 정산 근거)", tStats.Sessions)
	}
	if tStats.UnpaidTotal != 0 {
		t.Errorf("트레이너에게 미수금 노출: %d", tStats.UnpaidTotal)
	}
}

// v2.1: 비율 지표는 **분모를 함께** 내려보낸다. Rate()가 분모 0에 0을 돌려주므로 비율만으로는
// "성과 0"과 "모수 없음"을 가를 수 없는데, 화면에서 둘은 정반대 뜻이다(신규 센터의 0%가 성과
// 실패로 읽힌다). 클라이언트가 "—"로 표시할 근거를 서버가 줘야 한다.
//
// 함께 고정하는 것: 분모가 **비율 계산에 쓴 그 값**이라는 것. 따로 세면 조용히 어긋난다.
func TestStatsCarriesRateDenominators(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)

	// ① 집계 대상이 아예 없는 상태 — 분모 0. (비율도 0이지만 뜻이 다르다.)
	empty, err := s.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	if empty.NoshowD != 0 || empty.HwD != 0 {
		t.Fatalf("모수 없는 센터의 분모 = noshow_d %d, hw_d %d, want 0/0", empty.NoshowD, empty.HwD)
	}

	// ② 완료 1 + 노쇼 1 → noshow_d=2, noshow_rate=0.5(취소·미래 예약은 분모에 안 들어간다).
	done, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 9), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteBooking(ctx, trainerP(), done.ID); err != nil {
		t.Fatal(err)
	}
	missed, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 10), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.NoshowBooking(ctx, trainerP(), missed.ID); err != nil {
		t.Fatal(err)
	}
	// 취소된 예약은 어느 쪽에도 안 잡힌다 — 분모를 부풀리는지 함께 본다.
	cancelled, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(2, 9), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CancelBooking(ctx, ownerP(), cancelled.ID, true); err != nil {
		t.Fatal(err)
	}

	// ③ 홈워크 2명 배정 중 1명만 체크 → hw_d=2, hw_rate=0.5.
	mem2, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "박현우", Phone: "010-2345-6789", TrainerID: "t1", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	hw, err := s.CreateHomework(ctx, ownerP(), HomeworkCreateRequest{
		TrainerID: "t1", Scope: domain.HwScopeIndividual,
		TargetMemberIDs: []string{mem.ID, mem2.ID},
		Items:           []domain.HwItem{{Name: "스쿼트", Sets: 3, Reps: "15"}},
		Schedule:        domain.HwSchedule{Type: "weekly", Days: []string{"mon", "wed", "fri"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateHwCheck(ctx, ownerP(), HwCheckRequest{
		MemberID: mem.ID, HwID: hw.ID, Date: time.Now().In(domain.KST).Format("2006-01-02"),
		Done: []bool{true},
	}); err != nil {
		t.Fatal(err)
	}

	got, err := s.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	if got.NoshowD != 2 {
		t.Errorf("noshow_d = %d, want 2(완료1+노쇼1 — 취소·미래는 제외)", got.NoshowD)
	}
	if got.NoshowRate != 0.5 {
		t.Errorf("noshow_rate = %v, want 0.5", got.NoshowRate)
	}
	if got.HwD != 2 {
		t.Errorf("hw_d = %d, want 2(배정 대상 수)", got.HwD)
	}
	if got.HwRate != 0.5 {
		t.Errorf("hw_rate = %v, want 0.5", got.HwRate)
	}
	// 분모가 비율 계산에 쓴 값과 같은지 — 두 수를 따로 세면 여기서 갈린다.
	if got.NoshowRate != domain.Rate(1, got.NoshowD) {
		t.Errorf("noshow_rate %v가 noshow_d %d와 정합하지 않음", got.NoshowRate, got.NoshowD)
	}
	if got.HwRate != domain.Rate(1, got.HwD) {
		t.Errorf("hw_rate %v가 hw_d %d와 정합하지 않음", got.HwRate, got.HwD)
	}

	// ④ 스코프가 바뀌면 분모도 함께 좁혀져야 한다 — 다른 코치 관점에선 모수가 0이다.
	other, err := s.Stats(ctx, Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}, "ytd", "me")
	if err != nil {
		t.Fatal(err)
	}
	if other.NoshowD != 0 || other.HwD != 0 {
		t.Errorf("타 코치 scope=me 분모 = noshow_d %d, hw_d %d, want 0/0(모수 없음)", other.NoshowD, other.HwD)
	}
}

// ---- GET /v1/stats 와이어 계약(라우터까지) ----

// keysOf — JSON 오브젝트의 키 집합(정렬). 와이어 키 비교 실패 메시지를 읽을 수 있게 한다.
func keysOf(m map[string]any) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// assertKeySet — 응답 오브젝트의 키 **집합 전체**를 고정한다. 빠진 키(오타·삭제)뿐 아니라
// 새 키도 실패시킨다 — 필드 추가는 계약 문서와 3계층을 함께 손대야 하는 일이라, 조용히
// 늘어나는 쪽이 아니라 여기서 한 번 걸리는 쪽이 싸다.
func assertKeySet(t *testing.T, what string, got map[string]any, want []string) {
	t.Helper()
	sort.Strings(want)
	gotKeys := keysOf(got)
	if len(gotKeys) != len(want) {
		t.Fatalf("%s 키 = %v\nwant %v", what, gotKeys, want)
	}
	for i := range want {
		if gotKeys[i] != want[i] {
			t.Fatalf("%s 키 = %v\nwant %v", what, gotKeys, want)
		}
	}
}

func numField(t *testing.T, what string, m map[string]any, key string) float64 {
	t.Helper()
	v, ok := m[key].(float64)
	if !ok {
		t.Fatalf("%s.%s = %v(%T), want 숫자", what, key, m[key], m[key])
	}
	return v
}

// getJSON — 라우터에 태우는 GET(dev 헤더 인증). postJSON/putJSON과 짝.
func getJSON(t *testing.T, r http.Handler, path, uid, role string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("X-Dev-Uid", uid)
	req.Header.Set("X-Dev-Role", role)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

// GET /v1/stats의 **와이어 키**를 라우터에 태워 고정한다(계약 v2.1 "검증 규약").
//
// 왜 서비스 호출 테스트로 부족한가: s.Stats(...)를 직접 부르는 테스트는 Go 필드를 보므로
// `json:"noshow_d"`가 `json:"noshowd"`로 오타 나도 전부 초록이다. 그런데 그 오타 하나면 어드민의
// 모든 비율이 분모를 못 찾아 "—"가 되고, 어드민 게이트도 자기 코드는 멀쩡하니 초록이다. 양쪽이
// 초록인 채로 화면만 죽는 조합 — blockers.slot_key를 raw JSON으로 본 것과 같은 이유·같은 방식이다.
//
// 키 집합 전체를 한 번에 고정하는 이유: 분모 2개만 보면 다음에 이름이 바뀌는 필드는 또 못 잡는다.
func TestStatsWireKeysThroughRouter(t *testing.T) {
	r := newTestRouter(t)
	kst := time.Now().In(domain.KST)

	// 트레이너 1명 온보딩 → by_trainer 행이 생기는 최소 조건.
	rec := postJSON(t, r, "/v1/staff", "owner1", domain.RoleOwner,
		`{"name":"정혜린","email":"hyerin@rise.kr","role":"trainer"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("POST /v1/staff = %d %s", rec.Code, rec.Body.String())
	}
	var staff map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &staff); err != nil {
		t.Fatal(err)
	}
	trainerUID, _ := staff["uid"].(string)

	// 회원 2명(홈워크 분모 2) + 첫 회원에게 패스·결제.
	newMember := func(name, phone string) string {
		t.Helper()
		rec := postJSON(t, r, "/v1/members", "owner1", domain.RoleOwner, fmt.Sprintf(
			`{"name":%q,"phone":%q,"trainer_id":%q,"status":"active"}`, name, phone, trainerUID))
		if rec.Code != http.StatusOK {
			t.Fatalf("POST /v1/members = %d %s", rec.Code, rec.Body.String())
		}
		var mem map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &mem); err != nil {
			t.Fatal(err)
		}
		id, _ := mem["id"].(string)
		return id
	}
	mem1, mem2 := newMember("김민지", "010-1234-5678"), newMember("박현우", "010-2345-6789")

	rec = postJSON(t, r, "/v1/passes", "owner1", domain.RoleOwner, fmt.Sprintf(
		`{"member_id":%q,"trainer_id":%q,"product":"PT 10회","paid_amount":550000,"total_sessions":10,"valid_from":%q,"valid_until":%q}`,
		mem1, trainerUID, kst.AddDate(0, 0, -1).Format("2006-01-02"), kst.AddDate(0, 0, 90).Format("2006-01-02")))
	if rec.Code != http.StatusOK {
		t.Fatalf("POST /v1/passes = %d %s", rec.Code, rec.Body.String())
	}
	var pass map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &pass); err != nil {
		t.Fatal(err)
	}
	passID, _ := pass["id"].(string)

	// monthly[]가 비어 있으면 그 안의 키(month/amount)를 고정할 수 없다 — 결제를 한 건 넣는다.
	if rec := postJSON(t, r, "/v1/payments", "owner1", domain.RoleOwner, fmt.Sprintf(
		`{"member_id":%q,"pass_id":%q,"method":"card","total":550000}`, mem1, passID)); rec.Code != http.StatusOK {
		t.Fatalf("POST /v1/payments = %d %s", rec.Code, rec.Body.String())
	}

	// 예약 2건 → 완료 1 + 노쇼 1(noshow_d=2, noshow_rate=0.5, sessions=1).
	book := func(days, hour int) string {
		t.Helper()
		rec := postJSON(t, r, "/v1/bookings", "owner1", domain.RoleOwner, fmt.Sprintf(
			`{"slot_key":%q,"member_id":%q,"pass_id":%q}`, slotKeyDaysAhead(days, hour), mem1, passID))
		if rec.Code != http.StatusOK && rec.Code != http.StatusCreated {
			t.Fatalf("POST /v1/bookings = %d %s", rec.Code, rec.Body.String())
		}
		var b map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &b); err != nil {
			t.Fatal(err)
		}
		id, _ := b["id"].(string)
		return id
	}
	if rec := postJSON(t, r, "/v1/bookings/"+book(1, 9)+"/complete", "owner1", domain.RoleOwner, ""); rec.Code != http.StatusOK {
		t.Fatalf("complete = %d %s", rec.Code, rec.Body.String())
	}
	if rec := postJSON(t, r, "/v1/bookings/"+book(1, 10)+"/noshow", "owner1", domain.RoleOwner, ""); rec.Code != http.StatusOK {
		t.Fatalf("noshow = %d %s", rec.Code, rec.Body.String())
	}

	// 홈워크 2명 배정 중 1명 체크(hw_d=2, hw_rate=0.5).
	rec = postJSON(t, r, "/v1/homeworks", "owner1", domain.RoleOwner, fmt.Sprintf(
		`{"trainer_id":%q,"scope":"individual","target_member_ids":[%q,%q],`+
			`"items":[{"name":"스쿼트","sets":3,"reps":"15"}],"schedule":{"type":"weekly","days":["mon"]}}`,
		trainerUID, mem1, mem2))
	if rec.Code != http.StatusOK {
		t.Fatalf("POST /v1/homeworks = %d %s", rec.Code, rec.Body.String())
	}
	var hw map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &hw); err != nil {
		t.Fatal(err)
	}
	if rec := postJSON(t, r, "/v1/hw-checks", "owner1", domain.RoleOwner, fmt.Sprintf(
		`{"member_id":%q,"hw_id":%q,"date":%q,"done":[true]}`,
		mem1, hw["id"], kst.Format("2006-01-02"))); rec.Code != http.StatusOK {
		t.Fatalf("POST /v1/hw-checks = %d %s", rec.Code, rec.Body.String())
	}

	// ---- 와이어 응답: Go 구조체가 아니라 **JSON 키**를 본다 ----
	rec = getJSON(t, r, "/v1/stats?range=ytd&scope=center", "owner1", domain.RoleOwner)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /v1/stats = %d %s", rec.Code, rec.Body.String())
	}
	var got map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("stats 본문 파싱 실패: %v (%s)", err, rec.Body.String())
	}
	assertKeySet(t, "stats", got, []string{
		"active_members", "registered", "rereg_rate", "rereg_n", "rereg_d",
		"unassigned", "long_absent", "expiring", "monthly", "ytd", "target",
		"noshow_rate", "noshow_d", "hw_rate", "hw_d", "sessions",
		"unpaid_total", "unpaid_count", "upcoming_total", "by_trainer",
	})
	// 분모는 비율에 쓴 그 값이다 — 키가 살아 있어도 값이 0으로 새면 화면은 똑같이 "—"가 된다.
	for _, c := range []struct {
		key  string
		want float64
	}{{"noshow_d", 2}, {"noshow_rate", 0.5}, {"hw_d", 2}, {"hw_rate", 0.5}, {"sessions", 1}, {"active_members", 2}} {
		if v := numField(t, "stats", got, c.key); v != c.want {
			t.Errorf("stats.%s = %v, want %v", c.key, v, c.want)
		}
	}

	monthly, ok := got["monthly"].([]any)
	if !ok || len(monthly) == 0 {
		t.Fatalf("stats.monthly = %v, want 1건 이상", got["monthly"])
	}
	point, ok := monthly[0].(map[string]any)
	if !ok {
		t.Fatalf("stats.monthly[0] = %v, want 오브젝트", monthly[0])
	}
	assertKeySet(t, "stats.monthly[0]", point, []string{"month", "amount"})

	rows, ok := got["by_trainer"].([]any)
	if !ok || len(rows) != 1 {
		t.Fatalf("stats.by_trainer = %v, want 1행(트레이너 1명)", got["by_trainer"])
	}
	row, ok := rows[0].(map[string]any)
	if !ok {
		t.Fatalf("stats.by_trainer[0] = %v, want 오브젝트", rows[0])
	}
	// 행의 분모 키는 top-level과 **같은 이름**이어야 한다 — 클라이언트가 "분모 0이면 —" 규칙을
	// 한 벌로 쓴다(이름이 갈리면 행마다 다른 코드가 필요해지고, 그 시점에 한쪽이 잊힌다).
	assertKeySet(t, "stats.by_trainer[0]", row, []string{
		"uid", "status", "name", "revenue", "sessions",
		"rereg_rate", "rereg_n", "rereg_d", "noshow_rate", "noshow_d", "hw_rate", "hw_d",
	})
	for _, c := range []struct {
		key  string
		want float64
	}{{"noshow_d", 2}, {"noshow_rate", 0.5}, {"hw_d", 2}, {"hw_rate", 0.5}, {"sessions", 1}, {"rereg_d", 0}} {
		if v := numField(t, "stats.by_trainer[0]", row, c.key); v != c.want {
			t.Errorf("by_trainer[0].%s = %v, want %v", c.key, v, c.want)
		}
	}

	// 트레이너 scope=me: by_trainer는 owner 전용이라 **키 자체가 사라진다**(omitempty).
	// 금액 지표도 0으로 비워지지만 키는 남는다 — 어드민이 "구버전 서버"와 헷갈리지 않게.
	rec = getJSON(t, r, "/v1/stats?range=ytd&scope=me", trainerUID, domain.RoleTrainer)
	if rec.Code != http.StatusOK {
		t.Fatalf("트레이너 GET /v1/stats = %d %s", rec.Code, rec.Body.String())
	}
	var mine map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &mine); err != nil {
		t.Fatal(err)
	}
	if _, exists := mine["by_trainer"]; exists {
		t.Errorf("트레이너 응답에 by_trainer 노출: %s", rec.Body.String())
	}
	for _, key := range []string{"noshow_d", "hw_d"} {
		if _, exists := mine[key]; !exists {
			t.Errorf("트레이너 응답에 %s 없음 — 분모는 비율이 있는 곳엔 항상 따라간다: %s", key, rec.Body.String())
		}
	}
}

// v1.4: 트레이너 휴무일 예약 거부 + DEV_SEED 시딩 스모크.
func TestOffdayBookingRejectedAndSeedSmoke(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	kst := time.Now().In(domain.KST)
	offday := kst.AddDate(0, 0, 3).Format("2006-01-02")
	if err := s.store.SaveStaff(ctx, testCenter, &domain.Staff{UID: "t1", Role: domain.RoleTrainer, Name: "정혜린", Offdays: []string{offday}}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(3, 10), MemberID: mem.ID, PassID: pass.ID,
	}); err == nil {
		t.Fatal("휴무일 예약이 통과")
	}
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(4, 10), MemberID: mem.ID, PassID: pass.ID,
	}); err != nil {
		t.Fatalf("휴무 아닌 날 예약 실패: %v", err)
	}

	// 시딩 스모크: 빈 스토어에 시딩 → 핵심 화면 데이터가 실제로 조회되는지.
	fresh := NewService(store.NewMemory(), config.Config{DefaultCenterID: testCenter}, nil)
	if err := store.SeedDemo(ctx, fresh.store, testCenter); err != nil {
		t.Fatalf("SeedDemo: %v", err)
	}
	membersOut, err := fresh.ListMembers(ctx, ownerP(), "", "")
	if err != nil || len(membersOut) != 5 {
		t.Fatalf("시딩 회원 = %v %d명, want 5", err, len(membersOut))
	}
	st, err := fresh.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	if st.UnpaidTotal != 250_000 {
		t.Errorf("시딩 미수금 = %d, want 250,000", st.UnpaidTotal)
	}
	demoMember := Principal{UID: "member1", Role: domain.RoleMember, CenterID: testCenter,
		MemberID: membersOut[0].ID} // 김민지(이름순 정렬 무관하게 uid 인덱스로 재확인
	idx, err := fresh.store.GetUserIndex(ctx, "member1")
	if err != nil {
		t.Fatal(err)
	}
	demoMember.MemberID = idx.MemberID
	logs, err := fresh.ListWorkoutLogs(ctx, demoMember, "", "")
	if err != nil || len(logs) != 2 {
		t.Errorf("시딩 수업기록 = %v %d건, want 2", err, len(logs))
	}
}

// ---- P03 검수 회귀 ----

// P03 HIGH-1: 환불 실행이 미래 confirmed 예약을 일괄 취소하고, 잔존분 완료 처리도 차단된다.
func TestRefundCancelsFutureBookings(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	b1, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(2, 10), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.RefundPass(ctx, ownerP(), pass.ID, 0); err != nil {
		t.Fatal(err)
	}
	got, err := s.store.GetBooking(ctx, testCenter, b1.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != domain.BookingCancelled {
		t.Errorf("환불 후 미래 예약 status = %s, want cancelled", got.Status)
	}
	// 슬롯 점유도 해제됐는지.
	if slot, err := s.store.GetSlot(ctx, testCenter, b1.SlotKey); err == nil && len(slot.Teams) != 0 {
		t.Errorf("환불 후 슬롯 팀 잔존: %+v", slot.Teams)
	}
	// (방어선) 어떤 경로로든 예약이 남았다면 완료 처리는 400이어야 한다 — 여기선 취소돼 있어
	// confirmed 가드에 걸리는 것으로 충분히 검증됨.
	if _, err := s.CompleteBooking(ctx, ownerP(), b1.ID); err == nil {
		t.Error("취소된(환불) 예약의 완료 처리가 통과")
	}
	entries, _ := s.store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if sum := domain.Sum(entries); sum != 0 {
		t.Errorf("환불 후 원장 합 = %d, want 0", sum)
	}
}

// P03 MEDIUM-2: used는 원장 파생값과 일치해야 한다(0 = 파생값 사용).
func TestRefundUsedCrossValidated(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	for i := 0; i < 7; i++ {
		if _, err := s.store.AppendLedger(ctx, testCenter, &domain.Ledger{
			PassID: pass.ID, MemberID: mem.ID, Delta: -1, Reason: domain.ReasonComplete, By: "t1", At: time.Now().UTC(),
		}); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := s.RefundPass(ctx, ownerP(), pass.ID, 3); err == nil {
		t.Fatal("원장(7회)과 다른 used=3이 통과 — 견적·원장 불일치 가드 실패")
	}
	_, quote, err := s.RefundPass(ctx, ownerP(), pass.ID, 0) // 0 = 원장 파생값(7회)으로 계산
	if err != nil {
		t.Fatal(err)
	}
	if quote.Refund != 550_000 {
		t.Errorf("파생 used 견적 = %d, want 550,000(7회 골든)", quote.Refund)
	}
}

// P03: refunded 패스는 홀딩·재개 불가, WorkoutLog 날짜 형식 검증, recurring 과거 시각 회차 금지.
func TestP03Guards(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	kst := time.Now().In(domain.KST)
	day := func(d int) string { return kst.AddDate(0, 0, d).Format("2006-01-02") }

	if _, _, err := s.RefundPass(ctx, ownerP(), pass.ID, 0); err != nil {
		t.Fatal(err)
	}
	if _, err := s.HoldPass(ctx, ownerP(), pass.ID, HoldRequest{From: day(1), To: day(2)}); err == nil {
		t.Error("refunded 패스 홀딩이 통과")
	}
	if _, err := s.ResumePass(ctx, ownerP(), pass.ID); err == nil {
		t.Error("refunded 패스 재개가 통과")
	}
	if _, err := s.CreateWorkoutLog(ctx, trainerP(), WorkoutLogCreateRequest{
		MemberID: mem.ID, Date: "2026-8-2",
	}); err == nil {
		t.Error("비정규 날짜(2026-8-2) 수업 기록이 통과")
	}
	if _, err := s.ListWorkoutLogs(ctx, ownerP(), "", "26-01-01"); err == nil {
		t.Error("비정규 from 필터가 통과")
	}

	// recurring: 오늘 이미 지난 시각 회차는 생성되지 않는다(매일 반복 규칙으로 검증 — 지난
	// 시각이면 오늘 회차 제외, 아니면 포함되므로 "과거 confirmed 생성 0건"만 단언).
	mem2, pass2 := seedMemberWithPass(t, s, 20)
	allDays := []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
	r, err := s.CreateRecurring(ctx, trainerP(), RecurringCreateRequest{
		MemberID: mem2.ID, TrainerID: "t1", PassID: pass2.ID, Days: allDays, Hour: 0, // 00시 — 항상 지난 시각
		Until: day(20),
	})
	if err != nil {
		t.Fatal(err)
	}
	bookings, _ := s.store.ListBookingsByMember(ctx, testCenter, mem2.ID)
	now := time.Now()
	for _, b := range bookings {
		if b.RecurringID != r.ID {
			continue
		}
		if start, err := domain.SlotStart(b.SlotKey); err == nil && start.Before(now) {
			t.Errorf("지난 시각 회차가 confirmed로 생성됨: %s", b.SlotKey)
		}
	}
}

// P03 LOW-6: 트레이너 비교표(by_trainer)에 owner 행이 섞이지 않는다.
func TestByTrainerExcludesOwner(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedMemberWithPass(t, s, 20)
	for _, st := range []domain.Staff{
		{UID: "owner1", Role: domain.RoleOwner, Name: "박관장"},
		{UID: "t1", Role: domain.RoleTrainer, Name: "정혜린"},
	} {
		stc := st
		if err := s.store.SaveStaff(ctx, testCenter, &stc); err != nil {
			t.Fatal(err)
		}
	}
	stats, err := s.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range stats.ByTrainer {
		if row.UID == "owner1" {
			t.Errorf("by_trainer에 owner 행 노출: %+v", row)
		}
	}
	if len(stats.ByTrainer) != 1 {
		t.Errorf("by_trainer 행 수 = %d, want 1(t1만)", len(stats.ByTrainer))
	}
}

// ---- P04 도메인 감사 회귀 ----

// P04 HIGH: 분할 미완납 패스 환불은 실수납 기준 + 미납 회차 청구 종결 + 미서명 계약 무효화.
func TestRefundSettlementWithPartialPayment(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	paidAt := time.Now().UTC()
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "transfer", Total: 1_000_000,
		Installments: []domain.Installment{
			{Due: "2026-08-01", Amount: 500_000, PaidAt: &paidAt},
			{Due: "2026-09-01", Amount: 500_000},
		},
	}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 7; i++ {
		if _, err := s.store.AppendLedger(ctx, testCenter, &domain.Ledger{
			PassID: pass.ID, MemberID: mem.ID, Delta: -1, Reason: domain.ReasonComplete, By: "t1", At: time.Now().UTC(),
		}); err != nil {
			t.Fatal(err)
		}
	}
	_, quote, err := s.RefundPass(ctx, ownerP(), pass.ID, 0)
	if err != nil {
		t.Fatal(err)
	}
	if quote.Refund != 50_000 || quote.PaidSum != 500_000 {
		t.Fatalf("정산 = %+v, want 실수납 500,000 기준 환불 50,000(계약가 기준 550,000 아님)", quote)
	}
	// 미납 회차 청구 종결 → 미수금 유령 제거.
	stats, err := s.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	if stats.UnpaidTotal != 0 || stats.UpcomingTotal != 0 {
		t.Errorf("환불 후 미수 = 연체 %d / 미도래 %d, want 0/0", stats.UnpaidTotal, stats.UpcomingTotal)
	}
	// 순매출: 환불 거래 제외.
	if stats.YTD != 0 {
		t.Errorf("환불 후 YTD = %d, want 0(순매출)", stats.YTD)
	}
	// 미서명(sent) 자동 계약 무효화 + 서명 시도 400.
	contracts, _ := s.ListContracts(ctx, ownerP(), mem.ID, "")
	for _, c := range contracts {
		if c.PassID == pass.ID && c.Status != domain.ContractStatusVoided {
			t.Errorf("환불 후 계약 status = %s, want voided", c.Status)
		}
	}
	if len(contracts) > 0 {
		if _, err := s.SignContract(ctx, memberP(mem.ID), contracts[0].ID, "1.2.3.4", nil); err == nil {
			t.Error("voided 계약 서명이 통과")
		}
	}
	// 종결된 회차 납부 처리 400.
	pays, _ := s.ListPayments(ctx, ownerP(), mem.ID)
	if len(pays) > 0 {
		if _, err := s.PayInstallment(ctx, ownerP(), pays[0].ID, 1); err == nil {
			t.Error("청구 종결(waived) 회차 납부 처리가 통과")
		}
	}
}

// P04: CreatePayment 검증 게이트 — 합계 불일치·음수·유령 패스·타 담당 트레이너 쓰기 차단.
func TestCreatePaymentValidationGate(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 1_000_000,
		Installments: []domain.Installment{{Due: "2026-08-01", Amount: 1}},
	}); err == nil {
		t.Error("합계(1원) ≠ 총액(100만) 결제가 통과")
	}
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: -1,
	}); err == nil {
		t.Error("음수 총액이 통과")
	}
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: "ghost", Method: "card", Total: 1000,
	}); err == nil {
		t.Error("유령 pass_id가 통과")
	}
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "bitcoin", Total: 1000,
	}); err == nil {
		t.Error("미지 결제수단이 통과")
	}
	if _, err := s.CreatePayment(ctx, Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter},
		PaymentCreateRequest{MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 1000}); !errors.Is(err, ErrForbidden) {
		t.Errorf("타 담당 트레이너 결제 생성 err = %v, want ErrForbidden", err)
	}
	// 정상 경로는 통과. 금액을 999,800원으로 둔 것은 아래 200원 건과 합쳐 계약가(1,000,000원)에
	// 정확히 맞추기 위해서다 — v2.3 계약가 상한은 "패스당 결제 1건"이 아니라 "합계 ≤ 계약가"라
	// 카드 일부 + 현금 일부 기록은 그대로 통과해야 한다.
	if _, err := s.CreatePayment(ctx, trainerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "card", Total: 999_800,
	}); err != nil {
		t.Fatalf("정상 결제 실패: %v", err)
	}
	// 납부 멱등: 회차 없는 결제엔 인덱스 밖 400은 기존 커버 — 이미 납부 회차 재처리 400 확인.
	paidAt := time.Now().UTC()
	pay, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass.ID, Method: "cash", Total: 200,
		Installments: []domain.Installment{{Due: "2026-08-01", Amount: 100, PaidAt: &paidAt}, {Due: "2026-09-01", Amount: 100}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.PayInstallment(ctx, ownerP(), pay.ID, 0); err == nil {
		t.Error("이미 납부된 회차 재처리가 통과(납부 시각 증적 덮어씀)")
	}
}

// P04: 같은 회원 같은 슬롯 이중 예약 차단(코치 달라도) + 미수금 연체/미도래 분리.
func TestMemberDoubleBookingAndOverdueSplit(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass1 := seedMemberWithPass(t, s, 20)
	// 같은 회원의 두 번째 패스(다른 코치 t2).
	seedTrainerRecord(t, s, "t2", "김태오")
	pass2, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t2", Product: "그룹 12회", PaidAmount: 360_000, TotalSessions: 12,
		ValidFrom:  time.Now().In(domain.KST).AddDate(0, 0, -1).Format("2006-01-02"),
		ValidUntil: time.Now().In(domain.KST).AddDate(0, 0, 90).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatal(err)
	}
	slot := slotKeyDaysAhead(1, 18)
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{SlotKey: slot, MemberID: mem.ID, PassID: pass1.ID}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{SlotKey: slot, MemberID: mem.ID, PassID: pass2.ID}); err == nil {
		t.Fatal("같은 회원이 코치 다른 패스로 같은 슬롯 2팀 점유가 통과")
	}

	// 미수금 분리: 연체(어제)와 미도래(내일)를 나눠 집계.
	kst := time.Now().In(domain.KST)
	if _, err := s.CreatePayment(ctx, ownerP(), PaymentCreateRequest{
		MemberID: mem.ID, PassID: pass1.ID, Method: "transfer", Total: 300_000,
		Installments: []domain.Installment{
			{Due: kst.AddDate(0, 0, -1).Format("2006-01-02"), Amount: 100_000},
			{Due: kst.AddDate(0, 0, 1).Format("2006-01-02"), Amount: 200_000},
		},
	}); err != nil {
		t.Fatal(err)
	}
	stats, err := s.Stats(ctx, ownerP(), "ytd", "center")
	if err != nil {
		t.Fatal(err)
	}
	if stats.UnpaidTotal != 100_000 || stats.UpcomingTotal != 200_000 {
		t.Errorf("연체 %d / 미도래 %d, want 100,000 / 200,000", stats.UnpaidTotal, stats.UpcomingTotal)
	}
}

// P04: tap 체크인 confirmed 가드 + 스태프 무차감 취소(waive) + recurring hour 검증.
func TestP04BookingGuards(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)
	b, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 9), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CancelBooking(ctx, ownerP(), b.ID, false); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Checkin(ctx, ownerP(), CheckinRequest{Source: "tap", BookingID: b.ID}); err == nil {
		t.Error("취소된 예약의 tap 체크인이 통과(LastVisitAt 오염 경로)")
	}
	// 컷오프 내 스태프 무차감 취소: 내일 아닌 "가장 가까운 미래 정시" 예약을 만들어 late 상태 재현이
	// 어려우므로, waive 플래그의 원장 무기록만 확인(2일 뒤 예약 — late 아님 → 어차피 무차감이나
	// 플래그 경로가 에러 없이 동작하는지와 member 무시를 본다).
	b2, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(2, 9), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CancelBooking(ctx, trainerP(), b2.ID, true); err != nil {
		t.Fatal(err)
	}
	entries, _ := s.store.ListLedger(ctx, testCenter, mem.ID, pass.ID)
	if got := domain.Sum(entries); got != 20 {
		t.Errorf("취소 2건 후 잔여 = %d, want 20(무차감)", got)
	}
	if _, err := s.CreateRecurring(ctx, trainerP(), RecurringCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", PassID: pass.ID, Days: []string{"mon"}, Hour: 25,
	}); err == nil {
		t.Error("hour=25 recurring이 통과(유령 규칙)")
	}
}

// ---- P05 트레이너 프로필(v1.6) ----

func TestStaffProfileUpdateScopesAndValidation(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedMemberWithPass(t, s, 20)
	if err := s.store.SaveStaff(ctx, testCenter, &domain.Staff{UID: "t1", Role: domain.RoleTrainer, Name: "정혜린"}); err != nil {
		t.Fatal(err)
	}
	profile := domain.StaffProfile{
		Title: "퍼포먼스 트레이너", CareerYears: 7,
		Specialties:    []string{"여성 근력"},
		Certifications: []string{"NASM-CPT"},
		Bio:            "소개",
	}
	// member 403 · 타 트레이너 403 · 본인/owner OK.
	if _, err := s.UpdateStaffProfile(ctx, memberP("memx"), "t1", profile); !errors.Is(err, ErrForbidden) {
		t.Errorf("member 프로필 수정 err = %v, want ErrForbidden", err)
	}
	if _, err := s.UpdateStaffProfile(ctx, Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}, "t1", profile); !errors.Is(err, ErrForbidden) {
		t.Errorf("타 트레이너 프로필 수정 err = %v, want ErrForbidden", err)
	}
	got, err := s.UpdateStaffProfile(ctx, trainerP(), "t1", profile)
	if err != nil {
		t.Fatalf("본인 프로필 수정 실패: %v", err)
	}
	if got.Profile.Title != "퍼포먼스 트레이너" || got.Profile.Awards == nil {
		t.Errorf("profile = %+v (Awards는 []이어야 — null 금지 규약)", got.Profile)
	}
	// 검증: 스킴 주입·범위 위반 400.
	bad := profile
	bad.PhotoURL = "javascript:alert(1)"
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", bad); !errors.Is(err, domain.ErrInvalidProfile) {
		t.Errorf("javascript: URL이 통과: %v", err)
	}
	bad = profile
	bad.CareerYears = 99
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", bad); !errors.Is(err, domain.ErrInvalidProfile) {
		t.Errorf("경력 99년이 통과: %v", err)
	}
	// ListStaff에 profile 포함 + member 조회에서도 payout만 가려지고 profile은 공개.
	list, err := s.ListStaff(ctx, memberP("memx"))
	if err != nil {
		t.Fatal(err)
	}
	for _, st := range list {
		if st.UID == "t1" {
			if st.Profile.Title != "퍼포먼스 트레이너" {
				t.Errorf("member가 본 profile = %+v", st.Profile)
			}
			if st.Payout.Value != 0 {
				t.Errorf("member에게 payout 노출: %+v", st.Payout)
			}
		}
	}
}

// ---- 스태프 온보딩(POST /v1/staff) ----

// 종전 갭 회귀: 스태프를 **만드는** 경로가 없어 SetOffdays·UpdateStaffProfile이 "이미 있는
// 스태프"에만 먹었다(둘 다 GetStaff 선행). 생성 → 인덱스 → 목록 노출 → 후속 수정까지
// 한 흐름으로 고정한다 — 대표가 콘솔 없이 트레이너를 온보딩할 수 있다는 증명.
func TestCreateStaffOnboardsTrainerEndToEnd(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	st, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
		Name: "정혜린", Email: "hyerin@rise.kr", Role: domain.RoleTrainer,
		Payout: &domain.Payout{Type: domain.PayoutRate, Value: 0.5},
	})
	if err != nil {
		t.Fatalf("CreateStaff: %v", err)
	}
	if st.UID == "" || st.Role != domain.RoleTrainer || st.Name != "정혜린" {
		t.Fatalf("staff = %+v", st)
	}
	if st.Offdays == nil || st.Profile.Specialties == nil || st.Profile.Certifications == nil || st.Profile.Awards == nil {
		t.Errorf("배열 null 금지 규약 위반: %+v", st) // 어드민 offdays.length·specialties.map 크래시 방지
	}
	if st.Payout != (domain.Payout{Type: domain.PayoutRate, Value: 0.5}) {
		t.Errorf("payout = %+v", st.Payout)
	}

	// UserIndex가 없으면 로그인해도 member로 폴백한다(auth.enrich) — 어드민이 열리지 않는다.
	idx, err := s.store.GetUserIndex(ctx, st.UID)
	if err != nil {
		t.Fatalf("UserIndex 미저장: %v", err)
	}
	if idx.Role != domain.RoleTrainer || idx.CenterID != testCenter || idx.MemberID != "" {
		t.Errorf("UserIndex = %+v", idx)
	}
	// Staff 레코드도 저장돼 목록에 뜬다.
	list, err := s.ListStaff(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, item := range list {
		if item.UID == st.UID {
			found = true
		}
	}
	if !found {
		t.Fatalf("GET /v1/staff 목록에 신규 스태프 없음: %+v", list)
	}

	// 원래 막혀 있던 후속 수정 두 개가 곧바로 먹는다(구멍이 메워졌다는 증명).
	offday := time.Now().In(domain.KST).AddDate(0, 0, 3).Format("2006-01-02")
	got, err := s.SetOffdays(ctx, ownerP(), st.UID, []string{offday})
	if err != nil || len(got.Offdays) != 1 || got.Offdays[0] != offday {
		t.Fatalf("SetOffdays = %+v, err = %v", got, err)
	}
	self := Principal{UID: st.UID, Role: domain.RoleTrainer, CenterID: testCenter} // 본인 자격
	got, err = s.UpdateStaffProfile(ctx, self, st.UID, domain.StaffProfile{Title: "퍼포먼스 트레이너", CareerYears: 7})
	if err != nil || got.Profile.Title != "퍼포먼스 트레이너" {
		t.Fatalf("UpdateStaffProfile = %+v, err = %v", got, err)
	}
	if len(got.Offdays) != 1 {
		t.Errorf("프로필 수정이 휴무를 날림: %+v", got.Offdays) // 두 수정이 서로를 덮지 않는다
	}
}

// owner 전용 — 트레이너·회원 모두 403(급여 필드가 붙는 레코드, P13).
func TestCreateStaffIsOwnerOnly(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	req := domain.StaffCreate{Name: "김태오", Email: "taeo@rise.kr", Role: domain.RoleTrainer}

	if _, err := s.CreateStaff(ctx, trainerP(), req); !errors.Is(err, ErrForbidden) {
		t.Errorf("trainer 생성 err = %v, want ErrForbidden", err)
	}
	if _, err := s.CreateStaff(ctx, memberP("m1"), req); !errors.Is(err, ErrForbidden) {
		t.Errorf("member 생성 err = %v, want ErrForbidden", err)
	}
	// 권한 거부 시 계정·레코드 어느 것도 만들어지지 않는다.
	list, err := s.ListStaff(ctx, ownerP())
	if err != nil || len(list) != 0 {
		t.Errorf("403인데 스태프가 생성됨: %v %+v", err, list)
	}
}

// 입력 검증 400: 이름 공백 / 이메일 형식 / role 값 / payout 범위.
func TestCreateStaffValidatesInput(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	base := domain.StaffCreate{Name: "김태오", Email: "taeo@rise.kr", Role: domain.RoleTrainer}

	cases := map[string]func(c *domain.StaffCreate){
		"이름 공백":        func(c *domain.StaffCreate) { c.Name = "   " },
		"이메일 형식":       func(c *domain.StaffCreate) { c.Email = "taeo(at)rise" },
		"이메일 표시이름 혼합":  func(c *domain.StaffCreate) { c.Email = "김태오 <taeo@rise.kr>" },
		"이메일 도메인 점 없음": func(c *domain.StaffCreate) { c.Email = "taeo@rise" },
		"role 값 오류":    func(c *domain.StaffCreate) { c.Role = domain.RoleMember },
		"role 공백":      func(c *domain.StaffCreate) { c.Role = "" },
		"payout type":  func(c *domain.StaffCreate) { c.Payout = &domain.Payout{Type: "bonus", Value: 1} },
		"payout 비율 범위": func(c *domain.StaffCreate) { c.Payout = &domain.Payout{Type: domain.PayoutRate, Value: 1.5} },
		"payout 음수":    func(c *domain.StaffCreate) { c.Payout = &domain.Payout{Type: domain.PayoutPerSession, Value: -1} },
		"color 형식":     func(c *domain.StaffCreate) { c.Color = "red" },
	}
	for name, mutate := range cases {
		req := base
		mutate(&req)
		if _, err := s.CreateStaff(ctx, ownerP(), req); !errors.Is(err, domain.ErrInvalidStaff) {
			t.Errorf("%s: err = %v, want ErrInvalidStaff(400)", name, err)
		}
	}
	// 정상 입력은 통과해야 한다(검증이 과하게 잠그지 않았는지 대조).
	if _, err := s.CreateStaff(ctx, ownerP(), base); err != nil {
		t.Fatalf("정상 입력이 거부됨: %v", err)
	}
}

// 같은 이메일 재초대 → 409. 계정 uid는 재사용되지만 기존 스태프 레코드를 덮어쓰지 않는다.
func TestCreateStaffRejectsDuplicateEmail(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	first, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
		Name: "정혜린", Email: "hyerin@rise.kr", Role: domain.RoleTrainer,
	})
	if err != nil {
		t.Fatal(err)
	}
	// 대소문자만 다른 이메일도 같은 계정이다(Normalize) — 중복 스태프가 생기면 안 된다.
	if _, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
		Name: "정혜린(중복)", Email: "Hyerin@Rise.KR", Role: domain.RoleTrainer,
	}); !errors.Is(err, ErrConflict) {
		t.Fatalf("중복 초대 err = %v, want ErrConflict(409)", err)
	}
	list, err := s.ListStaff(ctx, ownerP())
	if err != nil || len(list) != 1 || list[0].Name != "정혜린" {
		t.Errorf("중복 초대가 레코드를 덮음: %v %+v", err, list)
	}
	if _, err := s.store.GetStaff(ctx, testCenter, first.UID); err != nil {
		t.Errorf("원본 스태프 소실: %v", err)
	}
}

// 이미 회원(member)으로 연결된 계정은 스태프로 승격하지 않는다 — UserIndex가 uid당 1건이라
// role이 덮이는 순간 그 사람의 회원 앱이 통째로 잠긴다.
func TestCreateStaffRejectsUIDAlreadyLinkedToMember(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	email := "minji@rise.kr"
	uid, err := devUserProvisioner{}.EnsureUser(ctx, email) // dev 합성 uid는 이메일에 결정적
	if err != nil {
		t.Fatal(err)
	}
	mem, _ := seedMemberWithPass(t, s, 10)
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{
		UID: uid, Role: domain.RoleMember, CenterID: testCenter, MemberID: mem.ID,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
		Name: "김민지", Email: email, Role: domain.RoleTrainer,
	}); !errors.Is(err, ErrConflict) {
		t.Fatalf("회원 계정의 스태프 승격 err = %v, want ErrConflict(409)", err)
	}
	idx, err := s.store.GetUserIndex(ctx, uid)
	if err != nil || idx.Role != domain.RoleMember || idx.MemberID != mem.ID {
		t.Errorf("409인데 회원 인덱스가 훼손됨: %v %+v", err, idx)
	}
}

// color 미지정 시 팔레트 자동 배정 — 기존 스태프 색과 겹치지 않는다(스케줄 그리드 식별색).
func TestCreateStaffAssignsUnusedPaletteColor(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	// 팔레트 첫 색을 이미 쓰고 있는 기존 스태프(시딩된 owner 상당).
	if err := s.store.SaveStaff(ctx, testCenter, &domain.Staff{
		UID: "owner1", Role: domain.RoleOwner, Name: "박관장", Color: domain.StaffPalette[0],
	}); err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{domain.StaffPalette[0]: true}
	for i, email := range []string{"a@rise.kr", "b@rise.kr", "c@rise.kr"} {
		st, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
			Name: fmt.Sprintf("트레이너%d", i), Email: email, Role: domain.RoleTrainer,
		})
		if err != nil {
			t.Fatal(err)
		}
		if st.Color == "" || seen[st.Color] {
			t.Fatalf("%s 색 = %q (기존 색과 중복 — 그리드에서 구분 불가)", email, st.Color)
		}
		seen[st.Color] = true
	}
	// 명시 지정은 그대로 존중한다.
	st, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
		Name: "지정색", Email: "d@rise.kr", Role: domain.RoleTrainer, Color: "#ABCDEF",
	})
	if err != nil {
		t.Fatal(err)
	}
	if st.Color != "#abcdef" { // Normalize가 소문자로 접는다
		t.Errorf("지정 색 = %q, want #abcdef", st.Color)
	}
}

// payout 미지정 → {per_session, 0}(정산 미정). owner도 같은 기본값.
func TestCreateStaffDefaultsPayout(t *testing.T) {
	s := newTestService()
	st, err := s.CreateStaff(context.Background(), ownerP(), domain.StaffCreate{
		Name: "박관장", Email: "owner@rise.kr", Role: domain.RoleOwner,
	})
	if err != nil {
		t.Fatal(err)
	}
	if st.Payout != (domain.Payout{Type: domain.PayoutPerSession, Value: 0}) {
		t.Errorf("payout = %+v, want {per_session, 0}", st.Payout)
	}
	if st.Role != domain.RoleOwner {
		t.Errorf("role = %s, want owner(공동 대표 온보딩)", st.Role)
	}
}

// P07 회귀: 같은 API가 /v1 과 /api/v1 양쪽에 붙어 있어야 한다. 어드민은 Firebase Hosting에서
// /api/**가 Cloud Run으로 리라이트되는데 Hosting이 접두사를 벗겨주지 않아 /api/v1/...로 도착한다.
// 이 미러가 빠지면 배포된 어드민의 모든 호출이 404가 된다(로컬 개발은 프록시가 가려서 멀쩡함).
func TestAPIPrefixMirror(t *testing.T) {
	r := newTestRouter(t)

	for _, base := range []string{"/v1", "/api/v1"} {
		req := httptest.NewRequest(http.MethodGet, base+"/me", nil)
		req.Header.Set("X-Dev-Uid", "owner1")
		req.Header.Set("X-Dev-Role", domain.RoleOwner)
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s/me = %d %s, want 200", base, rec.Code, rec.Body.String())
		}
	}

	// 인증 미들웨어도 양쪽에 걸려 있어야 한다 — 미러가 인증을 우회하는 뒷문이 되면 안 된다.
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/me", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("무인증 GET /api/v1/me = %d, want 401(인증 우회 뒷문)", rec.Code)
	}

	// 쓰기 경로도 미러로 동작한다(어드민의 실제 호출 모양).
	body := `{"name":"김태오","email":"taeo@rise.kr","role":"trainer"}`
	if rec := postJSON(t, r, "/api/v1/staff", "owner1", domain.RoleOwner, body); rec.Code != http.StatusCreated {
		t.Fatalf("POST /api/v1/staff = %d %s, want 201", rec.Code, rec.Body.String())
	}
}

// HTTP 계약: 201/403/400/409 상태코드와 응답 필드(비밀번호 미노출)를 라우터까지 태워 고정한다.
func TestCreateStaffHTTPContract(t *testing.T) {
	r := newTestRouter(t)
	body := `{"name":"정혜린","email":"hyerin@rise.kr","role":"trainer","payout":{"type":"rate","value":0.5}}`

	rec := postJSON(t, r, "/v1/staff", "owner1", domain.RoleOwner, body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("owner 생성 = %d %s, want 201", rec.Code, rec.Body.String())
	}
	var got map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"uid", "role", "name", "color", "payout", "offdays", "profile"} {
		if _, ok := got[key]; !ok {
			t.Errorf("응답에 %s 없음: %v", key, got)
		}
	}
	for _, forbidden := range []string{"password", "temp_password", "email"} {
		if _, ok := got[forbidden]; ok {
			t.Errorf("응답에 %s가 실렸다(초대는 재설정 메일로): %v", forbidden, got)
		}
	}
	if offdays, ok := got["offdays"].([]any); !ok || len(offdays) != 0 {
		t.Errorf("offdays = %v, want [](null 금지)", got["offdays"])
	}

	dup := postJSON(t, r, "/v1/staff", "owner1", domain.RoleOwner, body)
	if dup.Code != http.StatusConflict {
		t.Errorf("중복 생성 = %d %s, want 409", dup.Code, dup.Body.String())
	}
	if msg := dup.Body.String(); strings.Contains(msg, "api:") || strings.Contains(msg, "domain:") {
		t.Errorf("에러 메시지에 내부 마커 노출: %s", msg) // 계약: 사용자향 한국어 문구만
	}
	if rec := postJSON(t, r, "/v1/staff", "t1", domain.RoleTrainer, body); rec.Code != http.StatusForbidden {
		t.Errorf("trainer 생성 = %d, want 403", rec.Code)
	}
	if rec := postJSON(t, r, "/v1/staff", "member1", domain.RoleMember, body); rec.Code != http.StatusForbidden {
		t.Errorf("member 생성 = %d, want 403", rec.Code)
	}
	bad := `{"name":"  ","email":"nope","role":"boss"}`
	if rec := postJSON(t, r, "/v1/staff", "owner1", domain.RoleOwner, bad); rec.Code != http.StatusBadRequest {
		t.Errorf("불량 입력 = %d %s, want 400", rec.Code, rec.Body.String())
	}
}

// P08 회귀: 민감정보(P8 체형사진·인바디) **쓰기**에도 읽기와 같은 스코프가 걸려야 한다.
// 종전엔 동의 검사만 하고 스코프를 보지 않아, 인증만 된 사용자면 누구의 체형사진이든 기록할 수
// 있었다(다른 회원인 척, 담당 아닌 트레이너도). 목록은 막혀 있어 읽기/쓰기가 비대칭이었다.
func TestSensitiveWritesRespectScope(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	victim, _ := seedMemberWithPass(t, s, 20) // 김민지, 담당 t1, sensitive 동의 有
	seedTrainerRecord(t, s, "t2", "김태오")      // v2.1: 담당으로 붙이는 코치는 실존해야 한다

	other, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "타인", Phone: "010-3333-4444", TrainerID: "t2", Status: domain.MemberStatusActive,
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatal(err)
	}

	photo := BodyPhotoCreateRequest{
		MemberID: victim.ID, Pose: "stand", Direction: "front",
		Date: "2026-08-22", StoragePath: "pending/x.jpg",
	}
	// v2.9부터 6지표가 모두 범위 검증을 받으므로 픽스처도 완전한 레코드여야 한다
	// (스코프 위반은 값 검증보다 앞에서 막히지만, 마지막 "정상 경로" 확인이 값까지 통과해야 한다).
	inbody := InbodyCreateRequest{
		MemberID: victim.ID, Date: "2026-08-22",
		Weight: 60, SMM: 24.5, BFM: 16.2, PBF: 27.0, VFL: 5, BMR: 1310,
	}

	// 다른 회원인 척 — 남의 체형사진·인바디를 기록할 수 없다.
	impostor := memberP(other.ID)
	if _, err := s.CreateBodyPhoto(ctx, impostor, photo); !errors.Is(err, ErrForbidden) {
		t.Fatalf("타인 체형사진 기록 = %v, want ErrForbidden", err)
	}
	if _, err := s.CreateInbody(ctx, impostor, inbody); !errors.Is(err, ErrForbidden) {
		t.Fatalf("타인 인바디 기록 = %v, want ErrForbidden", err)
	}

	// 담당이 아닌 트레이너도 막힌다(t2는 김민지 담당이 아니다).
	notMine := Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}
	if _, err := s.CreateBodyPhoto(ctx, notMine, photo); !errors.Is(err, ErrForbidden) {
		t.Fatalf("비담당 트레이너 체형사진 기록 = %v, want ErrForbidden", err)
	}
	if _, err := s.CreateInbody(ctx, notMine, inbody); !errors.Is(err, ErrForbidden) {
		t.Fatalf("비담당 트레이너 인바디 기록 = %v, want ErrForbidden", err)
	}

	// 정상 경로는 그대로 열려 있어야 한다(과잉 차단 방지) — 본인·담당 트레이너·대표.
	if _, err := s.CreateBodyPhoto(ctx, memberP(victim.ID), photo); err != nil {
		t.Fatalf("본인 체형사진 기록 실패: %v", err)
	}
	if _, err := s.CreateBodyPhoto(ctx, trainerP(), photo); err != nil {
		t.Fatalf("담당 트레이너 체형사진 기록 실패: %v", err)
	}
	if _, err := s.CreateInbody(ctx, ownerP(), inbody); err != nil {
		t.Fatalf("대표 인바디 기록 실패: %v", err)
	}
}

// P08 회귀: 가입 매칭 전(미연결) 회원의 홈워크 체크는 주인 없는 기록을 남기면 안 된다.
// p.MemberID가 ""인 채 저장되면 member_id 빈 문자열 레코드가 쌓인다 — 목록 계열은
// memberScopeID가 403으로 막고 있어 쓰기만 뚫려 있었다.
func TestHwCheckRejectsUnlinkedMember(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	unlinked := Principal{UID: "u_unlinked", Role: domain.RoleMember, CenterID: testCenter}

	if _, err := s.CreateHwCheck(ctx, unlinked,
		HwCheckRequest{HwID: "hw_1", Date: "2026-08-22", Done: []bool{true}}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("미연결 회원 체크 = %v, want ErrForbidden", err)
	}
}

// P09 회귀: 유효기간 없는 회원권은 발급 자체를 막는다.
// 종전엔 빈 값이 그대로 저장돼 **영원히 예약할 수 없는 회원권**이 조용히 만들어졌다 —
// 예약의 기간 검사가 문자열 비교라 ValidUntil이 ""면 어떤 날짜든 "유효기간 밖"이 된다.
// 프로덕션에 실제로 그런 레코드를 만들어 예약을 시도하다 발견했다.
func TestCreatePassRequiresValidPeriod(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedTrainerRecord(t, s, "t1", "정혜린")
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "기간검증", Phone: "010-4444-1234", TrainerID: "t1", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	base := PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: "PT 10회",
		PaidAmount: 500000, TotalSessions: 10,
	}

	bad := []struct {
		name        string
		from, until string
	}{
		{"둘 다 빈 값", "", ""},
		{"시작일만 빈 값", "", "2026-12-31"},
		{"종료일만 빈 값", "2026-08-23", ""},
		{"형식 오류", "2026/08/23", "2026-12-31"},
		{"종료가 시작보다 앞섬", "2026-12-31", "2026-08-23"},
	}
	for _, c := range bad {
		req := base
		req.ValidFrom, req.ValidUntil = c.from, c.until
		if _, err := s.CreatePass(ctx, ownerP(), req); !errors.Is(err, domain.ErrInvalidPassPeriod) {
			t.Errorf("%s: err = %v, want ErrInvalidPassPeriod", c.name, err)
		}
	}

	// 정상 기간은 발급되고, **그 회원권으로 실제 예약까지 된다**(과잉 차단 방지 + 원래 증상 재현).
	kst := time.Now().In(domain.KST)
	req := base
	req.ValidFrom = kst.Format("2006-01-02")
	req.ValidUntil = kst.AddDate(0, 3, 0).Format("2006-01-02")
	pass, err := s.CreatePass(ctx, ownerP(), req)
	if err != nil {
		t.Fatalf("정상 기간 발급 실패: %v", err)
	}
	if _, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 10), MemberID: mem.ID, PassID: pass.ID,
	}); err != nil {
		t.Fatalf("정상 기간 회원권으로 예약 실패: %v", err)
	}
}

// P10 회귀: /v1/me가 표시 이름을 함께 준다. 없으면 앱은 세션 복원 후 헤더가 센터명으로 떨어지고
// 어드민은 이메일 원문을 감추려 staff 목록을 조인해야 한다 — 두 우회가 같은 결핍에서 나왔다.
func TestMeCarriesDisplayName(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedTrainerRecord(t, s, "t1", "정혜린")
	mem, _ := seedMemberWithPass(t, s, 20) // 김민지

	// 스태프: Staff.name
	if got := s.Me(ctx, trainerP()); got.Name != "정혜린" {
		t.Errorf("트레이너 이름 = %q, want 정혜린", got.Name)
	}

	// 회원: Member.name
	if got := s.Me(ctx, memberP(mem.ID)); got.Name != "김민지" {
		t.Errorf("회원 이름 = %q, want 김민지", got.Name)
	}

	// 미연결 회원(가입 매칭 전) — 이름은 없지만 **호출 자체는 성공해야 한다**.
	// 여기서 실패하면 온보딩을 시작할 수도 없다.
	unlinked := Principal{UID: "u_new", Role: domain.RoleMember, CenterID: testCenter}
	got := s.Me(ctx, unlinked)
	if got.Name != "" || got.UID != "u_new" || got.Role != domain.RoleMember {
		t.Errorf("미연결 응답이 어긋남: %+v", got)
	}

	// 레코드가 없는 스태프 uid — 조회 실패가 에러로 번지지 않고 빈 이름으로 떨어진다.
	ghost := Principal{UID: "t_ghost", Role: domain.RoleTrainer, CenterID: testCenter}
	if got := s.Me(ctx, ghost); got.Name != "" || got.Role != domain.RoleTrainer {
		t.Errorf("유령 스태프 응답이 어긋남: %+v", got)
	}
}

// ── P14 C1: 위약금율 — 계약서에 인쇄되는 값과 실제 공제액이 같은 숫자여야 한다 ──────────
//
// 종전 실측(포트 8096): 정책 30% 저장 성공 → 자동 생성 계약 penalty_rate 0.3(회원이 서명) →
// refund-quote penalty 100,000(=10%). 세 겹이 서로 다른 말을 했다.
// 이 테스트는 **금액으로** 단언한다: 계약 스냅샷 요율 × 실결제가 == 서버가 실제로 공제한 위약금.
func TestContractPenaltyRateMatchesRefundDeduction(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	// 패스의 계약 스냅샷 요율과 실제 견적 위약금을 함께 뽑는 헬퍼.
	// used=0(미사용 해지)이라 위약금이 공제 전부다 — 이용분에 가려지지 않는다.
	quoteAndContract := func(memberID, passID string) (rate float64, penalty, refund int) {
		t.Helper()
		contracts, err := s.ListContracts(ctx, ownerP(), memberID, "")
		if err != nil {
			t.Fatalf("ListContracts: %v", err)
		}
		found := false
		for _, c := range contracts {
			if c.PassID == passID && c.Status != domain.ContractStatusVoided {
				if c.PenaltyRate == nil {
					t.Fatalf("계약 %s에 위약금율 스냅샷이 없다 — 회원이 서명할 조항이 비어 있다", c.ID)
				}
				rate, found = *c.PenaltyRate, true
				break
			}
		}
		if !found {
			t.Fatalf("패스 %s의 유효 계약을 찾지 못했다", passID)
		}
		q, err := s.RefundQuote(ctx, ownerP(), passID, 0)
		if err != nil {
			t.Fatalf("RefundQuote: %v", err)
		}
		return rate, q.Penalty, q.Refund
	}

	// ① 기본 정책(10%) — 계약서 값과 공제액이 같다(골든: 1,000,000 × 10% = 100,000).
	mem, pass := seedMemberWithPass(t, s, 20)
	rate, penalty, refund := quoteAndContract(mem.ID, pass.ID)
	if want := int(float64(pass.PaidAmount) * rate); penalty != want {
		t.Errorf("계약서 %.4f → 공제 %d원인데 실제 공제는 %d원", rate, want, penalty)
	}
	if penalty != 100_000 || refund != 900_000 {
		t.Errorf("기본 정책 견적 = penalty %d / refund %d, want 100,000 / 900,000", penalty, refund)
	}

	// ② 상한 초과 저장은 거부된다 — "저장됐어요"가 집행되지 않는 조항을 발행하던 경로를 막는다.
	over := domain.DefaultPolicy()
	over.PenaltyRate = 0.30
	overJSON, err := json.Marshal(over)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), overJSON); !errors.Is(err, domain.ErrInvalidPolicy) {
		t.Fatalf("위약금율 30%% 저장이 통과했다: %v", err)
	}

	// ③ 상한 이하(5%)는 그대로 계약서에 실리고 그대로 공제된다 — 대표가 낮추는 것은 언제나 가능.
	low := domain.DefaultPolicy()
	low.PenaltyRate = 0.05
	lowJSON, err := json.Marshal(low)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), lowJSON); err != nil {
		t.Fatalf("위약금율 5%% 저장 실패: %v", err)
	}
	pass5, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: "PT 20회(5%)",
		PaidAmount: 1_000_000, TotalSessions: 20,
		ValidFrom:  time.Now().In(domain.KST).AddDate(0, 0, -1).Format("2006-01-02"),
		ValidUntil: time.Now().In(domain.KST).AddDate(0, 0, 90).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatalf("CreatePass: %v", err)
	}
	rate5, penalty5, refund5 := quoteAndContract(mem.ID, pass5.ID)
	if rate5 != 0.05 {
		t.Errorf("계약 스냅샷 요율 = %v, want 0.05(정책 실값)", rate5)
	}
	if penalty5 != 50_000 || refund5 != 950_000 {
		t.Errorf("5%% 견적 = penalty %d / refund %d, want 50,000 / 950,000", penalty5, refund5)
	}
	if want := int(float64(pass5.PaidAmount) * rate5); penalty5 != want {
		t.Errorf("계약서 %.4f → 공제 %d원인데 실제 공제는 %d원", rate5, want, penalty5)
	}

	// ④ 이번 변경 전에 저장된 초과 문서(30%)는 읽는 순간 상한으로 접힌다 —
	//    새 계약도 10%로 서명되고 회원앱도 10%를 본다. 세 자리가 같은 숫자를 말한다.
	legacy := domain.DefaultPolicy()
	legacy.PenaltyRate = 0.30
	if err := s.store.SavePolicy(ctx, testCenter, &legacy); err != nil { // Validate 우회 = 구문서 재현
		t.Fatal(err)
	}
	passLegacy, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t1", Product: "PT 20회(구문서)",
		PaidAmount: 1_000_000, TotalSessions: 20,
		ValidFrom:  time.Now().In(domain.KST).AddDate(0, 0, -1).Format("2006-01-02"),
		ValidUntil: time.Now().In(domain.KST).AddDate(0, 0, 90).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatalf("CreatePass: %v", err)
	}
	rateL, penaltyL, refundL := quoteAndContract(mem.ID, passLegacy.ID)
	if rateL != domain.MaxPenaltyRate {
		t.Errorf("구문서 계약 스냅샷 = %v, want %v(상한으로 접힘)", rateL, domain.MaxPenaltyRate)
	}
	if want := int(float64(passLegacy.PaidAmount) * rateL); penaltyL != want || penaltyL != 100_000 {
		t.Errorf("구문서 견적 = penalty %d(계약서 기준 %d), want 100,000", penaltyL, want)
	}
	if refundL != 900_000 {
		t.Errorf("구문서 환불액 = %d, want 900,000", refundL)
	}
	// 회원 앱이 보는 값(GET /v1/center)도 같은 숫자여야 한다 — 종전엔 0.3이 그대로 내려갔다.
	res, err := s.GetCenter(ctx, memberP(mem.ID))
	if err != nil {
		t.Fatal(err)
	}
	if res.Policy.PenaltyRate != domain.MaxPenaltyRate {
		t.Errorf("회원 앱이 본 penalty_rate = %v, want %v", res.Policy.PenaltyRate, domain.MaxPenaltyRate)
	}
	// 구문서 상태에서도 다른 필드 수정이 잠기지 않는다(머지 PUT이 초과값을 이어받아 400 나던 자리).
	patched, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"slot_capacity":4}`))
	if err != nil {
		t.Fatalf("구문서 위에서 부분 PUT이 막혔다: %v", err)
	}
	if patched.Policy.SlotCapacity != 4 || patched.Policy.PenaltyRate != domain.MaxPenaltyRate {
		t.Errorf("부분 PUT 결과 = %+v", patched.Policy)
	}
}

// uncappedPolicyStore — GetPolicy가 **상한을 넘는 위약금율을 그대로** 돌려주는 스토어.
// Memory·Firestore 둘 다 읽는 자리에서 Normalize로 접기 때문에, 그 위층(계약 스냅샷)의
// 방어선은 정상 경로에서 관측되지 않는다 — 스토어가 거짓말하는 상황을 만들어야 보인다.
// 손으로 고친 Firestore 문서·정규화를 잊은 새 스토어 구현이 실제로 그 상황이다.
type uncappedPolicyStore struct {
	store.Store
	rate float64
}

func (u uncappedPolicyStore) GetPolicy(ctx context.Context, centerID string) (*domain.Policy, error) {
	p, err := u.Store.GetPolicy(ctx, centerID)
	if err != nil {
		return nil, err
	}
	p.PenaltyRate = u.rate // 정규화를 통과한 뒤 오염 — 스토어 계약 위반을 재현한다
	return p, nil
}

// P14 C1 최종 방어선 — 정책 출처가 무엇을 주든 **회원이 서명하는 숫자는 공제 가능한 숫자**다.
func TestContractSnapshotNeverExceedsCapEvenIfPolicySourceLies(t *testing.T) {
	s := NewService(uncappedPolicyStore{Store: store.NewMemory(), rate: 0.30}, config.Config{
		DefaultCenterID: testCenter,
	}, nil)
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20)

	contracts, err := s.ListContracts(ctx, ownerP(), mem.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(contracts) == 0 || contracts[0].PenaltyRate == nil {
		t.Fatalf("자동 생성 계약의 위약금율 스냅샷이 없다: %+v", contracts)
	}
	rate := *contracts[0].PenaltyRate
	if rate != domain.MaxPenaltyRate {
		t.Errorf("계약 스냅샷 = %v, want %v — 집행할 수 없는 조항을 발행했다", rate, domain.MaxPenaltyRate)
	}
	q, err := s.RefundQuote(ctx, ownerP(), pass.ID, 0)
	if err != nil {
		t.Fatal(err)
	}
	if want := int(float64(pass.PaidAmount) * rate); q.Penalty != want || q.Penalty != 100_000 {
		t.Errorf("계약서 %.4f → 공제 %d원인데 실제 공제는 %d원", rate, want, q.Penalty)
	}
}
