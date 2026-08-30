package domain

import (
	"errors"
	"time"
)

// Contract — 전자계약(API계약 v1.1 정합 패치). 회원권 발급/추가결제 시 서명 요청 흐름을
// draft(초안)→sent(서명요청 발송)→signed(서명완료) 순으로 추적한다. v2.18(P39)부터는 상태에
// 더해 **문서 스냅샷**(template_version·vars)과 그 봉인(sha256)까지 보관한다 — 렌더는
// 클라이언트가 하되 언제나 같은 결과가 나오는 §D (다)안. pdf_path만 여전히 후속 연동 자리다.
//
// 직렬화 규약: 계약 필드에는 omitempty를 붙이지 않는다(P37 리뷰). 스토어의 toDoc이 문서를
// 통째 Set하므로, 필드가 직렬화에서 빠지면 전이 트랜잭션의 재적용이 그 자리를 잃는다 —
// 새 필드(template_version·vars)도 같은 이유로 omitempty 없이 간다(빈 값 = 스탬프 전 레거시).
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
	// SHA256 — 문서 봉인(v2.18, P39): 서명 트랜잭션 안에서
	// SHA-256(template_version + "\n" + canonical_json(vars))의 소문자 hex로 채운다(§D ②).
	// 비어 있음 ⟺ 본문 렌더 없이(요약 고지로) 진행된 서명 — 거짓 신호를 만들지 않는다.
	SHA256 string `json:"sha256"`
	// SignaturePNG — 자필 서명 이미지(v2.21, P44 결정 1·2): 회원이 서명 패드에 그린 PNG 원본
	// 바이트의 base64(표준 인코딩·패딩 포함 — 서버가 수신 바이트를 재인코딩한 정규형만 저장).
	// 비어 있음 ⟺ 체크 동의만으로 성립한 서명(구버전 앱·레거시 — SHA256 빈 값 신호와 동형,
	// P44 결정 6). 문서 안에 두는 이유: 5년 보존·탈퇴 비파기(P22 계약 비접촉)를 저장 위치만으로
	// 자동 상속한다(P44 결정 2 — Storage 파일안 기각). 이미지로만 보관하고 특징점 추출은 없다
	// (생체인식 민감정보 비해당 구조, P44 결정 1).
	SignaturePNG string `json:"signature_png"`
	// SignatureSHA256 — 서명 이미지 **원본 PNG 바이트**의 SHA-256 소문자 hex(v2.21, P44 결정 3).
	// 내용 봉인 SHA256과는 역할이 분리된 별개 해시다(Dropbox Sign 2해시 모델과 동형): SHA256은
	// send 확정물(버전+vars)을 봉인하고, 이 해시는 서명 이미지의 사후 변조 검출만 맡는다 —
	// 서명 이미지는 contractSeal 입력에 절대 들어가지 않는다(직렬화 명세 동결 + send 시점에
	// 존재하지 않는 값, P44 결정 3). 두 해시 모두 법정 추정력 주장이 아니다 — 현행법상 추정은
	// 공인전자문서센터(전자문서법 §31조의7)만이며, 자체 해시는 입증 수단이다(P44 결정 7).
	SignatureSHA256 string `json:"signature_sha256"`
	PDFPath         string `json:"pdf_path"` // §D (나) PDF 연동 시 채워질 자리 — 억지로 채우지 않는다(§D ③)
	// TemplateVersion — 이 계약에 확정된 계약서 템플릿 버전(예: "pt-v1", v2.18/P39, §D ①).
	// 템플릿 원문은 앱·어드민에 번들되고 지난 버전은 지우지 않는다. 빈 값 = 스탬프 전
	// (발행 래치 OFF 동안의 계약·레거시) — 클라이언트는 지금 문구(요약 고지)를 유지한다.
	TemplateVersion string `json:"template_version"`
	// Vars — send 시점에 템플릿에 채워진 변수 전부(§C의 슬롯 → 값, v2.18/P39). Pass·Member·
	// Policy·Payment·Business에서 읽어 **그 순간 얼린다** — 이후 원본이 바뀌어도 이 맵은
	// 바뀌지 않는다(PenaltyRate 스냅샷과 같은 이유이자 같은 자리, §D ①). 재발송은 재확정
	// (P39 결정 2), 서명이 sha256으로 봉인해 동결한다.
	Vars map[string]string `json:"vars"`
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
