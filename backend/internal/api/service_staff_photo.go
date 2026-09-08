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
// 삭제 판정이 붙는 자리는 셋이다: 업로드 교체(⑤) · 프로필 PUT의 지우기/교체(UpdateStaffProfile) ·
// 퇴사 처리(DeactivateStaff ③, v2.31). 셋 다 접두만이 아니라 **`{uid}-` 명의까지** 본다
// (ownedStaffPhotoPath) — 접두만 보면 A의 photo_url이 재직자 B의 파일을 가리키는 순간 A의 퇴사가
// B의 얼굴을 지운다(P62 검증 이슈 1).
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

// parseStaffPhotoURL — Firebase 다운로드 URL을 (버킷, 오브젝트 경로)로 되뽑는다. `staff/photos/`
// 밖이거나 모양이 다르면 둘 다 빈 문자열이다.
//
// 경로를 프로필에 따로 저장하지 않고 URL에서 되뽑는 이유: `PUT /v1/staff/{uid}/profile`은
// **통 교체**라 어드민이 보내지 않은 필드는 지워진다(v1.6 계약). 서버만 관리하는
// `photo_path` 칸을 두면 프로필을 한 번 저장하는 순간 조용히 비고, 그때부터 교체가
// 옛 파일을 영원히 남긴다. URL은 어드민이 항상 되돌려 보내는 값이라 그 함정이 없다.
//
// 접두 검사가 1차 안전장치다: 대표가 손으로 넣은 임의 URL(예: 회원 체형사진 경로를 가리키는
// 토큰 URL)이 들어와도 `staff/photos/` 밖은 절대 지우지 않는다. 명의(uid)·버킷 검사는
// ownedStaffPhotoPath가 그 위에 얹는다.
func parseStaffPhotoURL(photoURL string) (bucket, object string) {
	if photoURL == "" {
		return "", ""
	}
	u, err := url.Parse(photoURL)
	if err != nil || u.Host != "firebasestorage.googleapis.com" {
		return "", ""
	}
	// /v0/b/{bucket}/o/{escaped object path}
	parts := strings.SplitN(strings.TrimPrefix(u.Path, "/"), "/", 5)
	if len(parts) != 5 || parts[0] != "v0" || parts[1] != "b" || parts[3] != "o" {
		return "", ""
	}
	// u.Path는 이미 디코드된 값이지만 EscapedPath 기준으로 한 번 더 푼다 — %2F로 인코딩된
	// 경로 구분자가 원본이라 그것을 살려야 오브젝트 이름이 맞는다.
	escaped := strings.SplitN(strings.TrimPrefix(u.EscapedPath(), "/"), "/", 5)
	if len(escaped) != 5 {
		return "", ""
	}
	object, err = url.PathUnescape(escaped[4])
	if err != nil {
		return "", ""
	}
	if !strings.HasPrefix(object, staffPhotoPrefix) || strings.Contains(object, "..") {
		return "", ""
	}
	return parts[2], object
}

// staffPhotoObjectPath — photo_url이 `staff/photos/` 안의 오브젝트를 가리키면 그 경로, 아니면 "".
// **삭제 판정에 직접 쓰지 않는다** — 명의를 보지 않는다. 삭제 판정은 ownedStaffPhotoPath.
func staffPhotoObjectPath(photoURL string) string {
	_, object := parseStaffPhotoURL(photoURL)
	return object
}

// staffOwnedPhotoPath — photo_url이 **이 uid 명의로 이 기능이 올린 파일**(`staff/photos/{uid}-…`,
// UploadStaffPhoto의 명명 규칙)을 가리킬 때만 오브젝트 경로를 돌려준다. 다른 uid 명의·외부
// URL·모양이 다른 URL은 전부 "" — 호출측은 그것을 외부 URL과 똑같이 다룬다(파일·포인터 무변경).
//
// 왜 접두만으로 부족한가(P62 검증 이슈 1): A의 프로필에 재직자 B의 파일 URL이 들어 있으면
// (대표가 복사해 붙여 넣는 것만으로 가능하다 — PUT은 http(s)면 무엇이든 받는다) 접두 판정은
// 그것을 "우리 파일"로 보고 A의 퇴사·[사진 지우기]가 **B의 얼굴을 지운다**. B의 photo_url은
// 그대로 남아 죽은 링크가 되고, B는 아무 동사도 부르지 않았다. 파일 이름에 실린 uid가 곧
// 소유권이므로 그것을 판정에 넣는다. `{uid}-`의 하이픈까지 비교해야 "t1"이 "t10-…"에 걸리지
// 않는다.
func staffOwnedPhotoPath(uid, photoURL string) string {
	if uid == "" {
		return ""
	}
	object := staffPhotoObjectPath(photoURL)
	if object == "" || !strings.HasPrefix(object, staffPhotoPrefix+uid+"-") {
		return ""
	}
	return object
}

