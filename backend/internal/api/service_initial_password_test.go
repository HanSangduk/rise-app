package api

// 계약 v2.36 — 초대 계정의 **최초 비밀번호**가 생성 응답에 실린다.
//
// 이 파일이 고정하는 사실 하나: **새로 만든 계정에만** 실린다. 그 구분이 없으면 관리자가
// 재초대 화면에서 기본 비밀번호를 읽어 상대에게 불러 주고, 상대는 (자기가 바꾼 비밀번호가
// 살아 있으므로) 원인 모른 채 로그인에 실패한다.
//
// 배경: 종전엔 서버가 아무도 모르는 난수를 걸고 어드민 프론트의 비밀번호 재설정 메일에
// 넘겼는데, **센터 생성 화면에는 그 메일을 보내는 코드가 없었다** — 새 센터 대표는 메일도
// 비밀번호도 없이 계정만 받았다(P71, 람 보고: "등록은 하는데 비밀번호가 없어서 문제").

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

// existingAccountProvisioner — "이미 있는 계정"을 흉내 낸다. dev 프로비저너는 합성 uid라
// 항상 created=true를 돌려주므로(그 자체가 규약이다) 재초대 경로는 이 스파이로만 만든다.
type existingAccountProvisioner struct{ devUserProvisioner }

func (p existingAccountProvisioner) EnsureUser(ctx context.Context, email string) (string, bool, error) {
	uid, _, err := p.devUserProvisioner.EnsureUser(ctx, email)
	return uid, false, err // 계정이 이미 있었다 — 이번 호출이 만들지 않았다
}

func TestCreateCenterCarriesInitialPassword(t *testing.T) {
	t.Run("새 계정이면 최초 비밀번호를 싣는다", func(t *testing.T) {
		s := newTestService()
		out, err := s.CreateCenter(context.Background(), superadminP(), validCenterCreate())
		if err != nil {
			t.Fatal(err)
		}
		if out.InitialPassword != testInitialPassword {
			t.Fatalf("initial_password = %q, want %q — 이게 비면 대표는 로그인할 방법이 없다",
				out.InitialPassword, testInitialPassword)
		}
	})

	t.Run("이미 있던 계정이면 비운다", func(t *testing.T) {
		s := newTestService()
		s.users = existingAccountProvisioner{}
		out, err := s.CreateCenter(context.Background(), superadminP(), validCenterCreate())
		if err != nil {
			t.Fatal(err)
		}
		if out.InitialPassword != "" {
			t.Fatalf("initial_password = %q, want \"\" — 그 사람이 이미 정한 비밀번호가 살아 있다",
				out.InitialPassword)
		}
	})

	// 응답 모양은 종전 그대로여야 한다(키 하나만 늘었다). initial_password는 omitempty라
	// 재초대 응답에서는 키 자체가 사라진다 — 화면이 "빈 문자열"과 "없음"을 같게 읽어야 한다.
	t.Run("직렬화: 새 계정에만 키가 뜬다", func(t *testing.T) {
		s := newTestService()
		out, err := s.CreateCenter(context.Background(), superadminP(), validCenterCreate())
		if err != nil {
			t.Fatal(err)
		}
		b, err := json.Marshal(out)
		if err != nil {
			t.Fatal(err)
		}
		wire := string(b)
		for _, key := range []string{`"center"`, `"owner"`, `"initial_password"`} {
			if !strings.Contains(wire, key) {
				t.Errorf("응답에 %s가 없다: %s", key, wire)
			}
		}
	})
}

func TestCreateStaffCarriesInitialPassword(t *testing.T) {
	req := domain.StaffCreate{Name: "정혜린", Email: "hyerin@rise.kr", Role: domain.RoleTrainer}

	t.Run("새 계정이면 최초 비밀번호를 싣는다", func(t *testing.T) {
		s := newTestService()
		st, err := s.CreateStaff(context.Background(), ownerP(), req)
		if err != nil {
			t.Fatal(err)
		}
		if st.InitialPassword != testInitialPassword {
			t.Fatalf("initial_password = %q, want %q", st.InitialPassword, testInitialPassword)
		}
		// 임베딩이라 Staff 필드가 그대로 살아 있어야 한다 — 구버전 클라이언트 파싱 보호.
		if st.Staff == nil || st.Name != "정혜린" || st.Role != domain.RoleTrainer {
			t.Fatalf("Staff 본문이 유실됐다: %+v", st)
		}
	})

	t.Run("이미 있던 계정이면 비운다", func(t *testing.T) {
		s := newTestService()
		s.users = existingAccountProvisioner{}
		st, err := s.CreateStaff(context.Background(), ownerP(), req)
		if err != nil {
			t.Fatal(err)
		}
		if st.InitialPassword != "" {
			t.Fatalf("initial_password = %q, want \"\"", st.InitialPassword)
		}
	})

	// 와이어 모양 회귀: Staff 필드는 **최상위 평면**이어야 한다(임베딩). {"staff":{...}}로
	// 바뀌면 어드민의 기존 파싱이 통째로 깨진다.
	t.Run("직렬화: Staff 필드가 최상위에 평평하게 온다", func(t *testing.T) {
		s := newTestService()
		st, err := s.CreateStaff(context.Background(), ownerP(), req)
		if err != nil {
			t.Fatal(err)
		}
		b, err := json.Marshal(st)
		if err != nil {
			t.Fatal(err)
		}
		var m map[string]any
		if err := json.Unmarshal(b, &m); err != nil {
			t.Fatal(err)
		}
		for _, key := range []string{"uid", "role", "name", "color", "payout", "offdays", "status", "initial_password"} {
			if _, ok := m[key]; !ok {
				t.Errorf("최상위 키 %q가 없다: %s", key, string(b))
			}
		}
		if _, nested := m["staff"]; nested {
			t.Errorf(`"staff" 중첩이 생겼다 — 임베딩이 풀렸다: %s`, string(b))
		}
	})
}
