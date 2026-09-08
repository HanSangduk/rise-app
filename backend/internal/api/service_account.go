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
//	       + 회원발 요청 큐 2종(가입 요청·재등록/상담 요청, v2.26/P53)
//	보존 = Ledger·Pass·Payment·Contract·과거 Booking — 전자상거래법 시행령 §6①(계약 5년,
//	       대금결제 5년). 이름·번호가 사라져 member_id라는 가명만 붙은 거래 기록으로 남는다.
//	       단, 미서명(draft/sent) 계약은 **문서를 보존한 채 voided로 종결**한다(v2.17, P40) —
//	       서명 주체가 파기된 뒤의 "서명 대기"는 사실이 아니다. signed는 불가침.
//
// **경계는 컬렉션 단위로 다시 그어야 한다**(v2.26/P53이 배운 것). 종전의 파기는 "centers/
// {centerID}/… 아래에서 member_id가 일치하는 문서"라는 **모양**으로 정의돼 있었고, 그 모양을
// 벗어난 개인정보 두 벌이 조용히 살아남았다 — 최상위 컬렉션 join_requests(이름·전화번호 원본,
// member_id 없이 uid 키)와, v2.11 이후에 생겨 스윕 목록에 오르지 못한 consult_requests(자유
// 서술 메모). 새 컬렉션을 만들 때 물어야 할 질문은 "센터 아래인가"가 아니라 **"탈퇴가 이걸
// 지우는가"**다.
//
// 근거의 전문은 domain.Member.Anonymized 주석과 work_log/P22·P53을 참고.

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
// 가드 ②였던 것(연결 필수) — **v2.27에서 분기로 바뀌었다.** 종전엔 member_id가 없으면
// store.ErrNotFound(404)로 **진입부터 막았다.** 근거는 "지울 대상 자체가 없다"였는데, 그것이
// 사실이 아니었다: 미연결 계정에도 지울 것이 둘 있다 — Firebase 계정(전화번호를 품는다)과
// **join_requests의 이름·전화번호 원본**(POST /v1/join/request가 신청자에게 직접 받아 적은 값).
//
// 그래서 v2.26이 만든 파기 경로(DeleteJoinRequestsByUID)에 도달할 길이 **회원이 된 사람에게만**
// 열려 있었다. 대기실에 갇힌 사람 — 이름·번호를 서버에 넘겼는데 아직 승인되지 않은 사람 —
// 은 자기 이름·전화번호를 지울 수단이 앱 안에 하나도 없었다. 개인정보보호법 §36(삭제 요구권)이
// 정면으로 겨냥하는 상태이고, App Store Guideline 5.1.1(v)의 "앱 안에서의 계정 삭제"도
// 계정을 만든 모든 사용자에게 적용된다(회원 연결 여부를 조건으로 달지 않는다).
//
// 아래 deleteUnlinkedAccount가 그 축소판을 돈다 — 새 패턴이 아니라 **같은 7단계 중 회원
// 레코드에 의존하지 않는 단계만** 남긴 것이다(그 함수 주석에 단계별 판정을 적어 두었다).
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
		return s.deleteUnlinkedAccount(ctx, p) // v2.27 — 대기실 계정의 축소 경로
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

	// ---- 4단계: 미서명 계약 종결(voided, v2.17 · P40) ----
	// ②에서 서명 주체(Firebase 계정)가 파기됐다 — draft/sent의 "서명 대기"는 이 시점부터
	// 사실이 아니고, 남겨두면 어드민 미서명 카운트에 영원히 행동 불가능한 항목으로 잡힌다
	// (P37·P38 적대 리뷰 [H]). signed는 성립했던 거래의 법적 기록이라 불가침이고, 문서는
	// 남고 상태만 바뀌므로 5년 보존과 비저촉 — 환불의 미서명 void(v1.5)와 같은 논리다.
	//
	// 자리가 왜 여기인가(P22 순서 규약): ②보다 **뒤**여야 한다 — 외부 파기가 실패해 탈퇴가
	// 좌초되면 살아 있는 회원의 계약이 이유 없이 voided로 남는다. ⑥(가명화)보다 앞이라
	// 여기서 실패하면 회원 문서가 멀쩡한 채 500으로 멈춰 미완료가 눈에 보이고, ⑦(UserIndex)
	// 보다 앞이라 그 재시도가 같은 토큰으로 가능하다. 각 void는 TransitionContract(CAS)라
	// 부분 성공 잔여도 해가 없다 — 재시도가 이미 voided를 스킵한다(멱등).
	voidedContracts, err := s.voidContractsForWithdrawal(ctx, p.CenterID, mem.ID)
	if err != nil {
		return res, err
	}

	// ---- 5단계: 가입 요청 파기(최상위 컬렉션, v2.26 · P53) ----
	// join_requests는 **센터 아래가 아니라 최상위**이고 member_id도 없다(uid 키) — ⑥의
	// 센터 스코프 스윕이 구조적으로 닿지 못하는 유일한 개인정보다. 그런데 담고 있는 것은
	// 신청자가 직접 적은 **이름·전화번호 원본**이라, 여기 없으면 탈퇴는 "지웠다"고 보고하면서
	// 그 둘을 남긴다(Play Data Safety의 "삭제 요청 가능" 답변이 거짓이 되는 자리).
	//
	// 자리가 왜 여기인가(P22 순서 규약 그대로): ⑥(가명화)보다 **앞**이어야 한다 — 뒤에 두면
	// 실패했을 때 회원 문서는 이미 가명화돼 재시도가 "이미 탈퇴 처리된 계정이에요"(400)로
	// 막히고, 이름·번호가 영구히 남는다. ⑦(UserIndex)보다 앞이라 그 재시도가 같은 토큰으로
	// 가능하다. 삭제는 없는 문서에도 성공이라(스토어 규약) 부분 실패 후 재시도가 멱등이다.
	joinReqs, err := s.store.DeleteJoinRequestsByUID(ctx, p.UID)
	if err != nil {
		return res, err
	}

	// ---- 6단계: 가명화 + 건강·이용 기록 파기(DB) ----
	anon := mem.Anonymized(now)
	purged, err := s.store.PurgeMemberPersonalData(ctx, p.CenterID, &anon)
	if err != nil {
		return res, err
	}
	// 파일 삭제 건수는 **메타 삭제 건수로 보고한다.** MediaPurger가 dev no-op일 수 있어
	// 그쪽 숫자를 믿으면 로컬·운영이 다른 말을 한다. 어차피 둘은 짝이다(경로가 메타에서 나온다).
	purged.BodyPhotos = len(photos)
	// 가입 요청은 스토어 밖(⑤단계)에서 지웠으므로 건수를 여기서 합류시킨다 — 응답의 purged가
	// **실제로 지운 것 전부**를 말해야 한다(PurgeCounts 주석: 세 자리가 각자 세면 화면이 거짓말을
	// 시작한다). BodyPhotos를 같은 방식으로 덮어쓰는 바로 윗줄과 같은 자리다.
	purged.JoinRequests = joinReqs

	// ---- 7단계: 로그인 매핑 제거 ----
	// 남으면 인증이 옛 member_id를 그대로 복원한다. 마지막에 두는 이유는 이것이 호출자의
	// 권한 자체를 없애기 때문이다 — 앞 단계에서 이걸 지우면 뒤 단계가 자기 권한을 잃는다.
	if err := s.store.DeleteUserIndex(ctx, p.UID); err != nil {
		return res, err
	}

	// 감사 로그: 이 사건은 되돌릴 수 없고 응답은 클라이언트로만 나간다. 파기 사실과 건수를
	// 서버 로그에 남겨야 나중에 "언제 무엇이 지워졌나"에 답할 수 있다(개인정보 파기 기록).
	// voided_contracts는 응답에 없다(retained.contracts 수가 변하지 않아 와이어 무변경) —
	// 로그가 유일한 관측 지점이다.
	log.Printf("account deleted: member=%s uid=%s purged=%+v retained=%+v cancelled_bookings=%d remaining_sessions=%d voided_contracts=%d",
		mem.ID, p.UID, purged, retained, cancelled, remaining, voidedContracts)

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

