package api

// 퇴사 시 프로필 사진 파기(계약 v2.31, P62) 회귀 테스트.
//
// 이 파일이 지키는 것은 성격이 셋으로 갈린다:
//
//   - **파기 완전성**: 퇴사(deactivate)·사진 지우기(빈 photo_url PUT)·교체가 우리 파일(`staff/photos/`)을
//     실제로 지우고, 지운 경우에만 photo_url을 비운다. 빈 URL ⇔ 우리 파일 없음 — 이 불변식이 깨지면
//     privacy.html의 "퇴사 처리되면 사진 파일도 함께 삭제됩니다"가 거짓이 된다.
//   - **순서와 실패 정책**: 파기는 ①계정 잠금·②인덱스 강등 **뒤**, ④레코드 저장 **앞**이고 실패는 전파한다.
//     ①②가 실패하면 파일은 손대지 않아야 하고(삭제는 불가역), ③이 실패하면 status가 active로 남아
//     재시도가 멱등으로 수렴해야 한다. 이 순서는 실패 주입 없이는 어떤 테스트도 잡지 못한다 —
//     recordingProvisioner.failDisable · hookStore.SaveUserIndex · hookStore.SaveStaff가 그 수단이다.
//   - **경계 존중**: 외부 URL·다른 uid 명의 파일·다른 버킷은 파일도 포인터도 건드리지 않고(v2.31 개정 —
//     A의 퇴사가 B의 파일을 지우지 않는다), 퇴사자 앞으로는 새 파일을 만들지 않으며, 프로필 PUT은 우리 파일
//     포인터를 새로 만들 수 없다(stale URL 409).

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

// uploadStaffPhotoFixture — uid 앞으로 사진 하나를 올리고 그 오브젝트 경로를 돌려준다.
func uploadStaffPhotoFixture(t *testing.T, s *Service, up *recordingUploader, uid string) string {
	t.Helper()
	if _, err := s.UploadStaffPhoto(context.Background(), ownerP(), uid, photoReq(t, photoPNG(t, 200, 200), "image/png")); err != nil {
		t.Fatalf("UploadStaffPhoto(%s): %v", uid, err)
	}
	return up.uploads[len(up.uploads)-1].path
}

func mustGetStaff(t *testing.T, s *Service, uid string) *domain.Staff {
	t.Helper()
	st, err := s.store.GetStaff(context.Background(), testCenter, uid)
	if err != nil {
		t.Fatalf("GetStaff(%s): %v", uid, err)
	}
	return st
}

// ---- 퇴사(파기) ----

// 퇴사가 우리 파일을 지우고 포인터를 비우되, 다른 프로필 칸은 남긴다.
func TestDeactivateDeletesUploadedPhotoAndClearsURL(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	path := uploadStaffPhotoFixture(t, s, up, "t1")
	url := staffPhotoURL(t, s, "t1")
	// 어드민처럼 사진 URL을 그대로 되돌려 보내며 직함만 채운다(통 교체).
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: url, Title: "헤드 트레이너"}); err != nil {
		t.Fatal(err)
	}

	st, err := s.DeactivateStaff(ctx, ownerP(), "t1", "")
	if err != nil {
		t.Fatalf("DeactivateStaff: %v", err)
	}
	if len(pg.deleted) != 1 || pg.deleted[0] != path {
		t.Fatalf("퇴사 파기 = %v, want [%s] — 퇴사자 얼굴 사진이 버킷에 무기한 남는다(보존 근거 없음)", pg.deleted, path)
	}
	if st.Profile.PhotoURL != "" {
		t.Errorf("응답 photo_url = %q, want \"\" — 파일은 지웠는데 포인터가 살아 있으면 어드민 퇴사 행이 죽은 링크를 가리킨다", st.Profile.PhotoURL)
	}
	saved := mustGetStaff(t, s, "t1")
	if saved.Profile.PhotoURL != "" {
		t.Errorf("저장된 photo_url = %q, want \"\"", saved.Profile.PhotoURL)
	}
	if saved.Profile.Title != "헤드 트레이너" {
		t.Errorf("직함이 사라짐: %+v — 파기 대상은 사진뿐이다(재고용 시 경력을 다시 입력시킬 이유가 없다)", saved.Profile)
	}
	if saved.Status != domain.StaffStatusInactive || saved.LeftAt == nil {
		t.Errorf("status = %s, left_at = %v, want inactive + left_at", saved.Status, saved.LeftAt)
	}
}

