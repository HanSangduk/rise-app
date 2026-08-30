package store

// SeedDemo — 데모 데이터 시딩(v1.4, DEV_SEED=true + 인메모리 전용). 첫 구동이 전부 빈 화면이라
// 데모/영업(설계01 Q3 "목업이 곧 영업 데모")과 로컬 개발이 불가능했던 갭을 푼다. 어드민 전
// 화면(대시보드 KPI·해야 할 일·미수금·예약 그리드·회원 상세·통계)과 회원 앱 전 탭이 의미 있는
// 상태로 보이도록 스태프·회원·패스·예약·홈워크·결제(미납 포함)·계약·수업기록을 심는다.
//
// 데모 계정: 어드민 X-Dev-Uid owner1(대표)·t1(정혜린)·t2(김태오)·t3(이수민) / 회원 앱 X-Dev-Uid member1(김민지).
//
// 프로필 사진(P40): t1·t2·t3는 외부 photo_url을 넣는다 — 회원 앱의 사진 아바타·
// 프로필 시트·코치 소개 목록이 실사진으로 테스트되는 자리다. owner1은 일부러
// 비워 둔다(이니셜 폴백 경로도 시드 상태에서 재현). 오프라인 데모에선 이미지
// 로드가 실패해도 TrainerAvatar가 색 배경+이니셜로 폴백하므로 화면이 깨지지 않는다.

