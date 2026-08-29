package store

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// Memory — 인메모리 Store(개발·테스트용, 프로세스 종료 시 소멸). 단일 뮤텍스로 모든 연산을
// 직렬화한다 — 친구 샵 규모(회원 수십 명)에선 성능보다 정확성·단순성이 우선이다
// (설계00 자문자답 라운드2 Q2·Q3). 키는 대부분 "centerID/id" 합성키로 센터 경계를 흉내낸다 —
// Firestore가 collection 경로(centers/{centerID}/...)로 자연히 나누는 것과 동등한 격리다.
type Memory struct {
	mu  sync.RWMutex
	seq int

	userIndex  map[string]*UserIndex         // key: uid
	joinReqs   map[string]*JoinRequest       // key: id (CenterID는 구조체 필드로 보유)
	members    map[string]*domain.Member     // key: centerID/id
	ledger     map[string]*domain.Ledger     // key: centerID/id
	passes     map[string]*domain.Pass       // key: centerID/id
	slots      map[string]*domain.Slot       // key: centerID/slotKey
	bookings   map[string]*domain.Booking    // key: centerID/id
	recurrings map[string]*domain.Recurring  // key: centerID/id
	homeworks  map[string]*domain.Homework   // key: centerID/id
	hwChecks   map[string]*domain.HwCheck    // key: centerID/memberID/hwID/date
	staff      map[string]*domain.Staff      // key: centerID/uid
	payments   map[string]*domain.Payment    // key: centerID/id
	contracts  map[string]*domain.Contract   // key: centerID/id
	photos     map[string]*domain.BodyPhoto  // key: centerID/id
	inbody     map[string]*domain.Inbody     // key: centerID/id
	checkins   map[string]*CheckinRecord     // key: center/booking-{bookingID} — 예약당 1건 upsert(멱등)
	policies   map[string]*domain.Policy     // key: centerID
	businesses map[string]*domain.Business   // key: centerID (v2.13 법정 고지 기재사항)
	workouts   map[string]*domain.WorkoutLog // key: centerID/id (v1.4 수업 기록)
}

// NewMemory — 빈 인메모리 스토어.
func NewMemory() *Memory {
	return &Memory{
		userIndex:  map[string]*UserIndex{},
		joinReqs:   map[string]*JoinRequest{},
		members:    map[string]*domain.Member{},
		ledger:     map[string]*domain.Ledger{},
		passes:     map[string]*domain.Pass{},
		slots:      map[string]*domain.Slot{},
		bookings:   map[string]*domain.Booking{},
		recurrings: map[string]*domain.Recurring{},
		homeworks:  map[string]*domain.Homework{},
		hwChecks:   map[string]*domain.HwCheck{},
		staff:      map[string]*domain.Staff{},
		payments:   map[string]*domain.Payment{},
		contracts:  map[string]*domain.Contract{},
		photos:     map[string]*domain.BodyPhoto{},
		inbody:     map[string]*domain.Inbody{},
		checkins:   map[string]*CheckinRecord{},
		policies:   map[string]*domain.Policy{},
		businesses: map[string]*domain.Business{},
		workouts:   map[string]*domain.WorkoutLog{},
	}
}

// ---- 수업 기록(WorkoutLog, v1.4) ----

func (m *Memory) CreateWorkoutLog(_ context.Context, centerID string, wl *domain.WorkoutLog) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if wl.ID == "" {
		wl.ID = m.nextID("wl")
	}
	if wl.Exercises == nil {
		wl.Exercises = []domain.Exercise{} // 직렬화 계약: 항상 배열
	}
	cp := *wl
	m.workouts[scoped(centerID, wl.ID)] = &cp
	return wl.ID, nil
}

func (m *Memory) ListWorkoutLogs(_ context.Context, centerID, memberID string) ([]domain.WorkoutLog, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.WorkoutLog{}
	for key, wl := range m.workouts {
		if !strings.HasPrefix(key, prefix) {
			continue
		}
		if memberID != "" && wl.MemberID != memberID {
			continue
		}
		out = append(out, *wl)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Date > out[j].Date }) // 최신 먼저
	return out, nil
}

func (m *Memory) nextID(prefix string) string {
	m.seq++
	return fmt.Sprintf("%s_%06d", prefix, m.seq)
}

func scoped(centerID, id string) string { return centerID + "/" + id }

// normalizePhone — 가입 매칭(P48)용 비교 키. 국내 표기와 Firebase 토큰의 E.164를 같은 값으로
// 수렴시킨다(P06) — 규칙과 근거는 domain.NormalizePhone 주석 참고. Firestore 구현도 같은 함수를
// 쓴다(두 스토어가 다르게 매칭하면 로컬에선 되고 프로덕션에선 안 되는 버그가 된다).
func normalizePhone(s string) string { return domain.NormalizePhone(s) }

