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
