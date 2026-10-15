package api

import (
	"log"
	"math"
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"
)

// ---- 요청 빈도 제한(v2.38, P74) ----
//
// 종전 미들웨어 체인(RequestID → RealIP → recover → Timeout → cors → accessLog → auth)에는 "같은
// 사람이 얼마나 자주 불러도 되는가"를 재는 층이 없었다. P55가 막은 것은 **같은 내용의 중복 제출**
// (멱등성)이고, 빈도는 다른 축이다: 상담 요청은 인증만 되면 무한히 쌓을 수 있었고, 무인증 공개
// 경로는 Hosting 경유(`/api/v1/public/*`, CDN 5분 캐시)와 달리 앱이 직접 부르는 Cloud Run URL
// (`/v1/public/*`)엔 완충이 전혀 없어 호출이 그대로 Firestore 읽기로 갔다.
//
// 프로세스 내 토큰 버킷이다 — 인스턴스가 여럿이면 상한이 인스턴스 수만큼 느슨해진다. 그래도
// "스크립트 한 대가 한 인스턴스를 분당 수백 번 때리는" 부류는 막고, 정상 사용(앱 자동 확인 30초·
// 센터 와이파이 뒤 회원 수십 명)은 burst가 흡수한다. 외부 의존성(golang.org/x/time/rate) 없이
// 100줄 남짓으로 충분하고, 정확한 분산 제한이 필요해지면 그때 Cloud Armor/Memorystore로 올린다.
//
// 키: 회원 요청은 uid(토큰 발급 주체 — 위조 불가), 무인증은 RealIP, 스태프는 세지 않는다
// (rateKeyMember). RealIP는 X-Forwarded-For 첫 값이라 클라이언트가 위조할 수 있다 — 그래서 무인증
// 경로의 제한은 "선의의 폭주 방지"이지 적대적 방어선이 아니고(App Check가 그 자리다 — work_log P74
// 후속), 위조 키가 메모리를 키우지 못하게 키 표에 상한을 둔다(maxBuckets).

type tokenBucket struct {
	tokens float64
	last   time.Time
}

type rateLimiter struct {
	mu      sync.Mutex
	buckets map[string]*tokenBucket
	rate    float64 // 초당 보충 토큰
	burst   float64 // 버킷 최대(= 순간 허용 연속 호출 수)
	now     func() time.Time
	logf    func(format string, args ...any)

	// 청소: 가득 찰 만큼(burst/rate) 쉰 버킷은 **새 버킷과 동작이 같다**(토큰은 0..burst에 머물고
	// 그 시간이면 어느 값에서든 burst까지 찬다) — 그래서 지워도 제한 결과가 한 번도 달라지지 않는다.
	// 주기 청소는 gcEvery마다, 키 표가 가득 차면 최대 초당 1회 강제 청소.
	idleTTL time.Duration
	gcEvery time.Duration
	lastGC  time.Time

	// 키 표 상한(메모리 상한). 무인증 공개 경로의 키(RealIP)는 클라이언트가 XFF로 마음대로 바꿀 수
	// 있어, 상한이 없으면 요청마다 새 키 = 새 버킷으로 청소 주기 안에 표가 끝없이 자란다(인증 전
	// 메모리 고갈). 가득 차면 새 키는 **추적 없이 통과**시킨다(fail-open): 위조 키는 어차피 매번 새
	// 버킷(= 가득 찬 burst)이라 거를 수 없었고, 이미 추적 중인 키의 제한은 그대로이며, 정상 신규
	// 사용자가 공격 때문에 429를 받는 일도 없다. 통과 건수는 분당 최대 한 줄로 로그에 남긴다.
	maxBuckets int
	untracked  int
	lastLog    time.Time
}

// defaultMaxBuckets — 버킷 하나가 맵 엔트리 포함 수십 바이트라 1만 개면 1MB 안쪽이다. 한 인스턴스가
// 청소 기준 시간(idleTTL, 20~30초) 안에 서로 다른 정상 사용자 1만 명을 받을 일은 없다.
const defaultMaxBuckets = 10_000

// newRateLimiter — 분당 perMinute건을 정상 속도로, burst건까지는 몰아쳐도 허용한다.
func newRateLimiter(perMinute, burst int) *rateLimiter {
	rate := float64(perMinute) / 60
	return &rateLimiter{
		buckets:    map[string]*tokenBucket{},
		rate:       rate,
		burst:      float64(burst),
		now:        time.Now,
		logf:       log.Printf,
		idleTTL:    time.Duration(float64(burst) / rate * float64(time.Second)),
		gcEvery:    time.Minute,
		maxBuckets: defaultMaxBuckets,
	}
}

