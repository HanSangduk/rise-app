package config

// 감사 회귀: 설정은 fail-open이면 안 된다. 실 DB에 붙은 채 dev 헤더 인증으로 뜨는 조합은
// 경고가 아니라 기동 거부여야 한다(X-Dev-Role 헤더 한 줄이면 누구나 대표가 된다).

import (
	"strings"
	"testing"
)

func TestValidateRejectsFirestoreWithoutFirebaseAuth(t *testing.T) {
	cases := []struct {
		name    string
		cfg     Config
		wantErr bool
	}{
		{
			name:    "실 DB + dev 헤더 인증 = 사고 조합",
			cfg:     Config{UseFirestore: true, GCPProject: "rise-prod"},
			wantErr: true,
		},
		{
			name:    "로컬 인메모리 개발 — 지금 그대로 뜬다",
			cfg:     Config{},
			wantErr: false,
		},
		{
			name:    "인메모리 + Firebase 인증(토큰 디버깅) — 실 데이터가 없으니 막을 이유 없다",
			cfg:     Config{FirebaseProject: "rise-prod"},
			wantErr: false,
		},
		{
			name:    "정상 프로덕션",
			cfg:     Config{UseFirestore: true, GCPProject: "rise-prod", FirebaseProject: "rise-prod", CheckinQRToken: "운영-전용-토큰"},
			wantErr: false,
		},
		{
			// env()가 빈 문자열을 미설정으로 보고 기본값으로 승격시키므로, 배포 설정에서
			// CHECKIN_QR_TOKEN이 실수로 비면 저장소에 적힌 공개 토큰으로 조용히 떨어진다.
			// 그 상태로 뜨면 데스크 QR 없이 아무나 남의 출석을 찍는다.
			name:    "실 DB + 저장소에 적힌 공개 체크인 토큰 = 자가 체크인 무제한",
			cfg:     Config{UseFirestore: true, GCPProject: "rise-prod", FirebaseProject: "rise-prod", CheckinQRToken: defaultCheckinQRToken},
			wantErr: true,
		},
		{
			name:    "로컬 인메모리에서는 기본 토큰이 정상 — 실 데이터가 없다",
			cfg:     Config{CheckinQRToken: defaultCheckinQRToken},
			wantErr: false,
		},
	}
	for _, c := range cases {
		err := c.cfg.Validate()
		if (err != nil) != c.wantErr {
			t.Errorf("%s: Validate() = %v, wantErr=%v", c.name, err, c.wantErr)
		}
		// 에러 메시지는 무엇을 고쳐야 하는지 그대로 알려줘야 한다(배포 중 새벽에 읽는 문장).
		if c.wantErr && err != nil &&
			!strings.Contains(err.Error(), "FIREBASE_PROJECT") &&
			!strings.Contains(err.Error(), "CHECKIN_QR_TOKEN") {
			t.Errorf("%s: 에러에 고칠 환경변수 이름이 없다: %v", c.name, err)
		}
	}
}

// Load()가 읽은 값으로도 같은 판정이 나오는지 — 환경변수 → Config 매핑까지 함께 고정한다.
func TestLoadThenValidate(t *testing.T) {
	t.Setenv("USE_FIRESTORE", "true")
	t.Setenv("GCP_PROJECT", "rise-prod")
	t.Setenv("FIREBASE_PROJECT", "")
	if err := Load().Validate(); err == nil {
		t.Fatal("USE_FIRESTORE=true + FIREBASE_PROJECT 미설정인데 기동 허용 — fail-open")
	}

	t.Setenv("FIREBASE_PROJECT", "rise-prod")
	if err := Load().Validate(); err == nil {
		t.Fatal("CHECKIN_QR_TOKEN 미설정 → 저장소의 공개 기본값으로 승격됐는데 기동 허용 — fail-open")
	}

	t.Setenv("CHECKIN_QR_TOKEN", "운영-전용-토큰")
	if err := Load().Validate(); err != nil {
		t.Fatalf("정상 프로덕션 설정이 거부됨: %v", err)
	}
}
