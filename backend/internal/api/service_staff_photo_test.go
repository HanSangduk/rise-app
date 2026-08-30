package api

// 트레이너 프로필 사진 업로드(계약 v2.25, P51).
//
// 이 스위트가 지키는 것은 서로 성격이 다르다:
//
//   - **거부는 계약을 건드리지 않는다.** 검증에 걸린 요청이 프로필의 기존 photo_url을
//     지우거나 버킷에 파일을 남기면, 실패한 시도 하나가 살아 있던 사진을 죽인다.
//   - **미구성은 조용히 성공하지 않는다.** STORAGE_BUCKET이 없을 때 no-op으로 떨어지면
//     어드민은 "저장됨"을 보고 회원 앱은 빈 아바타를 본다 — P22가 체형사진에서 실제로
//     겪은 실패 모양이다(조용한 no-op → 버킷에 고아 50개).
//   - **교체가 옛 파일을 영원히 남기지 않는다.** 사진을 열 번 바꾸면 오브젝트가 열 개
//     쌓이는데, 그중 아홉 개는 아무도 가리키지 않고 아무 경로로도 발견되지 않는다.

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"net/http"
	"strings"
	"testing"

	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/option"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// ---- 픽스처 ----

// photoPNG / photoJPEG — 실제 인코더로 만든 진짜 파일. 손으로 박은 가짜 바이트를 쓰지
// 않는 이유는 P44와 같다: 매직·헤더·꼬리가 전부 진짜여야 검증 계층이 실제로 지나간다.
func photoPNG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for x := 0; x < w; x++ {
		for y := 0; y < h; y++ {
			img.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 128, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("png encode: %v", err)
	}
	return buf.Bytes()
}

// photoPNGOversize — 2MB 상한을 넘기는 **완전한** PNG. 그라디언트는 PNG가 잘 압축해
// 4096px를 다 써도 2MB에 못 미치므로 픽셀을 의사난수로 채운다(압축 불가 → 원본에 비례).
// 상한 검사를 다른 층과 고립시키는 것이 목적이라 IEND·치수는 전부 정상이어야 한다.
func photoPNGOversize(t *testing.T) []byte {
	t.Helper()
	const side = 1024
	img := image.NewRGBA(image.Rect(0, 0, side, side))
	seed := uint32(12345) // 결정적 LCG — 테스트가 실행마다 달라지지 않는다
	next := func() uint8 {
		seed = seed*1664525 + 1013904223
		return uint8(seed >> 16)
	}
	for i := 0; i < len(img.Pix); i += 4 {
		img.Pix[i], img.Pix[i+1], img.Pix[i+2], img.Pix[i+3] = next(), next(), next(), 255
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("png encode: %v", err)
	}
	if buf.Len() <= maxStaffPhotoBytes {
		t.Fatalf("픽스처가 상한을 넘지 못했다: %d bytes (상한 %d)", buf.Len(), maxStaffPhotoBytes)
	}
	return buf.Bytes()
}

func photoJPEG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for x := 0; x < w; x++ {
		for y := 0; y < h; y++ {
			img.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 64, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, nil); err != nil {
		t.Fatalf("jpeg encode: %v", err)
	}
	return buf.Bytes()
}

// photoWebP — 최소 VP8L(무손실) WebP. Go에는 webp **인코더**가 없어(x/image도 디코더만
// 제공한다) 컨테이너를 손으로 조립한다. 그래도 가짜 픽스처가 아닌 이유: image.DecodeConfig
// (= x/image/webp)가 이 바이트에서 실제로 치수를 읽어낸다 — 독립 구현이 통과시킨다는 것이
// 이 픽스처가 규격에 맞다는 증거다.
//
// 레이아웃: "RIFF" + uint32le(나머지 길이) + "WEBP" + "VP8L" + uint32le(청크 길이)
// + 0x2F + [width-1:14b | height-1:14b | alpha:1b | version:3b] LE 4바이트.
func photoWebP(t *testing.T, w, h int) []byte {
	t.Helper()
	if w < 1 || h < 1 || w > 1<<14 || h > 1<<14 {
		t.Fatalf("webp 픽스처 치수 범위 밖: %dx%d", w, h)
	}
	var chunk bytes.Buffer
	chunk.WriteByte(0x2F)
	var hdr [4]byte
	binary.LittleEndian.PutUint32(hdr[:], uint32(w-1)|uint32(h-1)<<14)
	chunk.Write(hdr[:])
	data := chunk.Bytes()
	pad := len(data) % 2

	var out bytes.Buffer
	out.WriteString("RIFF")
	var n [4]byte
	binary.LittleEndian.PutUint32(n[:], uint32(4+8+len(data)+pad)) // "WEBP" + 청크헤더 + 본문
	out.Write(n[:])
	out.WriteString("WEBP")
	out.WriteString("VP8L")
	binary.LittleEndian.PutUint32(n[:], uint32(len(data)))
	out.Write(n[:])
	out.Write(data)
	for i := 0; i < pad; i++ {
		out.WriteByte(0)
	}
	return out.Bytes()
}

