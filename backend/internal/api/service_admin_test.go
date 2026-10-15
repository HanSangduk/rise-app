package api

// 관리 평면(멀티센터 Phase A) — superadmin 전용 API 테스트.

import (
	"context"
	"errors"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

func superadminP() Principal {
	// CenterID가 빈 값인 것이 규약이다(소속 없음) — 운영에선 UserIndex center_id=""가 만든다.
	return Principal{UID: "sa1", Role: domain.RoleSuperadmin, CenterID: ""}
}

func validCenterCreate() CenterCreate {
	return CenterCreate{
		ID: "gangnam-2", Name: "라이즈 강남 2호점", Phone: "02-555-0000", Address: "서울 강남구",
		Owner: domain.StaffCreate{Name: "김센터장", Email: "owner@gangnam2.kr"},
	}
}

func TestCreateCenter(t *testing.T) {
	t.Run("superadmin이 센터+기본 정책+최초 owner를 한 번에 만든다", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()

		res, err := s.CreateCenter(ctx, superadminP(), validCenterCreate())
		if err != nil {
			t.Fatal(err)
		}
		if res.Center.ID != "gangnam-2" || res.Center.Name != "라이즈 강남 2호점" {
			t.Fatalf("center = %+v", res.Center)
		}
		// owner 강제 — 요청이 role을 비워도(trainer를 보내도) 첫 스태프는 owner다.
		if res.Owner.Role != domain.RoleOwner || res.Owner.Status != domain.StaffStatusActive {
			t.Fatalf("owner = %+v", res.Owner)
		}
		// 정책이 기본값으로 심겼다 — 센터 문서를 먼저 Set했다면 지연 시딩이 죽어 제로 정책
		// (용량 0)이 됐을 자리(사전조사 CRITICAL).
		pol, err := s.store.GetPolicy(ctx, "gangnam-2")
		if err != nil {
			t.Fatal(err)
		}
		if pol.SlotCapacity != domain.DefaultPolicy().SlotCapacity {
			t.Fatalf("policy = %+v, want 기본값", pol)
		}
		// UserIndex가 새 센터를 가리킨다.
		idx, err := s.store.GetUserIndex(ctx, res.Owner.UID)
		if err != nil {
			t.Fatal(err)
		}
		if idx.CenterID != "gangnam-2" || idx.Role != domain.RoleOwner {
			t.Fatalf("user index = %+v", idx)
		}
		// 새 센터의 owner로 로그인하면 자기 센터 스태프 목록이 보인다(스코프 격리 확인).
		newOwner := Principal{UID: res.Owner.UID, Role: domain.RoleOwner, CenterID: "gangnam-2"}
		staff, err := s.ListStaff(ctx, newOwner)
		if err != nil {
			t.Fatal(err)
		}
		if len(staff) != 1 || staff[0].UID != res.Owner.UID {
			t.Fatalf("새 센터 스태프 = %+v", staff)
		}
	})

	t.Run("superadmin 아니면 전부 403 — owner도 센터를 만들 수 없다", func(t *testing.T) {
		s := newTestService()
		for name, p := range map[string]Principal{
			"owner": ownerP(), "trainer": trainerP(), "member": memberP("m1"),
		} {
			if _, err := s.CreateCenter(context.Background(), p, validCenterCreate()); !errors.Is(err, ErrForbidden) {
				t.Errorf("%s: err = %v, want ErrForbidden", name, err)
			}
		}
	})

	t.Run("이름이 다른 기존 센터 ID는 409 — 같은 요청 재호출(복구)은 통과", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()
		if _, err := s.CreateCenter(ctx, superadminP(), validCenterCreate()); err != nil {
			t.Fatal(err)
		}
		// 같은 요청 재호출 — 부분 실패 복구 경로라 멱등으로 이어진다.
		if _, err := s.CreateCenter(ctx, superadminP(), validCenterCreate()); err != nil {
			t.Fatalf("같은 요청 재호출 = %v, want 성공(복구 멱등)", err)
		}
		// 다른 이름으로 같은 ID — 실수로 남의 센터를 덮는 요청이다.
		req := validCenterCreate()
		req.Name = "다른 센터"
		req.Owner.Email = "other@x.kr"
		if _, err := s.CreateCenter(ctx, superadminP(), req); !errors.Is(err, ErrConflict) {
			t.Fatalf("err = %v, want ErrConflict", err)
		}
	})

	t.Run("입력 검증 — 슬러그 아닌 ID·빈 이름·owner 이메일 형식은 400", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()
		// 대문자 ID는 여기 없다 — Normalize가 소문자로 접는다(이메일 소문자 접기와 같은 규약).
		for name, mutate := range map[string]func(*CenterCreate){
			"한글 ID":       func(c *CenterCreate) { c.ID = "강남2호점" },
			"언더스코어 ID":    func(c *CenterCreate) { c.ID = "gang_nam" },
			"공백 ID":       func(c *CenterCreate) { c.ID = "gang nam" },
			"한 글자 ID":     func(c *CenterCreate) { c.ID = "g" },
			"빈 센터 이름":     func(c *CenterCreate) { c.Name = "  " },
			"owner 이름 빈값": func(c *CenterCreate) { c.Owner.Name = "" },
		} {
			req := validCenterCreate()
			mutate(&req)
			if _, err := s.CreateCenter(ctx, superadminP(), req); err == nil {
				t.Errorf("%s: 통과했다, want 검증 에러", name)
			}
		}
	})

	t.Run("다른 센터에 연결된 이메일로 owner를 앉히면 409 — 원래 센터 접근이 덮이지 않는다", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()
		// rise 센터의 owner 계정을 먼저 만든다(운영과 같은 경로 — CreateStaff).
		made, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
			Name: "기존대표", Email: "boss@rise.kr", Role: domain.RoleOwner,
		})
		if err != nil {
			t.Fatal(err)
		}
		req := validCenterCreate()
		req.Owner.Email = "boss@rise.kr" // 같은 이메일 → EnsureUser가 같은 uid를 재사용한다
		if _, err := s.CreateCenter(ctx, superadminP(), req); !errors.Is(err, ErrConflict) {
			t.Fatalf("err = %v, want ErrConflict(교차 센터 가드)", err)
		}
		// 원래 센터 인덱스가 그대로다 — 이 가드가 없으면 여기서 "gangnam-2"로 덮여 있다.
		idx, err := s.store.GetUserIndex(ctx, made.UID)
		if err != nil {
			t.Fatal(err)
		}
		if idx.CenterID != testCenter {
			t.Fatalf("기존 owner의 센터 = %q, want %q (인덱스가 덮였다)", idx.CenterID, testCenter)
		}
	})
}

