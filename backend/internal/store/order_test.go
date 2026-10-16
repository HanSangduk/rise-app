package store

// 목록 정렬 규약 테스트(order.go). 여기서 고정하는 건 하나다 — **Memory와 Firestore가 같은
// 순서를 낸다**.
//
// Firestore는 에뮬레이터 없이 돌릴 수 없으므로 betterPhoneMatch 선례와 같은 방식을 쓴다:
// 두 구현이 공유하는 헬퍼(sortByDocID + 컬렉션별 문서 ID 추출자) 자체를 못박고, Memory로
// 실제 스캔 경로까지 훑는다. firestore.go의 List 7종은 같은 헬퍼를 호출한다.
//
// "문서 ID 오름차순"이 기준인 이유: Firestore는 orderBy 없는 쿼리를 __name__ 오름차순으로
// 돌려준다. 반면 Memory는 맵 순회라 매 호출 순서가 달라져, 정렬이 없으면 로컬에서만
// 새로고침마다 목록이 뒤바뀐다(앱의 기본 패스 선택이 첫 active 패스를 집는다).

import (
	"context"
	"math/rand"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// 비교자 자체를 못박는다 — Firestore 구현이 그대로 재사용한다.
func TestSortByDocIDIsAscending(t *testing.T) {
	rows := []domain.Recurring{{ID: "rec_c"}, {ID: "rec_a"}, {ID: "rec_b"}}
	sortByDocID(rows, recurringDocID)
	for i, want := range []string{"rec_a", "rec_b", "rec_c"} {
		if rows[i].ID != want {
			t.Fatalf("rows[%d].ID = %q, want %q — 문서 ID 오름차순이 아니다", i, rows[i].ID, want)
		}
	}
}

// 회원권만 문서 ID가 아니라 valid_from이 기준이다(P13 M1). Firestore의 문서 ID는 무작위 20자라
// ID 정렬로는 두 스토어가 "같은 규칙, 다른 순서"였고, 회원 앱의 기본 회원권 선택이 제비뽑기가 됐다.
func TestSortPassesByValidFromThenID(t *testing.T) {
	rows := []domain.Pass{
		{ID: "zzz", ValidFrom: "2026-03-01"},
		{ID: "aaa", ValidFrom: "2026-09-01"}, // ID는 가장 앞이지만 시작일이 가장 늦다
		{ID: "mmm", ValidFrom: "2026-03-01"},
	}
	sortPasses(rows)
	for i, want := range []string{"mmm", "zzz", "aaa"} {
		if rows[i].ID != want {
			t.Fatalf("rows[%d].ID = %q, want %q — valid_from 오름차순(동률은 ID) 아님: %+v", i, rows[i].ID, want, rows)
		}
	}
}

// hwChecks만 엔티티 ID 필드가 없다. 정렬 키가 **Firestore가 실제로 쓰는 문서 ID**와 같은
// 함수에서 나와야 두 스토어의 순서가 일치한다(SaveHwCheck가 hwCheckDocID로 문서를 쓴다).
// Memory의 맵 키(구분자 "/")로 정렬하면 구분자 바이트가 달라 순서가 갈릴 수 있다.
//
// 기대값은 **리터럴 문자열**로 적는다. hwCheckDocID(...)로 want를 만들면 "정의 == 정의"라
// 규칙이 어떻게 바뀌어도 항상 참이다(자기참조 골든). 그런데 이 값은 Firestore의 실제 문서
// ID(SaveHwCheck)이고 Memory는 "/" 구분자 맵 키를 쓰므로, 규칙이 바뀌어도 **로컬에선 아무
// 테스트도 깨지지 않은 채 운영의 문서 경로만 갈라진다** — 이미 쓰인 문서를 못 찾는 종류의 사고다.
func TestHwCheckSortKeyIsTheFirestoreDocID(t *testing.T) {
	// 규칙 자체를 리터럴로 못박는다: member_id + "_" + hw_id + "_" + date, 문서 ID 금지문자는 "_"로.
	for _, tc := range []struct {
		memberID, hwID, date string
		want                 string
	}{
		{"mem_1", "hw_1", "2026-08-23", "mem_1_hw_1_2026-08-23"},
		// 금지문자 치환(docKey): "/" "\" "." "#" "$" "[" "]" → "_". Firestore 문서 ID에 "/"가
		// 들어가면 경로가 쪼개지고, 나머지는 규칙/쿼리 예약문자다.
		{"mem/1", "hw.a", "2026#08#23", "mem_1_hw_a_2026_08_23"},
		{"a$b", "c[d]", "e\\f", "a_b_c_d__e_f"},
	} {
		if got := hwCheckDocID(tc.memberID, tc.hwID, tc.date); got != tc.want {
			t.Errorf("hwCheckDocID(%q,%q,%q) = %q, want %q", tc.memberID, tc.hwID, tc.date, got, tc.want)
		}
	}
	// 정렬 키(hwCheckDocIDOf)도 같은 리터럴이어야 한다 — 저장 ID와 정렬 키가 한 값임을 고정.
	c := domain.HwCheck{MemberID: "mem_1", HwID: "hw_1", Date: "2026-08-23"}
	if got := hwCheckDocIDOf(c); got != "mem_1_hw_1_2026-08-23" {
		t.Fatalf("정렬 키 = %q, want %q(= SaveHwCheck가 쓰는 문서 ID)", got, "mem_1_hw_1_2026-08-23")
	}
	// 두 규칙이 실제로 갈리는 표본: 한 member_id가 다른 쪽의 접두일 때 구분자 바이트가 승부를
	// 가른다. "_"(0x5F) > "2"(0x32) > "/"(0x2F)라서 순서가 정확히 뒤집힌다.
	//   문서 ID: "mem_12_…" < "mem_1_…"   (Firestore가 주는 순서)
	//   맵   키: "…/mem_1/…" < "…/mem_12/…"
	short := domain.HwCheck{MemberID: "mem_1", HwID: "hw_a", Date: "2026-08-01"}
	long := domain.HwCheck{MemberID: "mem_12", HwID: "hw_a", Date: "2026-08-01"}
	mapKey := func(c domain.HwCheck) string { return "rise/" + c.MemberID + "/" + c.HwID + "/" + c.Date }
	if !(hwCheckDocIDOf(long) < hwCheckDocIDOf(short)) || !(mapKey(short) < mapKey(long)) {
		t.Fatalf("표본이 두 규칙을 가르지 못한다(테스트 전제 붕괴): doc %q/%q map %q/%q",
			hwCheckDocIDOf(short), hwCheckDocIDOf(long), mapKey(short), mapKey(long))
	}
	rows := []domain.HwCheck{short, long}
	sortByDocID(rows, hwCheckDocIDOf)
	if rows[0].MemberID != long.MemberID {
		t.Fatalf("hwChecks 정렬이 맵 키 기준으로 샘 — got %+v", rows)
	}

	// Memory의 실제 스캔 경로도 같은 답을 내야 한다.
	ctx := context.Background()
	m := NewMemory()
	for _, c := range []domain.HwCheck{short, long} {
		cc := c
		if err := m.SaveHwCheck(ctx, "rise", &cc); err != nil {
			t.Fatal(err)
		}
	}
	got, err := m.ListHwChecks(ctx, "rise")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].MemberID != long.MemberID {
		t.Fatalf("ListHwChecks = %+v, want %s 먼저(문서 ID 오름차순)", got, long.MemberID)
	}
}

