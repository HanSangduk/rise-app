package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// 재등록/상담 요청 핸들러(계약 v2.20, P42). 가드는 서비스 레이어 선두(다른 엔드포인트와 동일).

// CreateConsultRequest — POST /v1/consult-requests {kind, note?}(회원 본인).
func (h *Handlers) CreateConsultRequest(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req ConsultRequestBody
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	cr, err := h.svc.CreateConsultRequest(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, cr)
}

// ListConsultRequests — GET /v1/consult-requests(member: 자기 것 / owner: 전체 / trainer: 담당).
func (h *Handlers) ListConsultRequests(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListConsultRequests(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// DoneConsultRequest — POST /v1/consult-requests/{id}/done(스태프 — 데스크 처리 완료).
func (h *Handlers) DoneConsultRequest(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	cr, err := h.svc.DoneConsultRequest(r.Context(), p, chi.URLParam(r, "id"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, cr)
}
