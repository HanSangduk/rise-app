package api

// Vars 스탬프·봉인의 서비스 레벨 테스트(P39 v2.18 + P42 변형 선택). 세 축:
//
//   ① **latch-off 불변** — 래치를 내린 구성(withLatchOffContractVariants)에서는, 스탬프가
//      성립할 완전한 재료(사업자·결제·시설 선언)가 있어도 발급/send/sign이 v2.17 시절과
//      바이트 동일하게 동작한다(template_version·vars·sha256 전부 빈 값). 시설 상태를
//      어느 값으로 선언해도 같다 — 선택은 래치를 대체하지 않고 합성된다(P42).
//      **P48로 프로덕션 리터럴이 issuable=true가 되면서 이 축은 "배포 진실"에서 "되돌림
//      구성의 보장"으로 성격이 바뀌었다** — 단언 자체는 그대로 살린다(롤백 스위치가 실제로
//      종전 경로를 복원하는지는 증명 없이는 희망사항이다).
//   ② **latch-on 경로** — 테스트 전용 픽스처 변형(withIssuableContractVariants)으로만 연다.
//      발급 시점 스킵(결제 2키 결측), 결제 후 재발송 스탬프, 재발송 재확정, 불완전 재발송의
//      기존 스탬프 보존, 서명 봉인, Vars 없는 서명의 무봉인.
//   ③ **상태별 선택 매트릭스**(P42) — unknown 스킵(모르는 상태로 문서를 만들지 않는다) /
//      reported 25종(신고번호 포함) / exempt 24종(신고번호 없음) + 보증보험 빈 값 폴백.

