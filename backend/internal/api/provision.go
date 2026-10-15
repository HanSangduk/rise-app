package api

// 스태프 온보딩(POST /v1/staff)의 로그인 계정 발급 경계. 어드민은 트레이너도 이메일/비밀번호로
// 로그인하므로 스태프를 만든다는 건 Firebase 계정을 만든다는 뜻이다 — 그 SDK 호출을 인터페이스
// 뒤로 숨겨 테스트·로컬 구동이 네트워크 없이 돌게 한다(Authenticator의 fbClient == nil 분기와 동일 전략).

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"net/url"
	"strings"

	gcs "cloud.google.com/go/storage"
	fbauth "firebase.google.com/go/v4/auth"
	"google.golang.org/api/iterator"
)

// UserProvisioner — 이메일에 대응하는 로그인 계정의 uid를 확보하고, 생애주기(퇴사·복직)에 맞춰
// 계정 자체를 잠그거나 푼다.
type UserProvisioner interface {
	// EnsureUser — email 계정의 uid. 계정이 없으면 만들고, 이미 있으면 그 uid를 재사용한다
	// (재초대 허용 — 기존 비밀번호·로그인 세션은 건드리지 않는다).
	//
	// created — **이번 호출이 계정을 새로 만들었는가**(v2.36). 이 한 칸이 응답의 정직함을
	// 가른다: 새로 만든 계정만 최초 비밀번호가 설정된 값이고, 재초대로 uid만 재사용한
	// 계정은 **그 사람이 이미 바꿔 둔 비밀번호**를 그대로 쓴다. 구분하지 않고 화면에
	// "비밀번호: 123456"을 띄우면 관리자가 틀린 값을 불러 주고, 상대는 로그인에 실패한 채
	// 원인을 모른다.
	EnsureUser(ctx context.Context, email string) (uid string, created bool, err error)
	// DisableUser — 퇴사 처리의 **2차 방어선**(v2.0): 계정을 Disabled로 바꾸고 리프레시 토큰을
	// 폐기해 재로그인·토큰 재발급을 막는다. 이미 발급된 ID 토큰은 검증이 폐기 확인을 하지 않아
	// 최대 1시간 유효하다 — 즉시성은 UserIndex 강등이 담당한다(계약 v2.0).
	DisableUser(ctx context.Context, uid string) error
	// EnableUser — 복직(reactivate) 시 계정 잠금 해제.
	EnableUser(ctx context.Context, uid string) error
	// DeleteUser — 회원탈퇴(v2.11)의 계정 **삭제**. 퇴사(DisableUser)와 의도적으로 다르다:
	//
	//   ① Identity Platform 계정에는 **전화번호가 그대로 들어 있다.** 잠그기만 하면 파기가 아니다.
	//   ② 계정이 살아 있으면 같은 번호로 다시 로그인해 **같은 uid**를 받는다 — UserIndex를
	//      지워도 가입 매칭이 다시 돌아 붙으므로 사용자 눈에는 "탈퇴가 안 된" 상태가 된다.
	//
	// 퇴사자는 복직할 수 있어 계정이 남아야 하지만, 탈퇴자는 돌아오더라도 **새 계정**으로 온다.
	// 없는 계정은 성공으로 본다(DisableUser와 같은 관용 + 재시도 멱등).
	DeleteUser(ctx context.Context, uid string) error
}

