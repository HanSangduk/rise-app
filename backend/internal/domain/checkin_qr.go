package domain

// 데스크 체크인 QR 토큰(P49, 계약 v2.23) — 데스크에 인쇄해 붙이는 QR에 인코딩되는 센터 비밀.
//
// **환경변수(CHECKIN_QR_TOKEN)를 대체한다.** 종전엔 이 값이 Cloud Run 설정에만 있어서, 대표는
// 자기가 알 수 없는 문자열을 어드민에 손으로 옮겨 적어야 QR을 인쇄할 수 있었다(어드민이
// `sha256sum`으로 대조하라고 안내하던 자리). 사람이 아는 비밀은 사람이 흘리고, 손으로 옮기는
// 값은 손으로 틀린다 — 서버가 만들어 서버가 보관하고, 대표는 "발급" 버튼만 누른다.
//
// 저장은 centers/{id} 문서의 `checkin_qr` 맵이다(center·business·facility와 같은 네스팅 규약
// + 머지 쓰기 — P27 SavePolicy 교훈: 통 Set은 같은 문서의 동거 절을 지운다).

import (
	"crypto/rand"
	"encoding/base64"
	"strings"
	"time"
)

// CheckinQRTokenLen — 발급 토큰의 문자 수. 24바이트를 패딩 없는 URL-safe base64로 적으면
// 정확히 32자다(24 × 4 / 3). 192비트 엔트로피 — 온라인 추측이 성립하지 않는다.
//
// 길이를 32로 고른 이유는 QR 쪽 제약이다: 문자셋에 소문자·`-`·`_`가 있어 QR 영숫자 모드를
// 못 쓰고 바이트 모드로 떨어지는데, 32바이트는 오류정정 레벨 Q에서 버전 3(29모듈)에 정확히
// 들어간다. 더 길게 잡으면 버전이 올라가 같은 인쇄 크기에서 모듈이 잘아지고, 데스크 조명·
// 코팅 반사에서 스캔 실패가 늘어난다.
const CheckinQRTokenLen = 32

// checkinQRTokenBytes — 위 32자를 만드는 원본 바이트 수.
const checkinQRTokenBytes = 24

// CheckinQR — 센터의 데스크 체크인 QR 토큰 + 발급 시각(P49).
//
// **Business/Facility와 달리 사용자 입력이 없다.** 검증(Validate)이 없는 이유가 그것이다 —
// 값을 만드는 경로가 NewCheckinQRToken 하나뿐이라 "잘못된 입력"이라는 상태가 존재하지 않는다.
// 대신 Normalize를 읽기·쓰기 양쪽에 태운다: 손으로 고친 Firestore 문서에 딸려 들어간 공백
// 하나가 바이트 비교를 조용히 깨뜨리는 것만은 막아야 한다(응답으로 나가는 값과 비교에 쓰는
// 값이 같은 정규화를 지나야 인쇄물과 서버가 어긋나지 않는다).
type CheckinQR struct {
	// Token — 인쇄 QR에 그대로 들어가는 원문. 앱은 스캔한 문자열을 가공 없이 보내고 서버가
	// 바이트로 비교한다(api.Service.Checkin). **회원·트레이너에게 나가는 응답에는 절대
	// 실리지 않는다** — 이 값을 아는 회원은 집에서 출석을 찍을 수 있다.
	Token string `json:"token"`
	// IssuedAt — 마지막 발급 시각(UTC). 미발급이면 nil. 어드민이 "언제 인쇄한 QR인지"를
	// 이 값으로 말한다 — 재발급하면 이전 인쇄물이 즉시 무효가 되므로, 데스크에 붙은 종이가
	// 최신인지 판단할 유일한 근거다.
	IssuedAt *time.Time `json:"issued_at"`
}

// Issued — 발급된 적이 있는가. 빈 토큰은 결측이 아니라 **상태**다(Facility의 unknown과 같은
// 자리): 미발급 센터의 self_qr 체크인은 거부되고, 어드민은 "발급" 버튼만 보여준다.
func (q CheckinQR) Issued() bool { return q.Token != "" }

// Normalize — 저장·응답 직전 표기 정리(Facility.Normalize와 같은 규약).
func (q *CheckinQR) Normalize() {
	q.Token = strings.TrimSpace(q.Token)
	if q.Token == "" {
		// 토큰이 없는데 발급 시각만 남은 상태는 어드민 화면에서 "발급됨"과 "미발급"이 동시에
		// 참인 모양이 된다. 둘을 한 사실의 두 얼굴로 묶어 둔다.
		q.IssuedAt = nil
	}
}

// NewCheckinQRToken — crypto/rand 기반 32자 URL-safe base64 토큰.
//
// RawURLEncoding(패딩 `=` 없음)을 쓰는 이유: `=`는 URL·QR 페이로드 어디서든 이스케이프 논쟁을
// 부르는 문자이고, 여기서는 길이가 고정이라 패딩이 정보를 더하지도 않는다. 결과 문자셋은
// `A-Za-z0-9-_` — 전부 ASCII라 앱이 스캔한 문자열이 인코딩 왕복에서 변형될 여지가 없다.
//
// 에러를 삼키지 않고 올린다: crypto/rand가 실패한 상황에서 약한 대체 소스로 내려가면
// "발급됐다"는 응답 뒤에 추측 가능한 토큰이 인쇄된다 — 실패는 실패로 보여야 한다.
func NewCheckinQRToken() (string, error) {
	buf := make([]byte, checkinQRTokenBytes)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}
