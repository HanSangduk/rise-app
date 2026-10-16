// Package store는 데이터 substrate 추상화다. Store 인터페이스 뒤에 Firestore(실연동, 설계03 §11)와
// Memory(개발·테스트)를 스왑한다. 도메인 타입만 다룬다(SDK 모름) → 클린 아키텍처 경계 유지.
package store

import (
	"context"
	"time"

	"github.com/ramsang/rise-backend/internal/domain"
)

// UserIndex — uid → 센터/역할/회원 매핑(내부 전용, API계약 엔티티가 아니다). 인증 미들웨어가
// Firebase ID 토큰(또는 dev 헤더)의 uid만으로 role·center_id·member_id를 복원하는 데 쓴다.
//
// v1 한계(설계03 §6 멀티센터와의 차이, README 갭 참고): 회원의 memberships[]는 여러 센터를
// 지원하도록 설계돼 있으나, 이 인덱스는 uid당 최신 1건만 유지한다 — 실사용 센터가 하나뿐인
// 라이즈 컨디셔닝 v1에는 충분하고, 멀티센터 전환 시 슬라이스로 확장하면 된다.
type UserIndex struct {
	UID      string `json:"uid"`
	Role     string `json:"role"` // owner|trainer|member
	CenterID string `json:"center_id"`
	MemberID string `json:"member_id,omitempty"` // role=member일 때만
}

// JoinRequest — 가입 매칭 실패 시 폴백 요청(설계03 P48 플로우③).
type JoinRequest struct {
	ID        string    `json:"id"`
	CenterID  string    `json:"center_id"`
	UID       string    `json:"uid"`
	Name      string    `json:"name"`
	Phone     string    `json:"phone"`
	Status    string    `json:"status"` // pending|approved|rejected
	CreatedAt time.Time `json:"created_at"`
}

// JoinRequest.Status 값.
const (
	JoinPending  = "pending"
	JoinApproved = "approved"
	JoinRejected = "rejected"
)

// ConsultRequest — 회원발 재등록/상담 요청(계약 v2.20, P42). JoinRequest와 같은 "요청 큐"
// 패턴이지만 이미 센터에 귀속된 회원이 보내므로 센터 스코프 컬렉션이다(최상위 아님).
//
// 앱의 재등록 데드엔드("센터에 문의해주세요")를 데스크로 잇는 손잡이 — 결제·발급은 여기서
// 일어나지 않는다. 데스크가 상담 후 기존 수기 플로우(회원권 발급+결제 기록)로 마감하고
// done 처리한다.
type ConsultRequest struct {
	ID       string `json:"id"`
	MemberID string `json:"member_id"`
	Kind     string `json:"kind"` // renewal(재등록)|consult(상담)
	// Note — 회원이 남긴 한 줄(선택). 길이 상한은 서비스가 검증한다.
	Note      string    `json:"note,omitempty"`
	Status    string    `json:"status"` // pending|done
	CreatedAt time.Time `json:"created_at"`
}

// ConsultRequest.Kind / .Status 값.
const (
	ConsultKindRenewal = "renewal"
	ConsultKindConsult = "consult"

	ConsultPending = "pending"
	ConsultDone    = "done"
)

// CheckinRecord — 체크인 감사 로그(내부 전용, API계약 엔티티가 아니다). Member.LastVisitAt
// 갱신(설계03 §11 "체크인 시 갱신")의 근거를 남기기 위한 최소 기록.
type CheckinRecord struct {
	ID        string    `json:"id"`
	CenterID  string    `json:"center_id"`
	BookingID string    `json:"booking_id"`
	MemberID  string    `json:"member_id"`
	Source    string    `json:"source"` // tap|self_qr
	At        time.Time `json:"at"`
}

// PassMutator — UpdatePassWithLedger가 **트랜잭션(또는 Memory의 전역 락) 안에서** 호출하는
// 변경 함수. p는 방금 읽은 최신 패스(여기에 직접 쓴다), entries는 그 패스의 원장 전체다
// (잔여 재계산·유예 판정처럼 "원장이 진실"인 판단을 트랜잭션 안에서 내리기 위해 함께 준다).
//
// 반환한 *domain.Ledger가 nil이 아니면 패스 갱신과 **같은 트랜잭션**에 적재된다.
// 반환 에러는 트랜잭션을 롤백시키고 그대로 호출측으로 올라간다 — 상태 재검증 실패
// (이미 환불됨 등)를 여기서 돌려주면 그것이 경합의 최종 판정이 된다.
//
// 제약은 Store.UpdatePassWithLedger 주석 참고(순수해야 하고, Store를 다시 부르면 안 된다).
type PassMutator func(p *domain.Pass, entries []domain.Ledger) (*domain.Ledger, error)

