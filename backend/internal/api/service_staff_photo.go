package api

// 트레이너 프로필 사진 업로드(계약 v2.25, P51).
//
// **왜 서버가 올리는가.** `storage.rules`가 `staff/photos/{fileName}`에
// `allow read, write: if false`를 걸고 주석에 *"서버(Admin SDK)가 올리고, 클라이언트는
// 다운로드 토큰 URL로 읽는다"*라고 설계를 예약해 뒀는데, 그 서버 경로가 존재한 적이 없었다.
// 그 사이 어드민은 "사진 URL(http/https)" 텍스트 박스 하나로 대표에게 **URL을 만들어 오라**고
// 요구했다 — 휴대폰·바탕화면의 사진에는 URL이 없고, 제품 안에 그것을 만드는 수단도 없었다.
// 즉 이 기능은 없던 것이 아니라 **반쯤 만들어진 채 잠겨 있던 것**이고, 여기서 잠금을 푼다.
//
// 규칙은 손대지 않는다. Admin SDK는 보안 규칙을 지나지 않으므로(P22 MediaPurger와 같은 사실)
// 규칙의 전면 차단은 그대로 두고 서버만 쓴다. 클라이언트는 토큰 URL로 읽는데, 그 URL 역시
// 규칙을 거치지 않는다 — 규칙 주석이 적어 둔 대로다.

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"image"
	"log"
	"net/url"
	"regexp"
	"strings"

	// 치수 판독용 디코더 등록. **DecodeConfig는 헤더만 읽는다** — 픽셀을 풀지 않으므로
	// 디코드 폭탄 표면이 늘지 않는다(P44 서명 PNG 검증과 같은 근거).
	_ "image/jpeg"
	_ "image/png"

	_ "golang.org/x/image/webp" // stdlib에 webp 디코더가 없다(2026-08 기준 x/image v0.45.0)

	"github.com/ramsang/rise-backend/internal/store"
)

// 업로드 상한·경계(계약 v2.25).
const (
	// maxStaffPhotoBytes — 디코드된 원본 기준 2MB. 어드민이 클라이언트에서 축소해 보내므로
	// 이건 **예산이 아니라 최후 방어선**이다(원본 그대로 올리는 경로가 생겨도 버킷이 안 터진다).
	maxStaffPhotoBytes = 2 << 20
	// maxStaffPhotoBodyBytes — 요청 바디 상한. base64는 3바이트를 4자로 부풀리므로
	// 2MB 이미지가 약 2.67MiB가 된다 — 공용 maxBodyBytes(1MiB)로는 **정상 사진이 먼저 막힌다**.
	// 4MiB로 잡아 JSON 껍데기까지 여유를 준다(그래도 상한 없는 파싱은 아니다 — P35 H-1).
	maxStaffPhotoBodyBytes = 4 << 20

	minStaffPhotoSide = 64   // 이보다 작으면 아바타로 못 쓴다(썸네일에서도 뭉갠다)
	maxStaffPhotoSide = 4096 // 위생 상한 — 2MB 안에 들어오는 초대형 캔버스(1px 띠 등) 거부
)

// staffPhotoPrefix — 규칙이 예약해 둔 경로(storage.rules `match /staff/photos/{fileName}`).
// **삭제 대상 판정에도 쓴다** — 이 접두가 아닌 경로는 이 기능이 만든 파일이 아니므로 지우지 않는다.
const staffPhotoPrefix = "staff/photos/"

// staffPhotoFormat — 허용 content_type 하나의 명세. 선언된 타입과 실제 바이트가 **둘 다**
// 맞아야 통과한다: 헤더는 클라이언트가 쓰는 값이라 신뢰할 수 없고, 매직만 보면 응답
// Content-Type이 실제와 어긋나 브라우저가 렌더를 거부한다.
type staffPhotoFormat struct {
	contentType string
	ext         string
	magic       []byte
	// complete — 잘린 파일 판정. DecodeConfig는 **헤더까지만** 읽어 몸통·꼬리 부재를 못 본다
	// (P44 마감 리뷰: IHDR만 남긴 PNG가 "어떤 디코더로도 렌더 불가한 이미지"로 저장되던 갭).
	// 포맷마다 "끝났다"는 신호가 달라서 함수로 받는다.
	complete func([]byte) bool
}

// pngIENDSuffix는 handlers_contracts.go(P44)의 것을 그대로 재사용한다 — 같은 사실을 두 번
// 적으면 한쪽만 고쳐지는 날이 온다.

// jpegEOI — JPEG의 End Of Image 마커(FF D9). PNG의 IEND와 같은 자리다.
var jpegEOI = []byte{0xFF, 0xD9}

