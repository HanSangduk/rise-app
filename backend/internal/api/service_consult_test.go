package api

// 재등록/상담 요청(계약 v2.20, P42) — 회원발 요청 큐의 권한·중복·스코프 경계.

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// seedConsultMember — 트레이너 담당 회원 하나(패스 없이 — 이 큐는 잔여 0·만료가 주 고객이라
// 패스 존재를 전제하지 않는다).
func seedConsultMember(t *testing.T, s *Service, name, trainerID string) *domain.Member {
	t.Helper()
	mem := &domain.Member{Name: name, TrainerID: trainerID, Status: domain.MemberStatusActive,
		Flags: []domain.MemberFlag{}}
	id, err := s.store.SaveMember(context.Background(), testCenter, mem)
	if err != nil {
		t.Fatal(err)
	}
	mem.ID = id
	return mem
}

func TestCreateConsultRequest(t *testing.T) {
	t.Run("회원 본인이 재등록 요청을 보낸다 — pending으로 큐에 오른다", func(t *testing.T) {
		s := newTestService()
		mem := seedConsultMember(t, s, "김민지", "t1")

		cr, err := s.CreateConsultRequest(context.Background(), memberP(mem.ID),
			ConsultRequestBody{Kind: store.ConsultKindRenewal, Note: "다음 주부터 다시 하고 싶어요"})
		if err != nil {
			t.Fatal(err)
		}
		if cr.Status != store.ConsultPending || cr.MemberID != mem.ID || cr.Kind != store.ConsultKindRenewal {
			t.Fatalf("cr = %+v", cr)
		}
	})

	t.Run("pending이 살아 있는 동안 두 번째 요청은 409 — 연타로 큐가 쌓이지 않는다", func(t *testing.T) {
		s := newTestService()
		mem := seedConsultMember(t, s, "김민지", "t1")
		ctx := context.Background()
		if _, err := s.CreateConsultRequest(ctx, memberP(mem.ID),
			ConsultRequestBody{Kind: store.ConsultKindRenewal}); err != nil {
			t.Fatal(err)
		}
		_, err := s.CreateConsultRequest(ctx, memberP(mem.ID),
			ConsultRequestBody{Kind: store.ConsultKindConsult})
		if !errors.Is(err, ErrConflict) {
			t.Fatalf("err = %v, want ErrConflict", err)
		}
		// done 처리 후에는 다시 보낼 수 있다 — 재등록은 반복되는 일이다.
		list, _ := s.store.ListConsultRequests(ctx, testCenter, mem.ID)
		if _, err := s.DoneConsultRequest(ctx, ownerP(), list[0].ID); err != nil {
			t.Fatal(err)
		}
		if _, err := s.CreateConsultRequest(ctx, memberP(mem.ID),
			ConsultRequestBody{Kind: store.ConsultKindRenewal}); err != nil {
			t.Fatalf("done 이후 재요청 = %v, want 성공", err)
		}
	})

	t.Run("가드 — 스태프·매칭 전 회원·미지 kind·과길이 메모", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()
		body := ConsultRequestBody{Kind: store.ConsultKindRenewal}

		if _, err := s.CreateConsultRequest(ctx, ownerP(), body); !errors.Is(err, ErrForbidden) {
			t.Errorf("owner: %v, want ErrForbidden", err)
		}
		if _, err := s.CreateConsultRequest(ctx, trainerP(), body); !errors.Is(err, ErrForbidden) {
			t.Errorf("trainer: %v, want ErrForbidden", err)
		}
		// 매칭 전 회원(MemberID="") — 재등록할 대상 자체가 없다.
		unmatched := Principal{UID: "u-new", Role: domain.RoleMember, CenterID: testCenter}
		if _, err := s.CreateConsultRequest(ctx, unmatched, body); !errors.Is(err, ErrForbidden) {
			t.Errorf("매칭 전: %v, want ErrForbidden", err)
		}
		mem := seedConsultMember(t, s, "김민지", "t1")
		if _, err := s.CreateConsultRequest(ctx, memberP(mem.ID),
			ConsultRequestBody{Kind: "purchase"}); err == nil {
			t.Error("미지 kind: 통과했다, want 400")
		}
		if _, err := s.CreateConsultRequest(ctx, memberP(mem.ID),
			ConsultRequestBody{Kind: store.ConsultKindRenewal, Note: strings.Repeat("가", 201)}); err == nil {
			t.Error("201자 메모: 통과했다, want 400")
		}
	})
}

