package domain

import (
	"errors"
	"strings"
	"time"
)

// ErrInvalidBusiness — 사업자 정보 형식 위반(400 매핑, PUT /v1/center v2.13).
var ErrInvalidBusiness = errors.New("domain: invalid business")

func errBusiness(msg string) error { return errors.Join(ErrInvalidBusiness, errors.New(msg)) }

// 자유 입력 칸의 길이 상한. 법정 고지에 그대로 인쇄되는 값이라 레이아웃을 깨는 길이를 막는다.
const (
	businessNameMax    = 60  // 사업자명·대표자명·직책·부서명·담당자명
	businessAddressMax = 200 // 사업장 주소(도로명 + 상세)
	businessPhoneMax   = 24
	businessEmailMax   = 120
	// businessFieldCount — Business의 칸 수. MissingFields/IsComplete가 이 개수를 전부 본다는
	// 사실을 테스트가 붙잡는다(칸을 늘리고 판정을 안 늘리면 여기서 깨진다).
	businessFieldCount = 12
)

// Business — 센터의 **법정 고지 기재사항**(v2.13). 이용약관·개인정보처리방침·민감정보 동의·
// 계정 삭제 안내 4개 문서가 이 값을 인쇄한다.
//
// **Policy와 나란히 두고 안에 넣지 않는 이유**: Policy는 "예약 용량·컷오프·위약금율"처럼
// 서비스 동작을 바꾸는 운영 다이얼이고, 이쪽은 동작을 하나도 바꾸지 않는 신원 정보다. 섞으면
// ① Policy.Validate가 두 종류의 실패를 한 sentinel로 말하게 되고 ② 정책 편집 폼의 "바뀐 필드만
// 저장" 비교(어드민 PolicyEditForm)가 중첩 객체를 참조 비교해 늘 "바뀜"으로 읽으며
// ③ 무인증 공개 응답에서 정책 값을 걷어내는 일이 매번 필요해진다 — 걷어내기를 한 번 빠뜨리면
// 연 매출 목표가 익명에게 나간다. 응답에서도 CenterResponse.business로 분리해 둔다.
//
// 값이 비어 있는 것은 오류가 아니다(아직 등록 전). 대신 **부분 입력과 완성을 반드시 구분**한다
// (IsComplete) — 법정 문서는 완성일 때만 초안 배너를 내린다.
type Business struct {
	BizName  string `json:"biz_name"`   // 사업자명(상호)
	CeoName  string `json:"ceo_name"`   // 대표자명
	BizRegNo string `json:"biz_reg_no"` // 사업자등록번호(###-##-##### 정규화)
	Address  string `json:"address"`    // 사업장 주소
	Phone    string `json:"phone"`      // 대표 전화
	Email    string `json:"email"`      // 대표 이메일
	// 개인정보 보호책임자(개인정보보호법 §31 — 처리방침 필수 기재).
	PrivacyOfficerName  string `json:"privacy_officer_name"`
	PrivacyOfficerTitle string `json:"privacy_officer_title"`
	PrivacyOfficerEmail string `json:"privacy_officer_email"`
	// 권리행사(열람·정정·삭제) 접수 창구 — 처리방침이 "어디로 접수하는지"를 적어야 한다.
	PrivacyDept    string `json:"privacy_dept"`
	PrivacyManager string `json:"privacy_manager"`
	// EffectiveDate — 약관 시행일(YYYY-MM-DD). 이 값이 없으면 문서는 "시행 전 초안"이다.
	EffectiveDate string `json:"effective_date"`
}

// businessField — 폼·문서·미기재 안내가 모두 같은 순서로 말하게 하는 단일 목록.
// 판정(IsComplete·MissingFields)이 이 목록 하나만 돌면 칸을 늘렸을 때 판정이 따라오지 않는
// 일이 생기지 않는다.
var businessFields = []struct {
	key string
	get func(Business) string
}{
	{"biz_name", func(b Business) string { return b.BizName }},
	{"ceo_name", func(b Business) string { return b.CeoName }},
	{"biz_reg_no", func(b Business) string { return b.BizRegNo }},
	{"address", func(b Business) string { return b.Address }},
	{"phone", func(b Business) string { return b.Phone }},
	{"email", func(b Business) string { return b.Email }},
	{"privacy_officer_name", func(b Business) string { return b.PrivacyOfficerName }},
	{"privacy_officer_title", func(b Business) string { return b.PrivacyOfficerTitle }},
	{"privacy_officer_email", func(b Business) string { return b.PrivacyOfficerEmail }},
	{"privacy_dept", func(b Business) string { return b.PrivacyDept }},
	{"privacy_manager", func(b Business) string { return b.PrivacyManager }},
	{"effective_date", func(b Business) string { return b.EffectiveDate }},
}

