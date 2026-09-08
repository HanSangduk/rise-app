package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/ramsang/rise-backend/internal/domain"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Firestore — 실 DB 구현(설계03 §11). 문서 필드명은 도메인 struct의 json 태그를 그대로 쓴다
// (아래 toDoc/fromDoc가 json 라운드트립으로 매핑) — 클라이언트가 보는 JSON과 Firestore 필드명이
// 항상 일치해 별도 매핑 문서가 필요 없다(wodshot 패턴 재사용).
//
// 컬렉션 레이아웃:
//
//	centers/{centerID}                 센터 정책(Policy)을 문서 필드로 직접 보관(전용 엔드포인트 없음, README 갭)
//	  staff/{uid}  members/{id}  passes/{id}  ledger/{id}
//	  slots/{slotKey}  bookings/{id}  recurring/{id}
//	  homeworks/{id}  hwChecks/{memberID_hwID_date}
//	  payments/{id}  contracts/{id}(v1.1 정합 패치)  bodyPhotos/{id}  inbody/{id}  checkins/{id}
//	  consult_requests/{id}(재등록/상담 요청, v2.20 — 회원이 이미 센터 귀속이라 센터 스코프)
//	users/{uid}            UserIndex(인증 인덱스, 센터 무관 — 설계03 §6 users/{uid} 대응)
//	join_requests/{id}     JoinRequest(승인 전엔 특정 센터에 귀속되지 않아 최상위)
//
// **최상위 컬렉션은 탈퇴 파기의 사각지대다**(P53): PurgeMemberPersonalData는 center(...) 아래만
// 훑으므로 join_requests에 닿지 못했고, 이름·전화번호가 그대로 살아남았다. 최상위에 회원의
// 무언가를 새로 두려면 파기 경로를 함께 만들어라(DeleteJoinRequestsByUID가 그 선례다).
//
// 주의: 일부 쿼리는 복합 인덱스가 필요하다(예: ledger의 member_id+pass_id 동시 필터).
// 최초 실행 시 Firestore가 콘솔 링크로 인덱스 생성을 안내한다(wodshot 자문자답 선례와 동일).
type Firestore struct {
	c *firestore.Client
}

// NewFirestore — projectID로 클라이언트 생성. 에뮬레이터는 FIRESTORE_EMULATOR_HOST 자동 감지.
func NewFirestore(ctx context.Context, projectID string) (*Firestore, error) {
	c, err := firestore.NewClient(ctx, projectID)
	if err != nil {
		return nil, fmt.Errorf("firestore client: %w", err)
	}
	return &Firestore{c: c}, nil
}

func (f *Firestore) Close() error { return f.c.Close() }

// center — centers/{centerID} 문서 참조. 대부분의 컬렉션이 이 아래에 매달린다.
func (f *Firestore) center(centerID string) *firestore.DocumentRef {
	return f.c.Collection("centers").Doc(centerID)
}

// ---- json 라운드트립 어댑터(wodshot과 동일 패턴) ----

func toDoc(v any) map[string]any {
	b, _ := json.Marshal(v)
	var m map[string]any
	_ = json.Unmarshal(b, &m)
	return m
}

func fromDoc[T any](data map[string]any) (*T, error) {
	b, _ := json.Marshal(data)
	var t T
	if err := json.Unmarshal(b, &t); err != nil {
		return nil, err
	}
	return &t, nil
}

// mapNotFound — NotFound RPC만 ErrNotFound로 바꾼다. **빈 문서 ID는 여기로 오지 않는다**:
// Doc("")의 실패는 InvalidArgument라 그대로 500이 된다 — 그래서 ID로 한 건을 읽는 메서드는
// 모두 checkDocID(errors.go)로 먼저 거른다.
func mapNotFound(err error) error {
	if status.Code(err) == codes.NotFound {
		return ErrNotFound
	}
	return err
}

// docKey·hwCheckDocID(문서 ID 규칙)와 목록 정렬자는 order.go에 있다 — Memory가 같은 규칙으로
// 정렬해야 두 스토어의 순서가 일치한다.

// ---- 인증 인덱스 ----

func (f *Firestore) GetUserIndex(ctx context.Context, uid string) (*UserIndex, error) {
	if err := checkDocID(uid); err != nil {
		return nil, err
	}
	snap, err := f.c.Collection("users").Doc(uid).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[UserIndex](snap.Data())
}

func (f *Firestore) SaveUserIndex(ctx context.Context, u *UserIndex) error {
	_, err := f.c.Collection("users").Doc(u.UID).Set(ctx, toDoc(u))
	return err
}

// DeleteUserIndex — 없는 uid도 성공(Firestore의 Delete는 원래 그렇고, Memory도 같은 규칙으로
// 맞췄다). 근거는 Store 인터페이스 주석 참고.
func (f *Firestore) DeleteUserIndex(ctx context.Context, uid string) error {
	if err := checkDocID(uid); err != nil {
		return err
	}
	_, err := f.c.Collection("users").Doc(uid).Delete(ctx)
	return err
}

// ---- 가입 매칭(P48) ----

func (f *Firestore) FindMemberByPhone(ctx context.Context, centerID, phone string) (*domain.Member, error) {
	target := normalizePhone(phone)
	if target == "" {
		return nil, ErrNotFound
	}
	// 정규화 전화번호 색인이 없어 전체 스캔 후 Go에서 비교한다(친구 샵 규모엔 충분 —
	// 대규모 멀티센터 전환 시 정규화 필드를 별도 색인해야 한다, README 갭 참고).
	// 첫 히트에서 멈추지 않는다: 같은 번호 회원이 여럿이면 iterator 순서에 따라 다른 사람이
	// 나오므로, 끝까지 훑어 betterPhoneMatch로 고른다(Memory와 같은 규칙 — 같은 함수를 쓴다).
	iter := f.center(centerID).Collection("members").Documents(ctx)
	defer iter.Stop()
	var best *domain.Member
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		mem, err := fromDoc[domain.Member](snap.Data())
		if err != nil {
			return nil, err
		}
		if normalizePhone(mem.Phone) == target && betterPhoneMatch(mem, best) {
			best = mem
		}
	}
	if best == nil {
		return nil, ErrNotFound
	}
	return best, nil
}

func (f *Firestore) CreateJoinRequest(ctx context.Context, jr *JoinRequest) (string, error) {
	ref := f.c.Collection("join_requests").NewDoc()
	jr.ID = ref.ID
	if jr.CreatedAt.IsZero() {
		jr.CreatedAt = time.Now().UTC()
	}
	if jr.Status == "" {
		jr.Status = JoinPending
	}
	if _, err := ref.Set(ctx, toDoc(jr)); err != nil {
		return "", err
	}
	return jr.ID, nil
}

func (f *Firestore) GetJoinRequest(ctx context.Context, id string) (*JoinRequest, error) {
	if err := checkDocID(id); err != nil {
		return nil, err
	}
	snap, err := f.c.Collection("join_requests").Doc(id).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[JoinRequest](snap.Data())
}

// UpdateJoinRequest — 없는 ID면 ErrNotFound(UpdateRecurring과 같은 존재 확인 선행).
func (f *Firestore) UpdateJoinRequest(ctx context.Context, jr *JoinRequest) error {
	if err := checkDocID(jr.ID); err != nil {
		return err
	}
	ref := f.c.Collection("join_requests").Doc(jr.ID)
	if _, err := ref.Get(ctx); err != nil {
		return mapNotFound(err)
	}
	_, err := ref.Set(ctx, toDoc(jr))
	return err
}

// ListJoinRequests — join_requests는 최상위 컬렉션이라(승인 전엔 센터 귀속 전) center_id로 필터한다
// (GET /v1/join/requests, 어드민 가정 승인, v1.1 정합 패치).
func (f *Firestore) ListJoinRequests(ctx context.Context, centerID string) ([]JoinRequest, error) {
	iter := f.c.Collection("join_requests").Where("center_id", "==", centerID).Documents(ctx)
	defer iter.Stop()
	out := []JoinRequest{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		jr, err := fromDoc[JoinRequest](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *jr)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) }) // 최신 먼저
	return out, nil
}

// ListJoinRequestsByUID — 신청자 본인의 요청(센터 무관, v2.34). 계약·근거는 Store 인터페이스 주석.
// `uid ==` 단일 필드 쿼리(DeleteJoinRequestsByUID와 같은 쿼리)라 복합 인덱스가 필요 없다 —
// 정렬은 메모리에서 한다(ListJoinRequests와 같은 규약).
func (f *Firestore) ListJoinRequestsByUID(ctx context.Context, uid string) ([]JoinRequest, error) {
	out := []JoinRequest{}
	if uid == "" {
		return out, nil // `uid == ""`는 uid가 빈 레거시 문서에 실제로 매칭된다 — 남의 대기 상태가 된다
	}
	iter := f.c.Collection("join_requests").Where("uid", "==", uid).Documents(ctx)
	defer iter.Stop()
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		jr, err := fromDoc[JoinRequest](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *jr)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) }) // 최신 먼저
	return out, nil
}