// ownedStaffPhotoPath — staffOwnedPhotoPath에 **버킷 명의**를 얹은 서비스판. 삭제 판정 세 자리
// (퇴사 ③·프로필 PUT·교체 ⑤)는 전부 이것을 쓴다.
//
// 버킷을 보는 이유: DeleteObjects는 서버가 묶인 버킷(STORAGE_BUCKET) 안의 경로만 지우는데,
// 다른 버킷의 같은 이름 URL을 우리 것으로 판정하면 **우리 버킷의 동명 파일**을 지우게 된다
// (다른 프로젝트·이전 버킷의 URL이 프로필에 남아 있는 경우). 버킷이 설정되지 않은
// 환경(로컬·미구성)은 비교 기준이 없으므로 uid 판정만으로 간다 — 그 환경의 purger는 어차피
// 미구성이라 실제 삭제가 없다(Configured=false → purgeStaffPhoto가 건너뛴다).
func (s *Service) ownedStaffPhotoPath(uid, photoURL string) string {
	object := staffOwnedPhotoPath(uid, photoURL)
	if object == "" {
		return ""
	}
	if want := s.cfg.StorageBucket; want != "" {
		if bucket, _ := parseStaffPhotoURL(photoURL); bucket != want {
			return ""
		}
	}
	return object
}

// UploadStaffPhoto — POST /v1/staff/{uid}/photo(owner 전용, v2.25).
//
// **owner 전용인 이유**(프로필 편집 PUT은 본인 트레이너도 되는데 여기만 다르다): 이 호출은
// 센터 공용 버킷에 파일을 만든다. 되돌리는 수단은 대표에게만 있고, 비용·용량도 대표가 진다 —
// 스태프 관리 계열(생성·정정·이관·퇴사)이 전부 owner 전용인 것과 같은 경계다.
//
// 순서가 이 함수의 설계다(v2.31 개정 — ⑤가 ④ 앞으로, 실패 전파):
//
//	① 검증 → ② 스태프 조회 → ③ 새 파일 업로드 → ⑤ 옛 파일 삭제(이 uid 명의만) → ④ 프로필 저장
//
//	③이 나머지보다 앞이라 업로드가 실패하면 프로필은 손대지 않은 채 그대로다(재시도 가능).
//	⑤가 ④ **앞**인 이유(v2.25는 뒤였고 best-effort였다): 저장 뒤에 지우면 삭제 실패 시 새 URL은
//	이미 박혔고 옛 파일은 아무도 가리키지 않는 고아가 된다 — 발견 경로 0(P22). 앞에 두면 ⑤가
//	실패했을 때 방금 올린 새 파일을 best-effort로 되지우고 에러를 올린다: 프로필은 무변경이고
//	옛 파일은 옛 URL이 그대로 가리키므로 잃는 것이 없다. 대표는 "사진 교체 실패"를 보고 다시
//	올린다 — privacy.html "교체하거나 지우면 이전 파일은 삭제되며"가 참이 되는 유일한 정책이다
//	(best-effort면 실패한 삭제를 성공한 교체 뒤에 숨긴다). 퇴사 ③·프로필 PUT과 같은 정책.
//	④가 실패하면 "새 파일 고아 + 옛 URL 죽은 링크" 창이 생긴다(옛 파일은 이미 없다). 방금 올린
//	파일은 그 자리에서 되지우고, 재시도(업로드 다시 → prev 삭제 = ErrObjectNotExist 성공 → 저장)
//	로 수렴한다.
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
	// 퇴사자(inactive) 앞으로는 파일을 만들지 않는다(v2.31). 퇴사 처리가 사진을 파기했는데
	// 대표의 실수 한 번으로 새 파일이 생기면 파기가 되감긴다 — 파기의 역행 경로 차단.
	// 업로드(③) 전이라 버킷에 아무것도 생기지 않는다. 재입사(reactivate/재초대) 뒤엔 자연히 열린다.
	if !st.IsActive() {
		return res, errors.Join(errBadRequest, errors.New("퇴사 처리된 스태프의 사진은 올릴 수 없어요 — 재입사 처리 후 올려주세요"))
	}
	suffix, err := randomHex(4)
	if err != nil {
		return res, err
	}
	// 난수를 붙이는 이유는 두 가지다: ① 같은 uid의 교체본이 CDN·브라우저 캐시에서 옛 사진으로
	// 보이지 않는다(경로가 곧 버전) ② uid만으로 경로를 추측해 남의 사진을 훑는 것을 막는다
	// (토큰이 1차 방어선이고 이건 그 위의 얇은 한 겹).
	// 명명 규칙 `staff/photos/{uid}-{난수}.{ext}` — 파일 이름의 uid가 곧 소유권이다
	// (staffOwnedPhotoPath가 이 규칙으로 "이 uid 명의인가"를 되읽는다. 규칙을 바꾸면 그쪽도 같이).
	path := fmt.Sprintf("%s%s-%s.%s", staffPhotoPrefix, uid, suffix, format.ext)
	photoURL, err := s.uploader.Upload(ctx, path, format.contentType, raw)
	if err != nil {
		return res, err
	}

	// ⑤ 옛 파일 삭제 — 저장 **앞**. 비교 대상은 생성한 경로가 아니라 **새 URL이 실제로 가리키는
	// 경로**다. 둘은 정상 경로에서 같지만, 같은 오브젝트를 두 번 가리키게 되는 어떤 경우에도
	// (난수 충돌·업로더 구현 변경) 방금 올린 파일을 스스로 지우는 일이 없어야 한다.
	prevPath, newPath := s.ownedStaffPhotoPath(uid, st.Profile.PhotoURL), staffPhotoObjectPath(photoURL)
	if prevPath != "" && prevPath != newPath {
		if _, err := s.purgeStaffPhoto(ctx, uid, prevPath, "교체된 이전 프로필 사진"); err != nil {
			// 옛 파일이 남았으니 새 파일이 고아가 될 차례다 — 되지운다(best-effort: 이 삭제까지 실패하면
			// 재시도 업로드가 다른 난수 경로를 만들어 이 파일은 남는다. 그 잔존은 로그가 유일한 흔적이다).
			// 원래 에러를 덮지 않는다 — 대표에게는 "교체 실패"가 사실이고 프로필은 무변경이다.
			_ = s.deleteStaffPhotoObject(ctx, uid, path, "이전 사진 삭제 실패 후 방금 올린 파일")
			return res, err
		}
	}
	st.Profile.Normalize() // 배열 null 금지 규약(v1.3) — 저장 전 하이진은 프로필 PUT과 동일
	st.Profile.PhotoURL = photoURL
	if err := s.store.SaveStaff(ctx, p.CenterID, st); err != nil {
		// 프로필에 박히지 못한 파일은 아무도 가리키지 않는다 — 그 자리에서 지운다.
		// 실패해도 원래 에러를 덮지 않는다(사용자에게는 저장 실패가 사실이다) — 반환 에러는 로그만.
		// 옛 파일은 ⑤에서 이미 지워졌으므로 옛 URL은 죽은 링크로 남는다(아바타 이니셜 폴백) —
		// 재시도가 수렴시킨다(함수 주석의 실패 창).
		_ = s.deleteStaffPhotoObject(ctx, uid, path, "프로필 저장 실패 후 방금 올린 파일")
		return res, err
	}
	res.PhotoURL = photoURL
	return res, nil
}

