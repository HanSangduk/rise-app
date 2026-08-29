package domain

// 인바디 값 범위 검증(v2.9).
//
// 왜 도메인에 두는가: 종전 CreateInbody는 요청의 6개 숫자를 **한 번도 보지 않고** 그대로
// 저장했다(service.go의 rec := &domain.Inbody{...} 대입). 여기에 회원 셀프 입력 폼이 붙으면
// 오타 한 번이 곧 차트 오염이고, 정정 수단은 v2.9의 DELETE 하나뿐이라 "들어오는 자리에서
// 막는다"가 유일하게 값싼 방어다.

import (
	"errors"
	"strings"
	"testing"
)

// validInbody — 통과해야 하는 기준값(실측 범위의 한가운데). 각 케이스는 여기서 한 필드만 흔든다.
func validInbody() Inbody {
	return Inbody{
		MemberID: "m1", Date: "2026-08-20",
		Weight: 70.5, SMM: 32.1, BFM: 12.8, PBF: 18.4, VFL: 6, BMR: 1560,
	}
}

func TestInbodyValidateAcceptsRealisticRecords(t *testing.T) {
	for name, rec := range map[string]Inbody{
		"기준값":             validInbody(),
		"마른 체형":           {Weight: 45.2, SMM: 19.8, BFM: 9.1, PBF: 20.1, VFL: 2, BMR: 1080},
		"근육량 많은 남성":       {Weight: 92.0, SMM: 45.5, BFM: 9.2, PBF: 10.0, VFL: 3, BMR: 2050},
		"고도비만":            {Weight: 140.0, SMM: 34.0, BFM: 62.0, PBF: 44.3, VFL: 20, BMR: 2200},
		"경계값(하한)":         {Weight: 20, SMM: 5, BFM: 1, PBF: 1, VFL: 1, BMR: 500},
		"SMM+BFM이 체중과 동일": {Weight: 60, SMM: 40, BFM: 20, PBF: 33.3, VFL: 5, BMR: 1400},
	} {
		if err := rec.Validate(); err != nil {
			t.Errorf("%s가 거부됐다: %v", name, err)
		}
	}
}

func TestInbodyValidateRejectsOutOfRange(t *testing.T) {
	// 각 케이스는 "왜 이 값이 실제로 들어오는가"를 함께 적는다 — 범위를 나중에 넓힐 때
	// 무엇을 다시 열어 주는지 알 수 있어야 한다.
	cases := []struct {
		name string
		mut  func(*Inbody)
	}{
		{"체중 음수(부호 오입력)", func(r *Inbody) { r.Weight = -5 }},
		{"체중 0(미입력이 0.0으로 직렬화)", func(r *Inbody) { r.Weight = 0 }},
		{"체중 상한 초과", func(r *Inbody) { r.Weight = 400 }},
		// 하한 바로 아래 — 교차 검증(SMM/BFM 대비)이 잡아 줄 수 없는 자리라 **개별 하한만이**
		// 막는다. 나머지 값을 최소로 낮춰 다른 규칙에 걸리지 않게 한다.
		{"체중 19.9(하한 바로 아래)", func(r *Inbody) { r.Weight, r.SMM, r.BFM = 19.9, 5, 1 }},
		{"SMM 0", func(r *Inbody) { r.SMM = 0 }},
		{"BFM 0", func(r *Inbody) { r.BFM = 0 }},
		{"PBF 0", func(r *Inbody) { r.PBF = 0 }},
		{"PBF 999(자릿수 오타)", func(r *Inbody) { r.PBF = 999 }},
		{"VFL 0", func(r *Inbody) { r.VFL = 0 }},
		{"VFL 100(770/970 결과지의 내장지방단면적 cm²를 레벨 칸에 옮겨 적음)", func(r *Inbody) { r.VFL = 100 }},
		{"BMR 0", func(r *Inbody) { r.BMR = 0 }},
		{"BMR 15600(0 하나 더)", func(r *Inbody) { r.BMR = 15600 }},
	}
	for _, c := range cases {
		rec := validInbody()
		c.mut(&rec)
		err := rec.Validate()
		if !errors.Is(err, ErrInvalidInbody) {
			t.Errorf("%s → err = %v, want ErrInvalidInbody", c.name, err)
		}
	}
}

