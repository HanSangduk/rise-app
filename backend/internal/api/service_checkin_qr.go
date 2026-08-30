package api

// 데스크 체크인 QR 토큰(P49, 계약 v2.23) — GET/POST /v1/center/checkin-qr의 서비스 절.
//
// UpdateCenterFacility(v2.19)와 나란한 파일이고 권한선·머지 규약도 같지만, 따로 두는 이유는
// 이 절만 **비밀**이라는 것이다. facility·business는 계약서에 인쇄되는 공개 사실이라 회원도
// GET /v1/center에서 본다. 체크인 토큰은 반대다 — 아는 사람이 늘어날수록 값어치가 0에
// 수렴하고, 회원 한 명이 알면 그 순간 집에서 출석을 찍는다. 그래서 같은 센터 문서에 살아도
// **응답 경로를 공유하지 않는다**(CenterResponse에 필드가 없고, 전용 뷰 타입으로만 나간다).

import (
	"context"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// CheckinQRView — GET·POST /v1/center/checkin-qr의 응답(와이어 3키).
//
// **전용 응답 타입인 것이 보안 설계다**(PublicBusiness의 BusinessView와 같은 근거). 센터 문서
// 전체를 내려보내고 민감 필드를 마스킹하는 방식이었다면, 다음에 누가 필드를 하나 늘릴 때
// 마스킹 목록에 추가하는 것을 잊는 순간 새어나간다. 여기서는 담을 것을 손으로 적어야만
// 나가므로, 잊어서 새는 방향의 사고가 성립하지 않는다.
//
// issued를 **서버가 계산해 보내는** 이유(BusinessView.Complete와 같은 자리): 어드민이
// `token !== ""`로 직접 판정하면, 언젠가 토큰을 가린 응답을 받았을 때 "미발급"으로 잘못
// 표시하고 대표가 재발급을 눌러 데스크의 멀쩡한 인쇄물을 무효로 만든다.
type CheckinQRView struct {
	// Issued — 발급된 적이 있는가. 어드민은 이 값으로 "발급" / "재발급" 버튼을 고른다.
	Issued bool `json:"issued"`
	// Token — 인쇄 QR 원문. 미발급이면 "". owner 응답에만 실린다.
	Token string `json:"token"`
	// IssuedAt — 마지막 발급 시각(RFC3339 UTC). 미발급이면 null. 데스크에 붙은 종이가
	// 최신인지 판단할 유일한 근거다 — 재발급은 이전 인쇄물을 즉시 무효로 만든다.
	IssuedAt *time.Time `json:"issued_at"`
}

func checkinQRView(q domain.CheckinQR) CheckinQRView {
	q.Normalize() // 응답 직전에도 한 번 더(손편집 문서가 인쇄물과 어긋나지 않게 — businessView와 같은 규약)
	return CheckinQRView{Issued: q.Issued(), Token: q.Token, IssuedAt: q.IssuedAt}
}

// GetCheckinQR — GET /v1/center/checkin-qr(**owner 전용**).
//
// 왜 트레이너도 안 되는가: 데스크를 지키는 사람이 트레이너인 센터가 많으니 실무적으로는
// 트레이너에게 열어 주고 싶어진다. 그런데 이 값은 "보는 권한"과 "가지는 권한"이 같다 —
// 한 번 보면 화면을 찍어 영구히 보관할 수 있고, 퇴사해도 그 사본은 남는다. 인쇄물은 대표가
// 한 번 뽑아 붙이면 되는 물건이라 열어 줘서 얻는 편의보다 잃는 통제가 크다. 트레이너가
// 회원 출석을 찍어야 하는 상황은 이미 tap 체크인이 담당한다(권한 분리가 이미 존재한다).
//
// 미발급이면 200 + {issued:false, token:"", issued_at:null}이다(404가 아니다) — 어드민이
// "아직 발급 안 됨" 화면을 그리는 정상 상태이고, 404로 만들면 진짜 오류와 구분이 사라진다.
func (s *Service) GetCheckinQR(ctx context.Context, p Principal) (CheckinQRView, error) {
	if !p.IsOwner() {
		return CheckinQRView{}, ErrForbidden
	}
	q, err := s.store.GetCheckinQR(ctx, p.CenterID)
	if err != nil {
		return CheckinQRView{}, err
	}
	return checkinQRView(*q), nil
}

// RotateCheckinQR — POST /v1/center/checkin-qr/rotate(**owner 전용**). 새 토큰을 만들어
// 저장하고 같은 모양으로 돌려준다. 최초 발급과 재발급이 **같은 동사**다.
//
// 둘을 가르지 않은 이유: 나누면 "이미 발급됨"을 409로 돌려주는 분기가 생기고, 어드민은 그
// 상태를 먼저 조회해 버튼을 고르게 된다 — 조회와 실행 사이에 다른 창에서 발급이 끼면 대표는
// 무엇이 실패했는지 알 수 없는 에러를 본다. 발급은 멱등할 수 없는 행위(늘 새 값이다)라
// 어차피 확인은 UI의 몫이고, 서버는 "누르면 새로 난다"는 한 가지 의미만 갖는 편이 정직하다.
//
// **재발급은 이전 토큰을 즉시 무효로 만든다**(절 통 교체 — 스토어가 두 키를 함께 덮는다).
// 데스크에 붙은 인쇄물이 그 순간 죽는다는 뜻이고, 그것이 이 동사의 값어치다: 토큰이 샜을 때
// 대표가 스스로 되돌릴 수단이 여기 말고는 없다. 어드민이 누르기 전에 경고해야 하는 이유다.
func (s *Service) RotateCheckinQR(ctx context.Context, p Principal) (CheckinQRView, error) {
	if !p.IsOwner() {
		return CheckinQRView{}, ErrForbidden
	}
	token, err := domain.NewCheckinQRToken()
	if err != nil {
		// crypto/rand 실패는 500이다. 약한 대체 소스로 내려가지 않는다 — "발급됐다"는 응답
		// 뒤에 추측 가능한 토큰이 인쇄되는 것이 발급 실패보다 훨씬 나쁘다.
		return CheckinQRView{}, err
	}
	now := time.Now().UTC()
	q := domain.CheckinQR{Token: token, IssuedAt: &now}
	if err := s.store.SaveCheckinQR(ctx, p.CenterID, &q); err != nil {
		return CheckinQRView{}, err
	}
	return checkinQRView(q), nil
}
