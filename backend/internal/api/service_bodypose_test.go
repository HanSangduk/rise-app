package api

// 회원별 체형 포즈 시퀀스(v2.10) 회귀.
//
// 이 필드는 **nil이 의미를 갖는다**(nil = 센터 기본 사용). 그래서 다른 슬라이스 필드처럼
// nil→[] 정규화를 하면 안 되고, 응답 구체화를 저장 객체에 하면 안 된다. 두 실수 모두
// 조용히 동작하는 것처럼 보이므로 테스트로 못박는다:
//
//   ① 필드 없는 PUT(어드민의 기존 회원 수정 페이로드)이 **커스텀 시퀀스를 지우지 않는가**
//   ② 응답 구체화가 **저장 객체를 오염시키지 않는가** — 오염되면 그 회원만 센터 기본
//      변경을 영원히 못 따라온다(기본값이 커스텀으로 굳는다)

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"testing"

	"github.com/ramsang/rise-backend/internal/domain"
)

func seedPoseMember(t *testing.T, s *Service) *domain.Member {
	t.Helper()
	seedTrainerRecord(t, s, "t1", "이담당")
	mem, err := s.CreateMember(context.Background(), ownerP(), &domain.Member{
		Name: "포즈회원", Phone: "010-4444-5555", TrainerID: "t1",
		Status:  domain.MemberStatusActive,
		Consent: domain.Consent{General: true, Sensitive: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	return mem
}

func poseKeys(ps []domain.BodyPose) []string {
	out := make([]string, 0, len(ps))
	for _, p := range ps {
		out = append(out, p.Key)
	}
	return out
}

func eq(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// 기본값 구체화: 커스텀이 없으면 응답은 센터 기본 4종이어야 한다(앱이 기본을 몰라도 되게).
func TestBodyPosesMaterializedInResponses(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)

	want := poseKeys(domain.DefaultBodyPoses)
	if got := poseKeys(mem.BodyPoses); !eq(got, want) {
		t.Errorf("CreateMember 응답 = %v, want 기본 %v", got, want)
	}

	// 회원 본인 목록 조회 — 앱이 자기 포즈 시퀀스를 받는 실제 경로다.
	list, err := s.ListMembers(ctx, memberP(mem.ID), "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 {
		t.Fatalf("본인 목록 %d건", len(list))
	}
	if got := poseKeys(list[0].Member.BodyPoses); !eq(got, want) {
		t.Errorf("앱이 받는 시퀀스 = %v, want 기본 %v", got, want)
	}

	// 스태프 목록 — 어드민 포즈 편집기의 초기값.
	staffList, err := s.ListMembers(ctx, ownerP(), "", "")
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range staffList {
		if m.Member.ID != mem.ID {
			continue
		}
		if got := poseKeys(m.Member.BodyPoses); !eq(got, want) {
			t.Errorf("어드민이 받는 시퀀스 = %v, want 기본 %v", got, want)
		}
	}
}

// 커스텀 저장 → 필드 없는 PUT이 그걸 지우면 안 된다(어드민의 기존 회원 수정 페이로드가
// body_poses를 안 싣는다 — 지워지면 대표가 짜 둔 시퀀스가 이름 한 번 고칠 때마다 날아간다).
func TestBodyPosesSurviveMergePutWithoutField(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)

	custom := []domain.BodyPose{
		{Key: "front_relax", Label: "정면 이완"},
		{Key: "side_left", Label: "좌측면"},
	}
	body, _ := json.Marshal(map[string]any{"body_poses": custom})
	updated, err := s.UpdateMember(ctx, ownerP(), mem.ID, body)
	if err != nil {
		t.Fatal(err)
	}
	if got := poseKeys(updated.BodyPoses); !eq(got, []string{"front_relax", "side_left"}) {
		t.Fatalf("커스텀 저장 실패: %v", got)
	}

	// 이름만 바꾸는 PUT — body_poses 필드가 아예 없다.
	body2, _ := json.Marshal(map[string]any{"name": "이름변경"})
	after, err := s.UpdateMember(ctx, ownerP(), mem.ID, body2)
	if err != nil {
		t.Fatal(err)
	}
	if got := poseKeys(after.BodyPoses); !eq(got, []string{"front_relax", "side_left"}) {
		t.Errorf("필드 없는 PUT이 커스텀을 지웠다: %v", got)
	}
	if after.Name != "이름변경" {
		t.Errorf("이름이 안 바뀜: %q", after.Name)
	}
}

// 응답 구체화가 저장 객체를 오염시키면 안 된다. 오염되면 "기본을 쓰는 회원"이 사라져
// 센터 기본을 바꿔도 그 회원만 옛 값에 고정된다.
func TestBodyPosesMaterializationDoesNotPersist(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)

	// 조회를 여러 번 해서 구체화를 반복 트리거한 뒤,
	for range 3 {
		if _, err := s.ListMembers(ctx, ownerP(), "", ""); err != nil {
			t.Fatal(err)
		}
	}
	// 필드 없는 PUT을 태운다 — 저장 객체가 오염됐다면 이 시점에 기본값이 커스텀으로 굳는다.
	body, _ := json.Marshal(map[string]any{"name": "그대로"})
	if _, err := s.UpdateMember(ctx, ownerP(), mem.ID, body); err != nil {
		t.Fatal(err)
	}
	// 스토어 원본을 직접 본다(응답이 아니라).
	raw, err := s.store.GetMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if raw.BodyPoses != nil {
		t.Errorf("저장 객체가 오염됐다(nil이어야 기본 추종): %v", poseKeys(raw.BodyPoses))
	}
}

// 빈 배열·null = "센터 기본으로 초기화"(교체가 아니라 되돌리기).
func TestBodyPosesEmptyResetsToDefault(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)

	custom, _ := json.Marshal(map[string]any{
		"body_poses": []domain.BodyPose{{Key: "only_one", Label: "하나"}},
	})
	if _, err := s.UpdateMember(ctx, ownerP(), mem.ID, custom); err != nil {
		t.Fatal(err)
	}
	for _, reset := range []string{`{"body_poses":[]}`, `{"body_poses":null}`} {
		// 매번 커스텀으로 되돌려 놓고 초기화를 시험한다.
		if _, err := s.UpdateMember(ctx, ownerP(), mem.ID, custom); err != nil {
			t.Fatal(err)
		}
		after, err := s.UpdateMember(ctx, ownerP(), mem.ID, []byte(reset))
		if err != nil {
			t.Fatalf("%s → %v", reset, err)
		}
		if got := poseKeys(after.BodyPoses); !eq(got, poseKeys(domain.DefaultBodyPoses)) {
			t.Errorf("%s 후 = %v, want 기본", reset, got)
		}
		raw, _ := s.store.GetMember(ctx, testCenter, mem.ID)
		if raw.BodyPoses != nil {
			t.Errorf("%s 후 저장값이 nil이 아니다: %v", reset, poseKeys(raw.BodyPoses))
		}
	}
}

