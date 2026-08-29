package domain

import (
	"errors"
	"strings"
	"testing"
)

// completeBusiness — 12칸이 전부 채워진 정상 레코드(테스트 기준선).
func completeBusiness() Business {
	return Business{
		BizName:             "라이즈 컨디셔닝",
		CeoName:             "김대표",
		BizRegNo:            "123-45-67890",
		Address:             "서울특별시 강남구 테헤란로 123, 4층",
		Phone:               "02-1234-5678",
		Email:               "hello@rise.kr",
		PrivacyOfficerName:  "김대표",
		PrivacyOfficerTitle: "대표",
		PrivacyOfficerEmail: "privacy@rise.kr",
		PrivacyDept:         "고객지원팀",
		PrivacyManager:      "박담당",
		EffectiveDate:       "2026-09-01",
	}
}

// 미등록(전 칸 공백)은 **오류가 아니다**. 센터가 아직 사업자 정보를 넣지 않은 상태는 정상적인
// 초기 상태이고, 이 단계에서 저장을 막으면 대표가 아는 칸부터 채워 나갈 수가 없다.
// 대신 IsComplete가 false여야 한다 — 법정 문서는 이 값 하나로 초안 배너를 유지한다.
func TestBusinessEmptyIsValidButNotComplete(t *testing.T) {
	var b Business
	if err := b.Validate(); err != nil {
		t.Errorf("빈 사업자 정보가 거부됐다: %v — 미등록은 정상 초기 상태다", err)
	}
	if b.IsComplete() {
		t.Error("빈 사업자 정보가 complete로 판정됐다 — 법정 문서가 빈칸인 채로 시행된다")
	}
	if got := b.MissingFields(); len(got) != businessFieldCount {
		t.Errorf("빈 레코드의 미기재 항목 %d개, want %d개(전 항목)", len(got), businessFieldCount)
	}
}

func TestBusinessCompleteRecord(t *testing.T) {
	b := completeBusiness()
	if err := b.Validate(); err != nil {
		t.Fatalf("정상 레코드가 거부됐다: %v", err)
	}
	if !b.IsComplete() {
		t.Errorf("정상 레코드가 미완성으로 판정됐다 — 미기재: %v", b.MissingFields())
	}
	if got := b.MissingFields(); len(got) != 0 {
		t.Errorf("정상 레코드에 미기재 항목이 남았다: %v", got)
	}
}

// **이 테스트가 이 파일의 존재 이유다.** 한 칸이라도 비어 있으면 complete가 아니다.
// "일부만 채워졌다"와 "다 채워졌다"를 구분하지 못하면 법정 문서가 반쪽으로 렌더돼
// 시행 중인 약관인 척하게 된다 — 개인정보처리방침에 보호책임자 연락처가 빠진 채로
// 게시되는 것은 형식 미비가 아니라 법정 기재사항 누락이다.
func TestBusinessPartialIsNotComplete(t *testing.T) {
	base := completeBusiness()
	// 12칸을 하나씩 비워 가며 전수 확인 — "이 칸만 예외로 없어도 된다"가 생기지 않게.
	for _, blank := range []struct {
		name string
		set  func(*Business)
	}{
		{"biz_name", func(b *Business) { b.BizName = "" }},
		{"ceo_name", func(b *Business) { b.CeoName = "" }},
		{"biz_reg_no", func(b *Business) { b.BizRegNo = "" }},
		{"address", func(b *Business) { b.Address = "" }},
		{"phone", func(b *Business) { b.Phone = "" }},
		{"email", func(b *Business) { b.Email = "" }},
		{"privacy_officer_name", func(b *Business) { b.PrivacyOfficerName = "" }},
		{"privacy_officer_title", func(b *Business) { b.PrivacyOfficerTitle = "" }},
		{"privacy_officer_email", func(b *Business) { b.PrivacyOfficerEmail = "" }},
		{"privacy_dept", func(b *Business) { b.PrivacyDept = "" }},
		{"privacy_manager", func(b *Business) { b.PrivacyManager = "" }},
		{"effective_date", func(b *Business) { b.EffectiveDate = "" }},
	} {
		b := base
		blank.set(&b)
		// 부분 입력도 **저장은 된다** — 대표가 아는 칸부터 채워 나가는 게 정상 동선이다.
		if err := b.Validate(); err != nil {
			t.Errorf("%s만 빈 레코드가 저장에서 거부됐다: %v — 부분 입력은 오류가 아니다", blank.name, err)
		}
		if b.IsComplete() {
			t.Errorf("%s가 비었는데 complete로 판정됐다 — 그 칸이 빠진 채로 문서가 시행된다", blank.name)
		}
		if got := b.MissingFields(); len(got) != 1 || got[0] != blank.name {
			t.Errorf("%s만 빈 레코드의 미기재 목록 = %v, want [%s]", blank.name, got, blank.name)
		}
	}
}