// MediaPurger — Cloud Storage에 올라간 원본 파일을 파기하는 경계(UserProvisioner와 같은 전략:
// SDK 호출을 인터페이스 뒤에 숨겨 테스트·로컬이 네트워크 없이 돈다).
//
// 왜 서버가 지우는가: `storage.rules`가 체형사진에 `allow delete: if false`를 걸어 뒀다.
// 그 규칙의 의도는 "클라이언트가 파일만 지워 메타데이터를 고아로 만들지 못하게"이고, 주석도
// *"정리는 서버 몫"*이라고 적어 뒀는데 **그 서버 경로가 존재한 적이 없었다**(계약 v2.9가
// "동의 철회·탈퇴 시 파기 수단이 0"이라고 명시한 갭이 바로 이것이다).
//
// Storage 보안 규칙은 **클라이언트 SDK에만** 적용되고 Admin SDK는 지나지 않는다. 그래서
// 규칙은 그대로 두고(교차 서비스 IAM·평가당 2문서 상한 영역을 건드리지 않는다) 서버가 메타와
// 파일을 짝으로 지운다.
type MediaPurger interface {
	// DeleteObjects — 오브젝트 경로 목록을 지우고 실제 삭제 건수를 돌려준다.
	// 이미 없는 오브젝트는 성공으로 센다(재시도 멱등) — 부분 실패 후 재호출이 막히면 안 된다.
	DeleteObjects(ctx context.Context, paths []string) (int, error)

	// ListObjects — [prefix]로 시작하는 오브젝트 경로 전부.
	//
	// **고아 파일을 찾는 유일한 길이다.** 파일은 남았는데 메타가 없어진 경우
	// (부분 실패·과거 버그) 서버는 그 존재조차 모른다 — 메타에서 출발하는 어떤
	// 경로로도 닿을 수 없다. 버킷 쪽에서 거꾸로 훑어야만 보인다.
	ListObjects(ctx context.Context, prefix string) ([]string, error)

	// Configured — 이 구현이 **실제 버킷에 닿는지**(v2.31 개정, P62 검증 반영). 미구성 구현은
	// DeleteObjects를 no-op 성공으로 돌려주는데(위 주석 — 탈퇴를 막지 않기 위해), 스태프 사진
	// 경로(퇴사·프로필 PUT·교체)는 그 "성공"을 믿고 photo_url을 비우면 **파일은 남고 포인터만
	// 사라진다**(발견 경로 0 — 고아). 호출측이 이 값으로 "지운 척"을 피한다: 미구성이면 파일을
	// 지운 것으로 치지 않고 photo_url을 유지한 채 로그만 남긴다. 회원탈퇴 경로는 종전대로
	// no-op 성공을 그대로 쓴다(탈퇴는 파기 실패로 막히면 안 되고, 메타도 함께 지워져 포인터가
	// 남을 자리가 없다).
	Configured() bool
}

// MediaUploader — 서버가 Cloud Storage에 파일을 **올리는** 경계(v2.25, P51). MediaPurger의
// 거울상이다: 규칙이 클라이언트 쓰기를 막아 둔 경로(`staff/photos/**`는 `allow read, write:
// if false`)에 Admin SDK만이 쓸 수 있고, 그 주석이 적어 둔 *"서버가 올리고 클라이언트는
// 다운로드 토큰 URL로 읽는다"*를 실재하게 한다.
//
// **파기(MediaPurger)와 합치지 않은 이유**: 둘의 미설정 시 동작이 정반대여야 한다.
// 파기는 버킷이 없으면 조용한 no-op으로 떨어져도 서비스가 돌아야 하지만(예약·결제가 멈출
// 이유가 없다), 업로드는 no-op이 되는 순간 **"저장했어요"라고 말하고 아무것도 저장하지 않는
// 거짓말**이 된다. 그래서 이쪽은 미설정이면 명시적으로 실패한다(ErrUploadUnavailable → 503).
type MediaUploader interface {
	// Upload — 오브젝트를 쓰고 **인증 없이 열리는 다운로드 URL**을 돌려준다.
	// 규칙이 이 경로의 클라이언트 read까지 막고 있으므로 SDK 경로로는 못 읽는다 —
	// Firebase 다운로드 토큰 URL만이 유일한 읽기 수단이다(규칙 주석의 설계 그대로).
	Upload(ctx context.Context, path, contentType string, data []byte) (url string, err error)
}

// ErrUploadUnavailable — 업로드 경계가 구성되지 않음(503 매핑). "잘못된 요청"이 아니라
// **서버 설정 문제**라서 4xx로 내리지 않는다: 대표가 사진을 바꿔도 고쳐지지 않고,
// 고칠 사람은 배포 설정을 쥔 쪽이다.
var ErrUploadUnavailable = errors.New("api: upload unavailable")

