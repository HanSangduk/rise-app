package api

// 인바디 날짜 검증 회귀(P12 감사).
//
// 같은 파일의 CreateWorkoutLog·ListHomeworks는 날짜를 검증하는데 CreateInbody만 빠져 있었다.
// 그래서 "2026-8-2" 같은 값이 그대로 저장됐고, 회원 앱이 그 레코드를 파싱하다 던져
// **기록 탭 세 개(운동·인바디·체형)가 통째로** 죽었다 — pull-to-refresh로도 복구 불가.
//
// 앱에도 스킵 가드를 넣었지만 그건 불량 데이터를 조용히 감추는 것이라, 그 인바디는 회원에게
// 영영 안 보인다. 들어오는 자리에서 막아야 원인이 남지 않는다.

import (
	"context"
	"errors"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

func TestCreateInbodyValidatesDate(t *testing.T) {
	s := newTestService()
	ctx := context.Background()

	seedTrainerRecord(t, s, "t1", "이담당")

	// 인바디는 P8 민감정보라 동의가 있어야 저장된다 — 날짜 검증에 닿기 전에 막히면 테스트가
	// 아무것도 지키지 못하므로, 동의를 갖춘 회원을 처음부터 만든다.
	mem, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "인바디회원", Phone: "010-2222-3333", TrainerID: "t1",
		Status:  domain.MemberStatusActive,
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatal(err)
	}

	bad := []struct{ date, why string }{
		{"2026-8-2", "감사에서 이 값이 그대로 저장됐고 앱 기록 탭 전체를 죽였다"},
		{"", "빈 날짜는 어떤 질의로도 찾을 수 없는 레코드가 된다"},
		{"2026/08/02", "구분자가 다르면 문자열 정렬이 시간순과 어긋난다"},
		{"오늘", "형식 검증이 없으면 무엇이든 통과한다"},
		{"2026-13-45", "달·일 범위도 함께 걸린다"},
	}
	for _, c := range bad {
		_, err := s.CreateInbody(ctx, trainerP(), InbodyCreateRequest{
			MemberID: mem.ID, Date: c.date, Weight: 70.5, SMM: 32.1, BFM: 12.8,
			PBF: 18.4, VFL: 6, BMR: 1560,
		})
		if !errors.Is(err, errBadRequest) {
			t.Fatalf("date=%q → err = %v, want 400 (%s)", c.date, err, c.why)
		}
	}

	// 거부된 요청이 레코드를 남기면 안 된다 — 앱이 죽는 원인이 그대로 저장되는 셈이다.
	list, err := s.ListInbody(ctx, trainerP(), mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 0 {
		t.Fatalf("검증 실패한 인바디가 저장됐다: %d건", len(list))
	}

	// 과잉 차단 방지: 정상 날짜는 통과하고 그대로 조회된다.
	// (v2.9부터 6지표가 모두 범위 검증을 받는다 — 픽스처도 완전한 레코드여야 한다)
	rec, err := s.CreateInbody(ctx, trainerP(), InbodyCreateRequest{
		MemberID: mem.ID, Date: "2026-08-02", Weight: 70.5, SMM: 32.1, BFM: 12.8,
		PBF: 18.4, VFL: 6, BMR: 1560,
	})
	if err != nil {
		t.Fatalf("정상 날짜가 거부됨: %v", err)
	}
	if rec.Date != "2026-08-02" {
		t.Fatalf("날짜가 변형됐다: %q", rec.Date)
	}
}
