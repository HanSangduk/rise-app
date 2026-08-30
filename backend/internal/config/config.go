// Package config는 환경변수 기반 설정을 로드한다(12-factor, wodshot 패턴 재사용).
package config

import (
	"errors"
	"os"
	"strings"
)

// CHECKIN_QR_TOKEN은 **더 이상 없다**(P49, 계약 v2.23). 데스크 체크인 토큰은 센터 문서에
// 저장되는 서버 발급 비밀이 됐다 — 어드민의 발급 버튼(POST /v1/center/checkin-qr/rotate)이
// crypto/rand로 만들어 넣고, 체크인 대조는 그 저장값을 읽는다.
//
// 환경변수를 남겨 폴백으로 쓰지 않은 이유(P49 결정): 폴백이 있으면 **재발급이 이전 토큰을
// 무효로 만들지 못한다** — 유출된 env 토큰이 영원히 통과하는데, 어디에서도 보이지 않아
// 대표는 자기가 되돌렸다고 믿는다. 여기 있던 기동 검증(운영에서 기본값이면 거부)도 함께
// 지웠다: 그 검증은 "미설정이 저장소의 공개 기본값으로 승격되는" fail-open을 막던 것인데,
// 읽는 코드가 사라져 막을 fail-open 자체가 없어졌다. 아무도 읽지 않는 값 때문에 기동을
// 거부하면 그 자체가 새로운 거짓말이 된다.

// Config — 서버 실행 설정.
type Config struct {
	Port            string   // HTTP 포트(Cloud Run은 자동 주입)
	UseFirestore    bool     // false면 인메모리 스토어
	GCPProject      string   // Firestore projectID
	FirebaseProject string   // 설정 시 Firebase ID 토큰 검증 활성화. 비우면 dev 헤더 인증(X-Dev-Role/X-Dev-Uid)
	DefaultCenterID string   // v1 단일 센터 전제(라이즈 컨디셔닝). 센터 생성 API가 없어 이 값으로 부트스트랩(README 갭)
	CORSOrigins     []string // 어드민 오리진(콤마 구분)
	// StorageBucket — Cloud Storage 버킷(예: rize-218c1.firebasestorage.app). 서버가 Admin
	// SDK로 이 버킷을 만지는 경로가 **두 개**이고, 미설정 시 동작이 서로 반대다:
	//
	//	파기(v2.11 회원탈퇴)   : no-op + 기동 경고. 체형사진 업로드는 클라이언트 SDK가 하므로
	//	                        이 값이 없어도 서비스 자체는 돈다(api.Authenticator.MediaPurger).
	//	업로드(v2.25 트레이너 사진): **503으로 거부**. 규칙이 클라이언트 쓰기를 막아 둔 경로라
	//	                        서버만이 쓸 수 있고, no-op이면 "저장했어요"가 거짓말이 된다
	//	                        (api.Authenticator.MediaUploader).
	//
	// 요약: 프로필 사진 업로드를 쓰려면 이 값이 **필수**다.
	StorageBucket string
	DevSeed       bool // true면 인메모리 스토어에 데모 데이터 시딩(v1.4 — 어드민·앱 데모/영업용. Firestore 모드에선 무시)
}

// Load — 환경변수에서 설정을 읽고 합리적 기본값을 채운다.
func Load() Config {
	return Config{
		Port:            env("PORT", "8080"),
		UseFirestore:    env("USE_FIRESTORE", "false") == "true",
		GCPProject:      env("GCP_PROJECT", ""),
		FirebaseProject: env("FIREBASE_PROJECT", ""),
		DefaultCenterID: env("DEFAULT_CENTER_ID", "rise"),
		CORSOrigins:     splitCSV(env("CORS_ORIGINS", "http://localhost:5173,http://localhost:5174")), // 5174=어드민 vite dev 포트
		StorageBucket:   env("STORAGE_BUCKET", ""),
		DevSeed:         env("DEV_SEED", "false") == "true",
	}
}

// Validate — 기동 전 위험한 조합을 거른다(fail-closed). 설정이 어긋나면 경고가 아니라 거부다.
//
// 막는 조합: USE_FIRESTORE=true + FIREBASE_PROJECT 미설정. 예전엔 경고만 찍고 떴는데, 그러면
// **실 DB에 붙은 채 dev 헤더 인증(X-Dev-Role/X-Dev-Uid)으로 서비스한다** — 헤더 한 줄이면
// 누구나 대표가 되어 전 회원의 개인정보·결제·계약을 읽고 지운다. 배포 한 번 어긋난 것이 곧
// 유출이라 로그 경고로는 부족하다.
//
// 로컬 인메모리 개발(USE_FIRESTORE 미설정)은 그대로 통과한다 — dev 헤더 인증은 그 모드의
// 정상 동작이고 실 데이터가 없다. USE_FIRESTORE와 GCP_PROJECT의 짝은 스토어를 만드는
// cmd/server의 buildStore가 같은 방식으로 막는다.
func (c Config) Validate() error {
	if c.UseFirestore && c.FirebaseProject == "" {
		return errors.New("USE_FIRESTORE=true 인데 FIREBASE_PROJECT 미설정 — 실 DB에 붙은 채 dev 헤더 인증으로 뜨면 X-Dev-Role 헤더만으로 누구나 대표가 됩니다. " +
			"FIREBASE_PROJECT를 설정하거나, 로컬 개발이면 USE_FIRESTORE를 끄세요")
	}
	// 종전엔 체크인 토큰의 기본값도 여기서 막았다(v2.23에서 삭제 — 파일 상단 주석 참고).
	// 그 검사는 "환경변수 미설정 → 저장소의 공개 기본값으로 승격"이라는 fail-open을 겨냥한
	// 것이었고, 토큰이 DB로 옮겨가면서 승격될 기본값 자체가 사라졌다. 미발급 센터는 조용히
	// 열리는 대신 self_qr 체크인을 **거부**한다(api.Service.Checkin) — fail-closed가 기동
	// 검증이 아니라 요청 경로로 내려갔다.
	return nil
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func splitCSV(s string) []string {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	return parts
}
