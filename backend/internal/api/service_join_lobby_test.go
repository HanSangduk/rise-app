package api

// 대기실(Lobby) 회귀 테스트 — 계약 v2.27 · P55.
//
// 이 파일이 지키는 것은 "게이트를 옮기지 않고 게이트를 진실하고 유용하게 만든다"는 결정이다.
// 센터 미연결 회원은 여전히 홈에 못 들어가지만, 그 대기 상태가
//
//	① 서버에 있고(GET /v1/me의 join_request — 기기를 바꿔도 살아남는다)
//	② 하나뿐이고(pending 중복 409)
//	③ 큐에서 사라질 수 있고(pending 필터 + 거절)
//	④ **회원 기록을 죽이지 않는다**(이미 연결된 uid 승인 차단 + 연결 시 요청 파기)
//
// 는 네 성질을 갖는다. ④의 두 겹은 이미 배포된 CRITICAL(C-2)의 원인 제거와 마지막
// 방어선이라 각각 따로 고정한다 — 하나를 지웠을 때 다른 하나가 테스트를 초록으로
// 유지하면 그 순간 사고가 되돌아온다.

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// ---- A-1: GET /v1/me의 join_request ----

// 대기 상태의 주인이 서버다. 종전엔 앱의 SharedPreferences였고, 재설치·기기 변경이 그 상태를
// 지워서 이미 큐에 서 있는 사람이 화면상 "아무것도 안 한 사람"이 됐다.
func TestMeExposesJoinRequestForUnlinkedMember(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	applicant := Principal{UID: "u_lobby", Role: domain.RoleMember, CenterID: testCenter}

	// 요청 전 — 필드 자체가 없어야 한다(omitempty).
	if me := s.Me(ctx, applicant); me.JoinRequest != nil {
		t.Fatalf("요청 전 join_request = %+v, want nil", me.JoinRequest)
	}

	jr, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"})
	if err != nil {
		t.Fatal(err)
	}
	me := s.Me(ctx, applicant)
	if me.JoinRequest == nil {
		t.Fatal("요청 후에도 join_request가 없다 — 앱이 대기 상태를 복원할 수 없다")
	}
	if me.JoinRequest.Status != store.JoinPending {
		t.Errorf("status = %q, want pending", me.JoinRequest.Status)
	}
	if !me.JoinRequest.CreatedAt.Equal(jr.CreatedAt) {
		t.Errorf("created_at = %v, want %v — 앱이 '언제 보냈는지'를 띄운다", me.JoinRequest.CreatedAt, jr.CreatedAt)
	}
}

// **연결 전 단계 최소 노출**(JoinMatchMember와 같은 규율). id·name·phone은 실리지
// 않는다 — 이름·번호는 신청자가 방금 자기 손으로 적은 값이라 서버가 되돌려줄 이유가 없고,
// id는 owner 전용 동사(승인·거절)의 인자라 신청자에게 쓸모가 없다.
// center_id는 v2.34부터 **실린다** — v2.33이 센터 선택을 연 뒤로는 감추는 쪽이 거짓이다
// (요청은 2호점에 있는데 대기실은 1호점 연락처를 찍는다). 자기 uid 스코프·본인이 고른 값.
func TestMeJoinRequestExposesOnlyStatusCenterAndCreatedAt(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	applicant := Principal{UID: "u_lobby", Role: domain.RoleMember, CenterID: testCenter}
	if _, err := s.JoinRequestCreate(ctx, applicant,
		JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"}); err != nil {
		t.Fatal(err)
	}
	blob, err := json.Marshal(s.Me(ctx, applicant).JoinRequest)
	if err != nil {
		t.Fatal(err)
	}
	for _, leaked := range []string{"박지훈", "010-3333-2222", `"id"`, `"uid"`, `"name"`, `"phone"`} {
		if strings.Contains(string(blob), leaked) {
			t.Errorf("join_request에 %s 노출: %s", leaked, blob)
		}
	}
	var keys map[string]any
	if err := json.Unmarshal(blob, &keys); err != nil {
		t.Fatal(err)
	}
	if len(keys) != 3 {
		t.Errorf("join_request 키 %d개 %v, want 3(status/center_id/created_at)", len(keys), keys)
	}
	if keys["center_id"] != testCenter {
		t.Errorf("center_id = %v, want %q — 앱 대기실이 이 값으로 그 센터의 연락처·시간을 그린다", keys["center_id"], testCenter)
	}
}

// **v2.34 — 다른 센터에 보낸 요청도 /v1/me에 실린다.** 종전 latestJoinRequest는 Principal.CenterID
// (미연결 uid = 기본 센터 폴백) 큐만 훑어 2호점에 보낸 요청이 0건이 됐다 — 앱은 "요청 없음"을
// 읽고 사용자는 재요청 → 409 루프에 갇혔다(P69 팀 C 1-b). 이 테스트가 그 결함을 재현한다:
// uid 조회로 바꾸기 전에는 JoinRequest가 nil이다.
func TestMeJoinRequestFollowsSelectedCenter(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")
	applicant := Principal{UID: "u_lobby2", Role: domain.RoleMember, CenterID: testCenter} // 폴백 센터는 1호점

	if _, err := s.JoinRequestCreate(ctx, applicant,
		JoinRequestBody{CenterID: "gangnam-2", Name: "박지훈", Phone: "010-3333-2222"}); err != nil {
		t.Fatal(err)
	}
	me := s.Me(ctx, applicant)
	if me.JoinRequest == nil {
		t.Fatal("2호점에 보낸 요청이 /v1/me에 없다 — 기본 센터 큐만 훑고 있다(v2.33 이전 회귀)")
	}
	if me.JoinRequest.CenterID != "gangnam-2" || me.JoinRequest.Status != store.JoinPending {
		t.Errorf("join_request = %+v, want gangnam-2 pending", me.JoinRequest)
	}

	// 같은 사람이 1호점에도 보내면(센터별 409 규약은 종전대로 — 철회 동사가 없는 동안 전 센터로
	// 넓히면 사용자를 가둔다) 최신 1건이 현재 상태다.
	if _, err := s.JoinRequestCreate(ctx, applicant,
		JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"}); err != nil {
		t.Fatalf("다른 센터 요청 = %v, want 성공(판정은 센터별)", err)
	}
	if me := s.Me(ctx, applicant); me.JoinRequest == nil || me.JoinRequest.CenterID != testCenter {
		t.Errorf("최신 요청이 현재 상태여야 한다: %+v", me.JoinRequest)
	}
	// 어느 쪽 센터든 그 센터에 pending이 있으면 409 — 본문은 code + center_id(v2.34).
	_, err := s.JoinRequestCreate(ctx, applicant,
		JoinRequestBody{CenterID: "gangnam-2", Name: "박지훈", Phone: "010-3333-2222"})
	var pending *joinPendingError
	if !errors.Is(err, ErrConflict) || !errors.As(err, &pending) || pending.centerID != "gangnam-2" {
		t.Fatalf("2호점 중복 = %v, want joinPendingError{gangnam-2}", err)
	}
}