func TestListCenters(t *testing.T) {
	// v2.35: 기본 센터는 상호가 없어도 **항상 맨 앞**에 오른다. v2.16~v2.34는 name==""를 유령으로
	// 걸러 운영 중인 1호점이 관리 평면에서 사라졌었다(P70).
	t.Run("superadmin 전용 + 기본 센터(상호 미등록) ∪ 신원 등록 센터", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()
		// rise는 정책만 지연 시딩된 상태(신원 미등록 — 기존 운영 센터의 실상).
		if _, err := s.store.GetPolicy(ctx, testCenter); err != nil {
			t.Fatal(err)
		}
		if _, err := s.CreateCenter(ctx, superadminP(), validCenterCreate()); err != nil {
			t.Fatal(err)
		}

		list, err := s.ListCenters(ctx, superadminP())
		if err != nil {
			t.Fatal(err)
		}
		if len(list) != 2 || list[0].ID != testCenter || list[1].ID != "gangnam-2" {
			t.Fatalf("list = %+v, want [rise(기본, 상호 미등록), gangnam-2]", list)
		}
		if list[0].Name != "" || list[0].Status != domain.CenterStatusActive {
			t.Fatalf("기본 센터 항목 = %+v, want name=\"\" status=active(빈 채로 내보내고 화면이 미등록으로 그린다)", list[0])
		}

		if _, err := s.ListCenters(ctx, ownerP()); !errors.Is(err, ErrForbidden) {
			t.Fatalf("owner ListCenters = %v, want ErrForbidden", err)
		}
	})

	t.Run("기본 센터가 상호를 등록해도 한 번만 오른다", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()
		if _, err := s.UpdateCenterIdentity(ctx, ownerP(), []byte(`{"name":"라이즈 컨디셔닝"}`)); err != nil {
			t.Fatal(err)
		}
		if _, err := s.CreateCenter(ctx, superadminP(), validCenterCreate()); err != nil {
			t.Fatal(err)
		}
		list, err := s.ListCenters(ctx, superadminP())
		if err != nil {
			t.Fatal(err)
		}
		if len(list) != 2 || list[0].ID != testCenter || list[0].Name != "라이즈 컨디셔닝" || list[1].ID != "gangnam-2" {
			t.Fatalf("list = %+v, want [rise(상호 등록), gangnam-2] — 중복 없음", list)
		}
	})

	t.Run("기본 센터 외의 상호 미등록 문서는 여전히 유령으로 제외", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()
		if _, err := s.store.GetPolicy(ctx, "ghost-1"); err != nil { // 헬스체크·오타가 만드는 정책-only 문서
			t.Fatal(err)
		}
		list, err := s.ListCenters(ctx, superadminP())
		if err != nil {
			t.Fatal(err)
		}
		if len(list) != 1 || list[0].ID != testCenter {
			t.Fatalf("list = %+v, want [rise]만(ghost-1 제외)", list)
		}
	})
}