// riffNotWebP — RIFF 컨테이너이지만 WebP가 아닌 파일(예: WAV·AVI를 확장자만 바꾼 것).
// 매직("RIFF")과 선언 길이는 정상이라 앞의 두 층을 통과한다 — 'WEBP' 4바이트 검사만이
// 잡는다. 그 검사가 없으면 WebP가 아닌 RIFF가 "해석 불가"라는 **다른 이유**로 거부되어
// 어느 층이 일했는지 알 수 없게 되고, 잘린 WebP와 구분도 사라진다.
func riffNotWebP() []byte {
	var out bytes.Buffer
	body := []byte("WAVEfmt junkjunkjunk")
	out.WriteString("RIFF")
	var n [4]byte
	binary.LittleEndian.PutUint32(n[:], uint32(len(body)))
	out.Write(n[:])
	out.Write(body)
	return out.Bytes()
}

func b64img(b []byte) string { return base64.StdEncoding.EncodeToString(b) }

// ---- 업로드 경계 스파이 ----

// recordingUploader — 올라간 오브젝트를 기록한다. 실패 주입도 같은 타입으로 한다
// (스토리지 장애 시 프로필이 안 바뀌는지를 봐야 한다).
type recordingUploader struct {
	uploads []recordedUpload
	fail    error
	baseURL string // 비우면 실제와 같은 모양의 Firebase 다운로드 URL을 만든다
}

type recordedUpload struct {
	path        string
	contentType string
	size        int
}

func (u *recordingUploader) Upload(_ context.Context, path, contentType string, data []byte) (string, error) {
	if u.fail != nil {
		return "", u.fail
	}
	u.uploads = append(u.uploads, recordedUpload{path: path, contentType: contentType, size: len(data)})
	if u.baseURL != "" {
		return u.baseURL, nil
	}
	// 실제 firebaseMediaUploader와 **같은 모양**이어야 한다 — 교체 삭제가 이 URL을 되파싱한다.
	return "https://firebasestorage.googleapis.com/v0/b/test-bucket.firebasestorage.app/o/" +
		strings.ReplaceAll(path, "/", "%2F") + "?alt=media&token=tok-" + fmt.Sprint(len(u.uploads)), nil
}

// photoService — 업로드·삭제 스파이가 붙은 서비스 + 대상 트레이너 1명.
func photoService(t *testing.T) (*Service, *recordingUploader, *recordingPurger) {
	t.Helper()
	up := &recordingUploader{}
	pg := &recordingPurger{}
	s := newTestService().WithMediaUploader(up).WithMediaPurger(pg)
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")
	return s, up, pg
}

func photoReq(t *testing.T, raw []byte, ct string) StaffPhotoRequest {
	t.Helper()
	return StaffPhotoRequest{Image: b64img(raw), ContentType: ct}
}

func staffPhotoURL(t *testing.T, s *Service, uid string) string {
	t.Helper()
	st, err := s.store.GetStaff(context.Background(), testCenter, uid)
	if err != nil {
		t.Fatalf("GetStaff(%s): %v", uid, err)
	}
	return st.Profile.PhotoURL
}

// ---- 권한 ----

// owner 전용. 프로필 편집 PUT은 본인 트레이너도 되지만 이쪽은 다르다 — 센터 공용 버킷에
// 파일을 만드는 호출이고, 되돌리는 수단과 비용은 대표에게만 있다(스태프 관리 계열과 같은 경계).
func TestStaffPhotoUploadIsOwnerOnly(t *testing.T) {
	ctx := context.Background()
	raw := photoPNG(t, 200, 200)

	for _, c := range []struct {
		name string
		p    Principal
	}{
		{"트레이너 본인", trainerP()},
		{"회원", memberP("m1")},
	} {
		t.Run(c.name, func(t *testing.T) {
			s, up, _ := photoService(t)
			_, err := s.UploadStaffPhoto(ctx, c.p, "t1", photoReq(t, raw, "image/png"))
			if !errors.Is(err, ErrForbidden) {
				t.Fatalf("업로드가 통과: %v", err)
			}
			if len(up.uploads) != 0 {
				t.Errorf("403인데 파일이 올라갔다: %+v", up.uploads)
			}
		})
	}
}

// ---- 정상 경로 ----