// 명의 불일치(외부 URL·다른 폴더·다른 호스트·**다른 uid 명의**·**다른 버킷**)는 파일도 포인터도 건드리지
// 않는다 — 우리가 파기할 수 없는 것을 "삭제됨"처럼 보이게 하지 않고, 남의 오브젝트(회원 체형사진·재직자 B의
// 얼굴)는 절대 지우지 않는다. 픽스처는 프로필 PUT으로 심는다 — 이 URL들은 t1 명의가 아니라 PUT이 받아준다
// (우리 파일 포인터를 새로 만드는 것만 409다).
func TestDeactivateNeverDeletesForeignPhotoURL(t *testing.T) {
	ctx := context.Background()
	for _, prior := range []string{
		"https://cdn.example.com/old.jpg",
		"https://firebasestorage.googleapis.com/v0/b/test-bucket/o/members%2Fm1%2Fbody%2Ffront.jpg?alt=media&token=t",
		"https://evil.example.com/v0/b/test-bucket/o/staff%2Fphotos%2Fx.png?alt=media&token=t",
		// 재직자 t2 명의의 우리 파일 — 접두는 맞지만 t1의 것이 아니다.
		"https://firebasestorage.googleapis.com/v0/b/" + testPhotoBucket + "/o/staff%2Fphotos%2Ft2-ab12.png?alt=media&token=t",
		// t1 명의·우리 접두지만 다른 버킷 — 우리 버킷의 동명 파일을 지우게 된다.
		"https://firebasestorage.googleapis.com/v0/b/other-bucket/o/staff%2Fphotos%2Ft1-ab12.png?alt=media&token=t",
	} {
		s, _, pg := photoService(t)
		if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: prior}); err != nil {
			t.Fatal(err)
		}
		st, err := s.DeactivateStaff(ctx, ownerP(), "t1", "")
		if err != nil {
			t.Fatalf("DeactivateStaff(prior=%s): %v", prior, err)
		}
		if pg.calls != 0 {
			t.Fatalf("남의/외부 오브젝트에 삭제 호출(prior=%s): %v", prior, pg.deleted)
		}
		if st.Profile.PhotoURL != prior || mustGetStaff(t, s, "t1").Profile.PhotoURL != prior {
			t.Errorf("외부 URL이 비워짐(prior=%s): %q — 지우지 않은 것을 지운 것처럼 보이게 한다", prior, st.Profile.PhotoURL)
		}
	}
}

// A의 photo_url이 **재직자 B가 실제로 올린 파일**을 가리킬 때(대표가 URL을 복사해 붙여 넣으면 된다 —
// PUT은 http(s)면 무엇이든 받는다) A의 퇴사는 B의 파일을 지우지 않고 A의 포인터도 그대로 둔다.
// 접두만 보던 판정(v2.31 초판)은 여기서 B의 얼굴을 지웠다 — 이 테스트만이 "명의 결속 제거" 뮤턴트를
// 실제 업로드 파일로 잡는다. B의 프로필·파일은 무변경이어야 한다.
func TestDeactivateDoesNotDeleteAnotherStaffsUploadedPhoto(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	seedStaff(t, s, "t2", domain.RoleTrainer, "김민수")
	bPath := uploadStaffPhotoFixture(t, s, up, "t2")
	bURL := staffPhotoURL(t, s, "t2")
	// A(t1)의 프로필에 B의 URL을 붙여 넣는다 — t1 명의가 아니므로 PUT이 409 없이 받는다(외부 URL 취급).
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: bURL}); err != nil {
		t.Fatalf("B의 URL을 A에 PUT: %v", err)
	}

	st, err := s.DeactivateStaff(ctx, ownerP(), "t1", "")
	if err != nil {
		t.Fatalf("DeactivateStaff: %v", err)
	}
	if pg.calls != 0 {
		t.Fatalf("A의 퇴사가 B의 파일에 삭제 호출: %v (B 파일 %s) — B는 아무 동사도 부르지 않았다", pg.deleted, bPath)
	}
	if st.Profile.PhotoURL != bURL || mustGetStaff(t, s, "t1").Profile.PhotoURL != bURL {
		t.Errorf("A photo_url = %q, want 유지 %q — 지우지 않은 것을 지운 것처럼 보이게 한다", st.Profile.PhotoURL, bURL)
	}
	if got := staffPhotoURL(t, s, "t2"); got != bURL {
		t.Errorf("B photo_url = %q, want 무변경 %q", got, bURL)
	}
}

// 같은 시나리오의 프로필 PUT 동형 — A의 [사진 지우기](빈 photo_url PUT)가 B의 파일을 지우지 않는다.
// A의 포인터는 요청대로 비워진다(외부 URL을 지우는 것과 같은 취급 — 파일 삭제 호출은 없다).
func TestUpdateStaffProfileClearingAnotherStaffsURLDeletesNothing(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	seedStaff(t, s, "t2", domain.RoleTrainer, "김민수")
	uploadStaffPhotoFixture(t, s, up, "t2")
	bURL := staffPhotoURL(t, s, "t2")
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: bURL}); err != nil {
		t.Fatal(err)
	}
	st, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: ""})
	if err != nil {
		t.Fatalf("UpdateStaffProfile(지우기): %v", err)
	}
	if pg.calls != 0 {
		t.Fatalf("A의 지우기가 B의 파일에 삭제 호출: %v", pg.deleted)
	}
	if st.Profile.PhotoURL != "" {
		t.Errorf("A photo_url = %q, want \"\"(외부 URL 지우기와 같다)", st.Profile.PhotoURL)
	}
	if got := staffPhotoURL(t, s, "t2"); got != bURL {
		t.Errorf("B photo_url = %q, want 무변경", got)
	}
}

