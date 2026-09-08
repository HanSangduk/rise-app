package api

// 개인정보처리시스템 접속기록 — 「개인정보의 안전성 확보조치 기준」(개인정보보호위원회고시
// 제2026-9호, 2026.7.1. 일부개정·같은 날 시행(law.go.kr 헤더 [시행 2026. 7. 1.] 확인)) §8 · P61.
//
// 왜 이 파일이 있나: privacy.html이 "접속기록 2년 이상 보관·위변조 방지·점검"을 약속하는데
// 서버에는 chi 평문 요청 로그뿐이었다 — 취급자(uid)·처리한 정보주체·수행업무가 없어 고시 §2의
// '접속기록' 정의(식별자·접속일시·접속지·처리한 정보주체·수행업무)를 만족하지 못했고, 그 로그마저
// _Default 버킷 30일 뒤 사라졌다(P56 L9). 여기서 **한 요청 = JSON 한 줄**(log_type:"access")을
// stdout에 쓰고, Cloud Logging sink(backend/scripts/setup-access-log.sh)가 이 라인만 골라
// 서울 리전 전용 버킷(보존 740일)에 넣는다.
//
// 왜 stdout JSON인가: Cloud Run은 stdout의 JSON 한 줄을 jsonPayload로 파싱하고 severity·time·
// logging.googleapis.com/trace 같은 특수 키는 LogEntry 필드로 승격한다(structured-logging 문서).
// recoverJSON(health.go)이 ERROR 라인을 같은 규약으로 쓰는 것과 같은 이유다.
//
// 왜 응답 **뒤**(defer)에서 쓰나: chi는 서브라우터 미들웨어 시점엔 RoutePattern()이 "/v1/*"다 —
// 엔드포인트 패턴("/v1/members/{id}")과 URLParam은 next가 돌아온 뒤에만 읽힌다(chi v5.2.1 실측).
// 부작용: 라우팅 전에 끝나는 401·404는 route가 "/v1/*"로 남으므로 path를 항상 병기한다.
//
// 기록 범위(§8① "정보주체는 제외한다"): 스태프(owner/trainer/superadmin)의 요청은 전부,
// 회원(member) 요청은 **401·403 외에는 기록하지 않는다(400·404·5xx 포함)** — 정보주체 본인
// 접속은 의무 밖이고 회원 IP를 2년 쥐는 것은 최소수집에 역행한다(Cloud Run 요청 로그 30일이
// 운영 목적을 덮는다). **거부(401·403)는 역할 무관 기록** — 오·남용 대응(§8②)의 핵심 신호다.
// /healthz·/health·/v1/public/*는 v1 클로저 밖(router.go)이라 이 미들웨어를 지나지 않는다.
//
// 접속지(remote_ip)의 신뢰: middleware.RealIP는 True-Client-IP → X-Real-IP → XFF **첫** 값 순으로
// RemoteAddr를 덮어쓰는데 셋 다 클라이언트가 지정할 수 있다(위조 가능). 프록시가 **덧붙인** 값은
// X-Forwarded-For의 **마지막** 값이므로 그것을 xff_last로 따로 싣는다 — Cloud Run 직결이면 GFE가
// 붙인 실제 피어 IP, Hosting 리라이트 경유면 끝값이 Hosting 프록시라 끝에서 둘째가 클라이언트다.
//
// 절대 기록하지 않는 것(accesslog_test.go가 못 박는다): 요청·응답 본문, Authorization·X-Dev-*
// 헤더값, 쿠키, 쿼리 문자열 원문(GET /v1/members?q=이름·번호가 들어온다 — 화이트리스트 `member`
// 값만 subject로 옮긴다), Principal.Phone(검증된 전화번호), 이름.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