// 호출 한 번으로 끝난다: 파일이 올라가고 **프로필의 photo_url이 서버에서 갱신된다**.
// 어드민이 이어서 profile PUT을 부르지 않아도 되는 것이 계약의 요점이다.
func TestStaffPhotoUploadPersistsURLOnProfile(t *testing.T) {
	ctx := context.Background()
	for _, c := range []struct {
		name, ct, wantExt string
		raw               func(*testing.T) []byte
	}{
		{"PNG", "image/png", "png", func(t *testing.T) []byte { return photoPNG(t, 200, 240) }},
		{"JPEG", "image/jpeg", "jpg", func(t *testing.T) []byte { return photoJPEG(t, 320, 320) }},
		{"WEBP", "image/webp", "webp", func(t *testing.T) []byte { return photoWebP(t, 128, 96) }},
		// content_type에 파라미터가 붙어 와도 접는다(손으로 만든 요청에서 흔하다).
		{"PNG + charset 파라미터", "image/png; charset=binary", "png", func(t *testing.T) []byte { return photoPNG(t, 200, 200) }},
		// 대문자 MIME도 같은 형식이다.
		{"대문자 MIME", "IMAGE/PNG", "png", func(t *testing.T) []byte { return photoPNG(t, 100, 100) }},
	} {
		t.Run(c.name, func(t *testing.T) {
			s, up, _ := photoService(t)
			raw := c.raw(t)
			res, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, raw, c.ct))
			if err != nil {
				t.Fatalf("업로드 실패: %v", err)
			}
			if len(up.uploads) != 1 {
				t.Fatalf("업로드 호출 %d회, want 1: %+v", len(up.uploads), up.uploads)
			}
			got := up.uploads[0]
			if !strings.HasPrefix(got.path, staffPhotoPrefix+"t1-") {
				t.Errorf("오브젝트 경로 = %q, want %st1-{난수}.%s — 규칙이 예약한 경로여야 한다",
					got.path, staffPhotoPrefix, c.wantExt)
			}
			if !strings.HasSuffix(got.path, "."+c.wantExt) {
				t.Errorf("확장자 = %q, want .%s", got.path, c.wantExt)
			}
			if got.size != len(raw) {
				t.Errorf("업로드 바이트 = %d, want %d — 디코드된 원본 그대로 올라가야 한다", got.size, len(raw))
			}
			// content_type은 정규화된 값(파라미터·대소문자 접힘)으로 올라가야 브라우저가 렌더한다.
			if got.contentType != "image/"+map[string]string{"png": "png", "jpg": "jpeg", "webp": "webp"}[c.wantExt] {
				t.Errorf("content_type = %q", got.contentType)
			}
			if res.PhotoURL == "" || !strings.HasPrefix(res.PhotoURL, "https://") {
				t.Errorf("응답 photo_url = %q, want https URL", res.PhotoURL)
			}
			if stored := staffPhotoURL(t, s, "t1"); stored != res.PhotoURL {
				t.Errorf("프로필 photo_url = %q, want %q — 서버가 프로필까지 갱신해야 호출 한 번으로 끝난다",
					stored, res.PhotoURL)
			}
		})
	}
}

// 같은 트레이너에게 두 번 올리면 경로가 달라야 한다 — 경로가 곧 버전이라, 같으면 CDN·
// 브라우저 캐시가 옛 사진을 계속 보여준다(파일은 바뀌었는데 화면은 안 바뀌는 사고).
func TestStaffPhotoUploadPathIsUniquePerUpload(t *testing.T) {
	ctx := context.Background()
	s, up, _ := photoService(t)
	raw := photoPNG(t, 200, 200)
	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, raw, "image/png")); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, raw, "image/png")); err != nil {
		t.Fatal(err)
	}
	if up.uploads[0].path == up.uploads[1].path {
		t.Fatalf("두 업로드의 경로가 같다: %q — 교체가 캐시에 가려진다", up.uploads[0].path)
	}
}

// 프로필의 다른 칸(직함·경력·자격증)은 사진 업로드로 지워지지 않는다. 통 교체 PUT과 달리
// 이 엔드포인트는 photo_url **한 칸만** 만진다.
func TestStaffPhotoUploadPreservesRestOfProfile(t *testing.T) {
	ctx := context.Background()
	s, _, _ := photoService(t)
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{
		Title: "헤드 트레이너", CareerYears: 7,
		Specialties: []string{"체형교정"}, Certifications: []string{"생활스포츠지도사 2급"},
		Bio: "안녕하세요",
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, photoPNG(t, 200, 200), "image/png")); err != nil {
		t.Fatal(err)
	}
	st, err := s.store.GetStaff(ctx, testCenter, "t1")
	if err != nil {
		t.Fatal(err)
	}
	if st.Profile.Title != "헤드 트레이너" || st.Profile.CareerYears != 7 ||
		len(st.Profile.Specialties) != 1 || len(st.Profile.Certifications) != 1 || st.Profile.Bio != "안녕하세요" {
		t.Fatalf("사진 업로드가 프로필의 다른 칸을 지웠다: %+v", st.Profile)
	}
}

// ---- 검증 거부 ----

