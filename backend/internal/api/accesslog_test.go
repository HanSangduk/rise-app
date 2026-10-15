package api

// 접속기록(accesslog.go, v2.30 · P61)의 계약 테스트 — 「개인정보의 안전성 확보조치 기준」 §8.
// "미들웨어가 있다"가 아니라 **stdout에 무엇이 남고 무엇이 절대 남지 않는가**를 고정한다:
// 취급자·정보주체·수행업무 5요소가 실리지 않으면 고시 §2의 접속기록이 아니고, 본문·토큰·쿼리
// 원문이 실리면 "기록하지 않는 것" 약속이 거짓이 된다.

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/ramsang/rise-backend/internal/config"
	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// newAccessLogRouter — 실제 라우터 + 접속기록을 버퍼로 받는 조립(resilience_test.go 스타일).
func newAccessLogRouter(t *testing.T, cfg config.Config) (http.Handler, *bytes.Buffer, store.Store) {
	t.Helper()
	st := store.NewMemory()
	if cfg.DefaultCenterID == "" {
		cfg.DefaultCenterID = testCenter
	}
	auth, err := NewAuthenticator(context.Background(), cfg, st)
	if err != nil {
		t.Fatalf("NewAuthenticator: %v", err)
	}
	var buf bytes.Buffer
	h := NewHandlers(NewService(st, cfg, auth.Provisioner(testInitialPassword))).WithAccessLogWriter(&buf)
	return NewRouter(h, auth, nil), &buf, st
}

// accessLines — 버퍼의 JSON 라인을 전부 파싱한다(한 줄이라도 깨져 있으면 실패 — Cloud Logging은
// 깨진 줄을 textPayload로 떨어뜨려 sink 필터에서 조용히 빠진다).
func accessLines(t *testing.T, buf *bytes.Buffer) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, ln := range strings.Split(strings.TrimSpace(buf.String()), "\n") {
		if ln == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(ln), &m); err != nil {
			t.Fatalf("접속기록 라인이 JSON이 아니다(%v): %s", err, ln)
		}
		out = append(out, m)
	}
	return out
}