// purgeStaffPhoto — 스태프 사진 파기 세 자리(퇴사 ③·프로필 PUT·교체 ⑤)의 공통 정책.
// 돌려주는 bool은 "파일이 실제로 지워졌다(포인터를 비워도 된다)"이다.
//
// purger가 미구성(Configured=false)이면 **지우지 않고 false, nil**이다. 미구성 DeleteObjects는
// no-op 성공이라(unconfiguredPurger — 탈퇴를 막지 않기 위한 정책) 그 성공을 믿고 photo_url을
// 비우면 파일은 남고 포인터만 사라진다 — 발견 경로 0(P62 검증 이슈 5). 호출측은 false를 받아
// photo_url을 유지하고 나머지 동사(퇴사 상태 전이·프로필 저장)는 그대로 진행한다: 즉시 차단의
// 본체는 ①②이지 파일이 아니고, 파일은 버킷이 구성되는 날 남은 포인터로 좇을 수 있다.
// 로그 한 줄이 그 잔존의 유일한 흔적이다(reconcile 도구가 없다).
func (s *Service) purgeStaffPhoto(ctx context.Context, uid, path, why string) (bool, error) {
	if !s.media.Configured() {
		log.Printf("staff photo purge skipped uid=%s path=%s (%s) — 파기 경계 미구성(STORAGE_BUCKET), photo_url 유지", uid, path, why)
		return false, nil
	}
	if err := s.deleteStaffPhotoObject(ctx, uid, path, why); err != nil {
		return false, err
	}
	return true, nil
}

// deleteStaffPhotoObject — 스태프 사진 오브젝트 하나를 지운다. MediaPurger를 재사용한다(파기
// 경계가 이미 있는데 두 번째 삭제 경로를 만들면 STORAGE_BUCKET 미설정 같은 조건에서 동작이 갈린다).
//
// 실패는 로그로 남기고 **에러를 돌려준다** — 파기 세 자리(퇴사 ③·프로필 PUT·교체 ⑤)는 전부
// purgeStaffPhoto를 거쳐 전파한다(v2.31 개정 — 교체도 best-effort가 아니다). 직접 부르는 곳은
// "방금 올린 새 파일 되지우기"뿐이고 그것만 best-effort다(원래 에러를 덮지 않기 위해).
// 로그에 uid를 싣는 이유: 파기가 실패한 채 남은 퇴사 행을 나중에 사람이 좇을 때 "PhotoURL이
// 남은 스태프"와 이 줄을 잇는 유일한 키다(reconcile 도구가 없다).
func (s *Service) deleteStaffPhotoObject(ctx context.Context, uid, path, why string) error {
	if _, err := s.media.DeleteObjects(ctx, []string{path}); err != nil {
		log.Printf("staff photo delete 실패(%s): uid=%s path=%s err=%v — 버킷에 파일이 남습니다", why, uid, path, err)
		return err
	}
	return nil
}
