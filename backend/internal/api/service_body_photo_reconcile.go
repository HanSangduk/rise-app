package api

import (
	"context"
	"sort"

	"github.com/ramsang/rise-backend/internal/domain"
)

// 버킷과 메타의 어긋남을 맞춘다(v2.15).
//
// **왜 필요한가.** 삭제는 Storage 먼저, 메타 나중이다(v2.14). Storage 삭제가 에러를
// 내면 메타가 남아 다음 훑기가 다시 시도한다 — 그 순서가 고아를 막는다. 그런데
// Storage 삭제가 **에러가 아니라 조용한 no-op**이면(예: `STORAGE_BUCKET` 미설정으로
// 파기 경계가 dev no-op이던 시기) 메타만 지워지고 파일이 남는다. 그러면 서버는
// 그 파일의 존재조차 모른다 — 메타에서 출발하는 어떤 경로로도 닿을 수 없다.
//
// 실제로 이 프로젝트에서 그 일이 있었고 회원 한 명의 버킷에 50개가 남았다. 배포된
// 개인정보처리방침은 삭제 시 파일을 함께 파기한다고 약속하므로, 이건 쓰레기가 아니라
// **고지와 어긋난 상태**다.
//
// ## 안전 규칙 — 이 함수가 지켜야 하는 것
//
//  1. **메타가 가리키는 파일은 절대 지우지 않는다.** 소프트 삭제(유예 중)도 포함한다 —
//     스태프가 되돌릴 수 있다고 약속한 사진의 파일을 지우면 복원이 빈 껍데기가 된다.
//  2. **기본은 조회만**([apply]=false). 되돌릴 수 없는 일이라 눈으로 먼저 본다.
//  3. **대표만**. 남의 버킷을 훑는 일이다.

// BodyPhotoReconcileResult — 훑기 결과.
type BodyPhotoReconcileResult struct {
	// StorageObjects — 이 회원 폴더의 오브젝트 수.
	StorageObjects int `json:"storage_objects"`
	// KnownPaths — 메타가 가리키는 경로 수(소프트 삭제 포함).
	KnownPaths int `json:"known_paths"`
	// Orphans — 메타가 없는 오브젝트 경로.
	Orphans []string `json:"orphans"`
	// Deleted — 실제로 지운 수. [apply]가 false면 0.
	Deleted int `json:"deleted"`
	// Applied — 실제로 지웠는가.
	Applied bool `json:"applied"`
}

// ReconcileBodyPhotos — 버킷에서 거꾸로 훑어 메타 없는 오브젝트를 찾고, [apply]면 지운다.
func (s *Service) ReconcileBodyPhotos(
	ctx context.Context, p Principal, memberID string, apply bool,
) (*BodyPhotoReconcileResult, error) {
	if !p.IsOwner() {
		return nil, ErrForbidden
	}
	if _, err := s.store.GetMember(ctx, p.CenterID, memberID); err != nil {
		return nil, err
	}

	objects, err := s.media.ListObjects(ctx, domain.BodyPhotoPrefix(memberID))
	if err != nil {
		return nil, err
	}

	// **소프트 삭제된 것도 넣는다.** 유예 중인 사진은 복원될 수 있고, 복원된 사진이
	// 가리키는 파일이 없으면 그 복원은 빈 껍데기다.
	metas, err := s.store.ListBodyPhotos(ctx, p.CenterID, memberID)
	if err != nil {
		return nil, err
	}
	known := make(map[string]struct{}, len(metas))
	for _, m := range metas {
		if m.StoragePath != "" {
			known[m.StoragePath] = struct{}{}
		}
	}

	out := &BodyPhotoReconcileResult{
		StorageObjects: len(objects),
		KnownPaths:     len(known),
		Orphans:        []string{},
	}
	for _, o := range objects {
		if _, ok := known[o]; !ok {
			out.Orphans = append(out.Orphans, o)
		}
	}
	sort.Strings(out.Orphans)

	if !apply || len(out.Orphans) == 0 {
		return out, nil
	}
	n, err := s.media.DeleteObjects(ctx, out.Orphans)
	out.Deleted = n
	out.Applied = true
	if err != nil {
		// 부분 삭제로 끝났다 — 몇 개를 지웠는지는 돌려주고 실패도 함께 알린다.
		// 멱등이라 다시 부르면 남은 것만 지운다.
		return out, err
	}
	return out, nil
}
