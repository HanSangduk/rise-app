package api

import (
	"context"
	"errors"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// 센터 디렉터리(계약 v2.33) — 회원이 고를 수 있는 목록과, 그 목록을 신뢰 경계로 쓰는 두 소비자.

func seedBusiness(t *testing.T, s *Service, centerID, bizName string) {
	t.Helper()
	b := &domain.Business{BizName: bizName, CeoName: "대표", BizRegNo: "123-45-67890"}
	if err := s.store.SaveBusiness(context.Background(), centerID, b); err != nil {
		t.Fatalf("seed business %s: %v", centerID, err)
	}
}

func TestJoinCentersListsDefaultAndNamedCenters(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")

	list, err := s.JoinCenters(ctx, lobbyP("u-new", "010-0000-0000"))
	if err != nil {
		t.Fatal(err)
	}
	// **기본 센터(상호 미등록)도 목록에 있어야 한다.** 빼면 그 센터를 고를 방법이 사라져
	// 기존 신규 회원의 가입 요청 경로가 통째로 막힌다 — ListCenters만 쓰면 정확히 그렇게 된다.
	ids := map[string]CenterDirectoryEntry{}
	for _, e := range list {
		ids[e.ID] = e
	}
	if _, ok := ids[testCenter]; !ok {
		t.Fatalf("기본 센터가 목록에 없다: %+v — 상호 미등록 센터를 고를 방법이 사라진다", list)
	}
	if ids[testCenter].Name != "" {
		t.Fatalf("기본 센터 이름 = %q, want \"\"(미등록 그대로)", ids[testCenter].Name)
	}
	g, ok := ids["gangnam-2"]
	if !ok || g.Name != "라이즈 강남 2호점" {
		t.Fatalf("2호점 항목 = %+v", g)
	}
	// 정렬은 결정적이어야 한다(화면 순서가 호출마다 바뀌면 오선택을 만든다).
	if len(list) != 2 || list[0].ID != "gangnam-2" || list[1].ID != testCenter {
		t.Fatalf("목록 순서 = %+v, want [gangnam-2, %s]", list, testCenter)
	}
}

// 익명에게는 열지 않는다 — 센터 목록은 이 서비스를 쓰는 사업장 목록이라 크롤링 표면이 된다.
func TestJoinCentersRequiresIdentity(t *testing.T) {
	s := newTestService()
	if _, err := s.JoinCenters(context.Background(), Principal{}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("무인증 = %v, want 403", err)
	}
}

// TestJoinRequestGoesToSelectedCenter — 선택한 센터의 큐로 간다. 이것이 이번 변경의 본체다.
func TestJoinRequestGoesToSelectedCenter(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")
	applicant := lobbyP("u-new", "010-7777-1111")

	jr, err := s.JoinRequestCreate(ctx, applicant, JoinRequestBody{
		CenterID: "gangnam-2", Name: "신규회원", Phone: "010-7777-1111",
	})
	if err != nil {
		t.Fatal(err)
	}
	if jr.CenterID != "gangnam-2" {
		t.Fatalf("jr.CenterID = %q, want gangnam-2 — 선택이 무시됐다", jr.CenterID)
	}

	// 2호점 대표의 큐에 뜬다.
	list, err := s.ListJoinRequests(ctx, centerOwnerP("gangnam-2"))
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != jr.ID {
		t.Fatalf("2호점 큐 = %+v, want 요청 1건", list)
	}
	// **기본 센터 대표에게는 보이지 않는다** — 종전엔 전부 여기로 왔다.
	riseList, err := s.ListJoinRequests(ctx, ownerP())
	if err != nil {
		t.Fatal(err)
	}
	if len(riseList) != 0 {
		t.Fatalf("기본 센터 큐 = %+v, want 0건 — 남의 센터 요청이 섞였다", riseList)
	}
}

// 대소문자·공백은 정규화한다 — 화면이 보낸 값이 그대로 문서 키가 되므로.
func TestJoinRequestNormalizesSelectedCenter(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")

	jr, err := s.JoinRequestCreate(ctx, lobbyP("u-n", "010-7777-2222"), JoinRequestBody{
		CenterID: "  Gangnam-2 ", Name: "신규회원", Phone: "010-7777-2222",
	})
	if err != nil {
		t.Fatal(err)
	}
	if jr.CenterID != "gangnam-2" {
		t.Fatalf("jr.CenterID = %q, want gangnam-2(정규화)", jr.CenterID)
	}
}

// ── 법정 문서의 센터 차원 ───────────────────────────────────────────────────

func TestPublicBusinessPerCenter(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점")
	seedBusiness(t, s, testCenter, "주식회사 라이즈")
	seedBusiness(t, s, "gangnam-2", "강남2 스포츠")

	got, err := s.PublicBusiness(ctx, "gangnam-2")
	if err != nil {
		t.Fatal(err)
	}
	if got.BizName != "강남2 스포츠" {
		t.Fatalf("biz_name = %q, want 강남2 스포츠 — 남의 사업자 정보를 법정 고지로 인쇄한다", got.BizName)
	}

	// 파라미터 없음 → 기본 센터(배포된 구 링크 호환).
	got, err = s.PublicBusiness(ctx, "")
	if err != nil {
		t.Fatal(err)
	}
	if got.BizName != "주식회사 라이즈" {
		t.Fatalf("기본 센터 biz_name = %q", got.BizName)
	}

	// 모르는 센터 → **404**. 기본 센터로 조용히 폴백하면 그 문서는 거짓 고지가 된다.
	if _, err := s.PublicBusiness(ctx, "없는센터"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("모르는 센터 = %v, want not found — 기본 센터로 폴백하면 거짓 고지다", err)
	}
}

func TestPublicCenterPerCenter(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	c := &domain.Center{ID: "gangnam-2", Name: "라이즈 강남 2호점", Phone: "02-555-0000", Address: "서울 강남구"}
	c.Normalize()
	if err := s.store.SaveCenter(ctx, c); err != nil {
		t.Fatal(err)
	}

	got, err := s.PublicCenter(ctx, "gangnam-2")
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "라이즈 강남 2호점" || got.Phone != "02-555-0000" {
		t.Fatalf("center = %+v", got)
	}
	if _, err := s.PublicCenter(ctx, "없는센터"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("모르는 센터 = %v, want not found", err)
	}
}

// 전화·주소 폴백도 **그 센터의** 사업자 정보에서 와야 한다(종전엔 기본 센터 고정이었다).
func TestPublicCenterFallsBackToOwnCenterBusiness(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedCenter(t, s, "gangnam-2", "라이즈 강남 2호점") // 전화·주소 없음
	if err := s.store.SaveBusiness(ctx, "gangnam-2", &domain.Business{
		BizName: "강남2 스포츠", Phone: "02-999-1234", Address: "서울 강남구 테헤란로",
	}); err != nil {
		t.Fatal(err)
	}
	if err := s.store.SaveBusiness(ctx, testCenter, &domain.Business{
		BizName: "주식회사 라이즈", Phone: "02-111-1111", Address: "서울 송파구",
	}); err != nil {
		t.Fatal(err)
	}

	got, err := s.PublicCenter(ctx, "gangnam-2")
	if err != nil {
		t.Fatal(err)
	}
	if got.Phone != "02-999-1234" || got.Address != "서울 강남구 테헤란로" {
		t.Fatalf("폴백이 기본 센터 값을 썼다: %+v", got)
	}
}