// stale PUT — 업로드 2회 뒤 **옛 URL**을 되돌려 보내면 409다. 받아주면 (a) 현재 파일을 지우고 (b) 이미
// 없는 옛 파일의 URL을 박아 죽은 링크가 된다. 프로필 PUT은 우리 파일 포인터를 새로 만들 수 없다 —
// 그것은 업로드 엔드포인트만 한다(통 교체 시맨틱의 유일한 예외, v2.31 개정). 파일·URL 무변경.
func TestUpdateStaffProfileStaleOurURLIs409AndDeletesNothing(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	uploadStaffPhotoFixture(t, s, up, "t1")
	oldURL := staffPhotoURL(t, s, "t1")
	second := uploadStaffPhotoFixture(t, s, up, "t1")
	newURL := staffPhotoURL(t, s, "t1")
	if len(pg.deleted) != 1 {
		t.Fatalf("교체 삭제 = %v, want 1건(픽스처 점검)", pg.deleted)
	}

	_, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: oldURL, Title: "헤드 트레이너"})
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("옛 URL PUT err = %v, want 409 — 현재 파일을 지우고 죽은 링크를 박는다", err)
	}
	if !strings.Contains(err.Error(), "새로고침") {
		t.Errorf("문구가 remedy(새로고침)를 말하지 않는다: %q", err)
	}
	if pg.calls != 1 {
		t.Errorf("409인데 삭제 호출이 늘었다(총 %d회): %v — 현재 파일 %s가 지워진다", pg.calls, pg.deleted, second)
	}
	saved := mustGetStaff(t, s, "t1")
	if saved.Profile.PhotoURL != newURL || saved.Profile.Title != "" {
		t.Errorf("409인데 프로필이 바뀜: %+v — 무변경이어야 한다", saved.Profile)
	}

	// 퇴사가 파기한 URL을 되돌려 보내는 것도 같은 409다(prev == "" · next == 우리 파일) — 파기의 역행 차단.
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: newURL}); !errors.Is(err, ErrConflict) {
		t.Errorf("파기된 URL 되살리기 err = %v, want 409", err)
	}
	if got := staffPhotoURL(t, s, "t1"); got != "" {
		t.Errorf("파기 후 photo_url = %q, want \"\"", got)
	}
}

// 라우터를 태워 409 본문을 본다 — 어드민은 서버 error 문구를 그대로 그리므로(api.ts req) 문구가 곧 remedy다.
func TestUpdateStaffProfileStaleURLWireIs409(t *testing.T) {
	r, svc, _ := newTestRouterSharing(t)
	up := &recordingUploader{}
	svc.WithMediaUploader(up).WithMediaPurger(&recordingPurger{})
	svc.cfg.StorageBucket = testPhotoBucket
	seedStaff(t, svc, "t1", domain.RoleTrainer, "정혜린")
	uploadStaffPhotoFixture(t, svc, up, "t1")
	oldURL := staffPhotoURL(t, svc, "t1")
	uploadStaffPhotoFixture(t, svc, up, "t1")

	body := fmt.Sprintf(`{"profile":{"photo_url":%q,"title":"","career_years":0,"specialties":[],"certifications":[],"awards":[],"bio":""}}`, oldURL)
	rec := putJSON(t, r, "/v1/staff/t1/profile", "owner1", domain.RoleOwner, body)
	if rec.Code != http.StatusConflict {
		t.Fatalf("stale PUT = %d %s, want 409", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "새로고침") {
		t.Errorf("409 본문이 remedy를 말하지 않는다: %s", rec.Body.String())
	}
}

// 프로필 PUT의 실패 창(계약 v2.31 PUT 절): 지우기의 삭제는 성공했는데 SaveStaff가 실패하면 파일은 없고
// URL은 남는다(재직자 → 앱 아바타 이니셜 폴백). **같은 PUT 재시도**가 수렴시킨다(재시도의 삭제는 실환경에서
// ErrObjectNotExist=성공, 그 뒤 저장). 같은 URL을 되돌려 보내는 일반 저장은 prev == next라 창을 닫지
// 않는다 — 그것도 여기서 고정한다.
func TestUpdateStaffProfileSaveFailureAfterDeleteConvergesOnRetry(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	h := newHookStore(s.store)
	s.store = h
	path := uploadStaffPhotoFixture(t, s, up, "t1") // SaveStaff n==1
	url := staffPhotoURL(t, s, "t1")

	boom := errors.New("firestore write failed")
	h.fail = func(op string, n int) error {
		if op == "SaveStaff" && n == 2 {
			return boom
		}
		return nil
	}
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: "", Title: "헤드 트레이너"}); !errors.Is(err, boom) {
		t.Fatalf("저장 실패가 삼켜졌다: %v", err)
	}
	if len(pg.deleted) != 1 || pg.deleted[0] != path {
		t.Fatalf("1차 삭제 = %v, want [%s](저장 앞에서 지운다)", pg.deleted, path)
	}
	if saved := mustGetStaff(t, s, "t1"); saved.Profile.PhotoURL != url || saved.Profile.Title != "" {
		t.Fatalf("1차 실패 후 프로필 = %+v, want URL 유지(죽은 링크 창)·직함 없음", saved.Profile)
	}

	// 같은 URL을 되돌려 보내는 일반 저장은 창을 닫지 않는다 — 삭제 호출도 없고 URL도 그대로다.
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: url, Title: "임시"}); err != nil {
		t.Fatal(err)
	}
	if len(pg.deleted) != 1 || staffPhotoURL(t, s, "t1") != url {
		t.Errorf("같은 URL 저장이 창을 건드림: deleted=%v url=%q", pg.deleted, staffPhotoURL(t, s, "t1"))
	}

	// 같은 지우기 PUT 재시도 → 수렴(recordingPurger는 NotExist를 모델링하지 않아 같은 경로가 2건 쌓인다).
	st, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: "", Title: "헤드 트레이너"})
	if err != nil {
		t.Fatalf("재시도 실패: %v", err)
	}
	if len(pg.deleted) != 2 || pg.deleted[1] != path {
		t.Errorf("재시도 삭제 = %v, want [%s %s]", pg.deleted, path, path)
	}
	if st.Profile.PhotoURL != "" || st.Profile.Title != "헤드 트레이너" {
		t.Errorf("재시도 후 프로필 = %+v, want photo_url \"\" + 직함", st.Profile)
	}
}

