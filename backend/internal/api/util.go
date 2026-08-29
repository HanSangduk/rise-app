package api

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5/middleware"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// writeJSON — 표준 JSON 응답. Cache-Control 기본값은 no-store다 — 어드민 트래픽이 Hosting
// CDN(/api 리라이트)을 통과하므로, 캐시 지시자 없는 응답은 휴리스틱 캐싱 대상이 된다(RFC 9111
// §4.2.2). 실제로 캐시 지시자 없는 404가 CDN·브라우저에 1시간 눌러앉아 서버 복구가 사용자에게
// 도달하지 못한 사고가 있었다(P34/P35). 캐시하고 싶은 극소수 경로(PublicBusiness)만 writeJSON
// **호출 전에** 자기 값을 세팅해 이 기본값을 비켜간다.
func writeJSON(w http.ResponseWriter, status int, v any) {
	if w.Header().Get("Cache-Control") == "" {
		w.Header().Set("Cache-Control", "no-store")
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// errBody — 계약 표준 에러 포맷: {"error":"메시지"}.
type errBody struct {
	Error string `json:"error"`
}

// friendlyDomainMessages — 도메인 sentinel 에러의 사용자향 한국어 문구. 계약의 에러 메시지는
// 클라이언트가 그대로 화면에 띄우므로 영문 내부 문구("domain: ...")를 흘리지 않는다.
var friendlyDomainMessages = []struct {
	err error
	msg string
}{
	{domain.ErrSlotFull, "해당 시간이 만석이에요"},
	{domain.ErrTrainerBusy, "코치가 해당 시간에 이미 수업이 있어요"},
	{domain.ErrNoSessionsLeft, "남은 회차가 없어요 — 이미 잡힌 예약이 잔여 회차를 채웠어요"},
	{domain.ErrOutsideCheckinWindow, "체크인 가능 시간이 아니에요(수업 시작 ±30분)"},
	{domain.ErrInvalidHoldRange, "일시정지 기간이 올바르지 않아요"},
	{domain.ErrNoActiveHold, "지금 진행 중인 일시정지가 없어요"},
	{domain.ErrHoldLimitExceeded, "일시정지 가능 횟수/일수를 초과했어요(센터 정책)"},
	{domain.ErrInvalidSlotKey, "예약 시간 형식이 올바르지 않아요"},
	{domain.ErrInvalidContractStatus, "계약 상태 값이 올바르지 않아요"},
	{domain.ErrInvalidContractTransition, "현재 계약 상태에서는 처리할 수 없어요"},
}

// writeErr — 도메인/스토어 에러를 HTTP 상태코드로 매핑한다. 계약의 에러 메시지는 사용자향
// 문구다 — 내부 마커("api: bad request")나 Go 에러 원문을 그대로 흘리지 않는다.
// r을 받는 이유: 5xx 로그에 request ID·경로·호출자를 실어야 액세스 로그의 500 한 줄과
// 이어붙일 수 있다(P35) — 이게 없으면 트래픽이 조금만 있어도 "어느 요청이 왜 500이었나"를 못 찾는다.
func writeErr(w http.ResponseWriter, r *http.Request, err error) {
	// 퇴사 선행 조건 위반은 표준 {error} 위에 blockers를 얹은 확장 본문이다(계약 v2.0) —
	// 어드민이 "무엇을 먼저 이관해야 하는지"를 재조회 없이 바로 띄울 수 있어야 한다.
	var blocked *staffBlockedError
	if errors.As(err, &blocked) {
		writeJSON(w, http.StatusConflict, struct {
			Error    string        `json:"error"`
			Blockers StaffBlockers `json:"blockers"`
		}{Error: blocked.msg, Blockers: blocked.blockers})
		return
	}
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeJSON(w, http.StatusNotFound, errBody{Error: "찾을 수 없음"})
	case errors.Is(err, ErrForbidden):
		writeJSON(w, http.StatusForbidden, errBody{Error: "권한이 없습니다"})
	case errors.Is(err, domain.ErrSlotFull),
		errors.Is(err, domain.ErrTrainerBusy),
		errors.Is(err, ErrConflict):
		writeJSON(w, http.StatusConflict, errBody{Error: userMessage(err)})
	case errors.Is(err, store.ErrStateConflict):
		writeJSON(w, http.StatusBadRequest, errBody{Error: "이미 처리된 예약이에요(새로고침 후 확인해주세요)"})
	case errors.Is(err, domain.ErrOutsideCheckinWindow),
		errors.Is(err, domain.ErrInvalidHoldRange),
		errors.Is(err, domain.ErrNoActiveHold),
		errors.Is(err, domain.ErrHoldLimitExceeded),
		errors.Is(err, domain.ErrInvalidSlotKey),
		errors.Is(err, domain.ErrNoSessionsLeft),
		errors.Is(err, domain.ErrInvalidContractStatus),
		errors.Is(err, domain.ErrInvalidContractTransition),
		errors.Is(err, domain.ErrInvalidPolicy),
		errors.Is(err, domain.ErrInvalidBusiness),
		errors.Is(err, domain.ErrInvalidProfile),
		errors.Is(err, domain.ErrInvalidStaff),
		errors.Is(err, domain.ErrInvalidPassPeriod),
		errors.Is(err, domain.ErrInvalidHwSchedule),
		errors.Is(err, domain.ErrInvalidInbody),
		errors.Is(err, domain.ErrInvalidBodyPoses),
		errors.Is(err, errBadRequest):
		writeJSON(w, http.StatusBadRequest, errBody{Error: userMessage(err)})
	default:
		// 내부 오류 원문은 로그로만 남기고 응답에는 노출하지 않는다.
		p, _ := principalFrom(r.Context())
		log.Printf("internal error: reqid=%s %s %s uid=%s: %v",
			middleware.GetReqID(r.Context()), r.Method, r.URL.Path, p.UID, err)
		writeJSON(w, http.StatusInternalServerError, errBody{Error: "서버 오류가 발생했습니다"})
	}
}

// userMessage — 도메인 sentinel은 한국어 문구로 치환하고, errors.Join으로 겹친 내부 마커
// 라인("api: bad request")은 걷어낸다(errors.Join의 Error()는 개행으로 이어 붙는다).
func userMessage(err error) string {
	for _, fm := range friendlyDomainMessages {
		if errors.Is(err, fm.err) {
			return fm.msg
		}
	}
	lines := strings.Split(err.Error(), "\n")
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		// 내부 마커 라인은 전부 걷어낸다 — sentinel 관례가 "api:/domain:/store: " 프리픽스라
		// 목록을 하드코딩하지 않고 프리픽스로 거른다(ErrInvalidPolicy 등 신규 sentinel 포함).
		if l == "" || strings.HasPrefix(l, "api: ") || strings.HasPrefix(l, "domain: ") || strings.HasPrefix(l, "store: ") {
			continue
		}
		out = append(out, l)
	}
	if len(out) == 0 {
		return "잘못된 요청입니다"
	}
	return strings.Join(out, " / ")
}

