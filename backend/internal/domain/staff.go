package domain

import (
	"errors"
	"fmt"
	"net/mail"
	"strings"
	"time"
)

// Staff — 직원(대표|트레이너, API계약 v1 + v1.6 profile + v2.0 생애주기).
type Staff struct {
	UID     string   `json:"uid"`
	Role    string   `json:"role"` // owner|trainer
	Name    string   `json:"name"`
	Color   string   `json:"color"`
	Payout  Payout   `json:"payout"`
	Offdays []string `json:"offdays"` // "YYYY-MM-DD" 목록
	// Profile — 트레이너 소개(v1.6, P05). 전 필드가 회원 열람 전제의 공개 데이터 —
	// payout 마스킹(P13)과 달리 마스킹하지 않는다. 항상 객체(null 금지)·배열은 항상 [].
	Profile StaffProfile `json:"profile"`
	// Status — active|inactive(v2.0). 하드 삭제를 하지 않는 이유는 계약 v2.0 §"하드 삭제를
	// 하지 않는 이유" 참고(원장 append-only·정산 비교표 소급 파괴·평문 uid 196개 참조·법정 보존).
	// **필드 부재("")는 로드 시 active로 승격**한다(Normalize) — 기존 Firestore 문서를
	// 마이그레이션하지 않고도 동작해야 한다(v1.3 Policy.NormalizeHoldLimits와 동형 규약).
	Status string `json:"status"`
	// LeftAt — 퇴사 시각(inactive일 때만). 서버가 기록한다 — 일반 정정(PUT /v1/staff/{uid})
	// 바디로는 못 바꾸고 deactivate 전용 동사만 쓴다.
	LeftAt *time.Time `json:"left_at,omitempty"`
}

// Staff.Status 값(v2.0).
const (
	StaffStatusActive   = "active"
	StaffStatusInactive = "inactive"
)

// IsActive — 재직 중인지. **빈 값을 active로 읽는다** — Normalize를 거치지 않은 경로
// (수동 시딩 문서·테스트가 직접 심은 레코드)에서도 기존 스태프가 조용히 퇴사자로 뒤집히지
// 않게 하기 위해서다. "inactive"만이 명시적 퇴사다.
func (s Staff) IsActive() bool { return s.Status != StaffStatusInactive }

// Normalize — 로드 시 하이진(v2.0). status 부재를 active로 승격하고, 직렬화 계약(배열 null
// 금지)을 함께 만족시킨다. v1.3 Policy 상한 승격과 같은 자리 — 스토어 읽기 경로가 호출한다.
func (s *Staff) Normalize() {
	if s.Status == "" {
		s.Status = StaffStatusActive
	}
	if s.Status == StaffStatusActive {
		// active인데 left_at이 남아 있으면 "복직했는데 퇴사일이 찍혀 있는" 모순이다 —
		// reactivate가 지우지만, 수동 편집분까지 로드 시점에 정리한다.
		s.LeftAt = nil
	}
	if s.Offdays == nil {
		s.Offdays = []string{}
	}
	s.Profile.Normalize()
}

// StaffProfile — 트레이너 프로필(v1.6). 필드 구성은 시장 표준(운동닥터·다짐·포인티 조사,
// work_log/P05)에서 도출: 사진·직함·경력 연차·자격증·수상/선수 경력·전문분야·소개문.
// 리뷰/평점·가격·SNS는 의도적으로 제외(마켓플레이스 맥락 — 단일 센터 CRM엔 부적합).
type StaffProfile struct {
	PhotoURL       string   `json:"photo_url"`    // 외부 이미지 URL(http/https) — 업로드는 Storage 트랙 후속. 빈 값=이니셜 아바타
	Title          string   `json:"title"`        // 직함(예: "헤드 트레이너")
	CareerYears    int      `json:"career_years"` // 경력 연차(0=미표기)
	Specialties    []string `json:"specialties"`  // 전문분야 태그
	Certifications []string `json:"certifications"`
	Awards         []string `json:"awards"` // 수상·선수 경력
	Bio            string   `json:"bio"`    // 소개문
}

// ErrInvalidProfile — 프로필 값 범위 위반(400 매핑).
var ErrInvalidProfile = errors.New("domain: invalid staff profile")

func errProfile(msg string) error { return errors.Join(ErrInvalidProfile, errors.New(msg)) }