// MediaUploader — 인증 모드에 맞는 업로드 구현. MediaPurger와 같은 자리에서 갈리지만
// **폴백이 no-op이 아니다** — 미구성이면 호출마다 503을 내는 구현을 준다.
func (a *Authenticator) MediaUploader(ctx context.Context, bucket string) MediaUploader {
	if a.fbApp == nil {
		// 로컬 개발(FIREBASE_PROJECT 미설정)이 여기로 온다. 문구가 **두 값을 모두** 말해야
		// 한다 — 이 상태에서는 STORAGE_BUCKET만 채워도 열리지 않는다(Admin SDK 앱 자체가 없다).
		return unconfiguredUploader{reason: "사진 업로드가 설정되지 않았어요(서버에 FIREBASE_PROJECT·STORAGE_BUCKET 설정이 필요해요)"}
	}
	if bucket == "" {
		log.Printf("경고: STORAGE_BUCKET 미설정 — 트레이너 프로필 사진 업로드(POST /v1/staff/{uid}/photo)가 503으로 거부됩니다. 버킷 이름을 설정하세요")
		return unconfiguredUploader{reason: "사진 업로드 저장소가 설정되지 않았어요(관리자에게 STORAGE_BUCKET 설정을 요청해주세요)"}
	}
	client, err := a.fbApp.Storage(ctx)
	if err != nil {
		log.Printf("경고: Storage 클라이언트 초기화 실패(%v) — 트레이너 프로필 사진 업로드가 거부됩니다", err)
		return unconfiguredUploader{reason: "사진 저장소에 연결할 수 없어요(관리자 확인 필요)"}
	}
	handle, err := client.Bucket(bucket)
	if err != nil {
		log.Printf("경고: Storage 버킷 %q 접근 실패(%v) — 트레이너 프로필 사진 업로드가 거부됩니다", bucket, err)
		return unconfiguredUploader{reason: "사진 저장소에 연결할 수 없어요(관리자 확인 필요)"}
	}
	return firebaseMediaUploader{bucket: handle, bucketName: bucket}
}

// unconfiguredUploader — 업로드 경계 미구성. **조용한 성공을 절대 만들지 않는다**:
// dev no-op이 가짜 URL을 돌려주면 어드민은 "저장됨"을 보고, 회원 앱은 깨진 이미지를 보고,
// 아무도 원인에 도달하지 못한다(P22가 체형사진에서 실제로 겪은 실패 모양 — 조용한 no-op).
type unconfiguredUploader struct{ reason string }

func (u unconfiguredUploader) Upload(_ context.Context, _, _ string, _ []byte) (string, error) {
	return "", errors.Join(ErrUploadUnavailable, errors.New(u.reason))
}

// firebaseMediaUploader — Admin SDK(GCS 클라이언트)로 오브젝트를 쓰고 다운로드 토큰을 붙인다.
type firebaseMediaUploader struct {
	bucket     *gcs.BucketHandle
	bucketName string // 다운로드 URL 조립에 필요하다(핸들에서 되뽑지 않는다)
}

// Upload — 오브젝트 쓰기 + `firebaseStorageDownloadTokens` 메타데이터 부여.
//
// 이 메타데이터 키가 Firebase 콘솔의 "다운로드 URL 생성"과 **같은 메커니즘**이다: 값이 붙어
// 있으면 `firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?alt=media&token={token}`이
// 보안 규칙을 거치지 않고 열린다. 규칙이 이 경로의 read를 막아 둔 것과 모순이 아니라 설계다
// (storage.rules 주석: "토큰 URL은 규칙을 거치지 않으므로 여기서는 전면 차단이 맞다").
//
// 캐시: 파일명에 난수가 들어가 **내용이 바뀌면 경로도 바뀐다**(immutable). 그래서 길게 캐시해도
// 옛 사진이 남지 않는다 — 오히려 짧게 잡으면 회원 앱이 프로필을 열 때마다 원본을 다시 받는다.
func (u firebaseMediaUploader) Upload(ctx context.Context, path, contentType string, data []byte) (string, error) {
	token, err := randomHex(16) // 32자 — 추측으로 열 수 없어야 하는 유일한 방어선이다
	if err != nil {
		return "", err
	}
	w := u.bucket.Object(path).NewWriter(ctx)
	w.ContentType = contentType
	w.CacheControl = "public, max-age=31536000, immutable"
	w.Metadata = map[string]string{"firebaseStorageDownloadTokens": token}
	if _, err := w.Write(data); err != nil {
		_ = w.Close()
		return "", fmt.Errorf("storage write %q: %w", path, err)
	}
	// Close가 실제 업로드를 완료시킨다 — 여기 에러를 삼키면 쓰지 않은 파일의 URL을 돌려준다.
	if err := w.Close(); err != nil {
		return "", fmt.Errorf("storage close %q: %w", path, err)
	}
	return fmt.Sprintf("https://firebasestorage.googleapis.com/v0/b/%s/o/%s?alt=media&token=%s",
		u.bucketName, url.PathEscape(path), token), nil
}