// errBadRequest — 요청 파싱/검증 실패의 공용 마커(writeErr에서 400으로 매핑).
var errBadRequest = errors.New("api: bad request")

// logPaymentOverContract — 한 패스의 결제 기록 합이 계약가를 넘은 사건을 서버 로그에 남긴다
// (v2.3, P12 감사 C1). 정산은 domain.SettleRefund가 계약가로 캡핑해 막지만, 캡이 걸렸다는 것
// 자체가 "이 패스에 중복·오입력 결제가 남아 있다"는 신호다 — 사람이 정정해야 하고, 그러려면
// 먼저 눈에 보여야 한다. 응답에는 싣지 않는다(회원도 견적을 조회한다).
func logPaymentOverContract(passID string, recorded, contract int) {
	log.Printf("payment over contract: pass=%s recorded=%d contract=%d — 결제 기록 합이 계약가를 초과(중복 기록 의심, 정산은 계약가로 캡핑)",
		passID, recorded, contract)
}

// ErrConflict — 이미 존재하는 레코드와 충돌하는 생성 시도(409 매핑). 상태 전이 충돌
// (store.ErrStateConflict, 400)과 구분한다 — 이쪽은 "다시 시도해도 같다"는 뜻이다.
var ErrConflict = errors.New("api: conflict")