// VFL 상한 초과는 "숫자가 크다"가 아니라 **다른 지표를 옮겨 적었다**는 신호다(770/970 결과지는
// 내장지방'단면적'(cm², 100 근처)을 인쇄하고 도메인 필드는 '레벨'(1~20)이다). 회원이 결과지에서
// 무엇을 찾아야 하는지 문구가 알려주지 않으면 같은 값을 다시 넣는다.
func TestInbodyValidateVFLHintMentionsLevel(t *testing.T) {
	rec := validInbody()
	rec.VFL = 100
	err := rec.Validate()
	if err == nil {
		t.Fatal("VFL=100이 통과했다")
	}
	for _, want := range []string{"레벨", "단면적"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("VFL 초과 문구에 %q가 없다: %q", want, err.Error())
		}
	}
}

// 교차 검증 — 개별 범위는 다 통과하는데 조합이 물리적으로 불가능한 경우.
// 체/제 오기(BFM 칸에 FFM=제지방량을 적음)가 바로 여기서 잡힌다: FFM은 보통 체중의 70~90%라
// 개별 범위는 태연히 통과하지만 SMM+BFM이 체중을 넘는다.
//
// 문구까지 함께 검증한다: 세 검사가 겹쳐서 잡는 값이 많아(SMM>체중이면 SMM+BFM도 당연히
// 체중을 넘는다) "거부됐다"만 보면 어느 검사가 살아 있는지 알 수 없다. 회원에게는 **어느 두 칸을
// 비교해 보라는 것인지**가 전부라, 잡은 검사에 맞는 문구가 나오는 것까지가 계약이다.
func TestInbodyValidateRejectsImpossibleCombinations(t *testing.T) {
	cases := []struct {
		name    string
		rec     Inbody
		wantMsg string
	}{
		{"SMM이 체중보다 큼", Inbody{Weight: 60, SMM: 70, BFM: 10, PBF: 16, VFL: 4, BMR: 1400},
			"골격근량(70kg)이 체중(60kg)보다 클 수 없어요"},
		{"SMM이 체중과 같음", Inbody{Weight: 60, SMM: 60, BFM: 5, PBF: 8, VFL: 4, BMR: 1400},
			"골격근량(60kg)이 체중(60kg)보다 클 수 없어요"},
		{"BFM이 체중보다 큼", Inbody{Weight: 60, SMM: 20, BFM: 70, PBF: 40, VFL: 8, BMR: 1400},
			"체지방량(70kg)이 체중(60kg)보다 클 수 없어요"},
		{"BFM이 체중과 같음", Inbody{Weight: 60, SMM: 20, BFM: 60, PBF: 40, VFL: 8, BMR: 1400},
			"체지방량(60kg)이 체중(60kg)보다 클 수 없어요"},
		// 개별로는 셋 다 체중보다 작아 합계 검사만이 잡는다 — 체/제 오기의 실제 모양이다.
		{"BFM 칸에 FFM(제지방량)을 적음", Inbody{Weight: 70, SMM: 32, BFM: 57, PBF: 18.4, VFL: 6, BMR: 1560},
			"체중(70kg)을 넘어요"},
		{"SMM+BFM이 체중 초과", Inbody{Weight: 70, SMM: 40, BFM: 35, PBF: 50, VFL: 6, BMR: 1560},
			"체중(70kg)을 넘어요"},
	}
	for _, c := range cases {
		err := c.rec.Validate()
		if !errors.Is(err, ErrInvalidInbody) {
			t.Errorf("%s → err = %v, want ErrInvalidInbody", c.name, err)
			continue
		}
		if !strings.Contains(err.Error(), c.wantMsg) {
			t.Errorf("%s → 문구 %q에 %q가 없다", c.name, err.Error(), c.wantMsg)
		}
	}
}

// 사용자 노출 문구 규약(util.go userMessage): sentinel의 "domain: " 라인은 걷히고 **한국어
// 설명 라인이 남아야** 한다. 설명을 붙이지 않으면 회원은 "잘못된 요청입니다"만 본다.
func TestInbodyValidateMessagesAreKorean(t *testing.T) {
	for _, rec := range []Inbody{
		{Weight: 0, SMM: 32, BFM: 12, PBF: 18, VFL: 6, BMR: 1560},
		{Weight: 70, SMM: 32, BFM: 12, PBF: 18, VFL: 6, BMR: 0},
		{Weight: 60, SMM: 70, BFM: 10, PBF: 16, VFL: 4, BMR: 1400},
	} {
		err := rec.Validate()
		if err == nil {
			t.Fatalf("%+v가 통과했다", rec)
		}
		msg := err.Error()
		stripped := ""
		for _, line := range strings.Split(msg, "\n") {
			if line == "" || strings.HasPrefix(line, "domain: ") {
				continue
			}
			stripped += line
		}
		if stripped == "" {
			t.Errorf("%+v → sentinel만 있고 사용자 문구가 없다: %q", rec, msg)
		}
	}
}
