package api

import (
	"context"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// 체형사진 삭제(v2.13).
//
// **누가 눌렀느냐로 의미가 갈린다.** 회원 본인은 정보주체의 삭제권 행사라 배포된
// 개인정보처리방침("동의 철회, 삭제 요청 또는 탈퇴 시 **지체 없이** 파기")대로 즉시
// 파기해야 하고, 스태프는 운영 오조작이라 되돌릴 유예가 필요하다 — 잘못 지운 사진은
// 그날의 몸이라 다시 못 찍는다.

// recordingPurger — Storage 삭제 호출을 기록하고, 원하면 실패시킨다.
type recordingPurger struct {
	objects []string
	deleted []string
	fail    error
}

// 이 스위트는 훑기를 쓰지 않는다 — 버킷에 아무것도 없다고 답한다.
func (r *recordingPurger) ListObjects(_ context.Context, _ string) ([]string, error) {
	return r.objects, nil
}

func (r *recordingPurger) DeleteObjects(_ context.Context, paths []string) (int, error) {
	if r.fail != nil {
		return 0, r.fail
	}
	r.deleted = append(r.deleted, paths...)
	return len(paths), nil
}

func seedPhoto(t *testing.T, s *Service, memberID, pose string) *domain.BodyPhoto {
	t.Helper()
	bp := &domain.BodyPhoto{
		MemberID: memberID, Pose: pose, Direction: "front",
		Date: "2026-08-27", StoragePath: "members/" + memberID + "/body/" + pose + ".jpg",
	}
	if _, err := s.store.CreateBodyPhoto(context.Background(), testCenter, bp); err != nil {
		t.Fatalf("CreateBodyPhoto: %v", err)
	}
	return bp
}

func consentingMember(t *testing.T, s *Service) *domain.Member {
	t.Helper()
	seedTrainerRecord(t, s, "t1", "정혜린")
	mem, err := s.CreateMember(context.Background(), ownerP(), &domain.Member{
		Name: "김민지", Phone: "010-1234-5678", TrainerID: "t1",
		Status: domain.MemberStatusActive,
		// 민감정보 동의 없이는 조회 자체가 막힌다(P8).
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatalf("CreateMember: %v", err)
	}
	return mem
}

func TestMemberDeleteIsImmediatePurge(t *testing.T) {
	ctx := context.Background()
	purger := &recordingPurger{}
	s := newTestService().WithMediaPurger(purger)
	mem := consentingMember(t, s)
	bp := seedPhoto(t, s, mem.ID, "stand")

	if _, err := s.DeleteBodyPhoto(ctx, memberP(mem.ID), bp.ID); err != nil {
		t.Fatalf("DeleteBodyPhoto: %v", err)
	}

	// 방침이 "지체 없이 파기"라 유예가 있으면 안 된다.
	if _, err := s.store.GetBodyPhoto(ctx, testCenter, bp.ID); err == nil {
		t.Fatal("회원이 지웠는데 메타가 남아 있다 — 방침은 '지체 없이 파기'다")
	}
	if len(purger.deleted) != 1 || purger.deleted[0] != bp.StoragePath {
		t.Fatalf("Storage 파기 = %v, want [%s]", purger.deleted, bp.StoragePath)
	}
}

func TestStaffDeleteIsSoftWithGrace(t *testing.T) {
	ctx := context.Background()
	purger := &recordingPurger{}
	s := newTestService().WithMediaPurger(purger)
	mem := consentingMember(t, s)
	bp := seedPhoto(t, s, mem.ID, "stand")

	got, err := s.DeleteBodyPhoto(ctx, ownerP(), bp.ID)
	if err != nil {
		t.Fatalf("DeleteBodyPhoto: %v", err)
	}
	if got.DeletedAt == nil {
		t.Fatal("스태프 삭제인데 표시가 없다")
	}
	if len(purger.deleted) != 0 {
		t.Fatal("유예 없이 파일이 지워졌다 — 되돌릴 수 없게 된다")
	}

	// 화면에서는 **즉시** 사라져야 한다 — 유예는 되돌리기 위한 것이지 계속 보이라는 게 아니다.
	list, err := s.ListBodyPhotos(ctx, ownerP(), mem.ID)
	if err != nil {
		t.Fatalf("ListBodyPhotos: %v", err)
	}
	if len(list) != 0 {
		t.Fatalf("삭제한 사진이 목록에 %d장 남았다", len(list))
	}
}

func TestRestoreWithinGrace(t *testing.T) {
	ctx := context.Background()
	s := newTestService().WithMediaPurger(&recordingPurger{})
	mem := consentingMember(t, s)
	bp := seedPhoto(t, s, mem.ID, "stand")

	if _, err := s.DeleteBodyPhoto(ctx, ownerP(), bp.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := s.RestoreBodyPhoto(ctx, ownerP(), bp.ID); err != nil {
		t.Fatalf("restore: %v", err)
	}

	list, _ := s.ListBodyPhotos(ctx, ownerP(), mem.ID)
	if len(list) != 1 {
		t.Fatalf("복원 후 목록 %d장, want 1", len(list))
	}
}

func TestRestoreRefusedAfterGrace(t *testing.T) {
	// 기한이 지난 걸 되살리면 "30일 뒤 파기"가 거짓이 된다.
	ctx := context.Background()
	s := newTestService().WithMediaPurger(&recordingPurger{})
	mem := consentingMember(t, s)
	bp := seedPhoto(t, s, mem.ID, "stand")

	old := time.Now().UTC().Add(-domain.BodyPhotoPurgeAfter - time.Hour)
	bp.DeletedAt = &old
	if err := s.store.SaveBodyPhoto(ctx, testCenter, bp); err != nil {
		t.Fatalf("SaveBodyPhoto: %v", err)
	}

	if _, err := s.RestoreBodyPhoto(ctx, ownerP(), bp.ID); err == nil {
		t.Fatal("기한이 지난 사진이 복원됐다")
	}
}

func TestMemberCannotRestore(t *testing.T) {
	// 회원의 삭제는 즉시 파기라 되돌릴 대상이 없다 — 복원 경로가 열려 있으면
	// "지체 없이 파기"와 모순되는 문이 생긴다.
	ctx := context.Background()
	s := newTestService().WithMediaPurger(&recordingPurger{})
	mem := consentingMember(t, s)
	bp := seedPhoto(t, s, mem.ID, "stand")

	if _, err := s.DeleteBodyPhoto(ctx, ownerP(), bp.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := s.RestoreBodyPhoto(ctx, memberP(mem.ID), bp.ID); err == nil {
		t.Fatal("회원이 복원할 수 있다")
	}
}

func TestSweepPurgesAfterGrace(t *testing.T) {
	// 스케줄러가 없어 조회에 얹은 훑기가 유일한 바닥이다.
	ctx := context.Background()
	purger := &recordingPurger{}
	s := newTestService().WithMediaPurger(purger)
	mem := consentingMember(t, s)
	stale := seedPhoto(t, s, mem.ID, "stand")
	fresh := seedPhoto(t, s, mem.ID, "tpose")

	old := time.Now().UTC().Add(-domain.BodyPhotoPurgeAfter - time.Hour)
	stale.DeletedAt = &old
	if err := s.store.SaveBodyPhoto(ctx, testCenter, stale); err != nil {
		t.Fatalf("SaveBodyPhoto: %v", err)
	}

	if _, err := s.ListBodyPhotos(ctx, ownerP(), mem.ID); err != nil {
		t.Fatalf("ListBodyPhotos: %v", err)
	}

	if _, err := s.store.GetBodyPhoto(ctx, testCenter, stale.ID); err == nil {
		t.Fatal("기한이 지났는데 파기되지 않았다")
	}
	if _, err := s.store.GetBodyPhoto(ctx, testCenter, fresh.ID); err != nil {
		t.Fatal("살아 있는 사진까지 지웠다")
	}
	if len(purger.deleted) != 1 || purger.deleted[0] != stale.StoragePath {
		t.Fatalf("Storage 파기 = %v", purger.deleted)
	}
}

func TestStorageFailureKeepsMeta(t *testing.T) {
	// 메타를 먼저 지우면 오브젝트가 **기록 없이** 버킷에 영원히 남는다 —
	// 지웠다는 사실조차 추적할 수 없다. 다음 훑기가 다시 시도하도록 남긴다.
	ctx := context.Background()
	purger := &recordingPurger{fail: context.DeadlineExceeded}
	s := newTestService().WithMediaPurger(purger)
	mem := consentingMember(t, s)
	bp := seedPhoto(t, s, mem.ID, "stand")

	if _, err := s.DeleteBodyPhoto(ctx, memberP(mem.ID), bp.ID); err == nil {
		t.Fatal("Storage 삭제가 실패했는데 성공으로 돌아왔다")
	}
	if _, err := s.store.GetBodyPhoto(ctx, testCenter, bp.ID); err != nil {
		t.Fatal("Storage 삭제 실패인데 메타를 지웠다 — 오브젝트가 고아가 된다")
	}
}

func TestDeleteScope(t *testing.T) {
	ctx := context.Background()
	s := newTestService().WithMediaPurger(&recordingPurger{})
	mem := consentingMember(t, s)
	bp := seedPhoto(t, s, mem.ID, "stand")

	t.Run("다른 회원은 지울 수 없다", func(t *testing.T) {
		if _, err := s.DeleteBodyPhoto(ctx, memberP("other"), bp.ID); err == nil {
			t.Fatal("남의 사진을 지웠다")
		}
	})

	t.Run("동의를 철회하면 코치도 손댈 수 없다", func(t *testing.T) {
		// 배포된 방침이 담당 코치에 대해서도 "동의가 유효한 동안에만"이라고 적었다.
		fresh, err := s.store.GetMember(ctx, testCenter, mem.ID)
		if err != nil {
			t.Fatalf("GetMember: %v", err)
		}
		fresh.Consent.Sensitive = false
		if _, err := s.store.SaveMember(ctx, testCenter, fresh); err != nil {
			t.Fatalf("SaveMember: %v", err)
		}
		if _, err := s.DeleteBodyPhoto(ctx, trainerP(), bp.ID); err == nil {
			t.Fatal("동의 철회 후에도 코치가 사진에 접근했다")
		}
	})
}

var _ = store.ErrNotFound
