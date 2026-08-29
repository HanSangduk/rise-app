package api

import "net/http"

// Stats — GET /v1/stats?range=ytd&scope=me|center(scope=me=본인 스코프 P45, by_trainer는 owner만).
func (h *Handlers) Stats(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	stats, err := h.svc.Stats(r.Context(), p, queryParam(r, "range"), queryParam(r, "scope"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, stats)
}
