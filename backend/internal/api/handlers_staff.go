package api

import (
	"bytes"
	"errors"
	"io"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/ramsang/rise-backend/internal/domain"
)

// CreateStaff — POST /v1/staff(owner 전용, 트레이너 온보딩). 201 — 로그인 계정·Staff 레코드·
// UserIndex가 새로 생겼다는 뜻이다. 응답에 임시 비밀번호는 없다: 어드민이 이어서 클라이언트
// SDK의 sendPasswordResetEmail로 초대 메일을 보낸다(service.CreateStaff 주석 참고).
func (h *Handlers) CreateStaff(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req domain.StaffCreate
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	st, err := h.svc.CreateStaff(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, st)
}

// ListStaff — GET /v1/staff(타인 급여는 가려서 반환, P13).
func (h *Handlers) ListStaff(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListStaff(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// SetOffdays — POST /v1/staff/{uid}/offdays(본인 또는 owner만).
func (h *Handlers) SetOffdays(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	uid := chi.URLParam(r, "uid")
	var req struct {
		Offdays []string `json:"offdays"`
	}
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	st, err := h.svc.SetOffdays(r.Context(), p, uid, req.Offdays)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// UpdateStaff — PUT /v1/staff/{uid}(v2.0 정정, owner 전용). 머지 시맨틱 — 보낸 필드만 갱신한다.
// status는 받지 않는다: decodeJSON이 DisallowUnknownFields라 바디에 실으면 400이 되고,
// 상태 전이는 deactivate/reactivate 전용 동사만 담당한다.
func (h *Handlers) UpdateStaff(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	uid := chi.URLParam(r, "uid")
	var req domain.StaffUpdate
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	st, err := h.svc.UpdateStaff(r.Context(), p, uid, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// TransferStaff — POST /v1/staff/{uid}/transfer {to_uid}(v2.0, owner 전용).
// to_uid는 포인터로 받는다 — ""(미배정 회수)와 필드 누락을 구분해야 한다.
func (h *Handlers) TransferStaff(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	uid := chi.URLParam(r, "uid")
	var req struct {
		ToUID *string `json:"to_uid"`
	}
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	res, err := h.svc.TransferStaff(r.Context(), p, uid, req.ToUID)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// DeactivateStaff — POST /v1/staff/{uid}/deactivate {left_at?}(v2.0, owner 전용).
// 선행 조건 위반 시 409 + blockers(writeErr가 본문을 확장한다).
func (h *Handlers) DeactivateStaff(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	uid := chi.URLParam(r, "uid")
	var req struct {
		LeftAt string `json:"left_at"`
	}
	// 바디 없는 호출(= 지금 퇴사)도 정상 경로다 — 빈 본문을 {}와 같게 취급한다.
	// Content-Length에 기대지 않는다(chunked 요청은 -1이라 EOF 400으로 새는 자리).
	body, err := io.ReadAll(r.Body)
	defer r.Body.Close()
	if err != nil {
		writeErr(w, r, errors.Join(errBadRequest, err))
		return
	}
	if len(bytes.TrimSpace(body)) > 0 {
		if err := strictUnmarshal(body, &req); err != nil {
			writeErr(w, r, err)
			return
		}
	}
	st, err := h.svc.DeactivateStaff(r.Context(), p, uid, req.LeftAt)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// ReactivateStaff — POST /v1/staff/{uid}/reactivate(v2.0, owner 전용). 바디 없음.
func (h *Handlers) ReactivateStaff(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	st, err := h.svc.ReactivateStaff(r.Context(), p, chi.URLParam(r, "uid"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// UploadStaffPhoto — POST /v1/staff/{uid}/photo(v2.25, P51 — 프로필 사진 업로드, owner 전용).
//
// decodeJSON을 쓰지 않는 이유는 상한 하나뿐이다: 공용 maxBodyBytes(1MiB)로는 2MB 이미지의
// base64(약 2.67MiB)가 **정상 사진인데도** 먼저 막힌다. SignContract와 같은 모양으로
// 자기 상한을 걸고 엄격 디코딩은 그대로 간다(미지 필드 거부 — 계약 필드명 오타 조기 노출).
func (h *Handlers) UploadStaffPhoto(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	uid := chi.URLParam(r, "uid")
	r.Body = http.MaxBytesReader(w, r.Body, maxStaffPhotoBodyBytes)
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		writeErr(w, r, jsonErrMessage(err)) // MaxBytesError → "요청 본문이 너무 커요"
		return
	}
	var req StaffPhotoRequest
	if err := strictUnmarshal(raw, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	res, err := h.svc.UploadStaffPhoto(r.Context(), p, uid, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// UpdateStaffProfile — PUT /v1/staff/{uid}/profile(v1.6 — 트레이너 프로필, P05).
func (h *Handlers) UpdateStaffProfile(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	uid := chi.URLParam(r, "uid")
	var req struct {
		Profile domain.StaffProfile `json:"profile"`
	}
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	st, err := h.svc.UpdateStaffProfile(r.Context(), p, uid, req.Profile)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, st)
}
