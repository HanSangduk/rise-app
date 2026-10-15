package api

// 인바디 쓰기 경로의 안전장치(v2.9) — 회원 셀프 수기 입력을 열기 전에 서버가 먼저 갖춰야 하는 것.
//
// 배경: 종전 CreateInbody는 ①값을 전혀 검증하지 않고 ②미래 날짜를 받고 ③같은 날 중복을 막지
// 않고 ④정정(삭제) 수단이 아예 없었다. 이 상태로 회원 폼을 열면 오타 한 번이 차트에 영구
// 고정되고, 복구 경로는 Firestore 콘솔 수기 편집뿐이다. 그래서 폼보다 안전장치가 먼저다.

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

	"github.com/ramsang/rise-backend/internal/config"
	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// seedInbodyMember — 동의(sensitive)를 갖춘 회원 + 담당 코치. 인바디는 P8 민감정보라 동의가
// 없으면 값 검증에 닿기도 전에 막힌다.
func seedInbodyMember(t *testing.T, s *Service) *domain.Member {
	t.Helper()
	ctx := context.Background()
	seedTrainerRecord(t, s, "t1", "이담당")
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "인바디회원", Phone: "010-2222-3333", TrainerID: "t1",
		Status:  domain.MemberStatusActive,
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	return mem
}

// validInbodyReq — 통과해야 하는 기준 요청(각 테스트가 여기서 한 곳만 흔든다).
func validInbodyReq(memberID, date string) InbodyCreateRequest {
	return InbodyCreateRequest{
		MemberID: memberID, Date: date,
		Weight: 70.5, SMM: 32.1, BFM: 12.8, PBF: 18.4, VFL: 6, BMR: 1560,
	}
}

