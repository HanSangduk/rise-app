// Package domain은 라이즈 컨디셔닝(PT데스크)의 순수 도메인 로직이다.
//
// 설계 원칙(클린 아키텍처): 이 패키지는 프레임워크를 모른다. chi·firestore·firebase 같은
// 바깥 세계는 여기에 import 되지 않는다(표준 라이브러리만) — 회원권 원장·환불계산·예약 규칙·
// 홈워크 배정 같은 핵심 로직을 SDK 없이 즉시 테스트할 수 있다(각 *_test.go의 골든값 참고,
// 근거: PT데스크 설계 03 §11 구현순서, 설계 00 §4 도메인모델).
package domain

import (
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"
	"unicode/utf8"
)

// Member — 회원(API계약 v1). json 태그는 계약 문서의 필드명을 그대로 따른다.
type Member struct {
	ID          string       `json:"id"`
	Name        string       `json:"name"`
	Phone       string       `json:"phone"`
	Channel     string       `json:"channel"` // 진입경로: 지인소개|인스타|워크인|재등록|기타(설정값, P40 R7)
	TrainerID   string       `json:"trainer_id"`
	Flags       []MemberFlag `json:"flags"`
	Consent     Consent      `json:"consent"`
	AppLinked   bool         `json:"app_linked"`
	Status      string       `json:"status"` // active|dormant
	LastVisitAt *time.Time   `json:"last_visit_at"`

	// BodyPoses — 회원별 체형 촬영 포즈 시퀀스(v2.10). **nil = 센터 기본(DefaultBodyPoses) 사용**.
	//
	// nil이 의미를 가지므로 Flags식 "nil→[] 정규화"를 이 필드엔 적용하지 않는다. 저장 상태는
	// nil-또는-검증된-커스텀 둘뿐이고([]는 서비스가 nil로 정규화 = "기본으로 초기화"),
	// 응답에서만 EffectiveBodyPoses로 구체화한다 — **저장 객체에 구체화하면 필드 없는 머지
	// PUT이 기본값을 커스텀으로 굳혀버린다**(이후 센터 기본을 바꿔도 그 회원만 안 따라온다).
	// Firestore json 라운드트립상 구 문서(필드 부재)는 자동으로 nil → 기본이라 마이그레이션 불요.
	BodyPoses []BodyPose `json:"body_poses"`

	// WithdrawnAt — 회원탈퇴(파기) 시각(v2.11). Status가 withdrawn일 때만 값이 있고 서버가
	// 기록한다(클라이언트 값 무시 — Staff.LeftAt과 동형). 전자상거래법 보존기간(계약·결제
	// 5년)의 기산점이라 재시도가 이 값을 미래로 밀지 않는다(Anonymized 주석 참고).
	WithdrawnAt *time.Time `json:"withdrawn_at,omitempty"`
}

// BodyPose — 체형 촬영 시퀀스의 한 단계(v2.10). key는 Storage 파일명
// members/{id}/body/{yyyyMMdd}-{pose}-{direction}-{epochMs}.jpg 의 {pose} 조각으로 그대로
// 쓰이므로 슬러그 규칙(bodyPoseKeyRe)을 지켜야 한다. label은 앱 포즈 칩·어드민에 뜨는 표시명.
type BodyPose struct {
	Key   string `json:"key"`
	Label string `json:"label"`
}

// DefaultBodyPoses — 센터 기본 포즈 시퀀스 4종(설계03 §4). Member.BodyPoses가 nil이면 이걸 쓴다.
// 수정 금지(패키지 전역) — 응답에 실을 땐 EffectiveBodyPoses가 복사본을 돌려준다.
var DefaultBodyPoses = []BodyPose{
	{Key: PoseStand, Label: "차렷"},
	{Key: PoseTPose, Label: "T자"},
	{Key: PoseFold, Label: "전굴"},
	{Key: PoseOHSquat, Label: "OH스쿼트"},
}

// 커스텀 포즈 시퀀스 상한(v2.10). 개수 8: 연속 촬영 UX·앱 포즈 칩 한 행의 한계.
// label 12자: 칩 렌더 폭.
const (
	bodyPoseLabelMaxRunes = 12
	bodyPosesMax          = 8
)

// bodyPoseKeyRe — 포즈 key 슬러그. **하이픈 금지가 핵심**: Storage 파일명
// {yyyyMMdd}-{pose}-{direction}-{epochMs}.jpg 가 `-` 구분자라 key에 `-`가 들어가면 파일명
// 파싱(고스트의 epochMs 타이브레이커)이 모호해진다. `/`·대문자·유니코드 배제는 Storage 경로
// 세그먼트 안전 + URL 인코딩·대소문자 충돌 회피. 레거시 4종(stand/tpose/fold/ohsquat)도 통과한다.
var bodyPoseKeyRe = regexp.MustCompile(`^[a-z0-9_]{1,24}$`)

