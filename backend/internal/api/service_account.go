package api

// 회원탈퇴(계약 v2.11) — 앱 안에서 스스로 계정을 지우는 유일한 경로.
//
// 왜 이 파일이 생겼나: 서버에 회원을 지우는 경로가 **하나도 없었다**. 라우터의 DELETE는
// bookings·recurrings·inbody 셋뿐이었다. Apple App Store Review Guideline 5.1.1(v)는 계정
// 생성을 지원하는 앱에 **앱 안에서의 계정 삭제**를 요구하고, 고객센터 안내나 웹 링크로 대체할
// 수 없다.
//
// 이 파일의 형태를 결정한 것은 같은 조항의 예외다 — *"법적 목적으로 특정 정보를 보관해야
// 한다면 그 필요를 고객에게 구체적으로 고지하고 나머지는 삭제하라."* 그래서 전부 지우지도,
// 계정만 비활성화하지도 않는다. **파기와 보존의 경계를 긋고 그 경계를 응답으로 말한다.**
//
//	파기 = 사람을 가리키는 값(domain.Member.Anonymized) + 건강·이용 기록(Store.PurgeMemberPersonalData)
//	       + 체형사진 원본 파일(MediaPurger) + 로그인 수단(UserIndex·Firebase 계정)
//	보존 = Ledger·Pass·Payment·Contract·과거 Booking — 전자상거래법 시행령 §6①(계약 5년,
//	       대금결제 5년). 이름·번호가 사라져 member_id라는 가명만 붙은 거래 기록으로 남는다.
//
// 근거의 전문은 domain.Member.Anonymized 주석과 work_log/P22를 참고.

import (
	"context"
	"errors"
	"log"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
	"github.com/ramsang/rise-backend/internal/store"
)

// RetainedCounts — 탈퇴 후에도 **남는** 기록의 건수(계약 v2.11). 응답에 싣는 이유는 하나다:
// 앱이 "무엇이 남는지"를 추상적으로 설명하는 대신 **실제 숫자로** 말할 수 있어야 하기 때문이다
// (Guideline 5.1.1(v)의 "구체적으로 고지"). 화면이 서버가 준 사실만 옮기게 하는 장치다.
type RetainedCounts struct {
	Passes    int `json:"passes"`
	Payments  int `json:"payments"`
	Contracts int `json:"contracts"`
	Ledger    int `json:"ledger"`
	Bookings  int `json:"bookings"`
}

// AccountDeletionResult — DELETE /v1/me 응답.
type AccountDeletionResult struct {
	Deleted     bool              `json:"deleted"`
	MemberID    string            `json:"member_id"`
	WithdrawnAt time.Time         `json:"withdrawn_at"`
	Purged      store.PurgeCounts `json:"purged"`
	Retained    RetainedCounts    `json:"retained"`
	// CancelledBookings — 무차감 취소된 미래 예약 수(노쇼 유예를 소진하지 않는다).
	CancelledBookings int `json:"cancelled_bookings"`
	// RemainingSessions — 탈퇴 시점의 잔여 회차(원장 합산). **0이 아닐 수 있다** — 잔여가
	// 남아도 탈퇴를 막지 않기 때문이다(아래 DeleteMyAccount 주석 ③). 앱이 완료 화면에
	// "남은 N회의 정산은 센터와 별도로 진행됩니다"를 사실대로 띄우는 근거다.
	RemainingSessions int `json:"remaining_sessions"`
}

