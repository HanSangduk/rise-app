package api

// PUT /v1/center/facility(P42, 계약 v2.19) — 시설 신고 상태 선언의 HTTP 절.

import (
	"net/http"

	"github.com/ramsang/rise-backend/internal/domain"
)

// UpdateCenterFacility — PUT /v1/center/facility {report_status, report_no, insurance}
// (owner 전용). PUT /v1/center의 {policy?, business?} 덩어리에 세 번째를 얹지 않고 경로를
// 분리한 이유: 그 핸들러의 "보낸 덩어리만 처리 + 비원자" 규약은 두 값 사이 불변식이 없다는
// 전제 위에 있는데, 이쪽은 상태와 신고번호가 **한 검증**(reported⇒번호 필수)으로 묶인 한
// 덩어리라 부분 제출이라는 개념 자체가 없다 — 고정 3필드 바디가 계약이다.
//
// 바디는 domain.Facility로 곧장 디코드한다(와이어 3키 == 도메인 json 태그. decodeJSON의
// DisallowUnknownFields가 오타 필드를 400으로 돌려보낸다).
//
// **응답은 저장된 facility 그 자체다**(정규화 반영본) — GET /v1/center 전체가 아니다.
// PUT /v1/center(전체 재응답 — 캐시 갈아끼우기)와 다른 선택인 이유: 어드민의 saveFacility는
// 이 응답으로 폼만 재장전하고 센터 캐시는 쿼리 무효화(keys.center → GET 재조회)로 따로
// 맞춘다(P42 어드민 규약). 전체를 실으면 "이 엔드포인트는 이 절만 만진다"는 의미도 흐려진다.
func (h *Handlers) UpdateCenterFacility(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	var req domain.Facility
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	saved, err := h.svc.UpdateCenterFacility(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, saved)
}