// betterPhoneMatch — 같은 번호를 쓰는 회원이 여럿일 때 FindMemberByPhone이 누구를 돌려줄지
// 정하는 **단일 규칙**. cand가 지금까지의 best보다 앞서면 true.
//
// 부모 번호로 자녀 둘을 등록하는 건 실제로 흔하다. 그런데 두 스토어 모두 순서 없는 스캔
// (Go 맵 순회·Firestore 컬렉션 iterator)의 첫 히트를 돌려줘서, 같은 요청이 호출마다 다른
// 사람을 반환했다 — 앱이 확인 1탭에 띄우는 이름이 그때그때 바뀌고, 재시도 한 번에 엉뚱한
// 레코드로 연결될 수 있었다.
//
//	① app_linked=false 우선 — 이미 앱에 연결된 레코드는 주인이 있다. 새 가입자를 그 위에
//	   올리면 UserIndex가 나중 uid만 가리켜 먼저 연결한 사람이 자기 기록에서 밀려난다.
//	② 그다음 ID 오름차순 — 남은 후보들 사이에 전순서를 하나 박아 결과를 고정한다(먼저 등록된
//	   레코드가 이긴다: 패스·이력이 쌓여 있을 확률이 높은 쪽).
//
// normalizePhone과 같은 이유로 두 스토어가 이 함수 하나를 공유한다 — 규칙이 갈리면 로컬에선
// 되고 프로덕션에선 안 되는 버그가 된다.
func betterPhoneMatch(cand, best *domain.Member) bool {
	if best == nil {
		return true
	}
	if cand.AppLinked != best.AppLinked {
		return !cand.AppLinked // ① 미연결이 이긴다
	}
	return cand.ID < best.ID // ② 동률이면 ID 오름차순
}

// ---- 인증 인덱스 ----

func (m *Memory) GetUserIndex(_ context.Context, uid string) (*UserIndex, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if u, ok := m.userIndex[uid]; ok {
		cp := *u
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) SaveUserIndex(_ context.Context, u *UserIndex) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	cp := *u
	m.userIndex[u.UID] = &cp
	return nil
}

// DeleteUserIndex — 없는 uid도 성공(재시도 멱등). 근거는 Store 인터페이스 주석 참고.
func (m *Memory) DeleteUserIndex(_ context.Context, uid string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.userIndex, uid)
	return nil
}

// ---- 가입 매칭 ----

func (m *Memory) FindMemberByPhone(_ context.Context, centerID, phone string) (*domain.Member, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	target := normalizePhone(phone)
	if target == "" {
		return nil, ErrNotFound
	}
	prefix := centerID + "/"
	// 첫 히트를 돌려주지 않는다 — 맵 순회 순서는 매번 달라진다(betterPhoneMatch 주석 참고).
	var best *domain.Member
	for key, mem := range m.members {
		if !strings.HasPrefix(key, prefix) || normalizePhone(mem.Phone) != target {
			continue
		}
		if betterPhoneMatch(mem, best) {
			best = mem
		}
	}
	if best == nil {
		return nil, ErrNotFound
	}
	cp := *best
	return &cp, nil
}

func (m *Memory) CreateJoinRequest(_ context.Context, jr *JoinRequest) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if jr.ID == "" {
		jr.ID = m.nextID("jreq")
	}
	if jr.CreatedAt.IsZero() {
		jr.CreatedAt = time.Now().UTC()
	}
	if jr.Status == "" {
		jr.Status = JoinPending
	}
	cp := *jr
	m.joinReqs[jr.ID] = &cp
	return jr.ID, nil
}

func (m *Memory) GetJoinRequest(_ context.Context, id string) (*JoinRequest, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if jr, ok := m.joinReqs[id]; ok {
		cp := *jr
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) UpdateJoinRequest(_ context.Context, jr *JoinRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.joinReqs[jr.ID]; !ok {
		return ErrNotFound
	}
	cp := *jr
	m.joinReqs[jr.ID] = &cp
	return nil
}

func (m *Memory) ListJoinRequests(_ context.Context, centerID string) ([]JoinRequest, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := []JoinRequest{}
	for _, jr := range m.joinReqs {
		if jr.CenterID == centerID {
			out = append(out, *jr)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) }) // 최신 먼저
	return out, nil
}

// ---- 회원 ----