// ContractMutator — TransitionContract가 **트랜잭션(또는 Memory의 전역 락) 안에서** 호출하는
// 검증+변경 함수(P37, 계약 v2.15). c는 방금 읽은 최신 계약(여기에 직접 쓴다), pass는 그 계약의
// 패스 — "환불된 거래인가" 같은 판정을 트랜잭션 안에서 내리기 위해 함께 준다. 패스 문서가
// 없으면(계약만 남은 레거시·픽스처) nil이다. pass는 **판정 전용**이다 — 여기 쓴 변경은
// 저장되지 않는다(이 동사는 계약 문서 하나만 쓴다).
//
// 반환 에러는 트랜잭션을 롤백시키고 그대로 호출측으로 올라간다 — 전이 재검증 실패(이미 서명됨·
// 이미 무효됨 등)를 여기서 돌려주면 그것이 경합의 최종 판정이 된다.
// 제약은 PassMutator와 같다(순수해야 하고, Store를 다시 부르면 안 된다).
//
// c의 포인터 필드(SentAt·FirstSentAt·SignedAt·PenaltyRate)는 **재할당만** 하라
// (`c.SentAt = &t`). 경유 쓰기(`*c.SentAt = t`)는 금지 — Memory는 저장본의 얕은 사본 위에서
// mutate를 돌리고 에러 시 사본을 버리는 방식으로 롤백하는데, 포인터가 가리키는 값은 저장본과
// 공유라 경유 쓰기는 롤백 뒤에도 저장본에 남는다(P40 — P37 리뷰 권고 명문화).
type ContractMutator func(c *domain.Contract, pass *domain.Pass) error

// ContractSweepMutator — UpdatePassWithLedgerAndContracts가 트랜잭션 안에서 **지목된 계약마다**
// 호출하는 재판정 함수(P37, 계약 v2.15). save=false면 그 계약은 건드리지 않는다(스킵) —
// "signed는 무효화 불가"(domain.CanVoidContract) 같은 도메인 판정이, 후보 선정 이후 끼어든
// 서명에 대해서도 성립하게 하는 자리다. 에러를 반환하면 패스·원장·앞서 판정한 계약까지
// **전부** 롤백된다. 제약은 PassMutator와 같다(순수·Store 재호출 금지).
type ContractSweepMutator func(c *domain.Contract) (save bool, err error)

// PurgeCounts — 회원탈퇴(v2.11)로 **실제 삭제된** 문서 수. 응답·감사 로그·앱 완료 화면이
// 전부 이 값을 쓴다 — 세 자리가 각자 세면 어긋나고, 그 순간 "무엇이 지워졌는지"를 말하는
// 화면이 거짓말을 하기 시작한다.
type PurgeCounts struct {
	BodyPhotos  int `json:"body_photos"`
	Inbody      int `json:"inbody"`
	WorkoutLogs int `json:"workout_logs"`
	HwChecks    int `json:"hw_checks"`
	Checkins    int `json:"checkins"`
	Recurrings  int `json:"recurrings"`
	// ConsultRequests — 재등록/상담 요청(v2.20, P42). 회원이 남긴 한 줄 메모(Note)가 자유
	// 서술이라 무엇이 적혔는지 서버가 알 수 없다 — 거래 기록이 아니므로 파기 대상이다
	// (PurgeMemberPersonalData의 센터 스코프 스윕이 함께 지운다, P53).
	ConsultRequests int `json:"consult_requests"`
	// JoinRequests — 가입 요청(P48③). **이름·전화번호 원본**을 품는 최상위 컬렉션이라
	// 센터 스코프 스윕이 닿지 못한다 — DeleteJoinRequestsByUID가 따로 지우고 호출측이
	// 이 칸에 옮겨 담는다(api.Service.DeleteMyAccount ⑤단계, P53).
	JoinRequests int `json:"join_requests"`
}

