package api

// P35 서버 견고화의 계약 테스트 — 캐시 오염 방지 헤더·패닉 복구 포맷·의존성 헬스체크.
// 이 셋은 "코드가 있다"가 아니라 "응답이 그렇게 나간다"를 고정해야 하는 항목들이다:
// no-store가 빠지면 CDN/브라우저에 눌러앉은 에러가 서버 복구를 무효화하고(P34 실사고),
// 패닉 응답이 계약 포맷을 벗어나면 클라이언트가 파싱 오류로 오진한다.

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ramsang/rise-backend/internal/config"
	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

func newResilienceRouter(t *testing.T, st store.Store) http.Handler {
	t.Helper()
	cfg := config.Config{DefaultCenterID: "rise"}
	auth, err := NewAuthenticator(context.Background(), cfg, st)
	if err != nil {
		t.Fatalf("authenticator: %v", err)
	}
	return NewRouter(NewHandlers(NewService(st, cfg, nil)), auth, nil)
}

// 모든 API 응답의 기본 Cache-Control은 no-store다 — 에러 응답 포함.
func TestResponsesDefaultToNoStore(t *testing.T) {
	router := newResilienceRouter(t, store.NewMemory())
	cases := []struct {
		name, method, path string
		devHeaders         bool
	}{
		{"인증된 조회", http.MethodGet, "/v1/me", true},
		{"401 에러", http.MethodGet, "/v1/me", false},
		{"404 에러", http.MethodGet, "/v1/nonexistent", true},
		{"405 에러", http.MethodPut, "/v1/me", true},
		{"liveness", http.MethodGet, "/healthz", false},
		{"의존성 헬스체크", http.MethodGet, "/health", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(tc.method, tc.path, nil)
			if tc.devHeaders {
				req.Header.Set("X-Dev-Uid", "owner1")
				req.Header.Set("X-Dev-Role", "owner")
			}
			rr := httptest.NewRecorder()
			router.ServeHTTP(rr, req)
			if got := rr.Header().Get("Cache-Control"); got != "no-store" {
				t.Fatalf("%s %s: Cache-Control=%q, want no-store (status=%d)", tc.method, tc.path, got, rr.Code)
			}
		})
	}
}

// 에러 응답은 **이미 캐시 헤더가 세팅돼 있어도** no-store로 덮인다.
// 라우터를 통과시키는 테이블 테스트로는 이 분기를 잡을 수 없다(지금은 캐시 헤더를 세운 뒤
// 에러로 빠지는 핸들러가 없어서 else 분기만으로도 통과한다) — 그래서 writeJSON을 직접 친다.
// 이 방어가 필요한 이유: 나중에 누군가 캐시 헤더를 먼저 세우고 에러 분기를 타면, 그 순간
// 에러가 캐시 가능해져 P34(캐시된 에러가 복구를 무효화)가 재발한다.
func TestErrorResponseOverridesExistingCacheHeader(t *testing.T) {
	for _, status := range []int{http.StatusBadRequest, http.StatusNotFound, http.StatusInternalServerError} {
		rr := httptest.NewRecorder()
		rr.Header().Set("Cache-Control", "public, max-age=300") // 핸들러가 먼저 세운 상황
		writeJSON(rr, status, errBody{Error: "x"})
		if got := rr.Header().Get("Cache-Control"); got != "no-store" {
			t.Fatalf("status=%d: Cache-Control=%q, want no-store — 에러가 캐시 가능해진다", status, got)
		}
	}
}

// PublicBusiness는 유일한 의도적 캐시 경로 — 기본값이 그 헤더를 덮어쓰면 안 된다.
// (무인증 공개 경로의 Firestore 읽기 증폭을 캐시로 막는 설계 — handlers_me.go 주석.)
func TestPublicBusinessKeepsItsOwnCacheHeader(t *testing.T) {
	router := newResilienceRouter(t, store.NewMemory())
	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/v1/public/business", nil))
	if got := rr.Header().Get("Cache-Control"); got != "public, max-age=300" {
		t.Fatalf("Cache-Control=%q, want public, max-age=300", got)
	}
}