// randomHex — crypto/rand n바이트의 hex 문자열(2n자).
func randomHex(n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

// Provisioner — 인증 모드에 맞는 구현. Firebase 모드면 Authenticator가 이미 초기화한 Admin SDK
// 클라이언트를 그대로 재사용한다(SDK 중복 초기화 금지 — 자격증명 로딩이 두 번 일어나지 않게).
func (a *Authenticator) Provisioner(initialPassword string) UserProvisioner {
	if a.fbClient == nil {
		return devUserProvisioner{}
	}
	return firebaseUserProvisioner{client: a.fbClient, initialPassword: initialPassword}
}

// MediaPurger — 인증 모드에 맞는 파일 파기 구현. Firebase 모드라도 **버킷 이름이 없으면
// 미구성 구현으로 떨어진다**(STORAGE_BUCKET 미설정). 기동을 막지 않는 이유: 이 값이 없다고
// 예약·결제·수업기록이 멈춰야 할 이유가 없다. 대신 **기동 로그에 경고를 남긴다** — 조용히
// no-op이 되면 탈퇴 화면이 "사진을 삭제했어요"라고 말하는데 실제로는 남는다.
//
// 미구성 구현(unconfiguredPurger)은 **두 동사의 실패 모양이 다르다**(v2.28, P56 A4):
// DeleteObjects는 no-op(탈퇴를 막지 않는다), ListObjects는 명시적 에러(reconcile을 조용히
// "고아 0건"으로 만들지 않는다). 그 이유는 타입 주석에 있다. reason 문구는 강등 원인마다
// 다르게 — 503 본문이 "무엇을 설정해야 하는지"를 말해야 고칠 사람이 원인에 도달한다
// (MediaUploader와 같은 규율).
func (a *Authenticator) MediaPurger(ctx context.Context, bucket string) MediaPurger {
	if a.fbApp == nil {
		// 로컬 개발(FIREBASE_PROJECT 미설정). 이 상태에서는 STORAGE_BUCKET만 채워도 열리지 않는다.
		return unconfiguredPurger{reason: "사진 저장소가 설정되지 않았어요(서버에 FIREBASE_PROJECT·STORAGE_BUCKET 설정이 필요해요)"}
	}
	if bucket == "" {
		log.Printf("경고: STORAGE_BUCKET 미설정 — 회원탈퇴 시 체형사진 **원본 파일이 버킷에 그대로 남습니다**(메타데이터만 삭제). 스태프 퇴사·프로필 사진 지우기는 파기를 건너뛰고 photo_url을 유지합니다(요청당 skipped 로그, v2.31). 고아 훑기(POST /v1/body-photos/reconcile)는 503으로 거부됩니다. 버킷 이름을 설정하세요")
		return unconfiguredPurger{reason: "사진 저장소가 설정되지 않았어요(관리자에게 STORAGE_BUCKET 설정을 요청해주세요)"}
	}
	client, err := a.fbApp.Storage(ctx)
	if err != nil {
		log.Printf("경고: Storage 클라이언트 초기화 실패(%v) — 회원탈퇴 시 체형사진 원본 파일이 남습니다. 스태프 퇴사·프로필 사진 지우기는 파기를 건너뛰고 photo_url을 유지합니다. 고아 훑기는 503으로 거부됩니다", err)
		return unconfiguredPurger{reason: "사진 저장소에 연결할 수 없어요(관리자 확인 필요)"}
	}
	handle, err := client.Bucket(bucket)
	if err != nil {
		log.Printf("경고: Storage 버킷 %q 접근 실패(%v) — 회원탈퇴 시 체형사진 원본 파일이 남습니다. 스태프 퇴사·프로필 사진 지우기는 파기를 건너뛰고 photo_url을 유지합니다. 고아 훑기는 503으로 거부됩니다", bucket, err)
		return unconfiguredPurger{reason: "사진 저장소에 연결할 수 없어요(관리자 확인 필요)"}
	}
	return firebaseMediaPurger{bucket: handle}
}

// devUserProvisioner — dev 모드(FIREBASE_PROJECT 미설정) 합성 uid. 이메일에서 **결정적으로**
// 파생한다: 같은 이메일을 두 번 초대하면 Firebase처럼 같은 uid가 나와야 "이미 등록된 스태프"
// 409가 로컬에서도 그대로 재현된다(랜덤 uid면 중복 초대가 조용히 통과해버린다).
type devUserProvisioner struct{}

// dev 모드는 **항상 created=true**다. 합성 uid라 "이미 있는 계정"이라는 상태 자체가 없고,
// 로컬에서 초대 화면을 열면 운영과 같은 최초 비밀번호 안내가 떠야 화면을 검증할 수 있다.
func (devUserProvisioner) EnsureUser(_ context.Context, email string) (string, bool, error) {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(email))))
	// 스토어의 ID 관례("{prefix}_{식별자}")를 따르되 순번 대신 해시를 쓴다 — 순번은 프로세스
	// 재시작마다 초기화돼 결정성을 잃고, api 레이어는 스토어의 시퀀스를 알지 못한다.
	return "staff_" + hex.EncodeToString(sum[:6]), true, nil
}

