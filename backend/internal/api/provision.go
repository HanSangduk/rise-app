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
