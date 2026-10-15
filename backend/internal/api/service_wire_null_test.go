package api

// 와이어 계약 고정(v2.28, P56 A3·A4·B12) — 라우터를 태워 **바이트**를 본다.
//
// 왜 서비스 호출이 아니라 raw JSON인가: Go에서 nil 슬라이스와 빈 슬라이스는 len()으로 구별되지
// 않는다 — s.ListPayments가 nil을 돌려줘도 `len(x.Installments) == 0`은 초록이다. 어드민이 죽는
// 자리는 `"installments":null`이라는 바이트이므로 그 바이트를 본다(TestStatsWireContract와 같은 이유).
//
// **레거시 문서**(스토어에 직접 nil로 심은 것)를 쓰는 이유: 생성 경로의 정규화만으로는 초록이
// 되는 자리를 남기지 않기 위해서다 — 프로덕션에 이미 null인 문서가 있을 수 있고, 쓰기만 고치면
// 그 문서는 영원히 안 낫는다. 읽기 정규화가 그 문서를 위한 바닥이다.
//
// **뮤테이션 표적**:
//   - normalizePaymentWire 호출(CreatePayment / ListPayments)      → TestPaymentInstallmentsNeverNullOnWire
//   - normalizeMemberWire 호출(ListMembers 두 분기 / UpdateMember) → TestMemberFlagsNeverNullOnWire
//   - normalizePassWire 호출(hydratePassRemaining / stampPassStatus) → TestPassHoldsNeverNullOnWire
//   - 라우터 404의 code                                             → TestRouterNotFoundCarriesCode
//   - unconfiguredPurger.ListObjects의 명시적 에러 + 503 매핑         → TestReconcileUnconfiguredIs503OnWire

