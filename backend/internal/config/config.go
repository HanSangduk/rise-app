// Package config는 환경변수 기반 설정을 로드한다(12-factor, wodshot 패턴 재사용).
package config

import (
	"errors"
	"os"
	"strings"
)

// defaultCheckinQRToken — 로컬 개발용 체크인 토큰. 저장소에 적혀 있으니 공개된 값이고,
// 운영에서 이 값이 쓰이면 아무나 남의 출석을 찍을 수 있다. Validate가 운영 모드에서 거부한다.
const defaultCheckinQRToken = "rise-desk-checkin"

// Config — 서버 실행 설정.
type Config struct {
	Port            string   // HTTP 포트(Cloud Run은 자동 주입)
	UseFirestore    bool     // false면 인메모리 스토어
	GCPProject      string   // Firestore projectID
	FirebaseProject string   // 설정 시 Firebase ID 토큰 검증 활성화. 비우면 dev 헤더 인증(X-Dev-Role/X-Dev-Uid)
	DefaultCenterID string   // v1 단일 센터 전제(라이즈 컨디셔닝). 센터 생성 API가 없어 이 값으로 부트스트랩(README 갭)
	CORSOrigins     []string // 어드민 오리진(콤마 구분)
	CheckinQRToken  string   // 데스크 인쇄 QR에 인코딩되는 고정 토큰(P44 self_qr 검증)
	// StorageBucket — 체형사진이 올라가는 Cloud Storage 버킷(예: rize-218c1.firebasestorage.app).
	// 회원탈퇴(v2.11)가 Admin SDK로 원본 파일을 파기하는 데만 쓴다 — 업로드는 클라이언트가
	// 자기 SDK 설정으로 하므로 이 값이 없어도 서비스는 돈다. 미설정이면 파일 파기가 no-op이
	// 되고 기동 로그에 경고가 남는다(api.Authenticator.MediaPurger).
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
		CheckinQRToken:  env("CHECKIN_QR_TOKEN", defaultCheckinQRToken),
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
	// 같은 이유로 체크인 토큰의 기본값도 운영에서 막는다. env()는 빈 문자열을 미설정으로 보고
	// 기본값으로 승격시키므로, 배포 설정에서 CHECKIN_QR_TOKEN이 실수로 비면 조용히 공개 토큰으로
	// 떨어진다 — 그 상태로 뜨면 데스크 QR 없이 아무나 자가 체크인이 된다.
	if c.UseFirestore && c.CheckinQRToken == defaultCheckinQRToken {
		return errors.New("CHECKIN_QR_TOKEN이 저장소에 적힌 기본값 그대로입니다 — 공개된 값이라 아무나 남의 출석을 찍을 수 있습니다. " +
			"운영에서는 별도 토큰을 설정하세요")
	}
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
