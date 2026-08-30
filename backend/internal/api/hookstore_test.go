package api

// hookStore — 스토어 호출 **사이의 창**을 테스트에서 직접 여는 데코레이터.
//
// 왜 필요한가: 이 프로젝트가 실제로 터진 사고 두 종류는 인메모리 스토어로 재현되지 않는다.
//
//	① 부분 실패(찢어진 쓰기) — 두 번째 스토어 호출만 실패하는 상황. 실환경에선 Firestore
//	   타임아웃·권한 오류·네트워크 단절로 일상적으로 일어나지만 Memory는 절대 실패하지 않는다.
//	② 순수 경합 — Memory는 전역 뮤텍스 하나로 모든 연산을 직렬화하므로 경합 창이 나노초다.
//
// hookStore는 둘 다 결정적으로 만든다: `fail`은 지정한 스토어 메서드의 n번째 호출을 실패시키고,
// `before`는 그 직전에 테스트가 원하는 만큼 다른 고루틴을 끼워 넣게 해 준다(래치).
// 경합 재현이 **에뮬레이터 없이** 되는 이유는 이것이 스케줄러 운에 기대지 않기 때문이다 —
// 창을 열어 두고 상대를 통째로 실행시킨 다음 닫는다.
//
// 여기서 감싸는 것은 돈·세션이 움직이는 경로가 실제로 부르는 메서드들뿐이다. 감싸지 않은
// 메서드는 임베딩된 Store로 그냥 통과한다.

import (
	"context"
	"sync"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

type hookStore struct {
	store.Store

	mu     sync.Mutex
	counts map[string]int

	// before — 실제 호출 **직전**에 불린다. n은 이 메서드의 1-based 호출 순번.
	// 락 밖에서 불리므로 여기서 블로킹해도 다른 고루틴의 스토어 접근을 막지 않는다.
	before func(op string, n int)
	// fail — nil이 아닌 에러를 돌려주면 실제 스토어를 부르지 않고 그 에러를 반환한다.
	fail func(op string, n int) error
}

func newHookStore(inner store.Store) *hookStore {
	return &hookStore{Store: inner, counts: map[string]int{}}
}

// enter — 호출 카운트를 올리고 before 훅을 실행한 뒤, 주입 에러가 있으면 돌려준다.
func (h *hookStore) enter(op string) error {
	h.mu.Lock()
	h.counts[op]++
	n := h.counts[op]
	before, fail := h.before, h.fail
	h.mu.Unlock()
	if before != nil {
		before(op, n)
	}
	if fail != nil {
		return fail(op, n)
	}
	return nil
}

func (h *hookStore) callCount(op string) int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.counts[op]
}

// reset — 픽스처 세팅 동안 쌓인 호출 카운트를 지운다(주입은 "검증 대상 호출"부터 1번이어야 한다).
func (h *hookStore) reset() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.counts = map[string]int{}
}

// latchOnFirstWrite — 첫 쓰기 호출 **직전에** 창을 열고, release가 닫힐 때까지 붙잡는다.
//
// op 이름을 집합으로 받는 이유: 이 래치는 뮤테이션(원자적 동사를 옛 2단계 호출로 되돌리기)
// 뒤에도 같은 자리를 잡아야 한다. 옛 코드의 첫 쓰기는 AppendLedger/UpdatePass였고 지금은
// UpdatePassWithLedger(AndContracts)다 — 전부 넣어 두면 두 버전에서 같은 창이 열린다.
// 계약 전이도 같은 규칙(P37): 지금은 TransitionContract, 옛 2단계 코드는 UpdateContract.
func latchOnFirstWrite(reached, release chan struct{}) func(string, int) {
	var once sync.Once
	writes := map[string]bool{
		"UpdatePassWithLedger":             true,
		"UpdatePassWithLedgerAndContracts": true,
		"UpdatePass":                       true,
		"AppendLedger":                     true,
		"TransitionContract":               true,
		"UpdateContract":                   true,
	}
	return func(op string, _ int) {
		if !writes[op] {
			return
		}
		first := false
		once.Do(func() { first = true })
		if !first {
			return
		}
		close(reached)
		<-release
	}
}

// failFirst — op의 첫 호출만 실패시키는 fail 훅.
func failFirst(op string, err error) func(string, int) error {
	return func(gotOp string, n int) error {
		if gotOp == op && n == 1 {
			return err
		}
		return nil
	}
}

// ---- 래핑(돈·세션 경로가 부르는 메서드) ----

func (h *hookStore) GetPass(ctx context.Context, centerID, id string) (*domain.Pass, error) {
	if err := h.enter("GetPass"); err != nil {
		return nil, err
	}
	return h.Store.GetPass(ctx, centerID, id)
}

