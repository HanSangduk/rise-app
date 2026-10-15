package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/store"
)

// 요청 빈도 제한(v2.38, P74) — 버킷 산술·키 분리·429 계약·라우터 배선을 고정한다.

func TestRateLimiterBurstThenRefill(t *testing.T) {
	now := time.Date(2026, 9, 26, 12, 0, 0, 0, time.UTC)
	l := newRateLimiter(60, 3) // 초당 1 보충, 순간 3
	l.now = func() time.Time { return now }

	for i := 0; i < 3; i++ {
		if ok, _ := l.allow("k"); !ok {
			t.Fatalf("burst 안 %d번째가 거부됐다", i+1)
		}
	}
	ok, wait := l.allow("k")
	if ok {
		t.Fatal("burst를 다 쓴 뒤 4번째가 허용됐다")
	}
	if wait <= 0 || wait > time.Second {
		t.Errorf("다음 토큰까지 %v, want (0, 1s]", wait)
	}
	// 다른 키는 독립이다.
	if ok, _ := l.allow("other"); !ok {
		t.Error("다른 키가 같이 막혔다")
	}
	// 1초 뒤 토큰 1개가 돌아온다 — 딱 하나만.
	now = now.Add(time.Second)
	if ok, _ := l.allow("k"); !ok {
		t.Error("1초 뒤 보충된 토큰이 없다")
	}
	if ok, _ := l.allow("k"); ok {
		t.Error("1초에 토큰이 둘 이상 보충됐다")
	}
	// 오래 쉬어도 burst를 넘겨 쌓이지 않는다.
	now = now.Add(time.Hour)
	for i := 0; i < 3; i++ {
		if ok, _ := l.allow("k"); !ok {
			t.Fatalf("한 시간 뒤 burst %d번째가 거부됐다", i+1)
		}
	}
	if ok, _ := l.allow("k"); ok {
		t.Error("burst 상한을 넘겨 쌓였다")
	}
}

func TestRateLimiterGCDropsIdleBuckets(t *testing.T) {
	now := time.Date(2026, 9, 26, 12, 0, 0, 0, time.UTC)
	l := newRateLimiter(60, 3)
	l.now = func() time.Time { return now }
	l.allow("a")
	l.allow("b")
	now = now.Add(11 * time.Minute)
	l.allow("c") // GC 트리거
	if _, ok := l.buckets["a"]; ok {
		t.Error("가득 찰 만큼 쉰 키가 주기 청소 뒤에도 남아 있다 — 메모리가 키 수만큼 자란다")
	}
	if _, ok := l.buckets["c"]; !ok {
		t.Error("방금 쓴 키가 지워졌다")
	}
}

// 청소는 제한 결과를 바꾸지 않는다: 가득 찰 만큼(burst/rate) 쉬지 않은 버킷은 남고(아직 제한 상태를
// 들고 있다), 그만큼 쉰 버킷만 지워진다 — 지워진 뒤의 새 버킷은 지워지지 않았을 버킷과 똑같이 동작한다.
func TestRateLimiterSweepKeepsLimitingState(t *testing.T) {
	now := time.Date(2026, 9, 26, 12, 0, 0, 0, time.UTC)
	l := newRateLimiter(60, 3) // 초당 1 보충 → idleTTL 3초
	l.now = func() time.Time { return now }
	l.gcEvery = 0 // 매 호출 청소 — 경계만 본다
	for i := 0; i < 3; i++ {
		l.allow("k")
	}
	now = now.Add(2 * time.Second)
	l.allow("x")
	if _, ok := l.buckets["k"]; !ok {
		t.Fatal("2초 쉰(아직 덜 찬) 버킷이 지워졌다 — 방금 burst를 다 쓴 키가 즉시 새 burst를 얻는다")
	}
	now = now.Add(time.Second)
	l.allow("x")
	if _, ok := l.buckets["k"]; ok {
		t.Fatal("3초(= burst/rate) 쉰 버킷이 남아 있다 — 새 버킷과 같은 상태라 지워야 메모리가 준다")
	}
	for i := 0; i < 3; i++ {
		if ok, _ := l.allow("k"); !ok {
			t.Fatalf("지워진 뒤 %d번째가 거부됐다 — 3초면 burst 3이 다 찼어야 한다", i+1)
		}
	}
	if ok, _ := l.allow("k"); ok {
		t.Error("지워진 뒤에도 burst를 넘겨 허용됐다")
	}
}