import (
	"context"
	"reflect"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// withIssuableContractVariants — 발행 래치 ON 픽스처(P42에서 변형 셋으로 확장). 프로덕션
// 엔트리는 건드리지 않고 테스트 전용 버전 2종을 **실제 변형 키 목록 그대로**(reported 25/
// exempt 24) 등록한 뒤, 상태→버전 맵만 픽스처로 바꾼다(전역 var — api 패키지 테스트는
// t.Parallel을 쓰지 않아 경합 없음). Cleanup이 반드시 원상복구한다.
func withIssuableContractVariants(t *testing.T) (verReported, verExempt string) {
	t.Helper()
	verReported, verExempt = "pt-test-reported", "pt-test-exempt"
	for ver, keys := range map[string][]string{
		verReported: contractPTv1ReportedVarKeys,
		verExempt:   contractPTv1ExemptVarKeys,
	} {
		if _, dup := contractTemplates[ver]; dup {
			t.Fatalf("픽스처 버전 %s가 이미 등록돼 있다", ver)
		}
		contractTemplates[ver] = contractTemplate{requiredVarKeys: keys, issuable: true}
	}
	prev := contractVariantByStatus
	contractVariantByStatus = map[string]string{
		domain.FacilityStatusReported: verReported,
		domain.FacilityStatusExempt:   verExempt,
	}
	t.Cleanup(func() {
		contractVariantByStatus = prev
		delete(contractTemplates, verReported)
		delete(contractTemplates, verExempt)
	})
	return verReported, verExempt
}

// withLatchOffContractVariants — 발행 래치 **OFF** 픽스처(P48). 위 픽스처의 거울이다:
// P48 이전에는 프로덕션 리터럴 자체가 OFF라 latch-off 불변 테스트가 픽스처 없이 성립했지만,
// 래치가 켜진 지금은 OFF가 "구성 하나"가 됐다. 그 구성의 불변(스탬프 없음 + facility 읽기조차
// 없음)은 **여전히 지켜야 하는 진짜 보장**이라 — 되돌림 스위치가 실제로 종전 경로로 돌아가는지
// 아무도 증명하지 않으면 롤백은 희망사항이 된다 — 테스트를 지우는 대신 픽스처로 옮긴다.
//
// 프로덕션 엔트리를 제자리에서 뒤집는 이유(별도 버전 등록이 아니라): 검증 대상이 "래치를 내린
// **그** 레지스트리"이지 새 변형이 아니다. Cleanup이 원래 값을 그대로 되돌린다.
func withLatchOffContractVariants(t *testing.T) {
	t.Helper()
	for _, ver := range []string{contractTemplatePTv1Reported, contractTemplatePTv1Exempt} {
		prev, ok := contractTemplates[ver]
		if !ok {
			t.Fatalf("%s가 레지스트리에 없다 — 래치 OFF 픽스처가 대상을 잃었다", ver)
		}
		off := prev
		off.issuable = false
		contractTemplates[ver] = off
		t.Cleanup(func() { contractTemplates[ver] = prev })
	}
	if contractStampLatchOn() {
		t.Fatalf("래치 OFF 픽스처를 적용했는데 사전 게이트가 열려 있다 — 픽스처가 무력하다")
	}
}

// seedFacility — 시설 신고 상태 선언(P42). 스탬프 경로가 상태→버전 선택에 읽는 값이라,
// latch-on 테스트는 이걸 심지 않으면 기본값 unknown으로 전부 스킵된다(그게 P42의 설계다).
func seedFacility(t *testing.T, s *Service, status, reportNo, insurance string) {
	t.Helper()
	if err := s.store.SaveFacility(context.Background(), testCenter, &domain.Facility{
		ReportStatus: status, ReportNo: reportNo, Insurance: insurance,
	}); err != nil {
		t.Fatalf("SaveFacility: %v", err)
	}
}

// seedContractBusiness — 계약 슬롯이 요구하는 사업자 6칸(P27 Business의 앞 6칸)만 채운다.
// 나머지 6칸(보호책임자 등)은 계약서 슬롯이 아니다 — 비워 둬서 "IsComplete가 아니라 계약
// 6칸"이 조립 조건임이 함께 검증된다.
func seedContractBusiness(t *testing.T, s *Service) domain.Business {
	t.Helper()
	biz := domain.Business{
		BizName: "라이즈 컨디셔닝", CeoName: "박라이즈", BizRegNo: "123-45-67890",
		Address: "서울특별시 강남구 라이즈로 1", Phone: "02-1234-5678", Email: "rise@example.com",
	}
	if err := s.store.SaveBusiness(context.Background(), testCenter, &biz); err != nil {
		t.Fatalf("SaveBusiness: %v", err)
	}
	return biz
}

// recordSplitPayment — 계약가 1,000,000 패스(seedMemberWithPass)에 카드 2회 분할을 기록한다.
// 1회차는 납부완료(과거 paid_at), 2회차는 예정 — {{납부일정}}의 두 상태를 함께 만든다.
func recordSplitPayment(t *testing.T, s *Service, memberID, passID string) {
	t.Helper()
	paidAt := time.Now().UTC().Add(-time.Hour)
	if _, err := s.CreatePayment(context.Background(), ownerP(), PaymentCreateRequest{
		MemberID: memberID, PassID: passID, Method: "card", Total: 1_000_000,
		Installments: []domain.Installment{
			{Due: "2026-09-01", Amount: 600_000, PaidAt: &paidAt},
			{Due: "2026-10-01", Amount: 400_000},
		},
	}); err != nil {
		t.Fatalf("CreatePayment: %v", err)
	}
}

// autoContractOf — 발급이 자동 생성한 계약 1건.
func autoContractOf(t *testing.T, s *Service, memberID string) *domain.Contract {
	t.Helper()
	cs, err := s.ListContracts(context.Background(), ownerP(), memberID, "")
	if err != nil || len(cs) != 1 {
		t.Fatalf("계약 목록: %v, %d건(want 1)", err, len(cs))
	}
	return &cs[0]
}

// ① latch-off 불변: 스탬프 재료가 완비돼 있어도(사업자 6칸 + 결제 기록 + **신고 상태
// reported 선언까지**) 래치가 꺼진 구성에서는 발급·재발송·서명 어디서도 template_version/
// vars/sha256이 생기지 않는다 — P39 결정 1("래치가 꺼진 동안 스탬프 자체를 안 한다" =
// 다운스트림 전부 종전 동작 그대로). 시설을 일부러 선언해 두는 이유: P42의 상태 선택이 래치를
// 우회하는 네 번째 길이 아님을 고정한다(contractTemplateForStatus가 reported여도 래치 OFF 스킵).
//
// P48: 프로덕션 래치가 ON이 됐으므로 이 테스트는 픽스처로 OFF를 만들어 검증한다 — 보장의
// 내용은 한 글자도 줄지 않았고, 적용 대상이 "배포 상태"에서 "롤백 구성"으로 옮겨졌을 뿐이다.
func TestContractLatchOffStampsNothing(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	withLatchOffContractVariants(t)
	seedContractBusiness(t, s)
	seedFacility(t, s, domain.FacilityStatusReported, "제2026-강남-0001호", "서울보증 1억")
	mem, pass := seedMemberWithPass(t, s, 10)
	recordSplitPayment(t, s, mem.ID, pass.ID)
	c := autoContractOf(t, s, mem.ID)

	if c.TemplateVersion != "" || len(c.Vars) != 0 {
		t.Fatalf("래치 OFF인데 발급이 스탬프했다: version=%q vars=%d", c.TemplateVersion, len(c.Vars))
	}
	resent, err := s.SendContract(ctx, ownerP(), c.ID)
	if err != nil {
		t.Fatalf("재발송: %v", err)
	}
	if resent.TemplateVersion != "" || len(resent.Vars) != 0 {
		t.Fatalf("래치 OFF인데 재발송이 스탬프했다: version=%q vars=%d", resent.TemplateVersion, len(resent.Vars))
	}
	signed, err := s.SignContract(ctx, memberP(mem.ID), c.ID, "1.2.3.4", nil)
	if err != nil {
		t.Fatalf("서명: %v", err)
	}
	if signed.SHA256 != "" {
		t.Errorf("래치 OFF 서명에 봉인이 생겼다: %q — sha256 비어 있음 ⟺ 요약 고지 서명이라는 신호가 깨진다", signed.SHA256)
	}
	if signed.Status != domain.ContractStatusSigned || signed.SignedAt == nil || signed.SignerIP != "1.2.3.4" {
		t.Errorf("서명 자체가 오늘 동작과 다르다: %+v", signed)
	}
}

// ② 발급 시점 스킵 → 결제 후 재발송에서 첫 완전 스탬프. 스킵 **사유**(결제 2키 결측)까지
// 조립기 레벨에서 단언한다 — "확정 플로우상 결제는 발급 뒤"라는 시점 현실이 코드의 우연이
// 아니라 문서화된 동작임을 고정.
func TestContractStampSkipsAtIssueThenStampsOnResend(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	ver, _ := withIssuableContractVariants(t)
	seedContractBusiness(t, s)
	seedFacility(t, s, domain.FacilityStatusReported, "제2026-강남-0001호", "서울보증 인허가보증보험, 보장한도 1억원")
	mem, pass := seedMemberWithPass(t, s, 10) // 발급 = 자동 send. 이 시점 결제 기록 없음
	c := autoContractOf(t, s, mem.ID)

	if c.TemplateVersion != "" || len(c.Vars) != 0 {
		t.Fatalf("결제 없는 발급이 스탬프됐다: version=%q vars=%v", c.TemplateVersion, c.Vars)
	}
	// 스킵 사유: 결측이 정확히 {결제방법, 납부일정}이어야 한다 — 다른 키가 섞이면 픽스처가
	// 아니라 조립기가 문제다(reported 25종 기준 — 시설 2키·약관 주소는 조립돼야 한다).
	freshPass, err := s.store.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	_, missing, err := s.gatherContractVars(ctx, testCenter, c, freshPass, nil, nil, contractPTv1ReportedVarKeys)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"결제방법", "납부일정"}; !reflect.DeepEqual(missing, want) {
		t.Fatalf("발급 시점 결측 = %q, want %q", missing, want)
	}

	// 결제 기록 → 재발송 = 첫 완전 스탬프(운영 정상 경로).
	recordSplitPayment(t, s, mem.ID, pass.ID)
	resent, err := s.SendContract(ctx, ownerP(), c.ID)
	if err != nil {
		t.Fatalf("재발송: %v", err)
	}
	if resent.TemplateVersion != ver {
		t.Fatalf("template_version = %q, want %q(reported 변형 — 신고 상태가 버전을 골랐다)", resent.TemplateVersion, ver)
	}
	if len(resent.Vars) != len(contractPTv1ReportedVarKeys) {
		t.Fatalf("vars %d개, want %d", len(resent.Vars), len(contractPTv1ReportedVarKeys))
	}
	savedMem, err := s.store.GetMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, kv := range [][2]string{
		{"상품명", "PT 10회"},
		{"계약금액", "1,000,000"},
		{"위약금율", "10"}, // DefaultPolicy 0.10 스냅샷
		{"총 회차", "10"},
		{"유효기간 시작일", freshPass.ValidFrom},
		{"유효기간 종료일", freshPass.ValidUntil},
		{"담당 트레이너명", "정혜린"},
		{"회원명", "김민지"},
		{"회원 전화번호", savedMem.Phone},
		{"결제방법", "카드"},
		{"납부일정", "1회차 600,000원 (2026-09-01 납부완료)\n2회차 400,000원 (2026-10-01 납부예정)"},
		{"취소 마감 시간", "24"},
		{"노쇼 유예 적용 여부", "적용"},
		{"홀딩 최대 횟수", "2"},
		{"홀딩 최대 일수", "30"},
		{"슬롯 정원", "3"},
		{"사업자명", "라이즈 컨디셔닝"},
		{"대표자명", "박라이즈"},
		{"사업자등록번호", "123-45-67890"},
		{"사업장 주소", "서울특별시 강남구 라이즈로 1"},
		{"대표 전화", "02-1234-5678"},
		{"대표 이메일", "rise@example.com"},
		// P42 시설·약관 게시 3종(reported 변형 전체 25종의 마지막 세 슬롯).
		{"약관 게시 주소", "https://rize-218c1.web.app/legal/terms.html"},
		{"보증보험 종류·보장내용", "서울보증 인허가보증보험, 보장한도 1억원"},
		{"체육시설업 신고번호", "제2026-강남-0001호"},
	} {
		if got := resent.Vars[kv[0]]; got != kv[1] {
			t.Errorf("vars[%s] = %q, want %q", kv[0], got, kv[1])
		}
	}
	// 응답만 맞고 저장이 틀리면 다음 조회가 다른 문서를 보여준다.
	saved, err := s.store.GetContract(ctx, testCenter, c.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.TemplateVersion != ver || !reflect.DeepEqual(saved.Vars, resent.Vars) {
		t.Error("저장본 스탬프가 응답과 다르다")
	}
	if saved.SHA256 != "" {
		t.Errorf("서명 전인데 봉인이 생겼다: %q — 봉인은 sign의 일이다(§D ②)", saved.SHA256)
	}
}

// ② 재발송 = 재확정(P39 결정 2): 정책 값(C-2)은 send 시점 값으로 갱신되지만, {{위약금율}}은
// **계약 스냅샷이 유일한 출처**라(§C 비고, P14) 정책 요율 변경이 재발송을 타고 소급되지
// 않는다. 두 방향을 한 테스트에서 대조한다.
func TestContractResendReconfirmsPolicyButNotPenalty(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	withIssuableContractVariants(t)
	seedContractBusiness(t, s)
	seedFacility(t, s, domain.FacilityStatusReported, "제2026-강남-0001호", "서울보증 1억")
	mem, pass := seedMemberWithPass(t, s, 10)
	recordSplitPayment(t, s, mem.ID, pass.ID)
	c := autoContractOf(t, s, mem.ID)
	if _, err := s.SendContract(ctx, ownerP(), c.ID); err != nil {
		t.Fatalf("1차 발송: %v", err)
	}

	pol, err := s.store.GetPolicy(ctx, testCenter)
	if err != nil {
		t.Fatal(err)
	}
	pol.CancelCutoffHours = 48
	pol.PenaltyRate = 0.05 // 계약 생성 후의 정책 요율 변경 — 계약서에 소급되면 안 된다
	if err := s.store.SavePolicy(ctx, testCenter, pol); err != nil {
		t.Fatal(err)
	}

	resent, err := s.SendContract(ctx, ownerP(), c.ID)
	if err != nil {
		t.Fatalf("재발송: %v", err)
	}
	if got := resent.Vars["취소 마감 시간"]; got != "48" {
		t.Errorf("재발송이 정책 값을 재확정하지 않았다: 취소 마감 시간 = %q, want 48", got)
	}
	if got := resent.Vars["위약금율"]; got != "10" {
		t.Errorf("정책 요율 변경이 계약서에 소급됐다: 위약금율 = %q, want 10(생성 시점 스냅샷) — P14 재발", got)
	}
}

// ② 불완전해진 재발송은 마지막 완전 스탬프를 보존한다: 이미 완전한 문서를 받아 본 회원의
// 열람물을, 사업자 정보가 나중에 비워졌다는 이유로 파괴하면 안 된다(v2.18 보존 규약).
func TestContractIncompleteResendPreservesLastStamp(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	ver, _ := withIssuableContractVariants(t)
	biz := seedContractBusiness(t, s)
	seedFacility(t, s, domain.FacilityStatusReported, "제2026-강남-0001호", "서울보증 1억")
	mem, pass := seedMemberWithPass(t, s, 10)
	recordSplitPayment(t, s, mem.ID, pass.ID)
	c := autoContractOf(t, s, mem.ID)
	first, err := s.SendContract(ctx, ownerP(), c.ID)
	if err != nil || first.TemplateVersion != ver {
		t.Fatalf("1차 스탬프 실패: %v (version=%q)", err, first.TemplateVersion)
	}

	biz.Email = "" // 대표 이메일이 비워짐 → 조립 불가 상태로 전락
	if err := s.store.SaveBusiness(ctx, testCenter, &biz); err != nil {
		t.Fatal(err)
	}
	time.Sleep(2 * time.Millisecond) // sent_at 갱신이 관측 가능해야 "재발송은 됐다"가 증명된다
	resent, err := s.SendContract(ctx, ownerP(), c.ID)
	if err != nil {
		t.Fatalf("불완전 재발송: %v — 스탬프만 건너뛰고 발송 자체는 오늘 경로로 성립해야 한다", err)
	}
	if resent.TemplateVersion != ver || !reflect.DeepEqual(resent.Vars, first.Vars) {
		t.Errorf("불완전 재발송이 기존 스탬프를 파괴했다: version=%q, vars 변화=%v",
			resent.TemplateVersion, !reflect.DeepEqual(resent.Vars, first.Vars))
	}
	if resent.SentAt == nil || first.SentAt == nil || !resent.SentAt.After(*first.SentAt) {
		t.Errorf("재발송인데 sent_at이 갱신되지 않았다: %v → %v", first.SentAt, resent.SentAt)
	}
}

// ② 서명 봉인: 저장된 스냅샷 그대로의 재계산과 일치해야 하고(변조 검출의 전제), Vars 없는
// 서명은 아무것도 봉인하지 않는다(sha256 비어 있음 ⟺ 요약 고지 서명 — 거짓 신호 없음).
func TestContractSignSealsStampAndLegacySealsNothing(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	withIssuableContractVariants(t)
	seedContractBusiness(t, s)
	seedFacility(t, s, domain.FacilityStatusReported, "제2026-강남-0001호", "서울보증 1억")
	mem, pass := seedMemberWithPass(t, s, 10)
	recordSplitPayment(t, s, mem.ID, pass.ID)
	c := autoContractOf(t, s, mem.ID)
	if _, err := s.SendContract(ctx, ownerP(), c.ID); err != nil {
		t.Fatal(err)
	}
	signed, err := s.SignContract(ctx, memberP(mem.ID), c.ID, "1.2.3.4", nil)
	if err != nil {
		t.Fatalf("서명: %v", err)
	}
	if want := contractSeal(signed.TemplateVersion, signed.Vars); signed.SHA256 != want || len(signed.SHA256) != 64 {
		t.Errorf("봉인 = %q, want 재계산 %q", signed.SHA256, want)
	}
	saved, err := s.store.GetContract(ctx, testCenter, c.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.SHA256 != signed.SHA256 {
		t.Error("저장본 봉인이 응답과 다르다")
	}

	// Vars 없는 서명(래치 ON이지만 이 계약은 스탬프된 적 없음 — 사업자 정보가 비어 재발송이
	// 전부 스킵된 시나리오): 봉인 없음.
	mem2 := seedMemberOnly(t, s, "이서연", "010-9999-8888")
	pass2 := seedBarePass(t, s, mem2.ID, domain.PassStatusActive)
	c2, err := s.CreateContract(ctx, ownerP(), ContractCreateRequest{MemberID: mem2.ID, PassID: pass2.ID})
	if err != nil {
		t.Fatal(err)
	}
	blank := domain.Business{} // 사업자 정보가 통째로 비워진 센터
	if err := s.store.SaveBusiness(ctx, testCenter, &blank); err != nil {
		t.Fatal(err)
	}
	sent2, err := s.SendContract(ctx, ownerP(), c2.ID)
	if err != nil {
		t.Fatalf("발송: %v", err)
	}
	if sent2.TemplateVersion != "" || len(sent2.Vars) != 0 {
		t.Fatalf("사업자 정보 없는 발송이 스탬프됐다: %q %v", sent2.TemplateVersion, sent2.Vars)
	}
	signed2, err := s.SignContract(ctx, memberP(mem2.ID), c2.ID, "5.6.7.8", nil)
	if err != nil {
		t.Fatalf("서명: %v", err)
	}
	if signed2.SHA256 != "" {
		t.Errorf("Vars 없는 서명에 봉인이 생겼다: %q", signed2.SHA256)
	}
}

// ③ 상태별 선택 매트릭스(P42, latch-on 픽스처): 같은 완전 재료(사업자 6칸 + 결제 기록)에서
// 신고 상태만 바꾸면 — unknown은 스킵(발송 자체는 성립), reported는 25종(신고번호 포함),
// exempt는 24종(신고번호 키 부재) + 보증보험 미입력 폴백이 찍힌다.
func TestContractStampVariantMatrix(t *testing.T) {
	seed := func(t *testing.T, s *Service) *domain.Contract {
		t.Helper()
		seedContractBusiness(t, s)
		mem, pass := seedMemberWithPass(t, s, 10)
		recordSplitPayment(t, s, mem.ID, pass.ID)
		return autoContractOf(t, s, mem.ID)
	}

	t.Run("unknown은 발송은 되고 스탬프만 스킵", func(t *testing.T) {
		s := newTestService()
		withIssuableContractVariants(t)
		c := seed(t, s) // 시설 미선언 — 저장소 기본값 unknown
		sent, err := s.SendContract(context.Background(), ownerP(), c.ID)
		if err != nil {
			t.Fatalf("재발송: %v — unknown 스킵은 발송을 막지 않아야 한다(래치·결측 스킵과 같은 제3의 길)", err)
		}
		if sent.TemplateVersion != "" || len(sent.Vars) != 0 {
			t.Fatalf("unknown인데 스탬프됐다: %q %d키 — 모르는 상태로 문서를 만들지 않는다(P42)", sent.TemplateVersion, len(sent.Vars))
		}
	})

	t.Run("unknown은 번호·보험이 남아 있어도 스킵", func(t *testing.T) {
		// unknown인데 번호가 채워진 문서(손편집·마이그레이션 잔재) — 결측 스킵이 아니라 상태
		// 스킵이 막아야 하는 케이스다. 이 구분이 없으면 "unknown → reported로 폴백" 퇴행이
		// 신고번호 결측에 가려져 완전 재료 센터에서만 터진다(미선언 센터에 신고 계약서 발행).
		s := newTestService()
		withIssuableContractVariants(t)
		seedFacility(t, s, domain.FacilityStatusUnknown, "제2026-강남-0001호", "서울보증 1억")
		c := seed(t, s)
		sent, err := s.SendContract(context.Background(), ownerP(), c.ID)
		if err != nil {
			t.Fatal(err)
		}
		if sent.TemplateVersion != "" || len(sent.Vars) != 0 {
			t.Fatalf("unknown(번호 잔존)인데 스탬프됐다: %q %d키 — 상태 선언 없이 문서가 나갔다", sent.TemplateVersion, len(sent.Vars))
		}
	})

	t.Run("reported는 25종에 신고번호 포함", func(t *testing.T) {
		s := newTestService()
		verReported, _ := withIssuableContractVariants(t)
		seedFacility(t, s, domain.FacilityStatusReported, "제2026-강남-0001호", "서울보증 1억")
		c := seed(t, s)
		sent, err := s.SendContract(context.Background(), ownerP(), c.ID)
		if err != nil {
			t.Fatal(err)
		}
		if sent.TemplateVersion != verReported || len(sent.Vars) != len(contractPTv1ReportedVarKeys) {
			t.Fatalf("reported 스탬프 = (%q, %d키), want (%q, %d키)",
				sent.TemplateVersion, len(sent.Vars), verReported, len(contractPTv1ReportedVarKeys))
		}
		if got := sent.Vars["체육시설업 신고번호"]; got != "제2026-강남-0001호" {
			t.Errorf("신고번호 = %q, want 선언값", got)
		}
	})

	t.Run("exempt는 24종에 신고번호 없음 + 보증보험 폴백", func(t *testing.T) {
		s := newTestService()
		_, verExempt := withIssuableContractVariants(t)
		seedFacility(t, s, domain.FacilityStatusExempt, "", "") // 미가입 — 빈 값이 정직한 상태
		c := seed(t, s)
		sent, err := s.SendContract(context.Background(), ownerP(), c.ID)
		if err != nil {
			t.Fatal(err)
		}
		if sent.TemplateVersion != verExempt || len(sent.Vars) != len(contractPTv1ExemptVarKeys) {
			t.Fatalf("exempt 스탬프 = (%q, %d키), want (%q, %d키)",
				sent.TemplateVersion, len(sent.Vars), verExempt, len(contractPTv1ExemptVarKeys))
		}
		if _, ok := sent.Vars["체육시설업 신고번호"]; ok {
			t.Error("exempt 스탬프에 신고번호가 끼었다 — :818 '행을 뺀다'가 깨졌다")
		}
		if got := sent.Vars["보증보험 종류·보장내용"]; got != "가입하지 않았습니다" {
			t.Errorf("보증보험 빈 값 = %q, want 가입하지 않았습니다(제20조③ 자체 설계)", got)
		}
		if got := sent.Vars["약관 게시 주소"]; got != "https://rize-218c1.web.app/legal/terms.html" {
			t.Errorf("약관 게시 주소 = %q, want 서버 상수", got)
		}
	})
}

// ① × ③: 래치 OFF 구성에서는 신고 상태를 무엇으로 선언해도 스탬프가 없다 — 상태 선택은
// 래치와 **합성**이지 대체가 아니다(P42). reported의 깊은 검증(서명·봉인까지)은
// TestContractLatchOffStampsNothing이 맡고, 여기는 세 상태의 무스탬프만 훑는다.
// (P48 — 픽스처로 OFF를 만든다. 서브테스트마다 적용해 Cleanup 범위를 좁게 유지한다.)
func TestContractLatchOffNeverStampsAnyStatus(t *testing.T) {
	for _, c := range []struct{ status, reportNo string }{
		{domain.FacilityStatusUnknown, ""},
		{domain.FacilityStatusReported, "제2026-강남-0001호"},
		{domain.FacilityStatusExempt, ""},
	} {
		t.Run(c.status, func(t *testing.T) {
			s := newTestService()
			withLatchOffContractVariants(t)
			seedContractBusiness(t, s)
			seedFacility(t, s, c.status, c.reportNo, "서울보증 1억")
			mem, pass := seedMemberWithPass(t, s, 10)
			recordSplitPayment(t, s, mem.ID, pass.ID)
			ct := autoContractOf(t, s, mem.ID)
			sent, err := s.SendContract(context.Background(), ownerP(), ct.ID)
			if err != nil {
				t.Fatal(err)
			}
			if sent.TemplateVersion != "" || len(sent.Vars) != 0 {
				t.Errorf("래치 OFF + %s인데 스탬프됐다: %q %d키", c.status, sent.TemplateVersion, len(sent.Vars))
			}
		})
	}
}

// latch-off 불변의 **스토어 접근 횟수** 절반(P42 연장, P48에서 픽스처화): 래치가 꺼져 있으면
// 재발송이 facility를 읽지도 않는다 — "추가 읽기 없이 종전 경로 그대로"(P39)가 새 게이트에서도
// 성립. 게이트 순서(래치 → facility 읽기 → 상태 선택)가 뒤집히면 여기서 잡힌다. 이 단언이
// 없으면 롤백 시 "스탬프는 안 하지만 읽기는 하는" 절반짜리 복귀를 아무도 못 본다.
func TestContractLatchOffReadsNoFacility(t *testing.T) {
	s, h := newHookedService(t)
	ctx := context.Background()
	withLatchOffContractVariants(t)
	seedContractBusiness(t, s)
	mem, pass := seedMemberWithPass(t, s, 10)
	recordSplitPayment(t, s, mem.ID, pass.ID)
	c := autoContractOf(t, s, mem.ID)

	h.reset()
	if _, err := s.SendContract(ctx, ownerP(), c.ID); err != nil {
		t.Fatal(err)
	}
	if got := h.callCount("GetFacility"); got != 0 {
		t.Errorf("래치 OFF 재발송이 GetFacility를 %d회 읽었다 — 스토어 접근 횟수까지 오늘과 같아야 한다", got)
	}

	// 대조군: 래치 ON이면 선택을 위해 정확히 1회 읽고, 조립은 그 값을 재사용한다(같은 문서
	// 2회 읽기 사이에 저장이 끼는 창 제거). 0 단언이 공허하지 않다는 증명(카운터 생존 확인)도 겸한다.
	withIssuableContractVariants(t)
	seedFacility(t, s, domain.FacilityStatusReported, "제2026-강남-0001호", "서울보증 1억")
	h.reset()
	if _, err := s.SendContract(ctx, ownerP(), c.ID); err != nil {
		t.Fatal(err)
	}
	if got := h.callCount("GetFacility"); got != 1 {
		t.Errorf("래치 ON 재발송의 GetFacility = %d회, want 1(선택 1회 + 조립 재사용)", got)
	}
}
