package api

// 시설 신고 상태 선언(P42, 계약 v2.19) — PUT /v1/center/facility의 서비스 절.
//
// UpdateCenterBusiness(v2.13)와 나란한 파일이되 따로 두는 이유: Business는 법정 고지 12칸의
// **완성도**가 문서 게시를 가르고, 이쪽은 3값 **선언**이 계약서 템플릿 선택(pt-v1-reported/
// pt-v1-exempt/스킵)을 가른다 — 소비자가 다르면 절도 다르다(domain/facility.go 참고).

import (
	"context"

	"github.com/ramsang/rise-backend/internal/domain"
)

// UpdateCenterFacility — 시설 신고 상태 저장(owner 전용 — 계약서에 인쇄되는 법적 선언이라
// 정책·사업자 정보와 같은 권한 선을 쓴다. member/trainer는 403).
//
// **절 통 교체 + 문서 머지**: 폼이 늘 3칸 전부를 제출하므로 절 안에서는 통 교체(Business와
// 같은 근거 — 잘못 적은 번호를 비워서 지울 수 있어야 한다)이고, centers 문서 차원에서는
// 머지 쓰기라 Policy·Business를 건드리지 않는다(P27 SavePolicy 교훈 — 스토어 규약 + 회귀
// 테스트로 고정).
//
// reported⇒신고번호 필수는 도메인 Validate가 강제한다(400) — unknown 스킵 게이트를 번호
// 없는 "신고했음"으로 통과시키지 않기 위한 저장 게이트다.
func (s *Service) UpdateCenterFacility(ctx context.Context, p Principal, fac domain.Facility) (domain.Facility, error) {
	if !p.IsOwner() {
		return domain.Facility{}, ErrForbidden
	}
	// 검증 **전에** 정규화한다(UpdateCenterBusiness와 같은 이유 — 붙여넣기 공백으로 400이
	// 나면 무엇이 틀렸는지 눈에 보이지 않는다). 빈 report_status는 여기서 unknown으로 접힌다.
	fac.Normalize()
	if err := fac.Validate(); err != nil {
		return domain.Facility{}, err
	}
	if err := s.store.SaveFacility(ctx, p.CenterID, &fac); err != nil {
		return domain.Facility{}, err
	}
	return fac, nil
}
