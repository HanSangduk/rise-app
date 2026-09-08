package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

// ListSlots — GET /v1/slots?date= → [Slot](용량·팀).
func (h *Handlers) ListSlots(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListSlots(r.Context(), p, queryParam(r, "date"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// ListBookings — GET /v1/bookings?member=&from=(앱 가정 승인: 내 예약 목록, v1.1 정합 패치).
func (h *Handlers) ListBookings(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListBookings(r.Context(), p, queryParam(r, "member"), queryParam(r, "from"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// CreateBooking — POST /v1/bookings {slot_key, member_id, pass_id}
// 트랜잭션: 용량3 + 트레이너동시1 + 잔여>0(P35).
func (h *Handlers) CreateBooking(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req BookingCreateRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	booking, err := h.svc.CreateBooking(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	setAccessSubject(r.Context(), booking.MemberID) // 접속기록 정보주체(v2.30) — 본문에만 있는 id
	writeJSON(w, http.StatusOK, booking)
}

// CancelBooking — DELETE /v1/bookings/{id}(컷오프 검사 24h).
func (h *Handlers) CancelBooking(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	// v1.5: ?waive=true — 스태프의 운영 사유 취소(무차감). member 요청에선 무시된다(서비스가 IsStaff 확인).
	waive := queryParam(r, "waive") == "true"
	if err := h.svc.CancelBooking(r.Context(), p, id, waive); err != nil {
		writeErr(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// CompleteBooking — POST /v1/bookings/{id}/complete(원장 차감, P4).
func (h *Handlers) CompleteBooking(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	booking, err := h.svc.CompleteBooking(r.Context(), p, id)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, booking)
}

// NoshowBooking — POST /v1/bookings/{id}/noshow(원장 차감·유예, P7).
func (h *Handlers) NoshowBooking(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	booking, err := h.svc.NoshowBooking(r.Context(), p, id)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, booking)
}

// CreateRecurring — POST /v1/recurrings(고정 스케줄, P47).
func (h *Handlers) CreateRecurring(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req RecurringCreateRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	rec, err := h.svc.CreateRecurring(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, rec)
}

// ListRecurrings — GET /v1/recurrings?include_expired=true(v1.4 — 고정 스케줄 관리 목록.
// owner=전체, trainer=본인). include_expired는 만료(until 경과) 규칙 정리용(v2.3).
func (h *Handlers) ListRecurrings(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListRecurrings(r.Context(), p, queryParam(r, "include_expired") == "true")
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// DeleteRecurring — DELETE /v1/recurrings/{id}?keep_bookings=true.
// v2.3: 204(빈 응답) → 200 {cancelled, kept}. 규칙과 함께 정리된 미래 예약 건수를 돌려준다 —
// 어드민이 "고정 해제 · 예정 10건 취소됨"을 그 자리에서 띄우고 회원에게 알릴 수 있어야 한다.
func (h *Handlers) DeleteRecurring(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	res, err := h.svc.DeleteRecurring(r.Context(), p, id, queryParam(r, "keep_bookings") == "true")
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// Checkin — POST /v1/checkin {source:"tap|self_qr", booking_id?|qr_token?}(P44).
func (h *Handlers) Checkin(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req CheckinRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	booking, err := h.svc.Checkin(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	setAccessSubject(r.Context(), booking.MemberID) // 접속기록 정보주체(v2.30) — 서버가 찾은 예약의 회원
	writeJSON(w, http.StatusOK, booking)
}
