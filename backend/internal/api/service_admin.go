package api

// 관리 평면(멀티센터 Phase A, 설계04) — superadmin 전용 API.
//
// 일상 운영 API와 분리된 파일에 두는 이유: 이 파일의 모든 메서드는 **IsSuperadmin() 가드로
// 시작**해야 하고, p.CenterID를 절대 쓰지 않는다(superadmin은 센터 소속이 없다 — 대상 센터는
// 항상 요청 본문·경로로 명시된다). 센터 스코프 메서드와 섞이면 이 불변식이 눈에 안 보인다.

import (
	"context"
	"errors"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// CenterCreate — POST /v1/admin/centers 요청. 센터 신원 + 최초 owner 초대를 한 요청으로 묶는다
// (owner 없는 센터는 아무도 못 들어가는 빈 방이라, 따로 만들 이유가 없다).
type CenterCreate struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Phone   string `json:"phone"`
	Address string `json:"address"`
	// Owner — 최초 센터장. role은 클라이언트가 뭘 보내든 서버가 owner로 강제한다.
	Owner domain.StaffCreate `json:"owner"`
}

// CenterCreated — 생성 결과. 임시 비밀번호는 담기지 않는다(CreateStaff와 같은 규약 —
// 초대 메일은 어드민 프론트가 sendPasswordResetEmail로 보낸다).
type CenterCreated struct {
	Center domain.Center `json:"center"`
	Owner  *domain.Staff `json:"owner"`
}

// CreateCenter — POST /v1/admin/centers(superadmin 전용). 세 조각을 순서대로 만든다:
// ① 정책 기본값(GetPolicy 지연 시딩 재사용) ② 센터 신원 ③ 최초 owner(계정+인덱스+레코드).
//
// 순서가 복구 가능성을 가른다(CreateStaff의 쓰기 순서 규약과 같은 원리): 어느 단계에서
// 실패해도 같은 요청을 재호출하면 이어서 완성된다 — ①·②는 멱등이고, ③은 EnsureUser가
// uid를 재사용한다.
//
// ①을 SaveCenter보다 **먼저** 부르는 이유(사전조사 CRITICAL): GetPolicy의 기본값 시딩은
// 문서 NotFound에서만 발동한다. 센터 신원을 먼저 Set하면 문서가 "존재"하게 되어 정책이
// 영원히 제로값(용량 0·컷오프 0)으로 남는다. GetPolicy를 먼저 부르면 새 센터엔 기본값이
// 심기고, 이미 정책이 있던 센터(rise처럼 지연 시딩된)는 그대로 보존된다.
func (s *Service) CreateCenter(ctx context.Context, p Principal, req CenterCreate) (*CenterCreated, error) {
	if !p.IsSuperadmin() {
		return nil, ErrForbidden
	}
	center := domain.Center{
		ID: req.ID, Name: req.Name, Phone: req.Phone, Address: req.Address,
		Status: domain.CenterStatusActive, CreatedAt: time.Now().UTC(),
	}
	center.Normalize()
	if err := center.Validate(); err != nil {
		return nil, err
	}
	owner := req.Owner
	owner.Role = domain.RoleOwner // 강제 — 최초 스태프가 trainer면 그 센터는 관리자 없는 방이 된다
	owner.Normalize()
	if err := owner.Validate(); err != nil {
		return nil, err
	}
	// 이름 있는 센터가 이미 있으면 409 — 재호출 복구(아래)와 "실수로 같은 ID에 덮어쓰기"를
	// 가르는 기준은 신원 등록 여부다. 정책만 있는 유령 문서(지연 시딩 산물)는 새 센터로 취급.
	if existing, err := s.store.GetCenter(ctx, center.ID); err != nil {
		return nil, err
	} else if existing.Name != "" && existing.Name != center.Name {
		return nil, errors.Join(ErrConflict, errors.New("이미 사용 중인 센터 ID예요"))
	}

	// ① 정책 확보(기본값 시딩 또는 기존 보존) — 반드시 센터 신원 저장 전에.
	if _, err := s.store.GetPolicy(ctx, center.ID); err != nil {
		return nil, err
	}
	// ② 센터 신원.
	if err := s.store.SaveCenter(ctx, &center); err != nil {
		return nil, err
	}
	// ③ 최초 owner — 계정 확보 → 교차 센터 가드 → 인덱스 → 레코드(CreateStaff 순서 규약).
	st, err := s.createFirstOwner(ctx, center.ID, owner)
	if err != nil {
		return nil, err
	}
	return &CenterCreated{Center: center, Owner: st}, nil
}

// createFirstOwner — 새 센터의 첫 스태프. CreateStaff의 코어와 같은 순서지만 판정이 다르다:
// 새 센터라 색 배정 조회·재고용 분기가 없고, 대신 **교차 센터 가드**가 핵심이다.
func (s *Service) createFirstOwner(ctx context.Context, centerID string, req domain.StaffCreate) (*domain.Staff, error) {
	uid, err := s.users.EnsureUser(ctx, req.Email)
	if err != nil {
		return nil, err
	}
	// 교차 센터 이메일 재사용 차단(사전조사 CRITICAL): EnsureUser는 기존 계정의 uid를
	// 재사용하는데, UserIndex는 uid당 1건이라 다른 센터에 연결된 계정을 여기 앉히면
	// **그 사람의 원래 센터 접근이 통째로 덮인다**(A센터 owner가 로그인하는 순간 B센터로
	// 떨어진다). 같은 센터 재호출(부분 실패 복구)만 통과시킨다.
	if idx, err := s.store.GetUserIndex(ctx, uid); err == nil {
		if idx.CenterID != centerID {
			return nil, errors.Join(ErrConflict,
				errors.New("이미 다른 센터에 연결된 계정이에요 — 센터마다 다른 이메일을 써주세요"))
		}
	} else if !errors.Is(err, store.ErrNotFound) {
		return nil, err
	}
	payout := domain.DefaultPayout()
	if req.Payout != nil {
		payout = *req.Payout
	}
	st := &domain.Staff{
		UID: uid, Role: req.Role, Name: req.Name,
		Color:   domain.PickStaffColor(nil), // 새 센터 — 쓰인 색이 없다
		Payout:  payout,
		Offdays: []string{},
		Status:  domain.StaffStatusActive,
	}
	st.Profile.Normalize()
	// 인덱스 먼저(CreateStaff 규약) — 인덱스만 남으면 재호출이 이어서 완성한다.
	if err := s.store.SaveUserIndex(ctx, &store.UserIndex{UID: uid, Role: req.Role, CenterID: centerID}); err != nil {
		return nil, err
	}
	if err := s.store.SaveStaff(ctx, centerID, st); err != nil {
		return nil, err
	}
	return st, nil
}

// ListCenters — GET /v1/admin/centers(superadmin 전용). 신원이 등록된 센터만(유령 문서 제외).
func (s *Service) ListCenters(ctx context.Context, p Principal) ([]domain.Center, error) {
	if !p.IsSuperadmin() {
		return nil, ErrForbidden
	}
	return s.store.ListCenters(ctx)
}