func (m *Memory) ListMembers(_ context.Context, centerID, trainerID, q string) ([]domain.Member, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	ql := strings.ToLower(strings.TrimSpace(q))
	out := []domain.Member{}
	for key, mem := range m.members {
		if !strings.HasPrefix(key, prefix) {
			continue
		}
		if trainerID != "" && mem.TrainerID != trainerID {
			continue
		}
		if ql != "" && !strings.Contains(strings.ToLower(mem.Name), ql) && !strings.Contains(mem.Phone, q) {
			continue
		}
		out = append(out, *mem)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

func (m *Memory) GetMember(_ context.Context, centerID, id string) (*domain.Member, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if mem, ok := m.members[scoped(centerID, id)]; ok {
		cp := *mem
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) SaveMember(_ context.Context, centerID string, mem *domain.Member) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if mem.ID == "" {
		mem.ID = m.nextID("mem")
	}
	cp := *mem
	m.members[scoped(centerID, mem.ID)] = &cp
	return mem.ID, nil
}

// PurgeMemberPersonalData — 회원탈퇴 집행(v2.11). 계약·근거는 Store 인터페이스 주석 참고.
//
// 전 과정을 **락 하나 안에서** 돈다: 부분 삭제 상태가 다른 요청에 관측되지 않는다
// (Firestore 구현은 이 원자성을 갖지 못하고, 그 차이는 conformance가 아니라 여기 주석이
// 진실이다 — 아래 Firestore 구현의 주석 참고).
func (m *Memory) PurgeMemberPersonalData(_ context.Context, centerID string, anonymized *domain.Member) (PurgeCounts, error) {
	if anonymized == nil || anonymized.ID == "" {
		return PurgeCounts{}, ErrNotFound
	}
	m.mu.Lock()
	defer m.mu.Unlock()

	memberID := anonymized.ID
	if _, ok := m.members[scoped(centerID, memberID)]; !ok {
		return PurgeCounts{}, ErrNotFound
	}
	prefix := centerID + "/"
	var c PurgeCounts

	for key, bp := range m.photos {
		if strings.HasPrefix(key, prefix) && bp.MemberID == memberID {
			delete(m.photos, key)
			c.BodyPhotos++
		}
	}
	for key, r := range m.inbody {
		if strings.HasPrefix(key, prefix) && r.MemberID == memberID {
			delete(m.inbody, key)
			c.Inbody++
		}
	}
	for key, wl := range m.workouts {
		if strings.HasPrefix(key, prefix) && wl.MemberID == memberID {
			delete(m.workouts, key)
			c.WorkoutLogs++
		}
	}
	for key, hc := range m.hwChecks {
		if strings.HasPrefix(key, prefix) && hc.MemberID == memberID {
			delete(m.hwChecks, key)
			c.HwChecks++
		}
	}
	for key, ck := range m.checkins {
		if strings.HasPrefix(key, prefix) && ck.MemberID == memberID {
			delete(m.checkins, key)
			c.Checkins++
		}
	}
	for key, r := range m.recurrings {
		if strings.HasPrefix(key, prefix) && r.MemberID == memberID {
			delete(m.recurrings, key)
			c.Recurrings++
		}
	}

	// 가명화된 회원 문서는 **마지막에** 쓴다(순서 규약 — Store 인터페이스 주석).
	cp := *anonymized
	m.members[scoped(centerID, memberID)] = &cp
	return c, nil
}

// ---- 원장 ----

func (m *Memory) AppendLedger(_ context.Context, centerID string, e *domain.Ledger) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if e.ID == "" {
		e.ID = m.nextID("led")
	}
	if e.At.IsZero() {
		e.At = time.Now().UTC()
	}
	cp := *e
	m.ledger[scoped(centerID, e.ID)] = &cp
	return e.ID, nil
}

func (m *Memory) ListLedger(_ context.Context, centerID, memberID, passID string) ([]domain.Ledger, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.listLedgerLocked(centerID, memberID, passID), nil
}

// listLedgerLocked — ListLedger의 본체. 락을 **이미 쥔** 원자적 연산(UpdatePassWithLedger·
// BookAtomic)이 트랜잭션 안에서 원장을 다시 세야 해서 분리했다 — 이 안에서 ListLedger를 부르면
// 같은 뮤텍스를 다시 잡아 교착한다.
func (m *Memory) listLedgerLocked(centerID, memberID, passID string) []domain.Ledger {
	prefix := centerID + "/"
	out := []domain.Ledger{}
	for key, e := range m.ledger {
		if !strings.HasPrefix(key, prefix) {
			continue
		}
		if e.MemberID != memberID {
			continue
		}
		if passID != "" && e.PassID != passID {
			continue
		}
		out = append(out, *e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].At.After(out[j].At) }) // 최신 먼저
	return out
}

// appendLedgerLocked — 락을 이미 쥔 상태에서의 원장 적재(ID·At 채움 규칙은 AppendLedger와 동일).
func (m *Memory) appendLedgerLocked(centerID string, e *domain.Ledger) {
	if e.ID == "" {
		e.ID = m.nextID("led")
	}
	if e.At.IsZero() {
		e.At = time.Now().UTC()
	}
	cp := *e
	m.ledger[scoped(centerID, e.ID)] = &cp
}

// ---- 회원권 ----

func (m *Memory) CreatePass(_ context.Context, centerID string, p *domain.Pass) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if p.ID == "" {
		p.ID = m.nextID("pass")
	}
	cp := *p
	m.passes[scoped(centerID, p.ID)] = &cp
	return p.ID, nil
}

func (m *Memory) GetPass(_ context.Context, centerID, id string) (*domain.Pass, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if p, ok := m.passes[scoped(centerID, id)]; ok {
		cp := *p
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) UpdatePass(_ context.Context, centerID string, p *domain.Pass) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := scoped(centerID, p.ID)
	if _, ok := m.passes[key]; !ok {
		return ErrNotFound
	}
	cp := *p
	m.passes[key] = &cp
	return nil
}

// IssuePass — Memory는 전역 뮤텍스 하나로 모든 접근을 직렬화하므로, 세 쓰기를 같은 Lock 구간에
// 두는 것만으로 Firestore 트랜잭션과 동등한 원자성을 얻는다(BookAtomic과 같은 논리).
func (m *Memory) IssuePass(_ context.Context, centerID string, p *domain.Pass, entry *domain.Ledger, contract *domain.Contract) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if p.ID == "" {
		p.ID = m.nextID("pass")
	}
	pc := *p
	m.passes[scoped(centerID, p.ID)] = &pc
	if entry != nil {
		entry.PassID = p.ID // 새 패스 ID로 덮어쓴다 — 호출측이 채울 수 없는 값이다
		m.appendLedgerLocked(centerID, entry)
	}
	if contract != nil {
		contract.PassID = p.ID
		if contract.ID == "" {
			contract.ID = m.nextID("con")
		}
		cc := *contract
		m.contracts[scoped(centerID, contract.ID)] = &cc
	}
	return nil
}

