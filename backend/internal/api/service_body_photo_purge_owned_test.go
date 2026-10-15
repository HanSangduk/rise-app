package api

import (
	"context"
	"errors"
	"slices"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// 파기는 **그 회원 폴더 안의 파일만** 지운다(v2.38, P74 감사 후속). 생성 검사(BodyPhotoPathOwnedBy, 400)는
// 새 레코드만 막는다 — v2.38 이전에 저장된 레코드가 남의 경로를 가리키면 파기가 남의 파일을 지우는 원시
// 연산이 된다. 그런 레코드는 스토어에 직접 심어 재현한다(API로는 이제 만들 수 없다).

func plantBodyPhoto(t *testing.T, s *Service, memberID, path string) string {
	t.Helper()
	id, err := s.store.CreateBodyPhoto(context.Background(), testCenter, &domain.BodyPhoto{
		MemberID: memberID, Pose: "stand", Direction: "front", Date: today(), StoragePath: path,
	})
	if err != nil {
		t.Fatalf("CreateBodyPhoto: %v", err)
	}
	return id
}

func TestBodyPhotoPurgeDeletesOnlyOwnedFiles(t *testing.T) {
	s := newTestService()
	media := &recordingMedia{}
	s.WithMediaPurger(media)
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 10)
	ownPath := "members/" + mem.ID + "/body/20260820-stand-front-1755000000000.jpg"
	ownID := plantBodyPhoto(t, s, mem.ID, ownPath)
	foreignID := plantBodyPhoto(t, s, mem.ID, "staff/photos/coach-t1.jpg")

	for _, id := range []string{ownID, foreignID} {
		if _, err := s.DeleteBodyPhoto(ctx, memberP(mem.ID), id); err != nil { // 회원 삭제 = 즉시 파기
			t.Fatalf("DeleteBodyPhoto(%s): %v", id, err)
		}
	}
	if slices.Contains(media.paths, "staff/photos/coach-t1.jpg") {
		t.Errorf("파기가 회원 폴더 밖의 파일을 지웠다: %v", media.paths)
	}
	if !slices.Contains(media.paths, ownPath) {
		t.Errorf("본인 폴더의 파일은 지워야 한다: %v", media.paths)
	}
	for _, id := range []string{ownID, foreignID} {
		if _, err := s.store.GetBodyPhoto(ctx, testCenter, id); !errors.Is(err, store.ErrNotFound) {
			t.Errorf("메타 %s가 남았다(%v) — 폴더 밖이어도 레코드는 지운다", id, err)
		}
	}
}

func TestDeleteMyAccountDeletesOnlyOwnedPhotoFiles(t *testing.T) {
	s := newTestService()
	s.users = &recordingProvisioner{}
	media := &recordingMedia{}
	s.WithMediaPurger(media)
	ctx := context.Background()
	mem, _ := seedWithdrawableMember(t, s) // 본인 폴더 사진 1장을 품는다
	plantBodyPhoto(t, s, mem.ID, "staff/photos/coach-t1.jpg")

	if _, err := s.DeleteMyAccount(ctx, memberP(mem.ID)); err != nil {
		t.Fatalf("DeleteMyAccount: %v", err)
	}
	if slices.Contains(media.paths, "staff/photos/coach-t1.jpg") {
		t.Errorf("탈퇴 파기가 회원 폴더 밖의 파일을 지웠다: %v", media.paths)
	}
	if len(media.paths) != 1 || !domain.BodyPhotoPathOwnedBy(media.paths[0], mem.ID) {
		t.Errorf("지운 파일 = %v, want 본인 폴더 1장", media.paths)
	}
}