// 거부 표. 각 행이 **어떤 층에서 걸리는지**를 문구로 고립시킨다(층이 서로를 흡수하면
// 한 층을 지워도 테스트가 통과해버린다 — P44 서명 검증에서 같은 함정을 겪었다).
//
// 공통 단언: 400이면서 ① 파일이 올라가지 않고 ② 프로필의 기존 photo_url이 그대로다.
func TestStaffPhotoUploadValidationRejections(t *testing.T) {
	ctx := context.Background()
	const prior = "https://cdn.example.com/old.jpg" // 대표가 손으로 넣어 둔 기존 URL

	png200 := photoPNG(t, 200, 200)
	jpeg200 := photoJPEG(t, 200, 200)

	// 절단 PNG — IHDR까지만 남긴다(DecodeConfig는 치수를 읽지만 IEND가 없다).
	truncPNG := append([]byte{}, png200[:33]...)
	// IEND 뒤 쓰레기.
	trailingPNG := append(append([]byte{}, png200...), []byte("junk")...)
	// EOI가 없는 JPEG(헤더만 남기고 절단).
	truncJPEG := append([]byte{}, jpeg200[:64]...)
	// RIFF 선언 길이보다 짧게 자른 WebP.
	truncWebP := func() []byte {
		full := photoWebP(t, 128, 128)
		return full[:len(full)-3]
	}()
	// 2MB 초과 — 다른 층은 전부 정상인 완전한 PNG라 이 행이 크기 상한만 고립시킨다.
	huge := photoPNGOversize(t)

	cases := []struct {
		name    string
		req     StaffPhotoRequest
		wantMsg string
	}{
		{"허용되지 않은 형식(gif)", StaffPhotoRequest{Image: b64img(png200), ContentType: "image/gif"}, "JPG·PNG·WEBP"},
		{"content_type 누락", StaffPhotoRequest{Image: b64img(png200)}, "JPG·PNG·WEBP"},
		{"image 빈 문자열", StaffPhotoRequest{Image: "", ContentType: "image/png"}, "비어 있어요"},
		{"base64가 아님", StaffPhotoRequest{Image: "!!!not base64!!!", ContentType: "image/png"}, "base64"},
		{"data URL 통째로", StaffPhotoRequest{Image: "data:image/png;base64," + b64img(png200), ContentType: "image/png"}, "data:image"},
		{"PNG라고 선언한 JPEG(매직 불일치)", StaffPhotoRequest{Image: b64img(jpeg200), ContentType: "image/png"}, "형식이 아니에요"},
		{"JPEG라고 선언한 PNG(매직 불일치)", StaffPhotoRequest{Image: b64img(png200), ContentType: "image/jpeg"}, "형식이 아니에요"},
		{"WEBP라고 선언한 PNG(매직 불일치)", StaffPhotoRequest{Image: b64img(png200), ContentType: "image/webp"}, "형식이 아니에요"},
		{"절단 PNG(IEND 없음)", StaffPhotoRequest{Image: b64img(truncPNG), ContentType: "image/png"}, "손상됐거나 잘렸어요"},
		{"IEND 뒤 쓰레기", StaffPhotoRequest{Image: b64img(trailingPNG), ContentType: "image/png"}, "손상됐거나 잘렸어요"},
		{"절단 JPEG(EOI 없음)", StaffPhotoRequest{Image: b64img(truncJPEG), ContentType: "image/jpeg"}, "손상됐거나 잘렸어요"},
		{"절단 WEBP(RIFF 선언 길이 미달)", StaffPhotoRequest{Image: b64img(truncWebP), ContentType: "image/webp"}, "손상됐거나 잘렸어요"},
		{"RIFF지만 WebP가 아님(WAV 등)", StaffPhotoRequest{Image: b64img(riffNotWebP()), ContentType: "image/webp"}, "손상됐거나 잘렸어요"},
		{"2MB 초과", StaffPhotoRequest{Image: b64img(huge), ContentType: "image/png"}, "너무 커요"},
		{"치수 하한 미달(63px)", StaffPhotoRequest{Image: b64img(photoPNG(t, 63, 200)), ContentType: "image/png"}, "크기가 올바르지 않아요"},
		{"치수 상한 초과(4097px)", StaffPhotoRequest{Image: b64img(photoWebP(t, 4097, 100)), ContentType: "image/webp"}, "크기가 올바르지 않아요"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s, up, pg := photoService(t)
			if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: prior}); err != nil {
				t.Fatal(err)
			}
			_, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", c.req)
			if !errors.Is(err, errBadRequest) {
				t.Fatalf("통과했다(400이어야 한다): %v", err)
			}
			if !strings.Contains(err.Error(), c.wantMsg) {
				t.Errorf("문구 = %q, want %q 포함 — 층마다 다른 이유를 말해야 한다", err, c.wantMsg)
			}
			if len(up.uploads) != 0 {
				t.Errorf("거부됐는데 파일이 올라갔다: %+v", up.uploads)
			}
			if len(pg.deleted) != 0 {
				t.Errorf("거부됐는데 파일을 지웠다: %v", pg.deleted)
			}
			if got := staffPhotoURL(t, s, "t1"); got != prior {
				t.Errorf("거부가 기존 사진을 건드렸다: %q, want %q — 실패한 시도 하나가 살아 있던 사진을 죽인다", got, prior)
			}
		})
	}
}