// 키 표 상한: 가득 차면 새 키는 추적 없이 통과(fail-open)하고, 이미 추적 중인 키의 제한은 그대로다.
// 강제 청소는 초당 1회로 묶이고, 통과 건수는 로그 한 줄로 남는다.
func TestRateLimiterBucketCapFailsOpen(t *testing.T) {
	now := time.Date(2026, 9, 26, 12, 0, 0, 0, time.UTC)
	l := newRateLimiter(60, 2) // idleTTL 2초
	l.now = func() time.Time { return now }
	l.maxBuckets = 3
	var logs []string
	l.logf = func(f string, a ...any) { logs = append(logs, fmt.Sprintf(f, a...)) }

	for _, k := range []string{"k1", "k2", "k3"} {
		l.allow(k)
	}
	if ok, _ := l.allow("k4"); !ok {
		t.Fatal("표가 가득 찬 뒤의 새 키가 거부됐다 — 공격 중 정상 신규 사용자가 429를 받는다")
	}
	if len(l.buckets) != 3 || l.untracked != 1 {
		t.Fatalf("buckets=%d untracked=%d, want 3·1 — 상한을 넘겨 추적했다", len(l.buckets), l.untracked)
	}
	// 추적 중인 키는 계속 제한된다(burst 2).
	if ok, _ := l.allow("k1"); !ok {
		t.Fatal("k1 두 번째가 거부됐다")
	}
	if ok, _ := l.allow("k1"); ok {
		t.Error("표가 가득 찼다고 추적 중인 키의 제한까지 풀렸다")
	}
	// 같은 순간 또 새 키 — 강제 청소는 초당 1회라 순회 없이 통과만 한다.
	l.allow("k5")
	if l.untracked != 2 {
		t.Errorf("untracked = %d, want 2", l.untracked)
	}
	// 2초 뒤(= idleTTL) 새 키 — 강제 청소가 쉰 버킷을 비우고 새 키를 추적한다. 통과 건수는 로그로.
	now = now.Add(2 * time.Second)
	l.allow("k6")
	if _, ok := l.buckets["k6"]; !ok {
		t.Error("강제 청소 뒤에도 새 키를 추적하지 않는다")
	}
	if len(logs) != 1 || !strings.Contains(logs[0], "2건") {
		t.Errorf("logs = %q, want 추적 없이 통과한 2건을 알리는 한 줄", logs)
	}
	if l.untracked != 0 {
		t.Errorf("로그 뒤 untracked = %d, want 0", l.untracked)
	}
}

// Retry-After는 올림이다 — 버림이면 초당 0.5 보충(분당 30)에서 1.98초 대기를 "1"로 알려, 그대로
// 따른 클라이언트가 두 번째 429를 받는다.
func TestRetryAfterRoundsUp(t *testing.T) {
	for _, tc := range []struct {
		wait time.Duration
		want int
	}{{1980 * time.Millisecond, 2}, {2 * time.Second, 2}, {2001 * time.Millisecond, 3}, {200 * time.Millisecond, 1}, {0, 1}} {
		if got := retryAfterSeconds(tc.wait); got != tc.want {
			t.Errorf("retryAfterSeconds(%v) = %d, want %d", tc.wait, got, tc.want)
		}
	}
	// 실제 분당 30 버킷에서: 알려 준 초만큼 기다리면 반드시 통과한다.
	now := time.Date(2026, 9, 26, 12, 0, 0, 0, time.UTC)
	l := newRateLimiter(30, 1)
	l.now = func() time.Time { return now }
	l.allow("k")
	now = now.Add(20 * time.Millisecond)
	ok, wait := l.allow("k")
	if ok {
		t.Fatal("burst 1을 쓴 직후가 허용됐다")
	}
	now = now.Add(time.Duration(retryAfterSeconds(wait)) * time.Second)
	if ok, _ := l.allow("k"); !ok {
		t.Errorf("Retry-After(%d초)만큼 기다렸는데 또 거부됐다", retryAfterSeconds(wait))
	}
}

