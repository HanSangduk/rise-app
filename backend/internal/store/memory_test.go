package store

// 스토어 레이어 테스트. 여기서 고정하는 건 "어느 레코드를 돌려주는가" 하나다 — 같은 번호를
// 쓰는 회원이 둘 이상일 때 두 구현(Memory·Firestore)이 같은 답을 내야 한다. Firestore는
// 에뮬레이터 없이 돌릴 수 없으므로, 두 구현이 공유하는 betterPhoneMatch를 직접 못박고
// Memory로 스캔 경로까지 훑는다(firestore.go는 같은 함수를 호출한다).

import (
	"context"
	"errors"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

// 빈 문서 ID 조회는 두 스토어 공통으로 ErrNotFound다(errors.go의 checkDocID).
//
// 왜 중요한가: 미배정 담당(trainer_id == "")은 1급 상태라 GetStaff(ctx, center, "")가 실제로
// 호출된다. Memory는 맵 미스라 ErrNotFound지만, Firestore의 Collection.Doc("")는 빈 ID
// DocumentRef를 만들고 Get RPC가 codes.InvalidArgument로 실패한다 — mapNotFound는 NotFound만
// 변환하므로 그대로 500이 된다. 즉 가드가 없으면 **같은 호출이 로컬 404, 운영 500**이다.
// (Firestore는 에뮬레이터 없이 못 돌리므로 betterPhoneMatch·sortByDocID 선례처럼 공유 규칙
// 자체를 못박고, 실제 스캔 경로는 Memory로 확인한다.)
func TestEmptyDocIDIsNotFound(t *testing.T) {
	if err := checkDocID(""); !errors.Is(err, ErrNotFound) {
		t.Fatalf("checkDocID(\"\") = %v, want ErrNotFound", err)
	}
	if err := checkDocID("t1"); err != nil {
		t.Fatalf("checkDocID(\"t1\") = %v, want nil", err)
	}

	ctx := context.Background()
	m := NewMemory()
	// 빈 UID 레코드를 일부러 심는다 — 가드가 없으면 맵이 이걸 집어 "미배정 담당" 조회가
	// 유령 스태프를 반환한다(가드가 실제로 동작하는지 보려면 맵 미스로는 부족하다).
	if err := m.SaveStaff(ctx, "rise", &domain.Staff{UID: "", Name: "유령", Role: domain.RoleTrainer}); err != nil {
		t.Fatal(err)
	}
	if got, err := m.GetStaff(ctx, "rise", ""); !errors.Is(err, ErrNotFound) {
		t.Fatalf("GetStaff(\"\") = %+v, %v — want ErrNotFound", got, err)
	}
	// 정상 uid는 그대로 조회된다(가드가 과잉 차단하지 않는지).
	if err := m.SaveStaff(ctx, "rise", &domain.Staff{UID: "t1", Name: "정혜린", Role: domain.RoleTrainer}); err != nil {
		t.Fatal(err)
	}
	if got, err := m.GetStaff(ctx, "rise", "t1"); err != nil || got.Name != "정혜린" {
		t.Fatalf("GetStaff(\"t1\") = %+v, %v", got, err)
	}
}

// 우선순위 규칙 자체를 못박는다 — Firestore 구현이 그대로 재사용하는 비교자다.
func TestBetterPhoneMatchPriority(t *testing.T) {
	linkedFirst := &domain.Member{ID: "mem_000001", AppLinked: true}
	unlinkedLater := &domain.Member{ID: "mem_000009", AppLinked: false}
	unlinkedFirst := &domain.Member{ID: "mem_000002", AppLinked: false}

	if !betterPhoneMatch(linkedFirst, nil) {
		t.Fatal("첫 후보는 항상 채택돼야 한다")
	}
	// ① 미연결 우선 — ID가 뒤여도 이미 연결된 레코드를 이긴다(연결된 쪽은 주인이 있다).
	if !betterPhoneMatch(unlinkedLater, linkedFirst) {
		t.Fatal("미연결 회원이 연결된 회원을 이기지 못함 — 남의 레코드에 올라탄다")
	}
	if betterPhoneMatch(linkedFirst, unlinkedLater) {
		t.Fatal("연결된 회원이 미연결 회원을 이김 — 우선순위 역전")
	}
	// ② 동률이면 ID 오름차순.
	if !betterPhoneMatch(unlinkedFirst, unlinkedLater) {
		t.Fatal("같은 조건에서 ID 오름차순이 아님")
	}
	if betterPhoneMatch(unlinkedLater, unlinkedFirst) {
		t.Fatal("ID 비교가 대칭적으로 깨짐 — 전순서가 아니다")
	}
}

// 감사 실측 회귀: 같은 번호 회원이 둘이면 호출마다 다른 사람이 나왔다(60회 중 55/5로 갈림).
// 맵 순회 순서에 기대지 않는지 반복 호출로 확인한다.
func TestFindMemberByPhoneIsDeterministic(t *testing.T) {
	ctx := context.Background()
	m := NewMemory()
	// 부모 번호로 자녀 둘 + 이미 앱에 연결된 형제 하나. 저장 순서와 ID 순서를 일부러 어긋나게 둔다.
	for _, mem := range []*domain.Member{
		{ID: "mem_000007", Name: "둘째", Phone: "010-1234-5678"},
		{ID: "mem_000003", Name: "첫째", Phone: "+82 10-1234-5678"}, // 표기가 달라도 같은 번호
		{ID: "mem_000001", Name: "엄마", Phone: "01012345678", AppLinked: true},
	} {
		if _, err := m.SaveMember(ctx, "rise", mem); err != nil {
			t.Fatal(err)
		}
	}
	// 다른 센터의 동일 번호는 절대 새어나오면 안 된다(센터 경계).
	if _, err := m.SaveMember(ctx, "other", &domain.Member{ID: "mem_000000", Name: "타센터", Phone: "010-1234-5678"}); err != nil {
		t.Fatal(err)
	}

	for i := range 60 {
		got, err := m.FindMemberByPhone(ctx, "rise", "010-1234-5678")
		if err != nil {
			t.Fatalf("%d회차 조회 실패: %v", i, err)
		}
		// 미연결 중 ID가 가장 작은 "첫째"가 항상 나와야 한다(엄마는 연결됨, 둘째는 ID가 뒤).
		if got.ID != "mem_000003" {
			t.Fatalf("%d회차에 %s(%s) — 매칭이 비결정적이다", i, got.ID, got.Name)
		}
	}

	// 후보가 모두 연결된 경우엔 ID 오름차순으로 떨어진다(폴백 경로).
	linkedOnly := NewMemory()
	for _, mem := range []*domain.Member{
		{ID: "mem_000005", Phone: "010-1234-5678", AppLinked: true},
		{ID: "mem_000002", Phone: "010-1234-5678", AppLinked: true},
	} {
		if _, err := linkedOnly.SaveMember(ctx, "rise", mem); err != nil {
			t.Fatal(err)
		}
	}
	for range 30 {
		got, err := linkedOnly.FindMemberByPhone(ctx, "rise", "010-1234-5678")
		if err != nil || got.ID != "mem_000002" {
			t.Fatalf("연결된 회원만 있을 때 결과가 흔들림: %v %+v", err, got)
		}
	}
}