// 치수 하한/상한의 **경계값은 통과**해야 한다(64·4096). 경계를 한 칸 안쪽으로 잡으면
// 정상 사진이 거부되고, 그 사실은 실사용에서만 드러난다.
func TestStaffPhotoDimensionBoundsAreInclusive(t *testing.T) {
	ctx := context.Background()
	for _, c := range []struct {
		name string
		raw  []byte
		ct   string
	}{
		{"하한 정확히 64×64", photoPNG(t, 64, 64), "image/png"},
		{"상한 정확히 4096×64(webp 헤더 치수)", photoWebP(t, 4096, 64), "image/webp"},
	} {
		t.Run(c.name, func(t *testing.T) {
			s, _, _ := photoService(t)
			if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, c.raw, c.ct)); err != nil {
				t.Fatalf("경계값이 거부됐다: %v", err)
			}
		})
	}
}

// 없는 스태프 앞으로는 파일을 만들지 않는다 — 고아 파일의 가장 흔한 출처다(아무도
// 가리키지 않고, 메타에서 출발하는 어떤 경로로도 닿을 수 없다).
func TestStaffPhotoUploadUnknownStaffCreatesNoObject(t *testing.T) {
	ctx := context.Background()
	s, up, _ := photoService(t)
	_, err := s.UploadStaffPhoto(ctx, ownerP(), "nobody", photoReq(t, photoPNG(t, 100, 100), "image/png"))
	if !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("없는 스태프 = %v, want ErrNotFound", err)
	}
	if len(up.uploads) != 0 {
		t.Errorf("없는 스태프 앞으로 파일이 올라갔다: %+v", up.uploads)
	}
}

// 경로 세그먼트 주입 차단 — uid가 오브젝트 경로에 그대로 실리므로 `..`이나 `/` 한 글자가
// 곧 다른 폴더 쓰기다(회원 체형사진 폴더를 덮어쓰는 경로가 여기서 열린다).
func TestStaffPhotoUploadRejectsPathTraversalUID(t *testing.T) {
	ctx := context.Background()
	for _, uid := range []string{"../members/m1/body/x", "t1/../../evil", "t 1", "t1%2F..%2Fx"} {
		s, up, _ := photoService(t)
		_, err := s.UploadStaffPhoto(ctx, ownerP(), uid, photoReq(t, photoPNG(t, 100, 100), "image/png"))
		// **400이어야 한다** — 404(그런 스태프 없음)로는 부족하다. "없어서" 막힌 것과
		// "모양이 위험해서" 막힌 것은 다른 사실이고, 앞의 이유에만 기대면 어쩌다 그
		// 이름의 레코드가 생기는 날 경로 주입이 열린다.
		if !errors.Is(err, errBadRequest) {
			t.Fatalf("uid %q = %v, want 400(경로에 실릴 값의 모양 거부)", uid, err)
		}
		if len(up.uploads) != 0 {
			t.Fatalf("uid %q로 파일이 올라갔다: %+v", uid, up.uploads)
		}
	}
}

// 새 URL이 **이미 프로필이 가리키던 오브젝트**와 같으면 지우지 않는다. 지우면 방금
// 성공한 업로드를 스스로 되돌려 프로필이 죽은 링크를 가리킨다.
func TestStaffPhotoReplacementNeverDeletesTheObjectItJustPointedTo(t *testing.T) {
	ctx := context.Background()
	const same = "https://firebasestorage.googleapis.com/v0/b/b1/o/staff%2Fphotos%2Ft1-same.png?alt=media&token=t"
	s, up, pg := photoService(t)
	up.baseURL = same // 업로더가 항상 같은 URL을 돌려준다(난수 충돌의 결정적 재현)
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: same}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, photoPNG(t, 200, 200), "image/png")); err != nil {
		t.Fatal(err)
	}
	if len(pg.deleted) != 0 {
		t.Fatalf("방금 올린 오브젝트를 지웠다: %v — 프로필이 죽은 링크를 가리킨다", pg.deleted)
	}
	if got := staffPhotoURL(t, s, "t1"); got != same {
		t.Errorf("프로필 = %q, want %q", got, same)
	}
}

