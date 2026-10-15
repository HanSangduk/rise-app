package config

// 감사 회귀: 설정은 fail-open이면 안 된다. 실 DB에 붙은 채 dev 헤더 인증으로 뜨는 조합은
// 경고가 아니라 기동 거부여야 한다(X-Dev-Role 헤더 한 줄이면 누구나 대표가 된다).

import (
	"reflect"
	"strings"
	"testing"
)

func TestValidateRejectsFirestoreWithoutFirebaseAuth(t *testing.T) {
	// v2.36: InitialStaffPassword가 Validate의 두 번째 검사라 **모든 케이스가 이 값을 채워야**
	// 다른 조합을 홀로 검증할 수 있다. Load()는 항상 기본값을 채우므로 실서비스에서는 빈 값이
	// 나오지 않는다 — 여기서만 손으로 세운다.
	const pw = "123456"
	cases := []struct {
		name    string
		cfg     Config
		wantErr bool
	}{
		{
			name:    "실 DB + dev 헤더 인증 = 사고 조합",
			cfg:     Config{UseFirestore: true, GCPProject: "rise-prod", InitialStaffPassword: pw},
			wantErr: true,
		},
		{
			name:    "로컬 인메모리 개발 — 지금 그대로 뜬다",
			cfg:     Config{InitialStaffPassword: pw},
			wantErr: false,
		},
		{
			name:    "인메모리 + Firebase 인증(토큰 디버깅) — 실 데이터가 없으니 막을 이유 없다",
			cfg:     Config{FirebaseProject: "rise-prod", InitialStaffPassword: pw},
			wantErr: false,
		},
		{
			name:    "정상 프로덕션",
			cfg:     Config{UseFirestore: true, GCPProject: "rise-prod", FirebaseProject: "rise-prod", InitialStaffPassword: pw},
			wantErr: false,
		},
	}
	for _, c := range cases {
		err := c.cfg.Validate()
		if (err != nil) != c.wantErr {
			t.Errorf("%s: Validate() = %v, wantErr=%v", c.name, err, c.wantErr)
		}
		// 에러 메시지는 무엇을 고쳐야 하는지 그대로 알려줘야 한다(배포 중 새벽에 읽는 문장).
		if c.wantErr && err != nil && !strings.Contains(err.Error(), "FIREBASE_PROJECT") {
			t.Errorf("%s: 에러에 고칠 환경변수 이름이 없다: %v", c.name, err)
		}
	}
}

// P49(v2.23): CHECKIN_QR_TOKEN은 **읽히지 않는다**. 체크인 토큰이 센터 문서로 옮겨간 뒤에도
// 이 환경변수가 어딘가에서 살아 있으면 두 개의 진실이 생기고, 그 순간 재발급이 이전 토큰을
// 무효로 만들지 못한다(유출된 env 토큰이 영원히 통과하는데 화면에는 안 보인다).
//
// **환경변수가 설정돼 있어도 Config가 아무 영향을 받지 않는다**는 것이 여기서 고정하는 사실이다.
// 종전에는 이 값이 미설정이면 저장소의 공개 기본값으로 승격돼 기동이 거부됐다 — 그 거부가
// 사라진 것도 함께 고정한다(아무도 안 읽는 값 때문에 기동을 막으면 그게 새 거짓말이다).
func TestCheckinQRTokenEnvIsNoLongerRead(t *testing.T) {
	t.Setenv("USE_FIRESTORE", "true")
	t.Setenv("GCP_PROJECT", "rise-prod")
	t.Setenv("FIREBASE_PROJECT", "rise-prod")

	t.Setenv("CHECKIN_QR_TOKEN", "")
	bare := Load()
	if err := bare.Validate(); err != nil {
		t.Fatalf("CHECKIN_QR_TOKEN 미설정인데 기동 거부: %v — 그 검증은 v2.23에서 사라졌다", err)
	}

	t.Setenv("CHECKIN_QR_TOKEN", "누군가-남겨둔-옛-운영-토큰")
	withEnv := Load()
	if !reflect.DeepEqual(withEnv, bare) {
		t.Errorf("CHECKIN_QR_TOKEN이 Config를 바꿨다: %+v vs %+v — 폴백이 되살아나면 재발급이 옛 토큰을 못 죽인다", withEnv, bare)
	}
	if err := withEnv.Validate(); err != nil {
		t.Errorf("남아 있는 CHECKIN_QR_TOKEN이 기동을 막았다: %v — 레거시 배포 설정은 무해해야 한다", err)
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
	if err := Load().Validate(); err != nil {
		t.Fatalf("정상 프로덕션 설정이 거부됨: %v", err)
	}
}

// v2.36 — Firebase는 6자 미만 비밀번호로 계정을 만들지 못한다(Admin SDK가 요청 전에 거부:
// "password must be a string at least 6 characters long"). 그 값으로 뜨면 **직원·센터 대표
// 초대가 전부 실패**하는데, 실패는 첫 초대 요청까지 드러나지 않는다 — 그 시점엔 센터 문서와
// 정책이 이미 저장돼 "센터는 생겼는데 대표가 없는" 반쪽 상태가 남는다. 그래서 기동에서 막는다.
func TestValidateRejectsShortInitialStaffPassword(t *testing.T) {
	for _, pw := range []string{"", "1234", "12345"} {
		cfg := Config{InitialStaffPassword: pw}
		err := cfg.Validate()
		if err == nil {
			t.Errorf("InitialStaffPassword=%q: Validate()=nil, want 기동 거부", pw)
			continue
		}
		if !strings.Contains(err.Error(), "INITIAL_STAFF_PASSWORD") {
			t.Errorf("InitialStaffPassword=%q: 에러에 고칠 환경변수 이름이 없다: %v", pw, err)
		}
	}
	if err := (Config{InitialStaffPassword: "123456"}).Validate(); err != nil {
		t.Errorf("6자는 통과해야 한다(Firebase 최저 길이): %v", err)
	}
}

// Load의 기본값이 Firebase 최저 길이를 만족해야 한다 — 환경변수를 안 주고 띄우는 로컬·CI가
// 기동 거부에 걸리면 안 된다.
func TestLoadDefaultInitialStaffPasswordPassesValidate(t *testing.T) {
	t.Setenv("INITIAL_STAFF_PASSWORD", "")
	if err := Load().Validate(); err != nil {
		t.Fatalf("기본값으로 기동이 거부됐다: %v", err)
	}
}