// Validate — 프로필 범위 검증(v1.6). photo_url은 http/https만 — javascript: 등 스킴 주입 차단.
func (p StaffProfile) Validate() error {
	if p.PhotoURL != "" {
		if len(p.PhotoURL) > 2048 {
			return errProfile("photo_url이 너무 길어요(최대 2048자)")
		}
		if lower := strings.ToLower(p.PhotoURL); !strings.HasPrefix(lower, "http://") && !strings.HasPrefix(lower, "https://") {
			return errProfile("photo_url은 http(s) 주소여야 해요")
		}
	}
	if len([]rune(p.Title)) > 40 {
		return errProfile("직함은 40자 이내여야 해요")
	}
	if p.CareerYears < 0 || p.CareerYears > 50 {
		return errProfile("경력 연차는 0~50 사이여야 해요")
	}
	if len([]rune(p.Bio)) > 500 {
		return errProfile("소개문은 500자 이내여야 해요")
	}
	for name, list := range map[string][]string{"specialties": p.Specialties, "certifications": p.Certifications, "awards": p.Awards} {
		if len(list) > 20 {
			return errProfile(fmt.Sprintf("%s 항목은 20개 이내여야 해요", name))
		}
		for _, v := range list {
			if strings.TrimSpace(v) == "" {
				return errProfile(fmt.Sprintf("%s에 빈 항목이 있어요", name))
			}
			if len([]rune(v)) > 80 {
				return errProfile(fmt.Sprintf("%s 항목은 80자 이내여야 해요", name))
			}
		}
	}
	return nil
}

// Normalize — 배열 null 금지 규약(v1.3 연장): nil 슬라이스를 빈 배열로 승격.
func (p *StaffProfile) Normalize() {
	if p.Specialties == nil {
		p.Specialties = []string{}
	}
	if p.Certifications == nil {
		p.Certifications = []string{}
	}
	if p.Awards == nil {
		p.Awards = []string{}
	}
}

// 역할 상수(Staff.Role, Member 관점의 인증 Principal.Role 공용).
const (
	RoleOwner   = "owner"
	RoleTrainer = "trainer"
	RoleMember  = "member"

	// RoleSuperadmin — 교차 센터 관리 평면 전용(멀티센터 Phase A, 설계04 §2). 센터 소속이
	// 없고(UserIndex.center_id="") Staff 레코드도 없다 — 센터 생성·최초 owner 초대만 하고,
	// 회원·매출 등 일상 운영 API에는 들어가지 않는다(IsStaff에 포함시키지 않는 이유).
	// 최초 superadmin 1회는 Firestore 콘솔에서 users/{uid} = {role:"superadmin", center_id:""}
	// 수작업 시딩(backend README 부트스트랩 절차).
	RoleSuperadmin = "superadmin"
)

// Payout — 트레이너 정산 방식.
type Payout struct {
	Type  string  `json:"type"` // per_session|rate
	Value float64 `json:"value"`
}

// Payout.Type 값.
const (
	PayoutPerSession = "per_session" // 회당 정산액(원)
	PayoutRate       = "rate"        // 매출 배분율(0~1 소수)
)

// maxPerSessionPayout — 회당 정산액 상한(원). 정산 규칙이 아니라 오타 방어선이다
// (35,000을 3,500,000으로 잘못 넣는 사고를 저장 전에 막는다).
const maxPerSessionPayout = 1_000_000

// DefaultPayout — 정산 미지정 시 기본값(회당 0원). "0"은 미정을 뜻하고, owner처럼 정산
// 대상이 아닌 스태프도 이 값을 쓴다(시딩된 박관장의 Payout{}과 같은 자리).
func DefaultPayout() Payout { return Payout{Type: PayoutPerSession, Value: 0} }

// Validate — 정산 값 범위 검증(POST /v1/staff). 잘못된 type을 통과시키면 정산 화면이
// 조용히 0원을 표시하므로 저장 전에 거부한다.
func (p Payout) Validate() error {
	switch p.Type {
	case PayoutPerSession:
		if p.Value < 0 || p.Value > maxPerSessionPayout {
			return errStaff("회당 정산액은 0~1,000,000원 사이여야 해요")
		}
	case PayoutRate:
		if p.Value < 0 || p.Value > 1 {
			return errStaff("정산 비율은 0~1 소수여야 해요(50% = 0.5)")
		}
	default:
		return errStaff("정산 방식은 per_session 또는 rate여야 해요")
	}
	return nil
}