// 프로필 저장이 실패하면 **방금 올린 파일을 그 자리에서 지운다.** 아무도 가리키지 않는
// 오브젝트는 메타에서 출발하는 어떤 경로로도 발견되지 않는다(P22가 체형사진에서 겪은 상태 —
// 회원 한 명의 버킷에 고아 50개). 에러는 그대로 올라가야 한다 — 대표에게는 저장 실패가 사실이다.
func TestStaffPhotoUploadCleansUpObjectWhenProfileSaveFails(t *testing.T) {
	ctx := context.Background()
	up := &recordingUploader{}
	pg := &recordingPurger{}
	s, h := newHookedService(t)
	s.WithMediaUploader(up).WithMediaPurger(pg)
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")

	boom := errors.New("firestore write failed")
	h.fail = func(op string, _ int) error {
		if op == "SaveStaff" {
			return boom
		}
		return nil
	}
	_, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, photoPNG(t, 200, 200), "image/png"))
	if !errors.Is(err, boom) {
		t.Fatalf("저장 실패가 삼켜졌다: %v", err)
	}
	if len(up.uploads) != 1 {
		t.Fatalf("업로드 호출 = %d, want 1", len(up.uploads))
	}
	if len(pg.deleted) != 1 || pg.deleted[0] != up.uploads[0].path {
		t.Fatalf("정리 삭제 = %v, want [%s] — 아무도 가리키지 않는 파일이 버킷에 남는다",
			pg.deleted, up.uploads[0].path)
	}
}

// ---- 미구성(STORAGE_BUCKET 없음) ----

// 기본 서비스는 업로드 경계가 **503 구현**이다 — 주입을 잊어도 조용한 성공이 되지 않는다.
func TestStaffPhotoUploadUnsetBucketFailsLoudly(t *testing.T) {
	ctx := context.Background()
	s := newTestService() // WithMediaUploader 없음 = STORAGE_BUCKET 미설정과 같은 상태
	seedStaff(t, s, "t1", domain.RoleTrainer, "정혜린")

	_, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, photoPNG(t, 200, 200), "image/png"))
	if !errors.Is(err, ErrUploadUnavailable) {
		t.Fatalf("미구성 업로드 = %v, want ErrUploadUnavailable — 조용한 성공은 거짓말이다", err)
	}
	if !strings.Contains(err.Error(), "STORAGE_BUCKET") {
		t.Errorf("문구가 고칠 방법을 말하지 않는다: %q", err)
	}
	if got := staffPhotoURL(t, s, "t1"); got != "" {
		t.Errorf("업로드 실패인데 프로필이 바뀌었다: %q", got)
	}

	// nil 주입이 기본값을 지우면 안 된다 — 다음 업로드가 nil 인터페이스 호출로 패닉하거나
	// (더 나쁘게) 조용한 성공으로 되돌아간다. WithMediaPurger의 같은 가드와 대칭.
	s.WithMediaUploader(nil)
	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, photoPNG(t, 200, 200), "image/png")); !errors.Is(err, ErrUploadUnavailable) {
		t.Fatalf("nil 주입 후 = %v, want ErrUploadUnavailable(기본값 유지)", err)
	}
}

// Authenticator.MediaUploader — 두 미구성 분기가 **모두** 503 구현을 준다(no-op이 아니다).
//
// 두 번째 분기(Firebase는 붙었는데 STORAGE_BUCKET만 없다)가 실배포에서 가장 흔한 실수라
// 굳이 SDK 앱을 만들어 그 갈래까지 지나간다. WithoutAuthentication으로 만든 앱은 네트워크를
// 타지 않는다 — 버킷이 비면 Storage 클라이언트를 만들기 전에 돌아 나오기 때문이다.
func TestMediaUploaderUnconfiguredBranches(t *testing.T) {
	ctx := context.Background()

	t.Run("Firebase 모드 아님", func(t *testing.T) {
		u := (&Authenticator{}).MediaUploader(ctx, "some-bucket")
		if _, ok := u.(unconfiguredUploader); !ok {
			t.Fatalf("업로더 = %T, want unconfiguredUploader", u)
		}
		if _, err := u.Upload(ctx, "staff/photos/x.png", "image/png", []byte("x")); !errors.Is(err, ErrUploadUnavailable) {
			t.Fatalf("Upload = %v, want ErrUploadUnavailable", err)
		}
	})

	t.Run("STORAGE_BUCKET만 미설정", func(t *testing.T) {
		app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: "demo-rize"}, option.WithoutAuthentication())
		if err != nil {
			t.Skipf("Admin SDK 앱 생성 불가(환경): %v", err)
		}
		u := (&Authenticator{fbApp: app}).MediaUploader(ctx, "")
		if _, ok := u.(unconfiguredUploader); !ok {
			t.Fatalf("버킷 미설정 업로더 = %T, want unconfiguredUploader — 조용한 성공이 된다", u)
		}
		_, err = u.Upload(ctx, "staff/photos/x.png", "image/png", []byte("x"))
		if !errors.Is(err, ErrUploadUnavailable) {
			t.Fatalf("Upload = %v, want ErrUploadUnavailable", err)
		}
		if !strings.Contains(err.Error(), "STORAGE_BUCKET") {
			t.Errorf("문구가 고칠 방법을 말하지 않는다: %q", err)
		}
	})
}