// 값 범위 위반은 400이고 **아무것도 저장되지 않는다**. 앱 폼이 같은 범위를 미리 검사하지만
// 그건 왕복을 아끼는 것이고, 진실은 여기다(어드민·직접 호출도 같은 문을 지난다).
func TestCreateInbodyRejectsOutOfRangeValues(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedInbodyMember(t, s)
	date := today()

	cases := []struct {
		name string
		mut  func(*InbodyCreateRequest)
	}{
		{"weight=-5", func(r *InbodyCreateRequest) { r.Weight = -5 }},
		{"weight=0", func(r *InbodyCreateRequest) { r.Weight = 0 }},
		{"pbf=999", func(r *InbodyCreateRequest) { r.PBF = 999 }},
		{"bmr=0", func(r *InbodyCreateRequest) { r.BMR = 0 }},
		{"smm>weight", func(r *InbodyCreateRequest) { r.SMM = 80 }},
		{"vfl=0", func(r *InbodyCreateRequest) { r.VFL = 0 }},
		{"bfm=0", func(r *InbodyCreateRequest) { r.BFM = 0 }},
	}
	for _, c := range cases {
		req := validInbodyReq(mem.ID, date)
		c.mut(&req)
		if _, err := s.CreateInbody(ctx, trainerP(), req); !errors.Is(err, domain.ErrInvalidInbody) {
			t.Errorf("%s → err = %v, want domain.ErrInvalidInbody(400)", c.name, err)
		}
	}

	list, err := s.ListInbody(ctx, trainerP(), mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 0 {
		t.Fatalf("검증 실패한 인바디가 저장됐다: %d건", len(list))
	}

	// 과잉 차단 방지 — 정상 값은 그대로 통과한다.
	if _, err := s.CreateInbody(ctx, trainerP(), validInbodyReq(mem.ID, date)); err != nil {
		t.Fatalf("정상 값이 거부됨: %v", err)
	}
}

// 측정일은 미래일 수 없다. 미래 인바디는 존재할 수 없는 사실인데, 저장되는 순간 앱 차트의
// 마지막 점이 되어 "직전 대비 증감"의 기준이 된다(paid_at 미래 차단과 같은 이유).
func TestCreateInbodyRejectsFutureDate(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedInbodyMember(t, s)

	future := time.Now().In(domain.KST).AddDate(0, 0, 1).Format("2006-01-02")
	for _, date := range []string{"2099-12-31", future} {
		if _, err := s.CreateInbody(ctx, trainerP(), validInbodyReq(mem.ID, date)); !errors.Is(err, errBadRequest) {
			t.Errorf("date=%s → err = %v, want 400", date, err)
		}
	}

	// 경계: KST 오늘은 통과해야 한다(측정 당일 저녁에 입력하는 게 정상 사용 흐름이다).
	if _, err := s.CreateInbody(ctx, trainerP(), validInbodyReq(mem.ID, today())); err != nil {
		t.Fatalf("오늘 날짜가 거부됨: %v", err)
	}
}

// 같은 회원·같은 날 2건은 409. 인바디는 하루 1회 측정이 전제고, 2건이 있으면 차트의 그날 점이
// 둘로 갈려 "직전 대비 증감"이 어느 쪽 기준인지 알 수 없게 된다. 정정은 삭제 후 재입력이다.
func TestCreateInbodyRejectsDuplicateDate(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedInbodyMember(t, s)
	date := today()

	if _, err := s.CreateInbody(ctx, trainerP(), validInbodyReq(mem.ID, date)); err != nil {
		t.Fatal(err)
	}
	dup := validInbodyReq(mem.ID, date)
	dup.Weight = 71.0 // 값이 달라도 같은 날이면 충돌이다
	if _, err := s.CreateInbody(ctx, trainerP(), dup); !errors.Is(err, ErrConflict) {
		t.Fatalf("같은 날 2번째 = %v, want ErrConflict(409)", err)
	}

	list, err := s.ListInbody(ctx, trainerP(), mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 {
		t.Fatalf("중복 거부 후 %d건, want 1건", len(list))
	}
	if list[0].Weight != 70.5 {
		t.Errorf("기존 기록이 덮였다: weight = %v, want 70.5", list[0].Weight)
	}

	// 다른 날짜는 막히지 않는다.
	other := time.Now().In(domain.KST).AddDate(0, 0, -1).Format("2006-01-02")
	if _, err := s.CreateInbody(ctx, trainerP(), validInbodyReq(mem.ID, other)); err != nil {
		t.Fatalf("다른 날짜가 거부됨: %v", err)
	}
}

// 409 문구는 호출자가 **실제로 할 수 있는 행동**을 지시해야 한다(P18 검증 지적).
// 기존 기록이 센터 입력분(source=staff)이면 회원은 그걸 지울 수 없다(DeleteInbody가 403) —
// 그런 회원에게 "기존 기록을 지우고 다시 저장해주세요"라고 하면 403으로 가는 길을 안내하는
// 셈이다. 회원에게는 코치에게 요청하라고, 지울 수 있는 경우에만 지우라고 말한다.
func TestCreateInbodyConflictMessageMatchesCallerAbility(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedInbodyMember(t, s)
	date := today()

	// ① 센터(트레이너)가 먼저 입력 → 회원이 같은 날 시도: "코치에게 요청" 안내여야 한다.
	if _, err := s.CreateInbody(ctx, trainerP(), validInbodyReq(mem.ID, date)); err != nil {
		t.Fatal(err)
	}
	_, err := s.CreateInbody(ctx, memberP(mem.ID), validInbodyReq(mem.ID, date))
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("회원 중복 시도 = %v, want ErrConflict", err)
	}
	if !strings.Contains(err.Error(), "담당 코치에게 요청") {
		t.Errorf("센터 기록과 충돌한 회원에게 삭제를 지시했다: %v", err)
	}
	if strings.Contains(err.Error(), "지우고 다시") {
		t.Errorf("회원이 할 수 없는 행동(센터 기록 삭제)을 지시했다: %v", err)
	}

	// ② 회원 셀프 기록과의 충돌(어제 날짜로 셀프 입력 후 재시도): 삭제 안내가 맞다.
	yesterday := time.Now().In(domain.KST).AddDate(0, 0, -1).Format("2006-01-02")
	if _, err := s.CreateInbody(ctx, memberP(mem.ID), validInbodyReq(mem.ID, yesterday)); err != nil {
		t.Fatal(err)
	}
	_, err = s.CreateInbody(ctx, memberP(mem.ID), validInbodyReq(mem.ID, yesterday))
	if !errors.Is(err, ErrConflict) || !strings.Contains(err.Error(), "지우고 다시") {
		t.Errorf("셀프 기록 충돌은 삭제 후 재입력 안내여야 한다: %v", err)
	}

	// ③ 스태프는 어느 쪽이든 지울 수 있으므로 삭제 안내 그대로.
	_, err = s.CreateInbody(ctx, trainerP(), validInbodyReq(mem.ID, date))
	if !errors.Is(err, ErrConflict) || !strings.Contains(err.Error(), "지우고 다시") {
		t.Errorf("스태프 충돌은 삭제 후 재입력 안내여야 한다: %v", err)
	}
}

// source는 요청에서 받지 않고 서버가 Principal로 판정한다. 이 값이 곧 삭제 권한의 근거라
// (회원은 자기가 넣은 것만 지울 수 있다) 클라이언트가 정할 수 있으면 안 된다.
func TestCreateInbodyStampsSourceFromPrincipal(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedInbodyMember(t, s)

	self, err := s.CreateInbody(ctx, memberP(mem.ID), validInbodyReq(mem.ID, today()))
	if err != nil {
		t.Fatal(err)
	}
	if self.Source != domain.InbodySourceMemberSelf {
		t.Errorf("회원 Principal → source = %q, want %q", self.Source, domain.InbodySourceMemberSelf)
	}

	yesterday := time.Now().In(domain.KST).AddDate(0, 0, -1).Format("2006-01-02")
	byStaff, err := s.CreateInbody(ctx, trainerP(), validInbodyReq(mem.ID, yesterday))
	if err != nil {
		t.Fatal(err)
	}
	if byStaff.Source != domain.InbodySourceStaff {
		t.Errorf("스태프 Principal → source = %q, want %q", byStaff.Source, domain.InbodySourceStaff)
	}

	byOwner, err := s.CreateInbody(ctx, ownerP(),
		validInbodyReq(mem.ID, time.Now().In(domain.KST).AddDate(0, 0, -2).Format("2006-01-02")))
	if err != nil {
		t.Fatal(err)
	}
	if byOwner.Source != domain.InbodySourceStaff {
		t.Errorf("owner Principal → source = %q, want %q", byOwner.Source, domain.InbodySourceStaff)
	}

	// 저장본에도 남아야 한다(응답에만 찍고 저장을 빠뜨리면 삭제 권한 판정이 무너진다).
	list, err := s.ListInbody(ctx, trainerP(), mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, r := range list {
		got[r.Date] = r.Source
	}
	if got[today()] != domain.InbodySourceMemberSelf || got[yesterday] != domain.InbodySourceStaff {
		t.Errorf("저장본 source = %v", got)
	}
}

// 회원은 **자기가 넣은 기록만** 지울 수 있다. 코치가 기기에서 옮겨 적은 측정값을 회원이
// 지울 수 있으면, 마음에 안 드는 수치를 없애 상담 근거 자체가 사라진다.
func TestDeleteInbodyScope(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedInbodyMember(t, s)

	staffRec, err := s.CreateInbody(ctx, trainerP(), validInbodyReq(mem.ID, today()))
	if err != nil {
		t.Fatal(err)
	}
	yesterday := time.Now().In(domain.KST).AddDate(0, 0, -1).Format("2006-01-02")
	selfRec, err := s.CreateInbody(ctx, memberP(mem.ID), validInbodyReq(mem.ID, yesterday))
	if err != nil {
		t.Fatal(err)
	}

	// ① 회원이 스태프 기록 삭제 → 403, 레코드는 남는다.
	if err := s.DeleteInbody(ctx, memberP(mem.ID), staffRec.ID); !errors.Is(err, ErrForbidden) {
		t.Fatalf("회원이 staff 기록 삭제 = %v, want ErrForbidden", err)
	}
	if _, err := s.store.GetInbody(ctx, testCenter, staffRec.ID); err != nil {
		t.Fatalf("403인데 레코드가 사라졌다: %v", err)
	}

	// ② 다른 회원은 남의 기록에 손댈 수 없다(스코프).
	other, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "남", Phone: "010-9999-8888", TrainerID: "t1", Status: domain.MemberStatusActive,
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.DeleteInbody(ctx, memberP(other.ID), selfRec.ID); !errors.Is(err, ErrForbidden) {
		t.Fatalf("타 회원 삭제 = %v, want ErrForbidden", err)
	}

	// ③ 본인 기록은 지워진다.
	if err := s.DeleteInbody(ctx, memberP(mem.ID), selfRec.ID); err != nil {
		t.Fatalf("본인 기록 삭제 실패: %v", err)
	}
	if _, err := s.store.GetInbody(ctx, testCenter, selfRec.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("삭제 후 조회 = %v, want ErrNotFound", err)
	}

	// ④ 스태프는 출처와 무관하게 지울 수 있다(정정은 데스크의 일상 업무다).
	if err := s.DeleteInbody(ctx, trainerP(), staffRec.ID); err != nil {
		t.Fatalf("스태프 삭제 실패: %v", err)
	}

	// ⑤ 없는 ID는 404.
	if err := s.DeleteInbody(ctx, trainerP(), "nope"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("없는 ID 삭제 = %v, want ErrNotFound", err)
	}
}

// 삭제 후 같은 날짜를 다시 넣을 수 있어야 한다 — 그게 "정정"의 전부다(PUT을 만들지 않은 근거).
func TestDeleteThenRecreateSameDate(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedInbodyMember(t, s)
	date := today()

	first, err := s.CreateInbody(ctx, memberP(mem.ID), validInbodyReq(mem.ID, date))
	if err != nil {
		t.Fatal(err)
	}
	if err := s.DeleteInbody(ctx, memberP(mem.ID), first.ID); err != nil {
		t.Fatal(err)
	}
	fixed := validInbodyReq(mem.ID, date)
	fixed.Weight = 71.2
	if _, err := s.CreateInbody(ctx, memberP(mem.ID), fixed); err != nil {
		t.Fatalf("삭제 후 같은 날짜 재입력이 막혔다: %v", err)
	}
}

// 같은 날짜 2건이 이미 저장돼 있는 상황(v2.9 이전 데이터)에서도 목록 순서는 **호출마다 같아야**
// 한다. Memory는 맵 순회라 정렬이 없으면 새로고침마다 뒤바뀐다 — 앱 차트의 점 순서가 곧 화면이다.
func TestListInbodyOrderIsDeterministic(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedInbodyMember(t, s)
	date := today()

	// 서비스는 중복을 막으므로 스토어에 직접 심는다(레거시 데이터 재현).
	for i := 0; i < 5; i++ {
		rec := &domain.Inbody{
			MemberID: mem.ID, Date: date, Weight: 70 + float64(i),
			SMM: 32.1, BFM: 12.8, PBF: 18.4, VFL: 6, BMR: 1560,
			Source: domain.InbodySourceStaff,
		}
		if _, err := s.store.CreateInbody(ctx, testCenter, rec); err != nil {
			t.Fatal(err)
		}
	}
	// 다른 날짜도 섞는다 — 1차 키(date desc)가 살아 있는지 함께 본다.
	older := time.Now().In(domain.KST).AddDate(0, 0, -3).Format("2006-01-02")
	if _, err := s.CreateInbody(ctx, trainerP(), validInbodyReq(mem.ID, older)); err != nil {
		t.Fatal(err)
	}

	var first []string
	for call := 0; call < 20; call++ {
		list, err := s.ListInbody(ctx, trainerP(), mem.ID)
		if err != nil {
			t.Fatal(err)
		}
		ids := make([]string, len(list))
		for i, r := range list {
			ids[i] = r.ID
		}
		if call == 0 {
			first = ids
			if len(list) != 6 {
				t.Fatalf("%d건, want 6건", len(list))
			}
			if list[len(list)-1].Date != older {
				t.Errorf("최신 먼저가 깨졌다: 마지막 = %s, want %s", list[len(list)-1].Date, older)
			}
			continue
		}
		for i := range ids {
			if ids[i] != first[i] {
				t.Fatalf("호출 %d에서 순서가 달라졌다: %v vs %v", call, first, ids)
			}
		}
	}
	// 동률 타이브레이커는 ID 오름차순(두 스토어 공통 규칙). 같은 날짜 구간만 검사한다.
	list, err := s.ListInbody(ctx, trainerP(), mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	for i := 1; i < len(list); i++ {
		if list[i-1].Date == list[i].Date && list[i-1].ID > list[i].ID {
			t.Fatalf("동률(%s) 타이브레이커가 ID 오름차순이 아니다: %q → %q",
				list[i].Date, list[i-1].ID, list[i].ID)
		}
	}
}

// ---- 라우터 경유(상태코드·응답 본문 계약) ----
//
// 서비스 직접 호출만으로는 v2.9의 절반이 검증되지 않는다: 앱이 실제로 보는 것은 상태코드
// (400/403/404/409)와 응답 필드이고, 그 매핑은 writeErr·라우터 등록에 있다. 특히 DELETE는
// 라우트 한 줄이 빠져도 서비스 테스트는 전부 통과하면서 실기기에서 404가 된다.

// newInbodyRouter — 라우터와 **같은 스토어를 공유하는** 서비스를 함께 돌려준다(newTestRouter는
// 스토어를 감추므로 회원 UserIndex를 심을 수 없다 — role=member Principal에 member_id를
// 붙이려면 인덱스가 있어야 한다).
func newInbodyRouter(t *testing.T) (http.Handler, *Service) {
	t.Helper()
	st := store.NewMemory()
	cfg := config.Config{DefaultCenterID: testCenter}
	auth, err := NewAuthenticator(context.Background(), cfg, st)
	if err != nil {
		t.Fatalf("NewAuthenticator: %v", err)
	}
	svc := NewService(st, cfg, auth.Provisioner(testInitialPassword))
	return NewRouter(NewHandlers(svc), auth, nil), svc
}

func doReq(t *testing.T, r http.Handler, method, path, uid, role, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Dev-Uid", uid)
	req.Header.Set("X-Dev-Role", role)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

func TestInbodyHTTPContract(t *testing.T) {
	r, s := newInbodyRouter(t)
	ctx := context.Background()

	seedTrainerRecord(t, s, "t1", "이담당")
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{
		UID: "owner1", Role: domain.RoleOwner, CenterID: testCenter,
	}); err != nil {
		t.Fatal(err)
	}
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "인바디회원", Phone: "010-2222-3333", TrainerID: "t1",
		Status:  domain.MemberStatusActive,
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	const memberUID = "u-inbody"
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{
		UID: memberUID, Role: domain.RoleMember, CenterID: testCenter, MemberID: mem.ID,
	}); err != nil {
		t.Fatal(err)
	}

	body := func(date string, weight float64) string {
		return fmt.Sprintf(
			`{"member_id":%q,"date":%q,"weight":%g,"smm":32.1,"bfm":12.8,"pbf":18.4,"vfl":6,"bmr":1560}`,
			mem.ID, date, weight)
	}
	yesterday := time.Now().In(domain.KST).AddDate(0, 0, -1).Format("2006-01-02")

	// ① 스태프 생성 → 200 + source=staff(응답 본문에 실려야 한다 — 앱이 삭제 버튼 노출을 이 값으로 가른다).
	rec := doReq(t, r, http.MethodPost, "/v1/inbody", "owner1", domain.RoleOwner, body(today(), 70.5))
	if rec.Code != http.StatusOK {
		t.Fatalf("스태프 생성 = %d %s, want 200", rec.Code, rec.Body.String())
	}
	var staffRec domain.Inbody
	if err := json.Unmarshal(rec.Body.Bytes(), &staffRec); err != nil {
		t.Fatal(err)
	}
	if staffRec.Source != domain.InbodySourceStaff {
		t.Errorf("응답 source = %q, want %q", staffRec.Source, domain.InbodySourceStaff)
	}

	// ② 같은 날 재요청 → 409(연타·응답 유실 재시도의 실제 모양).
	if rec := doReq(t, r, http.MethodPost, "/v1/inbody", "owner1", domain.RoleOwner, body(today(), 71.0)); rec.Code != http.StatusConflict {
		t.Errorf("중복 = %d %s, want 409", rec.Code, rec.Body.String())
	}

	// ③ 요청 바디에 source를 실으면 400(decodeJSON의 DisallowUnknownFields). 앱이 절대 보내면
	//    안 되는 필드라, 계약이 실제로 그렇게 동작하는지 여기서 못박는다.
	withSource := fmt.Sprintf(
		`{"member_id":%q,"date":%q,"weight":70.5,"smm":32.1,"bfm":12.8,"pbf":18.4,"vfl":6,"bmr":1560,"source":"staff"}`,
		mem.ID, yesterday)
	if rec := doReq(t, r, http.MethodPost, "/v1/inbody", "owner1", domain.RoleOwner, withSource); rec.Code != http.StatusBadRequest {
		t.Errorf("source 포함 요청 = %d %s, want 400", rec.Code, rec.Body.String())
	}

	// ④ 범위 위반 → 400, 그리고 응답 문구가 한국어 사용자향이어야 한다(Go 에러 원문 노출 금지).
	bad := fmt.Sprintf(`{"member_id":%q,"date":%q,"weight":0,"smm":32.1,"bfm":12.8,"pbf":18.4,"vfl":6,"bmr":1560}`,
		mem.ID, yesterday)
	rec = doReq(t, r, http.MethodPost, "/v1/inbody", "owner1", domain.RoleOwner, bad)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("범위 위반 = %d, want 400", rec.Code)
	}
	if msg := rec.Body.String(); strings.Contains(msg, "domain:") || !strings.Contains(msg, "체중") {
		t.Errorf("에러 본문이 사용자향이 아니다: %s", msg)
	}

	// ⑤ 미래 날짜 → 400.
	if rec := doReq(t, r, http.MethodPost, "/v1/inbody", "owner1", domain.RoleOwner, body("2099-12-31", 70.5)); rec.Code != http.StatusBadRequest {
		t.Errorf("미래 날짜 = %d, want 400", rec.Code)
	}

	// ⑥ 회원이 스태프 기록 삭제 → 403.
	if rec := doReq(t, r, http.MethodDelete, "/v1/inbody/"+staffRec.ID, memberUID, domain.RoleMember, ""); rec.Code != http.StatusForbidden {
		t.Errorf("회원→staff 기록 삭제 = %d %s, want 403", rec.Code, rec.Body.String())
	}

	// ⑦ 회원 본인 생성 → source=member_self, 삭제 → 200 {"deleted":true}.
	rec = doReq(t, r, http.MethodPost, "/v1/inbody", memberUID, domain.RoleMember, body(yesterday, 70.2))
	if rec.Code != http.StatusOK {
		t.Fatalf("회원 생성 = %d %s, want 200", rec.Code, rec.Body.String())
	}
	var selfRec domain.Inbody
	if err := json.Unmarshal(rec.Body.Bytes(), &selfRec); err != nil {
		t.Fatal(err)
	}
	if selfRec.Source != domain.InbodySourceMemberSelf {
		t.Errorf("회원 생성 source = %q, want %q", selfRec.Source, domain.InbodySourceMemberSelf)
	}
	rec = doReq(t, r, http.MethodDelete, "/v1/inbody/"+selfRec.ID, memberUID, domain.RoleMember, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("본인 기록 삭제 = %d %s, want 200", rec.Code, rec.Body.String())
	}
	var delBody map[string]bool
	if err := json.Unmarshal(rec.Body.Bytes(), &delBody); err != nil || !delBody["deleted"] {
		t.Errorf("삭제 응답 본문 = %s", rec.Body.String())
	}

	// ⑧ 두 번째 삭제 → 404(재시도가 "지웠다"를 두 번 보고하지 않는다).
	if rec := doReq(t, r, http.MethodDelete, "/v1/inbody/"+selfRec.ID, memberUID, domain.RoleMember, ""); rec.Code != http.StatusNotFound {
		t.Errorf("재삭제 = %d, want 404", rec.Code)
	}

	// ⑨ 삭제한 날짜는 다시 넣을 수 있다(정정 = 삭제 + 재입력).
	if rec := doReq(t, r, http.MethodPost, "/v1/inbody", memberUID, domain.RoleMember, body(yesterday, 70.9)); rec.Code != http.StatusOK {
		t.Errorf("재입력 = %d %s, want 200", rec.Code, rec.Body.String())
	}
}