// 파기 실패는 **전파**된다(best-effort 아님): status는 active로 남고 URL은 유지되어 재시도 자격이
// 남는다. 이 시점엔 ②인덱스 강등이 끝나 사람은 이미 잠겨 있으므로 500이 보안을 늦추지 않는다.
// 재시도는 멱등으로 수렴한다.
func TestDeactivatePhotoDeleteFailurePropagates(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	path := uploadStaffPhotoFixture(t, s, up, "t1")
	url := staffPhotoURL(t, s, "t1")

	boom := errors.New("storage delete down")
	pg.fail = boom
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); !errors.Is(err, boom) {
		t.Fatalf("파기 실패가 삼켜졌다: err = %v — 재시도 동사 없이 '지체 없이 삭제' 고지가 거짓이 된다", err)
	}
	saved := mustGetStaff(t, s, "t1")
	if saved.Status != domain.StaffStatusActive || saved.LeftAt != nil {
		t.Errorf("파기 실패인데 status = %s — 재시도가 '이미 퇴사' 400에 막힌다", saved.Status)
	}
	if saved.Profile.PhotoURL != url {
		t.Errorf("파기 실패인데 photo_url = %q, want 유지 — 포인터를 잃으면 파일은 발견 경로 없는 고아가 된다", saved.Profile.PhotoURL)
	}
	if len(pg.deleted) != 0 {
		t.Errorf("실패한 삭제가 기록됨: %v", pg.deleted)
	}
	// ②까지는 끝나 있다 — 사람은 이미 잠겨 있다(안전한 방향의 잔여 상태).
	idx, err := s.store.GetUserIndex(ctx, "t1")
	if err != nil || idx.Role != domain.RoleMember {
		t.Errorf("UserIndex = %+v, err = %v — 파기 실패 시점에 이미 강등돼 있어야 한다(즉시 차단의 본체)", idx, err)
	}

	// 스토리지 복구 후 재시도 → 수렴.
	pg.fail = nil
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); err != nil {
		t.Fatalf("재시도 실패: %v", err)
	}
	saved = mustGetStaff(t, s, "t1")
	if saved.Status != domain.StaffStatusInactive || saved.Profile.PhotoURL != "" {
		t.Errorf("재시도 후 = status %s photo_url %q, want inactive + \"\"", saved.Status, saved.Profile.PhotoURL)
	}
	if len(pg.deleted) != 1 || pg.deleted[0] != path {
		t.Errorf("재시도 파기 = %v, want [%s]", pg.deleted, path)
	}
}

// 사진이 없으면 DeleteObjects를 부르지 않는다 — `DeleteObjects([""])` 같은 빈 호출을 만들지 않는다.
func TestDeactivateWithoutPhotoCallsNoDelete(t *testing.T) {
	s, _, pg := photoService(t)
	st, err := s.DeactivateStaff(context.Background(), ownerP(), "t1", "")
	if err != nil {
		t.Fatalf("DeactivateStaff: %v", err)
	}
	if pg.calls != 0 {
		t.Fatalf("사진 없는 퇴사가 DeleteObjects를 %d회 불렀다(deleted=%v)", pg.calls, pg.deleted)
	}
	if st.Status != domain.StaffStatusInactive {
		t.Errorf("status = %s, want inactive", st.Status)
	}
}