// 스토리지 장애(업로드 자체가 실패)면 프로필은 손대지 않는다 — 재시도가 그대로 통한다.
func TestStaffPhotoUploadStorageFailureLeavesProfileUntouched(t *testing.T) {
	ctx := context.Background()
	s, up, _ := photoService(t)
	if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: "https://cdn.example.com/old.jpg"}); err != nil {
		t.Fatal(err)
	}
	up.fail = errors.New("storage down")
	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, photoPNG(t, 200, 200), "image/png")); err == nil {
		t.Fatal("스토리지 장애인데 성공했다")
	}
	if got := staffPhotoURL(t, s, "t1"); got != "https://cdn.example.com/old.jpg" {
		t.Errorf("업로드 실패 후 프로필 = %q — 기존 사진이 사라졌다", got)
	}
}

// ---- 교체(옛 파일 정리) ----

// 두 번째 업로드가 첫 번째 오브젝트를 지운다. 지우지 않으면 사진을 바꿀 때마다 아무도
// 가리키지 않는 파일이 하나씩 쌓이고, 메타에서 출발하는 어떤 경로로도 발견되지 않는다.
func TestStaffPhotoReplacementDeletesPreviousObject(t *testing.T) {
	ctx := context.Background()
	s, up, pg := photoService(t)
	raw := photoPNG(t, 200, 200)

	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, raw, "image/png")); err != nil {
		t.Fatal(err)
	}
	first := up.uploads[0].path
	if len(pg.deleted) != 0 {
		t.Fatalf("첫 업로드가 무언가를 지웠다: %v", pg.deleted)
	}

	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, raw, "image/jpeg")); err == nil {
		t.Fatal("매직 불일치가 통과했다(픽스처 점검)")
	}
	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, photoJPEG(t, 200, 200), "image/jpeg")); err != nil {
		t.Fatal(err)
	}
	if len(pg.deleted) != 1 || pg.deleted[0] != first {
		t.Fatalf("교체 삭제 = %v, want [%s] — 옛 파일이 버킷에 영원히 남는다", pg.deleted, first)
	}
}

// 삭제 실패는 업로드를 실패시키지 않는다(best-effort). 대표 입장에서 사진은 이미 바뀌었고,
// 남은 파일 한 개 때문에 성공한 일을 실패로 보여줄 이유가 없다.
func TestStaffPhotoReplacementDeleteFailureDoesNotFailUpload(t *testing.T) {
	ctx := context.Background()
	s, _, pg := photoService(t)
	raw := photoPNG(t, 200, 200)
	if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, raw, "image/png")); err != nil {
		t.Fatal(err)
	}
	pg.fail = errors.New("storage delete down")
	res, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, raw, "image/png"))
	if err != nil {
		t.Fatalf("삭제 실패가 업로드를 실패시켰다: %v", err)
	}
	if got := staffPhotoURL(t, s, "t1"); got != res.PhotoURL {
		t.Errorf("프로필 = %q, want %q", got, res.PhotoURL)
	}
}

// 대표가 손으로 넣은 외부 URL(또는 다른 폴더를 가리키는 토큰 URL)은 **절대 지우지 않는다.**
// 이 가드가 없으면 회원 체형사진 경로를 가리키는 URL이 프로필에 들어 있는 것만으로
// 사진 교체 한 번이 남의 민감정보 파일을 지운다.
func TestStaffPhotoReplacementNeverDeletesForeignObjects(t *testing.T) {
	ctx := context.Background()
	for _, prior := range []string{
		"https://cdn.example.com/old.jpg",
		"https://firebasestorage.googleapis.com/v0/b/test-bucket/o/members%2Fm1%2Fbody%2Ffront.jpg?alt=media&token=t",
		"https://evil.example.com/v0/b/test-bucket/o/staff%2Fphotos%2Fx.png?alt=media&token=t",
	} {
		s, _, pg := photoService(t)
		if _, err := s.UpdateStaffProfile(ctx, ownerP(), "t1", domain.StaffProfile{PhotoURL: prior}); err != nil {
			t.Fatal(err)
		}
		if _, err := s.UploadStaffPhoto(ctx, ownerP(), "t1", photoReq(t, photoPNG(t, 200, 200), "image/png")); err != nil {
			t.Fatal(err)
		}
		if len(pg.deleted) != 0 {
			t.Fatalf("남의 오브젝트를 지웠다(prior=%s): %v", prior, pg.deleted)
		}
	}
}