// DeleteMyAccount — DELETE /v1/me. 호출자 **본인**의 계정을 지운다.
//
// 가드 ①(회원 전용): owner/trainer는 403. 스태프에겐 지울 회원 레코드가 없고, 만에 하나
// 회원으로도 연결된 계정이면 UserIndex가 사라져 **센터가 대표를 잃는다**(되돌릴 API 없음).
// v1.9 guardNotStaff·v2.0 락아웃 가드와 같은 계열의 방어선이고, 스태프의 이탈 경로는
// 대표의 POST /v1/staff/{uid}/deactivate로 이미 있다.
//
// 가드 ②(연결 필수): member_id가 없으면(가입 매칭 전) 404 — 지울 대상 자체가 없다. 계정만
// 만들고 센터에 연결되지 않은 사용자를 여기서 조용히 통과시키면 "탈퇴했다"는 응답이 실제로는
// 아무것도 하지 않은 응답이 된다.
//
// 가드 없음 ③: **잔여 회차가 남아 있어도 막지 않는다.** 검토하고 기각한 설계다 — Guideline
// 5.1.1(v)는 사업상 상태를 이유로 앱 안의 삭제를 막는 것을 예외로 인정하지 않는다. 막을
// 실익도 없다: Pass·Payment·Contract·Ledger가 전부 보존되므로 탈퇴 뒤에 환불을 요구해도
// 정산 근거는 살아 있다(그게 5년 보존의 목적이다). 대신 응답이 잔여 회차를 실어 앱이 고지한다.
//
// **단계 순서가 이 함수의 설계 그 자체다.** 외부 시스템 호출(Storage·Firebase)을 DB 쓰기보다
// **앞에** 둔다 — 그 둘이 실패해도 DB가 그대로면 같은 ID 토큰으로 재시도가 되기 때문이다
// (VerifyIDToken은 계정 삭제를 확인하지 않아 토큰이 최대 1시간 살아 있다 — provision.go 참고).
// 반대로 DB를 먼저 지우면 UserIndex가 사라진 순간 호출자는 403이 되어 **자기 탈퇴를 마저
// 끝낼 수도 없다.**
func (s *Service) DeleteMyAccount(ctx context.Context, p Principal) (AccountDeletionResult, error) {
	var res AccountDeletionResult
	if !p.IsMember() {
		return res, ErrForbidden // 가드 ①
	}
	if p.MemberID == "" {
		return res, store.ErrNotFound // 가드 ②
	}
	mem, err := s.store.GetMember(ctx, p.CenterID, p.MemberID)
	if err != nil {
		return res, err
	}
	if mem.IsWithdrawn() {
		// 여기 도달하는 정상 경로는 없다(탈퇴하면 UserIndex가 사라져 MemberID가 비므로 ②에서
		// 걸린다). 인덱스만 남은 잔여 상태에서 온 재시도를 위한 이중 방어선이다.
		return res, errors.Join(errBadRequest, errors.New("이미 탈퇴 처리된 계정이에요"))
	}

	now := time.Now().UTC()

	// ---- 0단계: 읽기만 — 지우기 전에 "무엇이 있었는지"를 센다 ----
	photos, err := s.store.ListBodyPhotos(ctx, p.CenterID, mem.ID)
	if err != nil {
		return res, err
	}
	paths := make([]string, 0, len(photos))
	for _, ph := range photos {
		paths = append(paths, ph.StoragePath)
	}
	retained, remaining, err := s.retainedForMember(ctx, p.CenterID, mem.ID)
	if err != nil {
		return res, err
	}

	// ---- 1단계: 체형사진 **원본 파일**(외부) ----
	// 메타보다 먼저 지운다. 반대로 하면 경로를 아는 유일한 문서가 먼저 사라져 원본이 버킷에
	// 영영 남는다 — 그 잔존은 아무 화면에도 드러나지 않아 발견조차 불가능하다. 실패하면
	// 여기서 500으로 멈추고 DB는 손대지 않는다(재시도가 메타에서 경로를 다시 찾는다).
	if _, err := s.media.DeleteObjects(ctx, paths); err != nil {
		return res, err
	}

	// ---- 2단계: Firebase 계정(외부) ----
	// 계정 안의 전화번호까지 파기된다. 아직 DB는 그대로라, 실패해도 같은 토큰으로 재시도된다.
	if err := s.users.DeleteUser(ctx, p.UID); err != nil {
		return res, err
	}

	// ---- 3단계: 미래 예약 무차감 취소 ----
	// CancelAtomic을 거쳐야 Slot.teams 사본까지 함께 비어 그 자리를 다른 회원이 쓸 수 있다.
	// 페널티 원장은 남기지 않는다 — 탈퇴는 노쇼가 아니다(v1.5 waive=true·v2.3 고정 스케줄
	// 해제와 같은 취급).
	cancelled, err := s.cancelFutureBookingsForWithdrawal(ctx, p.CenterID, mem.ID)
	if err != nil {
		return res, err
	}

	// ---- 4단계: 가명화 + 건강·이용 기록 파기(DB) ----
	anon := mem.Anonymized(now)
	purged, err := s.store.PurgeMemberPersonalData(ctx, p.CenterID, &anon)
	if err != nil {
		return res, err
	}
	// 파일 삭제 건수는 **메타 삭제 건수로 보고한다.** MediaPurger가 dev no-op일 수 있어
	// 그쪽 숫자를 믿으면 로컬·운영이 다른 말을 한다. 어차피 둘은 짝이다(경로가 메타에서 나온다).
	purged.BodyPhotos = len(photos)

	// ---- 5단계: 로그인 매핑 제거 ----
	// 남으면 인증이 옛 member_id를 그대로 복원한다. 마지막에 두는 이유는 이것이 호출자의
	// 권한 자체를 없애기 때문이다 — 앞 단계에서 이걸 지우면 뒤 단계가 자기 권한을 잃는다.
	if err := s.store.DeleteUserIndex(ctx, p.UID); err != nil {
		return res, err
	}

	// 감사 로그: 이 사건은 되돌릴 수 없고 응답은 클라이언트로만 나간다. 파기 사실과 건수를
	// 서버 로그에 남겨야 나중에 "언제 무엇이 지워졌나"에 답할 수 있다(개인정보 파기 기록).
	log.Printf("account deleted: member=%s uid=%s purged=%+v retained=%+v cancelled_bookings=%d remaining_sessions=%d",
		mem.ID, p.UID, purged, retained, cancelled, remaining)

	return AccountDeletionResult{
		Deleted:           true,
		MemberID:          mem.ID,
		WithdrawnAt:       now,
		Purged:            purged,
		Retained:          retained,
		CancelledBookings: cancelled,
		RemainingSessions: remaining,
	}, nil
}