// dev 모드엔 잠글 계정 자체가 없다(합성 uid) — no-op. 퇴사 처리의 즉시 차단은 UserIndex
// 강등이 담당하므로 로컬에서도 동작이 그대로 재현된다.
func (devUserProvisioner) DisableUser(_ context.Context, _ string) error { return nil }
func (devUserProvisioner) EnableUser(_ context.Context, _ string) error  { return nil }
func (devUserProvisioner) DeleteUser(_ context.Context, _ string) error  { return nil }

// ErrMediaListUnavailable — 파기 경계가 구성되지 않아 버킷을 **훑을 수 없음**(503 매핑, v2.28).
// ErrUploadUnavailable과 같은 성격이다: 요청은 옳고 서버 설정이 문제라 4xx가 아니다.
var ErrMediaListUnavailable = errors.New("api: media listing unavailable")

// unconfiguredPurger — 파기 경계 미구성(로컬 개발 / STORAGE_BUCKET 미설정 / 버킷 접근 실패).
// **두 동사의 실패 모양이 일부러 다르다**(v2.28, P56 A4):
//
//   - DeleteObjects = no-op(요청받은 경로 수 그대로 성공). 이 경계를 쓰는 파기 경로는 탈퇴·
//     회원 삭제·유예 스윕인데, **파기 실패가 탈퇴를 막으면 안 된다**(P51 결정 — 버킷이 없다고
//     예약·결제·탈퇴가 멈출 이유가 없다). 건수를 0이 아니라 len(paths)로 돌려주는 이유: 0이면
//     로컬 탈퇴 응답이 "사진 0장 삭제"라고 말하는데 인메모리 스토어에는 실제로 메타가 지워져
//     있어 화면과 사실이 어긋난다. 이 no-op의 대가(원본 잔존)는 기동 로그 경고가 알린다.
//
//   - ListObjects = **명시적 에러**. 종전엔 nil,nil을 돌려줘 고아 훑기(reconcile)가 미구성 상태에서
//     항상 "고아 0건"이었다 — 그 도구는 바로 이 no-op이 남긴 고아 50개(v2.15) 때문에 만들어졌는데,
//     같은 강등이 그 도구까지 조용히 무력화했다. "버킷에 아무것도 없다"와 "버킷을 볼 수 없다"는
//     다른 사실이고, 후자를 전자로 보고하면 대표는 파일이 깨끗하다고 믿는다. 훑기는 조회 동사라
//     실패해도 아무것도 잃지 않는다 — 크게 실패하는 비용이 0이고, 조용히 성공하는 비용은
//     고지와 어긋난 잔존이다(unconfiguredUploader와 같은 판단: 조용한 성공을 만들지 않는다).
//
// 왜 DeleteObjects까지 에러로 만들지 않는가: 그러면 미구성 서버에서 탈퇴가 500이 되고, 자기
// 개인정보를 지울 권리(§36)가 배포 설정 하나에 막힌다. 탈퇴는 "메타·계정·인덱스 파기"가
// 본체이고 파일 파기는 그 일부라, 일부가 안 됐다고 본체를 거부하는 것이 더 큰 거짓이다.
type unconfiguredPurger struct{ reason string }

