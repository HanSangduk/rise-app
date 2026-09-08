package api

import (
	"context"
	"errors"
	"sort"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// 회원-센터 연결의 **센터 차원**(멀티센터 Phase C, 계약 v2.32).
//
// # 무엇이 고장나 있었나
//
// 가입 매칭(`JoinMatch`)과 확인(`JoinConfirm`)은 `p.CenterID`로 회원을 찾았다. 그런데 앱을
// 처음 켠 사람은 `UserIndex`가 없어서 `auth.enrich`가 **`cfg.DefaultCenterID`("rise")를 꽂아
// 준다**. 즉 2호점 데스크가 회원을 등록해도 그 회원의 앱은 **라이즈에서만** 자기를 찾았고,
// 영원히 "아직 연결된 센터가 없어요"에 갇혔다. 센터를 늘리는 순간 신규 회원 연결이 통째로
// 죽는, 멀티센터의 첫 번째 차단 결함이다.
//
// # 무엇으로 고쳤나 — 번호가 센터를 정한다
//
// 회원이 센터를 **고르지 않는다**(설계04 §4: PT는 데스크 상담 → 등록 → 앱 연결 순서라
// 회원이 센터를 고르는 순간이 현실에 없다). 대신 **센터가 등록해 둔 전화번호**가 센터를
// 가리킨다. 그래서 여기서는 `p.CenterID`를 아예 쓰지 않고, 검증된 번호로 전 센터를 훑는다.
//
// 안전한 이유는 **번호가 Firebase가 검증한 본인 번호**이기 때문이다(`joinPhone` — 운영에서는
// `p.Phone`만 쓰고 바디 번호는 거부한다). 남의 번호로는 애초에 조회가 시작되지 않으므로
// 교차 센터 조회가 열람 표면을 넓히지 않는다. 클라이언트가 센터를 지정하던 구멍은 P41이
// 봉인했고(가입 요청 바디의 center_id), 이 경로도 같은 규율을 지킨다 — **센터는 언제나
// 서버가 정한다.**
//
// # 비용
//
// 센터 수만큼 `FindMemberByPhone`을 돈다. 가입 연결은 회원당 평생 몇 번뿐이라 v1 규모
// (센터 한 자릿수)에서는 무시할 수 있다. 센터가 수십 개가 되면 Firestore 컬렉션 그룹 쿼리로
// 한 번에 찾는 것이 다음 단계다(그때는 `phone_norm` 인덱스가 필요하다).

// memberCenterMatch — 번호가 가리킨 (센터, 회원) 한 쌍.
type memberCenterMatch struct {
	CenterID string
	Member   *domain.Member
}

// errMemberInMultipleCenters — 살아 있는 같은 번호가 두 센터 이상에 있다.
//
// **고르지 않고 막는다.** `UserIndex`는 uid당 센터 1건이라(설계03의 memberships[]는 Phase D)
// 여기서 한쪽을 고르면 그 선택이 그대로 굳고, 회원은 자기가 다니지 않는 센터의 회원권·예약을
// 보게 된다. 조용히 틀리느니 사람에게 넘긴다 — 실제로 이 상황을 풀 수 있는 건 데스크뿐이다.
var errMemberInMultipleCenters = errors.New("여러 센터에 등록된 번호예요 — 다니시는 센터 데스크에 문의해주세요")

// joinCenterIDs — 번호를 찾아볼 센터 전부. **정렬된 중복 없는 목록**이라 결과가 결정적이다.
//
// `ListCenters`만 쓰면 안 된다: 그 메서드는 **센터 신원(`center.name`)이 등록된 문서만**
// 돌려준다(유령 문서 거르기 — GetPolicy 지연 시딩이 만드는 빈 껍데기). 그런데 **1호 고객
// 라이즈가 정확히 그 상태다** — 상호 미등록이라 목록에 없다(backend/README.md의 "기존 rise
// 센터는 신원 미등록 상태로도 종전과 동일하게 동작한다", 2026-09-06 프로덕션 실측:
// `GET /v1/public/center` → `{"name":"", ...}`). 목록만 믿었으면 이 수정이 **기존 라이즈
// 회원 전원의 연결을 끊는** 정반대의 사고가 됐다. 그래서 기본 센터를 항상 먼저 넣는다.
func (s *Service) joinCenterIDs(ctx context.Context) ([]string, error) {
	seen := map[string]bool{}
	ids := make([]string, 0, 4)
	add := func(id string) {
		if id == "" || seen[id] {
			return
		}
		seen[id] = true
		ids = append(ids, id)
	}
	add(s.cfg.DefaultCenterID)

	centers, err := s.store.ListCenters(ctx)
	if err != nil {
		return nil, err
	}
	for _, c := range centers {
		add(c.ID)
	}
	sort.Strings(ids)
	return ids, nil
}

// resolveMemberByPhone — 검증된 번호로 회원이 등록된 센터를 찾는다.
//
// 반환 규약:
//   - 살아 있는 회원 1건 → 그 (센터, 회원).
//   - 살아 있는 회원 2건 이상 → [ErrConflict] + [errMemberInMultipleCenters].
//   - 살아 있는 회원 0건 + 탈퇴 회원 1건 이상 → **탈퇴 회원을 돌려준다**(센터 ID 오름차순 첫 건).
//     호출부가 "탈퇴한 회원이에요 — 새로 가입 요청을 해주세요"로 안내하던 종전 동선을
//     그대로 살리기 위해서다. 여기서 [store.ErrNotFound]로 접으면 그 안내가 사라지고
//     회원은 이유를 모른 채 미연결 화면에 선다.
//   - 아무것도 없음 → [store.ErrNotFound].
func (s *Service) resolveMemberByPhone(ctx context.Context, phone string) (*memberCenterMatch, error) {
	ids, err := s.joinCenterIDs(ctx)
	if err != nil {
		return nil, err
	}

	var live, withdrawn []memberCenterMatch
	for _, id := range ids {
		mem, err := s.store.FindMemberByPhone(ctx, id, phone)
		if err != nil {
			if errors.Is(err, store.ErrNotFound) {
				continue
			}
			return nil, err
		}
		match := memberCenterMatch{CenterID: id, Member: mem}
		if mem.IsWithdrawn() {
			withdrawn = append(withdrawn, match)
			continue
		}
		live = append(live, match)
	}

	switch {
	case len(live) == 1:
		return &live[0], nil
	case len(live) > 1:
		return nil, errors.Join(ErrConflict, errMemberInMultipleCenters)
	case len(withdrawn) > 0:
		return &withdrawn[0], nil
	}
	return nil, store.ErrNotFound
}

// joinCenterView — 매칭된 센터의 신원. 앱 대기실이 "어느 센터에 등록돼 있는지"를 말할 수 있게
// 매칭 응답에 함께 싣는다(계약 v2.32).
//
// **조회 실패를 에러로 올리지 않는다.** 센터 상호는 표시용이고, 그것 하나 때문에 연결 자체가
// 막히면 안 된다 — 라이즈처럼 상호가 미등록인 센터도 연결은 되어야 한다(그때는 빈 값이 가고
// 앱이 자기 폴백 문구를 쓴다).
func (s *Service) joinCenterView(ctx context.Context, centerID string) *CenterIdentityView {
	c, err := s.store.GetCenter(ctx, centerID)
	if err != nil || c == nil {
		return nil
	}
	v := centerIdentityView(*c)
	// **상호가 없으면 통째로 생략한다.** `GetCenter`는 미등록 센터에 ErrNotFound가 아니라
	// 빈 값을 준다(계약 규약). 그대로 실으면 `{"name":"","phone":"","address":""}`가 나가고,
	// 클라이언트는 "센터를 받았다"고 판단해 빈 문자열을 화면에 그린다 — 필드 부재와 빈 값이
	// 같은 뜻이 아니게 되는 흔한 사고다. 없으면 없다고 말한다(omitempty).
	if v.Name == "" {
		return nil
	}
	return &v
}