// staffPhotoObjectPath — URL → 오브젝트 경로 되파싱의 단위 표. 교체 삭제의 안전이 전부
// 이 함수에 걸려 있어 경계를 직접 고정한다.
func TestStaffPhotoObjectPathParsing(t *testing.T) {
	cases := []struct{ in, want string }{
		{"", ""},
		{
			"https://firebasestorage.googleapis.com/v0/b/b1/o/staff%2Fphotos%2Ft1-ab12.png?alt=media&token=x",
			"staff/photos/t1-ab12.png",
		},
		// 다른 폴더 — 우리 파일이 아니다.
		{"https://firebasestorage.googleapis.com/v0/b/b1/o/members%2Fm1%2Fbody%2Fa.jpg?alt=media&token=x", ""},
		// 다른 호스트.
		{"https://evil.example.com/v0/b/b1/o/staff%2Fphotos%2Fx.png?alt=media&token=x", ""},
		// 경로 모양이 다름.
		{"https://firebasestorage.googleapis.com/v0/staff%2Fphotos%2Fx.png", ""},
		// 상위 탈출 시도.
		{"https://firebasestorage.googleapis.com/v0/b/b1/o/staff%2Fphotos%2F..%2F..%2Fmembers%2Fx.jpg?alt=media", ""},
		// 평문(비인코딩) 경로도 같은 오브젝트를 가리킨다.
		{"https://firebasestorage.googleapis.com/v0/b/b1/o/staff/photos/t1-cd34.png?alt=media", "staff/photos/t1-cd34.png"},
		{"not a url at all", ""},
	}
	for _, c := range cases {
		if got := staffPhotoObjectPath(c.in); got != c.want {
			t.Errorf("staffPhotoObjectPath(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// ---- 라우터(상태코드·응답 키) ----

// 라우트가 등록돼 있는지, writeErr 매핑(200/400/403/404/503)이 계약대로인지.
// 서비스 테스트만으로는 라우트 한 줄이 빠져도 전부 통과하면서 실기기에서 404가 된다.
func TestStaffPhotoHTTPStatusMapping(t *testing.T) {
	r := newTestRouter(t)
	raw := photoPNG(t, 200, 200)

	// 대상 스태프를 만든다(POST /v1/staff — owner).
	rec := postJSON(t, r, "/v1/staff", "owner1", "owner",
		`{"name":"정혜린","email":"hyerin@example.com","role":"trainer"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("스태프 생성 = %d: %s", rec.Code, rec.Body.String())
	}
	var created struct {
		UID string `json:"uid"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	path := "/v1/staff/" + created.UID + "/photo"
	body := fmt.Sprintf(`{"image":%q,"content_type":"image/png"}`, b64img(raw))

	// 트레이너 → 403.
	if rec := postJSON(t, r, path, created.UID, "trainer", body); rec.Code != http.StatusForbidden {
		t.Errorf("트레이너 업로드 = %d, want 403: %s", rec.Code, rec.Body.String())
	}
	// owner + 업로더 미구성 → 503(newTestRouter는 STORAGE_BUCKET이 없다).
	rec = postJSON(t, r, path, "owner1", "owner", body)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("미구성 업로드 = %d, want 503: %s", rec.Code, rec.Body.String())
	}
	// 문구는 분기마다 다르지만(어느 설정이 빠졌는지) **무엇을 해야 하는지**는 공통이다.
	if !strings.Contains(rec.Body.String(), "설정") {
		t.Errorf("503 본문이 조치를 말하지 않는다: %s", rec.Body.String())
	}
	// 없는 스태프 → 404(검증 통과 후 조회 단계에서 걸린다).
	if rec := postJSON(t, r, "/v1/staff/nobody/photo", "owner1", "owner", body); rec.Code != http.StatusNotFound {
		t.Errorf("없는 스태프 = %d, want 404: %s", rec.Code, rec.Body.String())
	}
	// 잘못된 형식 → 400.
	bad := fmt.Sprintf(`{"image":%q,"content_type":"image/gif"}`, b64img(raw))
	if rec := postJSON(t, r, path, "owner1", "owner", bad); rec.Code != http.StatusBadRequest {
		t.Errorf("형식 위반 = %d, want 400: %s", rec.Code, rec.Body.String())
	}
	// 미지 필드 → 400(계약 필드명 오타를 조기에 드러낸다).
	if rec := postJSON(t, r, path, "owner1", "owner", `{"image":"","content_type":"image/png","oops":1}`); rec.Code != http.StatusBadRequest {
		t.Errorf("미지 필드 = %d, want 400: %s", rec.Code, rec.Body.String())
	}
}

// 바디 상한은 **2MB 이미지의 base64를 통과시켜야** 한다. 공용 1MiB로는 정상 사진이
// 먼저 막혀 "2MB까지"라는 계약이 거짓이 된다.
func TestStaffPhotoBodyLimitAllowsTwoMegabyteImage(t *testing.T) {
	if encoded := base64.StdEncoding.EncodedLen(maxStaffPhotoBytes); encoded+64 > maxStaffPhotoBodyBytes {
		t.Fatalf("바디 상한 %d가 2MB 이미지의 base64(%d)보다 작다 — 정상 사진이 막힌다",
			maxStaffPhotoBodyBytes, encoded)
	}
	if maxStaffPhotoBodyBytes <= maxBodyBytes {
		t.Fatalf("바디 상한이 공용 상한(%d)보다 크지 않다 — 전용 상한을 둔 이유가 사라졌다", maxBodyBytes)
	}
}