// IsOffday — 해당 날짜가 휴무일인지(P47: 고정 스케줄 생성 제외 판정에 사용).
func (s Staff) IsOffday(date string) bool {
	for _, d := range s.Offdays {
		if d == date {
			return true
		}
	}
	return false
}

// ---- 스태프 온보딩(POST /v1/staff) ----

// ErrInvalidStaff — 스태프 생성 입력 값 위반(400 매핑, api/util.go의 writeErr 참고).
var ErrInvalidStaff = errors.New("domain: invalid staff")

func errStaff(msg string) error { return errors.Join(ErrInvalidStaff, errors.New(msg)) }

// StaffCreate — POST /v1/staff 요청 바디. 어드민은 트레이너도 로그인해서 쓰므로(이메일/비밀번호)
// 스태프 생성은 "로그인 계정 + Staff 레코드 + UserIndex"가 한 묶음이다 — 이 타입은 그중
// 순수 입력 검증만 안다(계정 발급은 api 레이어의 UserProvisioner 소관).
//
// color·payout은 선택이다: 미지정이면 서비스가 팔레트 자동 배정 / DefaultPayout()으로 채운다.
type StaffCreate struct {
	Name   string  `json:"name"`
	Email  string  `json:"email"`  // 로그인 ID(Firebase 이메일 계정). Staff 레코드·응답에는 담기지 않는다
	Role   string  `json:"role"`   // owner|trainer — member는 스태프가 아니다
	Color  string  `json:"color"`  // "#rrggbb"(선택)
	Payout *Payout `json:"payout"` // 선택 — nil과 {type:"",value:0}을 구분해야 해서 포인터
}

// Normalize — 검증·비교 전 표기 정리. 이메일을 소문자로 접는 이유: 같은 사람을 "A@x.com"과
// "a@x.com"으로 두 번 초대하면 계정은 하나인데 uid 판정이 갈려 스태프가 중복 생성될 수 있다.
func (c *StaffCreate) Normalize() {
	c.Name = strings.TrimSpace(c.Name)
	c.Email = strings.ToLower(strings.TrimSpace(c.Email))
	c.Role = strings.TrimSpace(c.Role)
	c.Color = strings.ToLower(strings.TrimSpace(c.Color))
}

// Validate — Normalize 이후 호출 전제(공백·대소문자는 이미 정리된 값).
func (c StaffCreate) Validate() error {
	switch {
	case c.Name == "":
		return errStaff("이름을 입력해주세요")
	case len([]rune(c.Name)) > 40:
		return errStaff("이름은 40자 이내여야 해요")
	case c.Role != RoleOwner && c.Role != RoleTrainer:
		return errStaff("역할은 owner 또는 trainer여야 해요")
	}
	if err := validateEmail(c.Email); err != nil {
		return err
	}
	if c.Color != "" && !isHexColor(c.Color) {
		return errStaff("색상은 #rrggbb 형식이어야 해요")
	}
	if c.Payout != nil {
		return c.Payout.Validate()
	}
	return nil
}

// validateEmail — 로그인 ID로 쓸 이메일 검증. net/mail 파서 결과가 입력과 다르면 거부한다
// (예: "홍길동 <a@x.com>" — 표시이름이 섞인 형태는 계정 ID가 될 수 없다).
func validateEmail(email string) error {
	if email == "" {
		return errStaff("이메일을 입력해주세요")
	}
	if len(email) > 254 { // RFC 5321 경로 상한 — Firebase 계정 생성 전에 여기서 자른다
		return errStaff("이메일이 너무 길어요")
	}
	addr, err := mail.ParseAddress(email)
	if err != nil || addr.Address != email {
		return errStaff("이메일 형식이 올바르지 않아요")
	}
	// 도메인에 점이 없는 값("coach@gmail")은 파서를 통과하지만 실제로는 오타다.
	if at := strings.LastIndex(email, "@"); at < 0 || !strings.Contains(email[at+1:], ".") {
		return errStaff("이메일 형식이 올바르지 않아요")
	}
	return nil
}

// isHexColor — "#rrggbb"(소문자 전제 — Normalize가 접어둔다). 어드민·앱이 이 값을 그대로
// 배경색 스타일에 넣으므로 형식을 좁게 가둔다.
func isHexColor(s string) bool {
	if len(s) != 7 || s[0] != '#' {
		return false
	}
	for i := 1; i < len(s); i++ {
		if c := s[i]; (c < '0' || c > '9') && (c < 'a' || c > 'f') {
			return false
		}
	}
	return true
}

