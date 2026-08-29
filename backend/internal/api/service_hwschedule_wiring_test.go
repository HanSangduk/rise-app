package api

// 팀 간 인계 회귀(P12 감사).
//
// v2.3에서 `domain.ValidateHwSchedule`을 만들고 `HwSchedule` 판정을 계약에 명문화했지만,
// **CreateHomework가 그 함수를 부르지 않아** 검증이 매달려 있지 않았다. 도메인 단위 테스트는
// 통과하는데 실제 배정 경로는 그대로 열려 있는 상태 — 병렬 작업에서 가장 흔한 실패 모양이다.
//
// 도메인 함수 자체의 판정은 domain/hwschedule_test.go가 지킨다. 여기서 지키는 건 **연결**이다:
// 잘못된 스케줄이 API를 통과하지 못하고, 스토어에 닿기 전에 막히는가.

import (
	"context"
	"errors"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

func TestCreateHomeworkValidatesSchedule(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mine, _ := seedMemberWithPass(t, s, 20) // 담당 t1

	items := []domain.HwItem{{Name: "스쿼트", Sets: 3, Reps: "12"}}

	bad := []struct {
		name string
		sch  domain.HwSchedule
		why  string
	}{
		{
			name: "한글 type",
			sch:  domain.HwSchedule{Type: "매일매일", Days: []string{"월요일"}, From: "어제", To: "내일"},
			why:  "감사에서 이 값이 그대로 200으로 저장됐다",
		},
		{
			name: "한글 요일",
			sch:  domain.HwSchedule{Type: "weekly", Days: []string{"월"}},
			why:  "mon~sun 소문자 3글자가 아니면 앱과 서버 판정이 갈린다",
		},
		{
			name: "날짜 형식 불량",
			sch:  domain.HwSchedule{Type: "weekly", From: "2026-8-2"},
			why:  "YYYY-MM-DD가 아니면 구간 비교가 문자열 순서로 어긋난다",
		},
		{
			name: "기간 역전",
			sch:  domain.HwSchedule{Type: "weekly", From: "2026-09-01", To: "2026-08-01"},
			why:  "from > to면 어떤 날짜에도 유효하지 않은 배정이 저장된다",
		},
		{
			name: "once인데 수행일 없음",
			sch:  domain.HwSchedule{Type: "once"},
			why:  "종료일을 만들 수 없어 '한 번만'이 영구 노출된다",
		},
	}

	for _, c := range bad {
		t.Run(c.name, func(t *testing.T) {
			_, err := s.CreateHomework(ctx, trainerP(), HomeworkCreateRequest{
				Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{mine.ID},
				Items: items, Schedule: c.sch,
			})
			if !errors.Is(err, domain.ErrInvalidHwSchedule) {
				t.Fatalf("%s: err = %v, want ErrInvalidHwSchedule (%s)", c.name, err, c.why)
			}
		})
	}

	// 거부된 요청이 스토어에 흔적을 남기지 않아야 한다 — 배정은 회원 앱에 즉시 뜨는 데이터라
	// "저장은 됐는데 400"이면 유령 과제가 남는다.
	hws, err := s.ListHomeworks(ctx, trainerP(), "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(hws) != 0 {
		t.Fatalf("검증 실패한 배정이 저장됐다: %d건", len(hws))
	}

	// 과잉 차단 방지: 정상 스케줄은 그대로 통과한다.
	if _, err := s.CreateHomework(ctx, trainerP(), HomeworkCreateRequest{
		Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{mine.ID},
		Items: items, Schedule: domain.HwSchedule{Type: "weekly", Days: []string{"mon", "wed", "fri"}},
	}); err != nil {
		t.Fatalf("정상 weekly 배정이 거부됨: %v", err)
	}
	// 스케줄 미지정(레거시 호환)도 통과해야 한다 — 판정 규칙상 "항상 노출"이 정의돼 있다.
	if _, err := s.CreateHomework(ctx, trainerP(), HomeworkCreateRequest{
		Scope: domain.HwScopeIndividual, TargetMemberIDs: []string{mine.ID},
		Items: items,
	}); err != nil {
		t.Fatalf("스케줄 미지정 배정이 거부됨: %v", err)
	}
}