// deleteUnlinkedAccount — 회원 레코드가 **없는** 계정의 탈퇴(v2.27). DeleteMyAccount의 축소판.
//
// 어느 단계가 살아남는지는 "회원 레코드에 의존하는가"로 갈렸다. 전체 7단계를 그 기준으로 훑으면:
//
//	⓪ 사진 목록·보존 건수 세기   member_id 스코프 조회 → **없다**(셀 것이 없다)
//	① 체형사진 원본 파일 파기    ⓪의 경로 목록이 입력 → **없다**
//	② Firebase 계정 삭제         uid만 필요 → **남는다.** 계정 안의 전화번호까지 파기된다
//	③ 미래 예약 무차감 취소      member_id 스코프 → **없다**(예약을 가질 수 없다)
//	④ 미서명 계약 종결           member_id 스코프 → **없다**
//	⑤ 가입 요청 파기             **uid 키다** → **남는다.** 이 경로의 존재 이유 그 자체다
//	⑥ 가명화 + 건강기록 파기     회원 문서가 대상 → **없다**
//	⑦ UserIndex 제거             uid 키 → **남는다.** 인덱스가 있을 수도(대기실 상태로 심긴
//	                             경우) 없을 수도 있는데, 이 동사는 없는 uid도 성공이라
//	                             (스토어 규약) 두 경우가 같은 코드를 탄다
//
// 남은 셋의 **순서는 전체 흐름 그대로**다(P22 순서 규약): 외부(②)가 DB(⑤·⑦)보다 앞이라
// 실패해도 같은 ID 토큰으로 재시도가 되고, ⑦이 마지막이라 앞 단계가 자기 권한을 잃지 않는다.
//
// 응답의 모양은 회원 경로와 **같은 타입**이다. 숫자가 전부 0이어도 필드를 빼지 않는다 —
// 앱의 완료 화면은 서버가 준 숫자만 옮기는 장치이고(RetainedCounts 주석), 계정 종류에 따라
// 키가 달라지면 그 화면이 분기를 갖게 된다. member_id는 빈 문자열이다(가리킬 회원이 없다).
func (s *Service) deleteUnlinkedAccount(ctx context.Context, p Principal) (AccountDeletionResult, error) {
	var res AccountDeletionResult
	now := time.Now().UTC()

	// ---- ②단계: Firebase 계정(외부) ----
	if err := s.users.DeleteUser(ctx, p.UID); err != nil {
		return res, err
	}
	// ---- ⑤단계: 가입 요청 파기(이름·전화번호 원본) ----
	joinReqs, err := s.store.DeleteJoinRequestsByUID(ctx, p.UID)
	if err != nil {
		return res, err
	}
	// ---- ⑦단계: 로그인 매핑 제거 ----
	if err := s.store.DeleteUserIndex(ctx, p.UID); err != nil {
		return res, err
	}

	// 회원 경로와 같은 감사 로그(member는 빈 값). 이 사건도 되돌릴 수 없고, "언제 무엇이
	// 지워졌나"에 답해야 하는 것은 대기실 계정이라고 달라지지 않는다.
	log.Printf("account deleted (unlinked): member= uid=%s purged=%+v", p.UID, store.PurgeCounts{JoinRequests: joinReqs})

	return AccountDeletionResult{
		Deleted:     true,
		MemberID:    "",
		WithdrawnAt: now,
		Purged:      store.PurgeCounts{JoinRequests: joinReqs},
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

// errWithdrawalVoidSkip — void 스윕의 "판정만 하고 쓰지 않는다"를 나르는 내부 신호(P40).
// ContractMutator는 에러만 반환할 수 있고, 에러는 두 스토어 모두 무쓰기 롤백이다(Memory는
// 사본 폐기, Firestore는 트랜잭션 중단). 그래서 이 에러를 돌려주고 호출측이 삼키면
// RefundPass 스윕의 save=false(ContractSweepMutator)와 같은 의미가 된다 — 스킵 한 번을
// 위해 동사 계층에 변형을 늘리지 않는다. 서비스 밖으로 새면 안 되는 값이라 비공개다.
var errWithdrawalVoidSkip = errors.New("withdrawal void sweep: contract not voidable — skip")

// voidContractsForWithdrawal — 탈퇴 회원의 미서명(draft/sent) 계약을 voided로 종결한다(v2.17).
//
// 후보는 **여기서 다시 읽는다** — 0단계(retainedForMember)의 계약 스캔을 재사용하지 않는
// 이유: 그 스냅샷과 이 스윕 사이에 외부 호출 두 번(Storage·Firebase)이 있어 목록이 낡는다.
// cancelFutureBookingsForWithdrawal이 예약을 직접 읽는 것과 같은 자리다. 그래도 목록 조회
// 자체는 트랜잭션 밖이므로(컬렉션 잠금 회피 — RefundPass 후보 선정과 같은 구조), 계약별
// TransitionContract가 트랜잭션 안에서 다시 읽은 상태로 재판정한다: 그 사이 서명이
// 끼어들었으면 스킵(보존)이 최종 판정이다 — signed는 성립했던 거래의 법적 기록이다(v1.5).
//
// 멱등성: 이미 voided인 계약은 사전 판정이 거르고(트랜잭션조차 열지 않는다), 경합 잔여는
// 트랜잭션 안 재판정이 거른다 — 부분 실패 후 재시도가 몇 번을 다시 돌아도 결과가 같다.
func (s *Service) voidContractsForWithdrawal(ctx context.Context, centerID, memberID string) (int, error) {
	contracts, err := s.store.ListContracts(ctx, centerID, memberID, "")
	if err != nil {
		return 0, err
	}
	n := 0
	for _, c := range contracts {
		if !domain.CanVoidContract(c.Status) {
			continue // signed(불가침)·voided(재시도 잔여) — 스냅샷 판정으로 충분한 쪽은 여기서 끝낸다
		}
		_, err := s.store.TransitionContract(ctx, centerID, c.ID,
			func(fresh *domain.Contract, _ *domain.Pass) error {
				if !domain.CanVoidContract(fresh.Status) {
					return errWithdrawalVoidSkip // 후보 선정 후 끼어든 서명 — 쓰지 않고 보존
				}
				fresh.Status = domain.ContractStatusVoided
				return nil
			})
		switch {
		case err == nil:
			n++
		case errors.Is(err, errWithdrawalVoidSkip):
			// 보존이 최종 판정 — 탈퇴는 계속 진행한다(RefundPass 스윕의 스킵과 같은 취급).
		default:
			// ErrNotFound 포함 — 계약은 삭제되지 않는 문서라(PurgeMemberPersonalData 비접촉)
			// 실제로는 일어나지 않고, 조용한 스킵보다 표면화를 고른다(스토어 인터페이스 규약).
			return n, err
		}
	}
	return n, nil
}
