package api

// 스태프 온보딩(POST /v1/staff)의 로그인 계정 발급 경계. 어드민은 트레이너도 이메일/비밀번호로
// 로그인하므로 스태프를 만든다는 건 Firebase 계정을 만든다는 뜻이다 — 그 SDK 호출을 인터페이스
// 뒤로 숨겨 테스트·로컬 구동이 네트워크 없이 돌게 한다(Authenticator의 fbClient == nil 분기와 동일 전략).

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
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
	EnsureUser(ctx context.Context, email string) (uid string, err error)
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
func (a *Authenticator) Provisioner() UserProvisioner {
	if a.fbClient == nil {
		return devUserProvisioner{}
	}
	return firebaseUserProvisioner{client: a.fbClient}
}

// MediaPurger — 인증 모드에 맞는 파일 파기 구현. Firebase 모드라도 **버킷 이름이 없으면
// dev no-op으로 떨어진다**(STORAGE_BUCKET 미설정). 기동을 막지 않는 이유: 이 값이 없다고
// 예약·결제·수업기록이 멈춰야 할 이유가 없다. 대신 **기동 로그에 경고를 남긴다** — 조용히
// no-op이 되면 탈퇴 화면이 "사진을 삭제했어요"라고 말하는데 실제로는 남는다.
func (a *Authenticator) MediaPurger(ctx context.Context, bucket string) MediaPurger {
	if a.fbApp == nil {
		return devMediaPurger{}
	}
	if bucket == "" {
		log.Printf("경고: STORAGE_BUCKET 미설정 — 회원탈퇴 시 체형사진 **원본 파일이 버킷에 그대로 남습니다**(메타데이터만 삭제). 버킷 이름을 설정하세요")
		return devMediaPurger{}
	}
	client, err := a.fbApp.Storage(ctx)
	if err != nil {
		log.Printf("경고: Storage 클라이언트 초기화 실패(%v) — 회원탈퇴 시 체형사진 원본 파일이 남습니다", err)
		return devMediaPurger{}
	}
	handle, err := client.Bucket(bucket)
	if err != nil {
		log.Printf("경고: Storage 버킷 %q 접근 실패(%v) — 회원탈퇴 시 체형사진 원본 파일이 남습니다", bucket, err)
		return devMediaPurger{}
	}
	return firebaseMediaPurger{bucket: handle}
}

// devUserProvisioner — dev 모드(FIREBASE_PROJECT 미설정) 합성 uid. 이메일에서 **결정적으로**
// 파생한다: 같은 이메일을 두 번 초대하면 Firebase처럼 같은 uid가 나와야 "이미 등록된 스태프"
// 409가 로컬에서도 그대로 재현된다(랜덤 uid면 중복 초대가 조용히 통과해버린다).
type devUserProvisioner struct{}

func (devUserProvisioner) EnsureUser(_ context.Context, email string) (string, error) {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(email))))
	// 스토어의 ID 관례("{prefix}_{식별자}")를 따르되 순번 대신 해시를 쓴다 — 순번은 프로세스
	// 재시작마다 초기화돼 결정성을 잃고, api 레이어는 스토어의 시퀀스를 알지 못한다.
	return "staff_" + hex.EncodeToString(sum[:6]), nil
}

// dev 모드엔 잠글 계정 자체가 없다(합성 uid) — no-op. 퇴사 처리의 즉시 차단은 UserIndex
// 강등이 담당하므로 로컬에서도 동작이 그대로 재현된다.
func (devUserProvisioner) DisableUser(_ context.Context, _ string) error { return nil }
func (devUserProvisioner) EnableUser(_ context.Context, _ string) error  { return nil }
func (devUserProvisioner) DeleteUser(_ context.Context, _ string) error  { return nil }

// devMediaPurger — dev 모드엔 지울 버킷이 없다. 건수는 **요청받은 경로 수 그대로** 돌려준다:
// 0을 돌려주면 로컬 탈퇴 응답이 "사진 0장 삭제"라고 말하는데, 인메모리 스토어에는 실제로
// 메타가 지워져 있어 화면과 사실이 어긋난다.
type devMediaPurger struct{}

// dev 모드엔 버킷이 없다 — 훑을 대상이 0개라는 뜻이지 실패가 아니다.
func (devMediaPurger) ListObjects(_ context.Context, _ string) ([]string, error) {
	return nil, nil
}

func (devMediaPurger) DeleteObjects(_ context.Context, paths []string) (int, error) {
	return len(paths), nil
}

// firebaseUserProvisioner — Firebase Admin SDK 구현(프로덕션).
type firebaseUserProvisioner struct{ client *fbauth.Client }

func (f firebaseUserProvisioner) EnsureUser(ctx context.Context, email string) (string, error) {
	switch u, err := f.client.GetUserByEmail(ctx, email); {
	case err == nil:
		return u.UID, nil // 재초대 — 기존 계정 재사용
	case !fbauth.IsUserNotFound(err):
		return "", err
	}
	pw, err := tempPassword()
	if err != nil {
		return "", err
	}
	u, err := f.client.CreateUser(ctx, (&fbauth.UserToCreate{}).Email(email).Password(pw).EmailVerified(false))
	if err != nil {
		// 동시 초대 경합으로 그 사이 생성됐으면 조회로 되돌아가 uid를 재사용한다.
		if fbauth.IsEmailAlreadyExists(err) {
			if existing, gerr := f.client.GetUserByEmail(ctx, email); gerr == nil {
				return existing.UID, nil
			}
		}
		return "", err
	}
	return u.UID, nil
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

// tempPassword — 초대 계정의 임시 비밀번호(crypto/rand 32바이트 → base64url 43자).
// **아무에게도 알려주지 않는 값**이다: 응답·로그에 남기지 않고, 트레이너는 어드민이 생성 직후
// 보내는 비밀번호 재설정 메일(클라이언트 SDK sendPasswordResetEmail)로 자기 비밀번호를 정한다.
// 계정에 비밀번호를 아예 안 걸면 이메일/비밀번호 공급자가 붙지 않아 재설정 메일이 나가지 않는다.
func tempPassword() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}