// UpdatePassWithLedger — 패스 갱신 + 원장 적재를 같은 Lock 구간에서.
func (m *Memory) UpdatePassWithLedger(ctx context.Context, centerID, passID string, mutate PassMutator) (*domain.Pass, error) {
	return m.UpdatePassWithLedgerAndContracts(ctx, centerID, passID, mutate, nil, nil)
}

// UpdatePassWithLedgerAndContracts — 패스 갱신 + 원장 적재 + 지목 계약 갱신을 같은 Lock
// 구간에서(P37, 계약 v2.15). mutate/sweep은 저장본의 **사본**을 받고(에러 반환 시 아무것도
// 반영되지 않아야 하므로 원본을 직접 넘기지 않는다), 판정을 전부 끝낸 뒤에야 맵에 커밋한다 —
// sweep 중간 에러 시 패스·원장·앞서 판정한 계약까지 전무다(Firestore 트랜잭션 롤백과 같은 답).
func (m *Memory) UpdatePassWithLedgerAndContracts(_ context.Context, centerID, passID string, mutate PassMutator, contractIDs []string, sweep ContractSweepMutator) (*domain.Pass, error) {
	if err := checkDocID(passID); err != nil {
		return nil, err
	}
	for _, cid := range contractIDs {
		if err := checkDocID(cid); err != nil {
			return nil, err
		}
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	key := scoped(centerID, passID)
	cur, ok := m.passes[key]
	if !ok {
		return nil, ErrNotFound
	}
	fresh := *cur
	fresh.Holds = append([]domain.Hold{}, cur.Holds...) // 슬라이스 공유 금지 — 롤백이 원본을 건드리면 안 된다
	entries := m.listLedgerLocked(centerID, fresh.MemberID, passID)
	entry, err := mutate(&fresh, entries)
	if err != nil {
		return nil, err
	}
	type contractWrite struct {
		key string
		c   domain.Contract
	}
	writes := []contractWrite{}
	for _, cid := range contractIDs {
		ckey := scoped(centerID, cid)
		curC, ok := m.contracts[ckey]
		if !ok {
			return nil, ErrNotFound // 지목한 계약이 없다 — 조용한 스킵보다 표면화(인터페이스 주석)
		}
		cc := *curC
		save, err := sweep(&cc)
		if err != nil {
			return nil, err
		}
		if save {
			writes = append(writes, contractWrite{ckey, cc})
		}
	}
	if entry != nil {
		entry.PassID = passID
		m.appendLedgerLocked(centerID, entry)
	}
	saved := fresh
	m.passes[key] = &saved
	for _, w := range writes {
		cc := w.c
		m.contracts[w.key] = &cc
	}
	out := fresh
	out.Holds = append([]domain.Hold{}, fresh.Holds...)
	return &out, nil
}

func (m *Memory) ListPassesByMember(_ context.Context, centerID, memberID string) ([]domain.Pass, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.Pass{}
	for key, p := range m.passes {
		if strings.HasPrefix(key, prefix) && p.MemberID == memberID {
			out = append(out, *p)
		}
	}
	sortPasses(out) // 맵 순회는 매번 순서가 다르다 — Firestore와 같은 규칙(order.go)
	return out, nil
}

func (m *Memory) ListPasses(_ context.Context, centerID string) ([]domain.Pass, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.Pass{}
	for key, p := range m.passes {
		if strings.HasPrefix(key, prefix) {
			out = append(out, *p)
		}
	}
	sortPasses(out) // order.go — Firestore와 같은 규칙
	return out, nil
}

// ---- 슬롯/예약 ----

func (m *Memory) GetSlot(_ context.Context, centerID, slotKey string) (*domain.Slot, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if s, ok := m.slots[scoped(centerID, slotKey)]; ok {
		cp := *s
		cp.Teams = append([]domain.Team{}, s.Teams...)
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) ListSlots(_ context.Context, centerID, date string) ([]domain.Slot, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	datePart := strings.ReplaceAll(date, "-", "")
	prefix := centerID + "/" + datePart + "-"
	out := []domain.Slot{}
	for key, s := range m.slots {
		if strings.HasPrefix(key, prefix) {
			cp := *s
			cp.Teams = append([]domain.Team{}, s.Teams...)
			out = append(out, cp)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SlotKey < out[j].SlotKey })
	return out, nil
}

// BookAtomic — Memory는 프로세스 전역 뮤텍스 하나로 모든 접근을 직렬화하므로, 읽기(슬롯 조회)와
// 쓰기(팀 추가+예약 생성)를 같은 Lock 구간에 두는 것만으로 Firestore 트랜잭션과 동등한 원자성을 얻는다.
func (m *Memory) BookAtomic(_ context.Context, centerID, slotKey string, capacity int, booking *domain.Booking) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := scoped(centerID, slotKey)
	slot, ok := m.slots[key]
	if !ok {
		slot = &domain.Slot{SlotKey: slotKey, Capacity: capacity}
		m.slots[key] = slot
	}
	if len(slot.Teams) == 0 {
		slot.Capacity = capacity // 비어 있는 슬롯은 현재 정책 용량으로 갱신(v1.5 — 옛 스냅샷 영구화 방지)
	}
	if err := domain.CanBook(*slot, booking.TrainerID, booking.MemberID); err != nil {
		return err
	}
	// 잔여 청구권 재판정(P13 H1) — 슬롯 규칙과 같은 임계구역 안에서 본다.
	pass, hasPass := m.passes[scoped(centerID, booking.PassID)]
	if booking.PassID != "" && hasPass {
		remaining := domain.Sum(m.listLedgerLocked(centerID, booking.MemberID, booking.PassID))
		open := 0
		for bkey, b := range m.bookings {
			if !strings.HasPrefix(bkey, centerID+"/") {
				continue // 센터 경계 — 합성 키가 Firestore의 컬렉션 경로에 대응한다
			}
			if b.PassID == booking.PassID && b.MemberID == booking.MemberID && b.Status == domain.BookingConfirmed {
				open++
			}
		}
		if remaining-open <= 0 {
			return domain.ErrNoSessionsLeft
		}
		pass.Remaining = remaining // 저장 스냅샷을 원장 합으로 맞춘다(M3) — Firestore 구현과 대칭
	}
	if booking.ID == "" {
		booking.ID = m.nextID("bkg")
	}
	if booking.CreatedAt.IsZero() {
		booking.CreatedAt = time.Now().UTC()
	}
	if booking.Status == "" {
		booking.Status = domain.BookingConfirmed
	}
	cp := *booking
	m.bookings[scoped(centerID, booking.ID)] = &cp
	slot.Teams = append(slot.Teams, domain.Team{
		BookingID: booking.ID,
		TrainerID: booking.TrainerID,
		MemberID:  booking.MemberID,
		Kind:      booking.Kind,
		Status:    domain.BookingConfirmed, // v1.1 정합 패치: teams[].status 초기값
	})
	return nil
}

func (m *Memory) GetBooking(_ context.Context, centerID, id string) (*domain.Booking, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if b, ok := m.bookings[scoped(centerID, id)]; ok {
		cp := *b
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) ListBookingsByMember(_ context.Context, centerID, memberID string) ([]domain.Booking, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.Booking{}
	for key, b := range m.bookings {
		if strings.HasPrefix(key, prefix) && b.MemberID == memberID {
			out = append(out, *b)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SlotKey < out[j].SlotKey })
	return out, nil
}

func (m *Memory) ListBookings(_ context.Context, centerID string) ([]domain.Booking, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.Booking{}
	for key, b := range m.bookings {
		if strings.HasPrefix(key, prefix) {
			out = append(out, *b)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SlotKey < out[j].SlotKey })
	return out, nil
}

func (m *Memory) CancelAtomic(_ context.Context, centerID, bookingID string, entry *domain.Ledger) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	bkey := scoped(centerID, bookingID)
	b, ok := m.bookings[bkey]
	if !ok {
		return ErrNotFound
	}
	if b.Status != domain.BookingConfirmed {
		return ErrStateConflict // 완료/노쇼/취소된 예약의 재취소 금지(락 내부 재검증)
	}
	b.Status = domain.BookingCancelled
	skey := scoped(centerID, b.SlotKey)
	if slot, ok := m.slots[skey]; ok {
		kept := []domain.Team{}
		for _, t := range slot.Teams {
			if t.BookingID != bookingID {
				kept = append(kept, t)
			}
		}
		slot.Teams = kept
	}
	if entry != nil {
		m.appendLedgerLocked(centerID, entry) // 컷오프 내 취소의 페널티 — 취소와 찢어지지 않게(M4)
	}
	return nil
}

func (m *Memory) SetBookingStatusWithLedger(_ context.Context, centerID, bookingID, status string, entry *domain.Ledger) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	bkey := scoped(centerID, bookingID)
	b, ok := m.bookings[bkey]
	if !ok {
		return ErrNotFound
	}
	if b.Status != domain.BookingConfirmed {
		return ErrStateConflict // confirmed에서만 complete/noshow 전이(락 내부 재검증 — 동시 이중 호출 방어)
	}
	b.Status = status
	// v1.1 정합 패치: slot.teams[].status를 예약 상태와 함께 동기화한다(completed/noshow).
	if slot, ok := m.slots[scoped(centerID, b.SlotKey)]; ok {
		for i := range slot.Teams {
			if slot.Teams[i].BookingID == bookingID {
				slot.Teams[i].Status = status
				break
			}
		}
	}
	if entry != nil {
		m.appendLedgerLocked(centerID, entry)
	}
	return nil
}