// allow — 키의 버킷에서 토큰 하나를 꺼낸다. 없으면 false와 "다음 토큰까지 남은 시간".
func (l *rateLimiter) allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	if now.Sub(l.lastGC) >= l.gcEvery {
		l.sweepLocked(now)
	}
	b := l.buckets[key]
	if b == nil {
		if len(l.buckets) >= l.maxBuckets && now.Sub(l.lastGC) >= time.Second {
			l.sweepLocked(now) // 강제 청소 — 공격 중 요청마다 전체 순회가 돌지 않게 초당 1회로 묶는다
		}
		if len(l.buckets) >= l.maxBuckets {
			l.untracked++
			return true, 0
		}
		b = &tokenBucket{tokens: l.burst, last: now}
		l.buckets[key] = b
	}
	b.tokens += now.Sub(b.last).Seconds() * l.rate
	if b.tokens > l.burst {
		b.tokens = l.burst
	}
	b.last = now
	if b.tokens >= 1 {
		b.tokens--
		return true, 0
	}
	wait := time.Duration((1 - b.tokens) / l.rate * float64(time.Second))
	return false, wait
}

// sweepLocked — 가득 찰 만큼 쉰 버킷을 지운다(위 idleTTL 주석 — 제한 결과는 바뀌지 않는다).
func (l *rateLimiter) sweepLocked(now time.Time) {
	l.lastGC = now
	for k, b := range l.buckets {
		if now.Sub(b.last) >= l.idleTTL {
			delete(l.buckets, k)
		}
	}
	if l.untracked > 0 && now.Sub(l.lastLog) >= time.Minute {
		l.logf("ratelimit: 키 표 상한(%d)에 걸려 %d건을 추적 없이 통과시켰어요 — 위조 IP 폭주 의심(App Check 후속, work_log P74)",
			l.maxBuckets, l.untracked)
		l.untracked = 0
		l.lastLog = now
	}
}

// retryAfterSeconds — Retry-After 값. **올림**(최소 1): 버림이면 분당 30(초당 0.5 보충)에서 실제 대기
// 1.98초를 "1"로 알려, 그대로 따른 클라이언트가 한 번 더 429를 받는다.
func retryAfterSeconds(wait time.Duration) int {
	secs := int(math.Ceil(wait.Seconds()))
	if secs < 1 {
		secs = 1
	}
	return secs
}

// codeRateLimited — 429의 code 값. 클라이언트는 문구가 아니라 이 값(과 status)으로 분기한다.
const codeRateLimited = "rate_limited"

// middleware — 키 함수가 돌려준 키로 제한한다. 빈 키(판별 불가)는 제한하지 않는다 — 제한기가
// 인증 실패의 원인이 되면 안 되고, 키가 없는 요청은 어차피 auth가 거른다.
func (l *rateLimiter) middleware(keyOf func(*http.Request) string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := keyOf(r)
			if key != "" {
				if ok, wait := l.allow(key); !ok {
					w.Header().Set("Retry-After", strconv.Itoa(retryAfterSeconds(wait)))
					writeJSON(w, http.StatusTooManyRequests, errBodyWithCode{
						Error: "요청이 너무 잦아요 — 잠시 후 다시 시도해주세요",
						Code:  codeRateLimited,
					})
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

// rateKeyMember — 회원 요청은 uid로 센다. **스태프·superadmin은 세지 않는다**(빈 키 = 제한 없음):
// 어드민의 원탭 체크인(POST /v1/checkin, source=tap)이 회원 셀프 체크인과 같은 경로를 쓰는데, 데스크
// 한 명이 수업 시작 전에 몰아서 누르는 것은 폭주가 아니라 업무다. 스태프 토큰은 이보다 훨씬 강한
// 쓰기(회원·결제·환불)를 원래 제한 없이 하므로 이 경로만 세어서는 방어 가치도 없다.
// auth 미들웨어 **뒤**에서만 쓰인다(Principal은 컨텍스트에 있다) — 없으면(이론상 도달 불가) IP로 센다.
func rateKeyMember(r *http.Request) string {
	p, ok := principalFrom(r.Context())
	if !ok || p.UID == "" {
		return rateKeyIP(r)
	}
	if p.IsStaff() || p.IsSuperadmin() {
		return ""
	}
	return "uid:" + p.UID
}

// rateKeyIP — 무인증 공개 경로용. RealIP 미들웨어가 XFF/X-Real-IP를 RemoteAddr에 넣어 두고(포트
// 없음), 직결 요청은 "host:port"라 포트를 떼어 준다 — 안 떼면 연결마다 키가 달라져 제한이 없는 것과 같다.
func rateKeyIP(r *http.Request) string {
	addr := r.RemoteAddr
	if addr == "" {
		return ""
	}
	if host, _, err := net.SplitHostPort(addr); err == nil {
		addr = host
	}
	return "ip:" + addr
}
