package api

import "net/http"

// 관리 평면 핸들러(멀티센터 Phase A) — superadmin 전용. 가드는 서비스 레이어 선두에 있다
// (owner/staff 엔드포인트와 같은 패턴 — 라우터는 얇게).

// CreateCenter — POST /v1/admin/centers {id,name,phone,address,owner:{name,email}}.
func (h *Handlers) CreateCenter(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req CenterCreate
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	res, err := h.svc.CreateCenter(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, res)
}

// ListCenters — GET /v1/admin/centers.
func (h *Handlers) ListCenters(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListCenters(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// JoinCenters — GET /v1/join/centers (인증 필요, 계약 v2.33).
//
// 가입 요청을 보낼 수 있는 센터 목록. 관리 평면(`/v1/admin/centers`, superadmin 전용)과 다른
// 경로인 이유는 **독자가 다르기 때문**이다: 이쪽은 전화 인증만 끝난 신규 사용자가 읽고,
// 응답도 고르는 데 필요한 것(상호·주소·전화)만 싣는다.
func (h *Handlers) JoinCenters(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	res, err := h.svc.JoinCenters(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}