// DeleteJoinRequestsByUID — 회원탈퇴의 가입 요청 파기(P53). 계약·근거는 Store 인터페이스 주석.
//
// **센터로 좁히지 않는다** — uid 단일 필드 필터라 복합 인덱스도 필요 없다. 삭제는
// deleteWhereMember와 같은 방식(순회를 끝낸 뒤 지운다 — iterator를 돌면서 같은 컬렉션을
// 수정하지 않는다). 부분 실패는 지운 만큼의 건수와 함께 올라가고, 재시도가 남은 것을
// 마저 지운다(각 삭제는 이미 없는 문서에도 성공이라 멱등).
func (f *Firestore) DeleteJoinRequestsByUID(ctx context.Context, uid string) (int, error) {
	if uid == "" {
		// 빈 uid로 훑으면 uid 필드가 빈 문서(레거시·시딩 잔여)를 싹 지운다 — 탈퇴자의 것이
		// 아닌 문서를 지우는 유일한 경로라 여기서 끊는다. 지울 대상이 없는 것은 에러가 아니다.
		return 0, nil
	}
	iter := f.c.Collection("join_requests").Where("uid", "==", uid).Documents(ctx)
	defer iter.Stop()
	refs := []*firestore.DocumentRef{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return 0, err
		}
		refs = append(refs, snap.Ref)
	}
	for i, ref := range refs {
		if _, err := ref.Delete(ctx); err != nil {
			return i, err
		}
	}
	return len(refs), nil
}

// ---- 재등록/상담 요청(계약 v2.20, P42) — 센터 스코프 컬렉션 ----

func (f *Firestore) CreateConsultRequest(ctx context.Context, centerID string, cr *ConsultRequest) (string, error) {
	ref := f.center(centerID).Collection("consult_requests").NewDoc()
	cr.ID = ref.ID
	if cr.CreatedAt.IsZero() {
		cr.CreatedAt = time.Now().UTC()
	}
	if cr.Status == "" {
		cr.Status = ConsultPending
	}
	if _, err := ref.Set(ctx, toDoc(cr)); err != nil {
		return "", err
	}
	return cr.ID, nil
}

func (f *Firestore) GetConsultRequest(ctx context.Context, centerID, id string) (*ConsultRequest, error) {
	if err := checkDocID(id); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("consult_requests").Doc(id).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[ConsultRequest](snap.Data())
}

// UpdateConsultRequest — 없는 ID면 ErrNotFound(UpdateJoinRequest와 같은 존재 확인 선행).
func (f *Firestore) UpdateConsultRequest(ctx context.Context, centerID string, cr *ConsultRequest) error {
	if err := checkDocID(cr.ID); err != nil {
		return err
	}
	ref := f.center(centerID).Collection("consult_requests").Doc(cr.ID)
	if _, err := ref.Get(ctx); err != nil {
		return mapNotFound(err)
	}
	_, err := ref.Set(ctx, toDoc(cr))
	return err
}

func (f *Firestore) ListConsultRequests(ctx context.Context, centerID, memberID string) ([]ConsultRequest, error) {
	coll := f.center(centerID).Collection("consult_requests")
	var iter *firestore.DocumentIterator
	if memberID != "" {
		iter = coll.Where("member_id", "==", memberID).Documents(ctx)
	} else {
		iter = coll.Documents(ctx)
	}
	defer iter.Stop()
	out := []ConsultRequest{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		cr, err := fromDoc[ConsultRequest](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *cr)
	}
	// 오래 기다린 요청이 위로(데스크 큐) — 동률은 ID로 안정화(Memory 구현과 같은 규약).
	sort.Slice(out, func(i, j int) bool {
		if !out[i].CreatedAt.Equal(out[j].CreatedAt) {
			return out[i].CreatedAt.Before(out[j].CreatedAt)
		}
		return out[i].ID < out[j].ID
	})
	return out, nil
}

// ---- 회원 ----

func (f *Firestore) ListMembers(ctx context.Context, centerID, trainerID, q string) ([]domain.Member, error) {
	coll := f.center(centerID).Collection("members")
	var iter *firestore.DocumentIterator
	if trainerID != "" {
		iter = coll.Where("trainer_id", "==", trainerID).Documents(ctx)
	} else {
		iter = coll.Documents(ctx)
	}
	defer iter.Stop()
	ql := strings.ToLower(strings.TrimSpace(q))
	out := []domain.Member{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		mem, err := fromDoc[domain.Member](snap.Data())
		if err != nil {
			return nil, err
		}
		if ql != "" && !strings.Contains(strings.ToLower(mem.Name), ql) && !strings.Contains(mem.Phone, q) {
			continue
		}
		out = append(out, *mem)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

func (f *Firestore) GetMember(ctx context.Context, centerID, id string) (*domain.Member, error) {
	if err := checkDocID(id); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("members").Doc(id).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[domain.Member](snap.Data())
}

func (f *Firestore) SaveMember(ctx context.Context, centerID string, mem *domain.Member) (string, error) {
	coll := f.center(centerID).Collection("members")
	if mem.ID == "" {
		mem.ID = coll.NewDoc().ID
	}
	if _, err := coll.Doc(mem.ID).Set(ctx, toDoc(mem)); err != nil {
		return "", err
	}
	return mem.ID, nil
}

// PurgeMemberPersonalData — 회원탈퇴 집행(v2.11). 계약·순서 규약은 Store 인터페이스 주석 참고.
//
// **트랜잭션을 쓰지 않는다**(의도적). 여섯 컬렉션을 member_id로 훑어야 하는데 트랜잭션에
// 넣으면 그 컬렉션들이 통째로 잠기고, 쓰기 500건 상한에도 걸린다 — v2.6이 환불 뒷정리를
// 트랜잭션 밖에 둔 것과 **같은 판단**이다. 대신 순서로 안전을 만든다: 기록을 먼저 지우고
// 회원 문서를 마지막에 쓰므로, 중간 실패는 "이름이 아직 남아 있는" 눈에 보이는 상태로 멈추고
// 재시도가 이어서 완결한다(각 삭제는 이미 없는 문서에도 성공이라 멱등).
func (f *Firestore) PurgeMemberPersonalData(ctx context.Context, centerID string, anonymized *domain.Member) (PurgeCounts, error) {
	var c PurgeCounts
	if anonymized == nil {
		return c, ErrNotFound
	}
	memberID := anonymized.ID
	if err := checkDocID(memberID); err != nil {
		return c, err
	}
	center := f.center(centerID)
	if _, err := center.Collection("members").Doc(memberID).Get(ctx); err != nil {
		return c, mapNotFound(err)
	}

	// 컬렉션마다 member_id 단일 필드 필터라 복합 인덱스가 필요 없다(자동 인덱스로 충분).
	for _, target := range []struct {
		coll  string
		count *int
	}{
		// 컬렉션 이름은 각 Create*/List* 구현과 **글자 그대로** 일치해야 한다 — 오타 하나면
		// 그 컬렉션만 조용히 0건 삭제로 지나간다(쿼리는 성공하고 결과가 비었을 뿐이라
		// 에러조차 나지 않는다). workout_logs만 스네이크인 것도 그쪽 구현이 그렇기 때문이다.
		{"bodyPhotos", &c.BodyPhotos},
		{"inbody", &c.Inbody},
		{"workout_logs", &c.WorkoutLogs},
		{"hwChecks", &c.HwChecks},
		{"checkins", &c.Checkins},
		{"recurring", &c.Recurrings},
		// consult_requests(P53): 회원이 남긴 자유 서술 메모를 품는다. 여기 없던 동안
		// 탈퇴는 성공을 보고하면서 그 메모만 남겼다 — 최상위 join_requests와 함께
		// 이번 결함의 절반이다(다른 절반은 DeleteJoinRequestsByUID가 맡는다).
		{"consult_requests", &c.ConsultRequests},
	} {
		n, err := f.deleteWhereMember(ctx, center.Collection(target.coll), memberID)
		if err != nil {
			return c, err
		}
		*target.count = n
	}

	// 가명화된 회원 문서는 **마지막에**(순서 규약 — 실패 시 미완료가 눈에 보여야 한다).
	if _, err := center.Collection("members").Doc(memberID).Set(ctx, toDoc(anonymized)); err != nil {
		return c, err
	}
	return c, nil
}

// deleteWhereMember — member_id가 일치하는 문서를 전부 지우고 건수를 돌려준다.
// 삭제는 BulkWriter 대신 순차 호출이다: 회원 한 명의 사진·인바디·수업기록은 많아야 수십 건이라
// 배치 오류 수집의 복잡도를 살 이유가 없고, 실패 시 어디까지 지웠는지가 건수로 그대로 남는다.
func (f *Firestore) deleteWhereMember(ctx context.Context, coll *firestore.CollectionRef, memberID string) (int, error) {
	iter := coll.Where("member_id", "==", memberID).Documents(ctx)
	defer iter.Stop()
	refs := []*firestore.DocumentRef{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return 0, err
		}
		refs = append(refs, snap.Ref)
	}
	// 순회를 끝낸 뒤에 지운다 — iterator를 돌면서 같은 컬렉션을 수정하지 않는다.
	for i, ref := range refs {
		if _, err := ref.Delete(ctx); err != nil {
			return i, err
		}
	}
	return len(refs), nil
}

// ---- 원장 ----

func (f *Firestore) AppendLedger(ctx context.Context, centerID string, e *domain.Ledger) (string, error) {
	ref := f.center(centerID).Collection("ledger").NewDoc()
	e.ID = ref.ID
	if e.At.IsZero() {
		e.At = time.Now().UTC()
	}
	if _, err := ref.Set(ctx, toDoc(e)); err != nil {
		return "", err
	}
	return e.ID, nil
}

func (f *Firestore) ListLedger(ctx context.Context, centerID, memberID, passID string) ([]domain.Ledger, error) {
	q := f.center(centerID).Collection("ledger").Where("member_id", "==", memberID)
	if passID != "" {
		q = q.Where("pass_id", "==", passID)
	}
	iter := q.Documents(ctx)
	defer iter.Stop()
	out := []domain.Ledger{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		e, err := fromDoc[domain.Ledger](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].At.After(out[j].At) }) // 최신 먼저
	return out, nil
}