func TestRateLimitMiddleware429Contract(t *testing.T) {
	l := newRateLimiter(60, 2)
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) })
	h := l.middleware(func(r *http.Request) string { return r.Header.Get("X-Key") })

	do := func(key string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/x", nil)
		req.Header.Set("X-Key", key)
		rr := httptest.NewRecorder()
		h(next).ServeHTTP(rr, req)
		return rr
	}
	if do("u1").Code != 204 || do("u1").Code != 204 {
		t.Fatal("burst 안 요청이 통과하지 않았다")
	}
	rr := do("u1")
	if rr.Code != http.StatusTooManyRequests {
		t.Fatalf("3번째 status = %d, want 429", rr.Code)
	}
	if rr.Header().Get("Retry-After") == "" {
		t.Error("Retry-After 헤더가 없다")
	}
	if rr.Header().Get("Cache-Control") != "no-store" {
		t.Error("429가 no-store가 아니다(writeJSON 규약)")
	}
	var body errBodyWithCode
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil || body.Code != codeRateLimited || body.Error == "" {
		t.Errorf("429 본문 = %s, want {error, code:%q}", rr.Body.String(), codeRateLimited)
	}
	// 키가 비면(판별 불가) 제한하지 않는다 — 제한기가 인증 실패의 원인이 되면 안 된다.
	for i := 0; i < 5; i++ {
		if do("").Code != 204 {
			t.Fatal("빈 키가 제한됐다")
		}
	}
}

// 라우터 배선: 무인증 공개 경로는 IP 키로, 회원발 쓰기는 uid 키로 실제 429가 난다. 두 마운트
// (/v1·/api/v1)가 같은 버킷을 나눠 쓴다.
func TestRouterRateLimitsPublicAndWriteRoutes(t *testing.T) {
	router := newResilienceRouter(t, store.NewMemory())

	hit := func(method, path, ip, uid, role string) int {
		req := httptest.NewRequest(method, path, nil)
		req.RemoteAddr = ip + ":12345"
		if uid != "" {
			req.Header.Set("X-Dev-Uid", uid)
			req.Header.Set("X-Dev-Role", role)
		}
		rr := httptest.NewRecorder()
		router.ServeHTTP(rr, req)
		return rr.Code
	}

	// 공개 경로: 순간 30 → 31번째부터 429. /v1과 /api/v1이 같은 버킷이다.
	var codes []int
	for i := 0; i < 31; i++ {
		path := "/v1/public/business"
		if i%2 == 1 {
			path = "/api/v1/public/business"
		}
		codes = append(codes, hit(http.MethodGet, path, "10.0.0.1", "", ""))
	}
	for i := 0; i < 30; i++ {
		if codes[i] == http.StatusTooManyRequests {
			t.Fatalf("공개 경로 %d번째가 이미 429다(burst 30이어야 한다)", i+1)
		}
	}
	if codes[30] != http.StatusTooManyRequests {
		t.Errorf("공개 경로 31번째 = %d, want 429", codes[30])
	}
	// 다른 IP는 영향 없다.
	if c := hit(http.MethodGet, "/v1/public/business", "10.0.0.2", "", ""); c == http.StatusTooManyRequests {
		t.Error("다른 IP가 같이 막혔다")
	}

	// 회원발 요청 큐 쓰기: 순간 15 → 16번째부터 429(본문이 비어 400이 나더라도 429보다 뒤가 아니다 —
	// 제한이 핸들러보다 먼저 선다). 무인증 공개 경로 버킷과 분리돼 있다.
	var last int
	for i := 0; i < 16; i++ {
		last = hit(http.MethodPost, "/v1/consult-requests", "10.0.0.1", "member-x", "member")
		if i < 15 && last == http.StatusTooManyRequests {
			t.Fatalf("쓰기 %d번째가 이미 429다(burst 15이어야 한다)", i+1)
		}
	}
	if last != http.StatusTooManyRequests {
		t.Errorf("쓰기 16번째 = %d, want 429", last)
	}
	// 제한에 안 걸린 다른 경로(조회)는 그대로 — 전 구간 제한이 아니다.
	if c := hit(http.MethodGet, "/v1/me", "10.0.0.1", "member-x", "member"); c == http.StatusTooManyRequests {
		t.Error("제한 대상이 아닌 GET /v1/me가 429다")
	}
	// 상호작용 쓰기(hw-check)는 별도 버킷(순간 40)이다 — 같은 uid가 요청 큐 버킷을 방금 다 썼어도,
	// 하루치 홈워크 15개 안팎을 한 번에 훑는 탭 수(POST 수)는 429 없이 지나간다.
	for i := 0; i < 25; i++ {
		if c := hit(http.MethodPost, "/v1/hw-checks", "10.0.0.1", "member-x", "member"); c == http.StatusTooManyRequests {
			t.Fatalf("hw-checks %d번째가 429다 — 상호작용 쓰기는 요청 큐 버킷(15)과 분리돼 순간 40이어야 한다", i+1)
		}
	}
	// 체크인은 hw-check와 같은 상호작용 버킷(순간 40)이다 — 다른 회원으로 41번째에 429.
	for i := 0; i < 41; i++ {
		c := hit(http.MethodPost, "/v1/checkin", "10.0.0.3", "member-y", "member")
		if i < 40 && c == http.StatusTooManyRequests {
			t.Fatalf("회원 체크인 %d번째가 이미 429다(burst 40이어야 한다)", i+1)
		}
		if i == 40 && c != http.StatusTooManyRequests {
			t.Errorf("회원 체크인 41번째 = %d, want 429", c)
		}
	}
	// 스태프는 세지 않는다 — 어드민 원탭 체크인이 같은 /checkin을 쓴다(데스크 몰아 누르기는 업무다).
	for i := 0; i < 60; i++ {
		if c := hit(http.MethodPost, "/v1/checkin", "10.0.0.4", "owner-z", "owner"); c == http.StatusTooManyRequests {
			t.Fatalf("스태프 체크인 %d번째가 429다 — 스태프 요청은 제한 대상이 아니다", i+1)
		}
	}
}