// accessEntry — 한 요청의 접속기록 누적 버퍼. **포인터**로 컨텍스트에 심는다: auth.Middleware가
// r.WithContext로 파생 컨텍스트를 만들기 때문에(auth.go) 값으로 심으면 앞선 미들웨어(여기)가
// Principal을 볼 수 없다. auth가 resolve 직후 principal을 역주입하고, 본문에만 정보주체가 있는
// POST 핸들러는 setAccessSubject로 알려준다.
type accessEntry struct {
	principal     Principal
	resolved      bool   // auth가 Principal을 채웠는가(false = 401 경로)
	subjectMember string // 핸들러 훅이 알려준 정보주체(본문의 member_id)
}

type accessEntryKey struct{}

func accessEntryFrom(ctx context.Context) *accessEntry {
	e, _ := ctx.Value(accessEntryKey{}).(*accessEntry)
	return e
}

// setAccessSubject — 정보주체 식별자가 **본문에만** 있는 핸들러(예약·회원권·결제·계약·인바디…)가
// 디코드/생성 뒤 1줄로 부른다. 미들웨어가 본문을 읽지 않는 이유: '본문 기록 금지' 원칙과
// decodeJSON의 바디 소비가 충돌한다. 훅이 없어도 라인은 남는다(route·path로 수행업무는 확정) —
// 누락은 "덜 정확"일 뿐 조용한 실패가 아니다. 계약 v2.30 규약.
func setAccessSubject(ctx context.Context, memberID string) {
	if e := accessEntryFrom(ctx); e != nil && memberID != "" {
		e.subjectMember = memberID
	}
}

// WithAccessLogWriter — 접속기록 출력 주입(테스트는 bytes.Buffer). nil이면 os.Stdout.
// NewRouter 시그니처를 바꾸지 않으려고 Handlers에 싣는다(호출부 3곳 무변경).
func (h *Handlers) WithAccessLogWriter(w io.Writer) *Handlers {
	h.accessOut = w
	return h
}

func (h *Handlers) accessLogWriter() io.Writer {
	if h.accessOut != nil {
		return h.accessOut
	}
	return os.Stdout
}

// accessLine — 와이어(stdout) 스키마. 키 이름은 계약 v2.30에 고정돼 있다 — sink 필터
// (jsonPayload.log_type="access")와 점검 스크립트(access-log-review.sh)가 이 이름을 읽는다.
type accessLine struct {
	LogType   string `json:"log_type"`
	Severity  string `json:"severity"` // INFO | WARNING(401·403) | ERROR(5xx) — 항상 명시(Cloud Run 기본값에 기대지 않는다)
	Time      string `json:"time"`     // RFC3339Nano UTC → LogEntry.timestamp
	Message   string `json:"message"`
	RequestID string `json:"request_id"`
	// 식별자(취급자)
	UID      string `json:"uid"`
	Role     string `json:"role"`
	CenterID string `json:"center_id"`
	// 수행업무
	Method    string `json:"method"`
	Route     string `json:"route"`  // chi 패턴("/v1/members/{id}"); 미해석이면 "/v1/*"
	Path      string `json:"path"`   // 쿼리 제외
	Status    int    `json:"status"` // 응답 코드. 미기록(0)이면 타임아웃 504 / 그 외 500
	LatencyMS int64  `json:"latency_ms"`
	Bytes     int    `json:"bytes"`
	// 패닉으로 끊긴 요청(있을 때만 true). 헤더가 이미 나갔으면 status는 나간 값을 유지한다 —
	// 클라이언트가 받은 코드가 그것이고, 500으로 덮으면 점검 리포트가 "서버가 500을 줬다"는 거짓이 된다.
	Aborted bool `json:"aborted,omitempty"`
	// 접속지
	RemoteIP      string `json:"remote_ip"`                 // RealIP 결과: True-Client-IP → X-Real-IP → XFF 첫 값(셋 다 위조 가능)
	XForwardedFor string `json:"x_forwarded_for,omitempty"` // 원 헤더 전체(512자 클립) — remote_ip 교차 확인용
	XFFLast       string `json:"xff_last,omitempty"`        // XFF 마지막 값 = 프록시(GFE)가 덧붙인 값 — 신뢰 가능한 접속지
	UserAgent     string `json:"user_agent,omitempty"`      // 512자 클립
	// 처리한 정보주체
	Subject *accessSubject `json:"subject,omitempty"`
	// Cloud Run 요청 로그와의 상관 키(30일 안에서 httpRequest.remoteIp 등으로 교차 확인)
	Trace string `json:"logging.googleapis.com/trace,omitempty"`
}

