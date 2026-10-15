package domain

import (
	"errors"
	"fmt"
	"strings"
	"time"
)

// BodyPhotoPathOwnedBy — storage_path가 그 회원의 체형사진 폴더 안인가(v2.38, P74).
// 규약은 storage.rules(`match /members/{memberId}/body/{fileName}`)와 앱의 BodyPhotoStoragePath가 공유한다:
// **정확히** `members/{memberId}/body/{fileName}` 세 단계 + 파일명 하나, 파일명은 비어 있지 않고
// `/`·`..`를 담지 않는다. memberId가 비면 어떤 경로도 소유할 수 없다(빈 접두사가 모든 경로를 통과시킨다).
func BodyPhotoPathOwnedBy(storagePath, memberID string) bool {
	if memberID == "" || strings.ContainsAny(memberID, "/") {
		return false
	}
	prefix := "members/" + memberID + "/body/"
	if !strings.HasPrefix(storagePath, prefix) {
		return false
	}
	name := storagePath[len(prefix):]
	return name != "" && !strings.Contains(name, "/") && name != "." && name != ".."
}

// BodyPhoto — 체형 분석 사진 메타(API계약 v1). 실제 이미지는 Storage에, 여기는 메타만 보관한다.
// 저장 전 Consent.SensitiveConsentValid()가 참이어야 한다(P8 불변식5) — 강제는 서비스 레이어의 몫.
type BodyPhoto struct {
	ID          string `json:"id"`
	MemberID    string `json:"member_id"`
	Pose        string `json:"pose"`      // stand|tpose|fold|ohsquat
	Direction   string `json:"direction"` // front|side|back
	Date        string `json:"date"`
	StoragePath string `json:"storage_path"`
	Blurred     bool   `json:"blurred"` // 배경 인물 자동 블러 적용 여부(P34)

	// DeletedAt — 소프트 삭제 시각(v2.13). nil이면 살아 있다.
	//
	// **왜 즉시 파기하지 않나.** 체형 사진은 잘못 눌러 지우면 되돌릴 방법이 없다 —
	// 그날의 몸은 다시 못 찍는다. 유예 기간을 두면 오조작을 되돌릴 수 있고,
	// 그 사이에도 회원·코치 화면에서는 즉시 사라져 "지웠다"는 약속은 지켜진다.
	//
	// **왜 불리언이 아닌가.** 30일 시계가 이 값 하나에서 나온다. 불리언이면 지운
	// 시각을 어딘가 따로 들고 있어야 하고, 두 값이 갈리는 순간 파기 기한이 흔들린다.
	DeletedAt *time.Time `json:"deleted_at,omitempty"`
}

// BodyPhotoPurgeAfter — 소프트 삭제 후 완전 파기까지의 유예.
//
// 개인정보처리방침이 약속한 "요청하면 파기"와 오조작 복구 사이의 절충값이다.
// 이 값을 늘리면 방침 문구도 함께 고쳐야 한다 — 문서와 코드가 갈리면 문서가 거짓이 된다.
const BodyPhotoPurgeAfter = 30 * 24 * time.Hour

// IsDeleted — 소프트 삭제됐는가(목록·열람에서 숨긴다).
func (b BodyPhoto) IsDeleted() bool { return b.DeletedAt != nil }

// PurgeDue — 유예가 지나 **실제로 지워야 하는가**.
//
// 경계는 `>=`가 아니라 `>`다: 30일째 되는 순간이 아니라 30일을 **넘긴** 뒤에 지운다.
// 회원에게 "30일 뒤"라고 안내하는 값과 실제 파기 시점이 하루라도 어긋나면 안 된다.
func (b BodyPhoto) PurgeDue(now time.Time) bool {
	if b.DeletedAt == nil {
		return false
	}
	return now.Sub(*b.DeletedAt) > BodyPhotoPurgeAfter
}

// DaysUntilPurge — 파기까지 남은 일수(안내 문구용). 살아 있으면 nil.
func (b BodyPhoto) DaysUntilPurge(now time.Time) *int {
	if b.DeletedAt == nil {
		return nil
	}
	left := BodyPhotoPurgeAfter - now.Sub(*b.DeletedAt)
	d := int(left.Hours() / 24)
	if d < 0 {
		d = 0
	}
	return &d
}