// ---- 회원권 ----

func (f *Firestore) CreatePass(ctx context.Context, centerID string, p *domain.Pass) (string, error) {
	ref := f.center(centerID).Collection("passes").NewDoc()
	p.ID = ref.ID
	if _, err := ref.Set(ctx, toDoc(p)); err != nil {
		return "", err
	}
	return p.ID, nil
}

func (f *Firestore) GetPass(ctx context.Context, centerID, id string) (*domain.Pass, error) {
	if err := checkDocID(id); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("passes").Doc(id).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[domain.Pass](snap.Data())
}

// UpdatePass — 없는 ID면 ErrNotFound. Set은 upsert라 존재 확인을 먼저 한다(UpdateRecurring과
// 같은 이유·같은 패턴): 오타 ID 하나로 **원장도 계약도 없는 유령 패스 문서**가 생기고, Memory는
// 같은 호출에서 ErrNotFound라 로컬에선 재현되지 않는 차이가 된다(P13 요구3 실측 항목).
func (f *Firestore) UpdatePass(ctx context.Context, centerID string, p *domain.Pass) error {
	if err := checkDocID(p.ID); err != nil {
		return err
	}
	ref := f.center(centerID).Collection("passes").Doc(p.ID)
	if _, err := ref.Get(ctx); err != nil {
		return mapNotFound(err)
	}
	_, err := ref.Set(ctx, toDoc(p))
	return err
}

// IssuePass — 발급 3단을 한 트랜잭션으로(P13 C3). 읽기가 없는 트랜잭션이라 사실상 원자적 배치다.
func (f *Firestore) IssuePass(ctx context.Context, centerID string, p *domain.Pass, entry *domain.Ledger, contract *domain.Contract) error {
	passRef := f.center(centerID).Collection("passes").NewDoc()
	p.ID = passRef.ID
	var ledgerRef, contractRef *firestore.DocumentRef
	if entry != nil {
		ledgerRef = f.center(centerID).Collection("ledger").NewDoc()
		entry.ID = ledgerRef.ID
		entry.PassID = p.ID
		if entry.At.IsZero() {
			entry.At = time.Now().UTC()
		}
	}
	if contract != nil {
		contractRef = f.center(centerID).Collection("contracts").NewDoc()
		contract.ID = contractRef.ID
		contract.PassID = p.ID
	}
	return f.c.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		if err := tx.Set(passRef, toDoc(p)); err != nil {
			return err
		}
		if ledgerRef != nil {
			if err := tx.Set(ledgerRef, toDoc(entry)); err != nil {
				return err
			}
		}
		if contractRef != nil {
			if err := tx.Set(contractRef, toDoc(contract)); err != nil {
				return err
			}
		}
		return nil
	})
}

// UpdatePassWithLedger — 패스 갱신 + 원장 적재를 한 트랜잭션으로(환불·홀딩·재개·이관).
func (f *Firestore) UpdatePassWithLedger(ctx context.Context, centerID, passID string, mutate PassMutator) (*domain.Pass, error) {
	return f.updatePassInTx(ctx, centerID, passID, mutate, nil, nil)
}

// UpdatePassWithLedgerAndContracts — 환불 마감 + 지목 계약 무효화를 한 트랜잭션으로(P37, 계약
// v2.15). 계약을 찾는 스캔은 호출측이 트랜잭션 밖에서 끝내고(컬렉션 잠금 회피), 여기서는 그
// ID들을 점읽기로 다시 읽어 sweep이 최신 상태 위에서 재판정한다.
func (f *Firestore) UpdatePassWithLedgerAndContracts(ctx context.Context, centerID, passID string, mutate PassMutator, contractIDs []string, sweep ContractSweepMutator) (*domain.Pass, error) {
	return f.updatePassInTx(ctx, centerID, passID, mutate, contractIDs, sweep)
}

// updatePassInTx — 위 두 동사의 공용 본체. 읽기(패스 + 그 패스의 원장 전체 + 지목 계약)가 전부
// 쓰기보다 앞선다(SDK 제약 — CancelAtomic과 동일 패턴). mutate/sweep은 경합 재시도 시 다시
// 호출될 수 있으므로 매번 **다시 읽은** 문서 위에서 판정한다 — 이것이 "서비스 레이어의 재확인은
// 트랜잭션 밖이라 원리적으로 창을 못 닫는다"를 닫는 지점이다.
func (f *Firestore) updatePassInTx(ctx context.Context, centerID, passID string, mutate PassMutator, contractIDs []string, sweep ContractSweepMutator) (*domain.Pass, error) {
	if err := checkDocID(passID); err != nil {
		return nil, err
	}
	for _, cid := range contractIDs {
		if err := checkDocID(cid); err != nil {
			return nil, err
		}
	}
	// 같은 계약 ID가 두 번 지목되면 한 트랜잭션이 같은 문서를 두 번 쓴다(아래 contractWrites) —
	// 호출측(RefundPass 후보 선정)은 중복 없이 추리지만 여기서 한 번 더 거른다(P40 — P37 리뷰
	// 권고). 사본으로 거른다: 호출측 슬라이스를 제자리에서 줄이면 재사용하는 쪽이 놀란다.
	// Memory는 맵 커밋이라 중복이 자연 흡수된다 — 이 가드는 Firestore 쓰기 목록 전용이다.
	if len(contractIDs) > 1 {
		seen := make(map[string]struct{}, len(contractIDs))
		uniq := make([]string, 0, len(contractIDs))
		for _, cid := range contractIDs {
			if _, dup := seen[cid]; dup {
				continue
			}
			seen[cid] = struct{}{}
			uniq = append(uniq, cid)
		}
		contractIDs = uniq
	}
	passRef := f.center(centerID).Collection("passes").Doc(passID)
	var out *domain.Pass
	err := f.c.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		out = nil // 재시도마다 초기화 — 실패한 시도의 결과가 남지 않게
		snap, err := tx.Get(passRef)
		if err != nil {
			return mapNotFound(err)
		}
		pass, err := fromDoc[domain.Pass](snap.Data())
		if err != nil {
			return err
		}
		entries, err := f.ledgerInTx(tx, centerID, pass.MemberID, passID)
		if err != nil {
			return err
		}
		// 지목 계약도 여기서 다시 읽는다(쓰기 전 일괄 — SDK 제약).
		contracts := make([]*domain.Contract, 0, len(contractIDs))
		contractRefs := make([]*firestore.DocumentRef, 0, len(contractIDs))
		for _, cid := range contractIDs {
			cref := f.center(centerID).Collection("contracts").Doc(cid)
			csnap, err := tx.Get(cref)
			if err != nil {
				return mapNotFound(err)
			}
			c, err := fromDoc[domain.Contract](csnap.Data())
			if err != nil {
				return err
			}
			contracts = append(contracts, c)
			contractRefs = append(contractRefs, cref)
		}
		entry, err := mutate(pass, entries)
		if err != nil {
			return err
		}
		// 판정을 전부 끝낸 뒤에야 쓴다 — sweep 중간 에러 시 아무것도 반영되지 않는다.
		contractWrites := make([]int, 0, len(contracts))
		for i, c := range contracts {
			save, err := sweep(c)
			if err != nil {
				return err
			}
			if save {
				contractWrites = append(contractWrites, i)
			}
		}
		if entry != nil {
			ledgerRef := f.center(centerID).Collection("ledger").NewDoc()
			entry.ID = ledgerRef.ID
			entry.PassID = passID
			if entry.At.IsZero() {
				entry.At = time.Now().UTC()
			}
			if err := tx.Set(ledgerRef, toDoc(entry)); err != nil {
				return err
			}
		}
		if err := tx.Set(passRef, toDoc(pass)); err != nil {
			return err
		}
		for _, i := range contractWrites {
			if err := tx.Set(contractRefs[i], toDoc(contracts[i])); err != nil {
				return err
			}
		}
		out = pass
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// ledgerInTx — 트랜잭션 **안에서** 한 패스의 원장을 전부 읽는다. ListLedger와 같은 쿼리 형태를
// 쓴다(두 경로가 다른 집합을 보면 "원장이 진실"이 두 개가 된다). 정렬도 동일(최신 먼저).
func (f *Firestore) ledgerInTx(tx *firestore.Transaction, centerID, memberID, passID string) ([]domain.Ledger, error) {
	q := f.center(centerID).Collection("ledger").Where("member_id", "==", memberID).Where("pass_id", "==", passID)
	iter := tx.Documents(q)
	defer iter.Stop()
	out := []domain.Ledger{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		e, err := fromDoc[domain.Ledger](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].At.After(out[j].At) })
	return out, nil
}