// 공백만 있는 칸은 **빈 칸이다**. 스페이스 한 칸으로 complete가 되면 문서에 공백이 인쇄된다.
func TestBusinessWhitespaceOnlyIsMissing(t *testing.T) {
	b := completeBusiness()
	b.BizName = "   "
	if b.IsComplete() {
		t.Error("공백만 있는 사업자명이 complete로 판정됐다 — 문서에 빈칸이 인쇄된다")
	}
	b.Normalize()
	if b.BizName != "" {
		t.Errorf("Normalize 후 사업자명 = %q, want \"\"(공백은 미기재로 접힌다)", b.BizName)
	}
}

// 사업자등록번호 — 숫자 10자리. 문서에 인쇄되는 법정 기재사항이라 자릿수가 틀리면 저장 전에 막는다.
func TestBusinessRegNoFormat(t *testing.T) {
	bad := []string{
		"123456789",     // 9자리
		"12345678901",   // 11자리
		"123-45-6789",   // 하이픈 제외 9자리
		"123-45-678901", // 하이픈 제외 11자리
		"12A-45-67890",  // 숫자 아님
		"123 45 67890",  // 공백 구분자는 허용하지 않는다(문서 인쇄 형태가 흔들린다)
		"１２３４５６７８９０",    // 전각 숫자
	}
	for _, v := range bad {
		b := completeBusiness()
		b.BizRegNo = v
		if err := b.Validate(); !errors.Is(err, ErrInvalidBusiness) {
			t.Errorf("잘못된 사업자등록번호 %q가 통과했다: %v", v, err)
		}
	}
	for _, v := range []string{"1234567890", "123-45-67890"} {
		b := completeBusiness()
		b.BizRegNo = v
		if err := b.Validate(); err != nil {
			t.Errorf("정상 사업자등록번호 %q가 거부됐다: %v", v, err)
		}
	}
	// 하이픈 없이 넣어도 문서에는 늘 같은 모양으로 인쇄돼야 한다.
	b := completeBusiness()
	b.BizRegNo = "1234567890"
	b.Normalize()
	if b.BizRegNo != "123-45-67890" {
		t.Errorf("정규화 후 = %q, want \"123-45-67890\"(인쇄 형태 통일)", b.BizRegNo)
	}
}

// 이메일 2칸(대표·보호책임자) — 개인정보처리방침의 권리행사 창구다. 잘못된 주소가 실리면
// 정보주체가 열람·정정을 요구할 경로 자체가 없어진다.
func TestBusinessEmailFormat(t *testing.T) {
	bad := []string{"hello", "hello@", "@rise.kr", "hello@rise", "he llo@rise.kr", "hello@@rise.kr", "hello@rise..kr", "hello@.kr"}
	for _, v := range bad {
		for _, field := range []string{"email", "privacy_officer_email"} {
			b := completeBusiness()
			if field == "email" {
				b.Email = v
			} else {
				b.PrivacyOfficerEmail = v
			}
			if err := b.Validate(); !errors.Is(err, ErrInvalidBusiness) {
				t.Errorf("%s에 잘못된 이메일 %q가 통과했다: %v", field, v, err)
			}
		}
	}
	for _, v := range []string{"hello@rise.kr", "privacy.officer+tag@sub.example.co.kr"} {
		b := completeBusiness()
		b.Email, b.PrivacyOfficerEmail = v, v
		if err := b.Validate(); err != nil {
			t.Errorf("정상 이메일 %q가 거부됐다: %v", v, err)
		}
	}
}