import (
	"context"
	"fmt"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// DemoCheckinQRToken — 데모·로컬 전용 고정 체크인 토큰(P49). 앱의 `CHECKIN_QR_TOKEN`
// dart-define 기본값과 **같은 문자열이어야 한다**(app/lib/core/network/api_config.dart) —
// 카메라 없는 시뮬레이터·CI가 셀프 체크인을 끝까지 돌려보는 유일한 통로다.
//
// 공개된 값이지만 위험하지 않다: SeedDemo는 인메모리 스토어에서만 돌고(cmd/server/main.go의
// `DevSeed && !UseFirestore`), 운영 Firestore에는 발급 API로만 토큰이 들어간다.
const DemoCheckinQRToken = "rise-desk-checkin"

// SeedDemo — 멱등이 아니다(빈 스토어 전제). main이 인메모리 첫 구동에서만 호출한다.
func SeedDemo(ctx context.Context, st Store, centerID string) error {
	kst := time.FixedZone("KST", 9*60*60)
	now := time.Now().In(kst)
	day := func(d int) string { return now.AddDate(0, 0, d).Format("2006-01-02") }
	slotKey := func(d, hour int) string {
		return now.AddDate(0, 0, d).Format("20060102") + fmt.Sprintf("-%02d", hour)
	}
	at := func(hoursAgo int) time.Time { return now.Add(-time.Duration(hoursAgo) * time.Hour).UTC() }

	// ---- 스태프(대표 1 + 트레이너 3) + 인증 인덱스 ----
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
				PhotoURL: "https://randomuser.me/api/portraits/women/44.jpg",
				Title:    "퍼포먼스 트레이너", CareerYears: 7,
				Specialties:    []string{"여성 근력", "체형 교정", "산전·산후"},
				Certifications: []string{"NASM-CPT", "NASM-CES(교정운동)"},
				Awards:         []string{"피트니스 모델 그랑프리 2023 TOP5"},
				Bio:            "여성 회원 비율 80%. 무리한 감량보다 근력과 체형의 균형을 만드는 수업을 합니다.",
			}},
		{UID: "t2", Role: domain.RoleTrainer, Name: "김태오", Color: "#34d399",
			Payout: domain.Payout{Type: "per_session", Value: 35000}, Offdays: []string{},
			Profile: domain.StaffProfile{
				PhotoURL: "https://randomuser.me/api/portraits/men/32.jpg",
				Title:    "컨디셔닝 코치", CareerYears: 5,
				Specialties:    []string{"그룹 컨디셔닝", "체력 강화", "크로스핏 기초"},
				Certifications: []string{"ACSM-CPT", "CrossFit Level 1"},
				Awards:         []string{},
				Bio:            "그룹 수업 전문. 운동이 처음인 분도 5회 안에 기본 패턴을 잡아드립니다.",
			}},
		{UID: "t3", Role: domain.RoleTrainer, Name: "이수민", Color: "#a78bfa",
			Payout: domain.Payout{Type: "rate", Value: 0.45}, Offdays: []string{},
			Profile: domain.StaffProfile{
				PhotoURL: "https://randomuser.me/api/portraits/women/68.jpg",
				Title:    "모빌리티 코치", CareerYears: 4,
				Specialties:    []string{"모빌리티", "자세 교정", "폼롤러 리커버리"},
				Certifications: []string{"FRC Mobility Specialist", "생활스포츠지도사 2급"},
				Awards:         []string{},
				Bio:            "관절 가동범위가 운동의 시작입니다. 뻣뻣한 몸도 8회 안에 달라지는 걸 느끼게 해드려요.",
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

	// ---- 사업자·시설 신원(P43) — 계약서 본문·법정 문서 렌더용 데모 값 ----
	// 전부 **명백한 테스트 값**이다(등록번호 123-45-67890 · .example 도메인 · 신고번호
	// 제2026-…호). 실제 발행 전 어드민 설정에서 실값으로 교체하는 것이 계약서doc §F
	// 체크리스트다. 상호·대표자는 시드 페르소나(라이즈 컨디셔닝·박관장)와 일치시켰고,
	// 12칸을 전부 채워 legal 4문서의 초안 배너가 내려간 상태(IsComplete)까지 시연된다.
	// Insurance는 일부러 비운다 — {{보증보험 종류·보장내용}}의 "가입하지 않았습니다"
	// 폴백(제20조③ 자체 설계)이 데모에서 실제로 렌더되는 표본.
	if err := st.SaveBusiness(ctx, centerID, &domain.Business{
		BizName: "라이즈 컨디셔닝", CeoName: "박관장", BizRegNo: "123-45-67890",
		Address: "서울특별시 강남구 테헤란로 1, 2층", Phone: "02-1234-5678", Email: "hello@rize.example",
		PrivacyOfficerName: "박관장", PrivacyOfficerTitle: "대표", PrivacyOfficerEmail: "hello@rize.example",
		PrivacyDept: "운영팀", PrivacyManager: "박관장", EffectiveDate: day(0),
	}); err != nil {
		return err
	}
	if err := st.SaveFacility(ctx, centerID, &domain.Facility{
		ReportStatus: domain.FacilityStatusReported, ReportNo: "제2026-서울강남-0001호", Insurance: "",
	}); err != nil {
		return err
	}

	// ---- 데스크 체크인 QR 토큰(P49) ----
	//
	// 데모·로컬은 **고정 토큰**을 심는다. 실발급(crypto/rand)이면 매 구동마다 값이 달라져
	// 앱의 dart-define 폴백(`CHECKIN_QR_TOKEN`, 기본값 DemoCheckinQRToken)이 맞을 수가 없고,
	// 카메라 없는 시뮬레이터·CI에서 셀프 체크인 흐름을 끝까지 돌려볼 통로가 사라진다.
	//
	// 이 값이 공개돼 있어도 안전한 이유는 **범위**다: SeedDemo는 `DEV_SEED=true`이고
	// **인메모리 스토어일 때만** 호출된다(cmd/server/main.go). Firestore 모드에는 절대
	// 들어가지 않으므로, 실회원이 있는 저장소에서 이 문자열이 통과하는 경우가 없다.
	// 종전 구조의 위험은 "문자열이 알려졌다"가 아니라 "알려진 문자열이 **실 DB에 붙은 서버**
	// 에서 통했다"는 것이었고(그래서 기동 검증이 있었다), 그 조합이 여기서는 성립하지 않는다.
	seededAt := at(24 * 7)
	if err := st.SaveCheckinQR(ctx, centerID, &domain.CheckinQR{
		Token: DemoCheckinQRToken, IssuedAt: &seededAt,
	}); err != nil {
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
	// 김민지 두 번째 패스(담당 t3) — 회원 앱의 패스 전환 칩·코치 카드 전환·
	// "내 회원권 전체" 예약 모드가 코치 2명(사진 있는 t1·t3)으로 테스트되는 자리(P40).
	// P43: 이 패스에 결제+sent 계약을 붙인다 — 데모 앱 계정(member1)의 유일한 sent 계약
	// 자리라, main의 데모 재발송이 여기에 Vars를 스탬프해 계약서 본문·끝-스크롤 서명
	// 게이트를 앱에서 곧장 시연할 수 있다(김민지의 PT 20회 계약은 signed 종단 — 레거시
	// 요약 열람 분기 시연용으로 그대로 둔다).
	passMinjiMob, err := newPass(minji, "t3", "모빌리티 8회", 320_000, 8, day(-10), day(80))
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
		Schedule: domain.HwSchedule{Type: "weekly", Days: []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}, From: day(-14), To: day(28)}}
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
	// P43: 모빌리티 패스 결제 — 완납 1회차 + **미도래** 2회차(연체 아님: 미수금 KPI는 가을의
	// 250,000원 하나로 유지). {{납부일정}}이 "납부완료"와 "납부예정"을 섞어 렌더되는 표본.
	if _, err := st.CreatePayment(ctx, centerID, &domain.Payment{
		MemberID: minji, PassID: passMinjiMob.ID, Method: "card", Total: 320_000,
		Installments: []domain.Installment{
			{Due: day(-10), Amount: 200_000, PaidAt: ptrTime(at(24 * 9))},
			{Due: day(20), Amount: 120_000},
		},
		Channel: "재등록"}); err != nil {
		return err
	}
	for _, c := range []domain.Contract{
		{MemberID: minji, PassID: passMinji.ID, Product: "PT 20회", PaidAmount: 1_000_000, PenaltyRate: ptrF(0.10),
			Status: domain.ContractStatusSigned, SentAt: ptrTime(at(24 * 30)), FirstSentAt: ptrTime(at(24 * 30)),
			SignedAt: ptrTime(at(24*30 - 2)), SignerIP: "127.0.0.1"},
		{MemberID: gaeul, PassID: passGaeul.ID, Product: "PT 10회", PaidAmount: 550_000, PenaltyRate: ptrF(0.10),
			Status: domain.ContractStatusSent, SentAt: ptrTime(at(24 * 85)), FirstSentAt: ptrTime(at(24 * 85))},
		// P43: member1(김민지)의 sent 계약 — 데모 래치 ON 재발송이 Vars를 스탬프하는 자리.
		{MemberID: minji, PassID: passMinjiMob.ID, Product: "모빌리티 8회", PaidAmount: 320_000, PenaltyRate: ptrF(0.10),
			Status: domain.ContractStatusSent, SentAt: ptrTime(at(24 * 9)), FirstSentAt: ptrTime(at(24 * 9))},
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

	// ---- 체형 사진 4장(비교 시연, P46) ----
	// StoragePath가 demo/ 접두면 실파일은 Storage가 아니라 스토어 캡처 하네스가
	// 로컬 HTTP로 준다(app integration_test의 데모 로더 오버라이드). 실기기 일반
	// 실행에선 Storage 조회가 실패해 타일이 "다시 시도"로 뜰 뿐 크래시는 없다.
	for _, bp := range []domain.BodyPhoto{
		{MemberID: minji, Pose: "stand", Direction: "front", Date: day(-30), StoragePath: "demo/stand-front-before.jpg"},
		// 측면 쌍은 중간 날짜 — 최신(비교 기본 선택)이 정면이 되어 스크러버 기본 화면이
		// 정면 vs 정면 비교로 열린다(P46 스토어 캡처 실측: 섞이면 정면 vs 측면으로 보임).
		{MemberID: minji, Pose: "stand", Direction: "side", Date: day(-28), StoragePath: "demo/stand-side-before.jpg"},
		{MemberID: minji, Pose: "stand", Direction: "side", Date: day(-14), StoragePath: "demo/stand-side-after.jpg"},
		{MemberID: minji, Pose: "stand", Direction: "front", Date: day(-2), StoragePath: "demo/stand-front-after.jpg"},
	} {
		b := bp
		if _, err := st.CreateBodyPhoto(ctx, centerID, &b); err != nil {
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