import (
	"context"
	"encoding/json"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/config"
	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// newTestRouterSharing — newTestRouter와 같되 서비스·스토어를 함께 돌려준다. 레거시 문서를
// 스토어에 직접 심은 뒤 **같은** 라우터로 읽어야 하는 테스트용.
func newTestRouterSharing(t *testing.T) (http.Handler, *Service, store.Store) {
	t.Helper()
	st := store.NewMemory()
	cfg := config.Config{DefaultCenterID: testCenter}
	auth, err := NewAuthenticator(context.Background(), cfg, st)
	if err != nil {
		t.Fatalf("NewAuthenticator: %v", err)
	}
	svc := NewService(st, cfg, auth.Provisioner(testInitialPassword))
	return NewRouter(NewHandlers(svc), auth, nil), svc, st
}

// assertNoNullArray — 응답 본문에 `"field":null`이 없어야 한다.
func assertNoNullArray(t *testing.T, body, field string) {
	t.Helper()
	if strings.Contains(body, `"`+field+`":null`) {
		t.Fatalf(`응답에 "%s":null — 어드민의 .filter/.some이 여기서 죽는다: %s`, field, body)
	}
}

func TestPaymentInstallmentsNeverNullOnWire(t *testing.T) {
	r, svc, st := newTestRouterSharing(t)
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, svc, 10)

	// ① 생성 경로: 일시불(installments 생략) → 응답이 []이고 **저장된 문서도** []다.
	rec := postJSON(t, r, "/v1/payments", "owner1", domain.RoleOwner,
		`{"member_id":"`+mem.ID+`","pass_id":"`+pass.ID+`","method":"card","total":500000}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("POST /v1/payments = %d %s", rec.Code, rec.Body.String())
	}
	assertNoNullArray(t, rec.Body.String(), "installments")
	var created domain.Payment
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	saved, err := st.GetPayment(ctx, testCenter, created.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Installments == nil {
		t.Fatal("저장된 문서의 installments가 nil — JSON 왕복 스토어에서는 영구히 null이다")
	}

	// ② 레거시 문서: 정규화 이전에 null로 굳은 결제를 스토어에 직접 심는다(계약가 상한은 서비스
	// 게이트라 우회된다 — 프로덕션 문서의 모양을 흉내 내는 것이 목적이다).
	if _, err := st.CreatePayment(ctx, testCenter, &domain.Payment{
		MemberID: mem.ID, PassID: pass.ID, Method: domain.PayMethodCash, Total: 100000,
		Installments: nil,
	}); err != nil {
		t.Fatal(err)
	}
	list := getJSON(t, r, "/v1/payments?member="+mem.ID, "owner1", domain.RoleOwner)
	if list.Code != http.StatusOK {
		t.Fatalf("GET /v1/payments = %d %s", list.Code, list.Body.String())
	}
	assertNoNullArray(t, list.Body.String(), "installments")
	var rows []map[string]any
	if err := json.Unmarshal(list.Body.Bytes(), &rows); err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 {
		t.Fatalf("결제 %d건, want 2", len(rows))
	}
	for _, row := range rows {
		if _, ok := row["installments"].([]any); !ok {
			t.Fatalf("installments가 배열이 아니다: %v", row["installments"])
		}
	}
}

func TestMemberFlagsNeverNullOnWire(t *testing.T) {
	r, _, st := newTestRouterSharing(t)
	ctx := context.Background()
	// 레거시: 정규화 이전에 flags가 null로 굳은 회원 문서.
	id, err := st.SaveMember(ctx, testCenter, &domain.Member{
		Name: "레거시", Phone: "010-0000-0001", Status: domain.MemberStatusActive, Flags: nil,
	})
	if err != nil {
		t.Fatal(err)
	}

	// 목록(owner 분기).
	list := getJSON(t, r, "/v1/members", "owner1", domain.RoleOwner)
	if list.Code != http.StatusOK {
		t.Fatalf("GET /v1/members = %d %s", list.Code, list.Body.String())
	}
	assertNoNullArray(t, list.Body.String(), "flags")

	// 목록(member self 분기) — 회원 앱의 "내 프로필".
	if err := st.SaveUserIndex(ctx, &store.UserIndex{
		UID: "u-legacy", Role: domain.RoleMember, CenterID: testCenter, MemberID: id,
	}); err != nil {
		t.Fatal(err)
	}
	self := getJSON(t, r, "/v1/members", "u-legacy", domain.RoleMember)
	if self.Code != http.StatusOK {
		t.Fatalf("GET /v1/members(self) = %d %s", self.Code, self.Body.String())
	}
	assertNoNullArray(t, self.Body.String(), "flags")

	// PUT 머지가 문서를 **고친다**(와이어 감사 L-3): 이름만 보내도 flags가 []로 저장된다.
	// 종전엔 slices.Clone(nil)==nil이라 PUT으로도 복구되지 않았다.
	rec := putJSON(t, r, "/v1/members/"+id, "owner1", domain.RoleOwner, `{"name":"레거시2"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("PUT /v1/members = %d %s", rec.Code, rec.Body.String())
	}
	assertNoNullArray(t, rec.Body.String(), "flags")
	healed, err := st.GetMember(ctx, testCenter, id)
	if err != nil {
		t.Fatal(err)
	}
	if healed.Flags == nil {
		t.Fatal("PUT 뒤에도 저장된 flags가 nil — 이미 null인 문서를 되살릴 쓰기 경로가 없다")
	}
}

func TestPassHoldsNeverNullOnWire(t *testing.T) {
	r, svc, st := newTestRouterSharing(t)
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, svc, 10)

	// 레거시: holds가 null로 굳은 패스 — 스토어에 직접 덮어쓴다(정규화된 생성 경로를 우회).
	legacy, err := st.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	legacy.Holds = nil
	if err := st.UpdatePass(ctx, testCenter, legacy); err != nil {
		t.Fatal(err)
	}

	// 목록 경로(hydratePassRemaining): GET /v1/passes + GET /v1/members의 임베드 passes[].
	list := getJSON(t, r, "/v1/passes?member="+mem.ID, "owner1", domain.RoleOwner)
	if list.Code != http.StatusOK {
		t.Fatalf("GET /v1/passes = %d %s", list.Code, list.Body.String())
	}
	assertNoNullArray(t, list.Body.String(), "holds")
	members := getJSON(t, r, "/v1/members", "owner1", domain.RoleOwner)
	if members.Code != http.StatusOK {
		t.Fatalf("GET /v1/members = %d %s", members.Code, members.Body.String())
	}
	assertNoNullArray(t, members.Body.String(), "holds")

	// 단건 경로(stampPassStatus): 발급·홀딩·재개는 holds를 채우므로 nil이 될 수 없고, **환불**만
	// 저장된 문서를 그대로 응답한다 — 레거시 null이 새는 유일한 단건 응답이다.
	refund := postJSON(t, r, "/v1/passes/"+pass.ID+"/refund", "owner1", domain.RoleOwner, `{"used":0}`)
	if refund.Code != http.StatusOK {
		t.Fatalf("POST /v1/passes/{id}/refund = %d %s", refund.Code, refund.Body.String())
	}
	assertNoNullArray(t, refund.Body.String(), "holds")
}

