package api

// 전자계약 전이 테스트(P37, 계약 v2.15). P36 감사 M1: s.SendContract·s.CreateContract를 부르는
// 서비스 테스트가 0건이었다 — draft→sent 최초 발송, first_sent_at 보존(v1.5), signed 재발송
// 400(v1.4.1), 권한 경계(member 403·미담당 trainer 403), 환불 패스 가드 400, 패스당 유효 계약
// 1건이 전부 미검증. 여기에 고정한다.
//
// 경합 2종(재발송 vs 서명, 환불 무효화 vs 서명)은 hookstore의 래치로 **결정적으로** 재현한다
// (service_atomicity_test.go와 같은 수법 — 첫 쓰기 직전에 창을 열고 상대를 통째로 실행).
// 트랜잭션 밖 스냅샷 판정(옛 read-modify-write)으로 되돌리는 뮤테이션은 이 파일의 래치
// 테스트에서 걸린다: 래치가 UpdateContract(옛 쓰기)에도 잡히도록 집합에 들어 있다.

import (
	"context"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// seedMemberOnly — 패스 없는 회원 1명(담당 t1). 수동 계약(draft) 경로는 "계약 없는 패스"가
// 전제인데 서비스 CreatePass는 발급과 동시에 sent 계약을 만들므로(v1.1 확정 플로우), 패스는
// seedBarePass(스토어 직행)로 따로 심는다.
func seedMemberOnly(t *testing.T, s *Service, name, phone string) *domain.Member {
	t.Helper()
	seedTrainerRecord(t, s, "t1", "정혜린")
	mem, err := s.CreateMember(context.Background(), ownerP(), &domain.Member{
		Name: name, Phone: phone, TrainerID: "t1", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatalf("CreateMember: %v", err)
	}
	return mem
}

// seedBarePass — 자동 계약 없이 패스만 심는다(스토어 직행 — 시딩 전용 CreatePass).
// status를 받는 이유: 환불 패스 가드 테스트가 "refunded 패스 + 살아있는 sent 계약"이라는
// 잔존 데이터 상태(레거시·경합 잔여분)를 직접 구성해야 해서다.
func seedBarePass(t *testing.T, s *Service, memberID, status string) *domain.Pass {
	t.Helper()
	kst := time.Now().In(domain.KST)
	p := &domain.Pass{
		MemberID: memberID, TrainerID: "t1", Product: "PT 10회", PaidAmount: 500_000,
		TotalSessions: 10, Remaining: 10,
		ValidFrom:  kst.AddDate(0, 0, -1).Format("2006-01-02"),
		ValidUntil: kst.AddDate(0, 0, 90).Format("2006-01-02"),
		Status:     status, Holds: []domain.Hold{},
	}
	if _, err := s.store.CreatePass(context.Background(), testCenter, p); err != nil {
		t.Fatalf("CreatePass(스토어): %v", err)
	}
	return p
}

// M1: 수동 생성은 draft(요율 스냅샷 포함)로 시작하고, 최초 발송이 sent_at·first_sent_at을
// 함께 찍으며, 재발송은 sent_at만 갱신하고 **first_sent_at은 보존**한다(v1.5 — 최초 고지 증적).
func TestSendContractFirstAndResendKeepsFirstSentAt(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedMemberOnly(t, s, "김민지", "010-1234-5678")
	pass := seedBarePass(t, s, mem.ID, domain.PassStatusActive)

	c, err := s.CreateContract(ctx, ownerP(), ContractCreateRequest{MemberID: mem.ID, PassID: pass.ID})
	if err != nil {
		t.Fatalf("CreateContract: %v", err)
	}
	if c.Status != domain.ContractStatusDraft {
		t.Fatalf("생성 status = %s, want draft", c.Status)
	}
	if c.PenaltyRate == nil {
		t.Error("penalty_rate 스냅샷이 없다(v1.5 — 레거시 nil과 구분 불가)")
	}
	if c.SentAt != nil || c.FirstSentAt != nil {
		t.Errorf("draft에 발송 시각이 미리 찍혔다: sent_at=%v first_sent_at=%v", c.SentAt, c.FirstSentAt)
	}

	sent, err := s.SendContract(ctx, ownerP(), c.ID)
	if err != nil {
		t.Fatalf("최초 발송: %v", err)
	}
	if sent.Status != domain.ContractStatusSent || sent.SentAt == nil || sent.FirstSentAt == nil {
		t.Fatalf("최초 발송 = %s(sent_at=%v, first_sent_at=%v), want sent + 두 시각", sent.Status, sent.SentAt, sent.FirstSentAt)
	}
	first := *sent.FirstSentAt

	time.Sleep(2 * time.Millisecond) // 재발송 시각이 같으면 "보존"과 "덮어씀"이 구분되지 않는다
	resent, err := s.SendContract(ctx, ownerP(), c.ID)
	if err != nil {
		t.Fatalf("재발송: %v", err)
	}
	if resent.Status != domain.ContractStatusSent {
		t.Errorf("재발송 후 status = %s, want sent 유지", resent.Status)
	}
	if resent.FirstSentAt == nil || !resent.FirstSentAt.Equal(first) {
		t.Errorf("재발송이 first_sent_at을 덮었다: %v → %v — 최초 고지 증적 소실(v1.5)", first, resent.FirstSentAt)
	}
	if resent.SentAt == nil || !resent.SentAt.After(first) {
		t.Errorf("재발송 sent_at이 갱신되지 않았다: %v(최초 %v)", resent.SentAt, first)
	}
	// 저장본도 같은 말을 해야 한다(응답만 맞고 저장이 틀리면 다음 조회가 다른 답을 낸다).
	saved, err := s.store.GetContract(ctx, testCenter, c.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.FirstSentAt == nil || !saved.FirstSentAt.Equal(first) || saved.Status != domain.ContractStatusSent {
		t.Errorf("저장본 = %s(first_sent_at=%v), want sent(first_sent_at=%v)", saved.Status, saved.FirstSentAt, first)
	}
}

// M1: signed 재발송은 400(v1.4.1 계약)이고 서명 증적은 그대로여야 한다.
func TestSendContractSignedIsRejected(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 10) // 자동 sent 계약
	cs, err := s.ListContracts(ctx, ownerP(), mem.ID, "")
	if err != nil || len(cs) != 1 {
		t.Fatalf("계약 목록: %v %d건", err, len(cs))
	}
	cid := cs[0].ID
	if _, err := s.SignContract(ctx, memberP(mem.ID), cid, "1.2.3.4", nil); err != nil {
		t.Fatalf("서명: %v", err)
	}

	_, err = s.SendContract(ctx, ownerP(), cid)
	if !errors.Is(err, errBadRequest) || !errors.Is(err, domain.ErrInvalidContractTransition) {
		t.Fatalf("signed 재발송 = %v, want 400 전이 위반(v1.4.1)", err)
	}
	saved, err := s.store.GetContract(ctx, testCenter, cid)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusSigned || saved.SignedAt == nil || saved.SignerIP != "1.2.3.4" {
		t.Errorf("거부된 재발송이 저장본을 건드렸다: %s(signed_at=%v, ip=%q)", saved.Status, saved.SignedAt, saved.SignerIP)
	}
}

// M1: 발송 권한 — member는 403, 미담당 trainer는 403, 담당 trainer는 재발송 가능.
func TestSendContractScope(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, _ := seedMemberWithPass(t, s, 10) // 담당 t1의 sent 계약
	cs, err := s.ListContracts(ctx, ownerP(), mem.ID, "")
	if err != nil || len(cs) != 1 {
		t.Fatalf("계약 목록: %v %d건", err, len(cs))
	}
	cid := cs[0].ID

	if _, err := s.SendContract(ctx, memberP(mem.ID), cid); !errors.Is(err, ErrForbidden) {
		t.Errorf("member 발송 = %v, want ErrForbidden(서명 요청은 스태프의 일)", err)
	}
	seedTrainerRecord(t, s, "t2", "박서준")
	t2 := Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}
	if _, err := s.SendContract(ctx, t2, cid); !errors.Is(err, ErrForbidden) {
		t.Errorf("미담당 trainer 발송 = %v, want ErrForbidden", err)
	}
	if _, err := s.SendContract(ctx, trainerP(), cid); err != nil {
		t.Errorf("담당 trainer 재발송 = %v, want 성공", err)
	}
}

// M1: 환불 패스 가드 — refunded 패스에 살아남은 sent 계약(레거시·경합 잔존분)은 발송도 서명도
// 400. 정상 환불 흐름에선 v2.15부터 무효화가 마감과 한 트랜잭션이라 이 상태 자체가 안 생기지만,
// 가드는 그 이전에 쌓인 데이터와 후보 선정을 비켜간 계약(수동 생성 경합)의 마지막 방어선이다.
func TestSendAndSignContractRefundedPassGuard(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedMemberOnly(t, s, "김민지", "010-1234-5678")
	pass := seedBarePass(t, s, mem.ID, domain.PassStatusRefunded)
	c := &domain.Contract{MemberID: mem.ID, PassID: pass.ID, Status: domain.ContractStatusSent}
	cid, err := s.store.CreateContract(ctx, testCenter, c)
	if err != nil {
		t.Fatal(err)
	}

	_, err = s.SendContract(ctx, ownerP(), cid)
	if !errors.Is(err, errBadRequest) || !strings.Contains(err.Error(), "발송할 수 없어요") {
		t.Errorf("환불 패스 발송 = %v, want 400 '환불 처리된 거래의 계약은 발송할 수 없어요'", err)
	}
	_, err = s.SignContract(ctx, memberP(mem.ID), cid, "1.2.3.4", nil)
	if !errors.Is(err, errBadRequest) || !strings.Contains(err.Error(), "서명할 수 없어요") {
		t.Errorf("환불 패스 서명 = %v, want 400 '환불 처리된 거래의 계약은 서명할 수 없어요'", err)
	}
	saved, err := s.store.GetContract(ctx, testCenter, cid)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusSent || saved.SignedAt != nil {
		t.Errorf("거부된 전이가 저장본을 건드렸다: %s(signed_at=%v)", saved.Status, saved.SignedAt)
	}
}

// M1: 패스당 유효(비voided) 계약 1건(v1.5) — 중복 생성 400, voided 잔존 계약은 분모가 아니다.
func TestCreateContractOnePerPass(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 10) // 자동 sent 계약 1건

	_, err := s.CreateContract(ctx, ownerP(), ContractCreateRequest{MemberID: mem.ID, PassID: pass.ID})
	if !errors.Is(err, errBadRequest) || !strings.Contains(err.Error(), "이미 계약이 있어요") {
		t.Fatalf("중복 생성 = %v, want 400 '이 회원권에는 이미 계약이 있어요'", err)
	}

	// voided 잔존 계약만 있는 패스에는 새로 만들 수 있어야 한다(환불→재발급 아님, 무효화만 된 케이스).
	pass2 := seedBarePass(t, s, mem.ID, domain.PassStatusActive)
	if _, err := s.store.CreateContract(ctx, testCenter, &domain.Contract{
		MemberID: mem.ID, PassID: pass2.ID, Status: domain.ContractStatusVoided}); err != nil {
		t.Fatal(err)
	}
	c2, err := s.CreateContract(ctx, ownerP(), ContractCreateRequest{MemberID: mem.ID, PassID: pass2.ID})
	if err != nil {
		t.Fatalf("voided만 있는 패스에 생성 = %v, want 성공(voided는 유효 계약이 아니다)", err)
	}
	if c2.Status != domain.ContractStatusDraft {
		t.Errorf("생성 status = %s, want draft", c2.Status)
	}
}

