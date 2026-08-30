package domain

import (
	"errors"
	"regexp"
	"strings"
	"time"
)

// Center — 센터 신원(멀티센터 Phase A, 설계04). 종전엔 centers/{id} 문서가 Policy 보관용일
// 뿐이라 센터 "이름"조차 없었고, 어드민 3곳 + 회원앱이 상호를 하드코딩했다.
//
// 저장은 centers/{id} 문서의 `center` 맵으로 **네스팅**한다(Business의 `business` 맵과 같은
// 규약) — Policy 필드가 같은 문서 top-level에 살아서, 평평하게 병합하면 언젠가 키가 충돌한다.
type Center struct {
	// ID — 문서 키이자 storage.rules의 firestore.get 경로 세그먼트. 소문자 슬러그만 허용한다
	// (경로에 실리는 값이라 공백·특수문자가 곧 규칙 오동작이다).
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Phone     string    `json:"phone,omitempty"`
	Address   string    `json:"address,omitempty"`
	Status    string    `json:"status"` // active (v1은 전이 없음 — 폐업 등은 후속)
	CreatedAt time.Time `json:"created_at"`
}

const CenterStatusActive = "active"

var centerIDPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{1,29}$`)

// Normalize — 검증·저장 전 표기 정리(StaffCreate.Normalize와 같은 규약).
func (c *Center) Normalize() {
	c.ID = strings.ToLower(strings.TrimSpace(c.ID))
	c.Name = strings.TrimSpace(c.Name)
	c.Phone = strings.TrimSpace(c.Phone)
	c.Address = strings.TrimSpace(c.Address)
	c.Status = strings.TrimSpace(c.Status)
	if c.Status == "" {
		c.Status = CenterStatusActive
	}
}

// Validate — Normalize 이후 호출 전제.
func (c Center) Validate() error {
	switch {
	case !centerIDPattern.MatchString(c.ID):
		return errCenter("센터 ID는 소문자 영문·숫자·하이픈 2~30자여야 해요 (예: gangnam-2)")
	case c.Name == "":
		return errCenter("센터 이름을 입력해주세요")
	case len([]rune(c.Name)) > 60:
		return errCenter("센터 이름은 60자 이내여야 해요")
	case len([]rune(c.Phone)) > 20:
		return errCenter("전화번호는 20자 이내여야 해요")
	case len([]rune(c.Address)) > 120:
		return errCenter("주소는 120자 이내여야 해요")
	case c.Status != CenterStatusActive:
		return errCenter("status는 active여야 해요")
	}
	return nil
}

// ErrInvalidCenter — 센터 입력 값 위반(400 매핑, api/util.go의 writeErr 참고).
var ErrInvalidCenter = errors.New("domain: invalid center")

func errCenter(msg string) error { return errors.Join(ErrInvalidCenter, errors.New(msg)) }