// Normalize — 저장·응답 직전에 값의 모양을 하나로 맞춘다.
//
// ① 앞뒤 공백 제거: 복사·붙여넣기로 들어온 공백 한 칸이 "채워진 칸"으로 읽히면 IsComplete가
// 거짓말을 하고, 문서에는 빈칸이 인쇄된다.
// ② 사업자등록번호를 ###-##-##### 로 통일: 어떻게 입력하든 문서에는 늘 같은 모양이 찍혀야 한다.
func (b *Business) Normalize() {
	b.BizName = strings.TrimSpace(b.BizName)
	b.CeoName = strings.TrimSpace(b.CeoName)
	b.Address = strings.TrimSpace(b.Address)
	b.Phone = strings.TrimSpace(b.Phone)
	b.Email = strings.TrimSpace(b.Email)
	b.PrivacyOfficerName = strings.TrimSpace(b.PrivacyOfficerName)
	b.PrivacyOfficerTitle = strings.TrimSpace(b.PrivacyOfficerTitle)
	b.PrivacyOfficerEmail = strings.TrimSpace(b.PrivacyOfficerEmail)
	b.PrivacyDept = strings.TrimSpace(b.PrivacyDept)
	b.PrivacyManager = strings.TrimSpace(b.PrivacyManager)
	b.EffectiveDate = strings.TrimSpace(b.EffectiveDate)

	reg := strings.TrimSpace(b.BizRegNo)
	if digits := strings.ReplaceAll(reg, "-", ""); len(digits) == 10 && isASCIIDigits(digits) {
		reg = digits[:3] + "-" + digits[3:5] + "-" + digits[5:]
	}
	b.BizRegNo = reg
}

// Validate — **채워진 칸의 형식만** 본다. 빈 칸은 통과시킨다.
//
// 완성 여부를 여기서 강제하지 않는 이유: 대표는 사업자등록증을 보며 아는 칸부터 채우고, 보호책임자
// 지정은 그 뒤에 온다. 전부 채워야만 저장되게 만들면 중간 저장이 불가능해 결국 메모장에 적어 두게
// 된다. 대신 "다 채워졌는가"는 IsComplete가 따로 답하고, 문서 게시는 그 답에만 반응한다 —
// **저장 가능 조건과 게시 가능 조건을 분리한 것**이 이 파일의 설계다.
func (b Business) Validate() error {
	b.Normalize() // 값 복사본 — 호출자의 공백 유무가 판정을 가르지 않게 같은 모양에서 본다

	for _, c := range []struct {
		val, label string
		max        int
	}{
		{b.BizName, "사업자명", businessNameMax},
		{b.CeoName, "대표자명", businessNameMax},
		{b.PrivacyOfficerName, "개인정보 보호책임자 성명", businessNameMax},
		{b.PrivacyOfficerTitle, "개인정보 보호책임자 직책", businessNameMax},
		{b.PrivacyDept, "접수 부서명", businessNameMax},
		{b.PrivacyManager, "담당자 성명", businessNameMax},
		{b.Address, "사업장 주소", businessAddressMax},
	} {
		if len([]rune(c.val)) > c.max {
			return errBusiness(c.label + "은(는) " + itoa(c.max) + "자까지예요")
		}
	}

	if b.BizRegNo != "" {
		digits := strings.ReplaceAll(b.BizRegNo, "-", "")
		if len(digits) != 10 || !isASCIIDigits(digits) {
			return errBusiness("사업자등록번호는 숫자 10자리여야 해요(예: 123-45-67890)")
		}
	}
	if b.Phone != "" {
		if len([]rune(b.Phone)) > businessPhoneMax || !isDialable(b.Phone) {
			return errBusiness("대표 전화 형식이 올바르지 않아요(예: 02-1234-5678)")
		}
	}
	for _, c := range []struct{ val, label string }{
		{b.Email, "대표 이메일"},
		{b.PrivacyOfficerEmail, "개인정보 보호책임자 이메일"},
	} {
		if c.val == "" {
			continue
		}
		if len([]rune(c.val)) > businessEmailMax || !isEmailLike(c.val) {
			return errBusiness(c.label + " 형식이 올바르지 않아요(예: help@example.com)")
		}
	}
	if b.EffectiveDate != "" {
		// 저장소의 다른 날짜 필드(휴무일·유효기간)와 같은 규약. time.Parse는 2026-02-30 같은
		// 존재하지 않는 날짜도 거부한다 — 문서 머리에 인쇄되는 값이라 그 검사가 필요하다.
		if _, err := time.Parse("2006-01-02", b.EffectiveDate); err != nil {
			return errBusiness("약관 시행일은 YYYY-MM-DD 형식이어야 해요(예: 2026-09-01)")
		}
	}
	return nil
}