// ---- 스태프 정정(PUT /v1/staff/{uid}, v2.0) ----

// StaffUpdate — 정정 요청 바디. **머지 시맨틱**이라 전 필드가 포인터다: "안 보냄"(nil)과
// "빈 값으로 지움"을 구분해야 이름만 고치는 요청이 정산 조건을 0으로 초기화하지 않는다
// (PUT /v1/members·/v1/center와 같은 규약. profile의 "통 교체"와는 다른 자리 — 이름·색·정산·
// 역할은 서로 다른 편집 지점에서 온다).
//
// **status는 의도적으로 없다**(계약 v2.0): 상태 전이는 deactivate/reactivate 전용 동사만
// 담당한다. 디코더가 DisallowUnknownFields라 바디에 status를 실으면 400이 된다
// (RefundPass가 상태 전이를 전용 엔드포인트로 뺀 선례와 같다).
type StaffUpdate struct {
	Name   *string `json:"name"`
	Color  *string `json:"color"`
	Payout *Payout `json:"payout"`
	Role   *string `json:"role"`
}

// Normalize — StaffCreate.Normalize와 같은 표기 정리(공백 제거·색 소문자 접기).
func (u *StaffUpdate) Normalize() {
	if u.Name != nil {
		v := strings.TrimSpace(*u.Name)
		u.Name = &v
	}
	if u.Color != nil {
		v := strings.ToLower(strings.TrimSpace(*u.Color))
		u.Color = &v
	}
	if u.Role != nil {
		v := strings.TrimSpace(*u.Role)
		u.Role = &v
	}
}

// Validate — Normalize 이후 호출 전제. 보낸 필드만 검사한다(안 보낸 필드는 기존 값 유지).
func (u StaffUpdate) Validate() error {
	if u.Name != nil {
		switch {
		case *u.Name == "":
			return errStaff("이름을 입력해주세요")
		case len([]rune(*u.Name)) > 40:
			return errStaff("이름은 40자 이내여야 해요")
		}
	}
	// 색은 빈 문자열로 지울 수 없다 — 스케줄 그리드가 색 없는 스태프를 그리지 못한다
	// (생성 시 팔레트 자동 배정과 대칭: 항상 값이 있어야 한다).
	if u.Color != nil && !isHexColor(*u.Color) {
		return errStaff("색상은 #rrggbb 형식이어야 해요")
	}
	if u.Role != nil && *u.Role != RoleOwner && *u.Role != RoleTrainer {
		return errStaff("역할은 owner 또는 trainer여야 해요")
	}
	if u.Payout != nil {
		return u.Payout.Validate()
	}
	return nil
}

// IsEmpty — 갱신할 필드가 하나도 없는 요청인지(빈 바디 400 판정용).
func (u StaffUpdate) IsEmpty() bool {
	return u.Name == nil && u.Color == nil && u.Payout == nil && u.Role == nil
}

// StaffPalette — 스태프 식별색 자동 배정 팔레트. 앞 3색은 DEV_SEED 스태프(박관장·정혜린·
// 김태오)가 쓰던 색 그대로다 — 데모와 실데이터의 인상을 맞춘다. 어두운 배경의 스케줄 그리드
// 위에서 서로 구분되는 채도로 골랐다.
var StaffPalette = []string{
	"#60a5fa", "#f43f5e", "#34d399", "#f59e0b",
	"#a78bfa", "#22d3ee", "#fb7185", "#84cc16",
}

// PickStaffColor — used(기존 스태프 색)와 겹치지 않는 첫 팔레트 색. 색이 겹치면 스케줄
// 그리드에서 누구 수업인지 구분이 안 되므로 자동 배정은 중복 회피가 핵심이다.
func PickStaffColor(used []string) string {
	taken := make(map[string]bool, len(used))
	for _, c := range used {
		taken[strings.ToLower(strings.TrimSpace(c))] = true
	}
	for _, c := range StaffPalette {
		if !taken[c] {
			return c
		}
	}
	// 팔레트를 다 쓴 규모(스태프 9명 이상)에선 중복을 피할 수 없다 — 순환 배정한다.
	return StaffPalette[len(used)%len(StaffPalette)]
}
