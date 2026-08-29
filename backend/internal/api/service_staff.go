package api

// 직원 생애주기(계약 v2.0 — 정정·이관·퇴사·복직). v1.8로 초대가 열렸지만 되돌리기가 없어
// 이름 오타·역할 오지정·정산 조건 변경·퇴사를 처리할 경로가 없었다.
//
// 이 파일의 모든 상태 전이는 **락아웃(센터 영구 잠금)을 최우선으로** 설계돼 있다. UserIndex를
// 쓰는 API가 owner 전용이라 활성 owner가 0명이 되면 자력 복구 경로가 없고(Firestore 직접 편집만이
// 남는다), 그래서 세 겹으로 막는다: 자기 자신 금지 · 마지막 활성 owner 비활성화 금지 ·
// owner→trainer 강등도 같은 카운트에 포함.

import (
	"errors"
	"strings"
	"time"

	"context"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// ---- 퇴사 선행 조건(blockers) ----

// BlockedBooking — 퇴사를 막는 예약 한 건(계약 v2.1). id만 주던 것을 slot_key까지 함께 싣는다.
//
// 어드민은 "무엇을 옮겨야 하는지"를 사람이 읽는 시각("8/25 목 14시")으로 보여줘야 하는데,
// id만으로는 그릴 수 없어 예약 목록을 한 번 더 조회하고 있었다. 서버는 blockers를 만드는
// 시점에 이미 Booking을 손에 들고 있다(collectStaffAssignments가 Booking 자체를 모은다) —
// 없는 정보를 새로 캐는 게 아니라 이미 아는 값을 실어 왕복 한 번을 없애는 것이다.
// TransferStaff의 conflicts(StaffTransferConflict{booking_id, slot_key})와 같은 정보 짝이라
// 어드민의 두 표가 같은 모양을 소비한다.
type BlockedBooking struct {
	ID      string `json:"id"`
	SlotKey string `json:"slot_key"`
}

// StaffBlockers — 퇴사를 막는 담당 잔여물(계약 v2.0 409 본문 + v2.1 bookings 확장). 값은 실제
// ID다 — 어드민이 "무엇을 옮겨야 퇴사가 되는지" 목록에서 바로 짚을 수 있어야 한다.
// 항상 배열(null 금지).
type StaffBlockers struct {
	Members    []string         `json:"members"`
	Passes     []string         `json:"passes"`
	Recurrings []string         `json:"recurrings"`
	Bookings   []BlockedBooking `json:"bookings"`
}

// Empty — 네 목록이 전부 비었는지(퇴사 통과 조건).
func (b StaffBlockers) Empty() bool {
	return len(b.Members) == 0 && len(b.Passes) == 0 && len(b.Recurrings) == 0 && len(b.Bookings) == 0
}

// staffBlockedError — 409 상태코드와 blockers 본문을 함께 나르는 에러. ErrConflict를 감싸므로
// 기존 errors.Is 판별·writeErr 매핑이 그대로 동작하고, writeErr가 본문만 확장해 내보낸다.
type staffBlockedError struct {
	msg      string
	blockers StaffBlockers
}

func (e *staffBlockedError) Error() string { return e.msg }
func (e *staffBlockedError) Unwrap() error { return ErrConflict }

// staffAssignments — uid가 "담당"으로 박혀 있는 것들. deactivate의 선행 조건 검사와 transfer의
// 이관 대상이 **정확히 같은 집합**이어야 "이관 → 퇴사"가 실제로 통과한다(둘이 어긋나면 이관을
// 마쳐도 퇴사가 영원히 409로 막힌다). 그래서 수집을 한 함수로 묶었다.
type staffAssignments struct {
	members    []domain.Member
	passes     []domain.Pass
	recurrings []domain.Recurring
	bookings   []domain.Booking
}

func (a staffAssignments) blockers() StaffBlockers {
	b := StaffBlockers{
		Members: []string{}, Passes: []string{}, Recurrings: []string{},
		Bookings: []BlockedBooking{},
	}
	for _, m := range a.members {
		b.Members = append(b.Members, m.ID)
	}
	for _, p := range a.passes {
		b.Passes = append(b.Passes, p.ID)
	}
	for _, r := range a.recurrings {
		b.Recurrings = append(b.Recurrings, r.ID)
	}
	for _, bk := range a.bookings {
		b.Bookings = append(b.Bookings, BlockedBooking{ID: bk.ID, SlotKey: bk.SlotKey})
	}
	return b
}

// collectStaffAssignments — 계약 v2.0의 네 가지 선행 조건을 그대로 수집한다:
// ① Member.trainer_id ② status=active|scheduled 인 Pass ③ until 미경과 Recurring
// ④ 미래 confirmed Booking.
//
// 만료·환불된 패스와 이미 지난 고정 스케줄·예약은 **일부러 제외**한다. 미래 의무가 없어
// 퇴사를 막을 이유가 없고, 이관 대상에 넣으면 과거 정산 귀속(by_trainer의 revenue는
// Pass.trainer_id를 탄다)이 인수자에게 소급 이전돼 지난 비교표가 소급 파괴된다 —
// 하드 삭제를 하지 않는 이유(계약 v2.0 ②)와 같은 근거다.
func (s *Service) collectStaffAssignments(ctx context.Context, centerID, uid string) (staffAssignments, error) {
	var out staffAssignments
	members, err := s.store.ListMembers(ctx, centerID, uid, "")
	if err != nil {
		return out, err
	}
	out.members = members

	passes, err := s.store.ListPasses(ctx, centerID)
	if err != nil {
		return out, err
	}
	for _, ps := range passes {
		if ps.TrainerID != uid {
			continue
		}
		if ps.Status != domain.PassStatusActive && ps.Status != domain.PassStatusScheduled {
			continue
		}
		out.passes = append(out.passes, ps)
	}

	recurrings, err := s.store.ListRecurrings(ctx, centerID)
	if err != nil {
		return out, err
	}
	todayStr := today()
	for _, r := range recurrings {
		if r.TrainerID != uid {
			continue
		}
		if r.Until != "" && r.Until < todayStr {
			continue // 만료된 규칙(ListRecurrings도 숨긴다 — v1.5)
		}
		out.recurrings = append(out.recurrings, r)
	}

	bookings, err := s.store.ListBookings(ctx, centerID)
	if err != nil {
		return out, err
	}
	now := time.Now()
	for _, b := range bookings {
		if b.TrainerID != uid || b.Status != domain.BookingConfirmed {
			continue
		}
		if start, err := domain.SlotStart(b.SlotKey); err != nil || start.Before(now) {
			continue
		}
		out.bookings = append(out.bookings, b)
	}
	return out, nil
}

// activeOwnerCount — excludeUID를 뺀 활성 owner 수. 락아웃 가드의 유일한 계산식이다 —
// 비활성화·강등 어느 쪽으로 owner가 사라지든 같은 카운트를 본다(우회로를 남기지 않는다).
func (s *Service) activeOwnerCount(ctx context.Context, centerID, excludeUID string) (int, error) {
	list, err := s.store.ListStaff(ctx, centerID)
	if err != nil {
		return 0, err
	}
	n := 0
	for _, st := range list {
		if st.UID == excludeUID || st.Role != domain.RoleOwner || !st.IsActive() {
			continue
		}
		n++
	}
	return n, nil
}

// guardIndexNotLinkedMember — 이 uid가 **회원으로 연결된** 계정인지 본다(role=member면서
// member_id 보유). 그 상태에서 스태프로 (재)승격하면 UserIndex가 uid당 1건이라 member_id가
// 지워지고 그 사람의 회원 앱(내 패스·예약)이 조용히 통째로 잠긴다 — CreateStaff의 같은 가드와
// 동일한 근거다. 계정 분리를 요구하고 여기서 막는다.
//
// 퇴사 강등으로 role=member가 된 계정은 member_id가 비어 있어 여기 걸리지 않는다 — 그래야
// 재고용(재초대)과 복직이 열린다. 이 구분이 v2.0의 "재고용 영구 차단 금지"를 성립시킨다.
func (s *Service) guardIndexNotLinkedMember(ctx context.Context, uid string) error {
	idx, err := s.store.GetUserIndex(ctx, uid)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			return nil
		}
		return err
	}
	if idx.Role == domain.RoleMember && idx.MemberID != "" {
		return errors.Join(ErrConflict, errors.New("이미 회원으로 연결된 계정이에요"))
	}
	return nil
}

