package store

// SeedDemo — 데모 데이터 시딩(v1.4, DEV_SEED=true + 인메모리 전용). 첫 구동이 전부 빈 화면이라
// 데모/영업(설계01 Q3 "목업이 곧 영업 데모")과 로컬 개발이 불가능했던 갭을 푼다. 어드민 전
// 화면(대시보드 KPI·해야 할 일·미수금·예약 그리드·회원 상세·통계)과 회원 앱 전 탭이 의미 있는
// 상태로 보이도록 스태프·회원·패스·예약·홈워크·결제(미납 포함)·계약·수업기록을 심는다.
//
// 데모 계정: 어드민 X-Dev-Uid owner1(대표)·t1(정혜린)·t2(김태오) / 회원 앱 X-Dev-Uid member1(김민지).

import (
	"context"
	"fmt"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// SeedDemo — 멱등이 아니다(빈 스토어 전제). main이 인메모리 첫 구동에서만 호출한다.
func SeedDemo(ctx context.Context, st Store, centerID string) error {
	kst := time.FixedZone("KST", 9*60*60)
	now := time.Now().In(kst)
	day := func(d int) string { return now.AddDate(0, 0, d).Format("2006-01-02") }
	slotKey := func(d, hour int) string {
		return now.AddDate(0, 0, d).Format("20060102") + fmt.Sprintf("-%02d", hour)
	}
	at := func(hoursAgo int) time.Time { return now.Add(-time.Duration(hoursAgo) * time.Hour).UTC() }

	// ---- 스태프(대표 1 + 트레이너 2) + 인증 인덱스 ----
	staff := []domain.Staff{
		{UID: "owner1", Role: domain.RoleOwner, Name: "박관장", Color: "#60a5fa",
			Payout: domain.Payout{}, Offdays: []string{},
			Profile: domain.StaffProfile{
				Title: "대표 · 헤드 코치", CareerYears: 12,
				Specialties:    []string{"재활 트레이닝", "바디 리컴포지션"},
				Certifications: []string{"NSCA-CSCS", "생활스포츠지도사 2급(보디빌딩)"},
				Awards:         []string{"2019 전국 보디빌딩 클래식 -75kg 우승"},
				Bio:            "12년차 트레이너이자 라이즈 컨디셔닝 대표. 통증 없는 몸이 먼저라는 원칙으로 재활 기반 트레이닝을 지도합니다.",
			}},
		{UID: "t1", Role: domain.RoleTrainer, Name: "정혜린", Color: "#f43f5e",
			Payout: domain.Payout{Type: "rate", Value: 0.5}, Offdays: []string{day(6)},
			Profile: domain.StaffProfile{
				Title: "퍼포먼스 트레이너", CareerYears: 7,
				Specialties:    []string{"여성 근력", "체형 교정", "산전·산후"},
				Certifications: []string{"NASM-CPT", "NASM-CES(교정운동)"},
				Awards:         []string{"피트니스 모델 그랑프리 2023 TOP5"},
				Bio:            "여성 회원 비율 80%. 무리한 감량보다 근력과 체형의 균형을 만드는 수업을 합니다.",
			}},
		{UID: "t2", Role: domain.RoleTrainer, Name: "김태오", Color: "#34d399",
			Payout: domain.Payout{Type: "per_session", Value: 35000}, Offdays: []string{},
			Profile: domain.StaffProfile{
				Title: "컨디셔닝 코치", CareerYears: 5,
				Specialties:    []string{"그룹 컨디셔닝", "체력 강화", "크로스핏 기초"},
				Certifications: []string{"ACSM-CPT", "CrossFit Level 1"},
				Awards:         []string{},
				Bio:            "그룹 수업 전문. 운동이 처음인 분도 5회 안에 기본 패턴을 잡아드립니다.",
			}},
	}
	for i := range staff {
		if err := st.SaveStaff(ctx, centerID, &staff[i]); err != nil {
			return err
		}
		if err := st.SaveUserIndex(ctx, &UserIndex{UID: staff[i].UID, Role: staff[i].Role, CenterID: centerID}); err != nil {
			return err
		}
	}

	// ---- 회원 5명(상태 다양: 앱연결·부상·휴면·미배정·만료임박) ----
	consentOK := domain.Consent{General: true, Sensitive: true, SignedAt: ptrTime(at(24 * 30))}
	longAgo := at(24 * 70)
	members := []domain.Member{
		{Name: "김민지", Phone: "010-1234-5678", Channel: "지인소개", TrainerID: "t1",
			Flags: []domain.MemberFlag{}, Consent: consentOK, AppLinked: true,
			Status: domain.MemberStatusActive, LastVisitAt: ptrTime(at(24))},
		{Name: "박현우", Phone: "010-2345-6789", Channel: "인스타", TrainerID: "t1",
			Flags:   []domain.MemberFlag{{Type: domain.FlagInjury, Note: "어깨 회전근개 — 오버헤드 주의"}},
			Consent: domain.Consent{General: true}, AppLinked: false,
			Status: domain.MemberStatusActive, LastVisitAt: ptrTime(at(48))},
		{Name: "이서연", Phone: "010-3456-7890", Channel: "워크인", TrainerID: "t2",
			Flags: []domain.MemberFlag{}, Consent: consentOK, AppLinked: false,
			Status: domain.MemberStatusActive, LastVisitAt: ptrTime(at(24 * 3))},
		{Name: "최지훈", Phone: "010-4567-8901", Channel: "재등록", TrainerID: "",
			Flags: []domain.MemberFlag{}, Consent: domain.Consent{General: true}, AppLinked: false,
			Status: domain.MemberStatusDormant, LastVisitAt: &longAgo},
		{Name: "한가을", Phone: "010-5678-9012", Channel: "지인소개", TrainerID: "t1",
			Flags: []domain.MemberFlag{}, Consent: consentOK, AppLinked: false,
			Status: domain.MemberStatusActive, LastVisitAt: ptrTime(at(24 * 2))},
	}
	ids := make([]string, len(members))
	for i := range members {
		id, err := st.SaveMember(ctx, centerID, &members[i])
		if err != nil {
			return err
		}
		ids[i] = id
	}
	minji, hyunwoo, seoyeon, gaeul := ids[0], ids[1], ids[2], ids[4]
	// 회원 앱 데모 계정(member1)을 김민지에 연결(P48 매칭 완료 상태).
	if err := st.SaveUserIndex(ctx, &UserIndex{UID: "member1", Role: domain.RoleMember, CenterID: centerID, MemberID: minji}); err != nil {
		return err
	}

	// ---- 패스 + 원장(issue) ----
	newPass := func(memberID, trainerID, product string, paid, total int, from, until string) (*domain.Pass, error) {
		p := &domain.Pass{MemberID: memberID, TrainerID: trainerID, Product: product,
			PaidAmount: paid, TotalSessions: total, Remaining: total,
			ValidFrom: from, ValidUntil: until, Status: domain.PassStatusActive, Holds: []domain.Hold{}}
		id, err := st.CreatePass(ctx, centerID, p)
		if err != nil {
			return nil, err
		}
		p.ID = id
		_, err = st.AppendLedger(ctx, centerID, &domain.Ledger{
			PassID: id, MemberID: memberID, Delta: total, Reason: domain.ReasonIssue, By: "owner1", At: at(24 * 30)})
		return p, err
	}
	passMinji, err := newPass(minji, "t1", "PT 20회", 1_000_000, 20, day(-30), day(60))
	if err != nil {
		return err
	}
	passHyunwoo, err := newPass(hyunwoo, "t1", "PT 10회", 550_000, 10, day(-20), day(70))
	if err != nil {
		return err
	}
	passSeoyeon, err := newPass(seoyeon, "t2", "그룹 컨디셔닝 12회", 360_000, 12, day(-15), day(75))
	if err != nil {
		return err
	}
	passGaeul, err := newPass(gaeul, "t1", "PT 10회", 550_000, 10, day(-85), day(5)) // 만료 임박 D-5
	if err != nil {
		return err
	}

	// ---- 예약: 과거 완료 3(김민지 2·한가을 8회 소진은 원장으로 직접) + 노쇼 유예 1 + 오늘/미래 ----
	book := func(d, hour int, memberID, trainerID, passID, status string, ledgerDelta int, reason string) error {
		b := &domain.Booking{SlotKey: slotKey(d, hour), MemberID: memberID, TrainerID: trainerID,
			PassID: passID, Kind: domain.BookingKindPT, Status: domain.BookingConfirmed}
		if err := st.BookAtomic(ctx, centerID, b.SlotKey, 3, b); err != nil {
			return err
		}
		if status == domain.BookingConfirmed {
			return nil
		}
		var entry *domain.Ledger
		if reason != "" {
			entry = &domain.Ledger{PassID: passID, MemberID: memberID, Delta: ledgerDelta,
				Reason: reason, RefBookingID: b.ID, By: "t1", At: at(-24 * d)} // d<0(과거) → 양수 hoursAgo
		}
		return st.SetBookingStatusWithLedger(ctx, centerID, b.ID, status, entry)
	}
	if err := book(-7, 10, minji, "t1", passMinji.ID, domain.BookingCompleted, -1, domain.ReasonComplete); err != nil {
		return err
	}
	if err := book(-3, 10, minji, "t1", passMinji.ID, domain.BookingCompleted, -1, domain.ReasonComplete); err != nil {
		return err
	}
	if err := book(-2, 15, hyunwoo, "t1", passHyunwoo.ID, domain.BookingNoshow, 0, domain.ReasonNoshowWaive); err != nil {
		return err
	}
	if err := book(-1, 11, seoyeon, "t2", passSeoyeon.ID, domain.BookingCompleted, -1, domain.ReasonComplete); err != nil {
		return err
	}
	// 오늘·미래 confirmed
	for _, b := range [][4]interface{}{
		{0, 10, minji, passMinji.ID}, {0, 14, seoyeon, passSeoyeon.ID},
		{1, 11, minji, passMinji.ID}, {1, 16, hyunwoo, passHyunwoo.ID}, {2, 10, gaeul, passGaeul.ID},
	} {
		trainer := "t1"
		if b[2].(string) == seoyeon {
			trainer = "t2"
		}
		if err := book(b[0].(int), b[1].(int), b[2].(string), trainer, b[3].(string), domain.BookingConfirmed, 0, ""); err != nil {
			return err
		}
	}
	// 한가을: 잔여 2회 남기기(8회 사용 — 완료 원장만 직접 적재, 과거 예약 도큐먼트는 생략)
	for i := 0; i < 8; i++ {
		if _, err := st.AppendLedger(ctx, centerID, &domain.Ledger{
			PassID: passGaeul.ID, MemberID: gaeul, Delta: -1, Reason: domain.ReasonComplete,
			By: "t1", At: at(24 * (80 - i*9))}); err != nil {
			return err
		}
	}

	// ---- 고정 스케줄 규칙(김민지 화·금 20시) ----
	if _, err := st.CreateRecurring(ctx, centerID, &domain.Recurring{
		MemberID: minji, TrainerID: "t1", PassID: passMinji.ID,
		Days: []string{"tue", "fri"}, Hour: 20, Until: day(56)}); err != nil {
		return err
	}

	// ---- 홈워크(부상 자동 제외 시연) + 오늘 체크 ----
	hw := &domain.Homework{TrainerID: "t1", Scope: domain.HwScopeMyMembers,
		TargetMemberIDs: []string{minji, gaeul}, Excluded: []string{hyunwoo},
		Items: []domain.HwItem{
			{Name: "스쿼트", Sets: 3, Reps: "15", Note: "무릎 정렬 유지"},
			{Name: "플랭크", Sets: 3, Reps: "40초", Note: ""},
		},
		Schedule: domain.HwSchedule{Type: "weekly", Days: []string{"mon", "wed", "fri"}, From: day(-14), To: day(28)}}
	hwID, err := st.CreateHomework(ctx, centerID, hw)
	if err != nil {
		return err
	}
	if err := st.SaveHwCheck(ctx, centerID, &domain.HwCheck{
		MemberID: minji, HwID: hwID, Date: day(0), Done: []bool{true, false}}); err != nil {
		return err
	}

	// ---- 결제(분할 미납 1건 — 미수금 KPI 시연) + 계약 ----
	if _, err := st.CreatePayment(ctx, centerID, &domain.Payment{
		MemberID: minji, PassID: passMinji.ID, Method: "card", Total: 1_000_000,
		Installments: []domain.Installment{{Due: day(-30), Amount: 1_000_000, PaidAt: ptrTime(at(24 * 30))}},
		Channel:      "지인소개"}); err != nil {
		return err
	}
	if _, err := st.CreatePayment(ctx, centerID, &domain.Payment{
		MemberID: gaeul, PassID: passGaeul.ID, Method: "transfer", Total: 550_000,
		Installments: []domain.Installment{
			{Due: day(-85), Amount: 300_000, PaidAt: ptrTime(at(24 * 85))},
			{Due: day(-3), Amount: 250_000}, // 연체 미납 — 미수금(연체) 250,000원 시연(v1.5 재정의 정합)
		},
		Channel: "지인소개"}); err != nil {
		return err
	}
	for _, c := range []domain.Contract{
		{MemberID: minji, PassID: passMinji.ID, Product: "PT 20회", PaidAmount: 1_000_000, PenaltyRate: ptrF(0.10),
			Status: domain.ContractStatusSigned, SentAt: ptrTime(at(24 * 30)), FirstSentAt: ptrTime(at(24 * 30)),
			SignedAt: ptrTime(at(24*30 - 2)), SignerIP: "127.0.0.1"},
		{MemberID: gaeul, PassID: passGaeul.ID, Product: "PT 10회", PaidAmount: 550_000, PenaltyRate: ptrF(0.10),
			Status: domain.ContractStatusSent, SentAt: ptrTime(at(24 * 85)), FirstSentAt: ptrTime(at(24 * 85))},
	} {
		cc := c
		if _, err := st.CreateContract(ctx, centerID, &cc); err != nil {
			return err
		}
	}

	// ---- 수업 기록(회원 앱 기록 탭·어드민 회원 상세 시연) ----
	for _, wl := range []domain.WorkoutLog{
		{MemberID: minji, TrainerID: "t1", Date: day(-3), Title: "1:1 PT",
			Exercises: []domain.Exercise{
				{Name: "고블릿 스쿼트", Sets: 3, Reps: "12", WeightKG: 16},
				{Name: "루마니안 데드리프트", Sets: 3, Reps: "10", WeightKG: 37.5},
			},
			CoachNote: "폼 안정! 다음엔 40kg 도전"},
		{MemberID: minji, TrainerID: "t1", Date: day(-7), Title: "1:1 PT",
			Exercises: []domain.Exercise{
				{Name: "박스 스텝업", Sets: 4, Reps: "10", WeightKG: 8},
				{Name: "행잉 니레이즈", Sets: 3, Reps: "12", WeightKG: 0, Note: "자중"},
			},
			CoachNote: "코어 안정성 좋아짐"},
	} {
		w := wl
		if _, err := st.CreateWorkoutLog(ctx, centerID, &w); err != nil {
			return err
		}
	}

	// ---- 인바디 2회(추이 시연) ----
	for _, ib := range []domain.Inbody{
		// source=staff — 데모 데이터는 데스크에서 기기 결과를 옮겨 적은 것으로 본다(v2.9).
		// 회원 셀프 삭제 대상이 아니라, 시드 상태로도 "코치 기록은 회원이 못 지운다"가 재현된다.
		{MemberID: minji, Date: day(-30), Weight: 58.2, SMM: 22.1, BFM: 16.8, PBF: 28.9, VFL: 6, BMR: 1290,
			Source: domain.InbodySourceStaff},
		{MemberID: minji, Date: day(-2), Weight: 57.4, SMM: 22.5, BFM: 15.9, PBF: 27.7, VFL: 5, BMR: 1302,
			Source: domain.InbodySourceStaff},
	} {
		r := ib
		if _, err := st.CreateInbody(ctx, centerID, &r); err != nil {
			return err
		}
	}
	return nil
}

func ptrTime(t time.Time) *time.Time { return &t }

func ptrF(f float64) *float64 { return &f }
