package api

// P43 — 데모 경로(DEV_SEED + 발행 래치 ON) 통합 테스트. main.go의 데모 블록이 하는 일을
// 그대로 재현한다: SeedDemo → EnableContractTemplatesForDemo → sent 전건 재발송. 이 테스트가
// 없으면 "데모에서 계약서 본문이 안 나온다"는 회귀(시드 값 결측·키 목록 드리프트·래치 훅
// 파손)를 어떤 테스트도 잡지 못한다 — 시드는 프로덕션 코드가 아니라는 이유로 테스트 사각이
// 되기 쉽지만, 영업 데모가 첫 화면에서 깨지는 것은 사각이어도 되는 실패가 아니다.
//
// 전역 레지스트리를 변이하므로 Cleanup 원복 필수(service_contract_stamp_test.go 픽스처 규약,
// api 패키지는 t.Parallel을 쓰지 않는다).

import (
	"context"
	"strings"
	"testing"

	"github.com/ramsang/rise-backend/internal/config"
	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

func TestDemoSeedStampsSentContracts(t *testing.T) {
	ctx := context.Background()
	st := store.NewMemory()
	if err := store.SeedDemo(ctx, st, testCenter); err != nil {
		t.Fatalf("SeedDemo: %v", err)
	}
	s := NewService(st, config.Config{DefaultCenterID: testCenter}, nil)

	// 배포 진실 확인이 먼저다 — 데모 훅을 켜기 **전** 레지스트리 리터럴의 현재 의도 상태를
	// 단언한다. P43에서는 그 상태가 "전부 OFF"(v2.18 래치 OFF 배포)였고, **P48(계약 v2.22)
	// 대표 결정으로 "두 변형 모두 ON"으로 뒤집혔다** — 단언의 값어치는 방향이 아니라 *리터럴이
	// 조용히 표류하지 않는다*는 데 있으므로, 방향만 갈아끼우고 보장은 유지한다(실수로 false로
	// 되돌아가면 여기서 죽는다 = 발행이 조용히 멈추는 사고를 데모 테스트가 먼저 잡는다).
	//
	// 부수 효과로 이 단언은 EnableContractTemplatesForDemo가 **이제 no-op**임을 문서화한다 —
	// 훅과 Cleanup 규율은 그대로 유지한다(래치를 되돌리면 훅이 다시 실효하고, 그때 이 테스트가
	// 레지스트리를 오염시킨 채 끝나면 안 된다).
	for _, ver := range []string{contractTemplatePTv1Reported, contractTemplatePTv1Exempt} {
		tpl, ok := contractTemplates[ver]
		if !ok {
			t.Fatalf("프로덕션 레지스트리에 %s가 없다", ver)
		}
		if !tpl.issuable {
			t.Fatalf("프로덕션 레지스트리 %s가 issuable=false — 발행 래치 ON(P48, 계약 v2.22)이 되돌려졌다", ver)
		}
	}
	prevReported := contractTemplates[contractTemplatePTv1Reported]
	prevExempt := contractTemplates[contractTemplatePTv1Exempt]
	t.Cleanup(func() {
		contractTemplates[contractTemplatePTv1Reported] = prevReported
		contractTemplates[contractTemplatePTv1Exempt] = prevExempt
	})
	EnableContractTemplatesForDemo()

	// main 데모 블록 그대로: sent 전건 재발송(owner1).
	owner := Principal{UID: "owner1", Role: domain.RoleOwner, CenterID: testCenter}
	sent, err := st.ListContracts(ctx, testCenter, "", string(domain.ContractStatusSent))
	if err != nil {
		t.Fatalf("ListContracts(sent): %v", err)
	}
	if len(sent) < 2 {
		t.Fatalf("시드 sent 계약이 %d건 — 데모 앱 계정(모빌리티)·가을(PT 10회) 최소 2건이어야 한다", len(sent))
	}
	for _, c := range sent {
		if _, err := s.SendContract(ctx, owner, c.ID); err != nil {
			t.Fatalf("데모 재발송 실패(%s %s): %v", c.Product, c.ID, err)
		}
	}

	all, err := st.ListContracts(ctx, testCenter, "", "")
	if err != nil {
		t.Fatalf("ListContracts: %v", err)
	}
	var mob, signedPT *domain.Contract
	stamped := 0
	for i := range all {
		c := &all[i]
		switch {
		case c.Product == "모빌리티 8회":
			mob = c
		case c.Status == domain.ContractStatusSigned:
			signedPT = c
		}
		if c.TemplateVersion != "" {
			stamped++
		}
	}
	if mob == nil || signedPT == nil {
		t.Fatalf("시드 표본 부재: 모빌리티=%v signed=%v", mob != nil, signedPT != nil)
	}
	if stamped != len(sent) {
		t.Fatalf("스탬프 %d건 ≠ sent %d건 — 재발송이 일부 계약을 건너뛰었다", stamped, len(sent))
	}

	// 데모 앱 계정(member1=김민지)의 sent 계약 — 시설이 reported이므로 reported 변형 완전 스탬프.
	if mob.TemplateVersion != contractTemplatePTv1Reported {
		t.Fatalf("모빌리티 계약 버전 = %q, want %q", mob.TemplateVersion, contractTemplatePTv1Reported)
	}
	if got, want := len(mob.Vars), len(contractPTv1ReportedVarKeys); got != want {
		t.Fatalf("Vars %d종, want %d종(reported 요구 키 전부)", got, want)
	}
	for slot, want := range map[string]string{
		"사업자명":          "라이즈 컨디셔닝",
		"보증보험 종류·보장내용": "가입하지 않았습니다", // 시드가 Insurance를 비워 폴백을 시연(제20조③)
		"체육시설업 신고번호":    "제2026-서울강남-0001호",
	} {
		if mob.Vars[slot] != want {
			t.Fatalf("Vars[%s] = %q, want %q", slot, mob.Vars[slot], want)
		}
	}
	// 납부일정 — 완납 1회차 + 미도래 2회차가 "납부완료"/"납부예정"으로 섞여 렌더되는 표본(P43).
	if sched := mob.Vars["납부일정"]; !strings.Contains(sched, "납부완료") || !strings.Contains(sched, "납부예정") {
		t.Fatalf("납부일정에 완료·예정이 섞여야 한다: %q", sched)
	}

	// signed(PT 20회, 레거시 요약 서명)는 무접촉 — 재발송 대상이 아니고(종단) 스탬프·봉인도 없다.
	if signedPT.TemplateVersion != "" || signedPT.Vars != nil || signedPT.SHA256 != "" {
		t.Fatalf("signed 계약이 오염됐다: ver=%q vars=%d sha=%q",
			signedPT.TemplateVersion, len(signedPT.Vars), signedPT.SHA256)
	}
}