// saveStaffIndexRole — UserIndex의 role만 바꾼다(center_id·member_id는 보존). 인덱스가 없으면
// 만든다 — 수동 시딩된 스태프도 정정 한 번으로 인증 경로가 정합해진다.
func (s *Service) saveStaffIndexRole(ctx context.Context, centerID, uid, role string) error {
	idx, err := s.store.GetUserIndex(ctx, uid)
	if err != nil {
		if !errors.Is(err, store.ErrNotFound) {
			return err
		}
		idx = &store.UserIndex{UID: uid, CenterID: centerID}
	}
	idx.Role = role
	if role != domain.RoleMember {
		idx.MemberID = "" // 스태프 인덱스에 회원 스코프가 남으면 안 된다(uid당 1건 한계)
	}
	return s.store.SaveUserIndex(ctx, idx)
}

// saveStaffWithRole — Staff 레코드와 UserIndex의 role을 함께 갱신한다. 갈리면 "화면엔
// 트레이너인데 권한은 대표"가 조용히 생긴다(인증은 UserIndex만, 정산표·배지는 Staff.Role만 읽는다).
//
// 두 쓰기를 묶는 트랜잭션이 없다는 기존 한계(CreateStaff 주석) 위에서 **순서로 안전을 만든다**:
// 권한을 줄이는 쓰기를 먼저 하고, 늘리는 쓰기를 나중에 한다.
//
//	강등(owner→trainer): UserIndex 먼저 → Staff. 중간에 끊기면 "권한은 이미 낮은데 배지만
//	  대표"로 남는다(안전 — 재실행이 수렴시킨다).
//	승격(trainer→owner): Staff 먼저 → UserIndex. 끊기면 "배지는 대표인데 권한은 아직
//	  트레이너"로 남는다(역시 안전).
//
// 반대 순서였다면 잔여 상태가 각각 "표시만 강등되고 권한은 그대로", "권한만 먼저 오름" —
// 둘 다 조용히 권한이 남거나 앞서는 위험한 방향이다.
//
// **inactive 스태프는 UserIndex를 건드리지 않는다**: 퇴사자의 인덱스는 이미 member로 강등된
// 상태인데 여기서 role을 다시 쓰면 이름 정정 한 번이 조용히 권한을 복구시킨다. 복직은
// reactivate 전용 동사만 담당한다.
func (s *Service) saveStaffWithRole(ctx context.Context, centerID string, st *domain.Staff, prevRole string) error {
	sync := st.Role != prevRole && st.IsActive()
	demotion := prevRole == domain.RoleOwner && st.Role != domain.RoleOwner
	if sync && demotion {
		if err := s.saveStaffIndexRole(ctx, centerID, st.UID, st.Role); err != nil {
			return err
		}
	}
	if err := s.store.SaveStaff(ctx, centerID, st); err != nil {
		return err
	}
	if sync && !demotion {
		return s.saveStaffIndexRole(ctx, centerID, st.UID, st.Role)
	}
	return nil
}