// ValidPoseKey — BodyPose.Key와 BodyPhoto.Pose(CreateBodyPhoto 요청)가 공유하는 슬러그 검사.
func ValidPoseKey(key string) bool { return bodyPoseKeyRe.MatchString(key) }

// ErrInvalidBodyPoses — 포즈 시퀀스 검증 위반(400 매핑).
var ErrInvalidBodyPoses = errors.New("domain: invalid body poses")

func errBodyPoses(msg string) error { return errors.Join(ErrInvalidBodyPoses, errors.New(msg)) }

// NormalizeBodyPoses — 저장 전 정규화: label 앞뒤 공백 제거 + 빈 목록(nil/[])은 nil로
// ("기본으로 초기화" 시맨틱 — []가 저장되면 EffectiveBodyPoses의 nil 판정이 어긋난다).
// 항상 새 슬라이스를 돌려준다(입력과 백킹 배열 비공유).
func NormalizeBodyPoses(poses []BodyPose) []BodyPose {
	if len(poses) == 0 {
		return nil
	}
	out := make([]BodyPose, len(poses))
	for i, p := range poses {
		out[i] = BodyPose{Key: p.Key, Label: strings.TrimSpace(p.Label)}
	}
	return out
}

// ValidateBodyPoses — 커스텀 시퀀스 검증(v2.10): 개수 1~8 · key 슬러그(^[a-z0-9_]{1,24}$) ·
// key 중복 금지 · label(공백 제거 후) 1~12자. 문구는 화면에 그대로 뜬다(원인 + 다음 행동).
func ValidateBodyPoses(poses []BodyPose) error {
	if len(poses) == 0 {
		return errBodyPoses("포즈를 1개 이상 넣어주세요 — 기본 시퀀스로 되돌리려면 body_poses를 null 또는 []로 보내주세요")
	}
	if len(poses) > bodyPosesMax {
		return errBodyPoses(fmt.Sprintf("포즈는 최대 %d개까지 설정할 수 있어요(현재 %d개)", bodyPosesMax, len(poses)))
	}
	seen := make(map[string]bool, len(poses))
	for _, p := range poses {
		if !ValidPoseKey(p.Key) {
			return errBodyPoses(fmt.Sprintf("포즈 key %q가 올바르지 않아요 — 영소문자·숫자·언더스코어(_)로 1~24자예요(하이픈은 사진 파일명의 구분자라 쓸 수 없어요)", p.Key))
		}
		if seen[p.Key] {
			return errBodyPoses(fmt.Sprintf("포즈 key %q가 중복이에요 — key는 시퀀스 안에서 고유해야 해요", p.Key))
		}
		seen[p.Key] = true
		label := strings.TrimSpace(p.Label)
		if label == "" {
			return errBodyPoses(fmt.Sprintf("포즈 %q의 label(표시명)을 입력해주세요", p.Key))
		}
		if utf8.RuneCountInString(label) > bodyPoseLabelMaxRunes {
			return errBodyPoses(fmt.Sprintf("포즈 label은 %d자 이하로 입력해주세요(현재 %q)", bodyPoseLabelMaxRunes, label))
		}
	}
	return nil
}

// EffectiveBodyPoses — 실효 포즈 시퀀스: 커스텀이 없으면(nil — 방어적으로 []도) 센터 기본.
// 기본을 돌려줄 땐 복사본이다 — 호출자가 응답 구체화용으로 대입해도 DefaultBodyPoses가
// 오염되지 않는다. **응답 사본에만 쓸 것** — 저장 경로에 쓰면 기본값이 커스텀으로 굳는다.
func (m Member) EffectiveBodyPoses() []BodyPose {
	if len(m.BodyPoses) == 0 {
		return slices.Clone(DefaultBodyPoses)
	}
	return m.BodyPoses
}

// Member.Status 값. 필드 부재/""는 로드 시 active로 승격한다(v2.0 Staff.status와 동형 —
// 기존 Firestore 문서 마이그레이션 불필요).
const (
	MemberStatusActive  = "active"
	MemberStatusDormant = "dormant"
	// MemberStatusWithdrawn — 회원탈퇴(v2.11). 문서 자체는 남는다: 5년간 보존해야 하는
	// 계약·결제·원장이 member_id로 이 문서를 조인하는데, 지우면 **보존하기로 한 바로 그
	// 기록들이 누구 것인지도 모르는 채 화면에서 깨진다**(v2.0이 GET /v1/staff에서 inactive를
	// 계속 반환하기로 한 것과 같은 근거 — 이름 해석을 잃으면 참조 지점이 원시 ID로 붕괴한다).
	MemberStatusWithdrawn = "withdrawn"
)

