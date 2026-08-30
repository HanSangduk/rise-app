package api

// GET /v1/center/checkin-qr · POST /v1/center/checkin-qr/rotate(P49, 계약 v2.23) —
// 데스크 체크인 QR 토큰의 HTTP 절.
//
// **PUT /v1/center의 {policy?, business?} 덩어리에 얹지 않았고, PUT도 아니다.** 그 핸들러의
// 규약("보낸 덩어리만 저장")은 클라이언트가 값을 들고 온다는 전제 위에 있는데, 여기서는
// 값을 만드는 쪽이 서버다 — 대표는 보낼 값이 없고 누를 버튼만 있다. 요청 바디가 없는 것이
// 이 기능의 요점이고(사람이 비밀을 타이핑하지 않는다), 그래서 rotate는 바디 없는 POST다.
//
// 경로를 GET과 POST로 가른 이유: 조회는 부수효과가 없어야 하고, 발급은 **되돌릴 수 없는
// 파괴적 행위**(직전 인쇄물이 죽는다)라 브라우저 프리페치·재시도가 우연히 실행할 수 있는
// 메서드에 두면 안 된다.

import "net/http"

// CheckinQR — GET /v1/center/checkin-qr(owner 전용). 미발급도 200이다
// ({issued:false, token:"", issued_at:null}) — 어드민이 그리는 정상 상태다.
func (h *Handlers) CheckinQR(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	res, err := h.svc.GetCheckinQR(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// RotateCheckinQR — POST /v1/center/checkin-qr/rotate(owner 전용, 바디 없음).
//
// **바디를 읽지 않는다.** decodeJSON을 태우지 않는 것은 의도다: 읽는 순간 어드민이 무엇을
// 보내도 되는 것처럼 보이고, 언젠가 "원하는 토큰을 지정" 같은 필드가 붙는다 — 그러면 사람이
// 고른 비밀이 다시 들어오고 이 작업이 없앤 문제가 그대로 돌아온다. 토큰의 출처는 crypto/rand
// 하나뿐이라는 것이 계약이다.
//
// 응답은 200이다(201 아님): 만들어진 것은 새 리소스가 아니라 **같은 리소스의 새 값**이고,
// 돌려줄 Location도 없다.
func (h *Handlers) RotateCheckinQR(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	res, err := h.svc.RotateCheckinQR(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}
