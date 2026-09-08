package api

import (
	"context"
	"errors"
	"strings"

	"github.com/ramsang/rise-backend/internal/store"
)

// 센터 디렉터리(계약 v2.33) — **회원이 고를 수 있는 센터 목록**과, 그 목록을 신뢰 경계로 쓰는
// 두 소비자(가입 요청의 센터 선택 · 법정 문서의 `?center=`).
//
// # 왜 이제야 여는가
//
// `JoinRequestCreate`는 바디의 `center_id`를 **의도적으로 무시**해 왔고, 그 주석이 선택을 열
// 조건 셋을 미리 적어 뒀다: ① 신원 등록된 센터가 2곳 이상 ② 회원이 읽을 수 있는 목록
// 엔드포인트 ③ "그 센터가 실재하고 가입을 받는가" 검증. 이 파일이 ②와 ③이고, ①은 런타임
// 조건이라 **앱이 목록 길이로 판단한다**(2곳 미만이면 고를 것이 없으므로 선택 화면을 띄우지
// 않는다). 셋이 갖춰지기 전에 바디 값을 믿으면 종전 결함(존재하지 않는 센터로 200 → 어느
// 큐에도 안 뜨는 영원한 pending)이 그대로 돌아온다.
//
// # 신뢰 경계
//
// 클라이언트가 보낸 센터 ID는 **이 목록에 있을 때만** 통과한다. 목록은 서버가 만든다
// (`joinCenterIDs` — 기본 센터 ∪ `ListCenters`). 즉 선택은 열리되 값은 여전히 서버가 정한
// 집합 안에서만 유효하다 — P41이 봉인한 것은 "임의 문자열 신뢰"였지 "선택" 자체가 아니었다.

// CenterDirectoryEntry — 회원에게 보여줄 센터 한 곳. **가입 판단에 필요한 것만** 싣는다.
//
// 정책·사업자 정보·회원 수는 넣지 않는다: 이 응답은 전화 인증만 끝난 사람이 읽고(아직 어느
// 센터의 회원도 아니다), B2B2C에서 타 센터의 운영 수치는 남에게 보일 값이 아니다.
type CenterDirectoryEntry struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Address string `json:"address,omitempty"`
	Phone   string `json:"phone,omitempty"`
}

// JoinCenters — 가입 요청을 보낼 수 있는 센터 목록(계약 v2.33, 인증 필요).
//
// **상호가 빈 센터도 뺀 목록이 아니다.** `ListCenters`는 상호 미등록 문서를 유령으로 거르는데,
// 1호 고객(기본 센터)이 실제로 그 상태다 — 걸러 버리면 그 센터를 고를 방법이 사라져 기존
// 신규 회원의 가입 요청 경로가 통째로 막힌다. 그래서 `joinCenterIDs`(기본 센터를 항상 포함)를
// 쓰고, 이름이 빈 항목은 **빈 문자열 그대로** 내보낸다. 클라이언트가 자기 폴백 라벨로 그린다.
//
// 이름 없는 센터가 목록에 섞이는 것은 정상이 아니라 **미완 상태의 노출**이다 — 그 센터가
// 상호를 등록하면 저절로 사라진다(어드민 설정 → 센터 정보).
func (s *Service) JoinCenters(ctx context.Context, p Principal) ([]CenterDirectoryEntry, error) {
	// 인증만 요구한다(역할 무관). 이 목록을 읽는 사람은 아직 어느 센터에도 속하지 않은
	// 신규 사용자이므로 역할 게이트를 걸 대상이 없다. 무인증으로 열지 않는 이유는 반대다 —
	// 센터 목록은 이 서비스를 쓰는 사업장의 목록이라 익명 크롤링 표면으로 둘 값이 아니다.
	if p.UID == "" {
		return nil, ErrForbidden
	}
	ids, err := s.joinCenterIDs(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]CenterDirectoryEntry, 0, len(ids))
	for _, id := range ids {
		c, err := s.store.GetCenter(ctx, id)
		if err != nil {
			return nil, err
		}
		e := CenterDirectoryEntry{ID: id}
		if c != nil {
			e.Name = strings.TrimSpace(c.Name)
			e.Address = strings.TrimSpace(c.Address)
			e.Phone = strings.TrimSpace(c.Phone)
		}
		out = append(out, e)
	}
	return out, nil
}

// resolveJoinCenter — 가입 요청이 갈 센터를 정한다.
//
//   - 바디에 `center_id`가 없으면 `Principal.CenterID`(신규 uid면 기본 센터). 종전 동작 그대로라
//     구버전 앱이 그대로 동작한다.
//   - 있으면 **목록에 있는지 검증**한다. 없으면 400 — 200을 주고 어느 큐에도 안 뜨는 요청을
//     만드는 것이 종전 결함이었다.
func (s *Service) resolveJoinCenter(ctx context.Context, p Principal, requested string) (string, error) {
	requested = strings.ToLower(strings.TrimSpace(requested))
	if requested == "" {
		return p.CenterID, nil
	}
	ok, err := s.knownCenter(ctx, requested)
	if err != nil {
		return "", err
	}
	if !ok {
		return "", errors.Join(errBadRequest, errors.New("선택한 센터를 찾을 수 없어요 — 목록에서 다시 골라주세요"))
	}
	return requested, nil
}

// knownCenter — 서버가 아는 센터인가(기본 센터 ∪ 신원 등록 센터).
func (s *Service) knownCenter(ctx context.Context, id string) (bool, error) {
	ids, err := s.joinCenterIDs(ctx)
	if err != nil {
		return false, err
	}
	for _, known := range ids {
		if known == id {
			return true, nil
		}
	}
	return false, nil
}

// resolvePublicCenter — 무인증 법정 문서 endpoint(`?center=`)가 볼 센터.
//
//   - 파라미터가 없으면 기본 센터(구 URL 호환 — 배포된 문서 링크가 아직 `?center=` 없이 온다).
//   - 있는데 모르는 센터면 **404**. 기본 센터로 조용히 폴백하면 **남의 사업자 정보를 그 센터의
//     법정 고지로 인쇄한다** — 개인정보처리방침·계약서에서 그건 단순 오표기가 아니라 거짓 고지다.
//     못 찾으면 못 찾았다고 하고, 문서는 자기 자리표시자를 유지한다.
func (s *Service) resolvePublicCenter(ctx context.Context, requested string) (string, error) {
	requested = strings.ToLower(strings.TrimSpace(requested))
	if requested == "" {
		return s.cfg.DefaultCenterID, nil
	}
	ok, err := s.knownCenter(ctx, requested)
	if err != nil {
		return "", err
	}
	if !ok {
		return "", store.ErrNotFound
	}
	return requested, nil
}