func TestListConsultRequests(t *testing.T) {
	t.Run("member는 자기 것만·이름 미포함, owner는 전체+이름, trainer는 담당만", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()
		mine := seedConsultMember(t, s, "김민지", "t1")  // t1 담당
		other := seedConsultMember(t, s, "이서연", "t2") // t2 담당
		for _, m := range []*domain.Member{mine, other} {
			if _, err := s.CreateConsultRequest(ctx, memberP(m.ID),
				ConsultRequestBody{Kind: store.ConsultKindRenewal}); err != nil {
				t.Fatal(err)
			}
		}

		asMember, err := s.ListConsultRequests(ctx, memberP(mine.ID))
		if err != nil {
			t.Fatal(err)
		}
		if len(asMember) != 1 || asMember[0].MemberID != mine.ID || asMember[0].MemberName != "" {
			t.Fatalf("member 스코프 = %+v", asMember)
		}

		asOwner, err := s.ListConsultRequests(ctx, ownerP())
		if err != nil {
			t.Fatal(err)
		}
		if len(asOwner) != 2 || asOwner[0].MemberName == "" {
			t.Fatalf("owner 스코프 = %+v, want 2건+이름", asOwner)
		}

		asTrainer, err := s.ListConsultRequests(ctx, trainerP()) // t1
		if err != nil {
			t.Fatal(err)
		}
		if len(asTrainer) != 1 || asTrainer[0].MemberID != mine.ID {
			t.Fatalf("trainer 스코프 = %+v, want 담당(김민지)만", asTrainer)
		}
	})
}

func TestDoneConsultRequest(t *testing.T) {
	t.Run("스태프가 처리 완료 — done→done은 멱등, 회원은 403, 타 담당 trainer는 403", func(t *testing.T) {
		s := newTestService()
		ctx := context.Background()
		mem := seedConsultMember(t, s, "김민지", "t1")
		cr, err := s.CreateConsultRequest(ctx, memberP(mem.ID),
			ConsultRequestBody{Kind: store.ConsultKindRenewal})
		if err != nil {
			t.Fatal(err)
		}

		if _, err := s.DoneConsultRequest(ctx, memberP(mem.ID), cr.ID); !errors.Is(err, ErrForbidden) {
			t.Fatalf("member done = %v, want ErrForbidden", err)
		}
		otherTrainer := Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}
		if _, err := s.DoneConsultRequest(ctx, otherTrainer, cr.ID); !errors.Is(err, ErrForbidden) {
			t.Fatalf("타 담당 trainer done = %v, want ErrForbidden", err)
		}

		done, err := s.DoneConsultRequest(ctx, trainerP(), cr.ID) // t1 — 담당
		if err != nil {
			t.Fatal(err)
		}
		if done.Status != store.ConsultDone {
			t.Fatalf("done = %+v", done)
		}
		// 멱등 — 두 스태프가 나눠 처리하는 데스크 동선(두 번째 누름이 헛확인을 만들지 않게).
		again, err := s.DoneConsultRequest(ctx, ownerP(), cr.ID)
		if err != nil || again.Status != store.ConsultDone {
			t.Fatalf("done 재호출 = %+v, %v", again, err)
		}

		if _, err := s.DoneConsultRequest(ctx, ownerP(), "creq_missing"); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("없는 ID = %v, want ErrNotFound", err)
		}
	})
}