// 검증: 파일명·경로를 깨는 key와 렌더를 깨는 label을 막는다.
func TestBodyPosesValidation(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)

	bad := []struct {
		name  string
		poses []domain.BodyPose
		why   string
	}{
		{"하이픈", []domain.BodyPose{{Key: "front-relax", Label: "정면"}},
			"Storage 파일명이 '-'로 조각을 나눈다 — 고스트의 epochMs 파싱이 모호해진다"},
		{"슬래시", []domain.BodyPose{{Key: "a/b", Label: "정면"}}, "경로 세그먼트가 늘어난다"},
		{"대문자", []domain.BodyPose{{Key: "Front", Label: "정면"}}, "대소문자 충돌"},
		{"한글 key", []domain.BodyPose{{Key: "정면", Label: "정면"}}, "URL 인코딩 문제"},
		{"빈 key", []domain.BodyPose{{Key: "", Label: "정면"}}, ""},
		{"빈 label", []domain.BodyPose{{Key: "ok_key", Label: "  "}}, "칩에 빈 글자"},
		{"중복 key", []domain.BodyPose{{Key: "a", Label: "가"}, {Key: "a", Label: "나"}},
			"어느 라벨을 쓸지 모호"},
	}
	for _, c := range bad {
		body, _ := json.Marshal(map[string]any{"body_poses": c.poses})
		_, err := s.UpdateMember(ctx, ownerP(), mem.ID, body)
		if !errors.Is(err, domain.ErrInvalidBodyPoses) {
			t.Errorf("%s → %v, want ErrInvalidBodyPoses (%s)", c.name, err, c.why)
		}
		// 도메인 에러가 400으로 매핑되는지 — 매핑 목록에서 빠져 500으로 나가던 전례가 있다.
		if st := statusForTest(err); st != 400 {
			t.Errorf("%s → HTTP %d, want 400", c.name, st)
		}
	}

	// 정상 커스텀은 통과한다(과잉 차단 방지).
	ok, _ := json.Marshal(map[string]any{
		"body_poses": []domain.BodyPose{{Key: "front_relax", Label: "정면 이완"}},
	})
	if _, err := s.UpdateMember(ctx, ownerP(), mem.ID, ok); err != nil {
		t.Errorf("정상 커스텀이 거부됨: %v", err)
	}
}