func (h *hookStore) CreatePass(ctx context.Context, centerID string, p *domain.Pass) (string, error) {
	if err := h.enter("CreatePass"); err != nil {
		return "", err
	}
	return h.Store.CreatePass(ctx, centerID, p)
}

func (h *hookStore) UpdatePass(ctx context.Context, centerID string, p *domain.Pass) error {
	if err := h.enter("UpdatePass"); err != nil {
		return err
	}
	return h.Store.UpdatePass(ctx, centerID, p)
}

func (h *hookStore) IssuePass(ctx context.Context, centerID string, p *domain.Pass, e *domain.Ledger, c *domain.Contract) error {
	if err := h.enter("IssuePass"); err != nil {
		return err
	}
	return h.Store.IssuePass(ctx, centerID, p, e, c)
}

func (h *hookStore) UpdatePassWithLedger(ctx context.Context, centerID, passID string, mutate store.PassMutator) (*domain.Pass, error) {
	if err := h.enter("UpdatePassWithLedger"); err != nil {
		return nil, err
	}
	return h.Store.UpdatePassWithLedger(ctx, centerID, passID, mutate)
}

func (h *hookStore) UpdatePassWithLedgerAndContracts(ctx context.Context, centerID, passID string, mutate store.PassMutator, contractIDs []string, sweep store.ContractSweepMutator) (*domain.Pass, error) {
	if err := h.enter("UpdatePassWithLedgerAndContracts"); err != nil {
		return nil, err
	}
	return h.Store.UpdatePassWithLedgerAndContracts(ctx, centerID, passID, mutate, contractIDs, sweep)
}

func (h *hookStore) ListPassesByMember(ctx context.Context, centerID, memberID string) ([]domain.Pass, error) {
	if err := h.enter("ListPassesByMember"); err != nil {
		return nil, err
	}
	return h.Store.ListPassesByMember(ctx, centerID, memberID)
}

func (h *hookStore) AppendLedger(ctx context.Context, centerID string, e *domain.Ledger) (string, error) {
	if err := h.enter("AppendLedger"); err != nil {
		return "", err
	}
	return h.Store.AppendLedger(ctx, centerID, e)
}

func (h *hookStore) ListLedger(ctx context.Context, centerID, memberID, passID string) ([]domain.Ledger, error) {
	if err := h.enter("ListLedger"); err != nil {
		return nil, err
	}
	return h.Store.ListLedger(ctx, centerID, memberID, passID)
}

func (h *hookStore) CreateContract(ctx context.Context, centerID string, c *domain.Contract) (string, error) {
	if err := h.enter("CreateContract"); err != nil {
		return "", err
	}
	return h.Store.CreateContract(ctx, centerID, c)
}

func (h *hookStore) CreateContractGuarded(ctx context.Context, centerID string, c *domain.Contract, guard func(existing []domain.Contract) error) (string, error) {
	if err := h.enter("CreateContractGuarded"); err != nil {
		return "", err
	}
	return h.Store.CreateContractGuarded(ctx, centerID, c, guard)
}

func (h *hookStore) GetContract(ctx context.Context, centerID, id string) (*domain.Contract, error) {
	if err := h.enter("GetContract"); err != nil {
		return nil, err
	}
	return h.Store.GetContract(ctx, centerID, id)
}

func (h *hookStore) UpdateContract(ctx context.Context, centerID string, c *domain.Contract) error {
	if err := h.enter("UpdateContract"); err != nil {
		return err
	}
	return h.Store.UpdateContract(ctx, centerID, c)
}

func (h *hookStore) TransitionContract(ctx context.Context, centerID, contractID string, mutate store.ContractMutator) (*domain.Contract, error) {
	if err := h.enter("TransitionContract"); err != nil {
		return nil, err
	}
	return h.Store.TransitionContract(ctx, centerID, contractID, mutate)
}

func (h *hookStore) ListContracts(ctx context.Context, centerID, memberID, statusFilter string) ([]domain.Contract, error) {
	if err := h.enter("ListContracts"); err != nil {
		return nil, err
	}
	return h.Store.ListContracts(ctx, centerID, memberID, statusFilter)
}

func (h *hookStore) UpdatePayment(ctx context.Context, centerID string, p *domain.Payment) error {
	if err := h.enter("UpdatePayment"); err != nil {
		return err
	}
	return h.Store.UpdatePayment(ctx, centerID, p)
}

func (h *hookStore) ListPayments(ctx context.Context, centerID string) ([]domain.Payment, error) {
	if err := h.enter("ListPayments"); err != nil {
		return nil, err
	}
	return h.Store.ListPayments(ctx, centerID)
}