// Store — 전체 데이터 접근. Firestore(실연동)/Memory(개발) 구현.
// 대부분의 메서드가 centerID를 첫 인자로 받는다 — Firestore 문서 레이아웃은
// centers/{centerID}/...(설계03 §11)이고, Memory는 같은 경계를 합성 키로 흉내낸다.
type Store interface {
	// ---- 인증 인덱스 ----
	GetUserIndex(ctx context.Context, uid string) (*UserIndex, error)
	SaveUserIndex(ctx context.Context, u *UserIndex) error
	// DeleteUserIndex — uid → 센터/역할/회원 매핑을 지운다(회원탈퇴, v2.11). 이 문서가 남으면
	// 같은 uid로 다시 로그인했을 때 인증이 예전 member_id를 그대로 복원해 **탈퇴가 무효화된다**.
	//
	// **없는 uid도 성공이다**(DeleteInbody·DeleteRecurring의 "없으면 404"와 의도적으로 다르다):
	// 탈퇴 절차의 마지막 단계라 재시도가 404에 막히면 인덱스가 영구히 남는다. 사용자가 지운
	// 대상을 확인해야 하는 자리가 아니라 내부 뒷정리다.
	DeleteUserIndex(ctx context.Context, uid string) error

	// ---- 가입 매칭(P48) ----
	// FindMemberByPhone — 정규화 번호(domain.NormalizePhone)가 일치하는 회원 1건.
	// 같은 번호를 쓰는 회원이 여럿일 때(부모 번호로 자녀 둘 등록) **결정적**이어야 한다 —
	// 미연결(app_linked=false) 우선, 그다음 ID 오름차순(betterPhoneMatch). 두 구현이 같은
	// 규칙을 쓴다.
	FindMemberByPhone(ctx context.Context, centerID, phone string) (*domain.Member, error)
	CreateJoinRequest(ctx context.Context, jr *JoinRequest) (string, error)
	GetJoinRequest(ctx context.Context, id string) (*JoinRequest, error)
	UpdateJoinRequest(ctx context.Context, jr *JoinRequest) error
	// ListJoinRequests — 센터의 가입 요청 전체(GET /v1/join/requests, 어드민 가정 승인, v1.1 정합 패치).
	ListJoinRequests(ctx context.Context, centerID string) ([]JoinRequest, error)
	// ListJoinRequestsByUID — 그 uid가 낸 가입 요청 전부(센터 무관, 최신 먼저, v2.34 · P69).
	//
	// 왜 센터가 아니라 uid인가: 미연결 uid의 Principal.CenterID는 **기본 센터 폴백**이라 진실이
	// 아니다(v2.32). v2.33이 가입 요청에 센터 선택을 열자 2호점에 보낸 요청이 `GET /v1/me`
	// (기본 센터 큐만 훑던 latestJoinRequest)에 **아예 안 실렸다** — 앱은 "요청 없음"으로
	// 읽고 사용자는 재요청 → 409 루프에 갇혔다. 신청자의 대기 상태를 묻는 동사는 그 사람의
	// uid로 물어야 한다. 비용도 낫다: 센터 큐 전체(N, 상태 무관, 운영 기간에 비례해 자란다)
	// 대신 그 사람의 요청(k, 보통 1~2)만 읽는다.
	//
	// 빈 uid는 **빈 목록**이다(DeleteJoinRequestsByUID와 같은 가드 — `uid == ""` 쿼리는
	// uid가 빈 레거시 문서에 실제로 매칭된다). Firestore는 단일 필드 쿼리라 복합 인덱스가
	// 필요 없다(정렬은 메모리에서).
	ListJoinRequestsByUID(ctx context.Context, uid string) ([]JoinRequest, error)
	// DeleteJoinRequestsByUID — 그 uid가 낸 가입 요청을 **전부** 지우고 건수를 돌려준다
	// (회원탈퇴, P53). PurgeMemberPersonalData가 못 하는 일이라 별도 동사다:
	//
	//	① join_requests는 **최상위 컬렉션**이다(승인 전엔 센터 귀속 전 — Firestore 레이아웃
	//	   주석 참고). centers/{centerID}/… 아래를 훑는 그 스윕은 여기 닿지 못한다.
	//	② 이 문서엔 **member_id가 아예 없다**(승인돼야 회원이 생긴다). 키는 uid다 —
	//	   member_id로 좁히는 deleteWhereMember 계열을 재사용할 수 없다.
	//
	// 왜 지우는가: 신청자가 직접 적은 **이름·전화번호 원본**을 품는다. 처리 목적(센터 매칭·
	// 승인)은 계정이 사라진 순간 영구히 달성 불가능해지고, 계약·결제 기록이 아니라
	// 개인정보보호법 §21① 단서의 예외를 타지 못한다. 남기면 실해도 있다: JoinApprove가
	// jr.Name/jr.Phone을 그대로 새 회원 레코드로 굳히므로, pending 요청 하나가 파기한
	// 이름·번호를 되살리는 **승인 한 번짜리 경로**로 남는다(Member.Anonymized가 번호를
	// 비우는 이유와 같은 자리 — 그 방어선을 컬렉션 하나 옆에서 우회한다).
	//
	// **센터로 좁히지 않는다**(uid 전체). 다른 센터 큐에 남은 요청도 같은 사람의 이름·번호이고,
	// 그 계정은 이제 존재하지 않아 어느 센터도 승인할 수 없다 — 좁히면 승인 불가능한 PII만
	// 남는다.
	//
	// **없는 uid도 성공이다**(0건 반환 — DeleteUserIndex와 같은 규약): 탈퇴 재시도가 여기서
	// 막히면 이름·번호가 영구히 남는다. 그래서 이 동사는 몇 번을 돌려도 결과가 같다(멱등).
	DeleteJoinRequestsByUID(ctx context.Context, uid string) (int, error)

	// ---- 재등록/상담 요청(계약 v2.20, P42) ----
	// ListConsultRequests — memberID가 빈 값이면 센터 전체. 정렬은 CreatedAt 오름차순 →
	// ID(동률 안정) — 데스크 큐는 오래 기다린 요청이 위로 온다.
	CreateConsultRequest(ctx context.Context, centerID string, cr *ConsultRequest) (string, error)
	GetConsultRequest(ctx context.Context, centerID, id string) (*ConsultRequest, error)
	// UpdateConsultRequest — 없는 ID면 ErrNotFound(UpdateJoinRequest와 같은 존재 확인 선행).
	UpdateConsultRequest(ctx context.Context, centerID string, cr *ConsultRequest) error
	ListConsultRequests(ctx context.Context, centerID, memberID string) ([]ConsultRequest, error)

	// ---- 회원 ----
	ListMembers(ctx context.Context, centerID, trainerID, q string) ([]domain.Member, error)
	GetMember(ctx context.Context, centerID, id string) (*domain.Member, error)
	// SaveMember — id가 비어 있으면 새로 발급(POST), 있으면 upsert(PUT).
	SaveMember(ctx context.Context, centerID string, m *domain.Member) (string, error)
	// PurgeMemberPersonalData — 회원탈퇴의 **집행** 동사(v2.11). 무엇을 지우고 무엇을 남길지는
	// 도메인이 정하고(domain.Member.Anonymized), 여기서는 그 결정을 실행만 한다.
	//
	// 하는 일 두 가지:
	//   ① anonymized.ID 회원의 **건강·이용 기록**을 지운다 — 체형사진 메타·인바디·수업기록·
	//      홈워크 체크·체크인·고정 스케줄·재등록/상담 요청. 전자상거래법이 보존하라는
	//      "계약·결제 기록"이 아니므로 개인정보보호법 §21① 단서의 예외를 타지 못한다
	//      = 파기 대상이다.
	//   ② 가명화된 회원 문서를 **마지막에** 저장한다.
	//
	// 스윕의 사정거리는 **centers/{centerID}/… 아래 + member_id 필드를 가진 컬렉션**까지다.
	// 둘 중 하나라도 어긋나는 개인정보는 이 동사로 지울 수 없다 — 최상위 컬렉션인
	// join_requests가 그 경우이고(uid 키), DeleteJoinRequestsByUID가 따로 맡는다(P53).
	// **새 컬렉션을 만들 때 이 문단을 다시 읽어라**: 회원의 무언가를 담는데 여기 목록에도
	// 그쪽 동사에도 없으면, 탈퇴는 성공을 보고하면서 그것만 남긴다(P53이 실제로 겪은 결함).
	//
	// 순서가 규약이다. 기록을 먼저 지우고 회원 문서를 나중에 쓰면, 중간에 실패했을 때 회원
	// 문서에 이름·번호가 그대로 남아 **미완료가 눈에 보이고** 재시도가 깨끗하게 다시 돈다.
	// 반대 순서였다면 "탈퇴한 것처럼 보이는데 민감정보는 남아 있는" 보이지 않는 상태가 된다.
	//
	// 원장(Ledger)·Pass·Payment·Contract·Booking은 **건드리지 않는다** — append-only 불변식과
	// 5년 보존 의무가 함께 걸린 자리다(계약 v2.11). 미래 예약 정리는 슬롯 사본까지 함께
	// 비워야 해서 호출측이 CancelAtomic으로 **먼저** 처리한다.
	//
	// 체형사진의 **실제 파일**(Cloud Storage)은 스토어 밖이다 — 호출측이 메타를 지우기 전에
	// 파일부터 지운다(api.MediaPurger). 반대로 하면 경로를 아는 유일한 문서가 먼저 사라져
	// 원본이 버킷에 영영 남는다.
	PurgeMemberPersonalData(ctx context.Context, centerID string, anonymized *domain.Member) (PurgeCounts, error)

	// ---- 원장(append-only, P3) ----
	AppendLedger(ctx context.Context, centerID string, e *domain.Ledger) (string, error)
	// ListLedger — passID가 빈 값이면 회원의 전체 패스를 아우른다.
	ListLedger(ctx context.Context, centerID, memberID, passID string) ([]domain.Ledger, error)

	// ---- 회원권 ----
	// CreatePass — 패스 문서 하나만 만든다. **발급 경로에서는 쓰지 않는다**(IssuePass를 쓴다) —
	// 시딩·마이그레이션처럼 원장/계약을 호출측이 따로 책임지는 자리 전용.
	CreatePass(ctx context.Context, centerID string, p *domain.Pass) (string, error)
	GetPass(ctx context.Context, centerID, id string) (*domain.Pass, error)
	// UpdatePass — 패스 문서 통째 교체. **돈·세션이 움직이는 경로에서는 쓰지 않는다**
	// (UpdatePassWithLedger를 쓴다): read-modify-write라 동시 갱신이 서로를 조용히 덮고,
	// 원장 적재와 쪼개지면 찢어진 상태가 남는다(P13 C2·H2 실측). 없는 ID면 ErrNotFound.
	UpdatePass(ctx context.Context, centerID string, p *domain.Pass) error
	// IssuePass — 발급 3단(패스 문서 + 원장 issue + 계약 자동생성)을 **한 트랜잭션**으로 반영한다.
	//
	// 쪼개져 있을 때 실측된 사고(P13 C3): 계약 생성만 실패하는 상황에서 발급 3회 시도가 HTTP 500
	// × 3을 돌려주면서 실제로는 패스 3개(각 20회)와 원장 issue 3건을 남겼다 — "실패" 화면 뒤에서
	// 60회가 지급됐고, 패스 삭제 라우트가 없어 되돌릴 방법도 없다.
	//
	// entry/contract는 nil 가능(원장만·패스만). 성공 시 p.ID·entry.ID·contract.ID가 채워지고
	// entry.PassID/contract.PassID는 스토어가 새 패스 ID로 덮어쓴다(호출측 순서 실수 차단).
	IssuePass(ctx context.Context, centerID string, p *domain.Pass, entry *domain.Ledger, contract *domain.Contract) error
	// UpdatePassWithLedger — 패스 갱신 + 원장 적재를 **한 트랜잭션**으로 묶는다(환불·홀딩·재개·이관).
	// SetBookingStatusWithLedger가 예약에 대해 하는 일을 패스에 대해 한다.
	//
	// mutate는 트랜잭션 안에서 읽은 **최신** 패스와 그 패스의 원장 전체를 받는다 — 서비스
	// 레이어의 사전 가드(권한·상태)는 여기서 한 번 더 재검증돼야 경합 창이 실제로 닫힌다
	// (BookAtomic/CancelAtomic이 domain.CanBook·ErrStateConflict를 트랜잭션 안에서 다시 보는 것과
	// 같은 이중 방어). mutate가 에러를 반환하면 아무것도 쓰이지 않고 그 에러가 그대로 올라온다.
	//
	// mutate 계약(어기면 조용히 깨진다):
	//   ① 순수해야 한다 — Firestore 트랜잭션은 경합 시 재시도하므로 여러 번 호출될 수 있다.
	//      캡처 변수에 결과를 남기는 것은 허용되나(마지막 호출이 커밋된 호출이다) 누적은 금지.
	//   ② **Store를 다시 부르면 안 된다** — Memory는 전역 뮤텍스를 쥔 채 호출하므로 교착하고,
	//      Firestore는 트랜잭션 밖 읽기가 되어 원자성이 깨진다. 필요한 값(정책 등)은 미리 읽어
	//      클로저에 캡처한다.
	//   ③ 반환한 Ledger의 ID·PassID·At은 스토어가 채운다(호출측 값은 무시·덮어쓰기).
	// 없는 패스면 ErrNotFound.
	UpdatePassWithLedger(ctx context.Context, centerID, passID string, mutate PassMutator) (*domain.Pass, error)
	// UpdatePassWithLedgerAndContracts — UpdatePassWithLedger + **미리 지목한 계약들의 갱신**을
	// 같은 트랜잭션에 넣는다(환불 마감 전용, P37 · 계약 v2.15). 환불이 미서명 계약을 voided로
	// 돌리는 일이 종전엔 마감 **밖의** 루프였다(v2.6 남은 갭): 서명과 경합하면 "signed는 무효화
	// 불가"(v1.5) 불변식이 깨질 수 있었고, 중간 실패는 refunded 패스에 sent 계약을 영구
	// 잔존시켰다(재시도는 "이미 환불 처리된 패스예요"로 막힌다).
	//
	// 계약을 찾는 **스캔은 여전히 트랜잭션 밖이다**(호출측이 contractIDs를 미리 추린다 — 센터
	// 전체 컬렉션을 잠그지 않기 위해). 트랜잭션 안에서는 그 ID들을 점읽기로 다시 읽어 sweep이
	// **최신 상태** 위에서 재판정한다(후보 선정 후 서명이 끼어들었으면 스킵이 최종 판정이다).
	// contractIDs가 비면 UpdatePassWithLedger와 같다. 지목한 계약이 없으면 ErrNotFound —
	// 계약은 삭제되지 않는 문서라(PurgeMemberPersonalData도 비접촉) 실제로는 일어나지 않고,
	// 조용한 스킵보다 표면화를 고른다.
	UpdatePassWithLedgerAndContracts(ctx context.Context, centerID, passID string, mutate PassMutator, contractIDs []string, sweep ContractSweepMutator) (*domain.Pass, error)
	ListPassesByMember(ctx context.Context, centerID, memberID string) ([]domain.Pass, error)
	ListPasses(ctx context.Context, centerID string) ([]domain.Pass, error) // 통계 집계용 전체 조회

	// ---- 슬롯/예약(원자적, P35) ----
	GetSlot(ctx context.Context, centerID, slotKey string) (*domain.Slot, error) // 없으면 ErrNotFound
	ListSlots(ctx context.Context, centerID, date string) ([]domain.Slot, error)
	// BookAtomic — 슬롯 용량+트레이너 동시배정 규칙(domain.CanBook)을 원자적으로 강제하며 예약을
	// 생성한다. 슬롯 문서가 없으면 capacity로 새로 만든다. 위반 시 domain.ErrSlotFull/ErrTrainerBusy.
	//
	// booking.PassID가 가리키는 패스 문서가 있으면 **같은 트랜잭션 안에서** 잔여 청구권도 다시
	// 판정한다(P13 H1): `Σledger.delta − 이 패스의 confirmed 예약 수 > 0`이 아니면
	// domain.ErrNoSessionsLeft. 서비스 레이어에도 같은 검사가 있지만 그것만으로는 동시 예약
	// 2건이 같은 마지막 회차를 각자 통과한다 — 예약 규칙 중 유일하게 트랜잭션 밖에 있던 검사였다.
	// 부수효과로 pass.remaining 저장 스냅샷을 원장 합으로 맞춰 둔다(M3 드리프트 축소) —
	// 이 쓰기가 동시 예약끼리의 직렬화 지점이기도 하다(같은 패스 문서를 함께 읽고 쓴다).
	// 패스 문서가 없으면(픽스처·레거시) 검사를 건너뛴다.
	BookAtomic(ctx context.Context, centerID, slotKey string, capacity int, booking *domain.Booking) error
	GetBooking(ctx context.Context, centerID, id string) (*domain.Booking, error)
	ListBookingsByMember(ctx context.Context, centerID, memberID string) ([]domain.Booking, error)
	ListBookings(ctx context.Context, centerID string) ([]domain.Booking, error) // 통계·체크인 조회용 전체
	// CancelAtomic — 예약을 취소 처리하고 슬롯 teams에서 원자적으로 제거한다. entry가 nil이
	// 아니면 페널티 원장까지 **같은 트랜잭션**에 넣는다(컷오프 내 취소, P13 M4).
	//
	// entry를 받기 전에는 취소와 페널티 적재가 두 호출로 쪼개져 있었다: 원장 적재만 실패하면
	// 취소는 이미 확정인데 페널티가 없고, 재시도는 "confirmed 상태의 예약만 취소할 수 있어요"로
	// 막혀 페널티가 영구 소실됐다(실측). complete/noshow는 처음부터 한 트랜잭션이었다 —
	// 취소만 예외였던 자리를 맞춘다.
	CancelAtomic(ctx context.Context, centerID, bookingID string, entry *domain.Ledger) error
	// SetBookingStatusWithLedger — 예약 상태 변경 + 원장 기록을 원자적으로 함께 반영한다
	// (complete/noshow, P4·P7). entry가 nil이면 원장 기록 없이 상태만 바꾼다.
	SetBookingStatusWithLedger(ctx context.Context, centerID, bookingID, status string, entry *domain.Ledger) error
	// ReassignBookingTrainer — 예약의 담당 트레이너를 슬롯 teams 사본과 함께 원자적으로
	// 재지정한다(퇴사 이관, v2.0). 인수자가 같은 슬롯에 이미 배정돼 있으면
	// domain.ErrTrainerBusy — 트레이너 동시 1건 규칙(R2)을 이관이 우회하면 안 된다.
	// confirmed 예약만 대상(그 외 ErrStateConflict). toTrainerID=""는 미배정 회수.
	ReassignBookingTrainer(ctx context.Context, centerID, bookingID, toTrainerID string) error

	// ---- 고정 스케줄(P47) ----
	CreateRecurring(ctx context.Context, centerID string, r *domain.Recurring) (string, error)
	// UpdateRecurring — 기존 규칙 덮어쓰기(담당 이관, v2.0). ID가 없으면 ErrNotFound.
	UpdateRecurring(ctx context.Context, centerID string, r *domain.Recurring) error
	GetRecurring(ctx context.Context, centerID, id string) (*domain.Recurring, error)
	DeleteRecurring(ctx context.Context, centerID, id string) error
	ListRecurrings(ctx context.Context, centerID string) ([]domain.Recurring, error)

	// ---- Home Work(P39) ----
	CreateHomework(ctx context.Context, centerID string, hw *domain.Homework) (string, error)
	GetHomework(ctx context.Context, centerID, id string) (*domain.Homework, error)
	ListHomeworks(ctx context.Context, centerID string) ([]domain.Homework, error)
	SaveHwCheck(ctx context.Context, centerID string, c *domain.HwCheck) error
	ListHwChecksByMember(ctx context.Context, centerID, memberID string) ([]domain.HwCheck, error)
	// ListHwChecks — 센터의 HwCheck 전체(GET /v1/hw-checks?hw_id=&member=, 어드민·앱 가정 승인,
	// v1.1 정합 패치). member/hw_id 필터는 서비스 레이어에서 적용한다(ListHomeworks와 동일 패턴).
	ListHwChecks(ctx context.Context, centerID string) ([]domain.HwCheck, error)

	// ---- 직원 ----
	ListStaff(ctx context.Context, centerID string) ([]domain.Staff, error)
	GetStaff(ctx context.Context, centerID, uid string) (*domain.Staff, error)
	SaveStaff(ctx context.Context, centerID string, s *domain.Staff) error

	// ---- 결제(P19) ----
	CreatePayment(ctx context.Context, centerID string, p *domain.Payment) (string, error)
	GetPayment(ctx context.Context, centerID, id string) (*domain.Payment, error)
	UpdatePayment(ctx context.Context, centerID string, p *domain.Payment) error
	ListPayments(ctx context.Context, centerID string) ([]domain.Payment, error)
	// ListPaymentsByPass — 한 패스에 귀속된 결제만(v2.38, P74). 환불 정산·계약가 상한·계약서 조립은
	// 패스 1건의 결제만 필요한데 종전엔 센터 전체 결제를 읽고 Go에서 걸렀다 — 센터의 누적 결제
	// 수에 비례해 환불 견적 1건이 비싸지는 자리다. 정렬은 ListPayments와 같은 규칙(문서 ID).
	ListPaymentsByPass(ctx context.Context, centerID, passID string) ([]domain.Payment, error)
	// ListPaymentsByMember — 한 회원의 결제만(v2.38, P74). 앱 마이 탭이 회원마다 부르는 경로가 센터
	// 전체 결제를 읽지 않게 한다. 정렬은 ListPayments와 같은 규칙.
	ListPaymentsByMember(ctx context.Context, centerID, memberID string) ([]domain.Payment, error)

	// ---- 전자계약(Contract, v1.1 정합 패치) ----
	// CreateContract — 계약 문서 하나만 만든다. **수동 생성 경로에서는 쓰지 않는다**
	// (CreateContractGuarded를 쓴다): "패스당 유효 계약 1건" 검사가 밖에 있으면 동시 2건이
	// 각자 통과한다(P37 M2). 발급 경로는 IssuePass가 담당한다. 시딩·픽스처 전용.
	CreateContract(ctx context.Context, centerID string, c *domain.Contract) (string, error)
	// CreateContractGuarded — 같은 회원의 기존 계약 전부를 **같은 트랜잭션 안에서** 읽어 guard에
	// 넘긴 뒤 생성한다(P37 M2 · 계약 v2.15). "패스당 유효(비voided) 계약 1건" 불변식(v1.5)이
	// read-then-create였을 때는 동시 2건이 각자 통과했다 — 유효 계약이 둘이 되는 순간
	// refundBasis의 단일 스냅샷 가정(위약금율을 하나만 읽는다)이 깨진다. guard가 에러를
	// 반환하면 아무것도 만들어지지 않고 그 에러가 그대로 올라간다. guard 제약은 PassMutator와
	// 같다(순수·Store 재호출 금지).
	CreateContractGuarded(ctx context.Context, centerID string, c *domain.Contract, guard func(existing []domain.Contract) error) (string, error)
	GetContract(ctx context.Context, centerID, id string) (*domain.Contract, error)
	// UpdateContract — 계약 문서 통째 교체. **상태 전이 경로에서는 쓰지 않는다**
	// (TransitionContract를 쓴다): read-then-Set이라 재발송 vs 서명 경합이 signed 문서를 sent
	// 사본으로 덮어 signed_at·signer_ip(법적 증적)를 지운다(P36 감사 H → P37). 없는 ID면 ErrNotFound.
	UpdateContract(ctx context.Context, centerID string, c *domain.Contract) error
	// TransitionContract — 계약 상태 전이(send·sign·void)를 **한 트랜잭션**으로 반영한다
	// (P37 · 계약 v2.15). mutate는 트랜잭션 안에서 다시 읽은 **최신** 계약과 그 계약의 패스를
	// 받는다 — 서비스 레이어의 사전 가드는 스냅샷 위 판정이라, 전이 규칙(domain.
	// CanTransitionContract·CanVoidContract)과 환불 패스 가드는 여기서 재검증돼야 경합 창이
	// 실제로 닫힌다(UpdatePassWithLedger의 mutate 재검증과 같은 이중 방어). 없는 계약이면
	// ErrNotFound.
	TransitionContract(ctx context.Context, centerID, contractID string, mutate ContractMutator) (*domain.Contract, error)
	// ListContracts — member/status 모두 옵션(빈 값=필터 없음, ListMembers의 trainerID/q와 동일 패턴).
	ListContracts(ctx context.Context, centerID, memberID, status string) ([]domain.Contract, error)

	// ---- 체형사진(동의 게이트는 서비스 레이어, P8) ----
	// CreateBodyPhoto — bp.ID가 비면 스토어가 ID를 정한다. **비어 있지 않으면 그 ID로 없을 때만 생성**하고,
	// 이미 있으면 ErrAlreadyExists(P76 — 서비스가 storage_path 해시를 넘겨 메타 POST 재시도를 멱등으로 만든다).
	CreateBodyPhoto(ctx context.Context, centerID string, bp *domain.BodyPhoto) (string, error)
	ListBodyPhotos(ctx context.Context, centerID, memberID string) ([]domain.BodyPhoto, error)
	// GetBodyPhoto — 단건 조회(삭제 표시된 것도 돌려준다 — 복원·파기가 읽어야 한다).
	GetBodyPhoto(ctx context.Context, centerID, id string) (*domain.BodyPhoto, error)
	// SaveBodyPhoto — 메타 갱신(소프트 삭제 표시·복원). v2.13.
	SaveBodyPhoto(ctx context.Context, centerID string, bp *domain.BodyPhoto) error
	// DeleteBodyPhoto — **메타의 완전 파기**. Storage 오브젝트는 호출측이 먼저 지운다
	// (순서가 뒤바뀌면 오브젝트가 기록 없이 버킷에 영원히 남는다).
	DeleteBodyPhoto(ctx context.Context, centerID, id string) error
	// ListBodyPhotosPendingPurge — 센터 전체에서 유예가 지난 것들. 스케줄러가 없어
	// 조회 시점에 훑는다(api.Service.sweepBodyPhotoPurge) — limit로 한 번에 도는 양을 묶는다.
	ListBodyPhotosPendingPurge(ctx context.Context, centerID string, before time.Time, limit int) ([]domain.BodyPhoto, error)

	// ---- 인바디(동의 게이트는 서비스 레이어, P8) ----
	CreateInbody(ctx context.Context, centerID string, r *domain.Inbody) (string, error)
	// ListInbody — 최신(date) 먼저, 동률이면 문서 ID 오름차순(order.go sortInbody).
	ListInbody(ctx context.Context, centerID, memberID string) ([]domain.Inbody, error)
	// GetInbody/DeleteInbody — v2.9 정정 경로. 오입력을 되돌릴 유일한 수단이라
	// (PUT은 만들지 않았다) 없는 ID는 두 구현 모두 ErrNotFound여야 한다.
	GetInbody(ctx context.Context, centerID, id string) (*domain.Inbody, error)
	DeleteInbody(ctx context.Context, centerID, id string) error

	// ---- 수업 기록(WorkoutLog, v1.4) ----
	CreateWorkoutLog(ctx context.Context, centerID string, wl *domain.WorkoutLog) (string, error)
	// ListWorkoutLogs — memberID 빈 값이면 센터 전체(트레이너 필터는 서비스 레이어). 최신(date) 먼저.
	ListWorkoutLogs(ctx context.Context, centerID, memberID string) ([]domain.WorkoutLog, error)

	// ---- 체크인(P44) ----
	SaveCheckinRecord(ctx context.Context, centerID string, c *CheckinRecord) error

	// ---- 센터 신원(멀티센터 Phase A) ----
	//
	// GetCenter — 미등록이면 **빈 값**(ID만 채움, ErrNotFound 아님 — GetBusiness와 같은 규약:
	// 읽기가 문서를 만들지 않고, 기존 rise 센터처럼 이름 없는 센터도 정상 상태다).
	// ListCenters — `center` 신원이 등록된 센터만. GetPolicy 지연 시딩·헬스체크가 만드는
	// "정책만 있는 유령 문서"는 목록에 오르지 않는다.
	GetCenter(ctx context.Context, centerID string) (*domain.Center, error)
	SaveCenter(ctx context.Context, c *domain.Center) error
	ListCenters(ctx context.Context) ([]domain.Center, error)

	// ---- 센터 정책(설정값, P6) ----
	GetPolicy(ctx context.Context, centerID string) (*domain.Policy, error)
	SavePolicy(ctx context.Context, centerID string, p *domain.Policy) error

	// ---- 사업자 정보(법정 고지 기재사항, v2.13) ----
	// GetBusiness — 미등록이면 **빈 값**(ErrNotFound 아님). 무인증 공개 경로가 이 값을 읽으므로
	// 두 구현 모두 **읽기가 문서를 만들지 않아야 한다**(GetPolicy의 지연 시딩과 다른 규약).
	GetBusiness(ctx context.Context, centerID string) (*domain.Business, error)
	SaveBusiness(ctx context.Context, centerID string, b *domain.Business) error

	// ---- 시설 신고 상태(체육시설업 — 계약서 템플릿 선택의 근거, P42) ----
	// GetFacility — 미선언이면 **기본값**(report_status="unknown" — ErrNotFound 아님).
	// GetBusiness와 같은 규약: 읽기가 문서를 만들지 않는다. unknown은 결측이 아니라 상태다 —
	// 계약서 스탬프 게이트가 이 값으로 스킵을 고른다(모르는 상태로 문서를 만들지 않는다).
	// SaveFacility — centers 문서의 `facility` 절만 머지로 쓴다(Policy·Business 불침범 —
	// SaveBusiness와 같은 규약, P27 SavePolicy 교훈).
	GetFacility(ctx context.Context, centerID string) (*domain.Facility, error)
	SaveFacility(ctx context.Context, centerID string, f *domain.Facility) error

	// ---- 데스크 체크인 QR 토큰(센터 비밀, P49) ----
	// GetCheckinQR — 미발급이면 **빈 값**(token="", issued_at=nil — ErrNotFound 아님).
	// GetBusiness·GetFacility와 같은 규약: 읽기가 문서를 만들지 않는다. 미발급은 결측이 아니라
	// 상태다 — self_qr 체크인이 그 상태를 보고 "아직 발급되지 않았다"로 거부한다.
	// SaveCheckinQR — centers 문서의 `checkin_qr` 절만 머지로 쓴다(Policy·Business·Facility·
	// center 불침범 — SaveFacility와 같은 규약, P27 SavePolicy 교훈).
	//
	// **이 값은 센터 비밀이다.** 스토어는 그것을 모르지만, 읽는 쪽(api.Service)이 owner 전용
	// 응답과 체크인 대조 두 곳에서만 쓴다 — 회원·트레이너 응답에 실리는 순간 집에서 출석을
	// 찍을 수 있게 된다(api/service.go의 CheckinQRView 주석 + 키 집합 테스트).
	GetCheckinQR(ctx context.Context, centerID string) (*domain.CheckinQR, error)
	SaveCheckinQR(ctx context.Context, centerID string, q *domain.CheckinQR) error

	Close() error
}
