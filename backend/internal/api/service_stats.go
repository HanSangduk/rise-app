package api

import (
	"context"
	"errors"
	"fmt"
	"log"
	"sort"
	"strings"
	"sync/atomic"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// Stats — §8 지표 세트. scope=me(기본)는 호출자 본인 스코프(트레이너 관점으로 필터),
// scope=center는 센터 전체 + by_trainer 비교표(owner 전용 — P13·P45, 계약: "by_trainer는 owner만").
func (s *Service) Stats(ctx context.Context, p Principal, rangeParam, scope string) (domain.Stats, error) {
	if p.IsMember() {
		return domain.Stats{}, ErrForbidden
	}
	if scope == "" {
		scope = "me"
	}
	// 계약 밖 값은 400(P74 반박 — HEAD부터 있던 결함). 아래 분기는 "me가 아니면 센터 전체"로 집계하고 금액을
	// 비우는 조건은 scope=="center"뿐이라, 트레이너가 "all"·"ME"·"center " 같은 값을 보내면 센터 매출이 나갔다.
	if scope != "me" && scope != "center" {
		return domain.Stats{}, errors.Join(errBadRequest, fmt.Errorf("scope는 me 또는 center만 가능해요(받은 값 %q)", scope))
	}
	// v1.2 정합 패치: 트레이너의 scope=center 호출을 허용한다 — P45 "센터 평균과 비교" UX에
	// 필요. 단 금액 지표(monthly/ytd/target)와 by_trainer는 owner 전용(P13)이라 아래에서 비운다.
	_ = rangeParam // v1은 range 값과 무관하게 YTD + 월별 12개월 스타일을 고정 반환(README 갭)

	policy, err := s.store.GetPolicy(ctx, p.CenterID)
	if err != nil {
		return domain.Stats{}, err
	}
	members, err := s.store.ListMembers(ctx, p.CenterID, "", "")
	if err != nil {
		return domain.Stats{}, err
	}
	passes, err := s.store.ListPasses(ctx, p.CenterID)
	if err != nil {
		return domain.Stats{}, err
	}
	// 저장된 Status는 만료를 모른다 — expired를 대입하는 코드가 프로덕션에 없다
	// (domain.Pass.EffectiveStatus). 재등록률(§8)은 분모가 `status=expired` 개수라
	// 이 한 줄이 없으면 **영구 0**이고, 만료임박·활성 집계도 같은 값을 본다.
	// 사본에만 쓴다(ListPasses가 돌려준 슬라이스는 이 함수의 지역 값이다).
	todayKST := today()
	for i := range passes {
		passes[i].Status = passes[i].EffectiveStatus(todayKST)
	}
	bookings, err := s.store.ListBookings(ctx, p.CenterID)
	if err != nil {
		return domain.Stats{}, err
	}
	homeworks, err := s.store.ListHomeworks(ctx, p.CenterID)
	if err != nil {
		return domain.Stats{}, err
	}
	payments, err := s.store.ListPayments(ctx, p.CenterID)
	if err != nil {
		return domain.Stats{}, err
	}
	staffList, err := s.store.ListStaff(ctx, p.CenterID)
	if err != nil {
		return domain.Stats{}, err
	}

	var trainerFilter string
	if scope == "me" {
		trainerFilter = p.UID
	}
	// 패스 상태 인덱스(v1.5) — 미수·매출 집계에서 환불 패스를 제외하기 위한 조회용.
	passStatusByID := map[string]string{}
	for _, ps := range passes {
		passStatusByID[ps.ID] = ps.Status
	}

	now := time.Now().In(domain.KST)
	result := domain.Stats{}
	if p.IsOwner() {
		// 센터 매출 목표는 금액 지표 — scope와 무관하게 owner 전용(P13, 2R MEDIUM-7).
		result.Target = policy.RevenueTarget
	}

	// ---- 회원 스코프 ----
	activeMembers, unassigned, longAbsent := 0, 0, 0
	// 탈퇴 회원 집합(v2.37, P73) — 아래 회원권·Home Work 루프가 같은 원칙을 쓴다. 종전엔 이
	// 루프만 걸렀다: 탈퇴 시 유효기간이 남은 패스는 그대로 "만료 임박(연장 제안)"에 잡혔고
	// (연락처는 이미 파기됐다), 배정 대상에서 빠지지 않은 탈퇴자는 hw-check가 전부 삭제되므로
	// 배정이 끝날 때까지 분모만 채워 완료율을 끌어내렸다. 어드민 대시보드(computeTodo)는
	// 같은 판정을 P40부터 클라이언트에서 하고 있었다 — 서버 stats만 뒤처져 있었다.
	withdrawn := map[string]bool{}
	for _, m := range members {
		if m.IsWithdrawn() {
			withdrawn[m.ID] = true
		}
	}
	for _, m := range members {
		// 탈퇴 회원은 어느 KPI에도 들어가지 않는다(v2.11). 특히 **미배정 카운트가 급소다**:
		// 가명화가 trainer_id를 ""로 회수하므로, 거르지 않으면 탈퇴자 전원이 "담당 배정이 필요한
		// 회원"으로 집계돼 대표가 영원히 줄지 않는 할 일을 보게 된다. 장기미방문도 같다
		// (last_visit_at을 지웠으니 전원이 장기미방문으로 잡힌다).
		if m.IsWithdrawn() {
			continue
		}
		if trainerFilter != "" && m.TrainerID != trainerFilter {
			continue
		}
		if m.Status == domain.MemberStatusActive {
			activeMembers++
		}
		if m.TrainerID == "" {
			unassigned++
		}
		if domain.LongAbsent(m.LastVisitAt, now, policy.LongAbsentDays) {
			longAbsent++
		}
	}
	result.ActiveMembers = activeMembers
	result.Unassigned = unassigned
	result.LongAbsent = longAbsent
	// registered: Member에 가입일 필드가 계약에 없어 활성 회원수로 근사한다(README 갭).
	result.Registered = activeMembers

	// ---- 회원권 스코프: 만료임박·재등록률 ----
	expiring := 0
	passesByMember := map[string][]domain.Pass{}
	for _, ps := range passes {
		if trainerFilter != "" && ps.TrainerID != trainerFilter {
			continue
		}
		passesByMember[ps.MemberID] = append(passesByMember[ps.MemberID], ps)
		// 만료 임박은 "연장을 제안할 사람"의 수다 — 탈퇴자는 제안할 상대가 없다(위 withdrawn 주석).
		// passesByMember에는 남긴다: 매출(revenueByMonth)·재등록률 분모는 탈퇴와 무관한 사실이다
		// (탈퇴한 사람의 결제는 실제 매출이고, 만료 뒤 떠난 사람은 재등록하지 않은 사람이 맞다).
		if withdrawn[ps.MemberID] {
			continue
		}
		if ps.Status == domain.PassStatusActive && domain.ExpiringSoon(ps.ValidUntil, now, policy.ExpiringDays) {
			expiring++
		}
	}
	result.Expiring = expiring

	reregN, reregD := reregCount(passesByMember, policy.ReregWindowDays)
	result.ReregN, result.ReregD = reregN, reregD
	result.ReregRate = domain.Rate(reregN, reregD)

	// ---- 예약 스코프: 노쇼율 + 완료 세션 수(v1.4 — 트레이너 "내 정산"의 세션 근거) ----
	noshowN, noshowD, sessions := 0, 0, 0
	for _, b := range bookings {
		if trainerFilter != "" && b.TrainerID != trainerFilter {
			continue
		}
		switch b.Status {
		case domain.BookingCompleted:
			noshowD++
			sessions++
		case domain.BookingNoshow:
			noshowN++
			noshowD++
		}
	}
	result.NoshowRate = domain.Rate(noshowN, noshowD)
	// 분모 동봉(v2.1): 비율에 쓴 값을 **그대로** 싣는다 — 따로 세면 두 수가 조용히 어긋난다.
	result.NoshowD = noshowD
	result.Sessions = sessions

	// ---- Home Work 완료율(근사치) ----
	// 인덱스는 여기서 **한 번만** 만든다 — 아래 byTrainerStats도 같은 인덱스를 쓴다(v2.38, P74).
	// scope=center(owner)면 trainerFilter가 비어 전 트레이너의 활성 배정을 덮는다.
	today := now.Format("2006-01-02")
	hwIdx, err := loadHwDoneIndex(ctx, s.store, p.CenterID, homeworks, trainerFilter, today, withdrawn)
	if err != nil {
		return domain.Stats{}, err
	}
	hwDone, hwTotal := homeworkCompletion(homeworks, trainerFilter, today, withdrawn, hwIdx)
	result.HwRate = domain.Rate(hwDone, hwTotal)
	result.HwD = hwTotal

	// ---- 매출: 월별 + YTD ----
	monthly, ytd := revenueByMonth(payments, passesByMember, now.Year())
	result.Monthly = monthly
	result.YTD = ytd

	// ---- 미수금(v1.4→v1.5 재정의: 미수금=연체(due 경과), 미도래는 별도 — §8·시장 용례 정합) ----
	if p.IsOwner() {
		todayStr := now.Format("2006-01-02")
		unpaidTotal, unpaidCount, upcoming := 0, 0, 0
		for _, pay := range payments {
			if ps, ok := passStatusByID[pay.PassID]; ok && ps == domain.PassStatusRefunded {
				continue // 환불로 정산 종결된 결제는 미수 집계 제외(유령 미수금 방지 — waived와 이중 방어)
			}
			if o := pay.OverdueOutstanding(todayStr); o > 0 {
				unpaidTotal += o
				unpaidCount++
			}
			upcoming += pay.UpcomingOutstanding(todayStr)
		}
		result.UnpaidTotal = unpaidTotal
		result.UnpaidCount = unpaidCount
		result.UpcomingTotal = upcoming
	}

	// ---- owner + scope=center: 트레이너별 비교표 ----
	if scope == "center" && p.IsOwner() {
		result.ByTrainer = byTrainerStats(staffList, passes, bookings, homeworks, payments, *policy, now, withdrawn, hwIdx)
	}

	// 트레이너의 scope=center: 비율 지표(재등록·노쇼·HW)만 남기고 금액 지표는 비운다(P13 —
	// 센터 매출은 owner 전용. P45의 "센터 평균 비교"에 필요한 것은 비율뿐).
	if scope == "center" && !p.IsOwner() {
		result.Monthly = nil
		result.YTD = 0
		result.Target = 0
		result.ByTrainer = nil
	}

	return result, nil
}

// reregCount — 만료(status=expired)된 패스를 대상(d)으로, 만료 후 window일 내 같은 회원의
// 새 패스 발급(재등록, n)을 센다(§8: "만료 후 90일 내 재계약". 골든값: 설계03 §14 R10 4/20=20%).
func reregCount(byMember map[string][]domain.Pass, windowDays int) (n, d int) {
	for _, list := range byMember {
		for i, ps := range list {
			if ps.Status != domain.PassStatusExpired {
				continue
			}
			d++
			until, err := time.ParseInLocation("2006-01-02", ps.ValidUntil, domain.KST)
			if err != nil {
				continue
			}
			for j, other := range list {
				if j == i {
					continue
				}
				from, err := time.ParseInLocation("2006-01-02", other.ValidFrom, domain.KST)
				if err != nil {
					continue
				}
				if from.After(until) && from.Sub(until) <= time.Duration(windowDays)*24*time.Hour {
					n++
					break
				}
			}
		}
	}
	return n, d
}

func anyDone(done []bool) bool {
	for _, b := range done {
		if b {
			return true
		}
	}
	return false
}

// hwDoneIndex — 회원 → 배정 → "한 번이라도 체크했는가"(v2.38, P74).
type hwDoneIndex map[string]map[string]bool

// hwStatsFanOut — 통계가 회원별 hwChecks를 동시에 읽는 상한(ListMembers의 memberFanOut과 같은 결).
const hwStatsFanOut = 8

// loadHwDoneIndex — **활성 배정(기간 안 · 스코프 안)의 대상 회원만**, 회원당 한 번씩 읽어 편다.
//
// 읽기 비용의 변천(P74 감사에서 실측): 종전(HEAD)은 배정×대상회원 조합마다 ListHwChecksByMember를
// 불러 같은 회원을 배정 수만큼 다시 읽었고(scope=center면 트레이너별 표가 한 번 더), P74 1차는 이를
// "센터 hwChecks 전량 1회"로 바꿨는데 — 그 컬렉션은 회원 수 × 날짜로 끝없이 자라고 통계는 어드민이
// 데스크 뮤테이션마다 다시 부른다. 배정이 없는 트레이너(scope=me)도 센터 전체를 읽었다. 지금은
// 대상 회원 집합(중복 제거)만 읽는다 — HEAD보다는 항상 적고, 활성 배정이 없으면 0회다. 1차(전량)와 견주면
// 쿼리마다 최소 과금(결과가 비어도 문서 1건분)이 대상 회원 수만큼 붙지만, 전량은 회원 수 × 날짜로 자라므로
// 운영 규모에선 대상 회원 쿼리가 작다.
//
// 조회 실패는 **그 회원만** 빠진다(분모에는 남고 분자에 들지 않는다 — HEAD와 같은 단위). P74 1차는
// 전량 읽기 한 번의 실패가 완료율 전체를 조용히 0으로 만들었다. 실패 수는 로그 한 줄로 남긴다.
func loadHwDoneIndex(ctx context.Context, st store.Store, centerID string, hws []domain.Homework, trainerFilter, today string, withdrawn map[string]bool) (hwDoneIndex, error) {
	seen := map[string]bool{}
	var members []string
	for _, hw := range hws {
		if trainerFilter != "" && hw.TrainerID != trainerFilter {
			continue
		}
		if hw.Schedule.IsEndedOn(today) {
			continue
		}
		for _, id := range hw.TargetMemberIDs {
			if withdrawn[id] || seen[id] {
				continue
			}
			seen[id] = true
			members = append(members, id)
		}
	}
	perMember := make([]map[string]bool, len(members))
	var failed atomic.Int32
	// 회원의 **스토어 오류**는 돌려주지 않는다 — 한 회원의 실패가 나머지를 취소하면 안 된다(그 회원만 빠지는 단위).
	// 그래도 forEachParallel이 오류를 내는 경우가 둘 남는다: 워커 **패닉**(runRecovered가 오류로 바꾸고 나머지를
	// 취소한다)과 요청 **취소**. 둘 다 아직 안 읽은 회원이 조용히 빠진 부분 결과라 200으로 내지 않는다(P74 반박 —
	// HEAD는 같은 패닉이 recoverJSON을 거쳐 500이었다).
	err := forEachParallel(ctx, len(members), hwStatsFanOut, func(ctx context.Context, i int) error {
		checks, err := st.ListHwChecksByMember(ctx, centerID, members[i])
		if err != nil {
			failed.Add(1)
			return nil
		}
		done := map[string]bool{}
		for _, c := range checks {
			if anyDone(c.Done) {
				done[c.HwID] = true
			}
		}
		perMember[i] = done
		return nil
	})
	if err != nil {
		return nil, err
	}
	if n := failed.Load(); n > 0 {
		log.Printf("stats: hwChecks 조회 실패 %d/%d명 — 그 회원들은 HW 완료율 분자에서 빠졌어요(center=%s)", n, len(members), centerID)
	}
	idx := make(hwDoneIndex, len(members))
	for i, id := range members {
		if perMember[i] != nil {
			idx[id] = perMember[i]
		}
	}
	return idx, nil
}

// homeworkCompletion — 배정 대상 수(total=분모)와 그중 hw-check가 하나라도(done에 true 포함)
// 존재하는 대상 수(done=분자)를 센다. 진짜 완료율(스케줄 반복 대비 실제 이행율)은 v1 범위
// 밖이다(README 갭).
//
// 비율이 아니라 (분자, 분모)를 돌려준다(v2.1): 응답이 hw_d를 함께 실어야 하는데, 비율만
// 돌려주면 호출부가 분모를 다시 세게 되고 두 수가 어긋날 수 있다 — 세는 곳을 하나로 둔다.
//
// today(v2.3): **기간이 끝난 배정은 분모에서 뺀다**(P12 M4 ③). 종전엔 종료일을 아무도 보지
// 않아 분모가 단조 증가했다 — 지난달 끝난 4주 배정이 영원히 남아 완료율이 시간이 갈수록
// 구조적으로 하락했고, 그 하락은 센터가 뭘 해도 멈추지 않았다.
//
// IsActiveOn(오늘 대상 요일인가)이 아니라 IsEndedOn(기간이 끝났는가)을 쓴다: 주3회 배정은
// 화요일에 IsActiveOn=false지만 여전히 진행 중인 배정이라, 그걸 분모에 쓰면 hw_rate가 요일마다
// 출렁인다. 목록 조회(ListHomeworks)와 같은 domain 함수쌍을 공유하되 쓰는 쪽이 다르다.
//
// withdrawn(v2.37, P73): 탈퇴 회원은 분모에서 뺀다. 배정(Homework.TargetMemberIDs)은 탈퇴 시
// 정리되지 않는데 그 회원의 hw-check는 전부 파기되므로, 빼지 않으면 배정이 끝날 때까지 그 몫이
// "미이행"으로 고정돼 완료율이 트레이너가 한 일과 무관하게 내려간다.
func homeworkCompletion(hws []domain.Homework, trainerFilter, today string, withdrawn map[string]bool, doneIdx hwDoneIndex) (done, total int) {
	for _, hw := range hws {
		if trainerFilter != "" && hw.TrainerID != trainerFilter {
			continue
		}
		if hw.Schedule.IsEndedOn(today) {
			continue
		}
		for _, memberID := range hw.TargetMemberIDs {
			if withdrawn[memberID] {
				continue
			}
			total++
			if doneIdx[memberID][hw.ID] {
				done++
			}
		}
	}
	return done, total
}

// revenueByMonth — 결제(Payment.Total)를 해당 패스의 valid_from 월에 귀속시켜 집계한다
// (Payment엔 결제일 필드가 계약에 없어 Pass.valid_from을 근사 결제월로 쓴다 — README 갭).
func revenueByMonth(payments []domain.Payment, passesByMember map[string][]domain.Pass, year int) ([]domain.MonthlyPoint, int) {
	passByID := map[string]domain.Pass{}
	for _, list := range passesByMember {
		for _, ps := range list {
			passByID[ps.ID] = ps
		}
	}
	sums := map[string]int{}
	ytd := 0
	yearPrefix := fmt.Sprintf("%04d", year)
	for _, pay := range payments {
		ps, ok := passByID[pay.PassID]
		if !ok {
			continue // 이 스코프(트레이너 필터)에 없는 패스의 결제는 제외
		}
		if ps.Status == domain.PassStatusRefunded {
			continue // 순매출(v1.5): 환불된 거래는 매출에서 제외
		}
		month := ps.ValidFrom
		if len(month) >= 7 {
			month = month[:7] // "YYYY-MM"
		}
		sums[month] += pay.Total
		if strings.HasPrefix(month, yearPrefix) {
			ytd += pay.Total
		}
	}
	months := make([]string, 0, len(sums))
	for m := range sums {
		months = append(months, m)
	}
	sort.Strings(months)
	out := make([]domain.MonthlyPoint, 0, len(months))
	for _, m := range months {
		out = append(out, domain.MonthlyPoint{Month: m, Amount: sums[m]})
	}
	return out, ytd
}

// byTrainerStats — owner 전용 트레이너별 비교표(P13·P45).
func byTrainerStats(
	staffList []domain.Staff, passes []domain.Pass,
	bookings []domain.Booking, homeworks []domain.Homework, payments []domain.Payment,
	policy domain.Policy, now time.Time, withdrawn map[string]bool, hwIdx hwDoneIndex,
) []domain.TrainerStats {
	out := make([]domain.TrainerStats, 0, len(staffList))
	for _, st := range staffList {
		if st.Role != domain.RoleTrainer {
			continue // owner(대표) 행이 0값으로 비교표에 섞이는 것 방지(P03 — Settings의 "—" 처리와 일관)
		}
		passesByMember := map[string][]domain.Pass{}
		for _, ps := range passes {
			if ps.TrainerID != st.UID {
				continue
			}
			passesByMember[ps.MemberID] = append(passesByMember[ps.MemberID], ps)
		}
		reregN, reregD := reregCount(passesByMember, policy.ReregWindowDays)

		noshowN, noshowD, sessions := 0, 0, 0
		for _, b := range bookings {
			if b.TrainerID != st.UID {
				continue
			}
			switch b.Status {
			case domain.BookingCompleted:
				noshowD++
				sessions++
			case domain.BookingNoshow:
				noshowN++
				noshowD++
			}
		}

		passByID := map[string]domain.Pass{}
		for _, list := range passesByMember {
			for _, ps := range list {
				passByID[ps.ID] = ps
			}
		}
		revenue := 0
		for _, pay := range payments {
			if ps, ok := passByID[pay.PassID]; ok && ps.Status != domain.PassStatusRefunded {
				revenue += pay.Total // 순매출(v1.5): 환불 거래 제외
			}
		}

		// 퇴사자 행은 **해당 기간에 활동(sessions>0 또는 revenue>0)이 있을 때만** 넣는다(v2.0).
		// 정산 이력 보존과 현재 팀 목록 정합을 동시에 만족시킨다 — 2년 전 퇴사자가 올해 표를
		// 0값 행으로 어지럽히지 않으면서, 올해 근무분이 있는 퇴사자는 합계에서 사라지지 않는다.
		if !st.IsActive() && sessions == 0 && revenue == 0 {
			continue
		}

		hwDone, hwTotal := homeworkCompletion(homeworks, st.UID, now.Format("2006-01-02"), withdrawn, hwIdx)
		out = append(out, domain.TrainerStats{
			UID: st.UID, Status: st.Status, Name: st.Name, Revenue: revenue, Sessions: sessions,
			ReregRate:  domain.Rate(reregN, reregD),
			ReregN:     reregN,
			ReregD:     reregD,
			NoshowRate: domain.Rate(noshowN, noshowD),
			// 분모 동봉(v2.1): 위에서 비율에 쓴 바로 그 값을 싣는다 — 이미 세어놓고 버리면
			// "이번 기간 수업 0건"인 코치가 노쇼율 0.0%로 최우수처럼 정렬된다.
			NoshowD: noshowD,
			HwRate:  domain.Rate(hwDone, hwTotal),
			HwD:     hwTotal,
		})
	}
	return out
}
