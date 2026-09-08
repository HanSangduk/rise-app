package store

// 두 구현(Memory·Firestore) **공통** 계약 테스트.
//
// 왜 필요한가: 이 프로젝트가 이미 한 번 겪은 사고의 형태가 "테스트는 전부 통과하는데 프로덕션만
// 터진다"였다(전화번호 정규화 — 회원 온보딩 100% 불능). 스토어가 둘인 한 그 사고는 언제든
// 재발한다 — 감사가 18개 프로브 중 13개에서 두 구현의 동작 차이를 실측했다(Update*(없는 ID)가
// Memory는 ErrNotFound, Firestore는 **유령 문서 생성** 등).
//
// 그래서 규칙을 문서가 아니라 **같은 테스트 함수**에 담는다. 기본 `go test`는 Memory로 돌고,
// `-tags firestore_emulator`를 주면 완전히 같은 함수가 에뮬레이터를 상대로 다시 돈다
// (firestore_conformance_test.go). 새 스토어 메서드를 추가할 때 여기에 한 줄 추가하면 두 구현이
// 함께 검증된다 — 드리프트를 막는 가장 값싼 자리다.
//
// 각 서브테스트는 **자기 이름에서 파생한 centerID**를 쓴다: 에뮬레이터는 컬렉션이 남으므로
// 서브테스트끼리 격리돼야 하고, Memory도 같은 규칙을 쓰면 두 실행이 대칭이 된다.

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// conformanceCenter — 서브테스트 이름에서 파생한 격리 센터 ID(문서 ID 금지문자는 docKey가 치환).
func conformanceCenter(t *testing.T) string {
	t.Helper()
	return "cf_" + docKey(strings.ReplaceAll(t.Name(), "/", "_"))
}

// runStoreConformance — 두 구현이 반드시 같은 답을 내야 하는 계약 전부.
func runStoreConformance(t *testing.T, newStore func(t *testing.T) Store) {
	t.Run("UpdateOnMissingIDIsNotFoundAndCreatesNoGhost", func(t *testing.T) {
		testUpdateMissingID(t, newStore(t))
	})
	t.Run("ReadWithEmptyIDIsNotFound", func(t *testing.T) {
		testEmptyIDReads(t, newStore(t))
	})
	t.Run("IssuePassIsAtomicAndLinksIDs", func(t *testing.T) {
		testIssuePass(t, newStore(t))
	})
	t.Run("UpdatePassWithLedgerRollsBackOnMutateError", func(t *testing.T) {
		testUpdatePassWithLedgerRollback(t, newStore(t))
	})
	t.Run("UpdatePassWithLedgerSeesFreshState", func(t *testing.T) {
		testUpdatePassWithLedgerFreshState(t, newStore(t))
	})
	t.Run("CancelAtomicCarriesPenaltyLedger", func(t *testing.T) {
		testCancelAtomicWithLedger(t, newStore(t))
	})
	t.Run("BookAtomicEnforcesPassBudget", func(t *testing.T) {
		testBookAtomicBudget(t, newStore(t))
	})
	t.Run("PassListOrderedByValidFrom", func(t *testing.T) {
		testPassOrdering(t, newStore(t))
	})
	t.Run("InbodyListOrderedByDateThenID", func(t *testing.T) {
		testInbodyOrdering(t, newStore(t))
	})
	t.Run("InbodyGetDeleteRoundTrip", func(t *testing.T) {
		testInbodyGetDelete(t, newStore(t))
	})
	t.Run("PurgeMemberDeletesHealthDataAndKeepsLedger", func(t *testing.T) {
		testPurgeMemberPersonalData(t, newStore(t))
	})
	t.Run("DeleteUserIndexIsIdempotent", func(t *testing.T) {
		testDeleteUserIndex(t, newStore(t))
	})
	t.Run("JoinRequestsDeletedByUID", func(t *testing.T) {
		testDeleteJoinRequestsByUID(t, newStore(t))
	})
	t.Run("JoinRequestsListedByUIDAcrossCenters", func(t *testing.T) {
		testListJoinRequestsByUID(t, newStore(t))
	})
	t.Run("BusinessAndPolicyDoNotClobberEachOther", func(t *testing.T) {
		testBusinessPolicyCoexist(t, newStore(t))
	})
	t.Run("FacilityRoundTripAndCoexist", func(t *testing.T) {
		testFacilityCoexist(t, newStore(t))
	})
	t.Run("PolicyHoursPromotedOnRead", func(t *testing.T) {
		testPolicyHoursPromotion(t, newStore(t))
	})
	t.Run("CheckinQRRoundTripAndCoexist", func(t *testing.T) {
		testCheckinQRCoexist(t, newStore(t))
	})
	t.Run("CenterIdentityRoundTripAndCoexist", func(t *testing.T) {
		testCenterIdentity(t, newStore(t))
	})
	t.Run("ConsultRequestQueueOrderAndScope", func(t *testing.T) {
		testConsultRequests(t, newStore(t))
	})
	t.Run("ConcurrentRefundOnlyOneWins", func(t *testing.T) {
		testConcurrentRefund(t, newStore(t))
	})
	t.Run("ConcurrentHoldsAllLand", func(t *testing.T) {
		testConcurrentHolds(t, newStore(t))
	})
	t.Run("ConcurrentBookingsRespectBudget", func(t *testing.T) {
		testConcurrentBookings(t, newStore(t))
	})
	t.Run("ContractTransitionValidatesOnFreshDoc", func(t *testing.T) {
		testContractTransitionFresh(t, newStore(t))
	})
	t.Run("ConcurrentSignAndResendKeepSignedEvidence", func(t *testing.T) {
		testConcurrentContractTransition(t, newStore(t))
	})
	t.Run("PassCloseVoidsContractsAtomically", func(t *testing.T) {
		testPassCloseWithContracts(t, newStore(t))
	})
	t.Run("ConcurrentGuardedContractCreateOnePerPass", func(t *testing.T) {
		testConcurrentContractCreate(t, newStore(t))
	})
}

// ---- 개별 계약 ----

// Update*(없는 ID)는 두 구현 모두 ErrNotFound여야 하고, **아무 문서도 만들지 않아야** 한다.
// Firestore의 Set은 upsert라 존재 확인을 선행하지 않으면 오타 ID 하나가 원장도 계약도 없는
// 유령 패스 / 소유자 없는 결제 문서를 만든다 — Memory에선 재현되지 않는 종류의 차이다.
func testUpdateMissingID(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	const ghost = "does_not_exist_xyz"

	for _, tc := range []struct {
		name   string
		update func(id string) error
		get    func(id string) error
	}{
		{"Pass",
			func(id string) error { return st.UpdatePass(ctx, center, &domain.Pass{ID: id, MemberID: "m1"}) },
			func(id string) error { _, err := st.GetPass(ctx, center, id); return err }},
		{"Payment",
			func(id string) error { return st.UpdatePayment(ctx, center, &domain.Payment{ID: id, MemberID: "m1"}) },
			func(id string) error { _, err := st.GetPayment(ctx, center, id); return err }},
		{"Contract",
			func(id string) error { return st.UpdateContract(ctx, center, &domain.Contract{ID: id, MemberID: "m1"}) },
			func(id string) error { _, err := st.GetContract(ctx, center, id); return err }},
		{"Recurring",
			func(id string) error {
				return st.UpdateRecurring(ctx, center, &domain.Recurring{ID: id, MemberID: "m1"})
			},
			func(id string) error { _, err := st.GetRecurring(ctx, center, id); return err }},
		{"JoinRequest",
			func(id string) error {
				return st.UpdateJoinRequest(ctx, &JoinRequest{ID: id, CenterID: center, Name: "x"})
			},
			func(id string) error { _, err := st.GetJoinRequest(ctx, id); return err }},
		{"PassWithLedger",
			func(id string) error {
				_, err := st.UpdatePassWithLedger(ctx, center, id, func(*domain.Pass, []domain.Ledger) (*domain.Ledger, error) {
					return nil, nil
				})
				return err
			},
			func(id string) error { _, err := st.GetPass(ctx, center, id); return err }},
		{"PassWithLedgerAndContracts",
			func(id string) error {
				_, err := st.UpdatePassWithLedgerAndContracts(ctx, center, id,
					func(*domain.Pass, []domain.Ledger) (*domain.Ledger, error) { return nil, nil }, nil, nil)
				return err
			},
			func(id string) error { _, err := st.GetPass(ctx, center, id); return err }},
		{"ContractTransition",
			func(id string) error {
				_, err := st.TransitionContract(ctx, center, id,
					func(*domain.Contract, *domain.Pass) error { return nil })
				return err
			},
			func(id string) error { _, err := st.GetContract(ctx, center, id); return err }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for _, id := range []string{ghost, ""} { // 없는 ID · 빈 ID 둘 다
				if err := tc.update(id); !errors.Is(err, ErrNotFound) {
					t.Fatalf("Update%s(id=%q) = %v, want ErrNotFound", tc.name, id, err)
				}
			}
			// 유령 문서 검사 — Firestore의 Set(upsert)이 문서를 만들어 놓지 않았는지.
			if err := tc.get(ghost); !errors.Is(err, ErrNotFound) {
				t.Fatalf("Update 실패 후에도 %s 문서가 존재한다(유령 문서): %v", tc.name, err)
			}
		})
	}

	// Delete 계열도 같은 규칙 — Firestore의 Delete는 없는 문서에도 성공을 돌려준다.
	// "지웠다"는 응답을 받고 화면에서 사라졌는데 실제 문서는 그대로인 상태를 만들지 않는다.
	if err := st.DeleteRecurring(ctx, center, ghost); !errors.Is(err, ErrNotFound) {
		t.Fatalf("DeleteRecurring(없는 ID) = %v, want ErrNotFound", err)
	}
	for _, id := range []string{ghost, ""} {
		if err := st.DeleteInbody(ctx, center, id); !errors.Is(err, ErrNotFound) {
			t.Fatalf("DeleteInbody(id=%q) = %v, want ErrNotFound", id, err)
		}
	}
}

// 빈 문서 ID 조회는 ErrNotFound(errors.go checkDocID의 규약). Firestore에서 Doc("")는
// InvalidArgument라 정규화하지 않으면 로컬 404 / 운영 500으로 갈린다.
func testEmptyIDReads(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	for name, get := range map[string]func() error{
		"GetPass":      func() error { _, err := st.GetPass(ctx, center, ""); return err },
		"GetBooking":   func() error { _, err := st.GetBooking(ctx, center, ""); return err },
		"GetPayment":   func() error { _, err := st.GetPayment(ctx, center, ""); return err },
		"GetContract":  func() error { _, err := st.GetContract(ctx, center, ""); return err },
		"GetRecurring": func() error { _, err := st.GetRecurring(ctx, center, ""); return err },
		"GetMember":    func() error { _, err := st.GetMember(ctx, center, ""); return err },
		"GetSlot":      func() error { _, err := st.GetSlot(ctx, center, ""); return err },
		"GetInbody":    func() error { _, err := st.GetInbody(ctx, center, ""); return err },
	} {
		if err := get(); !errors.Is(err, ErrNotFound) {
			t.Errorf("%s(\"\") = %v, want ErrNotFound", name, err)
		}
	}
}

