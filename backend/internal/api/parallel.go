package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"runtime/debug"
	"sync"

	"github.com/go-chi/chi/v5/middleware"
)

// forEachParallel — 0..n-1을 최대 limit개씩 동시에 처리한다(v2.38, P74). 첫 오류가 곧 전체 오류이고,
// 그 순간 나머지에는 취소된 ctx가 전달된다(Firestore 호출은 취소를 존중하고, Memory는 무시한다).
// 결과는 호출자가 인덱스로 제자리에 쓴다 — 순서를 여기서 바꾸지 않는다.
//
// 어드민 회원 목록·회원권 목록이 회원·패스 수만큼 **직렬** 왕복하던 자리(N+1)를 위한 최소 도구다.
// 외부 의존성(errgroup)을 들이지 않는 이유: go.mod를 건드리지 않고도 50줄로 충분하고, 취소·상한·
// 첫 오류·패닉 격리라는 네 가지 계약만 필요해서다.
//
// **패닉 격리**: 워커는 요청 고루틴이 아니라서 recoverJSON(health.go)·accessLog의 recover가 닿지
// 않는다 — Go의 recover는 같은 고루틴의 스택에서만 잡힌다. 잡지 않으면 워커 하나의 패닉이
// **인스턴스 전체**(같은 인스턴스의 다른 요청 전부)를 죽인다. 직렬이던 시절엔 같은 버그가 요청
// 하나의 500이었으므로, 병렬화가 폭발 반경을 바꾸지 않도록 워커마다 패닉을 오류로 바꿔 첫 오류
// 경로에 태운다(응답은 writeErr의 기본 갈래 = 원문을 숨긴 500, 스택은 recoverJSON과 같은
// 구조화 ERROR 한 줄).
func forEachParallel(ctx context.Context, n, limit int, fn func(ctx context.Context, i int) error) error {
	if n == 0 {
		return nil
	}
	if limit <= 0 || limit > n {
		limit = n
	}
	gctx, cancel := context.WithCancel(ctx)
	defer cancel()
	sem := make(chan struct{}, limit)
	var (
		wg       sync.WaitGroup
		mu       sync.Mutex
		firstErr error
	)
loop:
	for i := 0; i < n; i++ {
		select {
		case sem <- struct{}{}:
		case <-gctx.Done():
			break loop // 이미 실패했다(또는 호출자가 취소했다) — 남은 항목은 시작하지 않는다.
		}
		// select는 준비된 갈래 중 **무작위**로 고른다 — 빈 자리와 취소가 함께 준비돼 있으면 절반은 자리를
		// 집는다(이 확인이 없을 때 이미 취소된 ctx로 최대 limit개가 시작됐다: 시험 40회 중 20회 실패).
		if gctx.Err() != nil {
			<-sem
			break
		}
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			defer func() { <-sem }()
			if err := runRecovered(gctx, i, fn); err != nil {
				mu.Lock()
				if firstErr == nil {
					firstErr = err
				}
				mu.Unlock()
				cancel()
			}
		}(i)
	}
	wg.Wait()
	if firstErr == nil && ctx.Err() != nil {
		return ctx.Err() // 호출자 취소로 일부를 시작조차 못 했다 — 빈 결과를 성공으로 돌려주지 않는다
	}
	return firstErr
}

// parallelPanicLog — 워커 패닉의 구조화 로그 출력처. 시험이 버퍼로 바꿔 끼운다.
var parallelPanicLog io.Writer = os.Stderr

// runRecovered — fn(ctx, i)를 부르고, 패닉이면 recoverJSON과 같은 모양의 ERROR 한 줄(스택 포함)을
// 남긴 뒤 오류로 돌려준다. 오류 문구는 로그용이다 — writeErr가 500의 응답 본문에서 숨긴다.
func runRecovered(ctx context.Context, i int, fn func(ctx context.Context, i int) error) (err error) {
	defer func() {
		rec := recover()
		if rec == nil {
			return
		}
		line, _ := json.Marshal(map[string]string{
			"severity": "ERROR",
			"message":  fmt.Sprintf("panic in parallel worker #%d: %v", i, rec),
			"reqid":    middleware.GetReqID(ctx),
			"stack":    string(debug.Stack()),
		})
		fmt.Fprintln(parallelPanicLog, string(line))
		err = fmt.Errorf("병렬 작업 #%d 패닉: %v", i, rec)
	}()
	return fn(ctx, i)
}