// ReassignBookingTrainer — 담당 이관(v2.0). BookAtomic과 같은 전역 뮤텍스 구간에서 슬롯 판정과
// 두 쓰기(예약·슬롯 teams)를 함께 처리해 원자성을 얻는다.
func (m *Memory) ReassignBookingTrainer(_ context.Context, centerID, bookingID, toTrainerID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	b, ok := m.bookings[scoped(centerID, bookingID)]
	if !ok {
		return ErrNotFound
	}
	if b.Status != domain.BookingConfirmed {
		return ErrStateConflict
	}
	slot, hasSlot := m.slots[scoped(centerID, b.SlotKey)]
	if hasSlot && toTrainerID != "" {
		// 인수자가 같은 슬롯의 **다른** 팀을 이미 맡고 있으면 거부(R2 트레이너 동시 1팀).
		// 자기 자신(이 예약)은 제외 — 재실행(멱등)이 자기 때문에 막히지 않게.
		for _, t := range slot.Teams {
			if t.BookingID != bookingID && t.TrainerID == toTrainerID {
				return domain.ErrTrainerBusy
			}
		}
	}
	b.TrainerID = toTrainerID
	if hasSlot {
		for i := range slot.Teams {
			if slot.Teams[i].BookingID == bookingID {
				slot.Teams[i].TrainerID = toTrainerID
				break
			}
		}
	}
	return nil
}