// 핸들러 패닉은 프로세스를 죽이지 않고 계약 포맷({"error":...}) 500으로 변환된다.
func TestRecoverJSONKeepsContractFormat(t *testing.T) {
	panicking := recoverJSON(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("boom")
	}))
	rr := httptest.NewRecorder()
	panicking.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/v1/anything", nil))
	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("status=%d, want 500", rr.Code)
	}
	if ct := rr.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("Content-Type=%q, want application/json — 빈 본문 500은 클라이언트가 파싱 오류로 오진한다", ct)
	}
	if !strings.Contains(rr.Body.String(), `"error"`) {
		t.Fatalf("본문에 error 필드가 없다: %s", rr.Body.String())
	}
	if got := rr.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("패닉 500의 Cache-Control=%q, want no-store — 에러가 캐시되면 복구가 도달하지 못한다", got)
	}
}

// failingPolicyStore — GetPolicy만 실패하는 스토어(의존성 장애 재현).
type failingPolicyStore struct{ store.Store }

func (failingPolicyStore) GetPolicy(context.Context, string) (*domain.Policy, error) {
	return nil, errors.New("firestore unavailable")
}

// ctxAwarePolicyStore — ctx 취소를 에러로 돌려주는 스토어. **Memory 스토어로는 이 계열을
// 검증할 수 없다**: Memory.GetPolicy는 시그니처가 `_ context.Context`라 취소를 무시하므로,
// 요청 ctx로 헬스체크를 하는 버그가 있어도 테스트가 초록으로 통과한다(실제로 그렇게 통과했다).
// Firestore는 ctx를 존중하므로 운영에서만 터진다 — 그 차이를 테스트가 재현하게 만든다.
type ctxAwarePolicyStore struct{ store.Store }

func (s ctxAwarePolicyStore) GetPolicy(ctx context.Context, centerID string) (*domain.Policy, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return s.Store.GetPolicy(ctx, centerID)
}

// /health는 의존성(Firestore) 장애를 503으로 드러낸다 — 순수 200이면 DB가 죽어도 uptime
// check가 초록불이라 아무도 모른다(P35 H-3). /healthz(liveness)는 그때도 200이어야 한다 —
// DB 블립으로 전 인스턴스가 동시 재시작되면 블립이 전면 장애로 증폭된다.
func TestHealthReflectsDependency(t *testing.T) {
	t.Run("의존성 정상이면 200", func(t *testing.T) {
		router := newResilienceRouter(t, store.NewMemory())
		rr := httptest.NewRecorder()
		router.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/health", nil))
		if rr.Code != http.StatusOK {
			t.Fatalf("status=%d, want 200", rr.Code)
		}
	})
	t.Run("의존성 장애면 503, liveness는 여전히 200", func(t *testing.T) {
		router := newResilienceRouter(t, failingPolicyStore{store.NewMemory()})
		rr := httptest.NewRecorder()
		router.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/health", nil))
		if rr.Code != http.StatusServiceUnavailable {
			t.Fatalf("/health status=%d, want 503", rr.Code)
		}
		rr = httptest.NewRecorder()
		router.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/healthz", nil))
		if rr.Code != http.StatusOK {
			t.Fatalf("/healthz status=%d, want 200", rr.Code)
		}
	})
	t.Run("Hosting 경유 감시 미러 /api/health가 실재한다", func(t *testing.T) {
		router := newResilienceRouter(t, store.NewMemory())
		rr := httptest.NewRecorder()
		router.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/health", nil))
		if rr.Code != http.StatusOK {
			t.Fatalf("/api/health status=%d, want 200", rr.Code)
		}
	})
	// 호출자가 연결을 끊어도 헬스 판정이 오염되지 않는다. r.Context()로 체크하면
	// context.Canceled가 실패로 캐시돼 15초간 503이 나가고 거짓 장애 알림이 울린다.
	t.Run("요청 취소가 헬스 판정을 오염시키지 않는다", func(t *testing.T) {
		router := newResilienceRouter(t, ctxAwarePolicyStore{store.NewMemory()})
		ctx, cancel := context.WithCancel(context.Background())
		cancel() // 이미 끊긴 연결을 흉내낸다.
		rr := httptest.NewRecorder()
		router.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/health", nil).WithContext(ctx))

		// 뒤이은 정상 요청이 앞 요청의 취소에 오염되면 안 된다(캐시 TTL 안에서 판정).
		rr2 := httptest.NewRecorder()
		router.ServeHTTP(rr2, httptest.NewRequest(http.MethodGet, "/health", nil))
		if rr2.Code != http.StatusOK {
			t.Fatalf("취소된 요청 뒤 /health status=%d, want 200 — 요청 ctx로 체크해 캐시가 오염됐다", rr2.Code)
		}
	})
}

