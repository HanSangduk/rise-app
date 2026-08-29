package api

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"runtime/debug"
	"sync"
	"time"

	"github.com/go-chi/chi/v5/middleware"
)

// ---- 헬스체크 2종 (P35 H-3) ----
//
// /healthz — liveness: 프로세스가 살아 있고 HTTP를 받을 수 있는가만 본다. 의존성을 보지 않는
//            이유: Firestore 블립 하나로 오케스트레이터가 전 인스턴스를 동시 재시작하면 블립이
//            전면 장애로 증폭된다.
// /health  — 외부 모니터링(uptime check)용: 의존성(Firestore)을 **얕게** 확인한다. 종전엔 이것도
//            순수 200이라, Firestore IAM 박탈·할당량 소진으로 모든 실사용 요청이 500이어도
//            uptime check는 초록불이었다 — 서비스가 완전히 죽어도 알림이 안 왔다.

// healthCacheTTL — 의존성 체크 결과 캐시. 헬스체크가 여러 리전에서 주기적으로 오므로, 캐시가
// 없으면 모니터링 자체가 Firestore 부하가 된다. TTL만큼 감지가 늦어지는 건 uptime check
// 주기(분 단위)보다 훨씬 짧아 무시 가능하다.
const healthCacheTTL = 15 * time.Second

// healthCheckTimeout — 의존성 체크 1회의 예산. 헬스체크가 느려지는 것 자체가 모니터링을
// 흔들므로 짧게 자른다 — Firestore가 2초 안에 정책 문서 하나를 못 읽으면 이미 비정상이다.
const healthCheckTimeout = 2 * time.Second

type healthState struct {
	mu      sync.Mutex
	checked time.Time
	err     error
}

// Health — GET /health(/api/health). Firestore에서 기본 센터 정책 문서 하나를 읽어본다.
// 정책 문서는 모든 실사용 경로가 지나는 가장 싼 읽기라 "이게 되면 DB 연결·인증·권한이 산 것"의
// 대표값으로 적합하다(양쪽 스토어 모두 부재 시 기본 정책을 자가 생성하므로 NotFound 오탐 없음).
// 실패 시 503 — uptime check(2xx 기대)가 즉시 알림을 낸다.
func (h *Handlers) Health(w http.ResponseWriter, r *http.Request) {
	h.health.mu.Lock()
	if time.Since(h.health.checked) > healthCacheTTL {
		ctx, cancel := context.WithTimeout(r.Context(), healthCheckTimeout)
		_, err := h.svc.store.GetPolicy(ctx, h.svc.cfg.DefaultCenterID)
		cancel()
		h.health.checked = time.Now()
		h.health.err = err
		if err != nil {
			log.Printf("health check degraded: %v", err)
		}
	}
	err := h.health.err
	h.health.mu.Unlock()

	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "degraded"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// recoverJSON — 핸들러 패닉을 계약 포맷({"error":...}) 500으로 바꾼다(P35 M-7).
//
// chi 기본 Recoverer를 안 쓰는 이유 둘: (1) 본문 없는 500을 내보내 클라이언트가 JSON 파싱
// 오류로 오진한다. (2) 스택을 여러 줄 평문으로 stdout에 흘려 Cloud Logging에서 줄마다 별개
// INFO 엔트리로 쪼개진다 — 에러 알림에 안 걸리고 검색도 안 된다. 여기서는 severity=ERROR인
// 구조화 JSON 한 줄로 stderr에 남긴다(Cloud Logging이 JSON 라인을 필드로 파싱한다).
func recoverJSON(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			rec := recover()
			if rec == nil {
				return
			}
			if rec == http.ErrAbortHandler {
				panic(rec) // net/http 규약 — 의도된 연결 중단은 그대로 통과시킨다.
			}
			line, _ := json.Marshal(map[string]string{
				"severity": "ERROR",
				"message":  fmt.Sprintf("panic: %s %s: %v", r.Method, r.URL.Path, rec),
				"reqid":    middleware.GetReqID(r.Context()),
				"stack":    string(debug.Stack()),
			})
			fmt.Fprintln(os.Stderr, string(line))
			// 응답이 이미 시작된 뒤라면 아래 WriteHeader는 "superfluous" 경고 한 줄로 끝난다 —
			// 그 경우 어차피 온전한 응답을 만들 방법이 없다.
			writeJSON(w, http.StatusInternalServerError, errBody{Error: "서버 오류가 발생했습니다"})
		}()
		next.ServeHTTP(w, r)
	})
}