func alReq(r http.Handler, method, path, uid, role, body string, hdr map[string]string) *httptest.ResponseRecorder {
	var rd *strings.Reader
	if body != "" {
		rd = strings.NewReader(body)
	} else {
		rd = strings.NewReader("")
	}
	req := httptest.NewRequest(method, path, rd)
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if uid != "" {
		req.Header.Set("X-Dev-Uid", uid)
		req.Header.Set("X-Dev-Role", role)
	}
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

// 고시 §2 정의의 5요소(식별자·접속일시·접속지·처리한 정보주체·수행업무)가 한 줄에 전부 실린다.
func TestAccessLogRecordsStaffRequest(t *testing.T) {
	r, buf, _ := newAccessLogRouter(t, config.Config{})
	rec := alReq(r, http.MethodPut, "/v1/members/m1", "owner1", domain.RoleOwner, `{"name":"x"}`, nil)

	lines := accessLines(t, buf)
	if len(lines) != 1 {
		t.Fatalf("라인 수=%d, want 1 — 스태프 요청은 성공·실패 무관 정확히 한 줄이다: %s", len(lines), buf.String())
	}
	l := lines[0]
	want := map[string]any{
		"log_type": "access", "severity": "INFO", "uid": "owner1", "role": domain.RoleOwner,
		"center_id": testCenter, "method": http.MethodPut, "route": "/v1/members/{id}", "path": "/v1/members/m1",
	}
	for k, v := range want {
		if l[k] != v {
			t.Errorf("%s=%v, want %v", k, l[k], v)
		}
	}
	if int(l["status"].(float64)) != rec.Code {
		t.Errorf("status=%v, want 응답 코드 %d — 응답과 다른 status는 점검 리포트를 거짓으로 만든다", l["status"], rec.Code)
	}
	if l["request_id"] == "" || l["request_id"] == nil {
		t.Errorf("request_id가 비었다 — Cloud Run 요청 로그·auth reject 로그와 이어 붙일 키가 없다")
	}
	if _, err := time.Parse(time.RFC3339Nano, l["time"].(string)); err != nil {
		t.Errorf("time=%v: RFC3339Nano가 아니면 LogEntry.timestamp로 승격되지 않는다: %v", l["time"], err)
	}
	subj, _ := l["subject"].(map[string]any)
	if subj["member_id"] != "m1" {
		t.Errorf("subject.member_id=%v, want m1 — path의 회원 id가 '처리한 정보주체'다", subj["member_id"])
	}
	if ip, _ := l["remote_ip"].(string); ip == "" || strings.Contains(ip, ":") {
		t.Errorf("remote_ip=%q — '접속지 정보'는 §2 필수 요소이고 포트 없는 IP여야 한다(XFF 없으면 RealIP가 ip:port를 그대로 둔다)", ip)
	}
}

// 절대 기록하지 않는 것: 본문(이름·번호)·Authorization·X-Dev-* 값·쿼리 원문(q=).
func TestAccessLogNeverContainsSecretsOrBody(t *testing.T) {
	r, buf, _ := newAccessLogRouter(t, config.Config{})
	hdr := map[string]string{"Authorization": "Bearer SECRET-TOKEN-XYZ", "Cookie": "session=COOKIE-SECRET"}
	alReq(r, http.MethodPost, "/v1/members", "owner1", domain.RoleOwner,
		`{"name":"김민지","phone":"010-1234-5678","status":"active"}`, hdr)
	alReq(r, http.MethodGet, "/v1/members?q=010-1234-5678&member=m9", "owner1", domain.RoleOwner, "", hdr)

	if len(accessLines(t, buf)) != 2 {
		t.Fatalf("라인 수가 2가 아니다: %s", buf.String())
	}
	out := buf.String()
	for _, forbidden := range []string{"SECRET-TOKEN", "COOKIE-SECRET", "010-1234", "김민지", "q=", "X-Dev"} {
		if strings.Contains(out, forbidden) {
			t.Errorf("접속기록에 %q가 실렸다 — 본문·토큰·쿠키·쿼리 원문은 2년 보관 대상이 아니다: %s", forbidden, out)
		}
	}
	// 화이트리스트 `member`만 subject로 옮겨진다 — 같은 쿼리 문자열에서 q=는 버리고 member=는 남긴다.
	if !strings.Contains(out, `"member_id":"m9"`) {
		t.Errorf("?member= 값이 subject.member_id로 옮겨지지 않았다: %s", out)
	}
}

// v1 클로저 밖 경로(헬스·공개)는 접속기록 대상이 아니다 — 누군가 공개 경로를 클로저 안으로
// 옮기면 여기가 깨진다(그때는 무인증 표면의 IP를 2년 쥐게 된다는 뜻이다).
func TestAccessLogSkipsUnauthenticatedSurface(t *testing.T) {
	r, buf, _ := newAccessLogRouter(t, config.Config{})
	for _, p := range []string{"/healthz", "/health", "/api/health", "/v1/public/business", "/v1/public/center",
		"/api/v1/public/business", "/api/v1/public/center"} {
		alReq(r, http.MethodGet, p, "", "", "", nil)
	}
	if buf.Len() != 0 {
		t.Fatalf("무인증 표면이 접속기록에 남았다: %s", buf.String())
	}
}

// 거부는 역할 무관 기록 — 401(auth 앞에 서 있어야만 가능)·superadmin 경계 403.
func TestAccessLogRecordsDenials(t *testing.T) {
	r, buf, _ := newAccessLogRouter(t, config.Config{})
	if rec := alReq(r, http.MethodGet, "/v1/me", "", "", "", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("무인증 /v1/me = %d, want 401", rec.Code)
	}
	if rec := alReq(r, http.MethodGet, "/v1/members", "sa1", domain.RoleSuperadmin, "", nil); rec.Code != http.StatusForbidden {
		t.Fatalf("superadmin /v1/members = %d, want 403", rec.Code)
	}
	lines := accessLines(t, buf)
	if len(lines) != 2 {
		t.Fatalf("라인 수=%d, want 2: %s", len(lines), buf.String())
	}
	l401 := lines[0]
	if l401["status"].(float64) != 401 || l401["severity"] != "WARNING" || l401["uid"] != "" {
		t.Errorf("401 라인: status=%v severity=%v uid=%v — 거부는 WARNING·uid 없음으로 남아야 한다", l401["status"], l401["severity"], l401["uid"])
	}
	if l401["path"] != "/v1/me" {
		t.Errorf("401 라인 path=%v, want /v1/me — 라우팅 전 거부라 route는 /v1/*이므로 path가 유일한 단서", l401["path"])
	}
	l403 := lines[1]
	if l403["status"].(float64) != 403 || l403["severity"] != "WARNING" || l403["uid"] != "sa1" || l403["role"] != domain.RoleSuperadmin {
		t.Errorf("403 라인: %v — superadmin 경계 위반은 uid·role과 함께 WARNING으로 남아야 한다", l403)
	}
}

// §8① "정보주체는 제외한다" — 회원 본인의 정상 요청은 기록하지 않는다. 거부는 예외.
func TestAccessLogOmitsMemberSelfAccess(t *testing.T) {
	r, buf, st := newAccessLogRouter(t, config.Config{})
	if err := st.SaveUserIndex(context.Background(), &store.UserIndex{
		UID: "u-member1", Role: domain.RoleMember, CenterID: testCenter, MemberID: "member1",
	}); err != nil {
		t.Fatal(err)
	}
	if rec := alReq(r, http.MethodGet, "/v1/me", "u-member1", domain.RoleMember, "", nil); rec.Code != http.StatusOK {
		t.Fatalf("회원 /v1/me = %d, want 200", rec.Code)
	}
	if buf.Len() != 0 {
		t.Fatalf("회원의 정상 요청이 접속기록에 남았다 — 정보주체 본인 접속은 §8① 의무 밖이고 최소수집 위반: %s", buf.String())
	}
	// 회원의 404(라우트 없음)도 기록하지 않는다 — 회원은 401·403 **외에는** 전부 제외(400·404·5xx 포함).
	// 404를 기록하면 잘못 친 URL마다 회원 IP가 2년 남는다.
	if rec := alReq(r, http.MethodGet, "/v1/does-not-exist", "u-member1", domain.RoleMember, "", nil); rec.Code != http.StatusNotFound {
		t.Fatalf("회원 GET /v1/does-not-exist = %d, want 404", rec.Code)
	}
	if buf.Len() != 0 {
		t.Fatalf("회원의 404가 접속기록에 남았다 — 회원은 401·403 외 기록 대상이 아니다: %s", buf.String())
	}
	// 회원이 스태프 전용 쓰기를 치면 403 — 이건 오·남용 신호라 기록한다.
	rec := alReq(r, http.MethodPost, "/v1/staff", "u-member1", domain.RoleMember, `{"name":"x","email":"x@x.kr","role":"trainer"}`, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("회원 POST /v1/staff = %d, want 403", rec.Code)
	}
	lines := accessLines(t, buf)
	if len(lines) != 1 || lines[0]["status"].(float64) != 403 || lines[0]["role"] != domain.RoleMember {
		t.Fatalf("회원의 403이 기록되지 않았다(거부는 역할 무관): %s", buf.String())
	}
}

// 회원의 429(빈도 제한, v2.38)는 403과 같은 오·남용 신호라 기록한다 — 앞선 15번(400/403)은 회원
// 규칙대로 빠지고, 제한에 걸린 16번째 한 줄만 WARNING으로 남는다.
func TestAccessLogRecordsMemberRateLimited(t *testing.T) {
	r, buf, st := newAccessLogRouter(t, config.Config{})
	if err := st.SaveUserIndex(context.Background(), &store.UserIndex{
		UID: "u-member1", Role: domain.RoleMember, CenterID: testCenter, MemberID: "member1",
	}); err != nil {
		t.Fatal(err)
	}
	var last int
	for i := 0; i < 16; i++ {
		last = alReq(r, http.MethodPost, "/v1/consult-requests", "u-member1", domain.RoleMember, "", nil).Code
	}
	if last != http.StatusTooManyRequests {
		t.Fatalf("16번째 = %d, want 429(burst 15)", last)
	}
	lines := accessLines(t, buf)
	if len(lines) != 1 {
		t.Fatalf("라인 수 = %d, want 1(429 한 줄만 — 앞선 400/403은 회원 규칙대로 제외): %s", len(lines), buf.String())
	}
	l := lines[0]
	if l["status"].(float64) != 429 || l["severity"] != "WARNING" || l["uid"] != "u-member1" || l["role"] != domain.RoleMember {
		t.Errorf("429 라인: %v — uid·role과 함께 WARNING으로 남아야 한다", l)
	}
}

// /api/v1 미러 마운트(P07)가 기록 우회 뒷문이 되지 않는다(TestAPIPrefixMirror 계열).
func TestAccessLogMirrorPaths(t *testing.T) {
	r, buf, _ := newAccessLogRouter(t, config.Config{})
	alReq(r, http.MethodPut, "/api/v1/members/m1", "owner1", domain.RoleOwner, `{"name":"x"}`, nil)
	lines := accessLines(t, buf)
	if len(lines) != 1 {
		t.Fatalf("미러 경로 라인 수=%d, want 1: %s", len(lines), buf.String())
	}
	if lines[0]["route"] != "/api/v1/members/{id}" || lines[0]["path"] != "/api/v1/members/m1" {
		t.Errorf("route=%v path=%v — 미러도 완전 패턴으로 남아야 점검 리포트가 두 마운트를 같은 업무로 집계한다", lines[0]["route"], lines[0]["path"])
	}
	if subj, _ := lines[0]["subject"].(map[string]any); subj["member_id"] != "m1" {
		t.Errorf("미러 경로의 subject.member_id=%v, want m1", subj["member_id"])
	}
}

// 정보주체가 본문에만 있는 POST(예약·회원 생성)도 setAccessSubject 훅으로 정보주체를 남긴다.
func TestAccessLogSubjectFromBodyViaHook(t *testing.T) {
	r, buf, _ := newAccessLogRouter(t, config.Config{})
	memberOf := func(rec *httptest.ResponseRecorder) string {
		t.Helper()
		lines := accessLines(t, buf)
		buf.Reset()
		if len(lines) != 1 {
			t.Fatalf("라인 수=%d, want 1", len(lines))
		}
		subj, _ := lines[0]["subject"].(map[string]any)
		id, _ := subj["member_id"].(string)
		return id
	}

	staffRec := alReq(r, http.MethodPost, "/v1/staff", "owner1", domain.RoleOwner,
		`{"name":"김태오","email":"taeo@rise.kr","role":"trainer"}`, nil)
	if staffRec.Code != http.StatusCreated {
		t.Fatalf("POST /v1/staff = %d %s", staffRec.Code, staffRec.Body.String())
	}
	var staff map[string]any
	_ = json.Unmarshal(staffRec.Body.Bytes(), &staff)
	trainerUID, _ := staff["uid"].(string)
	buf.Reset()

	// CreateMember — 본문에 id가 없고 응답의 id가 정보주체다.
	memRec := alReq(r, http.MethodPost, "/v1/members", "owner1", domain.RoleOwner,
		fmt.Sprintf(`{"name":"김민지","phone":"010-1111-2222","trainer_id":%q,"status":"active"}`, trainerUID), nil)
	if memRec.Code != http.StatusOK {
		t.Fatalf("POST /v1/members = %d %s", memRec.Code, memRec.Body.String())
	}
	var mem map[string]any
	_ = json.Unmarshal(memRec.Body.Bytes(), &mem)
	memberID, _ := mem["id"].(string)
	if got := memberOf(memRec); got != memberID {
		t.Errorf("POST /v1/members 라인의 subject.member_id=%q, want 생성된 id %q", got, memberID)
	}

	kst := time.Now().In(domain.KST)
	passRec := alReq(r, http.MethodPost, "/v1/passes", "owner1", domain.RoleOwner, fmt.Sprintf(
		`{"member_id":%q,"trainer_id":%q,"product":"PT 10회","paid_amount":550000,"total_sessions":10,"valid_from":%q,"valid_until":%q}`,
		memberID, trainerUID, kst.AddDate(0, 0, -1).Format("2006-01-02"), kst.AddDate(0, 0, 90).Format("2006-01-02")), nil)
	if passRec.Code != http.StatusOK {
		t.Fatalf("POST /v1/passes = %d %s", passRec.Code, passRec.Body.String())
	}
	var pass map[string]any
	_ = json.Unmarshal(passRec.Body.Bytes(), &pass)
	if got := memberOf(passRec); got != memberID {
		t.Errorf("POST /v1/passes 라인의 subject.member_id=%q, want %q", got, memberID)
	}

	bkRec := alReq(r, http.MethodPost, "/v1/bookings", "owner1", domain.RoleOwner, fmt.Sprintf(
		`{"slot_key":%q,"member_id":%q,"pass_id":%q}`, slotKeyDaysAhead(5, 15), memberID, pass["id"]), nil)
	if bkRec.Code != http.StatusOK && bkRec.Code != http.StatusCreated {
		t.Fatalf("POST /v1/bookings = %d %s", bkRec.Code, bkRec.Body.String())
	}
	if got := memberOf(bkRec); got != memberID {
		t.Errorf("POST /v1/bookings 라인의 subject.member_id=%q, want %q — 본문에만 있는 정보주체를 훅이 옮겨야 한다", got, memberID)
	}
}

// 패닉도 접속이다 — 500·ERROR 라인이 남고, 같은 값으로 다시 패닉해 바깥 recoverJSON이 계약 포맷
// 500을 만든다(재패닉을 지우면 응답이 빈 200이 되어 TestRecoverJSONKeepsContractFormat의 약속이
// 접속기록 뒤에서 깨진다).
func TestAccessLogSurvivesPanic(t *testing.T) {
	st := store.NewMemory()
	cfg := config.Config{DefaultCenterID: testCenter}
	auth, err := NewAuthenticator(context.Background(), cfg, st)
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	// 테스트 전용 라우터: 운영 라우터와 같은 미들웨어 계층(RequestID → recoverJSON → v1 클로저의
	// accessLog → auth)에 패닉 핸들러만 얹는다. NewRouter에 테스트 경로를 넣지 않기 위해서다.
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(recoverJSON)
	r.Route("/v1", func(r chi.Router) {
		r.Use(accessLog("", &buf))
		r.Use(auth.Middleware)
		r.Get("/boom", func(http.ResponseWriter, *http.Request) { panic("boom") })
	})

	rec := alReq(r, http.MethodGet, "/v1/boom", "owner1", domain.RoleOwner, "", nil)
	if rec.Code != http.StatusInternalServerError || !strings.Contains(rec.Body.String(), `"error"`) {
		t.Fatalf("패닉 응답 = %d %q, want 계약 포맷 500 — accessLog가 패닉을 삼키면 recoverJSON이 못 본다", rec.Code, rec.Body.String())
	}
	lines := accessLines(t, &buf)
	if len(lines) != 1 {
		t.Fatalf("패닉 요청의 라인 수=%d, want 1: %s", len(lines), buf.String())
	}
	if lines[0]["status"].(float64) != 500 || lines[0]["severity"] != "ERROR" || lines[0]["uid"] != "owner1" {
		t.Errorf("패닉 라인 %v — status 500·severity ERROR·uid가 남아야 '실패한 접근'도 접속기록이 된다", lines[0])
	}
	if lines[0]["route"] != "/v1/boom" {
		t.Errorf("route=%v, want /v1/boom — 패닉 뒤에도 RouteContext는 살아 있다", lines[0]["route"])
	}
}

// Cloud Run 요청 로그와의 상관 키 형식 — project가 있을 때만 "projects/<id>/traces/<trace>".
func TestAccessLogTraceField(t *testing.T) {
	const key = "logging.googleapis.com/trace"
	hdr := map[string]string{"X-Cloud-Trace-Context": "abc123/456;o=1"}

	r, buf, _ := newAccessLogRouter(t, config.Config{GCPProject: "rize-218c1"})
	alReq(r, http.MethodGet, "/v1/me", "owner1", domain.RoleOwner, "", hdr)
	lines := accessLines(t, buf)
	if len(lines) != 1 || lines[0][key] != "projects/rize-218c1/traces/abc123" {
		t.Fatalf("trace=%v, want projects/rize-218c1/traces/abc123 — SPAN_ID·옵션은 떼어야 요청 로그와 맺힌다", lines[0][key])
	}

	// 로컬(project 없음)에서는 필드 자체가 없다 — 잘못된 접두는 다른 프로젝트의 trace를 가리키는 거짓 링크다.
	r2, buf2, _ := newAccessLogRouter(t, config.Config{})
	alReq(r2, http.MethodGet, "/v1/me", "owner1", domain.RoleOwner, "", hdr)
	lines2 := accessLines(t, buf2)
	if _, present := lines2[0][key]; present {
		t.Fatalf("project 없이 trace 필드가 실렸다: %v", lines2[0][key])
	}
}

// 5xx는 ERROR — 패닉이 아닌 500(writeErr 기본 분기)도 같은 severity로 남는다.
func TestAccessLogSeverityByStatus(t *testing.T) {
	cases := []struct {
		status int
		want   string
	}{{200, "INFO"}, {404, "INFO"}, {401, "WARNING"}, {403, "WARNING"}, {429, "WARNING"}, {500, "ERROR"}, {503, "ERROR"}}
	for _, tc := range cases {
		var buf bytes.Buffer
		h := accessLog("", &buf)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if e := accessEntryFrom(r.Context()); e != nil {
				e.principal, e.resolved = Principal{UID: "owner1", Role: domain.RoleOwner}, true
			}
			w.WriteHeader(tc.status)
		}))
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/x", nil))
		lines := accessLines(t, &buf)
		if len(lines) != 1 || lines[0]["severity"] != tc.want {
			t.Errorf("status %d: severity=%v, want %s", tc.status, lines[0]["severity"], tc.want)
		}
	}
}

