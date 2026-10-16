package api

import (
	"context"
	"errors"
	"sync"
	"testing"
)

// 체형사진 메타 POST는 **같은 storage_path면 같은 레코드**다(P76 — P74 반박이 짚은 HEAD부터의 결함).
//
// 앱은 Storage 업로드가 끝난 뒤 메타 POST가 실패하면 **같은 경로로 POST만 다시** 한다(camera_view_model
// pendingRetry — 고아 파일을 만들지 않으려고 경로를 재사용한다). 그런데 첫 POST가 서버에선 커밋되고
// 응답만 잃었다면(지하철·엘리베이터) 재시도가 레코드를 하나 더 만들었다: 파일 하나를 레코드 둘이
// 가리키고, 하나를 지우면 파기가 파일을 지워 남은 하나가 영구 실패 타일("사진 파일을 찾지 못했어요")이 된다.

func validPhotoReq(memberID, file string) BodyPhotoCreateRequest {
	return BodyPhotoCreateRequest{
		MemberID: memberID, Pose: "stand", Direction: "front", Date: today(),
		StoragePath: "members/" + memberID + "/body/" + file,
	}
}

func TestCreateBodyPhotoRetryIsIdempotent(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)
	req := validPhotoReq(mem.ID, "20261016-stand-front-1760000000000.jpg")

	first, err := s.CreateBodyPhoto(ctx, memberP(mem.ID), req)
	if err != nil {
		t.Fatal(err)
	}
	again, err := s.CreateBodyPhoto(ctx, memberP(mem.ID), req) // 응답을 잃은 뒤의 재시도
	if err != nil {
		t.Fatalf("같은 경로 재시도가 실패했다(%v) — 앱은 재시도 실패를 사용자에게 보여 준다", err)
	}
	if again.ID != first.ID {
		t.Errorf("재시도 ID = %s, 처음 = %s — 같은 파일에 레코드가 둘이 됐다", again.ID, first.ID)
	}
	all, err := s.store.ListBodyPhotos(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 1 {
		t.Fatalf("레코드 %d개, want 1 — 같은 storage_path를 가리키는 메타가 중복됐다", len(all))
	}

	// 다른 사진(다른 경로)은 당연히 따로 생긴다 — 멱등이 과하게 합치지 않는다.
	if _, err := s.CreateBodyPhoto(ctx, memberP(mem.ID), validPhotoReq(mem.ID, "20261016-stand-side-1760000000001.jpg")); err != nil {
		t.Fatal(err)
	}
	if all, _ := s.store.ListBodyPhotos(ctx, testCenter, mem.ID); len(all) != 2 {
		t.Errorf("다른 경로 = 레코드 %d개, want 2", len(all))
	}
}

// 재시도가 첫 요청과 **동시에** 도착해도(첫 요청이 서버에서 느렸던 경우) 레코드는 하나다 — 확인 후 생성이
// 아니라 저장소의 "없을 때만 생성"으로 막아야 하는 자리.
func TestCreateBodyPhotoConcurrentDuplicatesMakeOneRecord(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)
	req := validPhotoReq(mem.ID, "20261016-stand-back-1760000000002.jpg")

	const n = 8
	var wg sync.WaitGroup
	ids := make([]string, n)
	errs := make([]error, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			bp, err := s.CreateBodyPhoto(ctx, memberP(mem.ID), req)
			errs[i] = err
			if bp != nil {
				ids[i] = bp.ID
			}
		}(i)
	}
	wg.Wait()
	for i := 0; i < n; i++ {
		if errs[i] != nil {
			t.Fatalf("동시 요청 %d: %v", i, errs[i])
		}
		if ids[i] != ids[0] {
			t.Fatalf("동시 요청이 서로 다른 레코드를 받았다: %s vs %s", ids[i], ids[0])
		}
	}
	if all, _ := s.store.ListBodyPhotos(ctx, testCenter, mem.ID); len(all) != 1 {
		t.Fatalf("레코드 %d개, want 1", len(all))
	}
}

// 같은 경로의 레코드가 이미 **삭제(유예)** 상태면 되살리지도 새로 만들지도 않고 409 — 스태프가 방금 지운
// 사진을 늦게 도착한 재시도가 다시 띄우면 안 된다.
func TestCreateBodyPhotoRetryAfterSoftDeleteConflicts(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)
	req := validPhotoReq(mem.ID, "20261016-tpose-front-1760000000003.jpg")
	bp, err := s.CreateBodyPhoto(ctx, memberP(mem.ID), req)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.DeleteBodyPhoto(ctx, trainerP(), bp.ID); err != nil { // 스태프 삭제 = 유예(소프트)
		t.Fatal(err)
	}
	if got, err := s.store.GetBodyPhoto(ctx, testCenter, bp.ID); err != nil || !got.IsDeleted() {
		t.Fatalf("전제: 스태프 삭제가 유예 상태여야 한다(%v, %+v)", err, got)
	}
	if _, err := s.CreateBodyPhoto(ctx, memberP(mem.ID), req); !errors.Is(err, ErrConflict) {
		t.Errorf("삭제된 경로로 재시도 = %v, want 409", err)
	}
	all, _ := s.store.ListBodyPhotos(ctx, testCenter, mem.ID)
	live := 0
	for _, p := range all {
		if !p.IsDeleted() {
			live++
		}
	}
	if live != 0 || len(all) != 1 {
		t.Errorf("레코드 %d개(살아 있는 것 %d) — 삭제된 사진이 되살아났거나 중복됐다", len(all), live)
	}
}

// 멱등은 **같은 요청**에만 — 같은 storage_path에 내용(회원·포즈·방향·날짜)이 다른 요청은 재시도가 아니라 클라이언트
// 오류라 409다(P76 반박: 종전 구현은 기존 레코드를 200으로 돌려줘 불일치를 숨겼다).
func TestCreateBodyPhotoSamePathDifferentContentConflicts(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)
	req := validPhotoReq(mem.ID, "20261016-stand-front-1760000000004.jpg")
	first, err := s.CreateBodyPhoto(ctx, memberP(mem.ID), req)
	if err != nil {
		t.Fatal(err)
	}
	other := req
	other.Direction = "side"
	if _, err := s.CreateBodyPhoto(ctx, memberP(mem.ID), other); !errors.Is(err, ErrConflict) {
		t.Errorf("같은 경로·다른 방향 = %v, want 409", err)
	}
	saved, err := s.store.GetBodyPhoto(ctx, testCenter, first.ID)
	if err != nil || saved.Direction != "front" {
		t.Errorf("저장본 = %+v (%v) — 다른 내용의 요청이 기록을 바꿨다", saved, err)
	}
}