func (f *Firestore) ListPassesByMember(ctx context.Context, centerID, memberID string) ([]domain.Pass, error) {
	iter := f.center(centerID).Collection("passes").Where("member_id", "==", memberID).Documents(ctx)
	defer iter.Stop()
	return collectPasses(iter)
}

func (f *Firestore) ListPasses(ctx context.Context, centerID string) ([]domain.Pass, error) {
	iter := f.center(centerID).Collection("passes").Documents(ctx)
	defer iter.Stop()
	return collectPasses(iter)
}

func collectPasses(iter *firestore.DocumentIterator) ([]domain.Pass, error) {
	out := []domain.Pass{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		p, err := fromDoc[domain.Pass](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *p)
	}
	sortPasses(out) // 서버 기본 순서(무작위 문서 ID)를 valid_from으로 덮어쓴다 — Memory와 같은 규칙(order.go)
	return out, nil
}

// ---- 슬롯/예약 ----

func (f *Firestore) GetSlot(ctx context.Context, centerID, slotKey string) (*domain.Slot, error) {
	if err := checkDocID(slotKey); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("slots").Doc(slotKey).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[domain.Slot](snap.Data())
}

func (f *Firestore) ListSlots(ctx context.Context, centerID, date string) ([]domain.Slot, error) {
	datePart := strings.ReplaceAll(date, "-", "")
	// slot_key="YYYYMMDD-HH" 필드 자체를 범위 쿼리(단일 필드 범위라 복합 인덱스 불필요).
	lo := datePart + "-00"
	hi := datePart + "-23"
	iter := f.center(centerID).Collection("slots").
		Where("slot_key", ">=", lo).Where("slot_key", "<=", hi).Documents(ctx)
	defer iter.Stop()
	out := []domain.Slot{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		s, err := fromDoc[domain.Slot](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *s)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SlotKey < out[j].SlotKey })
	return out, nil
}

// BookAtomic — Firestore 트랜잭션으로 "슬롯 읽기 → CanBook 판정 → 예약 생성 + 슬롯 갱신"을
// 원자적으로 묶는다(P35, 설계03 §5). 트랜잭션 내 모든 읽기는 쓰기보다 먼저 수행한다(SDK 제약).
func (f *Firestore) BookAtomic(ctx context.Context, centerID, slotKey string, capacity int, booking *domain.Booking) error {
	slotRef := f.center(centerID).Collection("slots").Doc(slotKey)
	bookingColl := f.center(centerID).Collection("bookings")
	return f.c.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		// ---- 읽기 먼저(SDK 제약): 슬롯 → 패스 → 원장 → 이 패스의 기존 예약 ----
		snap, err := tx.Get(slotRef)
		var slot *domain.Slot
		if err != nil {
			if status.Code(err) != codes.NotFound {
				return err
			}
			slot = &domain.Slot{SlotKey: slotKey, Capacity: capacity}
		} else {
			slot, err = fromDoc[domain.Slot](snap.Data())
			if err != nil {
				return err
			}
		}
		if len(slot.Teams) == 0 {
			slot.Capacity = capacity // 비어 있는 슬롯은 현재 정책 용량으로 갱신(v1.5)
		}

		// 잔여 청구권 재판정(P13 H1). 패스 문서를 **읽고 또 쓰기** 때문에 같은 패스에 대한 동시
		// 예약 트랜잭션끼리 충돌이 감지돼 직렬화된다 — 쿼리 결과만 읽으면 상대가 방금 만든 예약
		// 문서(phantom)를 못 봐서 둘 다 커밋된다. remaining 스냅샷 갱신은 그 부수효과이자 M3 보정.
		var passRef *firestore.DocumentRef
		var pass *domain.Pass
		if booking.PassID != "" {
			passRef = f.center(centerID).Collection("passes").Doc(booking.PassID)
			pSnap, pErr := tx.Get(passRef)
			switch {
			case pErr != nil && status.Code(pErr) != codes.NotFound:
				return pErr
			case pErr != nil:
				passRef = nil // 패스 문서 없음(픽스처·레거시) — 검사 생략, 오늘까지의 동작 유지
			default:
				pass, err = fromDoc[domain.Pass](pSnap.Data())
				if err != nil {
					return err
				}
			}
		}
		if pass != nil {
			entries, err := f.ledgerInTx(tx, centerID, booking.MemberID, booking.PassID)
			if err != nil {
				return err
			}
			open, err := f.countOpenPassBookingsInTx(tx, centerID, booking.MemberID, booking.PassID)
			if err != nil {
				return err
			}
			remaining := domain.Sum(entries)
			if remaining-open <= 0 {
				return domain.ErrNoSessionsLeft
			}
			pass.Remaining = remaining
		}

		// ---- 쓰기 ----
		bookingRef := bookingColl.NewDoc()
		booking.ID = bookingRef.ID
		if booking.CreatedAt.IsZero() {
			booking.CreatedAt = time.Now().UTC()
		}
		if booking.Status == "" {
			booking.Status = domain.BookingConfirmed
		}
		slot.Teams = append(slot.Teams, domain.Team{
			BookingID: booking.ID, TrainerID: booking.TrainerID, MemberID: booking.MemberID, Kind: booking.Kind,
			Status: domain.BookingConfirmed, // v1.1 정합 패치: teams[].status 초기값
		})

		if err := tx.Set(bookingRef, toDoc(booking)); err != nil {
			return err
		}
		if err := tx.Set(slotRef, toDoc(slot)); err != nil {
			return err
		}
		if pass != nil {
			if err := tx.Set(passRef, toDoc(pass)); err != nil {
				return err
			}
		}
		return nil
	})
}

// countOpenPassBookingsInTx — 트랜잭션 안에서 이 패스로 잡혀 있는 confirmed 예약 수.
// 서비스의 countOpenPassBookings와 같은 규칙(회원으로 쿼리하고 pass_id·status는 Go에서 필터 —
// 새 복합 인덱스를 요구하지 않는다).
func (f *Firestore) countOpenPassBookingsInTx(tx *firestore.Transaction, centerID, memberID, passID string) (int, error) {
	iter := tx.Documents(f.center(centerID).Collection("bookings").Where("member_id", "==", memberID))
	defer iter.Stop()
	n := 0
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return 0, err
		}
		b, err := fromDoc[domain.Booking](snap.Data())
		if err != nil {
			return 0, err
		}
		if b.PassID == passID && b.Status == domain.BookingConfirmed {
			n++
		}
	}
	return n, nil
}

func (f *Firestore) GetBooking(ctx context.Context, centerID, id string) (*domain.Booking, error) {
	if err := checkDocID(id); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("bookings").Doc(id).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[domain.Booking](snap.Data())
}

func (f *Firestore) ListBookingsByMember(ctx context.Context, centerID, memberID string) ([]domain.Booking, error) {
	iter := f.center(centerID).Collection("bookings").Where("member_id", "==", memberID).Documents(ctx)
	defer iter.Stop()
	return collectBookings(iter)
}

func (f *Firestore) ListBookings(ctx context.Context, centerID string) ([]domain.Booking, error) {
	iter := f.center(centerID).Collection("bookings").Documents(ctx)
	defer iter.Stop()
	return collectBookings(iter)
}

func collectBookings(iter *firestore.DocumentIterator) ([]domain.Booking, error) {
	out := []domain.Booking{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		b, err := fromDoc[domain.Booking](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *b)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SlotKey < out[j].SlotKey })
	return out, nil
}

