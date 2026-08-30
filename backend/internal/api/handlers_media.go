package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// ListBodyPhotos — GET /v1/body-photos?member=.
func (h *Handlers) ListBodyPhotos(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListBodyPhotos(r.Context(), p, queryParam(r, "member"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// CreateBodyPhoto — POST /v1/body-photos(동의 검증, P8).
func (h *Handlers) CreateBodyPhoto(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req BodyPhotoCreateRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	bp, err := h.svc.CreateBodyPhoto(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, bp)
}

// ListInbody — GET /v1/inbody?member=.
func (h *Handlers) ListInbody(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListInbody(r.Context(), p, queryParam(r, "member"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// CreateInbody — POST /v1/inbody(동의 검증, P8).
func (h *Handlers) CreateInbody(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req InbodyCreateRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	rec, err := h.svc.CreateInbody(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, rec)
}

// DeleteInbody — DELETE /v1/inbody/{id}(v2.9). 회원 본인은 자기가 넣은 기록만 지울 수 있다
// (판정은 서비스). 응답 본문은 {"deleted":true} — 204는 fetch 계열 클라이언트가 본문 없는
// 응답을 에러와 구분하기 번거로워, 이 API의 다른 동사들과 같이 200+JSON으로 통일한다.
func (h *Handlers) DeleteInbody(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	if err := h.svc.DeleteInbody(r.Context(), p, chi.URLParam(r, "id")); err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"deleted": true})
}

// DeleteBodyPhoto — DELETE /v1/body-photos/{id} (v2.13).
//
// 회원 본인이면 즉시 완전 파기, 스태프면 소프트 삭제 + 유예(Service 주석 참조).
// 응답은 삭제된 메타 — 앱이 "언제 파기되는지"를 그 값으로 말한다.
func (h *Handlers) DeleteBodyPhoto(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	bp, err := h.svc.DeleteBodyPhoto(r.Context(), p, chi.URLParam(r, "id"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, bp)
}

// RestoreBodyPhoto — POST /v1/body-photos/{id}/restore (v2.13, 스태프 전용).
func (h *Handlers) RestoreBodyPhoto(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	bp, err := h.svc.RestoreBodyPhoto(r.Context(), p, chi.URLParam(r, "id"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, bp)
}

// PurgeBodyPhotos — POST /v1/body-photos/purge (v2.13, 대표 전용).
// Cloud Scheduler가 붙을 자리 — 지금은 조회에 얹은 훑기가 바닥을 맡는다.
func (h *Handlers) PurgeBodyPhotos(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	n, err := h.svc.PurgeBodyPhotos(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"purged": n})
}

// ReconcileBodyPhotos — POST /v1/body-photos/reconcile?member=&apply=true (v2.15, 대표 전용).
//
// 버킷을 거꾸로 훑어 **메타가 없는 오브젝트**를 찾는다. 삭제가 Storage 먼저·메타
// 나중인데 Storage 쪽이 조용히 no-op이면 파일만 남고, 그 파일은 메타에서 출발하는
// 어떤 경로로도 닿을 수 없다.
//
// **기본은 조회만이다.** 되돌릴 수 없는 일이라 `apply=true`를 명시해야 지운다 —
// 오타 한 번이 남의 사진을 지우는 자리다.
func (h *Handlers) ReconcileBodyPhotos(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	memberID := r.URL.Query().Get("member")
	if memberID == "" {
		writeJSON(w, http.StatusBadRequest, errBody{Error: "member 파라미터가 필요합니다"})
		return
	}
	res, err := h.svc.ReconcileBodyPhotos(
		r.Context(), p, memberID, r.URL.Query().Get("apply") == "true")
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}