// 사진 저장의 pose는 종전 **무검증**이었다 — 파일명을 깨는 값이 그대로 저장됐다.
func TestCreateBodyPhotoValidatesPoseAndPath(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)

	valid := BodyPhotoCreateRequest{
		MemberID: mem.ID, Pose: "stand", Direction: "front", Date: today(),
		StoragePath: "members/" + mem.ID + "/body/20260824-stand-front-1.jpg",
	}
	if _, err := s.CreateBodyPhoto(ctx, trainerP(), valid); err != nil {
		t.Fatalf("레거시 포즈가 거부됨(비파괴여야 한다): %v", err)
	}

	badPose := valid
	badPose.Pose = "front-relax" // 하이픈 — 파일명 조각 구분자
	if _, err := s.CreateBodyPhoto(ctx, trainerP(), badPose); !errors.Is(err, errBadRequest) {
		t.Errorf("하이픈 pose = %v, want 400", err)
	}

	noPath := valid
	noPath.StoragePath = ""
	if _, err := s.CreateBodyPhoto(ctx, trainerP(), noPath); !errors.Is(err, errBadRequest) {
		t.Errorf("빈 storage_path = %v, want 400 (가리킬 파일이 없는 레코드)", err)
	}
}

// statusForTest — writeErr의 분기를 테스트에서 재사용해 "도메인 에러 → HTTP 코드" 매핑을
// 검증한다. 매핑 목록(util.go)에 새 도메인 에러를 넣는 걸 잊으면 검증은 도는데 응답만
// 500으로 나가고, 클라이언트는 사용자에게 이유를 못 보여준다(실제로 그 상태였다).
func statusForTest(err error) int {
	rr := httptest.NewRecorder()
	writeErr(rr, httptest.NewRequest("GET", "/test", nil), err)
	return rr.Code
}

// 검증 실패(400)가 **저장하지 않았는데도** 스토어 원본을 오염시키면 안 된다.
//
// Memory 스토어의 GetMember는 얕은 복사라 슬라이스 백킹 배열을 원본과 공유한다.
// json 언마샬이 기존 용량을 재사용해 그 자리를 덮어쓰면, 저장을 건너뛴 실패 경로에서도
// 원본 요소가 이미 바뀐 뒤다 — 대표는 "저장 실패"를 보고 창을 닫는데 회원의 포즈 시퀀스는
// 잘못된 값으로 바뀌어 있다. (Firestore는 문서를 매번 새로 언마샬해 무관 — Memory만의 함정)
func TestBodyPosesInvalidPutDoesNotCorruptStore(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedPoseMember(t, s)

	good, _ := json.Marshal(map[string]any{"body_poses": []domain.BodyPose{
		{Key: "front_relax", Label: "정면 이완"},
		{Key: "side_left", Label: "좌측면"},
	}})
	if _, err := s.UpdateMember(ctx, ownerP(), mem.ID, good); err != nil {
		t.Fatal(err)
	}

	// 같은 길이의 **잘못된** 시퀀스 — 용량이 맞아떨어져 백킹 배열 재사용이 일어나는 모양.
	bad, _ := json.Marshal(map[string]any{"body_poses": []domain.BodyPose{
		{Key: "BAD-KEY", Label: "덮어쓰기"},
		{Key: "another", Label: "두번째"},
	}})
	if _, err := s.UpdateMember(ctx, ownerP(), mem.ID, bad); !errors.Is(err, domain.ErrInvalidBodyPoses) {
		t.Fatalf("잘못된 시퀀스가 통과했다: %v", err)
	}

	raw, err := s.store.GetMember(ctx, testCenter, mem.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got := poseKeys(raw.BodyPoses); !eq(got, []string{"front_relax", "side_left"}) {
		t.Errorf("400인데 스토어 원본이 오염됐다: %v", got)
	}
}