// guardMemberNotWithdrawn — 탈퇴한 회원에게 **새 의무·새 데이터를 붙이지 못하게** 막는다.
//
// 탈퇴자는 스스로 호출할 수 없다(UserIndex·Firebase 계정이 없다). 그래서 이 가드가 지키는
// 것은 전부 **스태프 경로**다 — 어드민 화면에서 탈퇴 회원을 골라 회원권을 발급하거나 예약을
// 잡거나 Home Work를 배정하는 자리. 그 회원은 앱에 들어올 수 없으므로 그렇게 만들어진 것은
// 예외 없이 아무도 쓰지 못하는 유령 데이터이고, 개인정보 관점에서는 **파기했다고 고지한 계정에
// 새 처리를 다시 시작하는 것**이라 그 자체가 문제다.
//
// 400인 이유(403이 아니라): 호출자의 권한 문제가 아니라 대상의 상태 문제다 —
// "환불 처리된 패스의 예약은 400"과 같은 자리다.
func guardMemberNotWithdrawn(mem domain.Member, action string) error {
	if !mem.IsWithdrawn() {
		return nil
	}
	return errors.Join(errBadRequest, errors.New("탈퇴한 회원이에요 — "+action))
}

// retainedForMember — 탈퇴 후에도 남는 기록의 건수와 잔여 회차. **파기 전에** 센다 —
// 파기 후에 세면 미래 예약 취소분이 빠져 숫자가 달라진다.
//
// 잔여 회차는 원장 합(domain.Sum)으로 구한다. pass.remaining 스냅샷이 아니라 원장인 이유는
// P3 불변식 그대로다 — 스냅샷은 캐시일 뿐이고 완료·노쇼 경로에서 원장 합과 벌어질 수 있다.
func (s *Service) retainedForMember(ctx context.Context, centerID, memberID string) (RetainedCounts, int, error) {
	var out RetainedCounts

	passes, err := s.store.ListPassesByMember(ctx, centerID, memberID)
	if err != nil {
		return out, 0, err
	}
	out.Passes = len(passes)

	entries, err := s.store.ListLedger(ctx, centerID, memberID, "")
	if err != nil {
		return out, 0, err
	}
	out.Ledger = len(entries)
	remaining := domain.Sum(entries)
	if remaining < 0 {
		remaining = 0 // 음수 잔여는 화면에 띄울 값이 아니다(원장 드리프트의 표시일 뿐)
	}

	bookings, err := s.store.ListBookingsByMember(ctx, centerID, memberID)
	if err != nil {
		return out, 0, err
	}
	out.Bookings = len(bookings)

	contracts, err := s.store.ListContracts(ctx, centerID, memberID, "")
	if err != nil {
		return out, 0, err
	}
	out.Contracts = len(contracts)

	payments, err := s.store.ListPayments(ctx, centerID)
	if err != nil {
		return out, 0, err
	}
	for _, pay := range payments {
		if pay.MemberID == memberID {
			out.Payments++
		}
	}
	return out, remaining, nil
}

// cancelFutureBookingsForWithdrawal — 미래 confirmed 예약을 무차감 취소한다(entry=nil).
//
// 이미 지난 예약은 건드리지 않는다: 완료·노쇼 이력은 원장 항목이 ref_booking_id로 가리키는
// 대상이라, 지우거나 바꾸면 보존하기로 한 원장이 고아를 가리키게 된다(v2.3의 kept와 같은 판단).
func (s *Service) cancelFutureBookingsForWithdrawal(ctx context.Context, centerID, memberID string) (int, error) {
	bookings, err := s.store.ListBookingsByMember(ctx, centerID, memberID)
	if err != nil {
		return 0, err
	}
	now := time.Now()
	n := 0
	for _, b := range bookings {
		if b.Status != domain.BookingConfirmed {
			continue
		}
		if start, err := domain.SlotStart(b.SlotKey); err != nil || start.Before(now) {
			continue
		}
		switch err := s.store.CancelAtomic(ctx, centerID, b.ID, nil); {
		case err == nil:
			n++
		case errors.Is(err, store.ErrStateConflict), errors.Is(err, store.ErrNotFound):
			// 수집과 취소 사이에 이미 처리된 예약 — 정리할 것이 남아 있지 않다
			// (TransferStaff가 같은 경합을 같은 방식으로 흡수한다).
		default:
			return n, err
		}
	}
	return n, nil
}
