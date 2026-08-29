package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// CreatePass — POST /v1/passes(발급 + 원장 issue).
func (h *Handlers) CreatePass(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req PassCreateRequest
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	pass, err := h.svc.CreatePass(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, pass)
}

// HoldPass — POST /v1/passes/{id}/hold {from,to,reason}(P46).
func (h *Handlers) HoldPass(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	var req HoldRequest
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	pass, err := h.svc.HoldPass(r.Context(), p, id, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, pass)
}

// ResumePass — POST /v1/passes/{id}/resume(P46).
func (h *Handlers) ResumePass(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	pass, err := h.svc.ResumePass(r.Context(), p, id)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, pass)
}

// RefundQuote — POST /v1/passes/{id}/refund-quote {used} → {per_session,usage,penalty,refund}(P5).
func (h *Handlers) RefundQuote(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	var req struct {
		Used int `json:"used"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	result, err := h.svc.RefundQuote(r.Context(), p, id, req.Used)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

// RefundPass — POST /v1/passes/{id}/refund {used}(v1.4 — 환불 실행: 원장 refund + status 전이).
func (h *Handlers) RefundPass(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	var req struct {
		Used int `json:"used"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	pass, quote, err := h.svc.RefundPass(r.Context(), p, id, req.Used)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"pass": pass, "quote": quote})
}

// ListPasses — GET /v1/passes?member=(앱 가정 승인: 내/특정 회원 회원권 목록, v1.1 정합 패치).
func (h *Handlers) ListPasses(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListPasses(r.Context(), p, queryParam(r, "member"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}