// 패닉 복구가 **라우터에 실제로 배선돼** 있다 — 미들웨어 함수를 직접 감싸 테스트하면
// r.Use(recoverJSON) 한 줄이 빠져도 통과한다. 그 줄이 빠지면 핸들러 패닉이 프로세스를 죽인다.
func TestRouterWiresPanicRecovery(t *testing.T) {
	// 패닉하는 핸들러를 라우터 뒤에 두기 위해, 존재하는 경로에 패닉 서비스를 물린다.
	router := newResilienceRouter(t, panicOnPolicyStore{store.NewMemory()})
	rr := httptest.NewRecorder()
	// /health가 GetPolicy를 부른다 → 패닉 → recoverJSON이 라우터에 걸려 있어야 500 JSON.
	func() {
		defer func() {
			if rec := recover(); rec != nil {
				t.Fatalf("패닉이 라우터를 뚫고 나왔다(recoverJSON 미배선): %v", rec)
			}
		}()
		router.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/health", nil))
	}()
	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("status=%d, want 500", rr.Code)
	}
	if !strings.Contains(rr.Body.String(), `"error"`) {
		t.Fatalf("계약 포맷이 아니다: %s", rr.Body.String())
	}
}

// panicOnPolicyStore — GetPolicy에서 패닉하는 스토어(핸들러 패닉 재현).
type panicOnPolicyStore struct{ store.Store }

func (panicOnPolicyStore) GetPolicy(context.Context, string) (*domain.Policy, error) {
	panic("boom in handler")
}

// 헬스 판정은 캐시된다 — 감시가 3개 리전에서 주기적으로 오므로 매 요청 DB를 때리면
// 모니터링 자체가 부하가 된다. TTL 안에서는 스토어 호출이 늘지 않아야 한다.
func TestHealthResultIsCached(t *testing.T) {
	counting := &countingPolicyStore{Store: store.NewMemory()}
	router := newResilienceRouter(t, counting)
	for i := 0; i < 5; i++ {
		rr := httptest.NewRecorder()
		router.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/health", nil))
		if rr.Code != http.StatusOK {
			t.Fatalf("%d번째 /health status=%d, want 200", i, rr.Code)
		}
	}
	if counting.calls != 1 {
		t.Fatalf("GetPolicy 호출 %d회, want 1 — TTL 캐시가 동작하지 않는다", counting.calls)
	}
}

type countingPolicyStore struct {
	store.Store
	calls int
}

func (c *countingPolicyStore) GetPolicy(ctx context.Context, centerID string) (*domain.Policy, error) {
	c.calls++
	return c.Store.GetPolicy(ctx, centerID)
}

// 요청 바디 상한(1MiB) — 초과 바디는 400으로 거부된다(파싱 시도로 메모리를 태우지 않는다).
func TestOversizedBodyRejected(t *testing.T) {
	router := newResilienceRouter(t, store.NewMemory())
	big := `{"phone":"` + strings.Repeat("1", maxBodyBytes+1) + `"}`
	req := httptest.NewRequest(http.MethodPost, "/v1/join/match", strings.NewReader(big))
	req.Header.Set("X-Dev-Uid", "m1")
	req.Header.Set("X-Dev-Role", "member")
	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("status=%d, want 400", rr.Code)
	}
}