// M1: 생성 검증 — member 403, 소유 불일치 400, 환불 패스 400, 미담당 trainer 403.
func TestCreateContractScopeAndValidation(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem := seedMemberOnly(t, s, "김민지", "010-1234-5678")
	pass := seedBarePass(t, s, mem.ID, domain.PassStatusActive)

	if _, err := s.CreateContract(ctx, memberP(mem.ID), ContractCreateRequest{MemberID: mem.ID, PassID: pass.ID}); !errors.Is(err, ErrForbidden) {
		t.Errorf("member 생성 = %v, want ErrForbidden", err)
	}
	other, err := s.CreateMember(ctx, ownerP(), &domain.Member{
		Name: "이서준", Phone: "010-1234-5678", TrainerID: "t1", Status: domain.MemberStatusActive,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateContract(ctx, ownerP(), ContractCreateRequest{MemberID: other.ID, PassID: pass.ID}); !errors.Is(err, errBadRequest) {
		t.Errorf("소유 불일치 생성 = %v, want 400", err)
	}
	refundedPass := seedBarePass(t, s, mem.ID, domain.PassStatusRefunded)
	if _, err := s.CreateContract(ctx, ownerP(), ContractCreateRequest{MemberID: mem.ID, PassID: refundedPass.ID}); !errors.Is(err, errBadRequest) {
		t.Errorf("환불 패스 생성 = %v, want 400", err)
	}
	seedTrainerRecord(t, s, "t2", "박서준")
	t2 := Principal{UID: "t2", Role: domain.RoleTrainer, CenterID: testCenter}
	if _, err := s.CreateContract(ctx, t2, ContractCreateRequest{MemberID: mem.ID, PassID: pass.ID}); !errors.Is(err, ErrForbidden) {
		t.Errorf("미담당 trainer 생성 = %v, want ErrForbidden", err)
	}
}

// 서명이 먼저 성립한 계약은 환불이 **보존**해야 한다(v1.5 "signed는 무효화 불가" — 성립했던
// 거래의 법적 기록). 무효화 스윕의 CanVoidContract 스킵이 지키는 불변식의 순차 재현.
// v2.21(P44): 자필 서명 이미지 포함으로 서명한다 — 서명 증적 보존에 signature_png·
// signature_sha256도 포함된다는 것(이미지 있는 서명이 환불에 살아남는 것)까지 함께 고정.
func TestRefundKeepsSignedContract(t *testing.T) {
	s := newTestService()
	ctx := context.Background()
	mem, pass := seedMemberWithPass(t, s, 10)
	cs, err := s.ListContracts(ctx, ownerP(), mem.ID, "")
	if err != nil || len(cs) != 1 {
		t.Fatalf("계약 목록: %v %d건", err, len(cs))
	}
	cid := cs[0].ID
	sig := signPadPNG(t, 300, 120)
	if _, err := s.SignContract(ctx, memberP(mem.ID), cid, "1.2.3.4", sig); err != nil {
		t.Fatalf("서명: %v", err)
	}
	if _, _, err := s.RefundPass(ctx, ownerP(), pass.ID, 0); err != nil {
		t.Fatalf("환불: %v", err)
	}

	saved, err := s.store.GetContract(ctx, testCenter, cid)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusSigned || saved.SignedAt == nil || saved.SignerIP != "1.2.3.4" {
		t.Fatalf("환불이 signed 계약을 건드렸다: %s(signed_at=%v, ip=%q) — 서명된 계약은 보존", saved.Status, saved.SignedAt, saved.SignerIP)
	}
	if saved.SignaturePNG != base64.StdEncoding.EncodeToString(sig) || saved.SignatureSHA256 == "" {
		t.Errorf("환불이 서명 이미지 증적을 지웠다: png_len=%d hash=%q — signed 보존은 서명 이미지 포함(P44)",
			len(saved.SignaturePNG), saved.SignatureSHA256)
	}
	savedPass, err := s.store.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if savedPass.Status != domain.PassStatusRefunded {
		t.Errorf("패스 = %s, want refunded(계약 보존은 마감 실패가 아니다)", savedPass.Status)
	}
}

// ---- 결정적 경합(P36 감사 H — 래치 재현) ----

// (a) 재발송 vs 서명: 서명이 먼저 커밋되면 재발송은 전이 위반 400이어야 하고, signed 문서
// (signed_at·signer_ip — 법적 증적)는 그대로 남아야 한다. 옛 read-modify-write는 재발송의
// 스냅샷(sent) 위에서 판정하고 문서를 통째로 Set해서, 이 순서면 signed가 sent 사본으로 덮였다.
func TestResendCannotClobberSignedContract(t *testing.T) {
	ctx := context.Background()
	s, h := newHookedService(t)
	mem, _ := seedMemberWithPass(t, s, 10)
	cs, err := s.ListContracts(ctx, ownerP(), mem.ID, "")
	if err != nil || len(cs) != 1 {
		t.Fatalf("계약 목록: %v %d건", err, len(cs))
	}
	cid := cs[0].ID
	h.reset()

	reached, release := make(chan struct{}), make(chan struct{})
	h.before = latchOnFirstWrite(reached, release)

	sendErr := make(chan error, 1)
	go func() {
		_, err := s.SendContract(ctx, ownerP(), cid)
		sendErr <- err
	}()
	<-reached // 재발송이 계약 쓰기 직전에 멈춰 있다 — 사전 읽기(스냅샷)는 이미 끝난 지점
	if _, err := s.SignContract(ctx, memberP(mem.ID), cid, "1.2.3.4", nil); err != nil {
		t.Fatalf("서명: %v", err)
	}
	close(release)
	err = <-sendErr
	h.before = nil

	if !errors.Is(err, errBadRequest) || !errors.Is(err, domain.ErrInvalidContractTransition) {
		t.Fatalf("서명 완료 후 풀려난 재발송 = %v, want 400 전이 위반", err)
	}
	saved, err := h.Store.GetContract(ctx, testCenter, cid)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusSigned || saved.SignedAt == nil || saved.SignerIP != "1.2.3.4" {
		t.Fatalf("경합 후 저장본 = %s(signed_at=%v, ip=%q) — 재발송이 서명 증적을 덮었다",
			saved.Status, saved.SignedAt, saved.SignerIP)
	}
}

// (b-1) 환불 무효화 vs 서명, 서명이 늦는 방향: 무효화(마감 트랜잭션)가 커밋된 뒤 풀려난 서명은
// voided 종단 위 전이 위반 400이어야 한다 — 해지된 거래에 사후 법적 서명이 성립하면 안 된다.
func TestSignCannotResurrectVoidedContract(t *testing.T) {
	ctx := context.Background()
	s, h := newHookedService(t)
	mem, pass := seedMemberWithPass(t, s, 10)
	cs, err := s.ListContracts(ctx, ownerP(), mem.ID, "")
	if err != nil || len(cs) != 1 {
		t.Fatalf("계약 목록: %v %d건", err, len(cs))
	}
	cid := cs[0].ID
	h.reset()

	reached, release := make(chan struct{}), make(chan struct{})
	h.before = latchOnFirstWrite(reached, release)

	signErr := make(chan error, 1)
	go func() {
		_, err := s.SignContract(ctx, memberP(mem.ID), cid, "1.2.3.4", nil)
		signErr <- err
	}()
	<-reached // 서명이 계약 쓰기 직전에 멈춰 있다 — 스냅샷은 아직 sent·active였다
	if _, _, err := s.RefundPass(ctx, ownerP(), pass.ID, 0); err != nil {
		t.Fatalf("환불: %v", err)
	}
	close(release)
	err = <-signErr
	h.before = nil

	if !errors.Is(err, errBadRequest) {
		t.Fatalf("무효화 뒤 풀려난 서명 = %v, want 400", err)
	}
	saved, err := h.Store.GetContract(ctx, testCenter, cid)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusVoided || saved.SignedAt != nil {
		t.Fatalf("경합 후 저장본 = %s(signed_at=%v), want voided 유지 — 해지된 거래에 서명이 성립했다",
			saved.Status, saved.SignedAt)
	}
}

// (b-2) 환불 무효화 vs 서명, 무효화가 늦는 방향: 후보 선정(계약 목록) 후·마감 커밋 전에
// 끼어든 서명은 트랜잭션 안 재판정(CanVoidContract)이 스킵으로 보존해야 한다. 이 재판정이
// 없으면 사전 후보 목록이 낡은 채로 signed를 voided로 덮는다 — 스윕 재검증의 존재 이유.
func TestRefundVoidSkipsContractSignedMidflight(t *testing.T) {
	ctx := context.Background()
	s, h := newHookedService(t)
	mem, pass := seedMemberWithPass(t, s, 10)
	cs, err := s.ListContracts(ctx, ownerP(), mem.ID, "")
	if err != nil || len(cs) != 1 {
		t.Fatalf("계약 목록: %v %d건", err, len(cs))
	}
	cid := cs[0].ID
	h.reset()

	reached, release := make(chan struct{}), make(chan struct{})
	h.before = latchOnFirstWrite(reached, release)

	refundErr := make(chan error, 1)
	go func() {
		_, _, err := s.RefundPass(ctx, ownerP(), pass.ID, 0)
		refundErr <- err
	}()
	<-reached // 환불이 후보 선정(sent로 목록에 담음)을 끝내고 마감 쓰기 직전에 멈춰 있다
	if _, err := s.SignContract(ctx, memberP(mem.ID), cid, "1.2.3.4", nil); err != nil {
		t.Fatalf("서명: %v", err)
	}
	close(release)
	if err := <-refundErr; err != nil {
		t.Fatalf("환불: %v", err)
	}
	h.before = nil

	saved, err := h.Store.GetContract(ctx, testCenter, cid)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Status != domain.ContractStatusSigned || saved.SignedAt == nil || saved.SignerIP != "1.2.3.4" {
		t.Fatalf("후보 선정 뒤 끼어든 서명이 무효화됐다: %s(signed_at=%v, ip=%q) — signed는 보존(v1.5)",
			saved.Status, saved.SignedAt, saved.SignerIP)
	}
	// 계약 보존은 스킵 판정이지 환불의 실패가 아니다 — 마감 자체는 성립해야 한다.
	savedPass, err := h.Store.GetPass(ctx, testCenter, pass.ID)
	if err != nil {
		t.Fatal(err)
	}
	if savedPass.Status != domain.PassStatusRefunded {
		t.Errorf("경합 후 패스 = %s, want refunded", savedPass.Status)
	}
}