// WithdrawnMemberName — 탈퇴 후 회원 문서에 남는 고정 라벨. **식별자가 아니다** — 어드민의
// 미수금 표·계약 목록이 member_id로 조인할 때 이름 자리가 원시 ID로 깨지지 않게 하는 것이
// 유일한 목적이라, 탈퇴자 전원이 같은 문자열을 공유하는 것이 정상이자 의도다.
const WithdrawnMemberName = "탈퇴한 회원"

// IsWithdrawn — 탈퇴 처리된 회원인지.
func (m Member) IsWithdrawn() bool { return m.Status == MemberStatusWithdrawn }

// Normalize — 저장 전 표기 정리(StaffCreate·Center와 같은 규약).
//
// **번호의 표기는 건드리지 않는다.** 처음엔 NormalizePhone 결과(숫자만)로 저장하려 했는데,
// 두 스토어의 FindMemberByPhone과 가입 매칭이 **비교 시점에 양쪽을 정규화**하므로(memory.go·
// firestore.go의 normalizePhone(mem.Phone) != target) 저장 형식은 매칭에 아무 영향이 없다.
// 반면 바꾸면 기존 문서("010-1234-5678")와 새 문서("01012345678")가 섞이고, 데스크가 입력한
// 표기를 서버가 임의로 고쳐 되돌려 주는 것이 된다 — 얻는 것 없이 잃는 변경이다.
// 자릿수 검증만 정규화 값으로 한다(Validate).
func (m *Member) Normalize() {
	m.Name = strings.TrimSpace(m.Name)
	m.Phone = strings.TrimSpace(m.Phone)
	m.Channel = strings.TrimSpace(m.Channel)
	m.TrainerID = strings.TrimSpace(m.TrainerID)
	if m.Status == "" {
		m.Status = MemberStatusActive
	}
}

// Validate — 회원 레코드가 **앱과 만날 수 있는 상태**인가.
//
// v2.36에서 신설했다. 종전엔 회원만 도메인 검증이 없어(Staff·Center·Business·Facility·Policy는
// 전부 갖고 있었다) 이름도 번호도 빈 회원이 200으로 저장됐다. v2.32부터 **번호가 센터를 정하므로**
// 번호가 비거나 자릿수가 틀리면 그 회원은 앱 매칭·확인이 영원히 실패한다 — 그런데 데스크에는
// 등록 성공만 보이고, 회원은 "미연결" 화면에 갇힌 채 아무도 원인을 못 짚는다. 그 사고를 등록
// 시점에 막는다.
//
// withdrawn을 허용 목록에 넣는 이유: 탈퇴 레코드는 Anonymized()가 이름·번호를 지운 상태로
// 저장되므로(보존의무 5년) 여기 규칙을 그대로 적용하면 **탈퇴 처리 자체가 실패한다**. 탈퇴는
// 이 검증을 지나는 경로가 아니지만, 나중에 지나게 되더라도 막히지 않도록 상태를 함께 본다.
func (m Member) Validate() error {
	if m.Status == MemberStatusWithdrawn {
		return nil // 파기된 레코드 — 이름·번호가 비어 있는 것이 정상이다
	}
	name := strings.TrimSpace(m.Name)
	if name == "" {
		return errors.New("회원 이름을 입력해주세요")
	}
	if utf8.RuneCountInString(name) > 40 {
		return errors.New("회원 이름이 너무 길어요(40자 이내)")
	}
	// 번호는 이미 Normalize를 지난 값이어야 한다(숫자만). 국내 이동전화·지역번호가 10~11자리다.
	digits := NormalizePhone(m.Phone)
	if digits == "" {
		return errors.New("휴대폰 번호를 입력해주세요 — 회원이 앱에서 연결될 때 쓰는 유일한 열쇠예요")
	}
	if len(digits) < 10 || len(digits) > 11 {
		return errors.New("휴대폰 번호 자릿수가 맞지 않아요(10~11자리) — 앱 연결에 쓰는 번호라 정확해야 해요")
	}
	switch m.Status {
	case MemberStatusActive, MemberStatusDormant:
	default:
		return errors.New("회원 상태가 올바르지 않아요(active 또는 dormant)")
	}
	return nil
}

