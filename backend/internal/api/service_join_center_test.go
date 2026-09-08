package api

import (
	"context"
	"errors"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// 멀티센터 가입 연결(계약 v2.32) — **번호가 센터를 정한다**.
//
// 이 스위트가 지키는 것은 하나다: 앱을 처음 켠 사람의 `Principal.CenterID`는 기본 센터로
// 채워진 **의미 없는 값**이고, 회원이 실제로 속한 센터는 **센터가 등록해 둔 전화번호**가
// 가리킨다. 종전 코드는 그 무의미한 값으로 회원을 찾아 2호점 회원을 영원히 못 찾았다.

// centerOwnerP — 그 센터의 owner. 회원을 그 센터에 등록하는 데 쓴다.
func centerOwnerP(centerID string) Principal {
	return Principal{UID: "owner-" + centerID, Role: domain.RoleOwner, CenterID: centerID}
}

// lobbyP — **앱을 처음 켠 사람**. UserIndex가 없어 `auth.enrich`가 기본 센터를 꽂아 준 상태를
// 그대로 재현한다(CenterID = testCenter). 이 값이 회원의 진짜 센터와 다른 것이 요점이다.
func lobbyP(uid, phone string) Principal {
	return Principal{UID: uid, Role: domain.RoleMember, CenterID: testCenter, Phone: phone}
}

// seedMemberIn — 지정 센터에 회원 1명. 실제 경로(CreateMember)를 지나므로 저장 형태가 운영과 같다.
func seedMemberIn(t *testing.T, s *Service, centerID, name, phone string) *domain.Member {
	t.Helper()
	mem, err := s.CreateMember(context.Background(), centerOwnerP(centerID),
		&domain.Member{Name: name, Phone: phone, Status: domain.MemberStatusActive})
	if err != nil {
		t.Fatalf("seed member in %s: %v", centerID, err)
	}
	return mem
}

// seedCenter — 센터 신원을 등록한다(ListCenters에 뜨는 상태).
func seedCenter(t *testing.T, s *Service, id, name string) {
	t.Helper()
	c := &domain.Center{ID: id, Name: name, Status: domain.CenterStatusActive}
	c.Normalize()
	if err := s.store.SaveCenter(context.Background(), c); err != nil {
		t.Fatalf("seed center %s: %v", id, err)
	}
}

func TestJoinMatchFindsMemberInAnotherCenter(t *testing.T) {
	// 2호점이 데스크에서 회원을 등록했다. 그 회원이 앱을 처음 켠다.
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")
	mem := seedMemberIn(t, s, "gangnam-2", "김이호", "010-2222-0002")

	res, err := s.JoinMatch(ctx, lobbyP("u-new", "010-2222-0002"), "")
	if err != nil {
		t.Fatalf("JoinMatch = %v", err)
	}
	if !res.NeedsConfirm || res.Member == nil {
		t.Fatalf("2호점 회원을 못 찾았다 — 기본 센터에서만 조회하고 있다: %+v", res)
	}
	if res.Member.ID != mem.ID || res.Member.Name != "김이호" {
		t.Fatalf("match = %+v, want %s/김이호", res.Member, mem.ID)
	}
	// 대기실이 "라이즈"가 아니라 자기 센터를 말할 수 있어야 한다(v2.32 center 필드).
	if res.Center == nil || res.Center.Name != "라이즈 강남 2호점" {
		t.Fatalf("match.center = %+v, want 라이즈 강남 2호점 — 대기실이 남의 센터 이름을 보여준다", res.Center)
	}
}

func TestJoinConfirmLinksToTheMembersOwnCenter(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")
	mem := seedMemberIn(t, s, "gangnam-2", "김이호", "010-2222-0002")

	res, err := s.JoinConfirm(ctx, lobbyP("u-new", "010-2222-0002"),
		JoinConfirmRequest{MemberID: mem.ID, Confirm: true})
	if err != nil {
		t.Fatalf("JoinConfirm = %v", err)
	}
	if !res.Linked {
		t.Fatal("linked=false")
	}

	// **UserIndex가 2호점을 가리켜야 한다.** 기본 센터가 들어가면 그 회원은 이후 모든 조회를
	// 남의 센터에서 하게 되고(홈·예약·기록 전부 빈 화면), 그게 이 수정 이전의 동작이다.
	idx, err := s.store.GetUserIndex(ctx, "u-new")
	if err != nil {
		t.Fatal(err)
	}
	if idx.CenterID != "gangnam-2" {
		t.Fatalf("UserIndex.CenterID = %q, want gangnam-2", idx.CenterID)
	}
	if idx.MemberID != mem.ID {
		t.Fatalf("UserIndex.MemberID = %q, want %s", idx.MemberID, mem.ID)
	}

	// 회원 레코드도 **그 센터에서** app_linked가 되어야 한다.
	saved, err := s.store.GetMember(ctx, "gangnam-2", mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if !saved.AppLinked {
		t.Fatal("2호점 회원 레코드가 app_linked=false — 기본 센터에 썼다")
	}
}

// TestJoinMatchStillFindsDefaultCenterWithoutIdentity — **이 수정이 만들 수 있었던 정반대의 사고.**
//
// `ListCenters`는 상호(`center.name`)가 등록된 센터만 돌려준다. 그런데 1호 고객 라이즈가
// 정확히 그 상태다(프로덕션 실측: GET /v1/public/center → name:""). 목록만 훑었다면 이
// 변경은 **기존 회원 전원의 앱 연결을 끊었다.** 기본 센터를 항상 후보에 넣는 줄이 그것을 막는다.
func TestJoinMatchStillFindsDefaultCenterWithoutIdentity(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	// 센터 신원을 **등록하지 않는다** — 프로덕션 라이즈와 같은 상태.
	mem := seedMemberIn(t, s, testCenter, "김민지", "010-1111-0001")

	centers, err := s.store.ListCenters(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range centers {
		if c.ID == testCenter {
			t.Fatalf("전제가 깨졌다: 신원 미등록 센터가 ListCenters에 떴다(%+v) — 이 테스트의 의미가 사라진다", c)
		}
	}

	res, err := s.JoinMatch(ctx, lobbyP("u-old", "010-1111-0001"), "")
	if err != nil {
		t.Fatalf("JoinMatch = %v", err)
	}
	if !res.NeedsConfirm || res.Member == nil || res.Member.ID != mem.ID {
		t.Fatalf("기본 센터 회원을 못 찾았다 — 기존 회원 전원의 연결이 끊긴다: %+v", res)
	}
	// 상호가 없는 센터는 **center를 통째로 생략**한다 — 빈 문자열 세 칸을 보내면 클라이언트가
	// "센터를 받았다"고 판단해 빈 이름을 그린다.
	if res.Center != nil {
		t.Fatalf("match.center = %+v, want nil — 상호 미등록 센터가 빈 값을 실어 보냈다", res.Center)
	}
}

func TestJoinMatchNoMemberAnywhere(t *testing.T) {
	s := newTestService()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")
	seedMemberIn(t, s, "gangnam-2", "김이호", "010-2222-0002")

	res, err := s.JoinMatch(context.Background(), lobbyP("u-x", "010-9999-9999"), "")
	if err != nil {
		t.Fatalf("JoinMatch = %v", err)
	}
	if res.NeedsConfirm || res.Member != nil {
		t.Fatalf("등록되지 않은 번호가 매칭됐다: %+v", res)
	}
	if res.Center != nil {
		t.Fatalf("미매칭인데 센터를 말했다: %+v", res.Center)
	}
}

// TestJoinAmbiguousAcrossCenters — 같은 번호가 두 센터에 **살아 있는** 회원으로 있으면
// 고르지 않고 막는다. UserIndex가 uid당 센터 1건이라 한쪽을 고르면 그 선택이 굳고, 회원은
// 다니지 않는 센터의 회원권·예약을 보게 된다.
func TestJoinAmbiguousAcrossCenters(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")
	seedCenter(t, s, "songpa-3", "라이즈 송파 3호점")
	seedMemberIn(t, s, "gangnam-2", "김이호", "010-2222-0002")
	seedMemberIn(t, s, "songpa-3", "김이호", "010-2222-0002")

	if _, err := s.JoinMatch(ctx, lobbyP("u-dup", "010-2222-0002"), ""); !errors.Is(err, ErrConflict) {
		t.Fatalf("JoinMatch = %v, want conflict — 조용히 한쪽을 골랐다", err)
	}
	_, err := s.JoinConfirm(ctx, lobbyP("u-dup", "010-2222-0002"),
		JoinConfirmRequest{MemberID: "mem_000001", Confirm: true})
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("JoinConfirm = %v, want conflict", err)
	}
	if _, err := s.store.GetUserIndex(ctx, "u-dup"); !errors.Is(err, store.ErrNotFound) {
		t.Fatal("모호한 상태인데 연결됐다")
	}
}

// TestJoinConfirmRejectsMismatchedMemberID — 번호가 가리킨 회원과 클라이언트가 지목한
// member_id가 다르면 연결하지 않는다(서버가 고르고, 클라이언트 지목은 대조 대상이다).
func TestJoinConfirmRejectsMismatchedMemberID(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")
	seedMemberIn(t, s, "gangnam-2", "김이호", "010-2222-0002")
	other := seedMemberIn(t, s, "gangnam-2", "박삼호", "010-3333-0003")

	_, err := s.JoinConfirm(ctx, lobbyP("u-new", "010-2222-0002"),
		JoinConfirmRequest{MemberID: other.ID, Confirm: true})
	if !errors.Is(err, errBadRequest) {
		t.Fatalf("JoinConfirm = %v, want 400 — 남의 레코드에 붙었다", err)
	}
	if _, err := s.store.GetUserIndex(ctx, "u-new"); !errors.Is(err, store.ErrNotFound) {
		t.Fatal("불일치인데 연결됐다")
	}
}

// TestJoinConfirmUnknownPhoneIs400 — 번호로 아무도 못 찾으면 404가 아니라 400이다.
// (탈퇴 회원은 가명화로 번호가 비어 이 경로로 온다 — service_account_test의 "가입 재연결"과 한 규약.)
func TestJoinConfirmUnknownPhoneIs400(t *testing.T) {
	s := newTestService()
	_, err := s.JoinConfirm(context.Background(), lobbyP("u-ghost", "010-9999-9999"),
		JoinConfirmRequest{MemberID: "mem_000001", Confirm: true})
	if !errors.Is(err, errBadRequest) {
		t.Fatalf("JoinConfirm = %v, want 400", err)
	}
}

// TestJoinCenterIDsAreDeterministicAndDeduped — 후보 목록은 정렬·중복 제거된다.
// 기본 센터가 신원까지 등록돼 ListCenters에도 뜨는 상태(2호점 개설 후 라이즈가 상호를 채운 날)를
// 재현한다 — 여기서 중복이 생기면 같은 센터를 두 번 훑어 "여러 센터에 등록됨"으로 오판한다.
func TestJoinCenterIDsAreDeterministicAndDeduped(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, testCenter, "라이즈 컨디셔닝 센터")
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")

	ids, err := s.joinCenterIDs(ctx)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"gangnam-2", testCenter}
	if len(ids) != len(want) {
		t.Fatalf("joinCenterIDs = %v, want %v", ids, want)
	}
	for i := range want {
		if ids[i] != want[i] {
			t.Fatalf("joinCenterIDs = %v, want %v (정렬·중복 제거)", ids, want)
		}
	}

	// 중복 훑기가 있었다면 아래가 conflict로 죽는다.
	mem := seedMemberIn(t, s, testCenter, "김민지", "010-1111-0001")
	res, err := s.JoinMatch(ctx, lobbyP("u-dup2", "010-1111-0001"), "")
	if err != nil {
		t.Fatalf("JoinMatch = %v — 같은 센터를 두 번 훑어 모호로 오판했다", err)
	}
	if res.Member == nil || res.Member.ID != mem.ID {
		t.Fatalf("match = %+v", res.Member)
	}
}