// remote_ip는 위조 가능(RealIP가 X-Real-IP를 XFF보다 먼저 믿는다)하고, 신뢰할 값은 프록시가 끝에
// 덧붙인 XFF 마지막 값(xff_last)이다 — 점검자가 remote_ip만 보고 접속지를 단정하지 않도록 둘을 함께 싣는다.
func TestAccessLogRemoteIPSpoofableXFFLastTrusted(t *testing.T) {
	r, buf, _ := newAccessLogRouter(t, config.Config{})
	alReq(r, http.MethodGet, "/v1/me", "owner1", domain.RoleOwner, "", map[string]string{
		"X-Real-IP":       "6.6.6.6",
		"X-Forwarded-For": "1.1.1.1, 203.0.113.9 , 35.191.0.1",
	})
	lines := accessLines(t, buf)
	if len(lines) != 1 {
		t.Fatalf("라인 수=%d, want 1: %s", len(lines), buf.String())
	}
	if lines[0]["remote_ip"] != "6.6.6.6" {
		t.Errorf("remote_ip=%v, want 6.6.6.6 — RealIP는 클라이언트가 보낸 X-Real-IP를 그대로 믿는다(위조 가능이 실측이어야 문서가 참)", lines[0]["remote_ip"])
	}
	if lines[0]["xff_last"] != "35.191.0.1" {
		t.Errorf("xff_last=%v, want 35.191.0.1 — 프록시가 덧붙인 마지막 값(공백 제거)만이 신뢰할 접속지다", lines[0]["xff_last"])
	}
	if lines[0]["x_forwarded_for"] != "1.1.1.1, 203.0.113.9 , 35.191.0.1" {
		t.Errorf("x_forwarded_for=%v — 원 헤더 전체는 교차 확인용으로 그대로 남는다", lines[0]["x_forwarded_for"])
	}

	// XFF가 없으면 xff_last 필드 자체가 없다(빈 문자열을 "신뢰 IP 없음"과 구분하지 않게 생략).
	buf.Reset()
	alReq(r, http.MethodGet, "/v1/me", "owner1", domain.RoleOwner, "", nil)
	lines = accessLines(t, buf)
	if _, present := lines[0]["xff_last"]; present {
		t.Errorf("XFF 없이 xff_last가 실렸다: %v", lines[0]["xff_last"])
	}
}