func (u unconfiguredPurger) ListObjects(_ context.Context, _ string) ([]string, error) {
	return nil, errors.Join(ErrMediaListUnavailable, errors.New(u.reason))
}

func (unconfiguredPurger) DeleteObjects(_ context.Context, paths []string) (int, error) {
	return len(paths), nil
}

// 미구성 — 스태프 사진 경로는 이 값을 보고 "지운 척"을 하지 않는다(MediaPurger.Configured 주석).
func (unconfiguredPurger) Configured() bool { return false }

// firebaseUserProvisioner — Firebase Admin SDK 구현(프로덕션).
//
// initialPassword — 새로 만드는 계정에 걸 최초 비밀번호(config.InitialStaffPassword, v2.36).
// 난수가 아니라 **관리자가 알고 있는 값**이라 초대받은 사람에게 그대로 불러 줄 수 있다.
type firebaseUserProvisioner struct {
	client          *fbauth.Client
	initialPassword string
}

func (f firebaseUserProvisioner) EnsureUser(ctx context.Context, email string) (string, bool, error) {
	switch u, err := f.client.GetUserByEmail(ctx, email); {
	case err == nil:
		return u.UID, false, nil // 재초대 — 기존 계정 재사용(비밀번호는 그 사람 것이 그대로다)
	case !fbauth.IsUserNotFound(err):
		return "", false, err
	}
	u, err := f.client.CreateUser(ctx, (&fbauth.UserToCreate{}).Email(email).Password(f.initialPassword).EmailVerified(false))
	if err != nil {
		// 동시 초대 경합으로 그 사이 생성됐으면 조회로 되돌아가 uid를 재사용한다.
		// **created=false**로 돌려준다 — 이 호출은 만들지 않았고, 먼저 만든 쪽이 건 비밀번호가
		// 무엇인지 여기서는 알 수 없다(같은 값일 가능성이 높아도 단언하지 않는다).
		if fbauth.IsEmailAlreadyExists(err) {
			if existing, gerr := f.client.GetUserByEmail(ctx, email); gerr == nil {
				return existing.UID, false, nil
			}
		}
		return "", false, err
	}
	return u.UID, true, nil
}

// DisableUser — Disabled(true) + RevokeRefreshTokens. 순서가 중요하다: 먼저 계정을 잠가
// 새 로그인을 막고, 그다음 이미 나가 있는 세션의 리프레시 토큰을 폐기한다(반대 순서면 폐기와
// 잠금 사이에 갱신 요청이 통과할 수 있다).
//
// 계정이 없으면(수동 시딩된 uid 등) 잠글 대상이 없는 것이므로 성공으로 본다 — Firebase 계정
// 부재 하나로 퇴사 처리 전체가 실패하면 Staff·UserIndex까지 못 바꾸고 막힌다.
func (f firebaseUserProvisioner) DisableUser(ctx context.Context, uid string) error {
	if _, err := f.client.UpdateUser(ctx, uid, (&fbauth.UserToUpdate{}).Disabled(true)); err != nil {
		if fbauth.IsUserNotFound(err) {
			return nil
		}
		return err
	}
	if err := f.client.RevokeRefreshTokens(ctx, uid); err != nil && !fbauth.IsUserNotFound(err) {
		return err
	}
	return nil
}