func TestCreateStaffCrossCenterGuard(t *testing.T) {
	t.Run("다른 센터에 연결된 이메일 초대는 409(Phase A — 멀티센터에서 인덱스 덮임 방지)", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()
		// 다른 센터(gangnam-2)에 owner를 만들어 둔다.
		if _, err := s.CreateCenter(ctx, superadminP(), validCenterCreate()); err != nil {
			t.Fatal(err)
		}
		// rise 센터 owner가 같은 이메일을 트레이너로 초대 — 종전엔 이 인덱스가 rise로 덮였다.
		_, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{
			Name: "겸직시도", Email: "owner@gangnam2.kr", Role: domain.RoleTrainer,
		})
		if !errors.Is(err, ErrConflict) {
			t.Fatalf("err = %v, want ErrConflict", err)
		}
	})
}

func TestSuperadminPathBoundary(t *testing.T) {
	// 미들웨어 관문(superadminAllowedPath) — 센터 스코프 API에 superadmin이 들어가지 못한다.
	for path, want := range map[string]bool{
		"/v1/admin/centers":     true,
		"/api/v1/admin/centers": true,
		"/v1/me":                true,
		"/api/v1/me":            true,
		"/v1/center":            false, // CenterID=""로 store를 때리는 500 표면(사전조사 MEDIUM)
		"/v1/members":           false,
		"/v1/staff":             false,
		"/v1/payments":          false,
		// v2.37(P73) — 경로 파라미터 값이 우연히 판정 문자열을 만드는 경우. 종전 부분일치
		// 판정(Contains "/admin/" · HasSuffix "/me")은 아래 넷을 전부 통과시켰다.
		"/v1/inbody/me":               false, // DELETE /v1/inbody/{id}, id=me
		"/v1/body-photos/me":          false, // DELETE /v1/body-photos/{id}, id=me
		"/v1/bookings/admin/complete": false, // POST /v1/bookings/{id}/complete, id=admin
		"/api/v1/staff/admin/photo":   false, // POST /v1/staff/{uid}/photo, uid=admin
		"/v1/me/":                     false, // 정확한 형태만 — 라우터도 이 경로를 모른다
		"/v1/admin":                   false, // 관리 평면은 하위 경로뿐(라우터에 /admin 단독 라우트 없음)
	} {
		if got := superadminAllowedPath(path); got != want {
			t.Errorf("superadminAllowedPath(%q) = %v, want %v", path, got, want)
		}
	}
}
