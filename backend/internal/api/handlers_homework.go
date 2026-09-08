package api

import "net/http"

// ListHomeworks — GET /v1/homeworks?member=&date=(v2.3 date: 그날 스케줄상 유효한 배정만.
// 회원 응답은 date를 생략해도 오늘이 기본 — 이 목록이 곧 "오늘의 운동"이다).
func (h *Handlers) ListHomeworks(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListHomeworks(r.Context(), p, queryParam(r, "member"), queryParam(r, "date"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// CreateHomework — POST /v1/homeworks(부상 자동 제외, P39).
func (h *Handlers) CreateHomework(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req HomeworkCreateRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	hw, err := h.svc.CreateHomework(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	// 접속기록 정보주체(v2.30): 배정 대상이 여럿(scope)일 수 있어 개인 배정(대상 1명)일 때만
	// 확정한다 — 여럿을 한 칸에 욱여넣으면 점검 리포트의 uid×member 집계가 깨진다.
	if len(hw.TargetMemberIDs) == 1 {
		setAccessSubject(r.Context(), hw.TargetMemberIDs[0])
	}
	writeJSON(w, http.StatusOK, hw)
}

// CreateHwCheck — POST /v1/hw-checks {hw_id, date, done:[...]}.
func (h *Handlers) CreateHwCheck(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req HwCheckRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	c, err := h.svc.CreateHwCheck(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	setAccessSubject(r.Context(), c.MemberID) // 접속기록 정보주체(v2.30) — 스태프 대행 입력 시
	writeJSON(w, http.StatusOK, c)
}

// ListHwChecks — GET /v1/hw-checks?hw_id=&member=&date=(어드민·앱 가정 승인, v1.1 + v1.2 date).
func (h *Handlers) ListHwChecks(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListHwChecks(r.Context(), p, queryParam(r, "hw_id"), queryParam(r, "member"), queryParam(r, "date"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}