// 순서 ③파기→④저장의 실패 창: 파일은 지워졌는데 SaveStaff가 실패하면 URL이 죽은 링크로 남는다.
// 그 상태는 status가 아직 active라 재시도가 400에 막히지 않고, 재시도의 삭제가 성공(실환경에선
// ErrObjectNotExist=성공)하며 URL이 그때 비워진다 — 멱등으로 수렴한다. 반대 순서(저장 뒤 삭제)는
// 삭제 실패 시 포인터를 잃어 수렴 경로가 없다.
func TestDeactivateSaveFailureAfterDeleteConvergesOnRetry(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	// photoService 조립 뒤 스토어를 감싼다 — 업로드가 SaveStaff를 1회 먼저 부르므로 퇴사의 저장은 n==2다.
	h := newHookStore(s.store)
	s.store = h
	path := uploadStaffPhotoFixture(t, s, up, "t1")
	url := staffPhotoURL(t, s, "t1")

	boom := errors.New("firestore write failed")
	h.fail = func(op string, n int) error {
		if op == "SaveStaff" && n == 2 {
			return boom
		}
		return nil
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); !errors.Is(err, boom) {
		t.Fatalf("저장 실패가 삼켜졌다: %v", err)
	}
	if len(pg.deleted) != 1 || pg.deleted[0] != path {
		t.Fatalf("1차 파기 = %v, want [%s](저장 앞에서 지운다)", pg.deleted, path)
	}
	saved := mustGetStaff(t, s, "t1")
	if saved.Status != domain.StaffStatusActive {
		t.Fatalf("1차 실패 후 status = %s, want active(재시도 자격)", saved.Status)
	}
	if saved.Profile.PhotoURL != url {
		t.Fatalf("1차 실패 후 photo_url = %q, want 유지(죽은 링크 창 — 아바타는 이니셜로 폴백)", saved.Profile.PhotoURL)
	}

	// 재시도 → 수렴. recordingPurger는 ErrObjectNotExist를 모델링하지 않으므로 같은 경로가 2건 쌓인다.
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); err != nil {
		t.Fatalf("재시도 실패: %v", err)
	}
	if len(pg.deleted) != 2 || pg.deleted[1] != path {
		t.Errorf("재시도 파기 = %v, want [%s %s]", pg.deleted, path, path)
	}
	saved = mustGetStaff(t, s, "t1")
	if saved.Status != domain.StaffStatusInactive || saved.Profile.PhotoURL != "" {
		t.Errorf("재시도 후 = status %s photo_url %q, want inactive + \"\"", saved.Status, saved.Profile.PhotoURL)
	}
}

// ① 계정 잠금이 실패하면 사진은 손대지 않는다 — 삭제는 불가역이라 "퇴사가 실패했는데 사진만 사라진"
// 재직자를 만들면 안 된다. 이 테스트만이 "③을 ① 앞으로" 뮤턴트를 잡는다.
func TestDeactivateDisableUserFailureLeavesPhotoIntact(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	boom := errors.New("firebase disable down")
	s.users = &recordingProvisioner{failDisable: boom}
	uploadStaffPhotoFixture(t, s, up, "t1")
	url := staffPhotoURL(t, s, "t1")

	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); !errors.Is(err, boom) {
		t.Fatalf("DisableUser 실패가 삼켜졌다: %v", err)
	}
	if pg.calls != 0 {
		t.Fatalf("계정 잠금이 실패했는데 사진을 지웠다: %v — 재직 중인데 사진이 없어진다", pg.deleted)
	}
	saved := mustGetStaff(t, s, "t1")
	if saved.Profile.PhotoURL != url || saved.Status != domain.StaffStatusActive {
		t.Errorf("① 실패 후 = photo_url %q status %s, want 유지 + active(아무것도 안 바뀐 채 재시도)", saved.Profile.PhotoURL, saved.Status)
	}
	idx, err := s.store.GetUserIndex(ctx, "t1")
	if err != nil || idx.Role != domain.RoleTrainer {
		t.Errorf("① 실패인데 UserIndex = %+v — ②도 일어나지 않아야 한다", idx)
	}
}

// ② 인덱스 강등이 실패해도 같다 — 파일 무삭제·URL 유지·status active.
func TestDeactivateIndexDemotionFailureLeavesPhotoIntact(t *testing.T) {
	ctx := context.Background()
	up := &recordingUploader{}
	pg := &recordingPurger{}
	s, h := newHookedService(t)
	s.WithMediaUploader(up).WithMediaPurger(pg)
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	uploadStaffPhotoFixture(t, s, up, "t1")
	url := staffPhotoURL(t, s, "t1")

	boom := errors.New("firestore index write failed")
	h.fail = func(op string, _ int) error {
		if op == "SaveUserIndex" {
			return boom
		}
		return nil
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); !errors.Is(err, boom) {
		t.Fatalf("SaveUserIndex 실패가 삼켜졌다: %v", err)
	}
	if pg.calls != 0 {
		t.Fatalf("인덱스 강등이 실패했는데 사진을 지웠다: %v", pg.deleted)
	}
	saved := mustGetStaff(t, s, "t1")
	if saved.Profile.PhotoURL != url || saved.Status != domain.StaffStatusActive {
		t.Errorf("② 실패 후 = photo_url %q status %s, want 유지 + active", saved.Profile.PhotoURL, saved.Status)
	}
}