var staffPhotoFormats = []staffPhotoFormat{
	{
		contentType: "image/jpeg",
		ext:         "jpg",
		magic:       []byte{0xFF, 0xD8, 0xFF}, // SOI + 첫 마커
		// JPEG는 EOI(FF D9)로 끝난다. 일부 인코더가 뒤에 패딩을 붙이는 경우가 있어
		// **접미 일치 대신 존재**로 본다(PNG처럼 엄격하게 잡으면 정상 사진이 거부된다).
		// 그래도 "헤더만 있고 몸통이 없는" 절단본은 여기서 걸린다 — 그게 이 검사의 목적이다.
		complete: func(b []byte) bool { return bytes.Contains(b[2:], jpegEOI) },
	},
	{
		contentType: "image/png",
		ext:         "png",
		magic:       pngMagic,
		// PNG는 IEND가 **반드시 마지막 청크**이고 CRC가 상수다 — 접미 일치로 절단본과
		// IEND 뒤 쓰레기를 한 번에 막는다(P44와 같은 검사).
		complete: func(b []byte) bool { return bytes.HasSuffix(b, pngIENDSuffix) },
	},
	{
		contentType: "image/webp",
		ext:         "webp",
		magic:       []byte("RIFF"),
		complete:    webpComplete,
	},
}

// webpComplete — RIFF 컨테이너의 **선언 길이와 실제 길이가 맞는지**. WebP에는 PNG의 IEND
// 같은 종료 청크가 없지만, RIFF 헤더가 "이 뒤로 N바이트"를 스스로 적어 둔다 —
// 잘린 파일은 그 수보다 짧다. 같은 교훈(헤더는 멀쩡한데 몸통이 없는 파일)의 WebP판이다.
//
// 레이아웃: "RIFF"(4) + uint32le 나머지 길이(4) + "WEBP"(4) + 청크들.
// 선언 길이는 그 8바이트 **뒤부터** 세므로 전체 길이는 8 + declared다.
func webpComplete(b []byte) bool {
	if len(b) < 12 || !bytes.Equal(b[8:12], []byte("WEBP")) {
		return false
	}
	declared := binary.LittleEndian.Uint32(b[4:8])
	// 홀수 길이 청크는 1바이트 패딩이 붙어 실제가 1 클 수 있다 — 짧은 쪽만 거부한다.
	return uint64(len(b)) >= uint64(declared)+8
}

