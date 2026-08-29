package api

import (
	"context"
	"fmt"
	"sort"
	"strings"
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
	hwDone, hwTotal := homeworkCompletion(ctx, s.store, p.CenterID, homeworks, trainerFilter, now.Format("2006-01-02"))
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
		result.ByTrainer = s.byTrainerStats(ctx, p.CenterID, staffList, passes, bookings, homeworks, payments, *policy, now)
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
func homeworkCompletion(ctx context.Context, st store.Store, centerID string, hws []domain.Homework, trainerFilter, today string) (done, total int) {
	for _, hw := range hws {
		if trainerFilter != "" && hw.TrainerID != trainerFilter {
			continue
		}
		if hw.Schedule.IsEndedOn(today) {
			continue
		}
		for _, memberID := range hw.TargetMemberIDs {
			total++
			checks, err := st.ListHwChecksByMember(ctx, centerID, memberID)
			if err != nil {
				continue
			}
			for _, c := range checks {
				if c.HwID == hw.ID && anyDone(c.Done) {
					done++
					break
				}
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
func (s *Service) byTrainerStats(
	ctx context.Context, centerID string, staffList []domain.Staff, passes []domain.Pass,
	bookings []domain.Booking, homeworks []domain.Homework, payments []domain.Payment,
	policy domain.Policy, now time.Time,
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

		hwDone, hwTotal := homeworkCompletion(ctx, s.store, centerID, homeworks, st.UID, now.Format("2006-01-02"))
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