// IsComplete — 12칸이 전부 채워졌는가. **법정 문서가 시행 상태로 게시될 수 있는 유일한 조건**이다.
// 한 칸이라도 비면 false — 개인정보처리방침에서 보호책임자 연락처가 빠지는 것은 형식 미비가
// 아니라 법정 기재사항 누락이고, 그 상태의 문서를 "시행 중"으로 게시하면 고지 자체가 흠결이 된다.
func (b Business) IsComplete() bool { return len(b.MissingFields()) == 0 }

// MissingFields — 아직 비어 있는 칸의 json 키 목록(폼 순서 고정). 어드민이 "무엇이 남았는지"를
// 그대로 보여주고, 문서는 그 칸만 미기재로 렌더한다. 순서를 고정하는 이유는 화면의 안내 문구가
// 재조회마다 뒤바뀌지 않게 하기 위함이다.
func (b Business) MissingFields() []string {
	out := make([]string, 0, businessFieldCount)
	for _, f := range businessFields {
		if strings.TrimSpace(f.get(b)) == "" {
			out = append(out, f.key)
		}
	}
	return out
}

// ---- 형식 판정(순수 stdlib — 정규식 없이 손으로 읽는다) ----

func isASCIIDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// isDialable — 숫자 8~15자리 + 구분자(하이픈·선행 +)만. 회원 휴대폰(phone.go)의 010 정규화를
// 태우지 않는 이유: 센터 대표번호는 02·031·1544처럼 유선·대표번호가 정상이라 010으로 접으면
// 실제로 거는 번호가 사라진다. 8자리 하한은 국내 최단(지역번호 없는 1544-0000 = 8자리) 기준.
func isDialable(s string) bool {
	digits := 0
	for i, r := range s {
		switch {
		case r >= '0' && r <= '9':
			digits++
		case r == '-':
		case r == '+' && i == 0:
		default:
			return false
		}
	}
	return digits >= 8 && digits <= 15
}

// isEmailLike — local@domain, 도메인에 점 하나 이상, 공백·중복 @·빈 라벨 없음. RFC 5322 전체를
// 구현하지 않는 이유: 여기서 걸러야 하는 건 "hello", "hello@rise" 같은 **오타**지 희귀 문법이
// 아니고, 지나치게 엄격한 판정은 대표가 실제로 쓰는 주소를 막아 등록 자체를 못 하게 만든다.
func isEmailLike(s string) bool {
	at := strings.IndexByte(s, '@')
	if at <= 0 || at != strings.LastIndexByte(s, '@') || at == len(s)-1 {
		return false
	}
	local, domain := s[:at], s[at+1:]
	if strings.ContainsAny(s, " \t\r\n") || local == "" {
		return false
	}
	labels := strings.Split(domain, ".")
	if len(labels) < 2 {
		return false
	}
	for _, l := range labels {
		if l == "" {
			return false
		}
	}
	return true
}

// itoa — 검증 메시지에 상한 숫자를 끼우는 용도(strconv 하나 때문에 import를 늘리지 않는다).
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}
