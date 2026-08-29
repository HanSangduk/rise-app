package domain

import (
	"errors"
	"time"
)

// Contract — 전자계약(API계약 v1.1 정합 패치). 회원권 발급/추가결제 시 서명 요청 흐름을
// draft(초안)→sent(서명요청 발송)→signed(서명완료) 순으로 추적한다. 실제 PDF 생성·전자서명 연동
// 자체는 v1 범위 밖이다 — 이 구조체는 상태·메타데이터만 보관한다(sha256·pdf_path·signer_ip는
// 연동 시 채워질 자리, README 갭).
type Contract struct {
	ID         string `json:"id"`
	MemberID   string `json:"member_id"`
	PassID     string `json:"pass_id"`
	Product    string `json:"product"`
	PaidAmount int    `json:"paid_amount"`
	// PenaltyRate — 생성 시점 센터 정책의 위약금율 스냅샷(v1.5). 환불 정산은 회원이 동의한
	// 요율을 쓴다 — 이후 정책 변경이 기존 계약에 소급 적용되지 않게 한다. 포인터인 이유(P05 검수):
	// "동의된 0%"와 레거시(스냅샷 이전 — nil)를 구분해야 0% 계약이 인상 정책으로 소급되지 않는다.
	PenaltyRate *float64   `json:"penalty_rate"`
	Status      string     `json:"status"`  // draft|sent|signed|voided
	SentAt      *time.Time `json:"sent_at"` // 마지막 발송 시각(재발송 시 갱신)
	// FirstSentAt — 최초 서명 요청 시각(v1.5, 한 번만 기록) — 재발송이 최초 고지 증적을 지우지 않게.
	FirstSentAt *time.Time `json:"first_sent_at"`
	SignedAt    *time.Time `json:"signed_at"`
	SignerIP    string     `json:"signer_ip"`
	SHA256      string     `json:"sha256"`
	PDFPath     string     `json:"pdf_path"`
}

// Contract.Status 값(API계약 v1.1 + v1.5의 voided).
const (
	ContractStatusDraft  = "draft"
	ContractStatusSent   = "sent"
	ContractStatusSigned = "signed"
	// ContractStatusVoided — 무효(v1.5): 패스 환불로 거래가 해지돼 서명 대상에서 제외된 계약.
	// 미서명 카운트·서명 유도에서 빠지고, 서명·재발송 전이가 모두 막히는 종단 상태.
	ContractStatusVoided = "voided"
)

var (
	// ErrInvalidContractStatus — status 값이 draft|sent|signed|voided 중 하나가 아님(ValidContractStatus).
	ErrInvalidContractStatus = errors.New("domain: invalid contract status")
	// ErrInvalidContractTransition — draft→sent→signed 선형 순서를 벗어난 전이(역행·건너뛰기·종단상태 이후 전이).
	ErrInvalidContractTransition = errors.New("domain: invalid contract status transition")
)

// contractNextStatus — 선형 전이표(draft→sent→signed, 단방향). signed·voided는 종단 상태.
var contractNextStatus = map[string]string{
	ContractStatusDraft: ContractStatusSent,
	ContractStatusSent:  ContractStatusSigned,
}

// ValidContractStatus — status 값이 계약 4종(draft|sent|signed|voided) 중 하나인지.
func ValidContractStatus(s string) bool {
	return s == ContractStatusDraft || s == ContractStatusSent || s == ContractStatusSigned ||
		s == ContractStatusVoided
}

// CanVoidContract — voided 전이 가능 여부(v1.5): 서명 전(draft·sent)만 무효화할 수 있다.
// signed는 실제로 성립했던 거래의 법적 기록이라 보존한다(환불 맥락은 패스 상태로 표현).
func CanVoidContract(from string) bool {
	return from == ContractStatusDraft || from == ContractStatusSent
}

// CanTransitionContract — 상태 전이 헬퍼: from에서 to로의 전이가 유효한지 검증한다.
// draft→sent(최초 발송)·sent→signed(서명 완료)만 허용한다. 예외적으로 sent→sent는 재발송으로
// 허용한다(계약: "POST /v1/contracts/{id}/send 서명 요청(재)발송" — 재발송은 상태를 유지한 채
// sent_at만 갱신하는 것으로 해석). 그 외 동일상태 반복(draft→draft, signed→signed)·역행·건너뛰기는
// 모두 거부한다 — signed는 종단 상태로 그 이후 어떤 전이도 없다(재서명·해지는 v1 범위 밖).
func CanTransitionContract(from, to string) error {
	if !ValidContractStatus(from) || !ValidContractStatus(to) {
		return ErrInvalidContractStatus
	}
	if to == ContractStatusVoided {
		if !CanVoidContract(from) {
			return ErrInvalidContractTransition
		}
		return nil
	}
	if from == ContractStatusVoided {
		return ErrInvalidContractTransition // voided는 종단 — 어떤 전이도 없다
	}
	if from == ContractStatusSent && to == ContractStatusSent {
		return nil // 재발송
	}
	if contractNextStatus[from] != to {
		return ErrInvalidContractTransition
	}
	return nil
}
