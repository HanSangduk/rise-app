package store

import "errors"

// ErrNotFound — 조회 미존재. API 레이어가 404로 매핑한다.
var ErrNotFound = errors.New("store: not found")

// ErrStateConflict — 기대 상태가 아닌 레코드에 대한 전이 시도(예: confirmed가 아닌 예약의
// complete/noshow/cancel). 서비스 레벨 가드와 별개로 락/트랜잭션 **안에서** 재검증해
// 동시 이중 호출의 이중 차감을 막는다(P01 2R MEDIUM-5). API 레이어가 400으로 매핑한다.
var ErrStateConflict = errors.New("store: booking state conflict")

// checkDocID — **빈 문서 ID 조회는 ErrNotFound**(두 스토어 공통 규칙, order.go의 정렬 규약과
// 같은 이유로 한 곳에 둔다).
//
// Firestore에서 Collection.Doc("")는 에러 없이 빈 ID DocumentRef를 만들고, 실패는 Get의 RPC에서
// codes.InvalidArgument로 돌아온다 — mapNotFound는 codes.NotFound만 변환하므로 이 에러는 그대로
// 위로 올라가 500이 된다. 반면 Memory는 맵 미스라 ErrNotFound다. 즉 **같은 호출이 로컬에선 404,
// 운영에선 500**이었다.
//
// 빈 ID가 실제로 들어오는 자리: 미배정 담당(trainer_id == "" — 1급 상태다), 그리고 바디의
// pass_id/member_id 누락. 지금은 대부분의 호출부가 `err == nil`로 삼켜 표면화되지 않지만, 그
// 대가로 미배정 건마다 무의미한 RPC 왕복과 에러 로그가 쌓이고, 에러를 그대로 반환하는 호출부가
// 하나 생기는 순간 500이 된다. "없는 것을 찾으면 ErrNotFound"가 두 스토어의 같은 답이 되도록
// 스토어 경계에서 정규화한다(서비스 레이어가 아니라 여기인 이유: 규칙이 substrate 차이를
// 감추는 것이 Store 인터페이스의 일이다).
func checkDocID(id string) error {
	if id == "" {
		return ErrNotFound
	}
	return nil
}
