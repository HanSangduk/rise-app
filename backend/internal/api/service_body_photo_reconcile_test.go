package api

import (
	"context"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// 고아 파일 훑기(v2.15).
//
// **이 엔드포인트는 프로덕션 파일을 지운다.** 그래서 "지운다"보다 **"무엇을 지키는가"**를
// 먼저 잠근다: 메타가 가리키는 파일은 어떤 경우에도 손대지 않는다.

func seedPhotoAt(t *testing.T, s *Service, memberID, pose, path string) *domain.BodyPhoto {
	t.Helper()
	bp := &domain.BodyPhoto{
		MemberID: memberID, Pose: pose, Direction: "front",
		Date: "2026-08-27", StoragePath: path,
	}
	if _, err := s.store.CreateBodyPhoto(context.Background(), testCenter, bp); err != nil {
		t.Fatalf("CreateBodyPhoto: %v", err)
	}
	return bp
}

func TestReconcileFindsOrphansWithoutDeleting(t *testing.T) {
	// 기본은 **조회만**이다. 되돌릴 수 없는 일이라 눈으로 먼저 본다.
	ctx := context.Background()
	purger := &recordingPurger{}
	s := newTestService().WithMediaPurger(purger)
	mem := consentingMember(t, s)

	live := domain.BodyPhotoPrefix(mem.ID) + "20260823-stand-front-1.jpg"
	orphan := domain.BodyPhotoPrefix(mem.ID) + "20260827-ohsquat-front-2.jpg"
	purger.objects = []string{live, orphan}
	seedPhotoAt(t, s, mem.ID, "stand", live)

	res, err := s.ReconcileBodyPhotos(ctx, ownerP(), mem.ID, false)
	if err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if res.StorageObjects != 2 || res.KnownPaths != 1 {
		t.Fatalf("집계가 틀렸다: %+v", res)
	}
	if len(res.Orphans) != 1 || res.Orphans[0] != orphan {
		t.Fatalf("고아 = %v, want [%s]", res.Orphans, orphan)
	}
	if res.Applied || res.Deleted != 0 || len(purger.deleted) != 0 {
		t.Fatal("apply를 주지 않았는데 지웠다")
	}
}

func TestReconcileAppliesOnlyToOrphans(t *testing.T) {
	ctx := context.Background()
	purger := &recordingPurger{}
	s := newTestService().WithMediaPurger(purger)
	mem := consentingMember(t, s)

	live := domain.BodyPhotoPrefix(mem.ID) + "live.jpg"
	orphan := domain.BodyPhotoPrefix(mem.ID) + "orphan.jpg"
	purger.objects = []string{live, orphan}
	seedPhotoAt(t, s, mem.ID, "stand", live)

	res, err := s.ReconcileBodyPhotos(ctx, ownerP(), mem.ID, true)
	if err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if !res.Applied || res.Deleted != 1 {
		t.Fatalf("삭제 결과가 틀렸다: %+v", res)
	}
	if len(purger.deleted) != 1 || purger.deleted[0] != orphan {
		t.Fatalf("지운 것 = %v — 살아 있는 사진을 건드리면 안 된다", purger.deleted)
	}
}

func TestReconcileKeepsSoftDeletedFiles(t *testing.T) {
	// **가장 중요한 규칙이다.** 스태프 삭제는 30일간 복원 가능하다고 약속한다.
	// 유예 중인 사진의 파일을 지우면 그 복원은 **빈 껍데기**가 된다 — 메타는
	// 되살아나는데 가리키는 파일이 없다.
	ctx := context.Background()
	purger := &recordingPurger{}
	s := newTestService().WithMediaPurger(purger)
	mem := consentingMember(t, s)

	held := domain.BodyPhotoPrefix(mem.ID) + "soft-deleted.jpg"
	purger.objects = []string{held}
	bp := seedPhotoAt(t, s, mem.ID, "stand", held)

	// 스태프가 지운다 → 유예 중(메타는 남아 있다).
	if _, err := s.DeleteBodyPhoto(ctx, ownerP(), bp.ID); err != nil {
		t.Fatalf("DeleteBodyPhoto: %v", err)
	}

	res, err := s.ReconcileBodyPhotos(ctx, ownerP(), mem.ID, true)
	if err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if len(res.Orphans) != 0 {
		t.Fatalf("유예 중인 사진을 고아로 봤다: %v", res.Orphans)
	}
	if len(purger.deleted) != 0 {
		t.Fatal("복원할 수 있다고 약속한 사진의 파일을 지웠다")
	}

	// 복원이 실제로 성립하는지까지 확인한다.
	if _, err := s.RestoreBodyPhoto(ctx, ownerP(), bp.ID); err != nil {
		t.Fatalf("restore: %v", err)
	}
	list, _ := s.ListBodyPhotos(ctx, ownerP(), mem.ID)
	if len(list) != 1 {
		t.Fatalf("복원 후 %d장", len(list))
	}
}

func TestReconcileOwnerOnly(t *testing.T) {
	// 남의 버킷을 훑는 일이다.
	ctx := context.Background()
	s := newTestService().WithMediaPurger(&recordingPurger{})
	mem := consentingMember(t, s)

	for name, p := range map[string]Principal{
		"회원":  memberP(mem.ID),
		"트레이너": trainerP(),
	} {
		if _, err := s.ReconcileBodyPhotos(ctx, p, mem.ID, false); err == nil {
			t.Fatalf("%s가 훑기를 돌릴 수 있다", name)
		}
	}
}

func TestReconcileIgnoresOtherMembersFolder(t *testing.T) {
	// 앞머리가 회원별이라 남의 폴더는 애초에 목록에 오지 않아야 한다.
	prefix := domain.BodyPhotoPrefix("m1")
	if prefix != "members/m1/body/" {
		t.Fatalf("앞머리 = %q — storage.rules·앱 빌더와 어긋나면 훑기가 아무것도 못 찾는다", prefix)
	}
	if domain.BodyPhotoPrefix("m2") == prefix {
		t.Fatal("회원이 달라도 같은 앞머리가 나온다")
	}
}

func TestReconcileEmptyBucketIsNotAnError(t *testing.T) {
	// dev 모드(파기 경계가 no-op)에서도 500이 나면 안 된다.
	ctx := context.Background()
	s := newTestService().WithMediaPurger(&recordingPurger{})
	mem := consentingMember(t, s)

	res, err := s.ReconcileBodyPhotos(ctx, ownerP(), mem.ID, true)
	if err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if len(res.Orphans) != 0 || res.Deleted != 0 {
		t.Fatalf("빈 버킷인데 %+v", res)
	}
}

var _ = time.Now