// 시행일 — 약관이 효력을 갖는 날짜다. 파싱되지 않는 값이 저장되면 문서 머리에 그대로 인쇄된다.
// 저장소의 다른 날짜 필드(offdays·valid_until)와 같은 규약: YYYY-MM-DD.
func TestBusinessEffectiveDateFormat(t *testing.T) {
	bad := []string{"2026-9-1", "2026/09/01", "20260901", "2026-13-01", "2026-02-30", "내일", "2026-09-01T00:00:00Z"}
	for _, v := range bad {
		b := completeBusiness()
		b.EffectiveDate = v
		if err := b.Validate(); !errors.Is(err, ErrInvalidBusiness) {
			t.Errorf("잘못된 시행일 %q가 통과했다: %v", v, err)
		}
	}
	for _, v := range []string{"2026-09-01", "2026-12-31", "2027-02-28"} {
		b := completeBusiness()
		b.EffectiveDate = v
		if err := b.Validate(); err != nil {
			t.Errorf("정상 시행일 %q가 거부됐다: %v", v, err)
		}
	}
}

// 대표 전화 — 회원이 실제로 거는 번호다. 회원 휴대폰(domain/phone.go)과 달리 02·1544 같은
// 유선·대표번호가 정상이라 010 정규화를 태우지 않는다. 숫자 8~15자리만 본다.
func TestBusinessPhoneFormat(t *testing.T) {
	for _, v := range []string{"1234567", "02-1234-5678-9012-3456", "02-abcd-5678", "전화없음"} {
		b := completeBusiness()
		b.Phone = v
		if err := b.Validate(); !errors.Is(err, ErrInvalidBusiness) {
			t.Errorf("잘못된 대표 전화 %q가 통과했다: %v", v, err)
		}
	}
	for _, v := range []string{"02-1234-5678", "010-1234-5678", "1544-0000", "0212345678", "+82-2-1234-5678"} {
		b := completeBusiness()
		b.Phone = v
		if err := b.Validate(); err != nil {
			t.Errorf("정상 대표 전화 %q가 거부됐다: %v", v, err)
		}
	}
}

// 자유 입력 칸의 길이 상한 — 문서 레이아웃을 깨는 값이 법정 고지에 실리지 않게.
func TestBusinessTextLengthCap(t *testing.T) {
	b := completeBusiness()
	b.Address = strings.Repeat("가", businessAddressMax+1)
	if err := b.Validate(); !errors.Is(err, ErrInvalidBusiness) {
		t.Errorf("상한 초과 주소가 통과했다: %v", err)
	}
	b = completeBusiness()
	b.BizName = strings.Repeat("가", businessNameMax+1)
	if err := b.Validate(); !errors.Is(err, ErrInvalidBusiness) {
		t.Errorf("상한 초과 사업자명이 통과했다: %v", err)
	}
	// 상한 정확히는 허용(경계 포함).
	b = completeBusiness()
	b.BizName = strings.Repeat("가", businessNameMax)
	b.Address = strings.Repeat("가", businessAddressMax)
	if err := b.Validate(); err != nil {
		t.Errorf("상한 경계값이 거부됐다: %v", err)
	}
}

// Normalize는 앞뒤 공백을 걷어낸다 — 복사·붙여넣기로 들어온 공백이 "채워진 칸"으로 오인되면
// complete 판정이 거짓이 된다(위 whitespace 테스트와 짝).
func TestBusinessNormalizeTrims(t *testing.T) {
	b := Business{BizName: "  라이즈 컨디셔닝\n", Email: " hello@rise.kr ", EffectiveDate: " 2026-09-01 "}
	b.Normalize()
	if b.BizName != "라이즈 컨디셔닝" || b.Email != "hello@rise.kr" || b.EffectiveDate != "2026-09-01" {
		t.Errorf("Normalize 결과 = %+v", b)
	}
	// 정규화한 값은 Validate를 통과해야 한다 — 안 그러면 붙여넣기가 곧 400이다.
	if err := b.Validate(); err != nil {
		t.Errorf("정규화한 값이 거부됐다: %v", err)
	}
}

// MissingFields는 화면이 "무엇이 비었는지"를 그대로 보여주는 목록이다. 순서가 흔들리면
// 어드민의 미기재 안내가 새로고침마다 뒤바뀐다 — 폼 순서로 고정한다.
func TestBusinessMissingFieldsStableOrder(t *testing.T) {
	var b Business
	first := b.MissingFields()
	for i := 0; i < 3; i++ {
		if got := b.MissingFields(); len(got) != len(first) {
			t.Fatalf("호출마다 길이가 다르다: %v vs %v", got, first)
		} else {
			for j := range got {
				if got[j] != first[j] {
					t.Fatalf("호출마다 순서가 다르다: %v vs %v", got, first)
				}
			}
		}
	}
	if first[0] != "biz_name" {
		t.Errorf("첫 항목 = %q, want \"biz_name\"(폼 순서)", first[0])
	}
}
