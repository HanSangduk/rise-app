package api

import (
	"bytes"
	"encoding/base64"
	"errors"
	"image/png"
	"io"
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
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, r, err)
		return
	}
	c, err := h.svc.CreateContract(r.Context(), p, req)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	setAccessSubject(r.Context(), c.MemberID) // 접속기록 정보주체(v2.30)
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

// ContractSignRequest — POST /v1/contracts/{id}/sign의 **옵션** 바디(v2.21, P44). 바디 없음·
// 빈 바디·signature_png 빈 문자열은 전부 구버전 클릭 동의 서명으로 계속 유효하다(P44 결정 6 —
// 빈 값 ⟺ 체크 동의만, sha256 빈 값 신호와 동형).
type ContractSignRequest struct {
	SignaturePNG string `json:"signature_png"` // 자필 서명 PNG의 base64(표준 인코딩·패딩 포함)
}

// pngMagic — PNG 시그니처 8바이트. png.DecodeConfig도 같은 검사를 하지만 선분리하는 이유:
// "PNG가 아니다"(JPEG 등 다른 형식 업로드)와 "PNG인데 깨졌다"(절단·손상)를 다른 문구로
// 돌려줘야 앱이 사용자에게 정확히 안내한다 — 문구 차이는 테스트가 고정한다.
var pngMagic = []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}

// pngIENDSuffix — 정상 PNG의 마지막 12바이트(IEND 청크: 길이 0 + "IEND" + 고정 CRC).
// PNG 명세상 IEND는 반드시 마지막 청크이고 CRC는 상수다(P44 마감 리뷰 — 절단본 차단).
var pngIENDSuffix = []byte{0x00, 0x00, 0x00, 0x00, 'I', 'E', 'N', 'D', 0xAE, 0x42, 0x60, 0x82}

// 서명 이미지 검증 상한(v2.21, P44 결정 6): 크기는 패드 실측 5~18KB(P44 리서치)의 3배+ 여유 —
// 정상 서명은 절대 걸리지 않고, 계약 문서(1MiB 한도)를 서명이 잠식하는 것만 막는다. 치수는
// 캔버스로서 말이 안 되는 값(1px 띠·초대형)의 위생 거부다 — "빈 서명 방지"(최소 획·바운딩
// 박스)는 앱 몫이다(P44 결정 5). 저장은 자동 단일 필드 인덱스 예외 없이 간다: Firestore는
// 1500바이트 초과 필드 값의 인덱스 엔트리를 **잘라낼 뿐 쓰기는 성공**시키므로("Field values
// over 1500 bytes are truncated" — firebase.google.com/docs/firestore/quotas, 2026-08-29 확인)
// 쓰기 실패 위험이 없고, signature_png는 어떤 쿼리에도 쓰이지 않아 잘린 인덱스도 무해하다.
const (
	maxSignaturePNGBytes = 64 << 10 // 64KB — 디코드된 PNG 원본 기준
	minSignatureWidth    = 50
	maxSignatureWidth    = 2000
	minSignatureHeight   = 20
	maxSignatureHeight   = 2000
)

// decodeSignaturePNG — sign 옵션 바디의 서명 이미지를 검증하고 원본 바이트로 돌려준다(v2.21,
// P44). 순서: base64 → PNG 매직 → 크기 상한 → 치수 위생(png.DecodeConfig는 헤더만 읽는다 —
// 전체 픽셀 디코드 없음). 전부 서비스 호출 **전**의 400 — 저장 가능한 것만 트랜잭션에 들어간다.
// 입력은 maxBodyBytes(1MiB)로 이미 유계라 디코드 자체가 메모리 위험이 아니다.
func decodeSignaturePNG(b64 string) ([]byte, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, errors.Join(errBadRequest, errors.New("서명 이미지 인코딩(base64)이 올바르지 않아요"))
	}
	if !bytes.HasPrefix(raw, pngMagic) {
		return nil, errors.Join(errBadRequest, errors.New("서명 이미지는 PNG 형식이어야 해요"))
	}
	if len(raw) > maxSignaturePNGBytes {
		return nil, errors.Join(errBadRequest, errors.New("서명 이미지가 너무 커요(최대 64KB)"))
	}
	// P44 마감 리뷰: DecodeConfig는 IHDR만 읽어 IDAT·IEND 부재를 못 본다 — 헤더만 남기고
	// 절단한 PNG가 통과해 "어떤 디코더로도 렌더 불가한 이미지"가 증거로 저장될 수 있었다.
	// 정상 PNG는 반드시 IEND 청크(길이0 + "IEND" + 고정 CRC 12바이트)로 **끝나므로**, 접미
	// 검사 하나로 절단본과 IEND 뒤 쓰레기 둘 다 막는다(압축 해제 없음 — 폭탄 표면 불변).
	if !bytes.HasSuffix(raw, pngIENDSuffix) {
		return nil, errors.Join(errBadRequest, errors.New("서명 이미지가 손상됐어요 — 다시 서명해 주세요"))
	}
	cfg, err := png.DecodeConfig(bytes.NewReader(raw))
	if err != nil {
		return nil, errors.Join(errBadRequest, errors.New("서명 이미지를 해석할 수 없어요"))
	}
	if cfg.Width < minSignatureWidth || cfg.Width > maxSignatureWidth ||
		cfg.Height < minSignatureHeight || cfg.Height > maxSignatureHeight {
		return nil, errors.Join(errBadRequest,
			errors.New("서명 이미지 크기가 올바르지 않아요(가로 50~2000px, 세로 20~2000px)"))
	}
	return raw, nil
}

// SignContract — POST /v1/contracts/{id}/sign(v1.4 — 회원 자체서명, P27. v2.21/P44부터 자필
// 서명 이미지 옵션 바디). decodeJSON을 못 쓰는 이유: decodeJSON은 빈 바디를 400(EOF)으로
// 돌려주는데 여기선 빈 바디가 정상 경로다(구버전 앱 — P44 결정 6). 통읽기 후 빈 판정으로
// 가르되, 상한·스머글링 방어(MaxBytesReader)와 엄격 디코딩(strictUnmarshal)은 동일하게 간다.
func (h *Handlers) SignContract(w http.ResponseWriter, r *http.Request) {
	p, _ := principalFrom(r.Context())
	id := chi.URLParam(r, "id")
	var signature []byte
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		writeErr(w, r, jsonErrMessage(err)) // MaxBytesError → "요청 본문이 너무 커요"
		return
	}
	if len(bytes.TrimSpace(raw)) > 0 {
		var req ContractSignRequest
		if err := strictUnmarshal(raw, &req); err != nil {
			writeErr(w, r, err)
			return
		}
		if req.SignaturePNG != "" {
			if signature, err = decodeSignaturePNG(req.SignaturePNG); err != nil {
				writeErr(w, r, err)
				return
			}
		}
	}
	c, err := h.svc.SignContract(r.Context(), p, id, clientIPForAudit(r), signature)
	if err != nil {
		writeErr(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, c)
}