// 배선 전수(P74 감사 후속) — 위 시험은 경로 넷만 재서, 가입 3경로(대기실이 30초마다 부르는 join/match
// 포함)·공개 center 두 마운트에서 제한을 빼도 초록이었다. 경로마다 새 키를 써서 **그 경로의 배선만**
// 429를 낼 수 있게 한다. 같은 IP 뒤 회원 둘(센터 와이파이)·포트 떼기도 여기서 고정한다.
func TestRouterRateLimitWiringEveryRoute(t *testing.T) {
	router := newResilienceRouter(t, store.NewMemory())
	hit := func(method, path, remote, uid string) int {
		req := httptest.NewRequest(method, path, nil)
		req.RemoteAddr = remote
		if uid != "" {
			req.Header.Set("X-Dev-Uid", uid)
			req.Header.Set("X-Dev-Role", "member")
		}
		rr := httptest.NewRecorder()
		router.ServeHTTP(rr, req)
		return rr.Code
	}
	// burst+1번째가 429인지 — 그 앞은 429가 아니어야 한다.
	drains := func(t *testing.T, label string, burst int, do func() int) {
		t.Helper()
		for i := 0; i <= burst; i++ {
			c := do()
			if i < burst && c == http.StatusTooManyRequests {
				t.Fatalf("%s: %d번째가 이미 429다(burst %d)", label, i+1, burst)
			}
			if i == burst && c != http.StatusTooManyRequests {
				t.Errorf("%s: %d번째 = %d, want 429 — 이 경로에 제한이 배선돼 있지 않다", label, i+1, c)
			}
		}
	}

	// 회원발 요청 큐 4경로 — 경로마다 다른 회원(버킷은 넷이 나눠 쓰므로 키를 갈라야 경로별 배선이 보인다).
	for i, path := range []string{"/v1/join/match", "/v1/join/confirm", "/v1/join/request", "/v1/consult-requests"} {
		uid := fmt.Sprintf("queue-member-%d", i)
		drains(t, "POST "+path, 15, func() int { return hit(http.MethodPost, path, "10.1.0.1:1000", uid) })
	}
	// 공개 center — 두 마운트 각각(다른 IP로 버킷을 갈라 마운트별 배선을 본다).
	drains(t, "GET /v1/public/center", 30, func() int { return hit(http.MethodGet, "/v1/public/center", "10.2.0.1:1000", "") })
	drains(t, "GET /api/v1/public/center", 30, func() int { return hit(http.MethodGet, "/api/v1/public/center", "10.2.0.2:1000", "") })

	// 같은 IP 뒤 회원 둘은 서로 독립(uid 키) — 센터 와이파이 뒤 한 회원의 폭주가 옆 회원을 막지 않는다.
	drains(t, "member-a(공유 IP)", 15, func() int { return hit(http.MethodPost, "/v1/consult-requests", "10.3.0.1:1000", "shared-ip-a") })
	if c := hit(http.MethodPost, "/v1/consult-requests", "10.3.0.1:1000", "shared-ip-b"); c == http.StatusTooManyRequests {
		t.Error("같은 IP의 다른 회원이 같이 429를 받았다 — 회원 쓰기는 IP가 아니라 uid로 세야 한다")
	}

	// 직결 요청(RemoteAddr "host:port")은 포트를 뗀 IP로 센다 — 연결마다 포트가 달라도 한 버킷이다.
	port := 2000
	drains(t, "포트만 다른 같은 IP", 30, func() int {
		port++
		return hit(http.MethodGet, "/v1/public/business", fmt.Sprintf("10.4.0.1:%d", port), "")
	})
}