// Memory의 List 7종이 실제로 그 규칙을 따르는지. 삽입 순서를 ID 순서와 일부러 어긋나게 두고,
// 맵 순회의 비결정성이 드러나도록 반복 조회한다(정렬 없던 시절 여기서 매번 다른 답이 나왔다).
func TestMemoryListsAreOrderedByDocID(t *testing.T) {
	ctx := context.Background()
	m := NewMemory()
	const center = "rise"

	// 저장 순서: 역순·뒤섞임. 기대 순서: 문서 ID 오름차순.
	for _, id := range []string{"pass_c", "pass_a", "pass_b"} {
		if _, err := m.CreatePass(ctx, center, &domain.Pass{ID: id, MemberID: "mem_1"}); err != nil {
			t.Fatal(err)
		}
	}
	for _, id := range []string{"rec_b", "rec_a"} {
		if _, err := m.CreateRecurring(ctx, center, &domain.Recurring{ID: id}); err != nil {
			t.Fatal(err)
		}
	}
	for _, id := range []string{"hw_c", "hw_a", "hw_b"} {
		if _, err := m.CreateHomework(ctx, center, &domain.Homework{ID: id}); err != nil {
			t.Fatal(err)
		}
	}
	for _, id := range []string{"pay_b", "pay_a"} {
		if _, err := m.CreatePayment(ctx, center, &domain.Payment{ID: id}); err != nil {
			t.Fatal(err)
		}
	}
	checks := []domain.HwCheck{
		{MemberID: "mem_1", HwID: "hw_b", Date: "2026-08-01"},
		{MemberID: "mem_1", HwID: "hw_a", Date: "2026-08-03"},
		{MemberID: "mem_1", HwID: "hw_a", Date: "2026-08-01"},
	}
	for i := range checks {
		if err := m.SaveHwCheck(ctx, center, &checks[i]); err != nil {
			t.Fatal(err)
		}
	}
	// 다른 센터 데이터가 순서에 섞이면 안 된다(센터 경계 + 정렬 동시 확인).
	if _, err := m.CreatePass(ctx, "other", &domain.Pass{ID: "pass_aaa", MemberID: "mem_1"}); err != nil {
		t.Fatal(err)
	}

	wantPasses := []string{"pass_a", "pass_b", "pass_c"}
	// 기대값은 리터럴이다 — hwCheckDocID로 만들면 함수가 바뀌어도 기대값이 같이 따라가
	// 순서만 맞으면 통과한다(문서 ID 규칙 변경을 못 잡는다).
	wantChecks := []string{ // 문서 ID(mem_hw_date) 오름차순
		"mem_1_hw_a_2026-08-01",
		"mem_1_hw_a_2026-08-03",
		"mem_1_hw_b_2026-08-01",
	}

	// 맵 순회는 호출마다 순서가 달라진다 — 한 번 맞은 게 우연이 아님을 반복으로 확인한다.
	for i := range 30 {
		byMember, err := m.ListPassesByMember(ctx, center, "mem_1")
		if err != nil {
			t.Fatal(err)
		}
		assertIDs(t, i, "ListPassesByMember", passIDs(byMember), wantPasses)

		all, err := m.ListPasses(ctx, center)
		if err != nil {
			t.Fatal(err)
		}
		assertIDs(t, i, "ListPasses", passIDs(all), wantPasses)

		recs, err := m.ListRecurrings(ctx, center)
		if err != nil {
			t.Fatal(err)
		}
		got := make([]string, len(recs))
		for j, r := range recs {
			got[j] = r.ID
		}
		assertIDs(t, i, "ListRecurrings", got, []string{"rec_a", "rec_b"})

		hws, err := m.ListHomeworks(ctx, center)
		if err != nil {
			t.Fatal(err)
		}
		got = make([]string, len(hws))
		for j, h := range hws {
			got[j] = h.ID
		}
		assertIDs(t, i, "ListHomeworks", got, []string{"hw_a", "hw_b", "hw_c"})

		pays, err := m.ListPayments(ctx, center)
		if err != nil {
			t.Fatal(err)
		}
		got = make([]string, len(pays))
		for j, p := range pays {
			got[j] = p.ID
		}
		assertIDs(t, i, "ListPayments", got, []string{"pay_a", "pay_b"})

		byMemberChecks, err := m.ListHwChecksByMember(ctx, center, "mem_1")
		if err != nil {
			t.Fatal(err)
		}
		assertIDs(t, i, "ListHwChecksByMember", checkDocIDs(byMemberChecks), wantChecks)

		allChecks, err := m.ListHwChecks(ctx, center)
		if err != nil {
			t.Fatal(err)
		}
		assertIDs(t, i, "ListHwChecks", checkDocIDs(allChecks), wantChecks)
	}
}