// ---- PUT /v1/staff/{uid} — 정정(owner 전용, 머지 시맨틱) ----

// UpdateStaff — 이름 오타·색·정산 조건·역할을 고친다. 상태(status/left_at)는 여기서 받지
// 않는다 — 전용 동사(deactivate/reactivate)만 바꾼다. 바디에 status를 실으면 디코더의
// DisallowUnknownFields가 400을 낸다(RefundPass가 상태 전이를 전용 엔드포인트로 뺀 선례).
func (s *Service) UpdateStaff(ctx context.Context, p Principal, uid string, req domain.StaffUpdate) (*domain.Staff, error) {
	if !p.IsOwner() {
		return nil, ErrForbidden // payout·role이 붙는 레코드다(P13) — CreateStaff와 같은 경계
	}
	req.Normalize()
	if err := req.Validate(); err != nil {
		return nil, err
	}
	if req.IsEmpty() {
		return nil, errors.Join(errBadRequest, errors.New("수정할 항목이 없어요"))
	}
	st, err := s.store.GetStaff(ctx, p.CenterID, uid)
	if err != nil {
		return nil, err
	}
	prevRole := st.Role
	if req.Role != nil && *req.Role != prevRole {
		// 락아웃 가드 ①(자기 강등 금지): owner가 스스로를 trainer로 내리면 그 순간 owner 전용
		// API를 잃는다 — 되돌릴 호출자가 자기 자신뿐이면 복구 경로가 사라진다.
		if p.UID == uid {
			return nil, errors.Join(errBadRequest, errors.New("본인의 역할은 바꿀 수 없어요"))
		}
		// 락아웃 가드 ③(강등도 같은 카운트): 비활성화만 막고 강등을 열어두면 owner 0명이
		// 되는 우회로가 남는다.
		if prevRole == domain.RoleOwner {
			n, err := s.activeOwnerCount(ctx, p.CenterID, uid)
			if err != nil {
				return nil, err
			}
			if n == 0 {
				return nil, errors.Join(ErrConflict, errors.New("마지막 활성 대표의 역할은 바꿀 수 없어요"))
			}
		}
	}
	if req.Name != nil {
		st.Name = *req.Name
	}
	if req.Color != nil {
		st.Color = *req.Color
	}
	if req.Payout != nil {
		st.Payout = *req.Payout
	}
	if req.Role != nil {
		st.Role = *req.Role
	}
	if err := s.saveStaffWithRole(ctx, p.CenterID, st, prevRole); err != nil {
		return nil, err
	}
	return st, nil
}