// CancelAtomic — 예약 상태를 cancelled로 바꾸고 슬롯 teams에서 원자적으로 제거한다.
// entry가 nil이 아니면 컷오프 내 취소의 페널티 원장도 같은 트랜잭션에 넣는다(P13 M4).
func (f *Firestore) CancelAtomic(ctx context.Context, centerID, bookingID string, entry *domain.Ledger) error {
	if err := checkDocID(bookingID); err != nil {
		return err
	}
	bookingRef := f.center(centerID).Collection("bookings").Doc(bookingID)
	return f.c.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		bSnap, err := tx.Get(bookingRef)
		if err != nil {
			return mapNotFound(err)
		}
		booking, err := fromDoc[domain.Booking](bSnap.Data())
		if err != nil {
			return err
		}
		if booking.Status != domain.BookingConfirmed {
			return ErrStateConflict // 완료/노쇼/취소된 예약의 재취소 금지(트랜잭션 내부 재검증)
		}

		slotRef := f.center(centerID).Collection("slots").Doc(booking.SlotKey)
		sSnap, slotErr := tx.Get(slotRef)
		var slot *domain.Slot
		if slotErr != nil && status.Code(slotErr) != codes.NotFound {
			return slotErr
		}
		if slotErr == nil {
			slot, err = fromDoc[domain.Slot](sSnap.Data())
			if err != nil {
				return err
			}
		}

		booking.Status = domain.BookingCancelled
		if err := tx.Set(bookingRef, toDoc(booking)); err != nil {
			return err
		}
		if slot != nil {
			kept := []domain.Team{}
			for _, t := range slot.Teams {
				if t.BookingID != bookingID {
					kept = append(kept, t)
				}
			}
			slot.Teams = kept
			if err := tx.Set(slotRef, toDoc(slot)); err != nil {
				return err
			}
		}
		if entry != nil {
			ledgerRef := f.center(centerID).Collection("ledger").NewDoc()
			entry.ID = ledgerRef.ID
			if entry.At.IsZero() {
				entry.At = time.Now().UTC()
			}
			if err := tx.Set(ledgerRef, toDoc(entry)); err != nil {
				return err
			}
		}
		return nil
	})
}

// SetBookingStatusWithLedger — 예약 상태 변경 + 원장 기록을 한 트랜잭션으로 묶는다(complete/noshow, P4·P7).
// v1.1 정합 패치: slot.teams[].status도 함께 동기화한다(Memory 구현과 동일 동작).
func (f *Firestore) SetBookingStatusWithLedger(ctx context.Context, centerID, bookingID, newStatus string, entry *domain.Ledger) error {
	bookingRef := f.center(centerID).Collection("bookings").Doc(bookingID)
	return f.c.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		// ---- 읽기 먼저(트랜잭션 SDK 제약: 모든 읽기가 쓰기보다 선행해야 함, CancelAtomic과 동일 패턴) ----
		snap, err := tx.Get(bookingRef)
		if err != nil {
			return mapNotFound(err)
		}
		booking, err := fromDoc[domain.Booking](snap.Data())
		if err != nil {
			return err
		}
		if booking.Status != domain.BookingConfirmed {
			return ErrStateConflict // confirmed에서만 전이 — 동시 이중 complete/noshow 방어(트랜잭션 내부)
		}

		slotRef := f.center(centerID).Collection("slots").Doc(booking.SlotKey)
		sSnap, slotErr := tx.Get(slotRef)
		var slot *domain.Slot
		if slotErr != nil && status.Code(slotErr) != codes.NotFound {
			return slotErr
		}
		if slotErr == nil {
			slot, err = fromDoc[domain.Slot](sSnap.Data())
			if err != nil {
				return err
			}
		}

		// ---- 쓰기 ----
		booking.Status = newStatus
		if err := tx.Set(bookingRef, toDoc(booking)); err != nil {
			return err
		}
		if slot != nil {
			for i := range slot.Teams {
				if slot.Teams[i].BookingID == bookingID {
					slot.Teams[i].Status = newStatus
					break
				}
			}
			if err := tx.Set(slotRef, toDoc(slot)); err != nil {
				return err
			}
		}
		if entry != nil {
			ledgerRef := f.center(centerID).Collection("ledger").NewDoc()
			entry.ID = ledgerRef.ID
			if entry.At.IsZero() {
				entry.At = time.Now().UTC()
			}
			if err := tx.Set(ledgerRef, toDoc(entry)); err != nil {
				return err
			}
		}
		return nil
	})
}

// ReassignBookingTrainer — 담당 이관(v2.0): 예약과 슬롯 teams 사본의 trainer_id를 한 트랜잭션에서
// 바꾼다. 읽기가 전부 쓰기보다 앞선다(SDK 제약 — CancelAtomic과 동일 패턴).
func (f *Firestore) ReassignBookingTrainer(ctx context.Context, centerID, bookingID, toTrainerID string) error {
	bookingRef := f.center(centerID).Collection("bookings").Doc(bookingID)
	return f.c.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		bSnap, err := tx.Get(bookingRef)
		if err != nil {
			return mapNotFound(err)
		}
		booking, err := fromDoc[domain.Booking](bSnap.Data())
		if err != nil {
			return err
		}
		if booking.Status != domain.BookingConfirmed {
			return ErrStateConflict
		}

		slotRef := f.center(centerID).Collection("slots").Doc(booking.SlotKey)
		sSnap, slotErr := tx.Get(slotRef)
		var slot *domain.Slot
		if slotErr != nil && status.Code(slotErr) != codes.NotFound {
			return slotErr
		}
		if slotErr == nil {
			slot, err = fromDoc[domain.Slot](sSnap.Data())
			if err != nil {
				return err
			}
		}
		if slot != nil && toTrainerID != "" {
			// 인수자의 동시 1팀 규칙(R2)은 이관도 우회하지 못한다. 자기 자신은 제외(멱등).
			for _, t := range slot.Teams {
				if t.BookingID != bookingID && t.TrainerID == toTrainerID {
					return domain.ErrTrainerBusy
				}
			}
		}

		booking.TrainerID = toTrainerID
		if err := tx.Set(bookingRef, toDoc(booking)); err != nil {
			return err
		}
		if slot != nil {
			for i := range slot.Teams {
				if slot.Teams[i].BookingID == bookingID {
					slot.Teams[i].TrainerID = toTrainerID
					break
				}
			}
			if err := tx.Set(slotRef, toDoc(slot)); err != nil {
				return err
			}
		}
		return nil
	})
}

// ---- 고정 스케줄 ----

func (f *Firestore) CreateRecurring(ctx context.Context, centerID string, r *domain.Recurring) (string, error) {
	ref := f.center(centerID).Collection("recurring").NewDoc()
	r.ID = ref.ID
	if _, err := ref.Set(ctx, toDoc(r)); err != nil {
		return "", err
	}
	return r.ID, nil
}

// UpdateRecurring — 담당 이관(v2.0). 문서가 없으면 새로 만들지 않고 ErrNotFound
// (Set은 upsert라 오타 ID로 유령 규칙이 생기는 것을 막기 위해 존재 확인을 먼저 한다).
func (f *Firestore) UpdateRecurring(ctx context.Context, centerID string, r *domain.Recurring) error {
	if err := checkDocID(r.ID); err != nil {
		return err
	}
	ref := f.center(centerID).Collection("recurring").Doc(r.ID)
	if _, err := ref.Get(ctx); err != nil {
		return mapNotFound(err)
	}
	_, err := ref.Set(ctx, toDoc(r))
	return err
}

func (f *Firestore) GetRecurring(ctx context.Context, centerID, id string) (*domain.Recurring, error) {
	if err := checkDocID(id); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("recurring").Doc(id).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[domain.Recurring](snap.Data())
}

// DeleteRecurring — 없는 ID면 ErrNotFound. Firestore의 Delete는 없는 문서에도 성공을 돌려주므로
// (Memory는 ErrNotFound) 존재 확인을 선행한다 — 어드민이 오타 ID로 "해제됨" 204를 받고 실제
// 규칙은 그대로 남는 차이를 막는다.
func (f *Firestore) DeleteRecurring(ctx context.Context, centerID, id string) error {
	if err := checkDocID(id); err != nil {
		return err
	}
	ref := f.center(centerID).Collection("recurring").Doc(id)
	if _, err := ref.Get(ctx); err != nil {
		return mapNotFound(err)
	}
	_, err := ref.Delete(ctx)
	return err
}

func (f *Firestore) ListRecurrings(ctx context.Context, centerID string) ([]domain.Recurring, error) {
	iter := f.center(centerID).Collection("recurring").Documents(ctx)
	defer iter.Stop()
	out := []domain.Recurring{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		r, err := fromDoc[domain.Recurring](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *r)
	}
	sortByDocID(out, recurringDocID) // order.go — Memory와 같은 규칙
	return out, nil
}

// ---- Home Work ----

func (f *Firestore) CreateHomework(ctx context.Context, centerID string, hw *domain.Homework) (string, error) {
	ref := f.center(centerID).Collection("homeworks").NewDoc()
	hw.ID = ref.ID
	if _, err := ref.Set(ctx, toDoc(hw)); err != nil {
		return "", err
	}
	return hw.ID, nil
}

func (f *Firestore) GetHomework(ctx context.Context, centerID, id string) (*domain.Homework, error) {
	if err := checkDocID(id); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("homeworks").Doc(id).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[domain.Homework](snap.Data())
}

