package api

// 쓰기 경로 담당 경계 회귀(P12 감사). 읽기 계열은 memberScopeID·checkMemberScope로 촘촘한데
// **쓰기 4곳**(수업기록 생성·홈워크 배정·홈워크 체크·tap 체크인)이 스코프를 보지 않아,
// 담당이 아닌 코치가 남의 회원 데이터를 만들 수 있었다(전부 curl 실측 재현).
//
// 네 테스트는 같은 모양이다: **담당 아닌 코치(t2)가 t1의 회원을 건드린다 → 403**.
// 정상 경로(담당 코치 본인·대표 대행)는 함께 열려 있는지 확인해 과잉 차단을 막는다.

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// outsiderTrainerP — 시딩 픽스처의 담당(t1)이 아닌 다른 코치. 경계 밖 호출자 역할.
func outsiderTrainerP() Principal {
	return Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}
}

// todayKST — 앱이 보내는 날짜와 같은 형식·같은 기준(센터 타임존).
func todayKST() string { return time.Now().In(domain.KST).Format("2006-01-02") }

// H1 회귀: booking_id 없는 수업기록에 담당 경계가 없었다.
//
// 실측(DEV_SEED): t2가 t1 담당 회원에게 booking_id 없이 POST /v1/workout-logs → 200.
// booking_id를 생략하면 아래 교차검증(회원·담당 일치)이 통째로 건너뛰어져, 회원 앱의
// "수업 기록" 탭에 한 번도 본 적 없는 코치의 기록이 뜬다.
func TestWorkoutLogWithoutBookingRequiresMemberScope(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 20) // 담당 t1
	seedTrainerRecord(t, s, "t2", "김태오")

	if _, err := s.CreateWorkoutLog(ctx, outsiderTrainerP(), WorkoutLogCreateRequest{
		MemberID: mem.ID, Title: "1:1 PT",
	}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("타 코치의 수업기록 생성 = %v, want ErrForbidden", err)
	}
	// 403인데 저장돼 있으면 회원 앱엔 그대로 뜬다 — 거부가 곧 미저장인지 확인한다.
	logs, err := s.ListWorkoutLogs(ctx, ownerP(), mem.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(logs) != 0 {
		t.Fatalf("거부된 요청이 저장됨: %+v", logs)
	}

	// 정상 경로는 열려 있어야 한다 — 담당 코치 본인, 대표 대행.
	if _, err := s.CreateWorkoutLog(ctx, trainerP(), WorkoutLogCreateRequest{MemberID: mem.ID}); err != nil {
		t.Fatalf("담당 코치 수업기록 실패: %v", err)
	}
	if _, err := s.CreateWorkoutLog(ctx, ownerP(), WorkoutLogCreateRequest{
		MemberID: mem.ID, TrainerID: "t1",
	}); err != nil {
		t.Fatalf("대표 대행 수업기록 실패: %v", err)
	}

	// 담당이 아니어도 **자기 예약**에 연결된 기록은 남길 수 있어야 한다: 회원은 코치별로 패스를
	// 따로 가질 수 있고(앱 패스 스위처), 그때 mem.trainer_id(주담당)와 그 회차를 실제로 가르친
	// 코치가 다르다. 경계를 필요 이상으로 좁히지 않았는지 함께 못박는다.
	kst := time.Now().In(domain.KST)
	p2, err := s.CreatePass(ctx, ownerP(), PassCreateRequest{
		MemberID: mem.ID, TrainerID: "t2", Product: "PT 10회",
		PaidAmount: 500_000, TotalSessions: 10,
		ValidFrom:  kst.AddDate(0, 0, -1).Format("2006-01-02"),
		ValidUntil: kst.AddDate(0, 0, 90).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatal(err)
	}
	b2, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(3, 11), MemberID: mem.ID, PassID: p2.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateWorkoutLog(ctx, outsiderTrainerP(), WorkoutLogCreateRequest{
		MemberID: mem.ID, BookingID: b2.ID,
	}); err != nil {
		t.Fatalf("자기 예약에 연결한 기록이 거부됨: %v", err)
	}
}

// H2 회귀: target_member_ids 무검증 → 담당 경계 + 부상 자동제외가 **동시에** 뚫렸다.
//
// 실측: t2가 scope="my_members", target_member_ids=[t1 담당 부상회원] → 200에 excluded:null.
// 후보는 요청 배열 그대로 쓰면서 부상 맵은 pool(ListMembers(내 담당))로만 만들어, pool 밖
// 회원은 부상 플래그가 있어도 탐지되지 않았다 — P39가 막으려던 "부상 회원에게 금기 운동 배정".
func TestHomeworkTargetsStayInScopeAndKeepInjuryExclusion(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mine, _ := seedMemberWithPass(t, s, 20) // 담당 t1
	seedTrainerRecord(t, s, "t2", "김태오")

	injured, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "부상회원", Phone: "010-7777-8888", TrainerID: "t1", Status: domain.MemberStatusActive,
		Flags: []domain.MemberFlag{{Type: domain.FlagInjury, Note: "어깨 회전근개 — 오버헤드 주의"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	theirs, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "태오회원", Phone: "010-5555-6666", TrainerID: "t2", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	overhead := []domain.HwItem{{Name: "오버헤드 프레스", Sets: 3, Reps: "12"}}
	weekly := domain.HwSchedule{Type: "weekly", Days: []string{"mon", "wed", "fri"}}

	// ① my_members + subset: 내 담당(pool) 밖 회원을 실으면 403.
	if _, err := s.CreateHomework(ctx, outsiderTrainerP(), HomeworkCreateRequest{
		Scope: domain.HwScopeMyMembers, TargetMemberIDs: []string{injured.ID},
		Items: overhead, Schedule: weekly,
	}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("타 코치 회원에 my_members 배정 = %v, want ErrForbidden", err)
	}
	// ② individual도 같은 경계다(부상 필터는 원래 안 걸지만, 담당 경계는 걸려야 한다).
	if _, err := s.CreateHomework(ctx, outsiderTrainerP(), HomeworkCreateRequest{
		Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{injured.ID},
		Items: overhead, Schedule: weekly,
	}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("타 코치 회원에 individual 배정 = %v, want ErrForbidden", err)
	}
	// ③ 대표 대행도 "그 코치의 담당"으로 좁혀진다 — subset이 pool과 어긋나면 부상 맵도 어긋난다.
	if _, err := s.CreateHomework(ctx, ownerP(), HomeworkCreateRequest{
		TrainerID: "t2", Scope: domain.HwScopeMyMembers, TargetMemberIDs: []string{injured.ID},
		Items: overhead, Schedule: weekly,
	}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("대표 대행 my_members가 타 코치 담당을 넘음 = %v, want ErrForbidden", err)
	}
	// ④ 없는 회원 ID는 고아 배정이 된다 → 404.
	if _, err := s.CreateHomework(ctx, trainerP(), HomeworkCreateRequest{
		Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{"does-not-exist"},
		Items: overhead, Schedule: weekly,
	}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("미존재 회원 배정 = %v, want store.ErrNotFound", err)
	}

	// ⑤ subset 경로에서도 부상 자동제외가 살아있다(후보와 부상 맵이 같은 집합에서 나와야 한다).
	hw, err := s.CreateHomework(ctx, trainerP(), HomeworkCreateRequest{
		Scope: domain.HwScopeMyMembers, TargetMemberIDs: []string{mine.ID, injured.ID},
		Items: overhead, Schedule: weekly,
	})
	if err != nil {
		t.Fatalf("담당 회원 subset 배정 실패: %v", err)
	}
	if !containsStr(hw.Excluded, injured.ID) {
		t.Errorf("부상 회원이 excluded에 없음: %+v", hw)
	}
	if containsStr(hw.TargetMemberIDs, injured.ID) {
		t.Errorf("부상 회원에게 금기 운동이 배정됨: %+v", hw)
	}
	if !containsStr(hw.TargetMemberIDs, mine.ID) {
		t.Errorf("정상 회원이 배정에서 빠짐: %+v", hw)
	}

	// ⑥ 수동 포함(include) 예외는 그대로 동작해야 한다 — 코치의 명시적 판단은 뒤집지 않는다.
	hw2, err := s.CreateHomework(ctx, trainerP(), HomeworkCreateRequest{
		Scope: domain.HwScopeMyMembers, TargetMemberIDs: []string{injured.ID},
		Include: []string{injured.ID}, Items: overhead, Schedule: weekly,
	})
	if err != nil {
		t.Fatalf("include 예외 배정 실패: %v", err)
	}
	if !containsStr(hw2.TargetMemberIDs, injured.ID) || len(hw2.Excluded) != 0 {
		t.Errorf("include 예외가 무시됨: %+v", hw2)
	}

	// ⑦ 자기 담당 회원 배정은 정상(과잉 차단 방지).
	if _, err := s.CreateHomework(ctx, outsiderTrainerP(), HomeworkCreateRequest{
		Scope: domain.HwScopeMyMembers, TargetMemberIDs: []string{theirs.ID},
		Items: overhead, Schedule: weekly,
	}); err != nil {
		t.Fatalf("자기 담당 회원 배정 실패: %v", err)
	}
}

// H3 회귀: 체크 생성에 검증이 하나도 없었다(hw 실존·대상 여부·날짜·done 길이 전부).
//
// 실측: hw_id="does-not-exist" → 200. date 생략 → 200에 date:"" — 앱의 ?date=오늘 질의에
// 안 잡혀 체크가 풀린 것처럼 보이는데, 통계 homeworkCompletion은 날짜를 안 보고 anyDone만
// 세서 "완료"로 잡는다. 화면과 지표가 정반대로 어긋났다.
func TestHwCheckValidatesHomeworkAndScope(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mine, _ := seedMemberWithPass(t, s, 20) // 담당 t1
	seedTrainerRecord(t, s, "t2", "김태오")
	stranger, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "태오회원", Phone: "010-5555-6666", TrainerID: "t2", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	hw, err := s.CreateHomework(ctx, trainerP(), HomeworkCreateRequest{
		Scope: domain.HwScopeMyMembers, TargetMemberIDs: []string{mine.ID},
		Items:    []domain.HwItem{{Name: "스쿼트", Sets: 3, Reps: "15"}, {Name: "플랭크", Sets: 3, Reps: "30초"}},
		Schedule: domain.HwSchedule{Type: "weekly", Days: []string{"mon", "wed", "fri"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	day := todayKST()

	// ① 없는 배정 → 404(주인 없는 체크가 쌓이던 자리).
	if _, err := s.CreateHwCheck(ctx, memberP(mine.ID), HwCheckRequest{
		HwID: "does-not-exist", Date: day, Done: []bool{true, false},
	}); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("미존재 hw_id 체크 = %v, want store.ErrNotFound", err)
	}
	// ② 타 코치의 대행 입력 → 403(남의 담당 회원 완료율 조작).
	if _, err := s.CreateHwCheck(ctx, outsiderTrainerP(), HwCheckRequest{
		MemberID: mine.ID, HwID: hw.ID, Date: day, Done: []bool{true, true},
	}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("타 코치 대행 체크 = %v, want ErrForbidden", err)
	}
	// ③ 배정 대상이 아닌 회원 본인의 체크 → 403(hw_id만 알면 남의 배정에 기록이 붙었다).
	if _, err := s.CreateHwCheck(ctx, memberP(stranger.ID), HwCheckRequest{
		HwID: hw.ID, Date: day, Done: []bool{true, true},
	}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("비대상 회원 체크 = %v, want ErrForbidden", err)
	}
	// ④ done 길이가 항목 수와 다르면 400 — 인덱스가 밀려 다른 운동이 완료로 표시된다.
	if _, err := s.CreateHwCheck(ctx, memberP(mine.ID), HwCheckRequest{
		HwID: hw.ID, Date: day, Done: []bool{true},
	}); !errors.Is(err, errBadRequest) {
		t.Fatalf("done 길이 불일치 = %v, want errBadRequest", err)
	}
	// ⑤ 날짜 형식 불량 → 400(문자열 비교 필터가 조용히 오염된다 — 수업기록과 같은 규칙).
	if _, err := s.CreateHwCheck(ctx, memberP(mine.ID), HwCheckRequest{
		HwID: hw.ID, Date: "2026-8-2", Done: []bool{true, false},
	}); !errors.Is(err, errBadRequest) {
		t.Fatalf("비정규 date = %v, want errBadRequest", err)
	}
	// ⑥ date 생략 → 서버가 오늘(KST)로 채우고, **앱과 같은 질의로 되짚었을 때 잡혀야** 한다.
	c, err := s.CreateHwCheck(ctx, memberP(mine.ID), HwCheckRequest{
		HwID: hw.ID, Done: []bool{true, false},
	})
	if err != nil {
		t.Fatalf("date 생략 체크 실패: %v", err)
	}
	if c.Date != day {
		t.Errorf("date = %q, want %q(서버가 오늘로 채움)", c.Date, day)
	}
	found, err := s.ListHwChecks(ctx, memberP(mine.ID), hw.ID, "", day)
	if err != nil {
		t.Fatal(err)
	}
	if len(found) != 1 {
		t.Errorf("앱 질의(?date=오늘) 결과 %d건, want 1(화면과 지표가 어긋나던 자리)", len(found))
	}
	// ⑦ 담당 코치의 대행 입력은 정상(과잉 차단 방지).
	if _, err := s.CreateHwCheck(ctx, trainerP(), HwCheckRequest{
		MemberID: mine.ID, HwID: hw.ID, Date: day, Done: []bool{true, true},
	}); err != nil {
		t.Fatalf("담당 코치 대행 체크 실패: %v", err)
	}
}

// M3 회귀: tap 체크인이 p.IsStaff()만 보고 booking.TrainerID를 안 봤다.
// 같은 파일의 CompleteBooking·NoshowBooking은 보고 있어 비대칭이었다.
//
// 실측: t2 → POST /v1/checkin {"source":"tap","booking_id": t1 담당 예약} → 200 + last_visit_at 갱신
// (장기미출석 통계의 근거 필드다 — 남의 회원 출석 이력이 조용히 바뀐다).
func TestCheckinTapRespectsTrainerScope(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 20) // 담당 t1
	seedTrainerRecord(t, s, "t2", "김태오")
	b, err := s.CreateBooking(ctx, ownerP(), BookingCreateRequest{
		SlotKey: slotKeyDaysAhead(1, 9), MemberID: mem.ID, PassID: pass.ID,
	})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := s.Checkin(ctx, outsiderTrainerP(), CheckinRequest{
		Source: "tap", BookingID: b.ID,
	}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("타 코치 tap 체크인 = %v, want ErrForbidden", err)
	}
	after, err := s.store.GetMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if after.LastVisitAt != nil {
		t.Errorf("거부된 체크인이 last_visit_at을 갱신함: %v", after.LastVisitAt)
	}

	// 담당 코치·대표는 통과(과잉 차단 방지).
	if _, err := s.Checkin(ctx, trainerP(), CheckinRequest{Source: "tap", BookingID: b.ID}); err != nil {
		t.Fatalf("담당 코치 tap 체크인 실패: %v", err)
	}
	if _, err := s.Checkin(ctx, ownerP(), CheckinRequest{Source: "tap", BookingID: b.ID}); err != nil {
		t.Fatalf("대표 tap 체크인 실패: %v", err)
	}
}
