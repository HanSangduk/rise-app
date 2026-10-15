package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// forEachParallel(v2.38, P74)의 세 가지 계약 — 상한·첫 오류·취소 — 을 고정한다.
func TestForEachParallelRespectsLimitAndKeepsIndex(t *testing.T) {
	const n, limit = 20, 3
	var inFlight, peak int32
	out := make([]int, n)
	err := forEachParallel(context.Background(), n, limit, func(_ context.Context, i int) error {
		cur := atomic.AddInt32(&inFlight, 1)
		for {
			p := atomic.LoadInt32(&peak)
			if cur <= p || atomic.CompareAndSwapInt32(&peak, p, cur) {
				break
			}
		}
		time.Sleep(2 * time.Millisecond)
		out[i] = i * 10
		atomic.AddInt32(&inFlight, -1)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	for i := range out {
		if out[i] != i*10 {
			t.Fatalf("out[%d] = %d, want %d — 인덱스가 섞였다", i, out[i], i*10)
		}
	}
	if peak > limit {
		t.Errorf("동시 실행 최대 %d, want <= %d", peak, limit)
	}
	if peak < 2 {
		t.Errorf("동시 실행 최대 %d — 병렬이 아니라 직렬로 돌았다", peak)
	}
}

func TestForEachParallelFirstErrorCancelsRest(t *testing.T) {
	boom := errors.New("boom")
	var started, cancelled int32
	err := forEachParallel(context.Background(), 50, 2, func(ctx context.Context, i int) error {
		atomic.AddInt32(&started, 1)
		if i == 1 {
			return boom
		}
		select {
		case <-ctx.Done():
			atomic.AddInt32(&cancelled, 1)
		case <-time.After(20 * time.Millisecond):
		}
		return nil
	})
	if !errors.Is(err, boom) {
		t.Fatalf("err = %v, want boom", err)
	}
	if s := atomic.LoadInt32(&started); s >= 50 {
		t.Errorf("실패 뒤에도 전부(%d) 시작했다 — 남은 항목은 시작하지 않아야 한다", s)
	}
	if atomic.LoadInt32(&cancelled) == 0 {
		t.Errorf("진행 중이던 항목에 취소가 전달되지 않았다")
	}
}

// 워커 패닉은 인스턴스를 죽이지 않고 오류가 된다 — 요청 고루틴 밖이라 recoverJSON이 못 잡는 자리다.
// 이 시험이 없으면 패닉 격리를 지워도 초록이다(패닉이 테스트 바이너리를 통째로 죽이는 것 = 실패로
// 보이긴 하지만, "오류로 돌아온다·스택 한 줄이 남는다·나머지가 취소된다"는 계약은 여기서만 잰다).
func TestForEachParallelRecoversWorkerPanic(t *testing.T) {
	var buf bytes.Buffer
	prev := parallelPanicLog
	parallelPanicLog = &buf
	t.Cleanup(func() { parallelPanicLog = prev })

	var cancelled int32
	err := forEachParallel(context.Background(), 20, 2, func(ctx context.Context, i int) error {
		if i == 1 {
			var m map[string]int
			m["boom"]++ // nil map 쓰기 — 런타임 패닉
		}
		select {
		case <-ctx.Done():
			atomic.AddInt32(&cancelled, 1)
		case <-time.After(20 * time.Millisecond):
		}
		return nil
	})
	if err == nil || !strings.Contains(err.Error(), "패닉") {
		t.Fatalf("err = %v, want 패닉을 담은 오류(프로세스가 죽지 않고 첫 오류로 돌아와야 한다)", err)
	}
	var line map[string]string
	if jerr := json.Unmarshal(bytes.TrimSpace(buf.Bytes()), &line); jerr != nil {
		t.Fatalf("패닉 로그가 JSON 한 줄이 아니다(%v): %q", jerr, buf.String())
	}
	if line["severity"] != "ERROR" || !strings.Contains(line["stack"], "parallel_test.go") {
		t.Errorf("패닉 로그 = %v — severity=ERROR와 워커 스택이 있어야 한다", line)
	}
	if atomic.LoadInt32(&cancelled) == 0 {
		t.Error("패닉 뒤 진행 중이던 워커에 취소가 전달되지 않았다")
	}
}

func TestForEachParallelEmptyAndParentCancel(t *testing.T) {
	if err := forEachParallel(context.Background(), 0, 4, func(context.Context, int) error {
		t.Fatal("n=0인데 호출됐다")
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	// select가 준비된 갈래 중 무작위로 고르므로 결함이 있으면 한 판에 절반 확률로만 드러난다(1회 실행 시험이
	// 40회 중 20회 실패했다) — 한 번의 `go test`로 확정되도록 판을 여러 번 돈다(0.5^200).
	for round := 0; round < 200; round++ {
		var calls int32
		err := forEachParallel(ctx, 5, 2, func(context.Context, int) error {
			atomic.AddInt32(&calls, 1)
			return nil
		})
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("취소된 ctx(%d판): err = %v, want context.Canceled(빈 결과를 성공으로 돌려주면 안 된다)", round, err)
		}
		if n := atomic.LoadInt32(&calls); n != 0 {
			t.Fatalf("취소된 ctx인데 %d판에서 %d회 실행됐다", round, n)
		}
	}
}

// 회원 목록의 병렬 조회가 직렬과 같은 답(같은 순서·같은 패스·같은 잔여)을 낸다.
func TestListMembersParallelMatchesSequential(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	seedTrainerRecord(t, s, "t1", "정혜린")
	const n = 12
	for i := 0; i < n; i++ {
		mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
			Name: fmt.Sprintf("회원%02d", i), Phone: fmt.Sprintf("010-1000-%04d", i),
			TrainerID: "t1", Status: domain.MemberStatusActive,
		})
		if err != nil {
			t.Fatal(err)
		}
		for k := 0; k < 1+i%3; k++ {
			if _, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
				MemberID: mem.ID, TrainerID: "t1", Product: "PT 10회", PaidAmount: 500_000, TotalSessions: 10,
				ValidFrom: "2026-01-01", ValidUntil: "2027-12-31",
			}); err != nil {
				t.Fatal(err)
			}
		}
	}
	// 직렬 기준값: 스토어를 직접 순서대로 읽어 만든다.
	members, err := s.store.ListMembers(ctx, testCenter, "", "")
	if err != nil {
		t.Fatal(err)
	}
	got, err := s.ListMembers(ctx, ownerP(), "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != len(members) || len(got) != n {
		t.Fatalf("len = %d, want %d", len(got), n)
	}
	for i := range members {
		if got[i].Member.ID != members[i].ID {
			t.Fatalf("[%d] 순서가 바뀌었다: %s vs %s", i, got[i].Member.ID, members[i].ID)
		}
		passes, err := s.store.ListPassesByMember(ctx, testCenter, members[i].ID)
		if err != nil {
			t.Fatal(err)
		}
		if len(got[i].Passes) != len(passes) {
			t.Errorf("[%d] passes = %d, want %d", i, len(got[i].Passes), len(passes))
		}
		for _, ps := range got[i].Passes {
			if ps.Remaining != 10 {
				t.Errorf("[%d] pass %s remaining = %d, want 10(원장 재계산 누락)", i, ps.ID, ps.Remaining)
			}
		}
	}
}