// 라우터 404와 리소스 404를 가른다(v2.28, P56 B12).
//
// 어드민의 "404 = 아직 미배포" 규약은 이 code 하나로만 성립한다. 종전엔 두 404가 status·body까지
// 같아서, 좀비 요청 경합의 리소스 404를 "거절 기능 미배포"로 접어 대표에게 *"그동안은 승인만
// 처리하세요"*라고 안내했다 — 그 승인이 P55 C-2다.
//
// **뮤테이션 표적**: router.go NotFound의 code를 지우면(옛 errBody로 되돌리면) 여기서 죽는다.
// 리소스 404에 code를 실어도 죽는다(어드민이 그것을 미배포로 접는다).
func TestRouterNotFoundCarriesCode(t *testing.T) {
	r := newTestRouter(t)

	decode := func(t *testing.T, body []byte) map[string]any {
		t.Helper()
		var m map[string]any
		if err := json.Unmarshal(body, &m); err != nil {
			t.Fatalf("본문이 JSON이 아니다: %s", body)
		}
		return m
	}

	// 라우터 404 — 이 배포에 없는 경로(인증 뒤 /v1 서브라우터: 부모의 NotFound를 상속한다).
	rec := getJSON(t, r, "/v1/definitely-not-a-route", "owner1", domain.RoleOwner)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("없는 경로 = %d, want 404 (%s)", rec.Code, rec.Body.String())
	}
	body := decode(t, rec.Body.Bytes())
	if body["code"] != codeRouteNotFound {
		t.Fatalf("라우터 404 = %v, want code=%q — 어드민이 미배포를 판정할 유일한 근거다", body, codeRouteNotFound)
	}
	if body["error"] == "" || body["error"] == nil {
		t.Fatalf("라우터 404에 error 문구가 없다: %v", body)
	}
	if cc := rec.Header().Get("Cache-Control"); cc != "no-store" {
		t.Fatalf("라우터 404 Cache-Control = %q, want no-store(P34 — 캐시된 404가 복구를 무효화한다)", cc)
	}
	// 인증 밖 루트도 같은 code(같은 핸들러).
	root := getJSON(t, r, "/nope", "", "")
	if root.Code != http.StatusNotFound || decode(t, root.Body.Bytes())["code"] != codeRouteNotFound {
		t.Fatalf("루트 404 = %d %s, want code=%q", root.Code, root.Body.String(), codeRouteNotFound)
	}

	// 리소스 404 — 있는 경로, 없는 id. **code가 없어야 한다**(무변경).
	res := postJSON(t, r, "/v1/join/reject", "owner1", domain.RoleOwner, `{"request_id":"jreq_does_not_exist"}`)
	if res.Code != http.StatusNotFound {
		t.Fatalf("없는 request_id = %d, want 404 (%s)", res.Code, res.Body.String())
	}
	resBody := decode(t, res.Body.Bytes())
	if _, has := resBody["code"]; has {
		t.Fatalf("리소스 404에 code가 실렸다(%v) — 어드민이 '미배포'로 접어 대표에게 승인만 하라고 안내한다", resBody)
	}
	if resBody["error"] != "찾을 수 없음" {
		t.Fatalf("리소스 404 본문 = %v, want {error:\"찾을 수 없음\"} 무변경", resBody)
	}
}