// jsonErrMessage — encoding/json 에러를 사용자향 한국어 문구로 치환한다(계약: "Go 에러 원문
// 노출 금지"). 원문은 디버깅용으로 로그에만 남긴다.
func jsonErrMessage(err error) error {
	var syntaxErr *json.SyntaxError
	var typeErr *json.UnmarshalTypeError
	var tooLarge *http.MaxBytesError
	msg := ""
	switch {
	case errors.As(err, &tooLarge):
		msg = "요청 본문이 너무 커요"
	case errors.Is(err, io.EOF), errors.Is(err, io.ErrUnexpectedEOF):
		msg = "요청 본문(JSON)이 비어 있거나 잘려 있어요"
	case errors.As(err, &syntaxErr):
		msg = "요청 본문(JSON) 형식이 올바르지 않아요"
	case errors.As(err, &typeErr):
		msg = "필드 형식이 올바르지 않아요: " + typeErr.Field
	case strings.Contains(err.Error(), "unknown field"):
		msg = "지원하지 않는 필드가 포함돼 있어요"
	default:
		msg = "요청 본문을 해석할 수 없어요"
	}
	log.Printf("json decode error: %v", err)
	return errors.Join(errBadRequest, errors.New(msg))
}

// maxBodyBytes — 요청 바디 상한(1MiB). 이 API의 최대 페이로드(계약 서명·수업기록)도 수십 KB라
// 여유가 크다. 상한이 없으면 임의 크기 JSON을 json.Decoder가 그대로 파싱을 시도한다 — 요청
// 하나로 메모리를 태우는 경로가 열려 있었다(P35 H-1).
const maxBodyBytes = 1 << 20

// decodeJSON — 요청 바디를 엄격 디코딩(알 수 없는 필드 거부 — 계약 필드명 오타를 조기에 드러낸다).
func decodeJSON(r *http.Request, v any) error {
	defer r.Body.Close()
	r.Body = http.MaxBytesReader(nil, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return jsonErrMessage(err)
	}
	if dec.More() {
		// v1.3 계약("이어붙인 다중 JSON 문서 거부")을 요청 바디 경로에도 동일 적용(P03).
		return errors.Join(errBadRequest, errors.New("요청 본문에 JSON 문서가 두 개 이상이에요"))
	}
	return nil
}

// strictUnmarshal — decodeJSON과 동일한 엄격 규칙(미지 필드 거부)을 raw 바이트에 적용한다.
// PUT 머지(기존 레코드 위 덮어쓰기)처럼 대상 구조체를 미리 채워야 하는 경로에서 사용.
func strictUnmarshal(data []byte, v any) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return jsonErrMessage(err)
	}
	if dec.More() {
		// "{...}{...}" 같은 이어붙인 문서의 뒷부분이 조용히 무시되지 않게 명시적으로 거부.
		return errors.Join(errBadRequest, errors.New("요청 본문에 JSON 문서가 두 개 이상이에요"))
	}
	return nil
}

// queryParam — r.URL.Query().Get(key)의 짧은 이름.
func queryParam(r *http.Request, key string) string {
	return r.URL.Query().Get(key)
}

func queryIntParam(r *http.Request, key string, def int) int {
	v := r.URL.Query().Get(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}
