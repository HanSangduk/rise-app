package api

import (
	"net"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
)

// ListContracts — GET /v1/contracts?member=&status=(계약 목록, 어드민 계약확인, v1.1 정합 패치).
func (h *Handlers) ListContracts(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListContracts(r.Context(), p, queryParam(r, "member"), queryParam(r, "status"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// CreateContract — POST /v1/contracts {member_id, pass_id}(생성 — 발급 시 자동 생성은 CreatePass가 담당).
func (h *Handlers) CreateContract(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req ContractCreateRequest
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	c, err := h.svc.CreateContract(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, c)
}

// SendContract — POST /v1/contracts/{id}/send(서명 요청 (재)발송).
func (h *Handlers) SendContract(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	c, err := h.svc.SendContract(r.Context(), p, id)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, c)
}

// clientIPForAudit — 서명 증적용 클라이언트 IP(v1.5). chi RealIP는 XFF "첫" 항목을 쓰는데,
// Cloud Run/GCLB는 클라이언트가 보낸 XFF 뒤에 실제 IP를 append하므로 첫 항목은 위조 가능하다
// (P04 감사) — 신뢰 프록시가 붙인 "마지막" 항목을 취하고, 없으면 소켓 주소로 폴백한다.
func clientIPForAudit(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		last := strings.TrimSpace(parts[len(parts)-1])
		if last != "" {
			return last
		}
	}
	ip := r.RemoteAddr
	if host, _, err := net.SplitHostPort(ip); err == nil {
		return host
	}
	return ip
}

// SignContract — POST /v1/contracts/{id}/sign(v1.4 — 회원 자체서명, P27).
func (h *Handlers) SignContract(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	c, err := h.svc.SignContract(r.Context(), p, id, clientIPForAudit(r))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, c)
}
