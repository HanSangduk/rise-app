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