// 핸들러가 타임아웃으로 아무 것도 못 쓰면(status 0) 라인은 504·ERROR — chi Timeout이 accessLog **뒤**에
// 504를 쓰기 때문에 ww.Status()는 0이고, 이를 500으로 적으면 "서버 버그"와 "느린 의존성"이 섞인다.
func TestAccessLogTimeoutIs504(t *testing.T) {
	var buf bytes.Buffer
	r := chi.NewRouter()
	r.Use(middleware.Timeout(20 * time.Millisecond))
	r.Use(accessLog("", &buf))
	r.Get("/v1/slow", func(w http.ResponseWriter, req *http.Request) {
		if e := accessEntryFrom(req.Context()); e != nil {
			e.principal, e.resolved = Principal{UID: "owner1", Role: domain.RoleOwner}, true
		}
		<-req.Context().Done() // 컨텍스트를 존중하는 핸들러 — 데드라인이 지나면 헤더를 안 쓰고 돌아간다
	})
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/slow", nil))
	if rec.Code != http.StatusGatewayTimeout {
		t.Fatalf("응답=%d, want 504(chi Timeout이 쓴다)", rec.Code)
	}
	lines := accessLines(t, &buf)
	if len(lines) != 1 || lines[0]["status"].(float64) != 504 || lines[0]["severity"] != "ERROR" {
		t.Fatalf("타임아웃 라인 %v — status 504·severity ERROR여야 한다", lines)
	}
	if _, present := lines[0]["aborted"]; present {
		t.Errorf("타임아웃은 패닉이 아니다 — aborted가 실리면 안 된다: %v", lines[0])
	}
}

