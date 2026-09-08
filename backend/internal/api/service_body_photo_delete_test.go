package api

import (
	"context"
	"errors"
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
// calls는 DeleteObjects **호출 횟수**다(deleted와 별개) — 빈 슬라이스 호출(`DeleteObjects([]string{})`)은
// deleted에 아무것도 남기지 않아 "호출 자체가 없었다"와 구별되지 않는다(v2.31 퇴사 파기 테스트가 본다).
type recordingPurger struct {
	objects []string
	deleted []string
	fail    error
	// failOnce — 다음 한 번의 DeleteObjects만 실패시킨다(교체 ⑤의 "옛 파일 삭제 실패 → 새 파일 되지우기
	// 성공" 순서를 고정하려면 호출마다 다른 결과가 필요하다). 소비되면 nil로 돌아간다.
	failOnce error
	calls    int
}

// 이 스위트는 훑기를 쓰지 않는다 — 버킷에 아무것도 없다고 답한다.
func (r *recordingPurger) ListObjects(_ context.Context, _ string) ([]string, error) {
	return r.objects, nil
}

// 구성된 버킷의 대역이다 — 스태프 사진 경로가 "지운 척"을 건너뛰지 않도록 true(미구성은 unconfiguredPurger).
func (r *recordingPurger) Configured() bool { return true }

func (r *recordingPurger) DeleteObjects(_ context.Context, paths []string) (int, error) {
	r.calls++
	if r.fail != nil {
		return 0, r.fail
	}
	if r.failOnce != nil {
		err := r.failOnce
		r.failOnce = nil
		return 0, err
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
	listing, err := s.ListBodyPhotos(ctx, ownerP(), mem.ID, false)
	if err != nil {
		t.Fatalf("ListBodyPhotos: %v", err)
	}
	if len(listing.Full) != 0 {
		t.Fatalf("삭제한 사진이 목록에 %d장 남았다", len(listing.Full))
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

	listing, _ := s.ListBodyPhotos(ctx, ownerP(), mem.ID, false)
	if len(listing.Full) != 1 {
		t.Fatalf("복원 후 목록 %d장, want 1", len(listing.Full))
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

	if _, err := s.ListBodyPhotos(ctx, ownerP(), mem.ID, false); err != nil {
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

	t.Run("담당이 아닌 코치는 지울 수 없다", func(t *testing.T) {
		// 동의를 보지 않게 됐어도(v2.28) 스코프는 그대로다 — 남의 회원 사진을 지우는 문은 없다.
		other := Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}
		if _, err := s.DeleteBodyPhoto(ctx, other, bp.ID); !errors.Is(err, ErrForbidden) {
			t.Fatalf("담당 아닌 코치 삭제 = %v, want ErrForbidden", err)
		}
	})
}

// 동의 철회 **이후**의 삭제(v2.28, P56 B1).
//
// 종전 이 자리의 테스트는 정반대("동의를 철회하면 코치도 손댈 수 없다")를 고정하고 있었다.
// 그것은 **열람**에 대해서는 여전히 참이지만 파기까지 막으면 배포된 방침이 안내하는 경로
// ("철회 후 데스크에 삭제 요청")가 403이 된다 — 형제 동사 DeleteInbody는 *"삭제는 동의 철회
// 이후에 더 필요한 동작"*이라며 동의를 보지 않는다. 열람 게이트와 파기 게이트를 갈라 고정한다.
//
// **뮤테이션 표적**: DeleteBodyPhoto의 checkMemberScope를 checkBodyPhotoAccess로 되돌리면
// 여기서 죽는다.
func TestDeleteBodyPhotoAllowedAfterConsentWithdrawal(t *testing.T) {
	ctx := context.Background()
	purger := &recordingPurger{}
	s := newTestService().WithMediaPurger(purger)
	mem := consentingMember(t, s)
	byOwner := seedPhoto(t, s, mem.ID, "stand")
	byTrainer := seedPhoto(t, s, mem.ID, "tpose")

	// 회원이 앱에서 동의를 철회한다 — 실제 경로(PUT /v1/members/{id} consent.sensitive=false)를
	// 태워 서버가 revoked_at을 찍게 한다. 스토어를 직접 고치면 SensitiveConsentValid의 판정
	// 규칙(revoked_at)을 비켜가 테스트가 실제와 다른 상태를 본다.
	if _, err := s.UpdateMember(ctx, memberP(mem.ID), mem.ID, []byte(`{"consent":{"sensitive":false}}`)); err != nil {
		t.Fatalf("동의 철회: %v", err)
	}

	// 열람은 잠긴다 — 방침 "동의가 유효한 동안에만". 다만 403이 아니라 **메타만**(id·pose·date)의
	// 잠긴 목록이다(v2.28): 스태프가 지울 id를 얻을 길이 있어야 아래 삭제 경로가 실재한다.
	listing, err := s.ListBodyPhotos(ctx, ownerP(), mem.ID, false)
	if err != nil || !listing.Locked || listing.Full != nil || len(listing.Meta) != 2 {
		t.Fatalf("철회 후 대표 목록 = %+v, %v — want Locked 메타 2건(Full 없음)", listing, err)
	}
	ids := map[string]bool{}
	for _, m := range listing.Meta {
		ids[m.ID] = true
	}
	if !ids[byOwner.ID] || !ids[byTrainer.ID] {
		t.Fatalf("잠긴 목록이 지울 id를 안 준다: %+v", listing.Meta)
	}
	if tl, err := s.ListBodyPhotos(ctx, trainerP(), mem.ID, false); err != nil || !tl.Locked {
		t.Fatalf("철회 후 담당 코치 목록 = %+v, %v — want Locked", tl, err)
	}
	// 스코프 밖은 잠긴 목록도 없다 — 403 그대로.
	if _, err := s.ListBodyPhotos(ctx, Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}, mem.ID, false); !errors.Is(err, ErrForbidden) {
		t.Fatalf("철회 후 담당 아닌 코치 목록 = %v, want ErrForbidden", err)
	}

	// 파기는 열린다 — 방침이 안내하는 바로 그 경로다.
	got, err := s.DeleteBodyPhoto(ctx, ownerP(), byOwner.ID)
	if err != nil {
		t.Fatalf("철회 후 대표 삭제 = %v — 방침이 '철회 후 데스크에 삭제 요청'을 안내하는데 그 경로가 막혀 있다", err)
	}
	if got.DeletedAt == nil {
		t.Fatal("스태프 삭제인데 유예 표시가 없다 — 동의와 무관하게 스태프 삭제는 소프트다")
	}
	if _, err := s.DeleteBodyPhoto(ctx, trainerP(), byTrainer.ID); err != nil {
		t.Fatalf("철회 후 담당 코치 삭제 = %v", err)
	}

	// 스코프는 그대로 — 동의를 안 본다는 것이 남의 사진을 지울 수 있다는 뜻은 아니다.
	other := Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}
	if _, err := s.DeleteBodyPhoto(ctx, other, byOwner.ID); !errors.Is(err, ErrForbidden) {
		t.Fatalf("담당 아닌 코치 삭제 = %v, want ErrForbidden", err)
	}
	if _, err := s.DeleteBodyPhoto(ctx, memberP("someone-else"), byOwner.ID); !errors.Is(err, ErrForbidden) {
		t.Fatalf("다른 회원 삭제 = %v, want ErrForbidden", err)
	}

	// 회원 본인의 즉시 파기도 철회 상태에서 여전히 된다(본인 = 정보주체의 삭제권).
	third := seedPhoto(t, s, mem.ID, "ohsquat")
	if _, err := s.DeleteBodyPhoto(ctx, memberP(mem.ID), third.ID); err != nil {
		t.Fatalf("철회 후 본인 삭제 = %v", err)
	}
	if len(purger.deleted) != 1 || purger.deleted[0] != third.StoragePath {
		t.Fatalf("Storage 파기 = %v, want [%s] — 본인 삭제만 즉시 파기다", purger.deleted, third.StoragePath)
	}
}

var _ = store.ErrNotFound