func passIDs(list []domain.Pass) []string {
	out := make([]string, len(list))
	for i, p := range list {
		out[i] = p.ID
	}
	return out
}

func checkDocIDs(list []domain.HwCheck) []string {
	out := make([]string, len(list))
	for i, c := range list {
		out[i] = hwCheckDocIDOf(c)
	}
	return out
}

func assertIDs(t *testing.T, round int, name string, got, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("%d회차 %s 건수 = %d, want %d (%v)", round, name, len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("%d회차 %s = %v, want %v — Firestore(문서 ID 오름차순)와 순서가 다르다", round, name, got, want)
		}
	}
}

// order.go 비교자의 동률 규칙(P76) — 입력을 여러 번 섞어도 같은 순서가 나와야 한다. 저장소 배선은
// conformance_test.go의 ListsTieBreakByDocID가 두 스토어로 잰다.
func TestTieBreakComparatorsAreDeterministic(t *testing.T) {
	at := time.Date(2026, 9, 1, 10, 0, 0, 0, time.UTC)
	rng := rand.New(rand.NewSource(76))
	shuffle := func(n int, swap func(i, j int)) { rng.Shuffle(n, swap) }
	join := func(ids ...string) string { return strings.Join(ids, " ") }

	for round := 0; round < 50; round++ {
		jr := []JoinRequest{{ID: "jreq_000001", CreatedAt: at}, {ID: "jreq_000003", CreatedAt: at},
			{ID: "jreq_000002", CreatedAt: at}, {ID: "jreq_000004", CreatedAt: at.Add(time.Microsecond)}}
		shuffle(len(jr), func(i, j int) { jr[i], jr[j] = jr[j], jr[i] })
		sortJoinRequestsNewest(jr)
		if got := join(jr[0].ID, jr[1].ID, jr[2].ID, jr[3].ID); got != "jreq_000004 jreq_000003 jreq_000002 jreq_000001" {
			t.Fatalf("가입 요청 = %s — 최신 먼저, 동률은 ID 내림차순(나중에 만든 것이 앞)", got)
		}

		led := []domain.Ledger{{ID: "l2", At: at}, {ID: "l1", At: at}, {ID: "l3", At: at.Add(-time.Second)}}
		shuffle(len(led), func(i, j int) { led[i], led[j] = led[j], led[i] })
		sortLedgerNewest(led)
		if got := join(led[0].ID, led[1].ID, led[2].ID); got != "l2 l1 l3" {
			t.Fatalf("원장 = %s", got)
		}

		ms := []domain.Member{{ID: "m3", Name: "김"}, {ID: "m1", Name: "김"}, {ID: "m2", Name: "가"}}
		shuffle(len(ms), func(i, j int) { ms[i], ms[j] = ms[j], ms[i] })
		sortMembersByName(ms)
		if got := join(ms[0].ID, ms[1].ID, ms[2].ID); got != "m2 m1 m3" {
			t.Fatalf("회원 = %s", got)
		}

		ss := []domain.Staff{{UID: "t2", Name: "박"}, {UID: "t1", Name: "박"}, {UID: "t0", Name: "최"}}
		shuffle(len(ss), func(i, j int) { ss[i], ss[j] = ss[j], ss[i] })
		sortStaffByName(ss)
		if got := join(ss[0].UID, ss[1].UID, ss[2].UID); got != "t1 t2 t0" {
			t.Fatalf("스태프 = %s", got)
		}

		bs := []domain.Booking{{ID: "b2", SlotKey: "20260901-10"}, {ID: "b1", SlotKey: "20260901-10"}, {ID: "b0", SlotKey: "20260901-11"}}
		shuffle(len(bs), func(i, j int) { bs[i], bs[j] = bs[j], bs[i] })
		sortBookingsBySlot(bs)
		if got := join(bs[0].ID, bs[1].ID, bs[2].ID); got != "b1 b2 b0" {
			t.Fatalf("예약 = %s", got)
		}

		ph := []domain.BodyPhoto{{ID: "p2", Date: "2026-09-01"}, {ID: "p1", Date: "2026-09-01"}, {ID: "p9", Date: "2026-08-31"}}
		shuffle(len(ph), func(i, j int) { ph[i], ph[j] = ph[j], ph[i] })
		sortBodyPhotos(ph)
		if got := join(ph[0].ID, ph[1].ID, ph[2].ID); got != "p1 p2 p9" {
			t.Fatalf("체형사진 = %s", got)
		}

		wl := []domain.WorkoutLog{{ID: "w2", Date: "2026-09-01"}, {ID: "w1", Date: "2026-09-01"}, {ID: "w9", Date: "2026-08-31"}}
		shuffle(len(wl), func(i, j int) { wl[i], wl[j] = wl[j], wl[i] })
		sortWorkoutLogs(wl)
		if got := join(wl[0].ID, wl[1].ID, wl[2].ID); got != "w1 w2 w9" {
			t.Fatalf("수업 기록 = %s", got)
		}
	}
}