// 발급 3단이 한 덩어리로 반영되고, 원장·계약이 **새로 만들어진 패스 ID**를 가리켜야 한다
// (호출측이 미리 채울 수 없는 값이라 스토어가 채운다).
func testIssuePass(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := &domain.Pass{MemberID: "m1", TrainerID: "t1", Product: "PT 20회",
		TotalSessions: 20, Remaining: 20, ValidFrom: "2026-01-01", ValidUntil: "2026-12-31",
		Status: domain.PassStatusActive, Holds: []domain.Hold{}}
	entry := &domain.Ledger{MemberID: "m1", Delta: 20, Reason: domain.ReasonIssue, By: "owner1"}
	contract := &domain.Contract{MemberID: "m1", Status: domain.ContractStatusSent}

	if err := st.IssuePass(ctx, center, pass, entry, contract); err != nil {
		t.Fatalf("IssuePass: %v", err)
	}
	if pass.ID == "" || entry.ID == "" || contract.ID == "" {
		t.Fatalf("ID 미채움: pass=%q entry=%q contract=%q", pass.ID, entry.ID, contract.ID)
	}
	if entry.PassID != pass.ID || contract.PassID != pass.ID {
		t.Fatalf("원장/계약이 새 패스를 가리키지 않는다: entry.pass=%q contract.pass=%q want %q",
			entry.PassID, contract.PassID, pass.ID)
	}
	if entry.At.IsZero() {
		t.Error("원장 At 미채움")
	}
	got, err := st.GetPass(ctx, center, pass.ID)
	if err != nil {
		t.Fatalf("GetPass: %v", err)
	}
	if got.TotalSessions != 20 {
		t.Errorf("저장된 패스 total = %d, want 20", got.TotalSessions)
	}
	ledger, err := st.ListLedger(ctx, center, "m1", pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(ledger) != 1 || ledger[0].Delta != 20 {
		t.Fatalf("원장 = %+v, want issue 1건(+20)", ledger)
	}
	cs, err := st.ListContracts(ctx, center, "m1", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(cs) != 1 || cs[0].PassID != pass.ID {
		t.Fatalf("계약 = %+v, want 1건(pass=%s)", cs, pass.ID)
	}
}

// mutate가 에러를 내면 **패스도 원장도** 그대로여야 한다(부분 반영 금지).
func testUpdatePassWithLedgerRollback(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := seedConformancePass(t, st, center, 10)

	boom := errors.New("mutate 실패")
	_, err := st.UpdatePassWithLedger(ctx, center, pass.ID,
		func(p *domain.Pass, _ []domain.Ledger) (*domain.Ledger, error) {
			p.Status = domain.PassStatusRefunded // 여기까지 바꿔 놓고 실패한다
			return &domain.Ledger{MemberID: p.MemberID, Delta: -10, Reason: domain.ReasonRefund}, boom
		})
	if !errors.Is(err, boom) {
		t.Fatalf("err = %v, want mutate 에러 그대로", err)
	}
	got, err := st.GetPass(ctx, center, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != domain.PassStatusActive {
		t.Errorf("롤백 후 status = %s, want active", got.Status)
	}
	ledger, err := st.ListLedger(ctx, center, pass.MemberID, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(ledger) != 1 { // issue 1건만
		t.Errorf("롤백 후 원장 %d건, want 1(issue만)", len(ledger))
	}
}

// mutate는 **저장본**과 **그 패스의 원장 전체**를 본다 — 이 두 입력이 트랜잭션 안에서 오는 것이
// 경합 방어의 전부다(호출측 스냅샷으로 판정하면 창이 닫히지 않는다).
func testUpdatePassWithLedgerFreshState(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := seedConformancePass(t, st, center, 10)

	if _, err := st.UpdatePassWithLedger(ctx, center, pass.ID,
		func(p *domain.Pass, _ []domain.Ledger) (*domain.Ledger, error) {
			p.Holds = append(p.Holds, domain.Hold{From: "2026-03-01", To: "2026-03-05"})
			return &domain.Ledger{MemberID: p.MemberID, Delta: 0, Reason: domain.ReasonHold}, nil
		}); err != nil {
		t.Fatal(err)
	}
	var sawHolds int
	var sawEntries int
	updated, err := st.UpdatePassWithLedger(ctx, center, pass.ID,
		func(p *domain.Pass, entries []domain.Ledger) (*domain.Ledger, error) {
			sawHolds = len(p.Holds)
			sawEntries = len(entries)
			if domain.Sum(entries) != 10 {
				return nil, fmt.Errorf("잔여 재계산 = %d, want 10", domain.Sum(entries))
			}
			p.Holds = append(p.Holds, domain.Hold{From: "2026-04-01", To: "2026-04-05"})
			return &domain.Ledger{MemberID: p.MemberID, Delta: 0, Reason: domain.ReasonHold}, nil
		})
	if err != nil {
		t.Fatal(err)
	}
	if sawHolds != 1 {
		t.Errorf("mutate가 본 holds = %d, want 1(직전 호출의 결과)", sawHolds)
	}
	if sawEntries != 2 { // issue + hold
		t.Errorf("mutate가 본 원장 = %d건, want 2", sawEntries)
	}
	if len(updated.Holds) != 2 {
		t.Errorf("반환 패스 holds = %d, want 2", len(updated.Holds))
	}
	saved, err := st.GetPass(ctx, center, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(saved.Holds) != 2 {
		t.Errorf("저장 패스 holds = %d, want 2 — 갱신이 서로를 덮었다", len(saved.Holds))
	}
}

// 인바디 목록은 **최신(date) 먼저, 동률이면 문서 ID 오름차순**이어야 한다(order.go sortInbody).
//
// 1차 키만 있던 종전 규칙의 문제: 같은 날짜 2건(v2.9의 중복 차단 이전에 저장된 데이터)의 상대
// 순서가 Memory에선 맵 순회라 **호출마다 뒤바뀌고** Firestore에선 문서 ID라 고정이었다. 인바디는
// 앱 기록 탭의 추이선과 "직전 대비 증감"의 입력이라 순서가 곧 화면이다 — 패스 목록에서 이미
// 같은 형태로 한 번 겪은 차이다(P13 M1).
func testInbodyOrdering(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	const member = "m_inbody_order"

	// 같은 날짜 3건 + 다른 날짜 2건. 삽입 순서를 일부러 뒤섞는다.
	for _, date := range []string{"2026-08-10", "2026-08-20", "2026-08-20", "2026-08-01", "2026-08-20"} {
		r := &domain.Inbody{MemberID: member, Date: date,
			Weight: 70, SMM: 32, BFM: 12, PBF: 18, VFL: 6, BMR: 1560,
			Source: domain.InbodySourceStaff}
		if _, err := st.CreateInbody(ctx, center, r); err != nil {
			t.Fatal(err)
		}
	}

	var first []string
	for call := range 10 {
		list, err := st.ListInbody(ctx, center, member)
		if err != nil {
			t.Fatal(err)
		}
		if len(list) != 5 {
			t.Fatalf("%d건, want 5건", len(list))
		}
		ids := make([]string, len(list))
		for i, r := range list {
			ids[i] = r.ID
			if i == 0 {
				continue
			}
			if list[i-1].Date < list[i].Date {
				t.Fatalf("최신 먼저가 깨졌다: %s → %s", list[i-1].Date, list[i].Date)
			}
			if list[i-1].Date == list[i].Date && list[i-1].ID > list[i].ID {
				t.Fatalf("동률(%s) 타이브레이커가 ID 오름차순이 아니다: %q → %q",
					list[i].Date, list[i-1].ID, list[i].ID)
			}
		}
		if call == 0 {
			first = ids
			continue
		}
		for i := range ids {
			if ids[i] != first[i] {
				t.Fatalf("호출 %d에서 순서가 달라졌다: %v vs %v", call, first, ids)
			}
		}
	}
}

// Get/Delete가 두 구현에서 같은 답을 내야 한다 — 인바디 정정의 **유일한** 경로라(PUT 없음)
// 여기가 갈리면 회원이 앱에서 지운 기록이 프로덕션에만 남거나 그 반대가 된다.
func testInbodyGetDelete(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	const member = "m_inbody_del"

	rec := &domain.Inbody{MemberID: member, Date: "2026-08-20",
		Weight: 70.5, SMM: 32.1, BFM: 12.8, PBF: 18.4, VFL: 6, BMR: 1560,
		Source: domain.InbodySourceMemberSelf}
	id, err := st.CreateInbody(ctx, center, rec)
	if err != nil {
		t.Fatal(err)
	}

	got, err := st.GetInbody(ctx, center, id)
	if err != nil {
		t.Fatalf("GetInbody: %v", err)
	}
	// source는 삭제 권한의 근거다 — 저장·재조회에서 살아남지 않으면 회원이 자기 기록도 못 지운다.
	if got.Source != domain.InbodySourceMemberSelf {
		t.Errorf("source = %q, want %q", got.Source, domain.InbodySourceMemberSelf)
	}
	if got.MemberID != member || got.Date != "2026-08-20" || got.BMR != 1560 {
		t.Errorf("라운드트립 불일치: %+v", got)
	}

	// 센터 격리 — 다른 센터에서 같은 ID로 읽거나 지울 수 없다.
	if _, err := st.GetInbody(ctx, center+"_other", id); !errors.Is(err, ErrNotFound) {
		t.Errorf("타 센터 GetInbody = %v, want ErrNotFound", err)
	}
	if err := st.DeleteInbody(ctx, center+"_other", id); !errors.Is(err, ErrNotFound) {
		t.Errorf("타 센터 DeleteInbody = %v, want ErrNotFound", err)
	}
	if _, err := st.GetInbody(ctx, center, id); err != nil {
		t.Fatalf("타 센터 삭제 시도 후 원본이 사라졌다: %v", err)
	}

	if err := st.DeleteInbody(ctx, center, id); err != nil {
		t.Fatalf("DeleteInbody: %v", err)
	}
	if _, err := st.GetInbody(ctx, center, id); !errors.Is(err, ErrNotFound) {
		t.Errorf("삭제 후 GetInbody = %v, want ErrNotFound", err)
	}
	list, err := st.ListInbody(ctx, center, member)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 0 {
		t.Errorf("삭제 후 목록에 %d건 남았다", len(list))
	}
	// 두 번째 삭제는 ErrNotFound(재시도가 "지웠다"를 두 번 보고하지 않는다).
	if err := st.DeleteInbody(ctx, center, id); !errors.Is(err, ErrNotFound) {
		t.Errorf("두 번째 DeleteInbody = %v, want ErrNotFound", err)
	}
}

// 회원탈퇴(v2.11) — 파기·보존 경계가 두 스토어에서 **글자 그대로 같아야** 한다.
//
// 이 자리가 특히 위험한 이유: Firestore 구현은 컬렉션 이름 문자열 6개를 손으로 적고, 이름이
// 하나라도 어긋나면 그 컬렉션만 **조용히 0건 삭제**로 지나간다(쿼리는 성공하고 결과만 비어
// 있어 에러조차 나지 않는다). Memory는 같은 맵을 훑으므로 그 오타가 재현되지 않는다 —
// 전화번호 정규화 사고(v1.7)와 정확히 같은 모양의 함정이다. 그래서 여섯 종류를 전부 심고
// 전부 0이 되는 것을 확인한다.
func testPurgeMemberPersonalData(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)

	mem := &domain.Member{
		Name: "김민지", Phone: "010-1234-5678", Channel: "인스타", TrainerID: "t1",
		Flags:     []domain.MemberFlag{{Type: domain.FlagInjury, Note: "어깨"}},
		Consent:   domain.Consent{General: true, Sensitive: true},
		AppLinked: true, Status: domain.MemberStatusActive,
	}
	memberID, err := st.SaveMember(ctx, center, mem)
	if err != nil {
		t.Fatalf("SaveMember: %v", err)
	}
	// 지워지면 **안 되는** 이웃 회원 — 필터가 member_id로 제대로 좁혀지는지 본다.
	other := &domain.Member{Name: "이서준", Phone: "010-9999-0000", Status: domain.MemberStatusActive}
	otherID, err := st.SaveMember(ctx, center, other)
	if err != nil {
		t.Fatalf("SaveMember(other): %v", err)
	}

	// ---- 파기 대상 6종 + 이웃 회원의 사본 ----
	for _, mid := range []string{memberID, otherID} {
		if _, err := st.CreateBodyPhoto(ctx, center, &domain.BodyPhoto{
			MemberID: mid, Pose: "stand", Direction: "front", Date: "2026-08-20",
			StoragePath: "members/" + mid + "/body/20260820-stand-front-1.jpg"}); err != nil {
			t.Fatalf("CreateBodyPhoto: %v", err)
		}
		if _, err := st.CreateInbody(ctx, center, &domain.Inbody{
			MemberID: mid, Date: "2026-08-20", Weight: 70.5, SMM: 32.1, BFM: 12.8,
			PBF: 18.4, VFL: 6, BMR: 1560}); err != nil {
			t.Fatalf("CreateInbody: %v", err)
		}
		if _, err := st.CreateWorkoutLog(ctx, center, &domain.WorkoutLog{
			MemberID: mid, TrainerID: "t1", Date: "2026-08-20", Title: "1:1 PT"}); err != nil {
			t.Fatalf("CreateWorkoutLog: %v", err)
		}
		if err := st.SaveHwCheck(ctx, center, &domain.HwCheck{
			MemberID: mid, HwID: "hw1", Date: "2026-08-20", Done: []bool{true}}); err != nil {
			t.Fatalf("SaveHwCheck: %v", err)
		}
		if err := st.SaveCheckinRecord(ctx, center, &CheckinRecord{
			BookingID: "bkg_" + mid, MemberID: mid, Source: "tap"}); err != nil {
			t.Fatalf("SaveCheckinRecord: %v", err)
		}
		if _, err := st.CreateRecurring(ctx, center, &domain.Recurring{
			MemberID: mid, TrainerID: "t1", Days: []string{"tue"}, Hour: 20,
			Until: "2026-12-31"}); err != nil {
			t.Fatalf("CreateRecurring: %v", err)
		}
		// 재등록/상담 요청(P53) — 회원이 남긴 자유 서술 메모. v2.11 스윕에 없던 7번째 종류라
		// 탈퇴가 성공을 보고하면서 이것만 남겼다(이번 결함).
		if _, err := st.CreateConsultRequest(ctx, center, &ConsultRequest{
			MemberID: mid, Kind: ConsultKindRenewal, Note: "무릎이 아파서 상담받고 싶어요",
			Status: ConsultPending}); err != nil {
			t.Fatalf("CreateConsultRequest: %v", err)
		}
	}

	// ---- 보존 대상: 원장 ----
	if _, err := st.AppendLedger(ctx, center, &domain.Ledger{
		PassID: "p1", MemberID: memberID, Delta: 20, Reason: domain.ReasonIssue,
		By: "owner1", At: time.Now().UTC()}); err != nil {
		t.Fatalf("AppendLedger: %v", err)
	}

	anon := mem.Anonymized(time.Date(2026, 8, 25, 5, 0, 0, 0, time.UTC))
	anon.ID = memberID
	counts, err := st.PurgeMemberPersonalData(ctx, center, &anon)
	if err != nil {
		t.Fatalf("PurgeMemberPersonalData: %v", err)
	}

	// JoinRequests가 0인 것은 정상이다 — 최상위 컬렉션이라 이 동사의 사정거리 밖이고,
	// DeleteJoinRequestsByUID가 따로 맡는다(testDeleteJoinRequestsByUID가 검증).
	want := PurgeCounts{
		BodyPhotos: 1, Inbody: 1, WorkoutLogs: 1, HwChecks: 1, Checkins: 1, Recurrings: 1,
		ConsultRequests: 1,
	}
	if counts != want {
		t.Errorf("PurgeCounts = %+v, want %+v — 0인 항목은 컬렉션 이름 오타를 의심하라", counts, want)
	}

	// ---- 실제로 사라졌는가(건수 보고를 믿지 않고 다시 읽는다) ----
	if photos, err := st.ListBodyPhotos(ctx, center, memberID); err != nil || len(photos) != 0 {
		t.Errorf("체형사진이 %d건 남았다(err=%v) — 민감정보는 보존 대상이 아니다", len(photos), err)
	}
	if rows, err := st.ListInbody(ctx, center, memberID); err != nil || len(rows) != 0 {
		t.Errorf("인바디가 %d건 남았다(err=%v)", len(rows), err)
	}
	if rows, err := st.ListWorkoutLogs(ctx, center, memberID); err != nil || len(rows) != 0 {
		t.Errorf("수업기록이 %d건 남았다(err=%v)", len(rows), err)
	}
	if rows, err := st.ListHwChecksByMember(ctx, center, memberID); err != nil || len(rows) != 0 {
		t.Errorf("홈워크 체크가 %d건 남았다(err=%v)", len(rows), err)
	}
	recurrings, err := st.ListRecurrings(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range recurrings {
		if r.MemberID == memberID {
			t.Errorf("고정 스케줄이 남았다: %+v", r)
		}
	}
	if rows, err := st.ListConsultRequests(ctx, center, memberID); err != nil || len(rows) != 0 {
		t.Errorf("재등록/상담 요청이 %d건 남았다(err=%v) — 회원이 남긴 메모는 거래 기록이 아니다", len(rows), err)
	}

	// ---- 이웃 회원은 온전한가 ----
	if photos, err := st.ListBodyPhotos(ctx, center, otherID); err != nil || len(photos) != 1 {
		t.Errorf("이웃 회원 체형사진 = %d건(err=%v), want 1 — 필터가 member_id로 좁혀지지 않았다", len(photos), err)
	}
	if rows, err := st.ListInbody(ctx, center, otherID); err != nil || len(rows) != 1 {
		t.Errorf("이웃 회원 인바디 = %d건(err=%v), want 1", len(rows), err)
	}
	if rows, err := st.ListWorkoutLogs(ctx, center, otherID); err != nil || len(rows) != 1 {
		t.Errorf("이웃 회원 수업기록 = %d건(err=%v), want 1", len(rows), err)
	}
	if rows, err := st.ListHwChecksByMember(ctx, center, otherID); err != nil || len(rows) != 1 {
		t.Errorf("이웃 회원 홈워크 체크 = %d건(err=%v), want 1", len(rows), err)
	}
	if rows, err := st.ListConsultRequests(ctx, center, otherID); err != nil || len(rows) != 1 {
		t.Errorf("이웃 회원 재등록/상담 요청 = %d건(err=%v), want 1 — 필터가 member_id로 좁혀지지 않았다", len(rows), err)
	}

	// ---- 원장은 그대로다(append-only 불변식 — 지우면 잔여 세션이 붕괴한다) ----
	entries, err := st.ListLedger(ctx, center, memberID, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || domain.Sum(entries) != 20 {
		t.Errorf("원장 = %d건 합계 %d, want 1건 합계 20 — 원장은 보존 대상이다", len(entries), domain.Sum(entries))
	}

	// ---- 회원 문서는 남되 비어 있다 ----
	got, err := st.GetMember(ctx, center, memberID)
	if err != nil {
		t.Fatalf("탈퇴 후 회원 문서를 읽을 수 없다: %v — 보존 기록의 조인 대상이 사라졌다", err)
	}
	if got.Name != domain.WithdrawnMemberName || got.Phone != "" || !got.IsWithdrawn() {
		t.Errorf("가명화가 저장되지 않았다: %+v", got)
	}
	// **번호 파기의 최종 확인**: 옛 번호로 다시 찾아지면 재가입이 탈퇴 레코드로 되돌아 붙는다.
	if found, err := st.FindMemberByPhone(ctx, center, "010-1234-5678"); err == nil {
		t.Errorf("탈퇴한 번호가 여전히 매칭된다: %+v — 재가입이 탈퇴를 무효화한다", found)
	}

	// ---- 없는 회원은 ErrNotFound(유령 문서를 만들지 않는다 — Firestore Set은 upsert다) ----
	ghost := domain.Member{ID: "no_such_member_xyz"}.Anonymized(time.Now().UTC())
	if _, err := st.PurgeMemberPersonalData(ctx, center, &ghost); !errors.Is(err, ErrNotFound) {
		t.Errorf("없는 회원 Purge = %v, want ErrNotFound", err)
	}
	if _, err := st.GetMember(ctx, center, "no_such_member_xyz"); !errors.Is(err, ErrNotFound) {
		t.Errorf("없는 회원 Purge가 유령 문서를 만들었다")
	}
}

// 가입 요청 파기(P53) — 탈퇴가 **이름·전화번호 원본**을 실제로 지우는지.
//
// 왜 별도 계약인가: join_requests는 최상위 컬렉션이고 member_id가 없다(uid 키). 두 구현이
// 다른 곳을 보기 가장 쉬운 자리다 — Memory는 맵 하나를 훑고 Firestore는 `uid ==` 쿼리를
// 날리는데, 그 필드명이 어긋나면 **쿼리는 성공하고 결과만 비어** 조용히 0건 삭제로 지나간다
// (PurgeMemberPersonalData의 컬렉션 이름 오타와 같은 종류의 함정).
// ListJoinRequestsByUID(v2.34) — 센터를 가로질러 그 사람의 요청만, 최신 먼저. 빈 uid는 빈 목록.
// GET /v1/me가 이 동사로 "내 요청은 지금 어떻게 됐나"를 답한다 — 2호점에 보낸 요청이 기본 센터
// 큐 조회에서 사라지던 결함(P69)의 스토어 쪽 방어선.
func testListJoinRequestsByUID(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	otherCenter := center + "-2"
	uid := "uid_" + docKey(t.Name())

	older := &JoinRequest{CenterID: center, UID: uid, Name: "김민지", Phone: "010-1234-5678", Status: JoinRejected,
		CreatedAt: time.Now().Add(-time.Hour)}
	newer := &JoinRequest{CenterID: otherCenter, UID: uid, Name: "김민지", Phone: "010-1234-5678", Status: JoinPending,
		CreatedAt: time.Now()}
	for _, jr := range []*JoinRequest{older, newer} {
		if _, err := st.CreateJoinRequest(ctx, jr); err != nil {
			t.Fatalf("CreateJoinRequest: %v", err)
		}
	}
	// 이웃 신청자·uid 빈 레거시 문서는 섞이면 안 된다.
	if _, err := st.CreateJoinRequest(ctx, &JoinRequest{CenterID: center, UID: uid + "_other", Name: "이서준", Phone: "010-9999-0000", Status: JoinPending}); err != nil {
		t.Fatal(err)
	}
	if _, err := st.CreateJoinRequest(ctx, &JoinRequest{CenterID: center, Name: "레거시", Phone: "010-0000-0000", Status: JoinPending}); err != nil {
		t.Fatal(err)
	}

	list, err := st.ListJoinRequestsByUID(ctx, uid)
	if err != nil {
		t.Fatalf("ListJoinRequestsByUID: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("건수 = %d, want 2(센터를 가로질러) — 0이면 uid 필드명을 의심하라: %+v", len(list), list)
	}
	if list[0].CenterID != otherCenter || list[0].Status != JoinPending {
		t.Errorf("첫 항목 = %+v, want 최신(다른 센터·pending) 먼저 — /v1/me는 첫 항목을 현재 상태로 읽는다", list[0])
	}
	if list[1].CenterID != center || list[1].Status != JoinRejected {
		t.Errorf("둘째 항목 = %+v, want 옛 거절 건", list[1])
	}
	if got, err := st.ListJoinRequestsByUID(ctx, ""); err != nil || len(got) != 0 {
		t.Errorf("빈 uid = (%d건, %v), want (0, nil) — uid 빈 레거시 문서를 남의 대기 상태로 돌려주면 안 된다", len(got), err)
	}
	if got, err := st.ListJoinRequestsByUID(ctx, uid+"_never"); err != nil || len(got) != 0 {
		t.Errorf("요청 없는 uid = (%d건, %v), want (0, nil)", len(got), err)
	}
}

func testDeleteJoinRequestsByUID(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	uid := "uid_" + docKey(t.Name())
	otherUID := uid + "_other"

	// 탈퇴자의 요청 2건(승인 대기 + 이미 거절된 것 — 상태와 무관하게 전부 파기 대상이다:
	// 거절된 요청도 이름·번호를 그대로 품는다).
	for _, status := range []string{JoinPending, JoinRejected} {
		if _, err := st.CreateJoinRequest(ctx, &JoinRequest{
			CenterID: center, UID: uid, Name: "김민지", Phone: "010-1234-5678", Status: status,
		}); err != nil {
			t.Fatalf("CreateJoinRequest(%s): %v", status, err)
		}
	}
	// 지워지면 **안 되는** 이웃 신청자.
	if _, err := st.CreateJoinRequest(ctx, &JoinRequest{
		CenterID: center, UID: otherUID, Name: "이서준", Phone: "010-9999-0000", Status: JoinPending,
	}); err != nil {
		t.Fatalf("CreateJoinRequest(other): %v", err)
	}
	// uid가 **빈** 레거시 문서 — 빈 uid 가드가 없으면 `uid == ""` 쿼리가 이걸 쓸어간다.
	if _, err := st.CreateJoinRequest(ctx, &JoinRequest{
		CenterID: center, Name: "레거시", Phone: "010-0000-0000", Status: JoinPending,
	}); err != nil {
		t.Fatalf("CreateJoinRequest(legacy): %v", err)
	}

	n, err := st.DeleteJoinRequestsByUID(ctx, uid)
	if err != nil {
		t.Fatalf("DeleteJoinRequestsByUID: %v", err)
	}
	if n != 2 {
		t.Errorf("삭제 건수 = %d, want 2 — 0이면 uid 필드명을 의심하라(쿼리는 성공하고 결과만 빈다)", n)
	}

	// 건수 보고를 믿지 않고 다시 읽는다.
	list, err := st.ListJoinRequests(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	remaining := 0
	for _, jr := range list {
		if jr.UID == uid {
			t.Errorf("탈퇴자의 가입 요청이 남았다: name=%q phone=%q — 승인 한 번으로 이름·번호가 되살아난다",
				jr.Name, jr.Phone)
		}
		if jr.UID == otherUID {
			remaining++
			if jr.Name != "이서준" || jr.Phone != "010-9999-0000" {
				t.Errorf("이웃 신청자의 요청이 훼손됐다: %+v", jr)
			}
		}
	}
	if remaining != 1 {
		t.Errorf("이웃 신청자 요청 = %d건, want 1 — 필터가 uid로 좁혀지지 않았다", remaining)
	}

	// **멱등**: 탈퇴 재시도가 여기서 막히면 이름·번호가 영구히 남는다(DeleteUserIndex와 같은 규약).
	if n, err := st.DeleteJoinRequestsByUID(ctx, uid); err != nil || n != 0 {
		t.Errorf("두 번째 호출 = (%d, %v), want (0, nil) — 재시도가 막히면 안 된다", n, err)
	}
	// 요청을 낸 적 없는 uid도 성공(0건).
	if n, err := st.DeleteJoinRequestsByUID(ctx, uid+"_never"); err != nil || n != 0 {
		t.Errorf("요청 없는 uid = (%d, %v), want (0, nil)", n, err)
	}
	// 빈 uid는 **아무것도 지우지 않는다** — 훑게 두면 uid가 빈 레거시 문서를 싹 쓸어간다
	// (Firestore의 `uid == ""`는 그 문서들에 실제로 매칭된다 — Memory만 보면 안 보이는 차이다).
	if n, err := st.DeleteJoinRequestsByUID(ctx, ""); err != nil || n != 0 {
		t.Errorf("빈 uid = (%d, %v), want (0, nil) — 남의 문서를 지우는 유일한 경로다", n, err)
	}
	after, err := st.ListJoinRequests(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if len(after) != 2 {
		t.Errorf("빈 uid 호출 후 요청 = %d건, want 2(이웃 + uid 빈 레거시)", len(after))
	}
	legacy := 0
	for _, jr := range after {
		if jr.UID == "" {
			legacy++
		}
	}
	if legacy != 1 {
		t.Errorf("uid가 빈 레거시 문서 = %d건, want 1 — 빈 uid 가드가 남의 문서를 쓸어갔다", legacy)
	}
}

// UserIndex 삭제는 **재시도 멱등**이다 — 탈퇴 절차의 마지막 단계라 두 번째 호출이 404로
// 막히면 인덱스가 영구히 남고, 그 인덱스 하나가 재로그인 시 옛 member_id를 복원한다.
func testDeleteUserIndex(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	uid := "uid_" + docKey(t.Name())

	if err := st.SaveUserIndex(ctx, &UserIndex{UID: uid, Role: domain.RoleMember, CenterID: center, MemberID: "m1"}); err != nil {
		t.Fatal(err)
	}
	if err := st.DeleteUserIndex(ctx, uid); err != nil {
		t.Fatalf("DeleteUserIndex: %v", err)
	}
	if _, err := st.GetUserIndex(ctx, uid); !errors.Is(err, ErrNotFound) {
		t.Errorf("삭제 후 GetUserIndex = %v, want ErrNotFound", err)
	}
	if err := st.DeleteUserIndex(ctx, uid); err != nil {
		t.Errorf("두 번째 DeleteUserIndex = %v, want nil(멱등 — 재시도가 막히면 안 된다)", err)
	}
}

// 취소 + 페널티 원장이 한 덩어리. 그리고 두 번째 취소는 ErrStateConflict(트랜잭션 내부 재검증).
func testCancelAtomicWithLedger(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := seedConformancePass(t, st, center, 10)
	b := &domain.Booking{SlotKey: "20260901-10", MemberID: pass.MemberID, TrainerID: "t1",
		PassID: pass.ID, Kind: domain.BookingKindPT, Status: domain.BookingConfirmed}
	if err := st.BookAtomic(ctx, center, b.SlotKey, 3, b); err != nil {
		t.Fatalf("BookAtomic: %v", err)
	}
	entry := &domain.Ledger{PassID: pass.ID, MemberID: pass.MemberID, Delta: -1,
		Reason: domain.ReasonNoshow, RefBookingID: b.ID, By: "owner1"}
	if err := st.CancelAtomic(ctx, center, b.ID, entry); err != nil {
		t.Fatalf("CancelAtomic: %v", err)
	}
	got, err := st.GetBooking(ctx, center, b.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != domain.BookingCancelled {
		t.Errorf("status = %s, want cancelled", got.Status)
	}
	ledger, err := st.ListLedger(ctx, center, pass.MemberID, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if domain.Sum(ledger) != 9 {
		t.Errorf("원장 합 = %d, want 9(발급 10 − 페널티 1)", domain.Sum(ledger))
	}
	// 재취소는 상태 충돌 — 재시도가 페널티를 두 번 물리지 않는다.
	if err := st.CancelAtomic(ctx, center, b.ID, entry); !errors.Is(err, ErrStateConflict) {
		t.Fatalf("두 번째 CancelAtomic = %v, want ErrStateConflict", err)
	}
	// 슬롯 teams에서도 빠졌는지.
	slot, err := st.GetSlot(ctx, center, b.SlotKey)
	if err != nil {
		t.Fatal(err)
	}
	for _, team := range slot.Teams {
		if team.BookingID == b.ID {
			t.Error("취소된 예약이 슬롯 teams에 남아 있다")
		}
	}
}

// 잔여 청구권(잔여 − 이미 잡힌 confirmed)이 트랜잭션 안에서 강제되는지. 순차 호출만으로도
// 종전 코드는 무제한이었다 — 경합이 아니라 검사 자체가 없었다.
func testBookAtomicBudget(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := seedConformancePass(t, st, center, 2)

	for i := range 2 {
		b := &domain.Booking{SlotKey: fmt.Sprintf("2026090%d-10", i+1), MemberID: pass.MemberID,
			TrainerID: "t1", PassID: pass.ID, Kind: domain.BookingKindPT, Status: domain.BookingConfirmed}
		if err := st.BookAtomic(ctx, center, b.SlotKey, 3, b); err != nil {
			t.Fatalf("%d번째 예약 실패: %v", i+1, err)
		}
	}
	third := &domain.Booking{SlotKey: "20260903-10", MemberID: pass.MemberID, TrainerID: "t1",
		PassID: pass.ID, Kind: domain.BookingKindPT, Status: domain.BookingConfirmed}
	if err := st.BookAtomic(ctx, center, third.SlotKey, 3, third); !errors.Is(err, domain.ErrNoSessionsLeft) {
		t.Fatalf("잔여 2회에 3번째 예약 = %v, want ErrNoSessionsLeft", err)
	}
	// 패스 문서가 없으면(픽스처·레거시) 검사를 건너뛴다 — 오늘까지의 동작 유지.
	orphan := &domain.Booking{SlotKey: "20260904-10", MemberID: "m_orphan", TrainerID: "t1",
		PassID: "pass_that_does_not_exist", Kind: domain.BookingKindPT, Status: domain.BookingConfirmed}
	if err := st.BookAtomic(ctx, center, orphan.SlotKey, 3, orphan); err != nil {
		t.Fatalf("패스 없는 예약이 막혔다: %v", err)
	}
	// 부수효과: remaining 저장 스냅샷이 원장 합으로 맞춰져 있어야 한다(M3).
	saved, err := st.GetPass(ctx, center, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Remaining != 2 {
		t.Errorf("remaining 스냅샷 = %d, want 2(원장 합)", saved.Remaining)
	}
}

// 회원권 목록은 valid_from 오름차순. Firestore의 무작위 문서 ID 순서와 Memory의 시퀀스 ID 순서가
// 여기서 같은 답으로 수렴해야 한다 — 앱의 기본 회원권 선택이 목록의 첫 active 패스이기 때문이다.
func testPassOrdering(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	// 일부러 시작일 역순으로 넣는다(삽입 순서 = ID 순서가 정답이 되지 않도록).
	for _, from := range []string{"2026-09-01", "2026-03-01", "2026-06-01"} {
		p := &domain.Pass{MemberID: "m1", TrainerID: "t1", TotalSessions: 10, Remaining: 10,
			ValidFrom: from, ValidUntil: "2027-12-31", Status: domain.PassStatusActive, Holds: []domain.Hold{}}
		if err := st.IssuePass(ctx, center, p, nil, nil); err != nil {
			t.Fatal(err)
		}
	}
	want := []string{"2026-03-01", "2026-06-01", "2026-09-01"}
	for range 5 { // 반복 — Memory의 맵 순회 비결정성이 드러나도록
		list, err := st.ListPassesByMember(ctx, center, "m1")
		if err != nil {
			t.Fatal(err)
		}
		if len(list) != 3 {
			t.Fatalf("패스 %d건, want 3", len(list))
		}
		for i, w := range want {
			if list[i].ValidFrom != w {
				t.Fatalf("ListPassesByMember 순서 = %s/%s/%s, want %v",
					list[0].ValidFrom, list[1].ValidFrom, list[2].ValidFrom, want)
			}
		}
	}
}

// C1 — 동시 환불 N건 중 **정확히 1건만** 성공해야 한다. 마감 판정(이미 refunded인가)이
// 트랜잭션 안에 있어야만 성립한다. Memory는 전역 락, Firestore는 OCC 재시도로 같은 답을 낸다.
func testConcurrentRefund(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := seedConformancePass(t, st, center, 10)

	const n = 4
	var wg sync.WaitGroup
	results := make([]error, n)
	for i := range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, results[i] = st.UpdatePassWithLedger(ctx, center, pass.ID,
				func(p *domain.Pass, entries []domain.Ledger) (*domain.Ledger, error) {
					if p.Status == domain.PassStatusRefunded {
						return nil, ErrStateConflict
					}
					remaining := domain.Sum(entries)
					p.Status = domain.PassStatusRefunded
					p.Remaining = 0
					if remaining == 0 {
						return nil, nil
					}
					return &domain.Ledger{MemberID: p.MemberID, Delta: -remaining,
						Reason: domain.ReasonRefund, By: "owner1"}, nil
				})
		}()
	}
	wg.Wait()

	ok := 0
	for i, err := range results {
		switch {
		case err == nil:
			ok++
		case errors.Is(err, ErrStateConflict):
		default:
			t.Errorf("%d번 환불 = %v, want nil 또는 ErrStateConflict", i, err)
		}
	}
	if ok != 1 {
		t.Errorf("성공한 환불 = %d건, want 정확히 1건(동시 환불 이중 지급)", ok)
	}
	ledger, err := st.ListLedger(ctx, center, pass.MemberID, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	refunds := 0
	for _, e := range ledger {
		if e.Reason == domain.ReasonRefund {
			refunds++
		}
	}
	if refunds != 1 {
		t.Errorf("refund 원장 = %d건, want 1", refunds)
	}
	if sum := domain.Sum(ledger); sum != 0 {
		t.Errorf("원장 합 = %d, want 0(음수면 이중 환불)", sum)
	}
}

// H2 — 겹치지 않는 홀딩 N건을 동시에 걸면 N건이 전부 남아야 한다. read-modify-write + 문서
// 통째 교체였을 때는 200 × 5인데 저장된 holds가 1건이었다(원장 hold는 5건 — 양쪽 말이 다 맞는 상태).
func testConcurrentHolds(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := seedConformancePass(t, st, center, 10)

	const n = 5
	var wg sync.WaitGroup
	errs := make([]error, n)
	for i := range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			h := domain.Hold{ // 겹치지 않는 5개월(02~06) 구간 — 서로를 덮으면 즉시 드러난다
				From:   fmt.Sprintf("2026-%02d-01", i+2),
				To:     fmt.Sprintf("2026-%02d-05", i+2),
				Reason: "동시 홀딩",
			}
			_, errs[i] = st.UpdatePassWithLedger(ctx, center, pass.ID,
				func(p *domain.Pass, _ []domain.Ledger) (*domain.Ledger, error) {
					for _, ex := range p.Holds {
						if ex.From == h.From && ex.To == h.To {
							return nil, ErrStateConflict
						}
					}
					newUntil, _, err := domain.ApplyHold(p.ValidUntil, h)
					if err != nil {
						return nil, err
					}
					p.Holds = append(p.Holds, h)
					p.ValidUntil = newUntil
					return &domain.Ledger{MemberID: p.MemberID, Delta: 0, Reason: domain.ReasonHold}, nil
				})
		}()
	}
	wg.Wait()
	for i, err := range errs {
		if err != nil {
			t.Fatalf("%d번 홀딩 실패: %v", i, err)
		}
	}
	saved, err := st.GetPass(ctx, center, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(saved.Holds) != n {
		t.Errorf("저장 holds = %d건, want %d — 동시 갱신이 서로를 덮었다", len(saved.Holds), n)
	}
	ledger, err := st.ListLedger(ctx, center, pass.MemberID, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	holdEntries := 0
	for _, e := range ledger {
		if e.Reason == domain.ReasonHold {
			holdEntries++
		}
	}
	if holdEntries != len(saved.Holds) {
		t.Errorf("원장 hold %d건 ≠ 패스 holds %d건 — 원장과 문서가 서로 다른 말을 한다",
			holdEntries, len(saved.Holds))
	}
}

// H1(경합판) — 잔여 2회 패스에 동시 예약 6건. 통과는 **잔여를 넘을 수 없다**가 안전 속성이고,
// 최소 1건은 통과해야 한다(살아있음). Memory는 전역 락이라 정확히 2건, Firestore는 OCC 재시도
// 소진으로 그보다 적을 수 있다 — 그래서 상한만 강하게 본다.
func testConcurrentBookings(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	const budget = 2
	pass := seedConformancePass(t, st, center, budget)

	const n = 6
	var wg sync.WaitGroup
	errs := make([]error, n)
	for i := range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			b := &domain.Booking{SlotKey: fmt.Sprintf("202609%02d-10", i+1), MemberID: pass.MemberID,
				TrainerID: "t1", PassID: pass.ID, Kind: domain.BookingKindPT, Status: domain.BookingConfirmed}
			errs[i] = st.BookAtomic(ctx, center, b.SlotKey, 3, b)
		}()
	}
	wg.Wait()

	ok := 0
	for _, err := range errs {
		if err == nil {
			ok++
		}
	}
	if ok > budget {
		t.Errorf("동시 예약 성공 = %d건, 잔여는 %d회 — 초과 예약이 통과했다", ok, budget)
	}
	if ok == 0 {
		t.Errorf("동시 예약이 전부 실패했다(errs=%v)", errs)
	}
	// 저장 상태로도 다시 확인한다(반환값만 보면 커밋되지 않은 성공을 놓친다).
	bookings, err := st.ListBookingsByMember(ctx, center, pass.MemberID)
	if err != nil {
		t.Fatal(err)
	}
	confirmed := 0
	for _, b := range bookings {
		if b.PassID == pass.ID && b.Status == domain.BookingConfirmed {
			confirmed++
		}
	}
	if confirmed > budget {
		t.Errorf("저장된 confirmed = %d건, 잔여는 %d회", confirmed, budget)
	}
}

// 전이 동사는 **저장본** 위에서 판정해야 한다(P37, 계약 v2.15) — 호출측 스냅샷으로 판정하면
// 재발송 vs 서명 경합이 signed를 sent 사본으로 덮는다(P36 감사 H). 에러 반환 시 롤백,
// 패스 동시 제공, 패스 없는 계약(레거시)의 nil까지 함께 고정한다.
func testContractTransitionFresh(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := seedConformancePass(t, st, center, 10)
	id, err := st.CreateContract(ctx, center, &domain.Contract{
		MemberID: pass.MemberID, PassID: pass.ID, Status: domain.ContractStatusSent})
	if err != nil {
		t.Fatal(err)
	}

	// ① mutate는 방금 읽은 계약 + 그 패스를 받는다.
	sawStatus, sawPass := "", ""
	updated, err := st.TransitionContract(ctx, center, id, func(c *domain.Contract, p *domain.Pass) error {
		sawStatus = c.Status
		if p != nil {
			sawPass = p.ID
		}
		now := time.Now().UTC()
		c.Status = domain.ContractStatusSigned
		c.SignedAt = &now
		c.SignerIP = "9.9.9.9"
		// v2.21(P44) 스팟체크: 자필 서명 2필드도 통문서 Set 왕복에서 무손실이어야 한다
		// (omitempty 금지 규약이 지키는 것 — 전이 재적용이 자리를 잃지 않는다).
		c.SignaturePNG = "aWNvbg=="
		c.SignatureSHA256 = "3333333333333333333333333333333333333333333333333333333333333333"
		return nil
	})
	if err != nil {
		t.Fatalf("TransitionContract: %v", err)
	}
	if sawStatus != domain.ContractStatusSent || sawPass != pass.ID {
		t.Errorf("mutate 입력 = (%s, pass %q), want (sent, %q)", sawStatus, sawPass, pass.ID)
	}
	if updated.Status != domain.ContractStatusSigned {
		t.Errorf("반환 계약 = %s, want signed", updated.Status)
	}
	if updated.SignaturePNG != "aWNvbg==" || updated.SignatureSHA256 == "" {
		t.Errorf("서명 2필드 왕복 실패: png=%q hash=%q (v2.21)", updated.SignaturePNG, updated.SignatureSHA256)
	}

	// ② 두 번째 호출은 **직전 커밋**(signed)을 봐야 하고, 에러 반환 시 아무것도 반영되지 않는다.
	boom := errors.New("전이 거부")
	_, err = st.TransitionContract(ctx, center, id, func(c *domain.Contract, _ *domain.Pass) error {
		if c.Status != domain.ContractStatusSigned {
			return fmt.Errorf("fresh가 아니라 스냅샷을 봤다: %s", c.Status)
		}
		c.Status = domain.ContractStatusVoided // 여기까지 바꿔 놓고 실패한다
		c.SignerIP = ""
		c.SignaturePNG = "" // 서명 이미지 증적도 롤백 보호 대상(v2.21)
		return boom
	})
	if !errors.Is(err, boom) {
		t.Fatalf("err = %v, want mutate 에러 그대로", err)
	}
	saved, err := st.GetContract(ctx, center, id)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusSigned || saved.SignedAt == nil || saved.SignerIP != "9.9.9.9" {
		t.Errorf("롤백 후 저장본 = %s(signed_at=%v, ip=%q) — 실패한 전이가 증적을 건드렸다",
			saved.Status, saved.SignedAt, saved.SignerIP)
	}
	if saved.SignaturePNG != "aWNvbg==" {
		t.Errorf("롤백 후 서명 이미지 = %q, want 유지 — 실패한 전이가 서명 증적을 지웠다(v2.21)", saved.SignaturePNG)
	}

	// ③ 패스 문서가 없는 계약(레거시)은 pass=nil — 판정은 계약만으로 진행돼야 한다.
	orphanID, err := st.CreateContract(ctx, center, &domain.Contract{
		MemberID: "m_orphan", PassID: "pass_never_created", Status: domain.ContractStatusDraft})
	if err != nil {
		t.Fatal(err)
	}
	sawNilPass := false
	if _, err := st.TransitionContract(ctx, center, orphanID, func(c *domain.Contract, p *domain.Pass) error {
		sawNilPass = p == nil
		c.Status = domain.ContractStatusSent
		return nil
	}); err != nil {
		t.Fatalf("패스 없는 계약 전이: %v", err)
	}
	if !sawNilPass {
		t.Error("없는 패스가 nil로 오지 않았다")
	}
}

// 서명 vs 재발송 N건 동시 — 최종 상태는 반드시 signed고 증적(signed_at·signer_ip)이 남아야
// 한다. 문서 통째 Set(UpdateContract)이었다면 늦게 커밋된 재발송 사본이 signed를 덮는다.
// Memory는 전역 락, Firestore는 OCC 재시도로 같은 답을 내야 한다(testConcurrentRefund와 같은 구도).
func testConcurrentContractTransition(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := seedConformancePass(t, st, center, 10)
	id, err := st.CreateContract(ctx, center, &domain.Contract{
		MemberID: pass.MemberID, PassID: pass.ID, Status: domain.ContractStatusSent})
	if err != nil {
		t.Fatal(err)
	}

	const resends = 3
	var wg sync.WaitGroup
	var signErr error
	resendErrs := make([]error, resends)
	wg.Add(1)
	go func() {
		defer wg.Done()
		_, signErr = st.TransitionContract(ctx, center, id, func(c *domain.Contract, _ *domain.Pass) error {
			if err := domain.CanTransitionContract(c.Status, domain.ContractStatusSigned); err != nil {
				return err
			}
			now := time.Now().UTC()
			c.Status = domain.ContractStatusSigned
			c.SignedAt = &now
			c.SignerIP = "1.2.3.4"
			return nil
		})
	}()
	for i := range resends {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, resendErrs[i] = st.TransitionContract(ctx, center, id, func(c *domain.Contract, _ *domain.Pass) error {
				if err := domain.CanTransitionContract(c.Status, domain.ContractStatusSent); err != nil {
					return err
				}
				now := time.Now().UTC()
				c.Status = domain.ContractStatusSent
				c.SentAt = &now
				return nil
			})
		}()
	}
	wg.Wait()

	if signErr != nil {
		t.Fatalf("서명 전이 = %v — sent→signed는 어느 순서에서도 유효해야 한다(재발송은 sent 유지)", signErr)
	}
	for i, err := range resendErrs {
		if err != nil && !errors.Is(err, domain.ErrInvalidContractTransition) {
			t.Errorf("%d번 재발송 = %v, want nil(서명 전) 또는 전이 위반(서명 후)", i, err)
		}
	}
	saved, err := st.GetContract(ctx, center, id)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusSigned || saved.SignedAt == nil || saved.SignerIP != "1.2.3.4" {
		t.Errorf("최종 저장본 = %s(signed_at=%v, ip=%q) — 재발송이 서명 증적을 덮었다",
			saved.Status, saved.SignedAt, saved.SignerIP)
	}
}

// 환불 마감 + 지목 계약 무효화가 **하나의 원자 단위**여야 한다(P37 — v2.6 남은 갭의 계약 절반).
// ① 스윕은 미서명만 voided로 바꾸고 signed는 스킵해 보존한다 ② 스윕 에러는 패스·원장까지
// 전부 롤백한다 ③ 없는 계약 ID는 ErrNotFound + 전무.
func testPassCloseWithContracts(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := seedConformancePass(t, st, center, 10)

	now := time.Now().UTC()
	mkContract := func(status string, signedAt *time.Time, ip string) string {
		t.Helper()
		cid, err := st.CreateContract(ctx, center, &domain.Contract{
			MemberID: pass.MemberID, PassID: pass.ID, Status: status, SignedAt: signedAt, SignerIP: ip})
		if err != nil {
			t.Fatal(err)
		}
		return cid
	}
	sentID := mkContract(domain.ContractStatusSent, nil, "")
	signedID := mkContract(domain.ContractStatusSigned, &now, "1.2.3.4")
	draftID := mkContract(domain.ContractStatusDraft, nil, "")

	closeMutate := func(p *domain.Pass, entries []domain.Ledger) (*domain.Ledger, error) {
		if p.Status == domain.PassStatusRefunded {
			return nil, ErrStateConflict
		}
		remaining := domain.Sum(entries)
		p.Status = domain.PassStatusRefunded
		p.Remaining = 0
		if remaining == 0 {
			return nil, nil
		}
		return &domain.Ledger{MemberID: p.MemberID, Delta: -remaining,
			Reason: domain.ReasonRefund, By: "owner1"}, nil
	}
	voidSweep := func(c *domain.Contract) (bool, error) {
		if !domain.CanVoidContract(c.Status) {
			return false, nil // signed는 성립했던 거래의 법적 기록 — 보존
		}
		c.Status = domain.ContractStatusVoided
		return true, nil
	}

	// ② 스윕 에러 → 전부 롤백(마감도 원장도 계약도).
	boom := errors.New("스윕 실패")
	if _, err := st.UpdatePassWithLedgerAndContracts(ctx, center, pass.ID, closeMutate,
		[]string{sentID, signedID, draftID},
		func(*domain.Contract) (bool, error) { return false, boom }); !errors.Is(err, boom) {
		t.Fatalf("스윕 에러 전파 = %v, want 스윕 에러 그대로", err)
	}
	if got, err := st.GetPass(ctx, center, pass.ID); err != nil || got.Status != domain.PassStatusActive {
		t.Fatalf("스윕 실패 후 패스 = %v/%s, want active(롤백)", err, got.Status)
	}
	if entries, err := st.ListLedger(ctx, center, pass.MemberID, pass.ID); err != nil || len(entries) != 1 {
		t.Fatalf("스윕 실패 후 원장 %d건(err=%v), want 1(issue만)", len(entries), err)
	}
	if got, err := st.GetContract(ctx, center, sentID); err != nil || got.Status != domain.ContractStatusSent {
		t.Fatalf("스윕 실패 후 sent 계약 = %v/%s, want sent(롤백)", err, got.Status)
	}

	// ③ 없는 계약 ID 지목 → ErrNotFound + 전무(계약은 삭제되지 않는 문서 — 조용한 스킵 금지).
	if _, err := st.UpdatePassWithLedgerAndContracts(ctx, center, pass.ID, closeMutate,
		[]string{sentID, "contract_never_created"}, voidSweep); !errors.Is(err, ErrNotFound) {
		t.Fatalf("없는 계약 지목 = %v, want ErrNotFound", err)
	}
	if got, err := st.GetPass(ctx, center, pass.ID); err != nil || got.Status != domain.PassStatusActive {
		t.Fatalf("없는 계약 지목 후 패스 = %v/%s, want active(전무)", err, got.Status)
	}

	// ① 정상 마감: 미서명 2건 voided · signed 보존 · 패스 refunded · 원장 마감 — 전부 한 번에.
	// sentID를 일부러 두 번 지목한다(P40 — P37 리뷰 권고): 중복 지목은 에러 없이 1회로 접혀야
	// 한다. Firestore가 같은 문서를 한 트랜잭션에서 두 번 쓰지 않게 하는 dedup 가드의 규약이다
	// (Memory는 맵 커밋이라 자연 흡수 — 두 구현이 같은 답을 내는지가 이 스위트의 존재 이유).
	updated, err := st.UpdatePassWithLedgerAndContracts(ctx, center, pass.ID, closeMutate,
		[]string{sentID, signedID, draftID, sentID}, voidSweep)
	if err != nil {
		t.Fatalf("마감: %v", err)
	}
	if updated.Status != domain.PassStatusRefunded {
		t.Errorf("반환 패스 = %s, want refunded", updated.Status)
	}
	for _, tc := range []struct{ id, want string }{
		{sentID, domain.ContractStatusVoided},
		{draftID, domain.ContractStatusVoided},
		{signedID, domain.ContractStatusSigned},
	} {
		got, err := st.GetContract(ctx, center, tc.id)
		if err != nil {
			t.Fatal(err)
		}
		if got.Status != tc.want {
			t.Errorf("계약 %s = %s, want %s", tc.id, got.Status, tc.want)
		}
	}
	if got, _ := st.GetContract(ctx, center, signedID); got.SignedAt == nil || got.SignerIP != "1.2.3.4" {
		t.Errorf("signed 계약의 증적이 훼손됐다: signed_at=%v ip=%q", got.SignedAt, got.SignerIP)
	}
	if entries, _ := st.ListLedger(ctx, center, pass.MemberID, pass.ID); domain.Sum(entries) != 0 {
		t.Errorf("마감 후 원장 합 = %d, want 0", domain.Sum(entries))
	}
}

// "패스당 유효(비voided) 계약 1건"(v1.5)이 생성과 **같은 트랜잭션**에서 판정돼야 동시 생성
// 2건이 나란히 통과하지 못한다(P36 감사 M2 — read-then-create). voided 잔존 계약은 분모가 아니다.
func testConcurrentContractCreate(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)
	pass := seedConformancePass(t, st, center, 10)
	// 무효화된 잔존 계약 — 이 1건이 생성을 막으면 안 된다.
	if _, err := st.CreateContract(ctx, center, &domain.Contract{
		MemberID: pass.MemberID, PassID: pass.ID, Status: domain.ContractStatusVoided}); err != nil {
		t.Fatal(err)
	}

	guard := func(existing []domain.Contract) error {
		for _, ec := range existing {
			if ec.PassID == pass.ID && ec.Status != domain.ContractStatusVoided {
				return ErrStateConflict
			}
		}
		return nil
	}
	const n = 4
	var wg sync.WaitGroup
	errs := make([]error, n)
	for i := range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, errs[i] = st.CreateContractGuarded(ctx, center, &domain.Contract{
				MemberID: pass.MemberID, PassID: pass.ID, Status: domain.ContractStatusDraft}, guard)
		}()
	}
	wg.Wait()

	ok := 0
	for i, err := range errs {
		switch {
		case err == nil:
			ok++
		case errors.Is(err, ErrStateConflict):
		default:
			t.Errorf("%d번 생성 = %v, want nil 또는 ErrStateConflict", i, err)
		}
	}
	if ok != 1 {
		t.Errorf("성공한 생성 = %d건, want 정확히 1건 — 유효 계약이 둘이면 위약금율 스냅샷 단일 가정(refundBasis)이 깨진다", ok)
	}
	cs, err := st.ListContracts(ctx, center, pass.MemberID, "")
	if err != nil {
		t.Fatal(err)
	}
	active := 0
	for _, c := range cs {
		if c.PassID == pass.ID && c.Status != domain.ContractStatusVoided {
			active++
		}
	}
	if active != 1 {
		t.Errorf("저장된 유효 계약 = %d건, want 1", active)
	}
}

// seedConformancePass — 발급된 패스 1건(원장 issue 포함).
func seedConformancePass(t *testing.T, st Store, center string, sessions int) *domain.Pass {
	t.Helper()
	p := &domain.Pass{MemberID: "m1", TrainerID: "t1", Product: "PT",
		PaidAmount: 1_000_000, TotalSessions: sessions, Remaining: sessions,
		ValidFrom: "2026-01-01", ValidUntil: "2026-12-31",
		Status: domain.PassStatusActive, Holds: []domain.Hold{}}
	e := &domain.Ledger{MemberID: "m1", Delta: sessions, Reason: domain.ReasonIssue,
		By: "owner1", At: time.Now().UTC()}
	if err := st.IssuePass(context.Background(), center, p, e, nil); err != nil {
		t.Fatalf("seed IssuePass: %v", err)
	}
	return p
}

// 정책과 사업자 정보는 **같은 센터 문서에 함께 산다**(v2.13). Firestore에서 둘 중 하나를
// 통 Set으로 쓰면 다른 하나가 조용히 사라진다 — 그 결과는 다음 배포도 아니고 **대표가 예약
// 용량 하나 바꾼 순간 법정 문서 5장이 동시에 초안으로 되돌아가는** 것으로 나타난다.
// Memory는 맵이 둘이라 이 결함이 재현되지 않는다: 에뮬레이터 러너에서만 실제로 잡히는
// 종류의 계약이라 여기(공통 스위트)에 둔다.
//
// 미등록 조회가 **문서를 만들지 않는다**는 규약도 함께 고정한다 — 이 값을 읽는 경로에
// 무인증 공개 엔드포인트가 있어서, 읽기가 쓰기를 유발하면 익명 요청으로 문서를 양산할 수 있다.
// testCenterIdentity — 센터 신원(멀티센터 Phase A): 미등록 빈 값 · 라운드트립 · 같은 문서에
// 동거하는 Policy/Business와의 3자 비덮어쓰기 · 유령 문서(정책만 시딩) 목록 제외.
func testCenterIdentity(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)

	// ① 미등록 조회: 빈 값(ID만) + ErrNotFound 아님 + 문서 생성 없음.
	empty, err := st.GetCenter(ctx, center)
	if err != nil {
		t.Fatalf("미등록 GetCenter: %v — 미등록은 오류가 아니다", err)
	}
	if empty.Name != "" || empty.ID != center {
		t.Fatalf("미등록 GetCenter = %+v, want 빈 값(ID=%s)", empty, center)
	}

	// ② 정책만 지연 시딩된 유령 센터는 목록에 오르지 않는다(헬스체크·GetPolicy 산물).
	if _, err := st.GetPolicy(ctx, center); err != nil {
		t.Fatal(err)
	}
	list, err := st.ListCenters(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range list {
		if c.ID == center {
			t.Fatalf("정책만 있는 유령 센터가 목록에 올랐다: %+v", c)
		}
	}

	// ③ 라운드트립 + 목록 포함.
	saved := &domain.Center{ID: center, Name: "테스트 2호점", Phone: "02-000-0000",
		Address: "서울", Status: domain.CenterStatusActive, CreatedAt: time.Now().UTC()}
	if err := st.SaveCenter(ctx, saved); err != nil {
		t.Fatal(err)
	}
	got, err := st.GetCenter(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "테스트 2호점" || got.ID != center {
		t.Fatalf("GetCenter = %+v, want 저장값", got)
	}
	list, err = st.ListCenters(ctx)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, c := range list {
		if c.ID == center && c.Name == "테스트 2호점" {
			found = true
		}
	}
	if !found {
		t.Fatalf("ListCenters에 저장한 센터가 없다: %+v", list)
	}

	// ④ 3자 비덮어쓰기 — Center·Policy·Business가 같은 문서에 동거한다.
	pol := domain.DefaultPolicy()
	pol.SlotCapacity = 5
	if err := st.SavePolicy(ctx, center, &pol); err != nil {
		t.Fatal(err)
	}
	if err := st.SaveBusiness(ctx, center, &domain.Business{BizName: "테스트상호"}); err != nil {
		t.Fatal(err)
	}
	got, err = st.GetCenter(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "테스트 2호점" {
		t.Fatalf("정책·사업자 저장 후 센터 신원 = %+v — 같은 문서의 다른 필드가 지워졌다", got)
	}
	// 반대 방향 — 센터 신원 재저장이 정책·사업자 정보를 지우면 안 된다.
	saved.Phone = "02-111-1111"
	if err := st.SaveCenter(ctx, saved); err != nil {
		t.Fatal(err)
	}
	polGot, err := st.GetPolicy(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if polGot.SlotCapacity != 5 {
		t.Fatalf("센터 신원 저장 후 정책 = %+v — SaveCenter가 정책을 지웠다", polGot)
	}
	bizGot, err := st.GetBusiness(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if bizGot.BizName != "테스트상호" {
		t.Fatalf("센터 신원 저장 후 사업자 정보 = %+v — SaveCenter가 business를 지웠다", bizGot)
	}
}

// testConsultRequests — 재등록/상담 요청(v2.20): 라운드트립 · 큐 정렬(오래된 순 → ID) ·
// 회원 필터 · 없는 ID 갱신 404.
func testConsultRequests(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)

	base := time.Date(2026, 8, 29, 10, 0, 0, 0, time.UTC)
	ids := make([]string, 3)
	for i, cr := range []ConsultRequest{
		{MemberID: "m1", Kind: ConsultKindRenewal, CreatedAt: base.Add(2 * time.Hour)},
		{MemberID: "m2", Kind: ConsultKindConsult, Note: "가격 문의", CreatedAt: base},
		{MemberID: "m1", Kind: ConsultKindRenewal, CreatedAt: base.Add(time.Hour)},
	} {
		c := cr
		id, err := st.CreateConsultRequest(ctx, center, &c)
		if err != nil {
			t.Fatal(err)
		}
		if c.Status != ConsultPending {
			t.Fatalf("기본 status = %q, want pending", c.Status)
		}
		ids[i] = id
	}

	// 큐 정렬 — 오래 기다린 요청이 위로.
	all, err := st.ListConsultRequests(ctx, center, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 3 || all[0].ID != ids[1] || all[1].ID != ids[2] || all[2].ID != ids[0] {
		t.Fatalf("정렬 = %+v, want 오래된 순(%s,%s,%s)", all, ids[1], ids[2], ids[0])
	}

	// 회원 필터.
	mine, err := st.ListConsultRequests(ctx, center, "m1")
	if err != nil {
		t.Fatal(err)
	}
	if len(mine) != 2 {
		t.Fatalf("m1 필터 = %d건, want 2", len(mine))
	}

	// 라운드트립 + done 갱신.
	got, err := st.GetConsultRequest(ctx, center, ids[1])
	if err != nil {
		t.Fatal(err)
	}
	if got.Note != "가격 문의" || got.Kind != ConsultKindConsult {
		t.Fatalf("GetConsultRequest = %+v", got)
	}
	got.Status = ConsultDone
	if err := st.UpdateConsultRequest(ctx, center, got); err != nil {
		t.Fatal(err)
	}
	after, err := st.GetConsultRequest(ctx, center, ids[1])
	if err != nil {
		t.Fatal(err)
	}
	if after.Status != ConsultDone {
		t.Fatalf("done 갱신 후 = %+v", after)
	}

	// 없는 ID 갱신은 404 — 유령을 만들지 않는다.
	if err := st.UpdateConsultRequest(ctx, center, &ConsultRequest{ID: "creq_missing"}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("없는 ID 갱신 = %v, want ErrNotFound", err)
	}
}

// 운영시간 승격(v2.24, P51) — **읽기 규약이 두 구현에서 같아야** 한다. 두 구현 모두
// GetPolicy에서 domain.Policy.Normalize()를 부르지만, 그 호출이 한쪽에서 빠지면 증상이
// 조용하다: Firestore를 쓰는 운영 센터만 open_hour=0·close_hour=0을 받아 어드민 시간
// 그리드가 통째로 비고, 로컬(인메모리)에서는 재현되지 않는다.
//
// 부재 판정이 **(0,0) 쌍**이라는 것도 여기서 잠근다 — 자정 개점(0,22)이 승격에 먹히면
// 24시간 헬스장의 여는 시각이 매 읽기마다 9시로 되돌아간다.
func testPolicyHoursPromotion(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)

	// ① 지연 시딩(문서 없음) → 기본값 9·21. 종전 하드코딩(09~21)과 같은 값이어야 한다.
	seeded, err := st.GetPolicy(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if seeded.OpenHour != 9 || seeded.CloseHour != 21 {
		t.Fatalf("최초 GetPolicy 운영시간 = %d~%d, want 9~21 — 기존 동작이 보존되지 않는다",
			seeded.OpenHour, seeded.CloseHour)
	}

	// ② v2.24 이전 문서(필드 부재 = 제로값) → 읽을 때 9·21로 승격. 마이그레이션 없이 동작해야 한다.
	legacy := domain.DefaultPolicy()
	legacy.OpenHour, legacy.CloseHour = 0, 0
	legacy.SlotCapacity = 4
	if err := st.SavePolicy(ctx, center, &legacy); err != nil {
		t.Fatal(err)
	}
	got, err := st.GetPolicy(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if got.OpenHour != 9 || got.CloseHour != 21 {
		t.Fatalf("구문서 운영시간 = %d~%d, want 9~21", got.OpenHour, got.CloseHour)
	}
	if got.SlotCapacity != 4 {
		t.Fatalf("승격이 이웃 필드를 건드렸다: %+v", got)
	}

	// ③ 자정 개점(0시)은 살아남는다 — 0을 **필드 단위** 부재로 읽었다면 여기서 9로 되돌아간다.
	midnight := domain.DefaultPolicy()
	midnight.OpenHour, midnight.CloseHour = 0, 22
	if err := st.SavePolicy(ctx, center, &midnight); err != nil {
		t.Fatal(err)
	}
	got, err = st.GetPolicy(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if got.OpenHour != 0 || got.CloseHour != 22 {
		t.Fatalf("자정 개점 왕복 = %d~%d, want 0~22 — 0시를 부재로 오독했다", got.OpenHour, got.CloseHour)
	}

	// ④ 일반 왕복 — 대표가 바꾼 값이 그대로 돌아온다.
	early := domain.DefaultPolicy()
	early.OpenHour, early.CloseHour = 6, 23
	if err := st.SavePolicy(ctx, center, &early); err != nil {
		t.Fatal(err)
	}
	got, err = st.GetPolicy(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if got.OpenHour != 6 || got.CloseHour != 23 {
		t.Fatalf("왕복 = %d~%d, want 6~23", got.OpenHour, got.CloseHour)
	}
}

func testBusinessPolicyCoexist(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)

	// ① 미등록 조회: 빈 값 + ErrNotFound 아님 + 문서 생성 없음.
	empty, err := st.GetBusiness(ctx, center)
	if err != nil {
		t.Fatalf("미등록 GetBusiness: %v — 미등록은 오류가 아니다", err)
	}
	if empty.IsComplete() || empty.BizName != "" {
		t.Fatalf("미등록 GetBusiness = %+v, want 빈 값", empty)
	}

	biz := &domain.Business{
		BizName: "라이즈 컨디셔닝", CeoName: "김대표", BizRegNo: "123-45-67890",
		Address: "서울특별시 강남구 테헤란로 123", Phone: "02-1234-5678", Email: "hello@rise.kr",
		PrivacyOfficerName: "김대표", PrivacyOfficerTitle: "대표", PrivacyOfficerEmail: "privacy@rise.kr",
		PrivacyDept: "고객지원팀", PrivacyManager: "박담당", EffectiveDate: "2026-09-01",
	}
	if err := st.SaveBusiness(ctx, center, biz); err != nil {
		t.Fatal(err)
	}

	// ② 정책 저장이 사업자 정보를 지우면 안 된다.
	pol := domain.DefaultPolicy()
	pol.SlotCapacity = 4
	if err := st.SavePolicy(ctx, center, &pol); err != nil {
		t.Fatal(err)
	}
	got, err := st.GetBusiness(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if !got.IsComplete() || got.BizName != "라이즈 컨디셔닝" {
		t.Fatalf("정책 저장 후 사업자 정보 = %+v — 통 Set이 같은 문서의 다른 필드를 지웠다", got)
	}

	// ③ 반대 방향 — 사업자 정보 저장이 정책을 지우면 안 된다.
	biz.CeoName = "이대표"
	if err := st.SaveBusiness(ctx, center, biz); err != nil {
		t.Fatal(err)
	}
	gotPol, err := st.GetPolicy(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if gotPol.SlotCapacity != 4 {
		t.Fatalf("사업자 정보 저장 후 정책 = %+v, want slot_capacity=4", gotPol)
	}

	// ④ 빈 칸으로 지우기가 저장에 반영된다(통 교체 시맨틱 — 오타를 지울 유일한 수단).
	if err := st.SaveBusiness(ctx, center, &domain.Business{BizName: "라이즈 컨디셔닝"}); err != nil {
		t.Fatal(err)
	}
	got, _ = st.GetBusiness(ctx, center)
	if got.CeoName != "" || got.Email != "" {
		t.Fatalf("빈 칸 저장이 반영되지 않았다: %+v — 잘못 적은 칸을 지울 방법이 없어진다", got)
	}
}

// 시설 신고 상태(P42) — centers 문서의 `facility` 절. testBusinessPolicyCoexist와 같은 형태:
// 미선언 기본값 / 왕복 / **동거 절 비덮어쓰기**(Policy·Business가 facility 저장에 살아남고,
// 그 반대도 성립) / 절 단위 통 교체(비워서 지우기).
func testFacilityCoexist(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)

	// ① 미선언 조회: unknown 기본값 + ErrNotFound 아님 + 문서 생성 없음(읽기 규약).
	empty, err := st.GetFacility(ctx, center)
	if err != nil {
		t.Fatalf("미선언 GetFacility: %v — 미선언은 오류가 아니다", err)
	}
	if empty.ReportStatus != domain.FacilityStatusUnknown || empty.ReportNo != "" || empty.Insurance != "" {
		t.Fatalf("미선언 GetFacility = %+v, want {unknown,\"\",\"\"}", empty)
	}
	if centers, err := st.ListCenters(ctx); err == nil {
		for _, c := range centers {
			if c.ID == center {
				t.Fatal("GetFacility가 센터 문서를 만들었다 — 읽기가 상태를 만들면 안 된다")
			}
		}
	}

	// ② 왕복 + 이웃 절 선등록.
	pol := domain.DefaultPolicy()
	pol.SlotCapacity = 4
	if err := st.SavePolicy(ctx, center, &pol); err != nil {
		t.Fatal(err)
	}
	if err := st.SaveBusiness(ctx, center, &domain.Business{BizName: "라이즈 컨디셔닝"}); err != nil {
		t.Fatal(err)
	}
	fac := &domain.Facility{
		ReportStatus: domain.FacilityStatusReported,
		ReportNo:     "제2026-강남-0001호",
		Insurance:    "서울보증 인허가보증보험(계약이행), 보장한도 1억원",
	}
	if err := st.SaveFacility(ctx, center, fac); err != nil {
		t.Fatal(err)
	}
	got, err := st.GetFacility(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if got.ReportStatus != domain.FacilityStatusReported || got.ReportNo != fac.ReportNo || got.Insurance != fac.Insurance {
		t.Fatalf("왕복 = %+v, want %+v", got, fac)
	}

	// ③ facility 저장이 동거 절(Policy·Business)을 지우면 안 된다 — P27 SavePolicy 교훈의
	// 세 번째 절 회귀. 통 Set이었다면 여기서 SlotCapacity=4·상호가 사라진다.
	gotPol, err := st.GetPolicy(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if gotPol.SlotCapacity != 4 {
		t.Fatalf("facility 저장 후 정책 = %+v, want slot_capacity=4 — 머지 쓰기가 아니다", gotPol)
	}
	gotBiz, err := st.GetBusiness(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if gotBiz.BizName != "라이즈 컨디셔닝" {
		t.Fatalf("facility 저장 후 사업자 정보 = %+v — 같은 문서의 다른 절이 지워졌다", gotBiz)
	}

	// ④ 반대 방향 — 정책·사업자 저장이 facility를 지우면 안 된다.
	pol.SlotCapacity = 5
	if err := st.SavePolicy(ctx, center, &pol); err != nil {
		t.Fatal(err)
	}
	if err := st.SaveBusiness(ctx, center, &domain.Business{BizName: "라이즈 컨디셔닝", CeoName: "김대표"}); err != nil {
		t.Fatal(err)
	}
	got, _ = st.GetFacility(ctx, center)
	if got.ReportStatus != domain.FacilityStatusReported || got.ReportNo == "" {
		t.Fatalf("정책·사업자 저장 후 facility = %+v — 신고 선언이 지워지면 스탬프가 조용히 꺼진다", got)
	}

	// ⑤ 절 단위 통 교체: exempt로 되돌리며 번호·보험을 비운 재제출이 그대로 반영돼야 한다
	// (toDoc이 빈 칸도 키로 포함 — 머지여도 절 안에서는 교체. 잘못 적은 선언을 지울 유일한 수단).
	if err := st.SaveFacility(ctx, center, &domain.Facility{ReportStatus: domain.FacilityStatusExempt}); err != nil {
		t.Fatal(err)
	}
	got, _ = st.GetFacility(ctx, center)
	if got.ReportStatus != domain.FacilityStatusExempt || got.ReportNo != "" || got.Insurance != "" {
		t.Fatalf("절 교체 = %+v, want {exempt,\"\",\"\"} — 이전 신고번호가 유령으로 남았다", got)
	}
}

// 데스크 체크인 QR 토큰(P49) — centers 문서의 `checkin_qr` 절. testFacilityCoexist와 같은
// 형태: 미발급 기본값 / 왕복 / **동거 절 비덮어쓰기** / 절 단위 통 교체(재발급).
//
// 이 절만 다른 점 하나: 여기 저장된 값은 **센터 비밀**이라, 두 구현이 어긋나면 증상이
// "체크인이 안 돼요"가 아니라 "Firestore에서만 옛 토큰이 계속 통한다"로 나타날 수 있다 —
// 재발급이 무효화에 실패하는 방향의 드리프트는 화면에 보이지 않는다.
func testCheckinQRCoexist(t *testing.T, st Store) {
	ctx := context.Background()
	center := conformanceCenter(t)

	// ① 미발급 조회: 빈 값 + ErrNotFound 아님 + **문서 생성 없음**.
	// 읽기가 문서를 만들면 회원의 체크인 시도가 곧 발급이 된다(인쇄하지 않은 QR이 유효해진다).
	empty, err := st.GetCheckinQR(ctx, center)
	if err != nil {
		t.Fatalf("미발급 GetCheckinQR: %v — 미발급은 오류가 아니다", err)
	}
	if empty.Issued() || empty.Token != "" || empty.IssuedAt != nil {
		t.Fatalf("미발급 GetCheckinQR = %+v, want {\"\",nil}", empty)
	}
	if centers, err := st.ListCenters(ctx); err == nil {
		for _, c := range centers {
			if c.ID == center {
				t.Fatal("GetCheckinQR가 센터 문서를 만들었다 — 읽기가 상태를 만들면 안 된다")
			}
		}
	}

	// ② 왕복 + 이웃 절 선등록.
	pol := domain.DefaultPolicy()
	pol.SlotCapacity = 4
	if err := st.SavePolicy(ctx, center, &pol); err != nil {
		t.Fatal(err)
	}
	if err := st.SaveBusiness(ctx, center, &domain.Business{BizName: "라이즈 컨디셔닝"}); err != nil {
		t.Fatal(err)
	}
	if err := st.SaveFacility(ctx, center, &domain.Facility{
		ReportStatus: domain.FacilityStatusReported, ReportNo: "제2026-강남-0001호",
	}); err != nil {
		t.Fatal(err)
	}
	first, err := domain.NewCheckinQRToken()
	if err != nil {
		t.Fatal(err)
	}
	issuedAt := time.Now().UTC().Truncate(time.Second) // Firestore 타임스탬프 해상도에 맞춘 비교 기준
	if err := st.SaveCheckinQR(ctx, center, &domain.CheckinQR{Token: first, IssuedAt: &issuedAt}); err != nil {
		t.Fatal(err)
	}
	got, err := st.GetCheckinQR(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if got.Token != first {
		t.Fatalf("왕복 토큰 = %q, want %q", got.Token, first)
	}
	if got.IssuedAt == nil || !got.IssuedAt.Equal(issuedAt) {
		t.Fatalf("왕복 issued_at = %v, want %v — 어드민이 발급 시각을 못 읽는다", got.IssuedAt, issuedAt)
	}

	// ③ 토큰 저장이 동거 절(Policy·Business·Facility)을 지우면 안 된다 — P27 교훈의 네 번째 절.
	gotPol, err := st.GetPolicy(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if gotPol.SlotCapacity != 4 {
		t.Fatalf("토큰 저장 후 정책 = %+v, want slot_capacity=4 — 머지 쓰기가 아니다", gotPol)
	}
	gotBiz, err := st.GetBusiness(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if gotBiz.BizName != "라이즈 컨디셔닝" {
		t.Fatalf("토큰 저장 후 사업자 정보 = %+v — 같은 문서의 다른 절이 지워졌다", gotBiz)
	}
	gotFac, err := st.GetFacility(ctx, center)
	if err != nil {
		t.Fatal(err)
	}
	if gotFac.ReportStatus != domain.FacilityStatusReported {
		t.Fatalf("토큰 저장 후 facility = %+v — 신고 선언이 지워졌다", gotFac)
	}

	// ④ 반대 방향 — 이웃 절 저장이 토큰을 지우면 데스크 QR이 조용히 죽는다(증상은 "체크인이
	// 안 돼요"뿐이라 원인에 도달하지 못한다).
	pol.SlotCapacity = 5
	if err := st.SavePolicy(ctx, center, &pol); err != nil {
		t.Fatal(err)
	}
	if err := st.SaveBusiness(ctx, center, &domain.Business{BizName: "라이즈 컨디셔닝", CeoName: "김대표"}); err != nil {
		t.Fatal(err)
	}
	if err := st.SaveFacility(ctx, center, &domain.Facility{ReportStatus: domain.FacilityStatusExempt}); err != nil {
		t.Fatal(err)
	}
	got, _ = st.GetCheckinQR(ctx, center)
	if got.Token != first {
		t.Fatalf("이웃 절 저장 후 토큰 = %q, want %q — 데스크 QR이 지워졌다", got.Token, first)
	}

	// ⑤ 절 단위 통 교체(재발급): 이전 토큰이 유령으로 남으면 옛 인쇄물이 계속 통과해
	// "재발급하면 무효"라는 약속이 두 구현 중 한쪽에서만 거짓이 된다.
	second, err := domain.NewCheckinQRToken()
	if err != nil {
		t.Fatal(err)
	}
	if second == first {
		t.Fatal("난수 토큰이 중복 — 난수원이 죽었다")
	}
	rotatedAt := issuedAt.Add(time.Hour)
	if err := st.SaveCheckinQR(ctx, center, &domain.CheckinQR{Token: second, IssuedAt: &rotatedAt}); err != nil {
		t.Fatal(err)
	}
	got, _ = st.GetCheckinQR(ctx, center)
	if got.Token != second {
		t.Fatalf("재발급 후 = %q, want %q — 이전 토큰이 남았다", got.Token, second)
	}
	if got.IssuedAt == nil || !got.IssuedAt.Equal(rotatedAt) {
		t.Fatalf("재발급 issued_at = %v, want %v", got.IssuedAt, rotatedAt)
	}
}

// ---- Memory 러너(기본 `go test`에 포함) ----

func TestMemoryStoreConformance(t *testing.T) {
	runStoreConformance(t, func(*testing.T) Store { return NewMemory() })
}
