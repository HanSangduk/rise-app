package api

import (
	"errors"
	"io"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/ramsang/rise-backend/internal/domain"
)

// ListMembers — GET /v1/members?trainer=&q=(역할 스코프 자동: 트레이너=담당만).
func (h *Handlers) ListMembers(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListMembers(r.Context(), p, queryParam(r, "trainer"), queryParam(r, "q"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// CreateMember — POST /v1/members.
func (h *Handlers) CreateMember(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var mem domain.Member
	if err := decodeJSON(r, &mem); err != nil {
		writeErr(w, r, err)
		return
	}
	saved, err := h.svc.CreateMember(r.Context(), p, &mem)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, saved)
}

// UpdateMember — PUT /v1/members/{id}. 머지 시맨틱이라 raw 바디를 서비스에 그대로 넘긴다
// (서비스가 기존 레코드를 불러온 뒤 그 위에 언마샬 — 보낸 필드만 갱신).
func (h *Handlers) UpdateMember(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	body, err := io.ReadAll(r.Body)
	defer r.Body.Close()
	if err != nil {
		writeErr(w, r, errors.Join(errBadRequest, err))
		return
	}
	saved, err := h.svc.UpdateMember(r.Context(), p, id, body)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, saved)
}

// MemberLedger — GET /v1/members/{id}/ledger?pass=.
func (h *Handlers) MemberLedger(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	list, err := h.svc.MemberLedger(r.Context(), p, id, queryParam(r, "pass"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}