// **승인이 같은 번호의 살아 있는 회원 위에 두 번째 레코드를 만들지 않는다**(v2.34, P69).
// 요청 이후에 데스크가 그 사람을 등록한 경우다 — 옳은 연결은 회원의 재인증(join/match)이지
// 승인이 아니다. 어드민 큐의 힌트가 같은 말을 먼저 하지만 화면 경고는 방어선이 아니다.
func TestJoinApproveRefusesDuplicatePhoneOfActiveMember(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 10) // 데스크가 등록한 회원(앱 미연결)

	applicant := Principal{UID: "u_dup", Role: domain.RoleMember, CenterID: testCenter}
	jr, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: mem.Name, Phone: mem.Phone})
	if err != nil {
		t.Fatal(err)
	}
	_, err = s.JoinApprove(ctx, ownerP(), jr.ID)
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("같은 번호 회원이 있는데 승인 = %v, want ErrConflict", err)
	}
	if msg := userMessage(err); !strings.Contains(msg, mem.Name) || !strings.Contains(msg, "번호 다시 인증하기") {
		t.Errorf("문구 = %q — 누구와 겹치는지·다음 행동(재인증)을 말해야 한다", msg)
	}
	// 부작용 0: 회원은 그대로 1명, 요청은 여전히 pending(이름·번호 보존 — 거절과 다르다).
	members, err := s.ListMembers(ctx, ownerP(), "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(members) != 1 {
		t.Fatalf("회원 %d명, want 1 — 거부했는데 레코드가 생겼다", len(members))
	}
	got, err := s.store.GetJoinRequest(ctx, jr.ID)
	if err != nil || got.Status != store.JoinPending || got.Name != mem.Name {
		t.Fatalf("요청 = %+v (err=%v), want pending·이름 보존", got, err)
	}
	// 정규화 대조: 표기가 달라도(하이픈 없음) 같은 번호다.
	jr2, err := s.JoinRequestCreate(ctx, Principal{UID: "u_dup2", Role: domain.RoleMember, CenterID: testCenter},
		JoinRequestBody{Name: "다른표기", Phone: strings.ReplaceAll(mem.Phone, "-", "")})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.JoinApprove(ctx, ownerP(), jr2.ID); !errors.Is(err, ErrConflict) {
		t.Errorf("표기만 다른 번호의 승인 = %v, want ErrConflict", err)
	}
	// 번호가 다른 신청자는 종전대로 승인된다.
	jr3, err := s.JoinRequestCreate(ctx, Principal{UID: "u_new", Role: domain.RoleMember, CenterID: testCenter},
		JoinRequestBody{Name: "신규", Phone: "010-7777-8888"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.JoinApprove(ctx, ownerP(), jr3.ID); err != nil {
		t.Errorf("번호가 다른 신청자 승인 = %v, want 성공", err)
	}
}

// 연결된 회원·스태프에겐 나가지 않는다. 스태프는 member_id가 늘 비어 있어, 분기 순서가
// 뒤집히면 대표의 /v1/me가 매 호출마다 가입 요청 큐를 훑고 신청자의 대기 상태를 되돌려준다.
func TestMeOmitsJoinRequestForLinkedMemberAndStaff(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20)

	// 대표 uid로도 요청 문서를 심어 둔다(스토어 직접 — 서비스 경로는 guardNotStaff가 막는다).
	if _, err := s.store.CreateJoinRequest(ctx, &store.JoinRequest{
		CenterID: testCenter, UID: "owner1", Name: "대표", Phone: "010-1111-1111", Status: store.JoinPending,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.store.CreateJoinRequest(ctx, &store.JoinRequest{
		CenterID: testCenter, UID: "u-" + mem.ID, Name: "김민지", Phone: "010-1234-5678", Status: store.JoinPending,
	}); err != nil {
		t.Fatal(err)
	}

	if me := s.Me(ctx, ownerP()); me.JoinRequest != nil {
		t.Errorf("owner /v1/me에 join_request = %+v, want nil", me.JoinRequest)
	}
	if me := s.Me(ctx, trainerP()); me.JoinRequest != nil {
		t.Errorf("trainer /v1/me에 join_request = %+v, want nil", me.JoinRequest)
	}
	if me := s.Me(ctx, memberP(mem.ID)); me.JoinRequest != nil {
		t.Errorf("연결된 회원 /v1/me에 join_request = %+v, want nil — member_id가 곧 '대기 끝'이다", me.JoinRequest)
	}

	// superadmin도 이 분기에 들어오지 않는다. 분기 조건이 `case p.IsMember()`가 아니라
	// `default`였다면 소속 없는 principal(CenterID="")이 매 /v1/me마다 가입 요청 컬렉션을
	// 훑게 되고, center_id가 빈 레거시·시딩 문서가 하나라도 있으면 그것을 자기 대기 상태로
	// 되받는다(스토어 적합성 테스트가 uid 빈 문서를 다루는 것과 같은 계열의 잔여다).
	if _, err := s.store.CreateJoinRequest(ctx, &store.JoinRequest{
		UID: "sa1", Name: "레거시", Phone: "010-0000-0000", Status: store.JoinPending, // center_id 없음
	}); err != nil {
		t.Fatal(err)
	}
	if me := s.Me(ctx, superadminP()); me.JoinRequest != nil {
		t.Errorf("superadmin /v1/me에 join_request = %+v, want nil — 소속 없는 롤은 대기실에 없다", me.JoinRequest)
	}
}

// 거절도 결론이고, 그 결론이 신청자에게 도달해야 한다(D-3이 문서를 통째로 지우지 않기로 한
// 이유와 같은 자리). rejected를 감추면 신청자는 pending과 구별하지 못해 영원히 기다린다.
func TestMeJoinRequestReportsRejection(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	applicant := Principal{UID: "u_lobby", Role: domain.RoleMember, CenterID: testCenter}
	jr, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.JoinReject(ctx, ownerP(), jr.ID); err != nil {
		t.Fatal(err)
	}
	me := s.Me(ctx, applicant)
	if me.JoinRequest == nil || me.JoinRequest.Status != store.JoinRejected {
		t.Fatalf("거절 후 join_request = %+v, want status=rejected", me.JoinRequest)
	}
}

// ---- A-2: pending 중복 409 ----

// **뮤테이션 표적**: JoinRequestCreate의 중복 루프를 지우면 여기서 죽는다.
//
// 같은 사람이 큐에 2·3건씩 쌓이던 것이 C-2(좀비 승인)의 재료였다. 규칙·문구 형태는
// CreateConsultRequest(v2.20)와 같다 — 새 패턴이 아니다.
func TestJoinRequestRejectsDuplicatePending(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	applicant := Principal{UID: "u_lobby", Role: domain.RoleMember, CenterID: testCenter}

	first, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"})
	if err != nil {
		t.Fatal(err)
	}
	_, err = s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"})
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("중복 가입 요청 = %v, want ErrConflict", err)
	}
	// 문구가 "살아 있다"는 사실을 전달해야 한다(가두지 않는다는 것의 실체).
	if msg := userMessage(err); msg != "이미 보낸 가입 요청이 있어요 — 센터에서 확인하면 연결돼요" {
		t.Errorf("문구 = %q — 요청이 살아 있다는 사실이 전달되지 않는다", msg)
	}
	list, err := s.store.ListJoinRequests(ctx, testCenter)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != first.ID {
		t.Fatalf("큐 = %+v, want 첫 요청 1건 — 중복이 실제로 만들어졌다", list)
	}

	// 남의 pending은 막지 않는다(uid 스코프 — 센터 전체를 잠그면 두 번째 신청자가 못 들어온다).
	other := Principal{UID: "u_other", Role: domain.RoleMember, CenterID: testCenter}
	if _, err := s.JoinRequestCreate(ctx, other, JoinRequestBody{Name: "이서준", Phone: "010-9999-0000"}); err != nil {
		t.Fatalf("다른 신청자 요청 = %v, want 성공", err)
	}
}

// 409가 사용자를 **가두지 않는다**: 결론(거절)이 나면 같은 사람이 다시 요청할 수 있어야 한다.
// pending이 아닌 요청은 중복 판정의 대상이 아니다.
func TestJoinRequestAllowedAgainAfterRejection(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	applicant := Principal{UID: "u_lobby", Role: domain.RoleMember, CenterID: testCenter}

	jr, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.JoinReject(ctx, ownerP(), jr.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.JoinRequestCreate(ctx, applicant,
		JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"}); err != nil {
		t.Fatalf("거절 후 재요청 = %v, want 성공 — 거절이 영구 차단이 되면 그게 막다른 길이다", err)
	}
}

// ---- A-3: 목록은 pending만 ----

// **뮤테이션 표적**: ListJoinRequests의 status 필터를 지우면 여기서 죽는다.
//
// 종전엔 승인·거절된 요청이 큐에 그대로 남아 대표가 "처리할 것"과 "처리한 것"을 구별할 수
// 없었다. 어드민 대기 건수가 사실이 아니었고, 그 착시가 두 번 누르는 동선을 만들었다.
func TestListJoinRequestsReturnsPendingOnly(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	mk := func(uid, name, phone string) *store.JoinRequest {
		t.Helper()
		jr, err := s.JoinRequestCreate(ctx,
			Principal{UID: uid, Role: domain.RoleMember, CenterID: testCenter},
			JoinRequestBody{Name: name, Phone: phone})
		if err != nil {
			t.Fatalf("JoinRequestCreate(%s): %v", uid, err)
		}
		return jr
	}
	approved := mk("u_a", "승인될사람", "010-1111-0001")
	rejected := mk("u_r", "거절될사람", "010-1111-0002")
	pending := mk("u_p", "대기중", "010-1111-0003")

	if _, err := s.JoinApprove(ctx, ownerP(), approved.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.JoinReject(ctx, ownerP(), rejected.ID); err != nil {
		t.Fatal(err)
	}

	list, err := s.ListJoinRequests(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != pending.ID {
		t.Fatalf("큐 = %+v, want pending 1건 — 처리된 요청이 큐에 남으면 대기 건수가 거짓이 된다", list)
	}

	// **감사 추적은 사라지지 않는다** — 필터는 응답에만 걸리고 문서는 스토어에 그대로 있다.
	all, err := s.store.ListJoinRequests(ctx, testCenter)
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 3 {
		t.Errorf("스토어의 요청 = %d건, want 3 — 필터가 문서를 지우고 있다(이력이 사라진다)", len(all))
	}
}

// ---- A-4: 이미 연결된 uid는 승인하지 않는다(C-2 마지막 방어선) ----

// **뮤테이션 표적**: JoinApprove의 "이미 연결된 uid" 가드를 지우면 여기서 죽는다.
//
// 실측 사고를 그대로 재현한다: 앱으로 먼저 요청(pending) → 대표가 데스크에서 그 사람을
// 어드민에 등록 → 회원이 재인증해 join/match+confirm으로 **진짜 레코드에 연결**(회원권이
// 거기 붙는다) → 며칠 뒤 대표가 큐를 정리하다 ①을 승인 → 종전엔 빈 회원 레코드가 새로
// 만들어지고 UserIndex가 그리로 옮겨가 **회원권·예약·기록이 통째로 사라졌다.**
//
// 이 시나리오에서 A-5(연결 시 요청 파기)를 우회하기 위해 요청 문서를 confirm **뒤에**
// 스토어로 직접 심는다 — 이미 배포된 프로덕션에 남아 있는 잔여 요청이 정확히 이 모양이다.
func TestJoinApproveRefusesAlreadyLinkedUID(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20) // 김민지 010-1234-5678, 회원권 20회

	applicant := Principal{UID: "u_dup", Role: domain.RoleMember, CenterID: testCenter}
	if out, err := s.JoinConfirm(ctx, applicant,
		JoinConfirmRequest{MemberID: mem.ID, Confirm: true, Phone: "010-1234-5678"}); err != nil || !out.Linked {
		t.Fatalf("연결 실패: %v", err)
	}
	// 배포 이전에 만들어진 좀비 요청(A-5의 파기를 지나온 상태를 흉내낸다).
	zombieID, err := s.store.CreateJoinRequest(ctx, &store.JoinRequest{
		CenterID: testCenter, UID: "u_dup", Name: "김민지", Phone: "010-1234-5678",
		Status: store.JoinPending,
	})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := s.JoinApprove(ctx, ownerP(), zombieID); !errors.Is(err, ErrConflict) {
		t.Fatalf("좀비 요청 승인 = %v, want ErrConflict — 회원 기록이 통째로 날아가는 경로다", err)
	}

	// 신원이 원래 레코드를 계속 가리키는가(승인이 UserIndex를 옮기지 않았는가).
	idx, err := s.store.GetUserIndex(ctx, "u_dup")
	if err != nil || idx.MemberID != mem.ID {
		t.Fatalf("UserIndex = %+v (err=%v), want member_id=%s — 신원이 빈 레코드로 옮겨갔다", idx, err, mem.ID)
	}
	// 회원권이 그대로인가(사고의 실제 피해).
	passes, err := s.store.ListPassesByMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(passes) != 1 || passes[0].ID != pass.ID {
		t.Fatalf("회원권 = %+v, want 1건 온전", passes)
	}
	// 빈 회원 레코드가 만들어지지 않았는가.
	members, err := s.ListMembers(ctx, ownerP(), "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(members) != 1 {
		t.Fatalf("회원 %d명, want 1 — 승인이 빈 레코드를 새로 만들었다: %+v", len(members), members)
	}
}

// **가드가 재가입을 막지 않는지 고정한다.** 탈퇴는 DeleteUserIndex를 수행하므로 GetUserIndex가
// ErrNotFound → 가드 통과 → 정상적으로 새 레코드가 생긴다. 그리고 탈퇴자에게 JoinConfirm은
// IsWithdrawn으로 막혀 있으므로(v2.11) **가입 요청 승인이 돌아오는 유일한 길**이다 —
// 여기서 막으면 탈퇴한 사람이 영원히 못 돌아온다.
func TestJoinApproveAllowsRejoinAfterWithdrawal(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedWithdrawableMember(t, s)

	if _, err := s.DeleteMyAccount(ctx, memberP(mem.ID)); err != nil {
		t.Fatalf("탈퇴: %v", err)
	}
	// 같은 사람이 같은 uid로 돌아온다(Firebase가 번호로 같은 계정을 다시 만드는 경우).
	returning := Principal{UID: "u-" + mem.ID, Role: domain.RoleMember, CenterID: testCenter}

	// 확인 경로는 여전히 막혀 있어야 한다(v2.11 — 탈퇴는 되돌릴 수 없는 종단 상태다).
	if _, err := s.JoinConfirm(ctx, returning,
		JoinConfirmRequest{MemberID: mem.ID, Confirm: true, Phone: "010-1234-5678"}); err == nil {
		t.Fatal("탈퇴 레코드에 재연결됐다 — v2.11 가드가 깨졌다")
	}
	// 요청 → 승인은 열려 있어야 한다.
	jr, err := s.JoinRequestCreate(ctx, returning, JoinRequestBody{Name: "김민지", Phone: "010-1234-5678"})
	if err != nil {
		t.Fatalf("재가입 요청 = %v, want 성공", err)
	}
	fresh, err := s.JoinApprove(ctx, ownerP(), jr.ID)
	if err != nil {
		t.Fatalf("재가입 승인 = %v, want 성공 — 이 경로를 막으면 탈퇴자가 영원히 못 돌아온다", err)
	}
	if fresh.ID == mem.ID {
		t.Errorf("탈퇴 레코드를 재사용했다: %s — 새 레코드여야 한다", fresh.ID)
	}
	idx, err := s.store.GetUserIndex(ctx, returning.UID)
	if err != nil || idx.MemberID != fresh.ID {
		t.Fatalf("UserIndex = %+v (err=%v), want 새 레코드 %s", idx, err, fresh.ID)
	}
}

// ---- A-5: 연결되면 그 uid의 가입 요청은 파기된다(C-2 원인 제거) ----

// **뮤테이션 표적**: JoinConfirm 끝의 DeleteJoinRequestsByUID 호출을 지우면 여기서 죽는다.
//
// A-4(승인 차단)와 **따로** 고정하는 이유: 둘은 같은 사고의 원인 제거와 방어선이라 한쪽만
// 남아도 사고 자체는 안 나지만, 원인이 남으면 큐에 처리 불가능한 유령 행이 계속 쌓이고
// (대표는 그것을 승인할 수도 거절할 수도 없다 — 승인은 409다) 그 안의 이름·전화번호가
// 목적을 잃은 채 남는다.
func TestJoinConfirmDestroysPendingJoinRequests(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20) // 김민지 010-1234-5678

	applicant := Principal{UID: "u_dup", Role: domain.RoleMember, CenterID: testCenter}
	if _, err := s.JoinRequestCreate(ctx, applicant,
		JoinRequestBody{Name: "김민지", Phone: "010-1234-5678"}); err != nil {
		t.Fatal(err)
	}
	// 이웃 신청자 — 남의 요청까지 쓸어가면 안 된다.
	if _, err := s.JoinRequestCreate(ctx,
		Principal{UID: "u_other", Role: domain.RoleMember, CenterID: testCenter},
		JoinRequestBody{Name: "이서준", Phone: "010-9999-0000"}); err != nil {
		t.Fatal(err)
	}

	if out, err := s.JoinConfirm(ctx, applicant,
		JoinConfirmRequest{MemberID: mem.ID, Confirm: true, Phone: "010-1234-5678"}); err != nil || !out.Linked {
		t.Fatalf("연결 실패: %v", err)
	}

	list, err := s.store.ListJoinRequests(ctx, testCenter)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].UID != "u_other" {
		t.Fatalf("연결 후 큐 = %+v, want 이웃 1건만 — 좀비 요청이 남았다(C-2의 원인)", list)
	}
	// 대기 상태도 함께 사라져야 한다(앱이 '연결됐는데 대기 중'을 동시에 보면 안 된다).
	if me := s.Me(ctx, memberP(mem.ID)); me.JoinRequest != nil {
		t.Errorf("연결 후 /v1/me join_request = %+v, want nil", me.JoinRequest)
	}
}

// confirm=false("본인이 아니에요")는 아무것도 지우지 않는다 — 연결되지 않았으므로 그 사람의
// 요청은 여전히 유효한 대기다.
func TestJoinConfirmDeclineKeepsJoinRequest(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20)

	applicant := Principal{UID: "u_dup", Role: domain.RoleMember, CenterID: testCenter}
	if _, err := s.JoinRequestCreate(ctx, applicant,
		JoinRequestBody{Name: "김민지", Phone: "010-1234-5678"}); err != nil {
		t.Fatal(err)
	}
	if out, err := s.JoinConfirm(ctx, applicant,
		JoinConfirmRequest{MemberID: mem.ID, Confirm: false, Phone: "010-1234-5678"}); err != nil || out.Linked {
		t.Fatalf("confirm=false = %v linked=%v", err, out.Linked)
	}
	if list, _ := s.store.ListJoinRequests(ctx, testCenter); len(list) != 1 {
		t.Fatalf("거부 후 큐 = %+v, want 1건 유지 — 연결되지 않았는데 대기가 사라졌다", list)
	}
}