// 회원 목록은 패스마다 **원장으로 잔여를 다시 센다**(hydrate) — 저장된 remaining이 틀어져 있어도 응답은
// 원장 합이다. 위 시험은 저장값과 원장 합이 같은(10) 데이터라 hydrate를 빼도 초록이었다(P74 감사).
func TestListMembersParallelStillHydratesFromLedger(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 10)
	stale, err := s.store.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	stale.Remaining = 999 // 저장값만 틀어 둔다(원장 합은 그대로 10)
	if err := s.store.UpdatePass(ctx, testCenter, stale); err != nil {
		t.Fatal(err)
	}
	got, err := s.ListMembers(ctx, ownerP(), "", "")
	if err != nil {
		t.Fatal(err)
	}
	for _, mw := range got {
		if mw.Member.ID != mem.ID {
			continue
		}
		if len(mw.Passes) != 1 || mw.Passes[0].Remaining != 10 {
			t.Fatalf("passes = %+v, want remaining 10(원장 합) — 저장값 999를 그대로 냈다면 hydrate가 빠졌다", mw.Passes)
		}
		return
	}
	t.Fatalf("회원 %s가 목록에 없다", mem.ID)
}

// 회원별 조회가 **실제로 겹치고**(직렬로 되돌리면 1) 상한(memberFanOut)을 넘지 않는다.
func TestListMembersFansOutWithinLimit(t *testing.T) {
	s, h := newHookedService(t)
	ctx := context.Background()
	seedTrainerRecord(t, s, "t1", "정혜린")
	for i := 0; i < 2*memberFanOut; i++ {
		if _, err := s.CreateMember(ctx, ownerP(), &domain.Member{
			Name: fmt.Sprintf("회원%02d", i), Phone: fmt.Sprintf("010-2000-%04d", i),
			TrainerID: "t1", Status: domain.MemberStatusActive,
		}); err != nil {
			t.Fatal(err)
		}
	}
	var mu sync.Mutex
	inFlight, peak := 0, 0
	h.before = func(op string, _ int) {
		if op != "ListPassesByMember" {
			return
		}
		mu.Lock()
		inFlight++
		if inFlight > peak {
			peak = inFlight
		}
		mu.Unlock()
		time.Sleep(5 * time.Millisecond) // 겹칠 시간을 준다
		mu.Lock()
		inFlight--
		mu.Unlock()
	}
	defer func() { h.before = nil }()

	got, err := s.ListMembers(ctx, ownerP(), "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2*memberFanOut {
		t.Fatalf("len = %d, want %d", len(got), 2*memberFanOut)
	}
	if peak < 2 {
		t.Errorf("회원별 조회가 겹치지 않았다(peak=%d) — 다시 직렬이다", peak)
	}
	if peak > memberFanOut {
		t.Errorf("동시 조회 %d개 — 상한 %d를 넘었다", peak, memberFanOut)
	}
}