func (f *Firestore) ListHomeworks(ctx context.Context, centerID string) ([]domain.Homework, error) {
	iter := f.center(centerID).Collection("homeworks").Documents(ctx)
	defer iter.Stop()
	out := []domain.Homework{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		hw, err := fromDoc[domain.Homework](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *hw)
	}
	sortByDocID(out, homeworkDocID) // order.go — Memory와 같은 규칙
	return out, nil
}

func (f *Firestore) SaveHwCheck(ctx context.Context, centerID string, c *domain.HwCheck) error {
	id := hwCheckDocID(c.MemberID, c.HwID, c.Date)
	_, err := f.center(centerID).Collection("hwChecks").Doc(id).Set(ctx, toDoc(c))
	return err
}

func (f *Firestore) ListHwChecksByMember(ctx context.Context, centerID, memberID string) ([]domain.HwCheck, error) {
	iter := f.center(centerID).Collection("hwChecks").Where("member_id", "==", memberID).Documents(ctx)
	defer iter.Stop()
	out := []domain.HwCheck{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		c, err := fromDoc[domain.HwCheck](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *c)
	}
	sortByDocID(out, hwCheckDocIDOf) // order.go — Memory와 같은 규칙(합성 문서 ID 기준)
	return out, nil
}

// ListHwChecks — 센터 전체(회원 무관, GET /v1/hw-checks?hw_id=&member= 지원용, v1.1 정합 패치).
func (f *Firestore) ListHwChecks(ctx context.Context, centerID string) ([]domain.HwCheck, error) {
	iter := f.center(centerID).Collection("hwChecks").Documents(ctx)
	defer iter.Stop()
	out := []domain.HwCheck{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		c, err := fromDoc[domain.HwCheck](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *c)
	}
	sortByDocID(out, hwCheckDocIDOf) // order.go — Memory와 같은 규칙(합성 문서 ID 기준)
	return out, nil
}

// ---- 직원 ----

func (f *Firestore) ListStaff(ctx context.Context, centerID string) ([]domain.Staff, error) {
	iter := f.center(centerID).Collection("staff").Documents(ctx)
	defer iter.Stop()
	out := []domain.Staff{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		s, err := fromDoc[domain.Staff](snap.Data())
		if err != nil {
			return nil, err
		}
		s.Normalize() // v2.0: status 필드가 없는 기존 문서를 active로 승격(GetPolicy와 같은 자리)
		out = append(out, *s)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

func (f *Firestore) GetStaff(ctx context.Context, centerID, uid string) (*domain.Staff, error) {
	if err := checkDocID(uid); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("staff").Doc(uid).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	s, err := fromDoc[domain.Staff](snap.Data())
	if err != nil {
		return nil, err
	}
	// v1.2 이전 정책 문서 승격(GetPolicy)과 동형: 마이그레이션 없이 구문서를 계약에 맞춘다.
	s.Normalize()
	return s, nil
}

func (f *Firestore) SaveStaff(ctx context.Context, centerID string, s *domain.Staff) error {
	_, err := f.center(centerID).Collection("staff").Doc(s.UID).Set(ctx, toDoc(s))
	return err
}

// ---- 결제 ----

func (f *Firestore) CreatePayment(ctx context.Context, centerID string, p *domain.Payment) (string, error) {
	ref := f.center(centerID).Collection("payments").NewDoc()
	p.ID = ref.ID
	if _, err := ref.Set(ctx, toDoc(p)); err != nil {
		return "", err
	}
	return p.ID, nil
}

func (f *Firestore) GetPayment(ctx context.Context, centerID, id string) (*domain.Payment, error) {
	if err := checkDocID(id); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("payments").Doc(id).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[domain.Payment](snap.Data())
}

// UpdatePayment — 없는 ID면 ErrNotFound(UpdateRecurring과 같은 존재 확인 선행).
func (f *Firestore) UpdatePayment(ctx context.Context, centerID string, p *domain.Payment) error {
	if err := checkDocID(p.ID); err != nil {
		return err
	}
	ref := f.center(centerID).Collection("payments").Doc(p.ID)
	if _, err := ref.Get(ctx); err != nil {
		return mapNotFound(err)
	}
	_, err := ref.Set(ctx, toDoc(p))
	return err
}

func (f *Firestore) ListPayments(ctx context.Context, centerID string) ([]domain.Payment, error) {
	iter := f.center(centerID).Collection("payments").Documents(ctx)
	defer iter.Stop()
	out := []domain.Payment{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		p, err := fromDoc[domain.Payment](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *p)
	}
	sortByDocID(out, paymentDocID) // order.go — Memory와 같은 규칙
	return out, nil
}

// ---- 전자계약(Contract, v1.1 정합 패치) ----

func (f *Firestore) CreateContract(ctx context.Context, centerID string, c *domain.Contract) (string, error) {
	ref := f.center(centerID).Collection("contracts").NewDoc()
	c.ID = ref.ID
	if _, err := ref.Set(ctx, toDoc(c)); err != nil {
		return "", err
	}
	return c.ID, nil
}

// CreateContractGuarded — 같은 회원의 기존 계약을 **트랜잭션 안에서** 질의해 guard에 넘긴 뒤
// 생성한다(P37 M2, 계약 v2.15). 트랜잭션 내 쿼리는 결과 집합에 대한 직렬화를 얻는다 — 동시
// 생성 2건이 서로를 보지 못한 채 나란히 통과할 수 없다(ledgerInTx와 같은 tx.Documents 패턴).
func (f *Firestore) CreateContractGuarded(ctx context.Context, centerID string, c *domain.Contract, guard func(existing []domain.Contract) error) (string, error) {
	ref := f.center(centerID).Collection("contracts").NewDoc()
	c.ID = ref.ID
	err := f.c.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		q := f.center(centerID).Collection("contracts").Where("member_id", "==", c.MemberID)
		iter := tx.Documents(q)
		defer iter.Stop()
		existing := []domain.Contract{}
		for {
			snap, err := iter.Next()
			if errors.Is(err, iterator.Done) {
				break
			}
			if err != nil {
				return err
			}
			ec, err := fromDoc[domain.Contract](snap.Data())
			if err != nil {
				return err
			}
			existing = append(existing, *ec)
		}
		if err := guard(existing); err != nil {
			return err
		}
		return tx.Set(ref, toDoc(c))
	})
	if err != nil {
		return "", err
	}
	return c.ID, nil
}

func (f *Firestore) GetContract(ctx context.Context, centerID, id string) (*domain.Contract, error) {
	if err := checkDocID(id); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("contracts").Doc(id).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[domain.Contract](snap.Data())
}

// UpdateContract — 없는 ID면 ErrNotFound(UpdateRecurring과 같은 존재 확인 선행).
// 상태 전이 경로에서는 쓰지 않는다(TransitionContract를 쓴다 — 인터페이스 주석, P37).
func (f *Firestore) UpdateContract(ctx context.Context, centerID string, c *domain.Contract) error {
	if err := checkDocID(c.ID); err != nil {
		return err
	}
	ref := f.center(centerID).Collection("contracts").Doc(c.ID)
	if _, err := ref.Get(ctx); err != nil {
		return mapNotFound(err)
	}
	_, err := ref.Set(ctx, toDoc(c))
	return err
}