// 미구성 purger(STORAGE_BUCKET 없음·Storage 초기화 실패)는 DeleteObjects가 no-op 성공이다(탈퇴를 막지
// 않기 위한 정책). 그 성공을 믿고 URL을 비우던 초판(v2.31)은 **파일은 남고 포인터만 사라지는** 고아를
// 만들었다(P62 검증 이슈 5). 이제 Configured()를 보고 파기를 건너뛰며 photo_url을 **유지**한다 — 퇴사 자체는
// 진행된다(즉시 차단의 본체는 ①②). 뮤테이션 표적: purgeStaffPhoto의 Configured 분기를 없애면 여기서 죽는다.
func TestDeactivateWithUnconfiguredPurgerKeepsURL(t *testing.T) {
	ctx := context.Background()
	s := newTestService() // WithMediaPurger 없음 = unconfiguredPurger
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	const ours = "https://firebasestorage.googleapis.com/v0/b/b1/o/staff%2Fphotos%2Ft1-ab12.png?alt=media&token=x"
	seedStaffPhotoURL(t, s, "t1", ours)
	st, err := s.DeactivateStaff(ctx, ownerP(), "t1", "")
	if err != nil {
		t.Fatalf("미구성 purger에서 퇴사가 막혔다: %v — 버킷이 없다고 퇴사가 멈출 이유는 없다(v2.28 규율)", err)
	}
	if st.Status != domain.StaffStatusInactive {
		t.Errorf("status = %s, want inactive(파기를 건너뛰어도 퇴사는 진행)", st.Status)
	}
	if st.Profile.PhotoURL != ours || mustGetStaff(t, s, "t1").Profile.PhotoURL != ours {
		t.Errorf("미구성인데 photo_url = %q, want 유지 %q — 지우지 못한 파일의 유일한 발견 경로가 포인터다", st.Profile.PhotoURL, ours)
	}
}

// 프로필 PUT의 [사진 지우기]도 미구성이면 같다 — 삭제를 건너뛰고 포인터를 유지하되 나머지 칸은 저장된다.
func TestUpdateStaffProfileWithUnconfiguredPurgerKeepsURL(t *testing.T) {
	ctx := context.Background()
	s := newTestService()
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	const ours = "https://firebasestorage.googleapis.com/v0/b/b1/o/staff%2Fphotos%2Ft1-ab12.png?alt=media&token=x"
	seedStaffPhotoURL(t, s, "t1", ours)
	st, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: "", Title: "헤드 트레이너"})
	if err != nil {
		t.Fatalf("UpdateStaffProfile: %v", err)
	}
	if st.Profile.PhotoURL != ours || st.Profile.Title != "헤드 트레이너" {
		t.Errorf("미구성 지우기 결과 = %+v, want photo_url 유지 + 직함 저장", st.Profile)
	}
}

// ---- 업로드 가드 ----

// 퇴사자 앞으로는 새 파일을 만들지 않는다 — 파기의 역행 경로 차단. 업로드 전이라 파일이 생기지 않는다.
func TestUploadStaffPhotoRejectsInactiveStaff(t *testing.T) {
	ctx := context.Background()
	s, up, _ := photoService(t)
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); err != nil {
		t.Fatal(err)
	}
	_, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, photoPNG(t, 200, 200), "image/png"))
	if !errors.Is(err, errBadRequest) {
		t.Fatalf("퇴사자 업로드 err = %v, want 400 — 퇴사가 파기한 것을 실수 한 번으로 되살린다", err)
	}
	if !strings.Contains(err.Error(), "재입사") {
		t.Errorf("문구가 remedy(재입사)를 말하지 않는다: %q", err)
	}
	if len(up.uploads) != 0 {
		t.Errorf("400인데 파일이 생겼다: %v", up.uploads)
	}
	if got := staffPhotoURL(t, s, "t1"); got != "" {
		t.Errorf("photo_url = %q, want \"\"", got)
	}
}

// ---- 복직·재고용 ----