// 200 헤더를 쓴 **뒤** 패닉하면 status는 200을 유지하고 aborted:true — 클라이언트가 받은 코드가 200이고
// recoverJSON은 그 경우 연결을 끊지 코드를 바꾸지 않는다(health.go). 500으로 덮으면 리포트가 거짓.
func TestAccessLogPanicAfterHeaderKeepsStatus(t *testing.T) {
	var buf bytes.Buffer
	h := accessLog("", &buf)(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if e := accessEntryFrom(req.Context()); e != nil {
			e.principal, e.resolved = Principal{UID: "owner1", Role: domain.RoleOwner}, true
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"partial":`))
		panic("boom after header")
	}))
	rec := httptest.NewRecorder()
	func() {
		defer func() {
			if rec := recover(); rec != "boom after header" {
				t.Fatalf("재패닉 값=%v, want 원래 값 — 바깥 recoverJSON이 받아야 한다", rec)
			}
		}()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/x", nil))
	}()
	lines := accessLines(t, &buf)
	if len(lines) != 1 {
		t.Fatalf("라인 수=%d, want 1: %s", len(lines), buf.String())
	}
	if lines[0]["status"].(float64) != 200 || lines[0]["aborted"] != true || lines[0]["severity"] != "ERROR" {
		t.Errorf("헤더 후 패닉 라인 %v — status 200 유지·aborted true·severity ERROR", lines[0])
	}
	if bytes, _ := lines[0]["bytes"].(float64); bytes == 0 {
		t.Errorf("bytes=0 — 부분 응답이 나갔다는 사실(잘린 바이트 수)이 남아야 한다")
	}
}

// 클라이언트가 채우는 헤더(XFF·UA)는 512자에서 자른다 — 2년 버킷의 라인 크기를 공격자가 정하게 두지 않는다.
func TestAccessLogClipsLongHeaders(t *testing.T) {
	r, buf, _ := newAccessLogRouter(t, config.Config{})
	longUA := strings.Repeat("a", 600) + "END"
	longXFF := strings.Repeat("1.2.3.4, ", 100) + "9.9.9.9"
	alReq(r, http.MethodGet, "/v1/me", "owner1", domain.RoleOwner, "", map[string]string{
		"User-Agent": longUA, "X-Forwarded-For": longXFF,
	})
	lines := accessLines(t, buf)
	ua, _ := lines[0]["user_agent"].(string)
	if !strings.HasSuffix(ua, "…") || len([]rune(ua)) != maxHeaderChars+1 || strings.Contains(ua, "END") {
		t.Errorf("user_agent 길이=%d(룬), 접미=%q — 512자 + '…'여야 한다", len([]rune(ua)), ua[len(ua)-3:])
	}
	xff, _ := lines[0]["x_forwarded_for"].(string)
	if !strings.HasSuffix(xff, "…") || len([]rune(xff)) != maxHeaderChars+1 {
		t.Errorf("x_forwarded_for 길이=%d(룬) — 512자 + '…'여야 한다", len([]rune(xff)))
	}
	if lines[0]["xff_last"] != "9.9.9.9" {
		t.Errorf("xff_last=%v, want 9.9.9.9 — 클립은 원 헤더 전체에만 적용되고 마지막 값은 온전히 남는다", lines[0]["xff_last"])
	}
	// 멀티바이트 경계: 한글 600자를 512자에서 잘라도 유효한 UTF-8(JSON 파싱이 이미 통과했다).
	buf.Reset()
	alReq(r, http.MethodGet, "/v1/me", "owner1", domain.RoleOwner, "", map[string]string{"User-Agent": strings.Repeat("가", 600)})
	ko, _ := accessLines(t, buf)[0]["user_agent"].(string)
	if len([]rune(ko)) != maxHeaderChars+1 || !strings.HasSuffix(ko, "…") {
		t.Errorf("멀티바이트 UA 클립 길이=%d(룬)", len([]rune(ko)))
	}
}