// Anonymized — 탈퇴 시 **남길** 회원 문서를 만든다(순수 함수 — 원본은 건드리지 않는다).
//
// 파기·보존의 경계를 코드로 못박는 자리다. 두 법이 반대 방향으로 당긴다:
//
//	개인정보보호법 §21①  — 처리 목적이 끝나면 지체 없이 파기하라
//	전자상거래법 §6+시행령 §6① — 계약·청약철회 5년, 대금결제·재화공급 5년 보존하라
//
// 충돌은 아니다. §21① 단서가 "다른 법령에 따라 보존하여야 하는 경우"를 예외로 두고, §21③이
// 그때 **분리 저장·관리**를 요구한다. 우리가 그은 선: 사람을 가리키는 값은 여기서 전부
// 비우고(그러면 남는 원장·결제·계약은 member_id라는 가명만 붙은 거래 기록이 된다), 건강
// 기록(체형사진·인바디·수업기록)은 애초에 보존 대상이 아니므로 스토어가 실제로 지운다.
//
// 전자상거래법 §6②가 허용하는 "성명 보존"을 **일부러 쓰지 않는다.** 허용은 의무가 아니고,
// 보존의 목적("그 거래가 있었다")은 금액·회차·날짜·계약 상태로 이미 완전하다. 남길 이유가
// 없는 식별자를 남기면 그건 §21①이 말하는 불필요해진 개인정보다.
//
// **재시도 멱등**: 이미 탈퇴한 회원에 다시 걸어도 결과가 같고, WithdrawnAt은 최초 시각을
// 보존한다 — 파기 시점이 곧 보존기간 기산점이라 재시도가 그것을 미래로 밀면 안 된다.
func (m Member) Anonymized(at time.Time) Member {
	withdrawnAt := m.WithdrawnAt
	if withdrawnAt == nil {
		t := at
		withdrawnAt = &t
	}
	return Member{
		// 보존 — 원장·결제·계약이 조인하는 가명 키.
		ID: m.ID,
		// 파기 — 사람을 가리키는 값.
		Name:    WithdrawnMemberName,
		Phone:   "", // 남기면 FindMemberByPhone이 계속 매칭해 재가입이 탈퇴 레코드로 되돌아 붙는다
		Channel: "", // 진입경로: 보존 근거 없음
		// 담당 회수 — 탈퇴 회원이 코치의 퇴사 선행 조건①("담당 회원 없음")을 영구히 막으면 안 된다.
		// 과거 정산 귀속은 Pass.trainer_id가 따로 들고 있어 소급 파괴되지 않는다.
		TrainerID: "",
		Flags:     []MemberFlag{}, // 부상 메모 = 건강 관련 정보. 직렬화 계약상 nil이 아니라 []
		Consent:   Consent{},      // 전이 시각까지 비운다 — 탈퇴가 동의 철회의 종국이다
		AppLinked: false,
		Status:    MemberStatusWithdrawn,
		// LastVisitAt(방문 이력)·BodyPoses(촬영 시퀀스)는 제로값 그대로 둔다.
		// BodyPoses는 nil이 "센터 기본 사용"이라 저장 상태가 신규 회원과 같아진다(v2.10).
		WithdrawnAt: withdrawnAt,
	}
}

// MemberFlag — 회원 플래그(부상 등). type="injury"면 Home Work 자동 제외 대상(P39).
type MemberFlag struct {
	Type string `json:"type"`
	Note string `json:"note"`
}

// FlagInjury — 부상 플래그 타입 상수.
const FlagInjury = "injury"

// Consent — 동의 트랙(설계00 §4 불변식5, P8·P9). general=일반 이용약관, sensitive=인바디·체형사진 등 민감정보.
// "민감정보 법정 암호화 의무" 같은 문구는 코드/문서 어디에도 쓰지 않는다(P9, 팩트체크 오정보 방지).
type Consent struct {
	General   bool       `json:"general"`
	Sensitive bool       `json:"sensitive"`
	SignedAt  *time.Time `json:"signed_at"`
	RevokedAt *time.Time `json:"revoked_at"`
}

// HasInjuryFlag — 부상 플래그 보유 여부(Home Work 자동 제외 판정, P39).
func (m Member) HasInjuryFlag() bool {
	for _, f := range m.Flags {
		if f.Type == FlagInjury {
			return true
		}
	}
	return false
}

// SensitiveConsentValid — 인바디·체형사진을 신규 저장할 수 있는지(P8 불변식5).
// 동의가 없거나 철회(RevokedAt 설정)되면 즉시 잠긴다(설계03 §11 회원 문서 주석).
func (c Consent) SensitiveConsentValid() bool {
	return c.Sensitive && c.RevokedAt == nil
}