// ---- POST /v1/staff/{uid}/transfer — 담당 일괄 이관(owner 전용) ----

// StaffTransferMoved — 이관된 건수(계약 v2.0 응답 moved).
type StaffTransferMoved struct {
	Members    int `json:"members"`
	Passes     int `json:"passes"`
	Recurrings int `json:"recurrings"`
	Bookings   int `json:"bookings"`
}

// StaffTransferConflict — 인수자의 슬롯 충돌로 **옮기지 않은** 예약.
type StaffTransferConflict struct {
	BookingID string `json:"booking_id"`
	SlotKey   string `json:"slot_key"`
}

type StaffTransferResult struct {
	Moved     StaffTransferMoved      `json:"moved"`
	Conflicts []StaffTransferConflict `json:"conflicts"`
}

// TransferStaff — 담당 회원·패스·고정 스케줄·미래 예약을 인수자에게 한 번에 넘긴다.
// to_uid=""는 미배정으로 회수(3계층에서 ""는 1급 상태다 — "미배정" 필터가 그 값을 쓴다).
//
// 인수자가 같은 슬롯에 이미 수업이 있으면 그 예약은 옮기지 않고 conflicts로 보고한다 —
// 트레이너 동시 1건 규칙(R2)을 이관이 우회하면 슬롯 그리드가 이중 배정으로 깨진다.
// 남은 예약은 그대로 퇴사를 계속 막는다(계약 v2.0 — 사람이 재조정해야 하는 자리다).
func (s *Service) TransferStaff(ctx context.Context, p Principal, uid string, toUID *string) (StaffTransferResult, error) {
	res := StaffTransferResult{Conflicts: []StaffTransferConflict{}}
	if !p.IsOwner() {
		return res, ErrForbidden
	}
	if toUID == nil {
		// ""는 "미배정 회수"라는 유효한 지시라서 필드 누락과 구분해야 한다 — 빈 바디 하나로
		// 담당이 통째로 날아가는 사고를 막는다.
		return res, errors.Join(errBadRequest, errors.New("to_uid가 필요해요(미배정으로 회수하려면 빈 문자열)"))
	}
	to := strings.TrimSpace(*toUID)
	if uid == "" {
		return res, store.ErrNotFound
	}
	if _, err := s.store.GetStaff(ctx, p.CenterID, uid); err != nil {
		return res, err
	}
	if to == uid {
		return res, errors.Join(errBadRequest, errors.New("같은 스태프에게는 이관할 수 없어요"))
	}
	if to != "" {
		toStaff, err := s.store.GetStaff(ctx, p.CenterID, to)
		if err != nil {
			return res, err
		}
		if !toStaff.IsActive() {
			// 퇴사자에게 넘기면 그 사람의 퇴사 선행 조건이 되살아난다(문제를 옆으로 옮길 뿐).
			return res, errors.Join(ErrConflict, errors.New("퇴사 처리된 스태프에게는 이관할 수 없어요"))
		}
	}

	as, err := s.collectStaffAssignments(ctx, p.CenterID, uid)
	if err != nil {
		return res, err
	}
	now := time.Now().UTC()

	for i := range as.members {
		mem := as.members[i]
		mem.TrainerID = to
		if _, err := s.store.SaveMember(ctx, p.CenterID, &mem); err != nil {
			return res, err
		}
		res.Moved.Members++
	}

	for i := range as.passes {
		ps := as.passes[i]
		// 이관 이벤트(설계03 §9)와 담당 변경을 **한 트랜잭션**으로 넣는다(P13 H2 계열).
		//
		// 종전에는 원장을 먼저 남기고 UpdatePass를 따로 불렀다 — 순서 자체는 재시도를 고려한
		// 것이었지만(패스만 옮겨진 채 실패하면 재수집에서 빠져 감사 기록을 잃는다), UpdatePass가
		// 문서 통째 교체라 이관 도중 들어온 홀딩·환불이 조용히 되감기는 창은 그대로였다.
		// mutate가 트랜잭션 안에서 읽은 최신 문서의 trainer_id만 바꾸므로 그 창이 닫힌다.
		if _, err := s.store.UpdatePassWithLedger(ctx, p.CenterID, ps.ID,
			func(fresh *domain.Pass, entries []domain.Ledger) (*domain.Ledger, error) {
				fresh.TrainerID = to
				fresh.Remaining = domain.Sum(entries) // 저장 스냅샷 정합(M3)
				return &domain.Ledger{
					MemberID: fresh.MemberID, Delta: 0, Reason: domain.ReasonTransfer, By: p.UID, At: now,
				}, nil
			}); err != nil {
			return res, err
		}
		res.Moved.Passes++
	}

	for i := range as.recurrings {
		r := as.recurrings[i]
		r.TrainerID = to
		if err := s.store.UpdateRecurring(ctx, p.CenterID, &r); err != nil {
			return res, err
		}
		res.Moved.Recurrings++
	}

	for _, b := range as.bookings {
		err := s.store.ReassignBookingTrainer(ctx, p.CenterID, b.ID, to)
		switch {
		case err == nil:
			res.Moved.Bookings++
		case errors.Is(err, domain.ErrTrainerBusy):
			res.Conflicts = append(res.Conflicts, StaffTransferConflict{BookingID: b.ID, SlotKey: b.SlotKey})
		case errors.Is(err, store.ErrStateConflict), errors.Is(err, store.ErrNotFound):
			// 수집과 이관 사이에 취소·완료된 예약 — 옮길 것이 남아 있지 않다.
		default:
			return res, err
		}
	}
	return res, nil
}