// BodyPhoto.Pose 값(설계03 §4 포즈 4종 시퀀스).
const (
	PoseStand   = "stand"
	PoseTPose   = "tpose"
	PoseFold    = "fold"
	PoseOHSquat = "ohsquat"
)

// BodyPhoto.Direction 값.
const (
	DirFront = "front"
	DirSide  = "side"
	DirBack  = "back"
)

// Inbody — 체성분 측정(수기 입력, v1 — 기기 연동 OUT). 저장 전 sensitive consent 필수(P8).
//
// 필드명은 InBody 표준 약어를 그대로 쓴다. 설계00 §3 팩트체크#5 주의사항:
// BFM(Body Fat Mass)=체지방량이고, FFM(Fat Free Mass, 제지방량)이 아니다 — 혼동 시 오기재.
type Inbody struct {
	ID       string  `json:"id"`
	MemberID string  `json:"member_id"`
	Date     string  `json:"date"`
	Weight   float64 `json:"weight"` // 체중(kg)
	SMM      float64 `json:"smm"`    // 골격근량(kg)
	BFM      float64 `json:"bfm"`    // 체지방량(kg) — FFM(제지방량) 아님에 주의
	PBF      float64 `json:"pbf"`    // 체지방률(%)
	VFL      float64 `json:"vfl"`    // 내장지방레벨
	BMR      float64 `json:"bmr"`    // 기초대사량(kcal)

	// Source — 이 기록을 누가 넣었는가(v2.9). "member_self" | "staff" | ""(v2.9 이전 레코드).
	//
	// **요청으로 받지 않는다** — 서버가 Principal로 판정해 채운다(POST /v1/inbody의 요청 바디에
	// source를 넣으면 decodeJSON의 DisallowUnknownFields에 걸려 400이다). 이 값이 곧 삭제 권한의
	// 근거라(회원은 "member_self"만 지울 수 있다) 클라이언트가 정할 수 있으면 안 된다.
	//
	// 빈 값은 v2.9 이전에 저장된 레코드다. 백필하지 않는다 — Firestore 저장이 json 라운드트립이라
	// 기존 문서는 ""로 언마샬되고, ""는 "회원 본인이 넣었다는 근거가 없다"는 뜻이라 삭제 판정에서
	// staff와 같은 취급을 받는 게 안전한 기본값이다.
	Source string `json:"source"`
}

// Inbody.Source 값.
const (
	InbodySourceMemberSelf = "member_self" // 회원이 앱에서 결과지를 보고 수기 입력
	InbodySourceStaff      = "staff"       // 코치·대표가 어드민/데스크에서 입력
)

// ErrInvalidInbody — 인바디 값 범위/조합 위반(400 매핑).
var ErrInvalidInbody = errors.New("domain: invalid inbody")

func errInbody(msg string) error { return errors.Join(ErrInvalidInbody, errors.New(msg)) }

// 인바디 6지표의 허용 범위. **생리학적 하한이 아니라 "오입력 판별선"**이다 — 진짜 측정값을
// 막지 않을 만큼 넓게 잡고, 오타(부호·자릿수·빈 칸의 0.0·다른 지표 옮겨 적기)만 걸러낸다.
// 0을 전부 거부하는 게 이 표의 핵심이다: JSON에서 미입력 숫자는 0.0으로 직렬화되므로
// "선택 입력"은 곧 "0kg 체중"이 되고, 0은 차트에서 바닥으로 내려가 추이 자체를 망가뜨린다.
var inbodyRanges = []struct {
	name     string // 사용자 노출 라벨(어드민 BodyPhotos.tsx의 InbodyList와 같은 문자열)
	unit     string
	get      func(Inbody) float64
	min, max float64
	hint     string // 상한 초과 시 덧붙일 안내(무엇을 잘못 봤는지)
}{
	{"체중", "kg", func(i Inbody) float64 { return i.Weight }, 20, 300, ""},
	{"골격근량(SMM)", "kg", func(i Inbody) float64 { return i.SMM }, 5, 120, ""},
	{"체지방량(BFM)", "kg", func(i Inbody) float64 { return i.BFM }, 1, 200,
		"체지방량이에요 — 제지방량(FFM) 칸이 아니에요"},
	{"체지방률(PBF)", "%", func(i Inbody) float64 { return i.PBF }, 1, 70, ""},
	{"내장지방레벨(VFL)", "", func(i Inbody) float64 { return i.VFL }, 1, 30,
		"내장지방'레벨'이에요 — 단면적(cm²)이 아니에요"},
	{"기초대사량(BMR)", "kcal", func(i Inbody) float64 { return i.BMR }, 500, 5000, ""},
}