// ---- D-3: 거절 ----

// **뮤테이션 표적**: JoinReject의 Name/Phone 비우기를 지우거나, owner·센터 가드를 지우면
// 여기서 죽는다.
func TestJoinRejectAnonymizesAndGuards(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	applicant := Principal{UID: "u_lobby", Role: domain.RoleMember, CenterID: testCenter}
	jr, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: "박지훈", Phone: "010-3333-2222"})
	if err != nil {
		t.Fatal(err)
	}

	// 권한: owner만(JoinApprove와 같은 경계).
	for _, p := range []Principal{trainerP(), applicant} {
		if _, err := s.JoinReject(ctx, p, jr.ID); !errors.Is(err, ErrForbidden) {
			t.Errorf("%s JoinReject = %v, want ErrForbidden", p.Role, err)
		}
	}
	// 센터 대조: 남의 센터 요청은 거절할 수 없다.
	foreign := Principal{UID: "owner2", Role: domain.RoleOwner, CenterID: "gangnam-2"}
	if _, err := s.JoinReject(ctx, foreign, jr.ID); !errors.Is(err, ErrForbidden) {
		t.Errorf("타 센터 owner JoinReject = %v, want ErrForbidden — 남의 큐를 조작하는 경로다", err)
	}

	out, err := s.JoinReject(ctx, ownerP(), jr.ID)
	if err != nil {
		t.Fatalf("거절 = %v", err)
	}
	if out.Status != store.JoinRejected {
		t.Errorf("status = %q, want rejected — store.JoinRejected는 v1.2부터 있었는데 아무도 대입하지 않았다", out.Status)
	}
	if out.Name != "" || out.Phone != "" {
		t.Errorf("거절 후 name=%q phone=%q — 목적을 잃은 개인정보가 남았다", out.Name, out.Phone)
	}
	// 저장된 문서를 다시 읽어 대조한다(응답만 비우고 저장은 안 하는 실수를 잡는다).
	saved, err := s.store.GetJoinRequest(ctx, jr.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Name != "" || saved.Phone != "" {
		t.Errorf("저장된 문서 name=%q phone=%q — 응답만 비웠다", saved.Name, saved.Phone)
	}
	// **문서 자체는 남는다** — 지우면 신청자 화면이 "요청한 적 없음"으로 되돌아가고
	// 무한 재요청 루프가 생긴다.
	if saved.UID != "u_lobby" || saved.CenterID != testCenter || saved.CreatedAt.IsZero() {
		t.Errorf("남은 문서 = %+v, want {uid, center_id, status, created_at} 온전", saved)
	}

	// 멱등 아님: 이미 처리된 요청은 409(JoinApprove와 같은 규칙).
	if _, err := s.JoinReject(ctx, ownerP(), jr.ID); !errors.Is(err, ErrConflict) {
		t.Errorf("중복 거절 = %v, want ErrConflict", err)
	}
	// 승인된 요청도 뒤늦게 거절로 덮을 수 없다.
	jr2, err := s.JoinRequestCreate(ctx,
		Principal{UID: "u_ok", Role: domain.RoleMember, CenterID: testCenter},
		JoinRequestBody{Name: "이서준", Phone: "010-9999-0000"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.JoinApprove(ctx, ownerP(), jr2.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.JoinReject(ctx, ownerP(), jr2.ID); !errors.Is(err, ErrConflict) {
		t.Errorf("승인된 요청 거절 = %v, want ErrConflict — 두 기록이 서로 다른 말을 하게 된다", err)
	}
}

// ---- A-6: PUT /v1/center {center} ----

// **뮤테이션 표적**: UpdateCenterIdentity의 owner 가드 / 부분 갱신(포인터) / ID 봉인을
// 지우면 여기서 죽는다.
func TestUpdateCenterIdentity(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	// 권한: owner만.
	for _, p := range []Principal{trainerP(), memberP("m1")} {
		if _, err := s.UpdateCenterIdentity(ctx, p, []byte(`{"name":"라이즈 컨디셔닝"}`)); !errors.Is(err, ErrForbidden) {
			t.Errorf("%s = %v, want ErrForbidden", p.Role, err)
		}
	}

	c, err := s.UpdateCenterIdentity(ctx, ownerP(),
		[]byte(`{"name":" 라이즈 컨디셔닝 ","phone":"02-555-1234","address":"서울 강남구 …"}`))
	if err != nil {
		t.Fatalf("등록 = %v", err)
	}
	if c.Name != "라이즈 컨디셔닝" { // 검증 전 Normalize — 붙여넣기 공백으로 400이 나면 안 된다
		t.Errorf("name = %q", c.Name)
	}
	if c.ID != testCenter || c.Status != domain.CenterStatusActive || c.CreatedAt.IsZero() {
		t.Errorf("center = %+v, want id/status/created_at 자동 채움", c)
	}

	// **부분 갱신**: 이름만 보내면 전화·주소는 그대로다(P27·P49 교훈 — 머지 쓰기).
	c2, err := s.UpdateCenterIdentity(ctx, ownerP(), []byte(`{"name":"라이즈 컨디셔닝 강남"}`))
	if err != nil {
		t.Fatal(err)
	}
	if c2.Phone != "02-555-1234" || c2.Address != "서울 강남구 …" {
		t.Fatalf("부분 갱신이 다른 칸을 지웠다: %+v", c2)
	}
	if !c2.CreatedAt.Equal(c.CreatedAt) {
		t.Errorf("created_at이 갱신마다 바뀐다: %v → %v", c.CreatedAt, c2.CreatedAt)
	}
	// 명시적 빈 값은 "지우기"다(business가 통 교체로 얻은 성질).
	c3, err := s.UpdateCenterIdentity(ctx, ownerP(), []byte(`{"address":""}`))
	if err != nil {
		t.Fatal(err)
	}
	if c3.Address != "" || c3.Name != "라이즈 컨디셔닝 강남" {
		t.Fatalf("명시적 빈 값이 반영되지 않았다: %+v", c3)
	}

	// **ID·상태·생성시각은 봉인**: 보내면 400(DisallowUnknownFields). 통과하면 SaveCenter가
	// 다른 센터 문서에 쓴다 — 대표의 폼이 남의 센터를 덮어쓰는 경로가 된다.
	for _, body := range []string{
		`{"id":"gangnam-2","name":"탈취"}`,
		`{"status":"closed","name":"x"}`,
		`{"created_at":"2020-01-01T00:00:00Z","name":"x"}`,
	} {
		if _, err := s.UpdateCenterIdentity(ctx, ownerP(), []byte(body)); !errors.Is(err, errBadRequest) {
			t.Errorf("%s = %v, want 400(봉인 필드)", body, err)
		}
	}
	if other, _ := s.store.GetCenter(ctx, "gangnam-2"); other.Name != "" {
		t.Fatalf("남의 센터가 쓰였다: %+v", other)
	}

	// 도메인 검증은 그대로 걸린다(빈 이름은 400 — ListCenters가 유령으로 거르는 상태).
	if _, err := s.UpdateCenterIdentity(ctx, ownerP(), []byte(`{"name":""}`)); !errors.Is(err, domain.ErrInvalidCenter) {
		t.Errorf("빈 이름 = %v, want ErrInvalidCenter", err)
	}
}

// 센터 신원 저장이 정책·사업자 정보·시설 선언을 건드리지 않는다(P27 SavePolicy 교훈).
// 그리고 등록되면 관리 평면 목록에 실제로 뜬다 — 운영 센터가 유령이 아니게 되는 것이
// 이 기능의 존재 이유다(회원 센터 선택의 선행조건).
func TestUpdateCenterIdentityDoesNotDisturbOtherSections(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	if _, err := s.UpdateCenterPolicy(ctx, ownerP(), []byte(`{"open_hour":6,"close_hour":23,"revenue_target":120000000}`)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterBusiness(ctx, ownerP(), []byte(completeBusinessJSON)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterFacility(ctx, ownerP(), domain.Facility{
		ReportStatus: domain.FacilityStatusReported, ReportNo: "제2026-강남-0001호",
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCenterIdentity(ctx, ownerP(),
		[]byte(`{"name":"라이즈 컨디셔닝","phone":"02-555-1234"}`)); err != nil {
		t.Fatal(err)
	}

	got, err := s.GetCenter(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "라이즈 컨디셔닝" {
		t.Errorf("name = %q", got.Name)
	}
	if got.Policy.OpenHour != 6 || got.Policy.CloseHour != 23 || got.Policy.RevenueTarget != 120000000 {
		t.Errorf("정책이 훼손됐다: %+v", got.Policy)
	}
	if !got.Business.Complete {
		t.Errorf("사업자 정보가 훼손됐다: %+v", got.Business)
	}
	if got.Facility.ReportStatus != domain.FacilityStatusReported {
		t.Errorf("시설 선언이 훼손됐다: %+v", got.Facility)
	}

	list, err := s.ListCenters(ctx, superadminP())
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != testCenter || list[0].Name != "라이즈 컨디셔닝" {
		t.Fatalf("ListCenters = %+v, want 운영 센터 1건 — 신원이 없으면 유령으로 걸러진다", list)
	}
}

// ---- 와이어(라우터를 태운다 — 앱·어드민이 실제로 보는 모양) ----

func TestLobbyWireContract(t *testing.T) {
	r := newTestRouter(t)

	// 신규 사용자의 /v1/me — join_request 필드 자체가 없다.
	me := getJSON(t, r, "/v1/me", "u_lobby", domain.RoleMember)
	var body map[string]any
	if err := json.Unmarshal(me.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if _, ok := body["join_request"]; ok {
		t.Errorf("요청 전 /v1/me에 join_request 키가 있다: %s", me.Body.String())
	}

	// 가입 요청 → 대기 상태가 /v1/me에 실린다.
	if rec := postJSON(t, r, "/v1/join/request", "u_lobby", domain.RoleMember,
		`{"name":"박지훈","phone":"010-3333-2222"}`); rec.Code != http.StatusOK {
		t.Fatalf("join/request = %d %s", rec.Code, rec.Body.String())
	}
	// 중복은 409 — 본문은 {error, code:"join_pending", center_id}(v2.34). 구앱은 error만 읽고,
	// 새 앱은 code로 "내 요청이 살아 있다"를 확정해 그 센터의 대기 화면으로 돌아간다.
	if rec := postJSON(t, r, "/v1/join/request", "u_lobby", domain.RoleMember,
		`{"name":"박지훈","phone":"010-3333-2222"}`); rec.Code != http.StatusConflict {
		t.Fatalf("중복 join/request = %d, want 409 (%s)", rec.Code, rec.Body.String())
	} else {
		var dup map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &dup); err != nil {
			t.Fatal(err)
		}
		assertKeySet(t, "409 join/request", dup, []string{"error", "code", "center_id"})
		if dup["code"] != codeJoinPending || dup["center_id"] != testCenter {
			t.Errorf("409 본문 = %v, want code=join_pending center_id=%s", dup, testCenter)
		}
	}

	me = getJSON(t, r, "/v1/me", "u_lobby", domain.RoleMember)
	if err := json.Unmarshal(me.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	jrRaw, ok := body["join_request"].(map[string]any)
	if !ok {
		t.Fatalf("/v1/me에 join_request가 없다: %s", me.Body.String())
	}
	if len(jrRaw) != 3 || jrRaw["status"] != store.JoinPending || jrRaw["center_id"] != testCenter {
		t.Fatalf("join_request = %v, want {status,center_id,created_at} 3키 pending", jrRaw)
	}
	if _, err := time.Parse(time.RFC3339, jrRaw["created_at"].(string)); err != nil {
		t.Errorf("created_at 파싱 불가: %v", jrRaw["created_at"])
	}

	// 큐(owner) — 1건.
	q := getJSON(t, r, "/v1/join/requests", "owner1", domain.RoleOwner)
	var queue []map[string]any
	if err := json.Unmarshal(q.Body.Bytes(), &queue); err != nil {
		t.Fatal(err)
	}
	if len(queue) != 1 {
		t.Fatalf("큐 = %v, want 1건", queue)
	}
	reqID, _ := queue[0]["id"].(string)

	// 거절 — owner만(trainer는 403), 응답의 name·phone은 빈 값.
	if rec := postJSON(t, r, "/v1/join/reject", "t1", domain.RoleTrainer,
		`{"request_id":"`+reqID+`"}`); rec.Code != http.StatusForbidden {
		t.Errorf("trainer join/reject = %d, want 403", rec.Code)
	}
	rec := postJSON(t, r, "/v1/join/reject", "owner1", domain.RoleOwner, `{"request_id":"`+reqID+`"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("join/reject = %d %s", rec.Code, rec.Body.String())
	}
	var rejected map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &rejected); err != nil {
		t.Fatal(err)
	}
	if rejected["status"] != store.JoinRejected || rejected["name"] != "" || rejected["phone"] != "" {
		t.Errorf("거절 응답 = %v, want status=rejected name/phone 빈 값", rejected)
	}
	// **이미 처리된 요청은 409다 — 404를 쓰지 않는다**(어드민 갈래 요구 3).
	//
	// 어드민은 이 엔드포인트의 404를 "이 배포에 아직 거절 기능이 없음"으로 접어 안내 문구를
	// 띄운다. 상태 충돌에 404를 쓰면 그 두 사건이 같은 코드로 겹쳐서, 이미 거절한 요청을 다시
	// 눌렀을 때 "거절 기능이 아직 서버에 올라가지 않았어요"가 뜬다. 404는 **없는 request_id**
	// 하나만 의미한다(스토어의 ErrNotFound — JoinApprove와 같은 매핑).
	if again := postJSON(t, r, "/v1/join/reject", "owner1", domain.RoleOwner,
		`{"request_id":"`+reqID+`"}`); again.Code != http.StatusConflict {
		t.Errorf("중복 join/reject = %d, want 409(어드민이 404를 '미배포'로 접는다)", again.Code)
	}
	if missing := postJSON(t, r, "/v1/join/reject", "owner1", domain.RoleOwner,
		`{"request_id":"jreq_does_not_exist"}`); missing.Code != http.StatusNotFound {
		t.Errorf("없는 request_id = %d, want 404 — 404의 의미는 이 하나뿐이다", missing.Code)
	}

	// 큐가 비고, 신청자에겐 결론이 도달한다.
	q = getJSON(t, r, "/v1/join/requests", "owner1", domain.RoleOwner)
	if err := json.Unmarshal(q.Body.Bytes(), &queue); err != nil {
		t.Fatal(err)
	}
	if len(queue) != 0 {
		t.Errorf("거절 후 큐 = %v, want 0건 — 대기 건수가 사실이 아니다", queue)
	}
	me = getJSON(t, r, "/v1/me", "u_lobby", domain.RoleMember)
	if err := json.Unmarshal(me.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if jr, _ := body["join_request"].(map[string]any); jr["status"] != store.JoinRejected {
		t.Errorf("거절 후 /v1/me join_request = %v, want rejected", body["join_request"])
	}
}

// PUT /v1/center의 세 덩어리 — 경로 등록 + 상태코드 + 응답 모양(GET /v1/center과 같은 모양).
func TestCenterIdentityWireContract(t *testing.T) {
	r := newTestRouter(t)

	// 빈 바디는 400(어느 덩어리도 없다).
	if rec := putJSON(t, r, "/v1/center", "owner1", domain.RoleOwner, `{}`); rec.Code != http.StatusBadRequest {
		t.Errorf("빈 PUT = %d, want 400", rec.Code)
	}
	if rec := putJSON(t, r, "/v1/center", "t1", domain.RoleTrainer,
		`{"center":{"name":"탈취"}}`); rec.Code != http.StatusForbidden {
		t.Errorf("trainer PUT center = %d, want 403", rec.Code)
	}
	// 봉인 필드는 400.
	if rec := putJSON(t, r, "/v1/center", "owner1", domain.RoleOwner,
		`{"center":{"id":"gangnam-2","name":"탈취"}}`); rec.Code != http.StatusBadRequest {
		t.Errorf("center.id PUT = %d, want 400", rec.Code)
	}

	rec := putJSON(t, r, "/v1/center", "owner1", domain.RoleOwner,
		`{"center":{"name":"라이즈 컨디셔닝","phone":"02-555-1234","address":"서울 강남구 …"},"policy":{"open_hour":6}}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("PUT = %d %s", rec.Code, rec.Body.String())
	}
	var res map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatal(err)
	}
	// 응답은 GET /v1/center과 같은 모양이어야 한다(클라이언트가 캐시를 그대로 갈아끼운다).
	if res["name"] != "라이즈 컨디셔닝" {
		t.Errorf("응답 name = %v — center 덩어리가 응답에 반영되지 않았다: %s", res["name"], rec.Body.String())
	}
	if pol, _ := res["policy"].(map[string]any); pol["open_hour"] != float64(6) {
		t.Errorf("응답 policy = %v — 같은 요청의 policy 덩어리가 반영되지 않았다", res["policy"])
	}
	for _, key := range []string{"center_id", "name", "center", "policy", "business", "facility"} {
		if _, ok := res[key]; !ok {
			t.Errorf("응답에 %q 키가 없다 — GET /v1/center과 모양이 달라졌다", key)
		}
	}

	// **center 블록으로 전화·주소를 되읽을 수 있어야 한다.** 종전엔 상호만 top-level name으로
	// 나가서 저장한 전화·주소를 읽을 경로가 없었다 — 어드민이 저장 후 새로고침하면 그 두 칸이
	// 빈 폼으로 돌아온다(어드민 갈래 요구 1).
	assertIdentity := func(what string, raw any) {
		t.Helper()
		blk, ok := raw.(map[string]any)
		if !ok {
			t.Fatalf("%s center 블록이 없다: %v", what, raw)
		}
		if len(blk) != 3 {
			t.Errorf("%s center 키 %d개 %v, want 3(name/phone/address) — 요청 키 집합과 같아야 한다", what, len(blk), blk)
		}
		if blk["name"] != "라이즈 컨디셔닝" || blk["phone"] != "02-555-1234" || blk["address"] != "서울 강남구 …" {
			t.Errorf("%s center = %v", what, blk)
		}
	}
	assertIdentity("PUT 응답", res["center"])

	// 회원도 상호를 읽는다(앱이 빌드 상수 대신 이 값을 쓴다).
	got := getJSON(t, r, "/v1/center", "u_lobby", domain.RoleMember)
	if err := json.Unmarshal(got.Body.Bytes(), &res); err != nil {
		t.Fatal(err)
	}
	if res["name"] != "라이즈 컨디셔닝" {
		t.Errorf("회원 GET /v1/center name = %v", res["name"])
	}
	assertIdentity("회원 GET", res["center"])

	// **center만 실린 바디가 정상 경로다**(어드민 갈래 요구 2) — 어드민의 센터 정보 폼은
	// policy·business와 따로 저장한다. 정책 저장이 함께 오지 않았다고 400이면 그 폼이 못 쓴다.
	only := putJSON(t, r, "/v1/center", "owner1", domain.RoleOwner,
		`{"center":{"phone":"02-555-9999"}}`)
	if only.Code != http.StatusOK {
		t.Fatalf("center만 실린 PUT = %d %s, want 200", only.Code, only.Body.String())
	}
	if err := json.Unmarshal(only.Body.Bytes(), &res); err != nil {
		t.Fatal(err)
	}
	blk, _ := res["center"].(map[string]any)
	if blk["phone"] != "02-555-9999" || blk["name"] != "라이즈 컨디셔닝" {
		t.Errorf("center 단독 PUT 결과 = %v — 부분 갱신이 다른 칸을 지웠다", blk)
	}
	// 정책이 같은 요청에 없어도 훼손되지 않는다.
	if pol, _ := res["policy"].(map[string]any); pol["open_hour"] != float64(6) {
		t.Errorf("center 단독 PUT이 정책을 훼손했다: %v", res["policy"])
	}
}

// ---- A5(v2.28): 승인도 거절과 동형으로 이름·번호를 비운다 ----

// **뮤테이션 표적**: JoinApprove의 `jr.Name = "" / jr.Phone = ""`를 지우면 여기서 죽는다.
// 비우기를 SaveMember **앞**으로 옮겨도 죽는다(회원 레코드의 이름이 빈 값이 된다).
func TestJoinApproveClearsNameAndPhone(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	applicant := Principal{UID: "u_approve", Role: domain.RoleMember, CenterID: testCenter}
	jr, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{Name: "최유진", Phone: "010-4444-5555"})
	if err != nil {
		t.Fatal(err)
	}
	if jr.Name == "" || jr.Phone == "" {
		t.Fatalf("처리 전 요청 = %+v — 대표가 큐에서 누구인지 봐야 하므로 처리 전엔 남아 있어야 한다", jr)
	}

	mem, err := s.JoinApprove(ctx, ownerP(), jr.ID)
	if err != nil {
		t.Fatalf("승인 = %v", err)
	}
	// 이름·번호는 회원 레코드로 **옮겨졌다** — 그것이 승인의 뜻이다.
	if mem.Name != jr.Name || mem.Phone != jr.Phone {
		t.Fatalf("회원 레코드 name=%q phone=%q, want %q/%q — 비우기가 SaveMember보다 앞섰다", mem.Name, mem.Phone, jr.Name, jr.Phone)
	}

	saved, err := s.store.GetJoinRequest(ctx, jr.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Name != "" || saved.Phone != "" {
		t.Errorf("승인 후 요청 문서 name=%q phone=%q — 회원 레코드로 굳은 뒤에도 아무도 읽지 않는 최상위 문서에 "+
			"영구 잔류한다(P53 '가장 오래 남는 개인정보'). 3줄 옆 JoinReject는 같은 상황에서 둘 다 비운다", saved.Name, saved.Phone)
	}
	// 감사 추적은 남는다 — {uid, center_id, status=approved, created_at}.
	if saved.Status != store.JoinApproved || saved.UID != "u_approve" || saved.CenterID != testCenter || saved.CreatedAt.IsZero() {
		t.Errorf("남은 문서 = %+v, want {uid, center_id, status=approved, created_at} 온전", saved)
	}
	// 신청자에겐 결론이 여전히 도달한다(/v1/me는 status·created_at만 읽는다).
	me := s.Me(ctx, applicant)
	if me.JoinRequest == nil || me.JoinRequest.Status != store.JoinApproved {
		t.Errorf("승인 후 /v1/me join_request = %+v, want approved — 비우기가 결론 전달을 깨뜨렸다", me.JoinRequest)
	}
}