// ---- POST /v1/staff/{uid}/deactivate — 퇴사 처리(owner 전용) ----

// DeactivateStaff — 선행 조건(담당 회원·활성 패스·미만료 고정 스케줄·미래 예약)이 전부 비어야
// 통과한다. 이관 없이 비활성화하면 담당 회원이 "목록엔 미배정으로 보이는데 미배정 필터·KPI엔
// 잡히지 않는" 발견 불가능 상태가 되고, 트레이너 퇴사가 사업자 귀책으로 해석되는 국내 관행상
// 잔여 회차 환급 리스크로 이어진다 — 재배정은 편의가 아니라 손해 방지 장치다(계약 v2.0).
//
// leftAtRaw는 RFC3339(생략 = 지금). 퇴사일 소급 입력이 이 엔드포인트의 존재 이유 중 하나라
// 받되, Staff.left_at을 바꾸는 경로는 여기뿐이다(정정 PUT은 못 건드린다).
func (s *Service) DeactivateStaff(ctx context.Context, p Principal, uid, leftAtRaw string) (*domain.Staff, error) {
	if !p.IsOwner() {
		return nil, ErrForbidden
	}
	if uid == "" {
		return nil, store.ErrNotFound
	}
	leftAt := time.Now().UTC()
	if leftAtRaw != "" {
		t, err := time.Parse(time.RFC3339, leftAtRaw)
		if err != nil {
			return nil, errors.Join(errBadRequest, errors.New("left_at은 RFC3339 형식이어야 해요(예: 2026-08-31T09:00:00+09:00)"))
		}
		leftAt = t.UTC()
	}
	st, err := s.store.GetStaff(ctx, p.CenterID, uid)
	if err != nil {
		return nil, err
	}
	// 락아웃 가드 ①(자기 자신): 마지막 owner가 아니어도 막는다. 비활성화 즉시 owner 전용
	// API를 잃어 스스로 되돌릴 수 없고, 실수를 깨달은 시점엔 이미 호출 자격이 없다.
	if p.UID == uid {
		return nil, errors.Join(errBadRequest, errors.New("본인은 퇴사 처리할 수 없어요"))
	}
	if !st.IsActive() {
		return nil, errors.Join(errBadRequest, errors.New("이미 퇴사 처리된 스태프예요"))
	}
	// 락아웃 가드 ②(마지막 활성 owner): owner 0명 = UserIndex를 쓰는 API가 전부 막혀
	// Firestore 직접 편집 외에는 복구 경로가 없다.
	if st.Role == domain.RoleOwner {
		n, err := s.activeOwnerCount(ctx, p.CenterID, uid)
		if err != nil {
			return nil, err
		}
		if n == 0 {
			return nil, errors.Join(ErrConflict, errors.New("마지막 활성 대표는 퇴사 처리할 수 없어요"))
		}
	}
	as, err := s.collectStaffAssignments(ctx, p.CenterID, uid)
	if err != nil {
		return nil, err
	}
	if b := as.blockers(); !b.Empty() {
		return nil, &staffBlockedError{
			msg:      "담당이 남아 있어 퇴사 처리할 수 없어요 — 먼저 이관해주세요",
			blockers: b,
		}
	}

	// 쓰기는 **권한을 줄이는 순서**로(saveStaffWithRole과 같은 원칙).
	// ① Firebase 계정 잠금: 실패하면 아무것도 바꾸지 않은 채 에러 — 그대로 재시도하면 된다
	//    (뒤로 미루면 "레코드는 퇴사인데 계정은 살아 있고 재시도는 400에 막히는" 상태가 된다).
	if err := s.users.DisableUser(ctx, uid); err != nil {
		return nil, err
	}
	// ② UserIndex 강등 — 즉시 차단의 본체다(인증이 요청마다 이 문서를 읽고 캐시가 없다).
	//    member로 내리되 member_id가 없어 회원 스코프 엔드포인트도 전부 403이 된다.
	//    (부작용: 퇴사자는 이제 join 계열의 guardNotStaff에 걸리지 않는다 — 본인 명의 회원으로
	//     등록되는 정상 경로다. 복직 시 인덱스를 다시 스태프로 덮으므로 그 조합은 피해야 한다.)
	if err := s.saveStaffIndexRole(ctx, p.CenterID, uid, domain.RoleMember); err != nil {
		return nil, err
	}
	// ③ Staff 레코드. 여기까지 못 와도 사람은 이미 잠겨 있다(안전한 방향의 잔여 상태).
	st.Status = domain.StaffStatusInactive
	st.LeftAt = &leftAt
	if err := s.store.SaveStaff(ctx, p.CenterID, st); err != nil {
		return nil, err
	}
	return st, nil
}