// ---- 고정 스케줄 ----

func (m *Memory) CreateRecurring(_ context.Context, centerID string, r *domain.Recurring) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if r.ID == "" {
		r.ID = m.nextID("rec")
	}
	cp := *r
	m.recurrings[scoped(centerID, r.ID)] = &cp
	return r.ID, nil
}

func (m *Memory) UpdateRecurring(_ context.Context, centerID string, r *domain.Recurring) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := scoped(centerID, r.ID)
	if _, ok := m.recurrings[key]; !ok {
		return ErrNotFound
	}
	cp := *r
	m.recurrings[key] = &cp
	return nil
}

func (m *Memory) GetRecurring(_ context.Context, centerID, id string) (*domain.Recurring, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if r, ok := m.recurrings[scoped(centerID, id)]; ok {
		cp := *r
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) DeleteRecurring(_ context.Context, centerID, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := scoped(centerID, id)
	if _, ok := m.recurrings[key]; !ok {
		return ErrNotFound
	}
	delete(m.recurrings, key)
	return nil
}

func (m *Memory) ListRecurrings(_ context.Context, centerID string) ([]domain.Recurring, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.Recurring{}
	for key, r := range m.recurrings {
		if strings.HasPrefix(key, prefix) {
			out = append(out, *r)
		}
	}
	sortByDocID(out, recurringDocID) // order.go — Firestore와 같은 규칙
	return out, nil
}

// ---- Home Work ----

func (m *Memory) CreateHomework(_ context.Context, centerID string, hw *domain.Homework) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if hw.ID == "" {
		hw.ID = m.nextID("hw")
	}
	cp := *hw
	m.homeworks[scoped(centerID, hw.ID)] = &cp
	return hw.ID, nil
}

func (m *Memory) GetHomework(_ context.Context, centerID, id string) (*domain.Homework, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if hw, ok := m.homeworks[scoped(centerID, id)]; ok {
		cp := *hw
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) ListHomeworks(_ context.Context, centerID string) ([]domain.Homework, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.Homework{}
	for key, hw := range m.homeworks {
		if strings.HasPrefix(key, prefix) {
			out = append(out, *hw)
		}
	}
	sortByDocID(out, homeworkDocID) // order.go — Firestore와 같은 규칙
	return out, nil
}

func hwCheckKey(centerID string, c *domain.HwCheck) string {
	return centerID + "/" + c.MemberID + "/" + c.HwID + "/" + c.Date
}

func (m *Memory) SaveHwCheck(_ context.Context, centerID string, c *domain.HwCheck) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	cp := *c
	m.hwChecks[hwCheckKey(centerID, c)] = &cp
	return nil
}

func (m *Memory) ListHwChecksByMember(_ context.Context, centerID, memberID string) ([]domain.HwCheck, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/" + memberID + "/"
	out := []domain.HwCheck{}
	for key, c := range m.hwChecks {
		if strings.HasPrefix(key, prefix) {
			out = append(out, *c)
		}
	}
	sortByDocID(out, hwCheckDocIDOf) // order.go — Firestore의 합성 문서 ID 순서와 일치시킨다
	return out, nil
}

// ListHwChecks — 센터 전체(회원 무관, GET /v1/hw-checks?hw_id=&member= 지원용, v1.1 정합 패치).
func (m *Memory) ListHwChecks(_ context.Context, centerID string) ([]domain.HwCheck, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.HwCheck{}
	for key, c := range m.hwChecks {
		if strings.HasPrefix(key, prefix) {
			out = append(out, *c)
		}
	}
	sortByDocID(out, hwCheckDocIDOf) // order.go — Firestore의 합성 문서 ID 순서와 일치시킨다
	return out, nil
}

// ---- 직원 ----