// TransitionContract — 계약 상태 전이를 한 트랜잭션으로(P37, 계약 v2.15). 계약과 그 패스를
// **같은 트랜잭션에서** 읽으므로 환불 마감(패스 쓰기)과 서명/재발송이 어긋나게 커밋될 수 없다
// (OCC — 읽은 문서가 커밋 전에 바뀌면 재시도되고, mutate가 새 상태 위에서 다시 판정한다).
func (f *Firestore) TransitionContract(ctx context.Context, centerID, contractID string, mutate ContractMutator) (*domain.Contract, error) {
	if err := checkDocID(contractID); err != nil {
		return nil, err
	}
	ref := f.center(centerID).Collection("contracts").Doc(contractID)
	var out *domain.Contract
	err := f.c.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		out = nil // 재시도마다 초기화(updatePassInTx와 동일)
		snap, err := tx.Get(ref)
		if err != nil {
			return mapNotFound(err)
		}
		c, err := fromDoc[domain.Contract](snap.Data())
		if err != nil {
			return err
		}
		// 패스도 같은 트랜잭션에서 읽는다 — 환불 여부 판정이 트랜잭션 밖 스냅샷이면 창이
		// 남는다. 계약만 있고 패스 문서가 없는 데이터(레거시·픽스처)는 nil로 넘긴다.
		var pass *domain.Pass
		if checkDocID(c.PassID) == nil {
			psnap, perr := tx.Get(f.center(centerID).Collection("passes").Doc(c.PassID))
			switch {
			case perr == nil:
				if pass, perr = fromDoc[domain.Pass](psnap.Data()); perr != nil {
					return perr
				}
			case errors.Is(mapNotFound(perr), ErrNotFound):
				// pass = nil 유지 — 판정은 계약만으로 진행한다.
			default:
				return perr
			}
		}
		if err := mutate(c, pass); err != nil {
			return err
		}
		if err := tx.Set(ref, toDoc(c)); err != nil {
			return err
		}
		out = c
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// ListContracts — member/status 모두 옵션(빈 값=필터 없음). Firestore Where는 조건별로 체이닝해야
// 해서 4가지 조합을 switch로 명시한다(ListMembers처럼 단일 옵션 필터가 아니라 두 옵션 조합이라
// firestore.Query 체이닝 스텝이 달라짐). 매개변수명은 statusFilter — 이 파일이 import한
// google.golang.org/grpc/status 패키지명과의 섀도잉을 피한다(SetBookingStatusWithLedger의 newStatus와
// 동일한 이유).
func (f *Firestore) ListContracts(ctx context.Context, centerID, memberID, statusFilter string) ([]domain.Contract, error) {
	coll := f.center(centerID).Collection("contracts")
	var iter *firestore.DocumentIterator
	switch {
	case memberID != "" && statusFilter != "":
		iter = coll.Where("member_id", "==", memberID).Where("status", "==", statusFilter).Documents(ctx)
	case memberID != "":
		iter = coll.Where("member_id", "==", memberID).Documents(ctx)
	case statusFilter != "":
		iter = coll.Where("status", "==", statusFilter).Documents(ctx)
	default:
		iter = coll.Documents(ctx)
	}
	defer iter.Stop()
	out := []domain.Contract{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		c, err := fromDoc[domain.Contract](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, nil
}

// ---- 체형사진 ----

func (f *Firestore) CreateBodyPhoto(ctx context.Context, centerID string, bp *domain.BodyPhoto) (string, error) {
	ref := f.center(centerID).Collection("bodyPhotos").NewDoc()
	bp.ID = ref.ID
	if _, err := ref.Set(ctx, toDoc(bp)); err != nil {
		return "", err
	}
	return bp.ID, nil
}

func (f *Firestore) GetBodyPhoto(ctx context.Context, centerID, id string) (*domain.BodyPhoto, error) {
	snap, err := f.center(centerID).Collection("bodyPhotos").Doc(id).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return fromDoc[domain.BodyPhoto](snap.Data())
}

func (f *Firestore) SaveBodyPhoto(ctx context.Context, centerID string, bp *domain.BodyPhoto) error {
	_, err := f.center(centerID).Collection("bodyPhotos").Doc(bp.ID).Set(ctx, toDoc(bp))
	return err
}

func (f *Firestore) DeleteBodyPhoto(ctx context.Context, centerID, id string) error {
	_, err := f.center(centerID).Collection("bodyPhotos").Doc(id).Delete(ctx)
	return err
}

// ListBodyPhotosPendingPurge — 유예가 지난 삭제 표시분.
//
// `deleted_at`에 부등호 쿼리를 걸지 않고 **전건을 훑어 걸러낸다**: 그 필드는 대부분
// 문서에 없어서(살아 있는 사진) 부등호 인덱스를 만들면 색인 비용만 늘고, 센터당
// 사진 수는 사람이 찍는 양이라 규모가 작다. 규모가 커지면 그때 색인을 만든다.
func (f *Firestore) ListBodyPhotosPendingPurge(ctx context.Context, centerID string, before time.Time, limit int) ([]domain.BodyPhoto, error) {
	iter := f.center(centerID).Collection("bodyPhotos").Documents(ctx)
	defer iter.Stop()
	out := []domain.BodyPhoto{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		bp, err := fromDoc[domain.BodyPhoto](snap.Data())
		if err != nil {
			return nil, err
		}
		if bp.DeletedAt != nil && bp.DeletedAt.Before(before) {
			out = append(out, *bp)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}

func (f *Firestore) ListBodyPhotos(ctx context.Context, centerID, memberID string) ([]domain.BodyPhoto, error) {
	iter := f.center(centerID).Collection("bodyPhotos").Where("member_id", "==", memberID).Documents(ctx)
	defer iter.Stop()
	out := []domain.BodyPhoto{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		bp, err := fromDoc[domain.BodyPhoto](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *bp)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Date > out[j].Date })
	return out, nil
}

// ---- 인바디 ----

// ---- 수업 기록(WorkoutLog, v1.4) ----

func (f *Firestore) CreateWorkoutLog(ctx context.Context, centerID string, wl *domain.WorkoutLog) (string, error) {
	ref := f.center(centerID).Collection("workout_logs").NewDoc()
	wl.ID = ref.ID
	if wl.Exercises == nil {
		wl.Exercises = []domain.Exercise{} // 직렬화 계약: 항상 배열
	}
	if _, err := ref.Set(ctx, toDoc(wl)); err != nil {
		return "", err
	}
	return wl.ID, nil
}

func (f *Firestore) ListWorkoutLogs(ctx context.Context, centerID, memberID string) ([]domain.WorkoutLog, error) {
	coll := f.center(centerID).Collection("workout_logs")
	var iter *firestore.DocumentIterator
	if memberID != "" {
		iter = coll.Where("member_id", "==", memberID).Documents(ctx)
	} else {
		iter = coll.Documents(ctx)
	}
	defer iter.Stop()
	out := []domain.WorkoutLog{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		wl, err := fromDoc[domain.WorkoutLog](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *wl)
	}
	// 정렬은 서버 인덱스 대신 여기서(복합 인덱스 요구 회피 — Memory 구현과 동일하게 최신 먼저).
	sort.Slice(out, func(i, j int) bool { return out[i].Date > out[j].Date })
	return out, nil
}

func (f *Firestore) CreateInbody(ctx context.Context, centerID string, r *domain.Inbody) (string, error) {
	ref := f.center(centerID).Collection("inbody").NewDoc()
	r.ID = ref.ID
	if _, err := ref.Set(ctx, toDoc(r)); err != nil {
		return "", err
	}
	return r.ID, nil
}

func (f *Firestore) ListInbody(ctx context.Context, centerID, memberID string) ([]domain.Inbody, error) {
	iter := f.center(centerID).Collection("inbody").Where("member_id", "==", memberID).Documents(ctx)
	defer iter.Stop()
	out := []domain.Inbody{}
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		r, err := fromDoc[domain.Inbody](snap.Data())
		if err != nil {
			return nil, err
		}
		out = append(out, *r)
	}
	sortInbody(out) // 최신 먼저 + 동률 시 ID(order.go — 두 스토어 공통 규칙)
	return out, nil
}

func (f *Firestore) GetInbody(ctx context.Context, centerID, id string) (*domain.Inbody, error) {
	if err := checkDocID(id); err != nil {
		return nil, err
	}
	snap, err := f.center(centerID).Collection("inbody").Doc(id).Get(ctx)
	if err != nil {
		return nil, mapNotFound(err)
	}
	return fromDoc[domain.Inbody](snap.Data())
}

// DeleteInbody — 없는 ID면 ErrNotFound(DeleteRecurring과 같은 존재 확인 선행 — Firestore의
// Delete는 없는 문서에도 성공을 돌려주므로 확인하지 않으면 오타 ID가 "지웠다"로 보고된다).
func (f *Firestore) DeleteInbody(ctx context.Context, centerID, id string) error {
	if err := checkDocID(id); err != nil {
		return err
	}
	ref := f.center(centerID).Collection("inbody").Doc(id)
	if _, err := ref.Get(ctx); err != nil {
		return mapNotFound(err)
	}
	_, err := ref.Delete(ctx)
	return err
}

// ---- 체크인 ----

func (f *Firestore) SaveCheckinRecord(ctx context.Context, centerID string, c *CheckinRecord) error {
	// 예약당 1문서(booking_id 기반 doc id) — 반복 체크인(연타·재시도)을 멱등 upsert로 흡수한다.
	ref := f.center(centerID).Collection("checkins").Doc("booking-" + c.BookingID)
	c.ID = ref.ID
	c.CenterID = centerID
	if c.At.IsZero() {
		c.At = time.Now().UTC()
	}
	_, err := ref.Set(ctx, toDoc(c))
	return err
}

// ---- 센터 신원(멀티센터 Phase A) ----

// GetCenter — centers/{id} 문서의 `center` 맵에서 읽는다. 문서·필드가 없으면 빈 값
// (GetBusiness와 같은 규약 — 읽기가 문서를 만들지 않는다).
func (f *Firestore) GetCenter(ctx context.Context, centerID string) (*domain.Center, error) {
	snap, err := f.center(centerID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return &domain.Center{ID: centerID}, nil
		}
		return nil, err
	}
	raw, ok := snap.Data()["center"].(map[string]any)
	if !ok {
		return &domain.Center{ID: centerID}, nil
	}
	c, err := fromDoc[domain.Center](raw)
	if err != nil {
		return nil, err
	}
	c.Normalize()
	// 문서 키가 진실 — 맵 안의 id가 손편집으로 어긋나도 키를 따른다. Normalize **뒤**에
	// 덮는다: 앞에 두면 ToLower가 키를 변조해 키를 그대로 돌려주는 Memory와 케이싱이
	// 드리프트한다(프로덕션 키는 centerIDPattern이 소문자로 강제하지만 계약은 키 원문이다).
	c.ID = centerID
	return c, nil
}

// SaveCenter — centers/{id} 문서의 `center` 필드만 머지로 쓴다(Policy·business 불침범 —
// SaveBusiness와 같은 규약).
func (f *Firestore) SaveCenter(ctx context.Context, c *domain.Center) error {
	_, err := f.center(c.ID).Set(ctx, map[string]any{"center": toDoc(c)}, firestore.MergeAll)
	return err
}

// ListCenters — `center` 신원이 등록된 문서만. GetPolicy 지연 시딩·헬스체크가 만든
// 정책-only 유령 문서는 name이 없어 자연히 걸러진다. 정렬은 ID 오름차순(결정적 순서).
func (f *Firestore) ListCenters(ctx context.Context) ([]domain.Center, error) {
	snaps, err := f.c.Collection("centers").Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := []domain.Center{}
	for _, snap := range snaps {
		raw, ok := snap.Data()["center"].(map[string]any)
		if !ok {
			continue
		}
		c, err := fromDoc[domain.Center](raw)
		if err != nil {
			return nil, err
		}
		if c.Name == "" {
			continue
		}
		c.Normalize()
		c.ID = snap.Ref.ID // GetCenter와 같은 순서 — 키 원문이 계약, Normalize가 케이싱을 못 바꾼다
		out = append(out, *c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, nil
}

// ---- 센터 정책 ----

// GetPolicy — centers/{centerID} 문서 자체에서 정책을 읽는다. 문서가 없으면(최초 접근) 기본값을
// 지연 시딩한다(센터 생성 전용 API가 없는 v1의 부트스트랩, README 갭 참고).
func (f *Firestore) GetPolicy(ctx context.Context, centerID string) (*domain.Policy, error) {
	snap, err := f.center(centerID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			def := domain.DefaultPolicy()
			if _, err := f.center(centerID).Set(ctx, toDoc(&def)); err != nil {
				return nil, err
			}
			return &def, nil
		}
		return nil, err
	}
	p, err := fromDoc[domain.Policy](snap.Data())
	if err != nil {
		return nil, err
	}
	// 구문서 승격(마이그레이션 없이): v1.2 이전 문서엔 홀딩 상한 필드가 없어 0(=무제한)으로
	// 읽히고, P14 이전 문서엔 상한(10%)을 넘는 위약금율이 저장돼 있을 수 있다. 둘 다 읽는
	// 자리에서 접는다 — 초과 위약금율은 계약 스냅샷·회원앱으로 새어나가고 머지 PUT을 잠근다.
	p.Normalize()
	return p, nil
}

// SavePolicy — **머지 쓰기**다(firestore.MergeAll). 종전엔 통 Set이라 센터 문서를 통째로
// 덮었는데, v2.13부터 같은 문서에 `business`(법정 고지 기재사항)가 함께 산다 — 통 Set으로
// 두면 대표가 예약 용량 하나만 바꿔도 사업자 정보가 조용히 지워지고, 그 결과가 다음 배포도
// 아니고 **법정 문서 5장이 동시에 초안으로 되돌아가는** 것으로 나타난다.
// toDoc(p)에 정책 전 필드가 들어 있어 머지여도 정책 자체는 전부 갱신된다.
func (f *Firestore) SavePolicy(ctx context.Context, centerID string, p *domain.Policy) error {
	_, err := f.center(centerID).Set(ctx, toDoc(p), firestore.MergeAll)
	return err
}

// ---- 사업자 정보(법정 고지 기재사항, v2.13) ----

// GetBusiness — 센터 문서의 `business` 맵에서 읽는다. 문서·필드가 없으면 **빈 값**이다
// (ErrNotFound 아님 — 미등록은 정상 상태다).
//
// **GetPolicy와 달리 지연 시딩을 하지 않는다.** 이 값을 읽는 경로에 무인증 공개 엔드포인트
// (GET /v1/public/business)가 있어서, 읽기가 문서를 만들면 익명 요청이 쓰기를 유발하는
// 구조가 된다 — 존재하지 않는 센터 ID로 문서를 양산할 수 있는 자리다.
func (f *Firestore) GetBusiness(ctx context.Context, centerID string) (*domain.Business, error) {
	snap, err := f.center(centerID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return &domain.Business{}, nil
		}
		return nil, err
	}
	raw, ok := snap.Data()["business"].(map[string]any)
	if !ok {
		return &domain.Business{}, nil
	}
	b, err := fromDoc[domain.Business](raw)
	if err != nil {
		return nil, err
	}
	b.Normalize() // 읽기 규약: 공백·등록번호 표기를 저장 시점과 무관하게 하나로 맞춘다
	return b, nil
}

// SaveBusiness — 센터 문서의 `business` 필드만 머지로 쓴다(정책을 건드리지 않는다).
// toDoc(b)는 빈 칸도 키로 포함하므로 "칸을 비워 지우기"가 머지에서도 그대로 반영된다.
func (f *Firestore) SaveBusiness(ctx context.Context, centerID string, b *domain.Business) error {
	_, err := f.center(centerID).Set(ctx, map[string]any{"business": toDoc(b)}, firestore.MergeAll)
	return err
}

// ---- 시설 신고 상태(체육시설업, P42) ----

// GetFacility — 센터 문서의 `facility` 맵에서 읽는다. 문서·필드가 없으면 **기본값**
// (report_status="unknown", ErrNotFound 아님 — GetBusiness와 같은 "읽기가 문서를 만들지
// 않는다" 규약). Normalize를 읽기에 태워 구 문서(절 부재)·손편집 값도 늘 3값 중 하나로
// 나간다 — 스탬프 게이트·응답이 이 값을 그대로 분기 조건으로 쓴다.
func (f *Firestore) GetFacility(ctx context.Context, centerID string) (*domain.Facility, error) {
	snap, err := f.center(centerID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return &domain.Facility{ReportStatus: domain.FacilityStatusUnknown}, nil
		}
		return nil, err
	}
	raw, ok := snap.Data()["facility"].(map[string]any)
	if !ok {
		return &domain.Facility{ReportStatus: domain.FacilityStatusUnknown}, nil
	}
	fac, err := fromDoc[domain.Facility](raw)
	if err != nil {
		return nil, err
	}
	fac.Normalize()
	return fac, nil
}

// SaveFacility — 센터 문서의 `facility` 필드만 머지로 쓴다(Policy·Business·center 불침범 —
// SaveBusiness와 같은 규약, P27 SavePolicy 교훈). toDoc(fac)는 빈 칸도 키로 포함하므로
// 상태를 되돌리거나 번호를 비우는 재제출이 머지에서도 그대로 반영된다(절 단위 통 교체).
func (f *Firestore) SaveFacility(ctx context.Context, centerID string, fac *domain.Facility) error {
	_, err := f.center(centerID).Set(ctx, map[string]any{"facility": toDoc(fac)}, firestore.MergeAll)
	return err
}

// ---- 데스크 체크인 QR 토큰(센터 비밀, P49) ----

// GetCheckinQR — 센터 문서의 `checkin_qr` 맵에서 읽는다. 문서·필드가 없으면 **빈 값**
// (ErrNotFound 아님 — GetFacility와 같은 "읽기가 문서를 만들지 않는다" 규약. 미발급은 정상
// 상태이고, 체크인 경로가 그 상태를 보고 안내 문구를 고른다).
//
// **지연 시딩을 하지 않는 것이 여기서는 특히 중요하다**: 읽기가 토큰을 만들면 회원의 체크인
// 시도가 곧 발급이 되어, 대표가 인쇄하지도 않은 QR이 유효해진다. 발급은 owner의 명시적
// 행위(POST rotate)뿐이다.
func (f *Firestore) GetCheckinQR(ctx context.Context, centerID string) (*domain.CheckinQR, error) {
	snap, err := f.center(centerID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return &domain.CheckinQR{}, nil
		}
		return nil, err
	}
	raw, ok := snap.Data()["checkin_qr"].(map[string]any)
	if !ok {
		return &domain.CheckinQR{}, nil
	}
	q, err := fromDoc[domain.CheckinQR](raw)
	if err != nil {
		return nil, err
	}
	q.Normalize() // 손편집 공백이 바이트 비교를 깨지 않도록 — 응답과 대조가 같은 모양을 본다
	return q, nil
}

// SaveCheckinQR — 센터 문서의 `checkin_qr` 필드만 머지로 쓴다(Policy·Business·Facility·center
// 불침범 — SaveFacility와 같은 규약, P27 SavePolicy 교훈). toDoc(q)가 두 키를 전부 포함하므로
// 절 안에서는 통 교체다 — 재발급이 이전 토큰을 유령으로 남기지 않는다(남으면 옛 인쇄물이
// 계속 통과해 "재발급하면 무효"가 거짓이 된다).
func (f *Firestore) SaveCheckinQR(ctx context.Context, centerID string, q *domain.CheckinQR) error {
	_, err := f.center(centerID).Set(ctx, map[string]any{"checkin_qr": toDoc(q)}, firestore.MergeAll)
	return err
}
