package api

import (
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
)

// CreatePayment — POST /v1/payments.
func (h *Handlers) CreatePayment(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req PaymentCreateRequest
	if err := decodeJSON(r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	pay, err := h.svc.CreatePayment(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, pay)
}

// ListPayments — GET /v1/payments?member=(결제 목록, 분할·미수 확인, v1.1 정합 패치).
func (h *Handlers) ListPayments(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListPayments(r.Context(), p, queryParam(r, "member"))
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// PayInstallment — POST /v1/payments/{id}/installments/{i}/pay.
func (h *Handlers) PayInstallment(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	idx, err := strconv.Atoi(chi.URLParam(r, "i"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errBody{Error: "invalid installment index"})
		return
	}
	pay, err := h.svc.PayInstallment(r.Context(), p, id, idx)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, pay)
}