// staffPhotoUIDPattern — 오브젝트 경로에 실리는 uid. Firebase uid는 영숫자지만 그 사실에
// 기대지 않는다 — 경로 세그먼트에 들어가는 값이라 `..`이나 `/` 한 글자가 곧 다른 폴더 쓰기다.
var staffPhotoUIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,128}$`)

// StaffPhotoRequest — POST /v1/staff/{uid}/photo 바디.
type StaffPhotoRequest struct {
	Image       string `json:"image"`        // 이미지 바이트의 base64(표준 인코딩·패딩 포함)
	ContentType string `json:"content_type"` // image/jpeg | image/png | image/webp
}

// StaffPhotoResponse — 업로드 결과. 프로필은 서버가 이미 갱신했으므로 **호출 한 번이면 끝난다**
// (어드민이 이어서 PUT /v1/staff/{uid}/profile을 부를 필요가 없다 — 그 왕복 사이에 다른 편집이
// 끼면 사진이 되감긴다).
type StaffPhotoResponse struct {
	PhotoURL string `json:"photo_url"`
}

// decodeStaffPhoto — 업로드 바이트 검증. 순서는 **싼 검사부터**다:
// content_type 화이트리스트 → base64 → 매직 → 완결성 → 크기 → 치수.
// 전부 서비스 쓰기 **전**의 400이라, 버킷에 올라가는 것은 이미 통과한 것뿐이다.
func decodeStaffPhoto(req StaffPhotoRequest) ([]byte, staffPhotoFormat, error) {
	var zero staffPhotoFormat
	ct := strings.ToLower(strings.TrimSpace(req.ContentType))
	// "image/jpeg; charset=..." 같은 파라미터가 붙어 오는 경우를 접는다(브라우저 File.type은
	// 붙이지 않지만 손으로 만든 요청은 붙인다).
	if i := strings.IndexByte(ct, ';'); i >= 0 {
		ct = strings.TrimSpace(ct[:i])
	}
	var format staffPhotoFormat
	found := false
	for _, f := range staffPhotoFormats {
		if f.contentType == ct {
			format, found = f, true
			break
		}
	}
	if !found {
		return nil, zero, errors.Join(errBadRequest,
			errors.New("사진은 JPG·PNG·WEBP 형식만 올릴 수 있어요"))
	}
	if strings.TrimSpace(req.Image) == "" {
		return nil, zero, errors.Join(errBadRequest, errors.New("사진 데이터가 비어 있어요"))
	}
	raw, err := base64.StdEncoding.DecodeString(req.Image)
	if err != nil {
		// data URL을 통째로 붙여 넣는 것이 가장 흔한 실수다 — 무엇을 떼야 하는지 말해준다
		// (조용히 접두를 벗겨 주면 "그래도 되는 형식"이 되어 계약이 두 개가 된다).
		return nil, zero, errors.Join(errBadRequest,
			errors.New("사진 인코딩(base64)이 올바르지 않아요 — `data:image/...;base64,` 접두는 빼고 보내주세요"))
	}
	if !bytes.HasPrefix(raw, format.magic) {
		// 선언과 실제가 다르다는 것을 그대로 말한다: 확장자만 바꾼 파일이 대부분이라
		// "형식이 아니에요"보다 이 문구가 실제로 문제를 푼다.
		return nil, zero, errors.Join(errBadRequest,
			fmt.Errorf("사진 내용이 %s 형식이 아니에요 — 파일 형식을 확인해주세요", ct))
	}
	// 크기를 완결성보다 **먼저** 본다: 완결성 검사는 버퍼를 훑으므로, 애초에 받지 않을
	// 파일을 훑을 이유가 없다(싼 검사부터라는 이 함수의 순서 원칙 그대로).
	if len(raw) > maxStaffPhotoBytes {
		return nil, zero, errors.Join(errBadRequest,
			fmt.Errorf("사진이 너무 커요(최대 2MB, 지금 %.1fMB)", float64(len(raw))/(1<<20)))
	}
	if !format.complete(raw) {
		return nil, zero, errors.Join(errBadRequest,
			errors.New("사진 파일이 손상됐거나 잘렸어요 — 다시 선택해주세요"))
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil {
		return nil, zero, errors.Join(errBadRequest, errors.New("사진을 해석할 수 없어요 — 다른 파일로 시도해주세요"))
	}
	if cfg.Width < minStaffPhotoSide || cfg.Width > maxStaffPhotoSide ||
		cfg.Height < minStaffPhotoSide || cfg.Height > maxStaffPhotoSide {
		return nil, zero, errors.Join(errBadRequest,
			fmt.Errorf("사진 크기가 올바르지 않아요(가로·세로 %d~%dpx, 지금 %d×%d)",
				minStaffPhotoSide, maxStaffPhotoSide, cfg.Width, cfg.Height))
	}
	return raw, format, nil
}

// staffPhotoObjectPath — 저장된 photo_url이 **이 기능이 올린 파일**을 가리키면 그 오브젝트
// 경로를, 아니면 빈 문자열을 돌려준다(교체 시 옛 파일 삭제 판정).
//
// 경로를 프로필에 따로 저장하지 않고 URL에서 되뽑는 이유: `PUT /v1/staff/{uid}/profile`은
// **통 교체**라 어드민이 보내지 않은 필드는 지워진다(v1.6 계약). 서버만 관리하는
// `photo_path` 칸을 두면 프로필을 한 번 저장하는 순간 조용히 비고, 그때부터 교체가
// 옛 파일을 영원히 남긴다. URL은 어드민이 항상 되돌려 보내는 값이라 그 함정이 없다.
//
// 접두 검사가 안전장치다: 대표가 손으로 넣은 임의 URL(예: 회원 체형사진 경로를 가리키는
// 토큰 URL)이 들어와도 `staff/photos/` 밖은 절대 지우지 않는다.
func staffPhotoObjectPath(photoURL string) string {
	if photoURL == "" {
		return ""
	}
	u, err := url.Parse(photoURL)
	if err != nil || u.Host != "firebasestorage.googleapis.com" {
		return ""
	}
	// /v0/b/{bucket}/o/{escaped object path}
	parts := strings.SplitN(strings.TrimPrefix(u.Path, "/"), "/", 5)
	if len(parts) != 5 || parts[0] != "v0" || parts[1] != "b" || parts[3] != "o" {
		return ""
	}
	// u.Path는 이미 디코드된 값이지만 EscapedPath 기준으로 한 번 더 푼다 — %2F로 인코딩된
	// 경로 구분자가 원본이라 그것을 살려야 오브젝트 이름이 맞는다.
	escaped := strings.SplitN(strings.TrimPrefix(u.EscapedPath(), "/"), "/", 5)
	if len(escaped) != 5 {
		return ""
	}
	object, err := url.PathUnescape(escaped[4])
	if err != nil {
		return ""
	}
	if !strings.HasPrefix(object, staffPhotoPrefix) || strings.Contains(object, "..") {
		return ""
	}
	return object
}

// UploadStaffPhoto — POST /v1/staff/{uid}/photo(owner 전용, v2.25).
//
// **owner 전용인 이유**(프로필 편집 PUT은 본인 트레이너도 되는데 여기만 다르다): 이 호출은
// 센터 공용 버킷에 파일을 만든다. 되돌리는 수단은 대표에게만 있고, 비용·용량도 대표가 진다 —
// 스태프 관리 계열(생성·정정·이관·퇴사)이 전부 owner 전용인 것과 같은 경계다.
//
// 순서가 이 함수의 설계다:
//
//	① 검증 → ② 스태프 조회 → ③ 업로드 → ④ 프로필 저장 → ⑤ 옛 파일 삭제(best-effort)
//
//	③이 ④보다 앞이라 업로드가 실패하면 프로필은 손대지 않은 채 그대로다(재시도 가능).
//	⑤가 ④보다 뒤인 이유는 더 중요하다: 저장이 실패했는데 옛 파일을 먼저 지우면 **프로필이
//	가리키는 URL이 죽은 링크가 된다**. 새 URL이 확실히 박힌 뒤에만 옛것을 지운다.
//	⑤의 실패는 업로드를 실패시키지 않는다 — 대표 입장에서 사진은 이미 바뀌었고,
//	남은 파일 한 개는 사람이 개입할 문제가 아니다(로그로 남긴다).
func (s *Service) UploadStaffPhoto(ctx context.Context, p Principal, uid string, req StaffPhotoRequest) (StaffPhotoResponse, error) {
	var res StaffPhotoResponse
	if !p.IsOwner() {
		return res, ErrForbidden
	}
	if uid == "" {
		return res, store.ErrNotFound // 다른 스태프 동사와 같은 매핑(DeactivateStaff 선례)
	}
	if !staffPhotoUIDPattern.MatchString(uid) {
		// 경로에 실릴 값이다 — 여기서 막지 않으면 `../`가 다른 폴더 쓰기가 된다.
		return res, errors.Join(errBadRequest, errors.New("스태프 식별자가 올바르지 않아요"))
	}
	raw, format, err := decodeStaffPhoto(req)
	if err != nil {
		return res, err
	}
	st, err := s.store.GetStaff(ctx, p.CenterID, uid)
	if err != nil {
		return res, err // 없는 스태프 앞으로 파일을 만들지 않는다(고아 파일의 가장 흔한 출처)
	}
	suffix, err := randomHex(4)
	if err != nil {
		return res, err
	}
	// 난수를 붙이는 이유는 두 가지다: ① 같은 uid의 교체본이 CDN·브라우저 캐시에서 옛 사진으로
	// 보이지 않는다(경로가 곧 버전) ② uid만으로 경로를 추측해 남의 사진을 훑는 것을 막는다
	// (토큰이 1차 방어선이고 이건 그 위의 얇은 한 겹).
	path := fmt.Sprintf("%s%s-%s.%s", staffPhotoPrefix, uid, suffix, format.ext)
	photoURL, err := s.uploader.Upload(ctx, path, format.contentType, raw)
	if err != nil {
		return res, err
	}

	prevPath := staffPhotoObjectPath(st.Profile.PhotoURL)
	st.Profile.Normalize() // 배열 null 금지 규약(v1.3) — 저장 전 하이진은 프로필 PUT과 동일
	st.Profile.PhotoURL = photoURL
	if err := s.store.SaveStaff(ctx, p.CenterID, st); err != nil {
		// 프로필에 박히지 못한 파일은 아무도 가리키지 않는다 — 그 자리에서 지운다.
		// 실패해도 원래 에러를 덮지 않는다(사용자에게는 저장 실패가 사실이다).
		s.deleteStaffPhotoObject(ctx, path, "프로필 저장 실패 후 방금 올린 파일")
		return res, err
	}
	// 비교 대상은 생성한 경로가 아니라 **새 URL이 실제로 가리키는 경로**다. 둘은 정상
	// 경로에서 같지만, 같은 오브젝트를 두 번 가리키게 되는 어떤 경우에도(난수 충돌·
	// 업로더 구현 변경) 방금 올린 파일을 스스로 지우는 일이 없어야 한다.
	if newPath := staffPhotoObjectPath(photoURL); prevPath != "" && prevPath != newPath {
		s.deleteStaffPhotoObject(ctx, prevPath, "교체된 이전 프로필 사진")
	}
	res.PhotoURL = photoURL
	return res, nil
}

// deleteStaffPhotoObject — best-effort 삭제. MediaPurger를 재사용한다(파기 경계가 이미
// 있는데 두 번째 삭제 경로를 만들면 STORAGE_BUCKET 미설정 같은 조건에서 동작이 갈린다).
// 실패는 로그로만 남긴다 — 이 삭제가 업로드를 실패시키면 대표는 **성공한 일을 실패로** 보게 된다.
func (s *Service) deleteStaffPhotoObject(ctx context.Context, path, why string) {
	if _, err := s.media.DeleteObjects(ctx, []string{path}); err != nil {
		log.Printf("staff photo delete 실패(%s): path=%s err=%v — 버킷에 파일이 남습니다", why, path, err)
	}
}
