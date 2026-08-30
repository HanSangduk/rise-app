package api

import (
	"encoding/json"
	"errors"
	"net/http"
)

// Handlers — HTTP 핸들러 묶음. 모든 핸들러는 principalFrom(r.Context())로 인증 정보를 읽는다
// (auth.go의 Middleware가 /v1 라우트 전체에 미리 심어둔다 — router.go 참고).
type Handlers struct {
	svc *Service
	// health — /health 의존성 체크 결과 캐시(health.go). 뮤텍스를 품으므로 Handlers는 항상
	// 포인터로 다룬다(NewHandlers가 이미 그렇게 준다).
	health healthState
}

func NewHandlers(svc *Service) *Handlers { return &Handlers{svc: svc} }

func (h *Handlers) Healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// Me — GET /v1/me → {uid, role, center_id, member_id?, name?}(v2.2).
func (h *Handlers) Me(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	writeJSON(w, http.StatusOK, h.svc.Me(r.Context(), p))
}

// DeleteMe — DELETE /v1/me(회원탈퇴, v2.11). 바디 없음.
//
// 바디로 confirm 플래그를 받지 않는다: 클라이언트가 스스로 세우는 값이라 실제로 막는 것이
// 없고(보안 연극), 확인 절차는 앱의 확인 화면이 담당한다. DELETE /v1/inbody/{id}가 같은
// 모양이다 — 파괴적이지만 바디가 없고, 되돌릴 수 없다는 고지는 클라이언트 몫이다.
func (h *Handlers) DeleteMe(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	res, err := h.svc.DeleteMyAccount(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// JoinMatch — POST /v1/join/match {phone} → {member?, needs_confirm}(P48①).
func (h *Handlers) JoinMatch(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req struct {
		Phone string `json:"phone"`
	}
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	res, err := h.svc.JoinMatch(r.Context(), p, req.Phone)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// JoinConfirm — POST /v1/join/confirm {member_id, confirm}(이름 확인 1탭, P48).
func (h *Handlers) JoinConfirm(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req JoinConfirmRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	res, err := h.svc.JoinConfirm(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// JoinRequest — POST /v1/join/request {name, phone}(매칭 실패 폴백, P48③).
// 바디의 center_id는 받아도 무시한다 — 센터는 토큰이 정한다(service.go JoinRequestCreate 주석).
func (h *Handlers) JoinRequest(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req JoinRequestBody
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	jr, err := h.svc.JoinRequestCreate(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, jr)
}

// JoinApprove — POST /v1/join/approve {request_id}(owner 원탭 승인).
func (h *Handlers) JoinApprove(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req struct {
		RequestID string `json:"request_id"`
	}
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	mem, err := h.svc.JoinApprove(r.Context(), p, req.RequestID)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, mem)
}

// JoinRequests — GET /v1/join/requests(어드민 가정 승인: 가입 요청 목록, v1.1 정합 패치).
func (h *Handlers) JoinRequests(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	list, err := h.svc.ListJoinRequests(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

// Center — GET /v1/center(v1.1, v1.4에서 member에게도 공개 — revenue_target은 owner만).
func (h *Handlers) Center(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	res, err := h.svc.GetCenter(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// UpdateCenter — PUT /v1/center {policy?, business?}(owner 전용). 둘 다 raw로 넘겨 각 서비스가
// 자기 시맨틱으로 처리한다: policy는 머지(누락 필드 초기화 방지, v1.4), business는 통 교체(v2.13).
//
// **보낸 덩어리만 처리한다.** 이 규칙이 없으면 정책만 저장하는 기존 어드민 호출이 사업자 정보를
// 빈 값으로 밀어버린다 — v2.13 배포 순간 법정 문서 5장이 한꺼번에 초안으로 되돌아간다.
//
// 둘을 한 요청에 함께 보내면 **원자적이지 않다**(정책 저장 후 사업자 정보 검증에서 400이면
// 정책만 저장된 상태로 끝난다). 트랜잭션으로 묶지 않은 이유: 어드민은 두 폼이 따로라 실제로는
// 한쪽씩만 오고, 두 값 사이에 지켜야 할 불변식이 없다 — 돈·세션이 움직이는 경로(v2.6)와 달리
// 여기서는 "절반만 저장됨"이 데이터를 모순되게 만들지 않는다. 응답이 저장 후 실제 상태이므로
// 무엇이 저장됐는지는 그 자리에서 보인다.
func (h *Handlers) UpdateCenter(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req struct {
		Policy json.RawMessage `json:"policy"`
		// Business — v2.13 신설. decodeJSON이 DisallowUnknownFields라 **서버가 먼저 이 필드를
		// 알아야** 어드민이 보낼 수 있다(계약 v2.13 "배포 순서" 절 — 서버 먼저, 어드민 나중).
		Business json.RawMessage `json:"business"`
	}
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	if len(req.Policy) == 0 && len(req.Business) == 0 {
		writeErr(w, r, errors.Join(errBadRequest, errors.New("policy 또는 business 객체가 필요해요")))
		return
	}
	if len(req.Policy) > 0 {
		if _, err := h.svc.UpdateCenterPolicy(r.Context(), p, req.Policy); err != nil {
			writeErr(w, r, err)
			return
		}
	}
	if len(req.Business) > 0 {
		if _, err := h.svc.UpdateCenterBusiness(r.Context(), p, req.Business); err != nil {
			writeErr(w, r, err)
			return
		}
	}
	// 저장 후 상태를 한 번에 다시 읽어 응답한다 — 어느 덩어리를 보냈든 클라이언트가 받는 모양이
	// GET /v1/center과 같아진다(캐시를 그대로 갈아끼울 수 있다).
	res, err := h.svc.GetCenter(r.Context(), p)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

// PublicBusiness — GET /v1/public/business(**무인증**, v2.13). 법정 고지 HTML 5장이 익명으로
// 읽는 유일한 엔드포인트다. 응답은 사업자 정보 12칸 + complete뿐 — 정책·센터 식별자는 없다.
func (h *Handlers) PublicBusiness(w http.ResponseWriter, r *http.Request) {
	res, err := h.svc.PublicBusiness(r.Context())
	if err != nil {
		writeErr(w, r, err)
		return
	}
	// 법정 문서는 Hosting CDN 뒤의 정적 HTML이고 이 응답만 동적이다. 무인증 경로라 호출량을
	// 통제할 다른 수단이 없어 캐시로 막는다 — 안 걸면 문서 조회가 그대로 Firestore 읽기가 된다.
	// 수정 반영이 최대 5분 늦지만, 연 단위로 바뀌는 값이라 그 지연이 비용보다 싸다.
	w.Header().Set("Cache-Control", "public, max-age=300")
	writeJSON(w, http.StatusOK, res)
}