func (h *hookStore) BookAtomic(ctx context.Context, centerID, slotKey string, capacity int, b *domain.Booking) error {
	if err := h.enter("BookAtomic"); err != nil {
		return err
	}
	return h.Store.BookAtomic(ctx, centerID, slotKey, capacity, b)
}

func (h *hookStore) CancelAtomic(ctx context.Context, centerID, bookingID string, entry *domain.Ledger) error {
	if err := h.enter("CancelAtomic"); err != nil {
		return err
	}
	return h.Store.CancelAtomic(ctx, centerID, bookingID, entry)
}

func (h *hookStore) SetBookingStatusWithLedger(ctx context.Context, centerID, bookingID, newStatus string, entry *domain.Ledger) error {
	if err := h.enter("SetBookingStatusWithLedger"); err != nil {
		return err
	}
	return h.Store.SetBookingStatusWithLedger(ctx, centerID, bookingID, newStatus, entry)
}

func (h *hookStore) GetBooking(ctx context.Context, centerID, id string) (*domain.Booking, error) {
	if err := h.enter("GetBooking"); err != nil {
		return nil, err
	}
	return h.Store.GetBooking(ctx, centerID, id)
}

func (h *hookStore) ListBookingsByMember(ctx context.Context, centerID, memberID string) ([]domain.Booking, error) {
	if err := h.enter("ListBookingsByMember"); err != nil {
		return nil, err
	}
	return h.Store.ListBookingsByMember(ctx, centerID, memberID)
}

func (h *hookStore) GetPolicy(ctx context.Context, centerID string) (*domain.Policy, error) {
	if err := h.enter("GetPolicy"); err != nil {
		return nil, err
	}
	return h.Store.GetPolicy(ctx, centerID)
}

func (h *hookStore) GetMember(ctx context.Context, centerID, id string) (*domain.Member, error) {
	if err := h.enter("GetMember"); err != nil {
		return nil, err
	}
	return h.Store.GetMember(ctx, centerID, id)
}

// GetFacility — 스탬프 게이트의 latch-off 불변("래치 OFF면 facility 읽기조차 없다" —
// 스토어 접근 횟수까지 오늘과 동일) 카운트 검증용(P42). 실패 스윕(hookedOps)에는 넣지
// 않는다 — 그 스윕은 돈·세션 원자성 경로 대상이고 이 읽기는 스탬프 선택 전용이다.
func (h *hookStore) GetFacility(ctx context.Context, centerID string) (*domain.Facility, error) {
	if err := h.enter("GetFacility"); err != nil {
		return nil, err
	}
	return h.Store.GetFacility(ctx, centerID)
}

// SaveStaff — 사진 업로드(v2.25)의 **찢어진 쓰기** 재현용. 업로드는 이미 끝났는데 프로필
// 저장이 실패하는 창이 실제로 존재하고, 그때 방금 올린 오브젝트를 정리하지 않으면 아무도
// 가리키지 않는 파일이 버킷에 남는다(발견 경로 0 — P22가 체형사진에서 겪은 그 상태).
// hookedOps(돈·세션 원자성 스윕)에는 넣지 않는다 — 그쪽 관심사가 아니다.
func (h *hookStore) SaveStaff(ctx context.Context, centerID string, s *domain.Staff) error {
	if err := h.enter("SaveStaff"); err != nil {
		return err
	}
	return h.Store.SaveStaff(ctx, centerID, s)
}

// hookedOps — 찢어진 쓰기 스윕이 하나씩 실패시켜 볼 메서드 목록. 위에서 래핑한 것과 같아야
// 한다(래핑하지 않은 메서드는 실패 주입이 통하지 않아 스윕이 조용히 건너뛴다).
var hookedOps = []string{
	"GetPass", "CreatePass", "UpdatePass", "IssuePass", "UpdatePassWithLedger",
	"UpdatePassWithLedgerAndContracts", "ListPassesByMember",
	"AppendLedger", "ListLedger",
	"CreateContract", "CreateContractGuarded", "GetContract", "UpdateContract",
	"TransitionContract", "ListContracts",
	"UpdatePayment", "ListPayments",
	"BookAtomic", "CancelAtomic", "SetBookingStatusWithLedger", "GetBooking", "ListBookingsByMember",
	"GetPolicy", "GetMember",
}

// newHookedService — hookStore를 물린 서비스. 반환된 훅으로 실패·래치를 주입한다.
func newHookedService(t *testing.T) (*Service, *hookStore) {
	t.Helper()
	s := newTestService()
	h := newHookStore(s.store)
	s.store = h
	return s, h
}