type accessSubject struct {
	MemberID   string `json:"member_id,omitempty"`
	ResourceID string `json:"resource_id,omitempty"`
	StaffUID   string `json:"staff_uid,omitempty"`
}

// accessLog — 접속기록 미들웨어. v1 클로저 안, **auth.Middleware보다 앞**에 선다(401을 기록하기
// 위해). project는 trace 필드 접두("projects/<id>/traces/…")에만 쓰인다 — 비어 있으면(로컬) 생략.
func accessLog(project string, out io.Writer) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			e := &accessEntry{}
			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
			start := time.Now()
			r = r.WithContext(context.WithValue(r.Context(), accessEntryKey{}, e))
			defer func() {
				if rec := recover(); rec != nil {
					// 패닉도 접속이다. 여기서 잡지 않으면 ww.Status()가 0이라 500 라인이 남지 않는다.
					// 라인을 쓴 뒤 **같은 값으로 다시 panic**한다 — 바깥 recoverJSON(health.go)이
					// 계약 포맷 500 + 스택 로그를 만든다(그 책임을 여기로 옮기지 않는다).
					writeAccessLine(out, project, r, ww, e, start, true)
					panic(rec)
				}
				writeAccessLine(out, project, r, ww, e, start, false)
			}()
			next.ServeHTTP(ww, r)
		})
	}
}

// writeAccessLine — 기록 범위 판정 + 라인 조립 + 출력.
//
// status가 0(핸들러가 헤더를 안 씀)인 경우의 해석: 컨텍스트가 DeadlineExceeded면 chi Timeout이
// 이 defer **뒤**에 504를 쓸 것이므로 504, 아니면 500(패닉 포함). 패닉인데 헤더가 이미 나갔으면 그
// 값을 유지하고 aborted=true — recoverJSON이 그 경우 연결을 끊지 코드를 바꾸지 않는다(health.go).
// 패닉은 status와 무관하게 ERROR — 응답 코드가 200이어도 서버 실패다.
func writeAccessLine(out io.Writer, project string, r *http.Request, ww middleware.WrapResponseWriter,
	e *accessEntry, start time.Time, panicked bool) {
	status := ww.Status()
	if status == 0 {
		if !panicked && errors.Is(r.Context().Err(), context.DeadlineExceeded) {
			status = http.StatusGatewayTimeout
		} else {
			status = http.StatusInternalServerError
		}
	}
	p := e.principal
	denied := status == http.StatusUnauthorized || status == http.StatusForbidden
	// 스태프 전부 + 미인증(401 경로) + 역할 무관 거부. 회원 요청은 401·403 외(400·404·5xx 포함) 여기서 빠진다.
	if !(p.IsStaff() || p.IsSuperadmin() || !e.resolved || denied) {
		return
	}

	severity := "INFO"
	switch {
	case status >= 500 || panicked:
		severity = "ERROR"
	case denied:
		severity = "WARNING"
	}

	route := "/v1/*"
	subject := &accessSubject{}
	if rctx := chi.RouteContext(r.Context()); rctx != nil {
		if pat := rctx.RoutePattern(); pat != "" {
			route = pat
		}
		// URLParam은 응답 뒤에도 RouteContext에 남아 있다(chi v5.2.1 실측).
		if id := rctx.URLParam("id"); id != "" {
			if strings.Contains(route, "/members/{id}") {
				subject.MemberID = id
			} else {
				subject.ResourceID = id
			}
		}
		if uid := rctx.URLParam("uid"); uid != "" {
			subject.StaffUID = uid
		}
	}
	// 쿼리는 화이트리스트 `member`만 — 원문(q=이름·번호)은 절대 싣지 않는다.
	if m := r.URL.Query().Get("member"); m != "" {
		subject.MemberID = m
	}
	if e.subjectMember != "" {
		subject.MemberID = e.subjectMember
	}
	if *subject == (accessSubject{}) {
		subject = nil
	}

	uid := p.UID
	if uid == "" {
		uid = "-"
	}
	line := accessLine{
		LogType:       "access",
		Severity:      severity,
		Time:          start.UTC().Format(time.RFC3339Nano),
		Message:       fmt.Sprintf("access %s %s %s %d", uid, r.Method, route, status),
		RequestID:     middleware.GetReqID(r.Context()),
		UID:           p.UID,
		Role:          p.Role,
		CenterID:      p.CenterID,
		Method:        r.Method,
		Route:         route,
		Path:          r.URL.Path,
		Status:        status,
		LatencyMS:     time.Since(start).Milliseconds(),
		Bytes:         ww.BytesWritten(),
		Aborted:       panicked,
		RemoteIP:      remoteIP(r.RemoteAddr),
		XForwardedFor: clip(r.Header.Get("X-Forwarded-For"), maxHeaderChars),
		XFFLast:       xffLast(r.Header.Get("X-Forwarded-For")),
		UserAgent:     clip(r.Header.Get("User-Agent"), maxHeaderChars),
		Subject:       subject,
		Trace:         traceField(project, r.Header.Get("X-Cloud-Trace-Context")),
	}
	b, err := json.Marshal(line)
	if err != nil {
		// 구조체 마샬은 실패할 수 없지만, 만약 실패해도 접속기록 때문에 요청을 죽이지 않는다.
		fmt.Fprintf(os.Stderr, `{"severity":"ERROR","message":"access log marshal: %v"}`+"\n", err)
		return
	}
	fmt.Fprintln(out, string(b))
}