// Validate — 저장 전 값 검증(v2.9). 종전엔 서비스가 요청의 6개 숫자를 그대로 대입해 저장했고,
// 정정 수단이 없어(PUT/DELETE 부재) 오타 한 번이 회원 차트에 영구 고정됐다.
//
// 두 층으로 본다:
//  1. 개별 범위 — 부호·자릿수·빈 칸(0.0) 오류.
//  2. 교차 검증 — 개별 범위는 통과하는데 조합이 물리적으로 불가능한 경우. 체/제 오기
//     (BFM 칸에 FFM=제지방량을 적음)가 여기서만 잡힌다. FFM은 보통 체중의 70~90%라 개별
//     범위는 태연히 통과하지만, 골격근량과 더하면 체중을 넘는다.
//
// ID/MemberID/Date는 보지 않는다 — 그건 서비스 레이어의 스코프·형식 검증 소관이다.
func (i Inbody) Validate() error {
	for _, r := range inbodyRanges {
		v := r.get(i)
		if v < r.min || v > r.max {
			msg := fmt.Sprintf("%s은(는) %g~%g%s 사이로 입력해주세요(입력값 %g%s)",
				r.name, r.min, r.max, r.unit, v, r.unit)
			if v > r.max && r.hint != "" {
				msg += " — " + r.hint
			}
			return errInbody(msg)
		}
	}
	// SMM/BFM은 체중의 구성 요소다 — 체중 이상일 수 없다(같아도 불가능: 뼈·수분·장기가 남는다).
	if i.SMM >= i.Weight {
		return errInbody(fmt.Sprintf("골격근량(%gkg)이 체중(%gkg)보다 클 수 없어요 — 두 값을 다시 확인해주세요",
			i.SMM, i.Weight))
	}
	if i.BFM >= i.Weight {
		return errInbody(fmt.Sprintf("체지방량(%gkg)이 체중(%gkg)보다 클 수 없어요 — 제지방량(FFM)을 적으신 건 아닌지 확인해주세요",
			i.BFM, i.Weight))
	}
	if i.SMM+i.BFM > i.Weight {
		return errInbody(fmt.Sprintf("골격근량(%gkg)+체지방량(%gkg)이 체중(%gkg)을 넘어요 — 체지방량 칸에 제지방량(FFM)을 적으신 건 아닌지 확인해주세요",
			i.SMM, i.BFM, i.Weight))
	}
	return nil
}

// BodyPhotoPrefix — 이 회원의 체형사진이 놓이는 버킷 내부 경로 앞머리.
//
// 실제 경로는 `members/{id}/body/{yyyyMMdd}-{pose}-{direction}-{epochMs}.jpg`이고
// 이 형태는 **배포된 `storage.rules`가 정한다**(세그먼트 4개 고정). 앱이 만들고
// 서버는 받아 적기만 하므로 서버에 빌더가 없었는데, 버킷을 거꾸로 훑으려면
// (고아 파일 찾기 — ReconcileBodyPhotos) 앞머리만은 서버도 알아야 한다.
//
// ⚠ 이 값을 바꾸려면 `storage.rules`와 앱의 `BodyPhotoStoragePath`도 함께 바꿔야
// 한다. 셋 중 하나만 바뀌면 훑기가 아무것도 못 찾거나(조용한 실패) 규칙이 막는다.
func BodyPhotoPrefix(memberID string) string {
	return "members/" + memberID + "/body/"
}
