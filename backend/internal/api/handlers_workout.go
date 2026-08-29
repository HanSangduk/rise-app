package api

import "net/http"

// ListWorkoutLogs — GET /v1/workout-logs?member=&from=(v1.4 수업 기록 — 회원 앱 기록 탭·어드민 회원 상세).
func (h *Handlers) ListWorkoutLogs(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListWorkoutLogs(r.Context(), p, queryParam(r, "member"), queryParam(r, "from"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// CreateWorkoutLog — POST /v1/workout-logs(v1.4 — 트레이너 30초 기록, P29 2안 수업 루프의 v1 흡수).
func (h *Handlers) CreateWorkoutLog(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req WorkoutLogCreateRequest
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	wl, err := h.svc.CreateWorkoutLog(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, wl)
}