// 복직은 사진을 되살리지 않는다(파일도 없다). 다른 프로필 칸은 그대로 돌아온다.
func TestReactivateDoesNotRestorePhoto(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	uploadStaffPhotoFixture(t, s, up, "t1")
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: staffPhotoURL(t, s, "t1"), Title: "헤드 트레이너"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), "t1", ""); err != nil {
		t.Fatal(err)
	}
	st, err := s.ReactivateStaff(ctx, ownerP(), "t1")
	if err != nil {
		t.Fatalf("ReactivateStaff: %v", err)
	}
	if st.Profile.PhotoURL != "" {
		t.Errorf("복직 후 photo_url = %q, want \"\" — 파일이 없는데 URL이 돌아오면 깨진 이미지다", st.Profile.PhotoURL)
	}
	if st.Profile.Title != "헤드 트레이너" {
		t.Errorf("복직 후 직함 = %q, want 보존", st.Profile.Title)
	}
	if len(pg.deleted) != 1 {
		t.Errorf("복직이 삭제를 더 불렀다: %v", pg.deleted)
	}
	// 복직 뒤엔 업로드가 다시 열린다.
	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, photoPNG(t, 200, 200), "image/png")); err != nil {
		t.Errorf("복직 후 업로드 = %v, want 성공", err)
	}
}

// 재고용(같은 이메일 재초대 → rehireStaff)도 동일 — 프로필은 보존하되 사진은 퇴사 때 이미 비어 있다.
// uid는 devUserProvisioner의 이메일 해시 규칙을 따른다(seedStaff의 "t1"에는 닿지 않는다).
func TestRehireDoesNotRestorePhoto(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	seedStaff(t, s, "owner1", domain.RoleOwner, "박관장")
	const email = "hyerin@rise.kr"
	first, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{Name: "정혜린", Email: email, Role: domain.RoleTrainer})
	if err != nil {
		t.Fatal(err)
	}
	if want, _ := (devUserProvisioner{}).EnsureUser(ctx, email); first.UID != want {
		t.Fatalf("uid = %q, want %q(이메일 해시 — 재초대가 같은 uid로 돌아와야 재고용 경로를 탄다)", first.UID, want)
	}
	path := uploadStaffPhotoFixture(t, s, up, first.UID)
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), first.UID, domain.StaffProfile{PhotoURL: staffPhotoURL(t, s, first.UID), Title: "퍼포먼스 트레이너"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.DeactivateStaff(ctx, ownerP(), first.UID, ""); err != nil {
		t.Fatal(err)
	}
	if len(pg.deleted) != 1 || pg.deleted[0] != path {
		t.Fatalf("퇴사 파기 = %v, want [%s]", pg.deleted, path)
	}
	again, err := s.CreateStaff(ctx, ownerP(), domain.StaffCreate{Name: "정혜린", Email: email, Role: domain.RoleTrainer})
	if err != nil {
		t.Fatalf("재초대(재고용) 실패: %v", err)
	}
	if again.UID != first.UID || again.Status != domain.StaffStatusActive {
		t.Fatalf("재고용 결과 = %+v, want 같은 uid + active", again)
	}
	if again.Profile.PhotoURL != "" {
		t.Errorf("재고용 후 photo_url = %q, want \"\"", again.Profile.PhotoURL)
	}
	if again.Profile.Title != "퍼포먼스 트레이너" {
		t.Errorf("재고용 후 직함 = %q, want 보존", again.Profile.Title)
	}
}

// ---- 프로필 PUT의 파기 판정 ----

// 어드민 [사진 지우기] = 빈 photo_url PUT. 종전엔 포인터만 비워 파일이 고아가 됐다 — 이제 파일도 지운다.
func TestUpdateStaffProfileClearingPhotoDeletesObject(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	path := uploadStaffPhotoFixture(t, s, up, "t1")
	st, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: "", Title: "헤드 트레이너"})
	if err != nil {
		t.Fatalf("UpdateStaffProfile: %v", err)
	}
	if len(pg.deleted) != 1 || pg.deleted[0] != path {
		t.Fatalf("지우기 파기 = %v, want [%s] — 포인터만 비우면 파일은 발견 경로 없는 고아가 된다", pg.deleted, path)
	}
	if st.Profile.PhotoURL != "" || st.Profile.Title != "헤드 트레이너" {
		t.Errorf("저장 결과 = %+v, want photo_url \"\" + 직함", st.Profile)
	}
}

// 통 교체라 어드민은 같은 URL을 그대로 되돌려 보낸다 — prev == next면 삭제하지 않는다.
// 지우면 방금 저장한 프로필이 죽은 링크를 가리킨다.
func TestUpdateStaffProfileSameURLDoesNotDelete(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	uploadStaffPhotoFixture(t, s, up, "t1")
	url := staffPhotoURL(t, s, "t1")
	// 대표 편집(owner)과 본인 편집(trainer — MyProfile은 사진 값을 손대지 않고 되보낸다) 둘 다.
	for _, p := range []Principal{ownerP(), trainerP()} {
		st, err := s.UpdateStaffProfile(ctx, p, "t1", domain.StaffProfile{PhotoURL: url, Title: "헤드 트레이너"})
		if err != nil {
			t.Fatalf("UpdateStaffProfile(%s): %v", p.Role, err)
		}
		if pg.calls != 0 {
			t.Fatalf("같은 URL 되돌림에 삭제 호출(%s): %v — 방금 저장한 프로필이 죽은 링크가 된다", p.Role, pg.deleted)
		}
		if st.Profile.PhotoURL != url {
			t.Errorf("photo_url = %q, want %q", st.Profile.PhotoURL, url)
		}
	}
}