func (m *Memory) ListStaff(_ context.Context, centerID string) ([]domain.Staff, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.Staff{}
	for key, s := range m.staff {
		if strings.HasPrefix(key, prefix) {
			cp := *s
			cp.Normalize() // v2.0: status 부재 → active 승격(Firestore 구현과 동일 규약)
			out = append(out, cp)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

func (m *Memory) GetStaff(_ context.Context, centerID, uid string) (*domain.Staff, error) {
	// 빈 uid는 두 스토어 공통으로 ErrNotFound(errors.go의 checkDocID). Memory는 맵 미스라 대개
	// 저절로 그렇게 되지만, 규칙을 명시해야 "미배정("") 조회"가 우연히 저장된 빈 키 레코드를
	// 집어가는 일이 없다 — Firestore 쪽은 이 가드가 없으면 500이다.
	if err := checkDocID(uid); err != nil {
		return nil, err
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	if s, ok := m.staff[scoped(centerID, uid)]; ok {
		cp := *s
		cp.Normalize()
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) SaveStaff(_ context.Context, centerID string, s *domain.Staff) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	cp := *s
	m.staff[scoped(centerID, s.UID)] = &cp
	return nil
}

// ---- 결제 ----

func (m *Memory) CreatePayment(_ context.Context, centerID string, p *domain.Payment) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if p.ID == "" {
		p.ID = m.nextID("pay")
	}
	cp := *p
	m.payments[scoped(centerID, p.ID)] = &cp
	return p.ID, nil
}

func (m *Memory) GetPayment(_ context.Context, centerID, id string) (*domain.Payment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if p, ok := m.payments[scoped(centerID, id)]; ok {
		cp := *p
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) UpdatePayment(_ context.Context, centerID string, p *domain.Payment) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := scoped(centerID, p.ID)
	if _, ok := m.payments[key]; !ok {
		return ErrNotFound
	}
	cp := *p
	m.payments[key] = &cp
	return nil
}

func (m *Memory) ListPayments(_ context.Context, centerID string) ([]domain.Payment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.Payment{}
	for key, p := range m.payments {
		if strings.HasPrefix(key, prefix) {
			out = append(out, *p)
		}
	}
	sortByDocID(out, paymentDocID) // order.go — Firestore와 같은 규칙
	return out, nil
}

// ---- 전자계약(Contract, v1.1 정합 패치) ----

func (m *Memory) CreateContract(_ context.Context, centerID string, c *domain.Contract) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if c.ID == "" {
		c.ID = m.nextID("con")
	}
	cp := *c
	m.contracts[scoped(centerID, c.ID)] = &cp
	return c.ID, nil
}

// CreateContractGuarded — 기존 계약 스캔 + guard + 생성을 같은 Lock 구간에서(P37 M2, 계약 v2.15).
func (m *Memory) CreateContractGuarded(_ context.Context, centerID string, c *domain.Contract, guard func(existing []domain.Contract) error) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	prefix := centerID + "/"
	existing := []domain.Contract{}
	for key, ec := range m.contracts {
		if strings.HasPrefix(key, prefix) && ec.MemberID == c.MemberID {
			existing = append(existing, *ec)
		}
	}
	if err := guard(existing); err != nil {
		return "", err
	}
	if c.ID == "" {
		c.ID = m.nextID("con")
	}
	cp := *c
	m.contracts[scoped(centerID, c.ID)] = &cp
	return c.ID, nil
}

func (m *Memory) GetContract(_ context.Context, centerID, id string) (*domain.Contract, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if c, ok := m.contracts[scoped(centerID, id)]; ok {
		cp := *c
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) UpdateContract(_ context.Context, centerID string, c *domain.Contract) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := scoped(centerID, c.ID)
	if _, ok := m.contracts[key]; !ok {
		return ErrNotFound
	}
	cp := *c
	m.contracts[key] = &cp
	return nil
}

// TransitionContract — 계약 전이 검증+쓰기를 같은 Lock 구간에서(P37, 계약 v2.15). mutate는
// 저장본의 **사본**을 받는다(에러 반환 시 아무것도 반영되지 않아야 하므로 —
// UpdatePassWithLedger와 동일). 함께 주는 패스도 사본이다 — 판정 전용이라 여기 쓴 변경은
// 저장되지 않는다(인터페이스 주석).
func (m *Memory) TransitionContract(_ context.Context, centerID, contractID string, mutate ContractMutator) (*domain.Contract, error) {
	if err := checkDocID(contractID); err != nil {
		return nil, err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	key := scoped(centerID, contractID)
	cur, ok := m.contracts[key]
	if !ok {
		return nil, ErrNotFound
	}
	fresh := *cur
	var pass *domain.Pass
	if p, ok := m.passes[scoped(centerID, fresh.PassID)]; ok {
		cp := *p
		cp.Holds = append([]domain.Hold{}, p.Holds...)
		pass = &cp
	}
	if err := mutate(&fresh, pass); err != nil {
		return nil, err
	}
	saved := fresh
	m.contracts[key] = &saved
	out := fresh
	return &out, nil
}

func (m *Memory) ListContracts(_ context.Context, centerID, memberID, status string) ([]domain.Contract, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.Contract{}
	for key, c := range m.contracts {
		if !strings.HasPrefix(key, prefix) {
			continue
		}
		if memberID != "" && c.MemberID != memberID {
			continue
		}
		if status != "" && c.Status != status {
			continue
		}
		out = append(out, *c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, nil
}

// ---- 체형사진 ----

func (m *Memory) CreateBodyPhoto(_ context.Context, centerID string, bp *domain.BodyPhoto) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if bp.ID == "" {
		bp.ID = m.nextID("photo")
	}
	cp := *bp
	m.photos[scoped(centerID, bp.ID)] = &cp
	return bp.ID, nil
}

func (m *Memory) GetBodyPhoto(_ context.Context, centerID, id string) (*domain.BodyPhoto, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	bp, ok := m.photos[scoped(centerID, id)]
	if !ok {
		return nil, ErrNotFound
	}
	cp := *bp
	return &cp, nil
}

func (m *Memory) SaveBodyPhoto(_ context.Context, centerID string, bp *domain.BodyPhoto) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.photos[scoped(centerID, bp.ID)]; !ok {
		return ErrNotFound
	}
	cp := *bp
	m.photos[scoped(centerID, bp.ID)] = &cp
	return nil
}

func (m *Memory) DeleteBodyPhoto(_ context.Context, centerID, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := scoped(centerID, id)
	if _, ok := m.photos[key]; !ok {
		return ErrNotFound
	}
	delete(m.photos, key)
	return nil
}

func (m *Memory) ListBodyPhotosPendingPurge(_ context.Context, centerID string, before time.Time, limit int) ([]domain.BodyPhoto, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.BodyPhoto{}
	for key, bp := range m.photos {
		if !strings.HasPrefix(key, prefix) || bp.DeletedAt == nil {
			continue
		}
		if bp.DeletedAt.Before(before) {
			out = append(out, *bp)
		}
	}
	// 맵 순회는 매번 순서가 다르다 — 한 번에 도는 양을 묶으려면 순서가 고정돼야
	// 재호출이 같은 걸 반복하지 않는다(Firestore와 같은 규칙).
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}

func (m *Memory) ListBodyPhotos(_ context.Context, centerID, memberID string) ([]domain.BodyPhoto, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.BodyPhoto{}
	for key, bp := range m.photos {
		if strings.HasPrefix(key, prefix) && bp.MemberID == memberID {
			out = append(out, *bp)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Date > out[j].Date })
	return out, nil
}

// ---- 인바디 ----

func (m *Memory) CreateInbody(_ context.Context, centerID string, r *domain.Inbody) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if r.ID == "" {
		r.ID = m.nextID("inbody")
	}
	cp := *r
	m.inbody[scoped(centerID, r.ID)] = &cp
	return r.ID, nil
}

func (m *Memory) ListInbody(_ context.Context, centerID, memberID string) ([]domain.Inbody, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	prefix := centerID + "/"
	out := []domain.Inbody{}
	for key, r := range m.inbody {
		if strings.HasPrefix(key, prefix) && r.MemberID == memberID {
			out = append(out, *r)
		}
	}
	sortInbody(out) // 최신 먼저 + 동률 시 ID(order.go — 두 스토어 공통 규칙)
	return out, nil
}

func (m *Memory) GetInbody(_ context.Context, centerID, id string) (*domain.Inbody, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if r, ok := m.inbody[scoped(centerID, id)]; ok {
		cp := *r
		return &cp, nil
	}
	return nil, ErrNotFound
}

func (m *Memory) DeleteInbody(_ context.Context, centerID, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	key := scoped(centerID, id)
	if _, ok := m.inbody[key]; !ok {
		return ErrNotFound
	}
	delete(m.inbody, key)
	return nil
}

// ---- 체크인 ----

func (m *Memory) SaveCheckinRecord(_ context.Context, centerID string, c *CheckinRecord) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if c.ID == "" {
		c.ID = m.nextID("chk")
	}
	if c.At.IsZero() {
		c.At = time.Now().UTC()
	}
	c.CenterID = centerID
	cp := *c
	// booking_id 기준 upsert — 같은 예약의 반복 체크인(연타·재시도)이 감사 로그를 오염시키지
	// 않게 멱등 처리한다(P01 2R — 출석 통계·LastVisitAt은 어차피 동일 결과).
	m.checkins[scoped(centerID, "booking-"+c.BookingID)] = &cp
	return nil
}