// 미구성 파기 경계의 훑기는 와이어에서 **503**이다(v2.28, P56 A4) — 200 "고아 0건"이 아니다.
//
// **뮤테이션 표적**: util.go writeErr의 ErrMediaListUnavailable 503 매핑을 지우면(500으로
// 떨어진다) 여기서 죽는다. ListObjects를 nil,nil로 되돌려도 죽는다(200).
func TestReconcileUnconfiguredIs503OnWire(t *testing.T) {
	r, svc, _ := newTestRouterSharing(t) // 파기 경계 미주입 = unconfiguredPurger
	mem := consentingMember(t, svc)

	rec := postJSON(t, r, "/v1/body-photos/reconcile?member="+mem.ID, "owner1", domain.RoleOwner, ``)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("미구성 훑기 = %d %s, want 503 — 200이면 대표는 버킷이 깨끗하다고 믿는다", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	msg, _ := body["error"].(string)
	if !strings.Contains(msg, "STORAGE_BUCKET") {
		t.Fatalf("503 문구 = %q — 무엇을 설정해야 하는지 말해야 고칠 사람이 원인에 도달한다", msg)
	}
	if strings.Contains(msg, "api:") {
		t.Fatalf("내부 마커가 응답에 샜다: %q", msg)
	}
	// code(어드민 갈래 요청 3): code 없는 503은 어드민이 전달 경로 장애로 읽어 재시도를 권한다 —
	// 재시도로 안 낫는 설정 문제임을 기계가 읽어야 한다. **뮤테이션 표적**: writeErr의 code를 지우면 죽는다.
	if body["code"] != codeMediaNotConfigured {
		t.Fatalf("503 body = %v, want code=%q", body, codeMediaNotConfigured)
	}
}

// firestoreShapedPassStore — 트랜잭션 갱신 결과를 **Firestore 모양**으로 돌려주는 래퍼.
//
// Memory의 UpdatePassWithLedger*는 `append([]domain.Hold{}, cur.Holds...)`로 롤백 안전을 위해
// 슬라이스를 새로 만들기 때문에 holds가 **절대 nil이 아니다**. Firestore 구현은 문서를
// fromDoc(JSON)으로 읽어 mutate한 값을 그대로 돌려주므로 null 문서는 nil로 나온다. 즉 이
// 결함은 기본 `go test`(Memory)로는 영원히 초록이다(P49·P53이 적은 "에뮬레이터 전용" 자리).
// 스토어를 바꾸지 않고 그 모양만 흉내 내 단건 응답 경로(stampPassStatus)의 정규화를 고정한다.
type firestoreShapedPassStore struct{ store.Store }

func (f firestoreShapedPassStore) UpdatePassWithLedgerAndContracts(
	ctx context.Context, centerID, passID string, mutate store.PassMutator,
	contractIDs []string, sweep store.ContractSweepMutator,
) (*domain.Pass, error) {
	out, err := f.Store.UpdatePassWithLedgerAndContracts(ctx, centerID, passID, mutate, contractIDs, sweep)
	if out != nil && len(out.Holds) == 0 {
		out.Holds = nil // Firestore가 null 문서를 읽었을 때의 모양
	}
	return out, err
}

// **뮤테이션 표적**: stampPassStatus의 normalizePassWire를 지우면 여기서 죽는다(Memory 스토어로는
// 위 이유로 살아남는다 — 그래서 래퍼가 필요하다).
func TestRefundResponseHoldsNeverNullWithFirestoreShapedStore(t *testing.T) {
	st := store.NewMemory()
	cfg := config.Config{DefaultCenterID: testCenter}
	svc := NewService(firestoreShapedPassStore{Store: st}, cfg, nil)
	mem, pass := seedMemberWithPass(t, svc, 10)
	_ = mem

	got, _, err := svc.RefundPass(context.Background(), ownerP(), pass.ID, 0)
	if err != nil {
		t.Fatalf("RefundPass: %v", err)
	}
	raw, err := json.Marshal(got)
	if err != nil {
		t.Fatal(err)
	}
	assertNoNullArray(t, string(raw), "holds")
}

// ---- B1 완결(v2.28): 철회 상태의 목록은 403이 아니라 **메타만**의 잠긴 목록이다 ----

// bodyPhotoMetaKeys — 잠긴 목록 원소에 허용되는 키 집합. **storage_path·blurred는 여기 없다** —
// 경로가 나가면 이미지에 닿을 수 있어 "열람 잠금"이 거짓이 된다.
var bodyPhotoMetaKeys = map[string]bool{
	"id": true, "member_id": true, "pose": true, "direction": true, "date": true, "deleted_at": true,
}

func assertMetaOnlyKeys(t *testing.T, row map[string]any) {
	t.Helper()
	for k := range row {
		if !bodyPhotoMetaKeys[k] {
			t.Fatalf("잠긴 목록에 %q가 샜다 — 허용 키는 %v: %v", k, bodyPhotoMetaKeys, row)
		}
	}
	for _, k := range []string{"id", "member_id", "pose", "direction", "date"} {
		if _, ok := row[k]; !ok {
			t.Fatalf("잠긴 목록에 %q가 없다 — 데스크가 어느 사진인지 알아볼 라벨이다: %v", k, row)
		}
	}
}

// **뮤테이션 표적**: BodyPhotoMeta에 StoragePath/Blurred 필드를 넣으면 죽는다(키 집합).
func TestBodyPhotoMetaWireKeys(t *testing.T) {
	now := time.Now().UTC()
	raw, err := json.Marshal(BodyPhotoMeta{ID: "b1", MemberID: "m1", Pose: "stand", Direction: "front", Date: "2026-09-04", DeletedAt: &now})
	if err != nil {
		t.Fatal(err)
	}
	var row map[string]any
	if err := json.Unmarshal(raw, &row); err != nil {
		t.Fatal(err)
	}
	assertMetaOnlyKeys(t, row)
	if len(row) != len(bodyPhotoMetaKeys) {
		t.Fatalf("키 집합 = %v, want 정확히 %v", row, bodyPhotoMetaKeys)
	}
}

// **뮤테이션 표적**: ListBodyPhotos의 "스태프+스코프 안 → Locked" 분기를 지우면(403 복원) 죽는다.
// 핸들러가 Locked에도 Full을 쓰면(빈 배열) 죽는다. bodyPhotoMetaOf가 storage_path를 옮기면 죽는다.
func TestBodyPhotoListLockedIsMetaOnlyOnWire(t *testing.T) {
	r, svc, st := newTestRouterSharing(t)
	ctx := context.Background()
	mem := consentingMember(t, svc)
	bp := seedPhoto(t, svc, mem.ID, "stand")
	keep := seedPhoto(t, svc, mem.ID, "tpose")

	decodeRows := func(t *testing.T, body []byte) []map[string]any {
		t.Helper()
		var rows []map[string]any
		if err := json.Unmarshal(body, &rows); err != nil {
			t.Fatalf("본문이 배열이 아니다: %s", body)
		}
		return rows
	}

	// 동의 유효: 계약 원본 모양(무변경 — storage_path 포함).
	full := getJSON(t, r, "/v1/body-photos?member="+mem.ID, "owner1", domain.RoleOwner)
	if full.Code != http.StatusOK {
		t.Fatalf("동의 유효 목록 = %d %s", full.Code, full.Body.String())
	}
	if rows := decodeRows(t, full.Body.Bytes()); len(rows) != 2 || rows[0]["storage_path"] == nil {
		t.Fatalf("동의 유효 목록 = %v, want 2건 + storage_path", rows)
	}

	// 회원이 동의를 철회한다(실제 경로 — 서버가 revoked_at을 찍는다).
	if _, err := svc.UpdateMember(ctx, memberP(mem.ID), mem.ID, []byte(`{"consent":{"sensitive":false}}`)); err != nil {
		t.Fatalf("동의 철회: %v", err)
	}

	// 대표: 200 + 메타만.
	locked := getJSON(t, r, "/v1/body-photos?member="+mem.ID, "owner1", domain.RoleOwner)
	if locked.Code != http.StatusOK {
		t.Fatalf("철회 후 목록 = %d %s — 403이면 스태프는 지울 id를 얻을 길이 없다(서버만 열린 절반 수리)", locked.Code, locked.Body.String())
	}
	rows := decodeRows(t, locked.Body.Bytes())
	if len(rows) != 2 {
		t.Fatalf("잠긴 목록 = %v, want 2건", rows)
	}
	for _, row := range rows {
		assertMetaOnlyKeys(t, row)
		if _, has := row["deleted_at"]; has {
			t.Fatalf("살아 있는 사진에 deleted_at이 실렸다: %v", row)
		}
	}
	// 담당 코치도 잠긴 목록(스코프 안). 담당 아닌 코치는 403 그대로.
	if tr := getJSON(t, r, "/v1/body-photos?member="+mem.ID, "t1", domain.RoleTrainer); tr.Code != http.StatusOK {
		t.Fatalf("철회 후 담당 코치 목록 = %d %s", tr.Code, tr.Body.String())
	}
	if other := getJSON(t, r, "/v1/body-photos?member="+mem.ID, "t2", domain.RoleTrainer); other.Code != http.StatusForbidden {
		t.Fatalf("철회 후 담당 아닌 코치 목록 = %d, want 403", other.Code)
	}

	// 그 id로 실제로 지운다 — 방침이 안내하는 경로가 여기서 완결된다.
	// 목록 순서는 비결정적이다(메모리 스토어 맵 순회) — rows[0]을 지우면 회차에 따라 keep이
	// 지워져 아래 "살아 있는 1건 = keep" 단언이 간헐 실패했다(P62 검증 중 3회 중 1회 실측).
	// 잠긴 목록이 **id를 준다**는 사실은 그대로 확인하되, 지우는 대상은 bp로 고정한다.
	var lockedIDs []string
	for _, row := range rows {
		lockedIDs = append(lockedIDs, row["id"].(string))
	}
	if !slices.Contains(lockedIDs, bp.ID) {
		t.Fatalf("잠긴 목록에 %s가 없다: %v", bp.ID, lockedIDs)
	}
	if _, err := svc.DeleteBodyPhoto(ctx, ownerP(), bp.ID); err != nil {
		t.Fatalf("잠긴 목록의 id로 삭제 = %v", err)
	}
	// 휴지통 뷰(include_deleted)도 메타만 + deleted_at.
	trash := getJSON(t, r, "/v1/body-photos?member="+mem.ID+"&include_deleted=true", "owner1", domain.RoleOwner)
	if trash.Code != http.StatusOK {
		t.Fatalf("잠긴 휴지통 = %d %s", trash.Code, trash.Body.String())
	}
	deletedSeen := 0
	for _, row := range decodeRows(t, trash.Body.Bytes()) {
		assertMetaOnlyKeys(t, row)
		if _, has := row["deleted_at"]; has {
			deletedSeen++
		}
	}
	if deletedSeen != 1 {
		t.Fatalf("잠긴 휴지통에 deleted_at 원소 %d건, want 1", deletedSeen)
	}

	// 회원 본인은 잠기지 않는다(본인 = 동의와 무관, 무변경) — 계약 원본 모양 그대로.
	if err := st.SaveUserIndex(ctx, &store.UserIndex{UID: "u-" + mem.ID, Role: domain.RoleMember, CenterID: testCenter, MemberID: mem.ID}); err != nil {
		t.Fatal(err)
	}
	self := getJSON(t, r, "/v1/body-photos?member="+mem.ID, "u-"+mem.ID, domain.RoleMember)
	if self.Code != http.StatusOK {
		t.Fatalf("철회 후 본인 목록 = %d %s", self.Code, self.Body.String())
	}
	selfRows := decodeRows(t, self.Body.Bytes())
	if len(selfRows) != 1 || selfRows[0]["id"] != keep.ID || selfRows[0]["storage_path"] != keep.StoragePath {
		t.Fatalf("본인 목록 = %v, want 살아 있는 1건(%s) 계약 원본 모양", selfRows, keep.ID)
	}
}

// ---- include_deleted(v2.28): v2.14 "30일 안에 복원" 약속을 새로고침 뒤에도 참으로 ----

// **뮤테이션 표적**: `includeDeleted && !p.IsStaff()` 가드를 지우면 죽는다(회원 403). 삭제분 필터에서
// includeDeleted 조건을 지우면(항상 거름) 죽는다. 조건을 뒤집으면(항상 포함) 죽는다.
func TestBodyPhotoIncludeDeletedIsStaffOnly(t *testing.T) {
	r, svc, st := newTestRouterSharing(t)
	ctx := context.Background()
	mem := consentingMember(t, svc)
	live := seedPhoto(t, svc, mem.ID, "stand")
	gone := seedPhoto(t, svc, mem.ID, "tpose")
	if _, err := svc.DeleteBodyPhoto(ctx, ownerP(), gone.ID); err != nil { // 스태프 삭제 = 소프트(유예)
		t.Fatal(err)
	}

	decodeRows := func(t *testing.T, body []byte) []map[string]any {
		t.Helper()
		var rows []map[string]any
		if err := json.Unmarshal(body, &rows); err != nil {
			t.Fatalf("본문이 배열이 아니다: %s", body)
		}
		return rows
	}

	// 기본: 삭제분 제외(무변경 — "즉시 사라진다").
	base := decodeRows(t, getJSON(t, r, "/v1/body-photos?member="+mem.ID, "owner1", domain.RoleOwner).Body.Bytes())
	if len(base) != 1 || base[0]["id"] != live.ID {
		t.Fatalf("기본 목록 = %v, want 살아 있는 1건", base)
	}
	// include_deleted: 삭제분 포함 + deleted_at(RFC3339).
	all := decodeRows(t, getJSON(t, r, "/v1/body-photos?member="+mem.ID+"&include_deleted=true", "owner1", domain.RoleOwner).Body.Bytes())
	if len(all) != 2 {
		t.Fatalf("include_deleted 목록 = %v, want 2건", all)
	}
	found := false
	for _, row := range all {
		if row["id"] == gone.ID {
			found = true
			ts, _ := row["deleted_at"].(string)
			if _, err := time.Parse(time.RFC3339, ts); err != nil {
				t.Fatalf("삭제분의 deleted_at = %v — 어드민 휴지통이 남은 유예를 계산하는 값이다", row["deleted_at"])
			}
		} else if _, has := row["deleted_at"]; has {
			t.Fatalf("살아 있는 사진에 deleted_at: %v", row)
		}
	}
	if !found {
		t.Fatalf("include_deleted인데 삭제분이 없다: %v", all)
	}
	// 담당 코치도 스태프 — 된다.
	if tr := getJSON(t, r, "/v1/body-photos?member="+mem.ID+"&include_deleted=true", "t1", domain.RoleTrainer); tr.Code != http.StatusOK || len(decodeRows(t, tr.Body.Bytes())) != 2 {
		t.Fatalf("담당 코치 include_deleted = %d %s, want 200 2건", tr.Code, tr.Body.String())
	}

	// 회원은 **403** — 회원 화면에서 삭제분은 "즉시 사라진다"(v2.13). 조용히 무시하지 않는다:
	// 회원 앱이 이 파라미터를 보내는 순간 그것은 버그이고, 버그는 크게 실패해야 보인다.
	if err := st.SaveUserIndex(ctx, &store.UserIndex{UID: "u-" + mem.ID, Role: domain.RoleMember, CenterID: testCenter, MemberID: mem.ID}); err != nil {
		t.Fatal(err)
	}
	if m := getJSON(t, r, "/v1/body-photos?member="+mem.ID+"&include_deleted=true", "u-"+mem.ID, domain.RoleMember); m.Code != http.StatusForbidden {
		t.Fatalf("회원 include_deleted = %d %s, want 403 — 회원 경로로 삭제분이 샌다", m.Code, m.Body.String())
	}
	// 파라미터 없는 회원 조회는 그대로 살아 있는 것만.
	self := decodeRows(t, getJSON(t, r, "/v1/body-photos?member="+mem.ID, "u-"+mem.ID, domain.RoleMember).Body.Bytes())
	if len(self) != 1 || self[0]["id"] != live.ID {
		t.Fatalf("회원 기본 목록 = %v, want 살아 있는 1건", self)
	}
}