// 외부 URL로 바꾸면 우리 파일은 지우고 외부 URL이 저장된다. 그 외부 URL을 다시 지워도 삭제 호출은 없다.
func TestUpdateStaffProfileExternalURLReplacesAndDeletesOurs(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	path := uploadStaffPhotoFixture(t, s, up, "t1")
	const external = "https://cdn.example.com/hyerin.jpg"
	st, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: external})
	if err != nil {
		t.Fatal(err)
	}
	if len(pg.deleted) != 1 || pg.deleted[0] != path {
		t.Fatalf("외부 URL 교체 파기 = %v, want [%s]", pg.deleted, path)
	}
	if st.Profile.PhotoURL != external {
		t.Errorf("photo_url = %q, want %q", st.Profile.PhotoURL, external)
	}
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: ""}); err != nil {
		t.Fatal(err)
	}
	if pg.calls != 1 {
		t.Errorf("외부 URL 지우기에 삭제 호출(총 %d회): %v — 우리 파일이 아니다", pg.calls, pg.deleted)
	}
}

// 지우기의 파기가 실패하면 프로필은 **아무것도 바뀌지 않는다**(저장 전 삭제·실패 전파).
func TestUpdateStaffProfileDeleteFailureLeavesProfileUntouched(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	uploadStaffPhotoFixture(t, s, up, "t1")
	url := staffPhotoURL(t, s, "t1")
	boom := errors.New("storage delete down")
	pg.fail = boom
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: "", Title: "헤드 트레이너"}); !errors.Is(err, boom) {
		t.Fatalf("파기 실패가 삼켜졌다: %v", err)
	}
	saved := mustGetStaff(t, s, "t1")
	if saved.Profile.PhotoURL != url || saved.Profile.Title != "" {
		t.Errorf("파기 실패인데 프로필이 바뀜: %+v — 포인터를 잃으면 파일이 고아가 된다", saved.Profile)
	}
}

// ---- 와이어 계약 ----

// 라우터를 태워 바이트를 본다: deactivate 200 응답의 `profile.photo_url`이 ""로 실리고(json 태그에
// omitempty 없음), 퇴사자 업로드는 400이다. newTestRouter는 업로더가 없어(503) 서비스에 직접 주입한다.
func TestDeactivateWireClearsPhotoURLAndBlocksReupload(t *testing.T) {
	r, svc, _ := newTestRouterSharing(t)
	pg := &recordingPurger{}
	svc.WithMediaUploader(&recordingUploader{}).WithMediaPurger(pg)

	rec := postJSON(t, r, "/v1/staff", "owner1", domain.RoleOwner, `{"name":"정혜린","email":"hyerin@rise.kr","role":"trainer"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("POST /v1/staff = %d %s", rec.Code, rec.Body.String())
	}
	var created struct {
		UID string `json:"uid"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	photoPath := "/v1/staff/" + created.UID + "/photo"
	body := fmt.Sprintf(`{"image":%q,"content_type":"image/png"}`, b64img(photoPNG(t, 200, 200)))
	if rec := postJSON(t, r, photoPath, "owner1", domain.RoleOwner, body); rec.Code != http.StatusOK {
		t.Fatalf("업로드 = %d %s, want 200", rec.Code, rec.Body.String())
	}

	rec = postJSON(t, r, "/v1/staff/"+created.UID+"/deactivate", "owner1", domain.RoleOwner, `{}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("퇴사 = %d %s, want 200", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"photo_url":""`) {
		t.Errorf("퇴사 응답에 빈 photo_url이 실리지 않음: %s", rec.Body.String())
	}
	var st struct {
		Status  string `json:"status"`
		Profile struct {
			PhotoURL string `json:"photo_url"`
		} `json:"profile"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &st); err != nil {
		t.Fatal(err)
	}
	if st.Status != domain.StaffStatusInactive || st.Profile.PhotoURL != "" {
		t.Errorf("퇴사 응답 = %+v, want inactive + photo_url \"\"", st)
	}
	if len(pg.deleted) != 1 {
		t.Errorf("파기 = %v, want 1건", pg.deleted)
	}

	// 퇴사자 업로드 → 400(remedy 문구 포함). 파일은 생기지 않는다.
	rec = postJSON(t, r, photoPath, "owner1", domain.RoleOwner, body)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("퇴사자 업로드 = %d %s, want 400", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "재입사") {
		t.Errorf("400 본문이 remedy를 말하지 않는다: %s", rec.Body.String())
	}
	if got := staffPhotoURL(t, svc, created.UID); got != "" {
		t.Errorf("400 뒤 photo_url = %q, want \"\"", got)
	}
}