// maxHeaderChars — 클라이언트가 채우는 헤더(XFF·UA)를 라인에 싣는 상한. 2년 버킷에 KB 단위 헤더를
// 요청마다 쌓게 두면 저장·점검 비용이 공격자 손에 있게 된다. 초과분은 "…"로 표시해 잘렸음을 남긴다.
const maxHeaderChars = 512

// clip — s를 최대 n 문자(룬)로 자르고 잘렸으면 접미 "…"를 붙인다. 바이트가 아니라 룬 단위인 이유:
// 멀티바이트 문자 중간에서 자르면 깨진 UTF-8이 되어 Cloud Logging이 라인 전체를 textPayload로 떨어뜨린다.
func clip(s string, n int) string {
	if len(s) <= n {
		return s
	}
	rs := []rune(s)
	if len(rs) <= n {
		return s
	}
	return string(rs[:n]) + "…"
}

// xffLast — X-Forwarded-For의 마지막 값(공백 제거). 프록시는 자신이 본 피어 IP를 **끝에** 덧붙이므로
// 마지막 값만이 클라이언트가 못 만든 값이다. 헤더가 없으면 "" → 필드 생략.
func xffLast(xff string) string {
	if xff == "" {
		return ""
	}
	i := strings.LastIndex(xff, ",")
	return strings.TrimSpace(xff[i+1:])
}

// remoteIP — middleware.RealIP는 XFF/X-Real-IP가 있을 때만 RemoteAddr를 IP로 바꾼다; 없으면
// "ip:port" 그대로다. 접속지 정보는 IP만 남긴다(포트는 점검 집계에 잡음이고 식별 가치가 없다).
func remoteIP(addr string) string {
	if host, _, err := net.SplitHostPort(addr); err == nil {
		return host
	}
	return addr
}

// traceField — "TRACE_ID/SPAN_ID;o=1" 헤더에서 TRACE_ID만 떼어 Cloud Logging 상관 키를 만든다.
// project가 비어 있으면(로컬·테스트) 필드를 생략한다 — 잘못된 접두는 상관을 못 맺을 뿐 아니라
// 다른 프로젝트의 trace를 가리키는 거짓 링크가 된다.
func traceField(project, header string) string {
	if project == "" || header == "" {
		return ""
	}
	id, _, _ := strings.Cut(header, "/")
	if id == "" {
		return ""
	}
	return "projects/" + project + "/traces/" + id
}