// EnableUser — 복직. 폐기된 리프레시 토큰은 되살리지 않는다(되살릴 수단도 없다) —
// 복직자는 한 번 다시 로그인한다.
func (f firebaseUserProvisioner) EnableUser(ctx context.Context, uid string) error {
	if _, err := f.client.UpdateUser(ctx, uid, (&fbauth.UserToUpdate{}).Disabled(false)); err != nil {
		if fbauth.IsUserNotFound(err) {
			return nil
		}
		return err
	}
	return nil
}

// DeleteUser — 회원탈퇴(v2.11). 계정과 함께 그 안의 전화번호도 사라진다.
//
// ⚠ 이 호출 **이후에도 이미 발급된 ID 토큰은 최대 1시간 유효하다** — VerifyIDToken은 계정
// 존재나 폐기 여부를 확인하지 않는다(v2.0 퇴사 처리 주석과 같은 사실). 탈퇴 절차에서는 그것이
// 오히려 필요한 성질이다: 계정을 먼저 지운 뒤 DB 파기가 실패해도 **같은 토큰으로 재시도**할 수
// 있어야 하기 때문이다(service_account.go의 단계 순서 주석 참고).
func (f firebaseUserProvisioner) DeleteUser(ctx context.Context, uid string) error {
	if err := f.client.DeleteUser(ctx, uid); err != nil && !fbauth.IsUserNotFound(err) {
		return err
	}
	return nil
}

// firebaseMediaPurger — Admin SDK로 버킷 오브젝트를 지운다(보안 규칙을 지나지 않는다).
type firebaseMediaPurger struct{ bucket *gcs.BucketHandle }

// 실제 버킷 핸들을 쥐고 있다 — DeleteObjects의 성공은 실제 삭제다.
func (firebaseMediaPurger) Configured() bool { return true }

func (p firebaseMediaPurger) DeleteObjects(ctx context.Context, paths []string) (int, error) {
	n := 0
	for _, path := range paths {
		if path == "" {
			continue // 빈 경로는 가리킬 오브젝트가 없다(v2.10부터 저장 시 400이지만 구 레코드가 있을 수 있다)
		}
		err := p.bucket.Object(path).Delete(ctx)
		switch {
		case err == nil, errors.Is(err, gcs.ErrObjectNotExist):
			// 이미 없는 것도 "지워진 상태"다 — 재시도가 여기서 막히면 나머지 경로가 영영 남는다.
			n++
		default:
			// 부분 삭제 상태로 멈춘다. 호출측이 이 실패를 500으로 올리고 DB는 손대지 않으므로
			// 재시도가 남은 경로를 마저 지운다(메타데이터가 아직 살아 있어 경로를 다시 찾는다).
			return n, fmt.Errorf("storage delete %q: %w", path, err)
		}
	}
	return n, nil
}

func (p firebaseMediaPurger) ListObjects(ctx context.Context, prefix string) ([]string, error) {
	it := p.bucket.Objects(ctx, &gcs.Query{Prefix: prefix})
	var out []string
	for {
		attrs, err := it.Next()
		if errors.Is(err, iterator.Done) {
			return out, nil
		}
		if err != nil {
			return nil, fmt.Errorf("storage list %q: %w", prefix, err)
		}
		out = append(out, attrs.Name)
	}
}

// tempPassword — **v2.36에서 사용을 멈춘 난수 비밀번호 생성기**(crypto/rand 32바이트 → base64url).
//
// 왜 지웠는지 남겨 둔다: 이 값은 아무에게도 알려주지 않는 설계였고, 초대받은 사람은 비밀번호
// 재설정 메일로 스스로 정하게 되어 있었다. 그런데 **센터 생성 경로에는 그 메일을 보내는 코드가
// 없었다** — 새 센터 대표는 메일도 못 받고 비밀번호도 모르는 계정만 받았다(람 보고, P71).
// 지금은 config.InitialStaffPassword를 걸고 그 값을 생성 응답에 담아 화면이 보여 준다.
//
// 되살릴 조건: 초대 메일 발송이 **서버 책임**이 되면(현재는 어드민 프론트의 클라이언트 SDK가
// 보낸다) 난수 비밀번호 + 서버 발송이 다시 더 안전한 조합이 된다. 그때까지는 죽은 코드로 두지
// 않고 지운다 — 아래 함수는 삭제됐고 이 주석만 이유로 남는다.