// ---- 센터 정책 ----

// GetPolicy — 최초 조회 시 DefaultPolicy()를 지연 시딩한다(센터 생성 API가 없는 v1의 부트스트랩,
// README 갭 참고).
func (m *Memory) GetPolicy(_ context.Context, centerID string) (*domain.Policy, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if p, ok := m.policies[centerID]; ok {
		cp := *p
		cp.Normalize() // Firestore.GetPolicy와 같은 읽기 규약(구문서 승격·위약금율 상한 접기)
		return &cp, nil
	}
	def := domain.DefaultPolicy()
	m.policies[centerID] = &def
	cp := def
	return &cp, nil
}

func (m *Memory) SavePolicy(_ context.Context, centerID string, p *domain.Policy) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	cp := *p
	m.policies[centerID] = &cp
	return nil
}

// ---- 사업자 정보(법정 고지 기재사항, v2.13) ----

// GetBusiness — 등록 전이면 **빈 값**을 준다(ErrNotFound 아님). 미등록은 정상 상태이고,
// 이 값을 읽는 경로에 무인증 공개 엔드포인트가 있어 **읽기가 문서를 만들지 않는다**
// (GetPolicy의 지연 시딩과 다른 점 — Firestore 구현 주석 참고).
func (m *Memory) GetBusiness(_ context.Context, centerID string) (*domain.Business, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if b, ok := m.businesses[centerID]; ok {
		cp := *b
		cp.Normalize() // Firestore.GetBusiness와 같은 읽기 규약(공백·등록번호 표기 통일)
		return &cp, nil
	}
	return &domain.Business{}, nil
}

func (m *Memory) SaveBusiness(_ context.Context, centerID string, b *domain.Business) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	cp := *b
	m.businesses[centerID] = &cp
	return nil
}

func (m *Memory) Close() error { return nil }