// ---- POST /v1/staff/{uid}/reactivate — 복직(owner 전용) ----

// ReactivateStaff — 재입사 복원. 순서는 deactivate의 정확한 역순이다(권한을 늘리는 쓰기는
// 마지막): Staff 레코드 → UserIndex 복원 → Firebase 잠금 해제.
func (s *Service) ReactivateStaff(ctx context.Context, p Principal, uid string) (*domain.Staff, error) {
	if !p.IsOwner() {
		return nil, ErrForbidden
	}
	if uid == "" {
		return nil, store.ErrNotFound
	}
	st, err := s.store.GetStaff(ctx, p.CenterID, uid)
	if err != nil {
		return nil, err
	}
	if st.IsActive() {
		return nil, errors.Join(errBadRequest, errors.New("이미 재직 중인 스태프예요"))
	}
	// 퇴사 후 본인 명의로 회원 등록까지 마친 계정이면 복직이 그 연결을 지운다 — 조용히
	// 깨뜨리는 대신 여기서 알린다(계정 분리 후 새 이메일로 초대하는 것이 remedy).
	if err := s.guardIndexNotLinkedMember(ctx, uid); err != nil {
		return nil, err
	}
	st.Status = domain.StaffStatusActive
	st.LeftAt = nil
	if err := s.store.SaveStaff(ctx, p.CenterID, st); err != nil {
		return nil, err
	}
	if err := s.saveStaffIndexRole(ctx, p.CenterID, uid, st.Role); err != nil {
		return nil, err
	}
	if err := s.users.EnableUser(ctx, uid); err != nil {
		return nil, err
	}
	return st, nil
}
