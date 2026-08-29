package domain

import "testing"

// 골든값: v1.1 정합 패치 "Contract {..., status:"draft|sent|signed", ...}" — draft→sent→signed
// 선형 전이만 허용하고, sent→sent(재발송)만 예외로 허용한다("POST /v1/contracts/{id}/send
// 서명 요청(재)발송").
func TestCanTransitionContract(t *testing.T) {
	cases := []struct {
		name string
		from string
		to   string
		ok   bool
	}{
		{"draft에서 sent로 최초 발송", ContractStatusDraft, ContractStatusSent, true},
		{"sent에서 signed로 서명 완료", ContractStatusSent, ContractStatusSigned, true},
		{"sent에서 sent로 재발송 허용", ContractStatusSent, ContractStatusSent, true},
		{"draft에서 signed로 건너뛰기 거부", ContractStatusDraft, ContractStatusSigned, false},
		{"signed에서 sent로 역행 거부", ContractStatusSigned, ContractStatusSent, false},
		{"signed에서 draft로 역행 거부", ContractStatusSigned, ContractStatusDraft, false},
		{"sent에서 draft로 역행 거부", ContractStatusSent, ContractStatusDraft, false},
		{"draft에서 draft로 반복 거부", ContractStatusDraft, ContractStatusDraft, false},
		{"signed에서 signed로 반복 거부(종단상태)", ContractStatusSigned, ContractStatusSigned, false},
		{"알 수 없는 시작 상태 거부", "voided", ContractStatusSent, false},
		{"draft 무효화 허용(v1.5)", ContractStatusDraft, ContractStatusVoided, true},
		{"sent 무효화 허용(v1.5)", ContractStatusSent, ContractStatusVoided, true},
		{"signed는 무효화 불가(기록 보존)", ContractStatusSigned, ContractStatusVoided, false},
		{"voided는 종단 — 재발송 불가", ContractStatusVoided, ContractStatusSent, false},
		{"알 수 없는 목표 상태 거부", ContractStatusDraft, "cancelled", false},
	}
	for _, c := range cases {
		err := CanTransitionContract(c.from, c.to)
		if (err == nil) != c.ok {
			t.Errorf("%s: CanTransitionContract(%s,%s) = %v, want ok=%v", c.name, c.from, c.to, err, c.ok)
		}
	}
}

func TestCanTransitionContractErrorKind(t *testing.T) {
	if err := CanTransitionContract("nope", ContractStatusSent); err != ErrInvalidContractStatus {
		t.Errorf("err = %v, want ErrInvalidContractStatus", err)
	}
	if err := CanTransitionContract(ContractStatusVoided, ContractStatusSent); err != ErrInvalidContractTransition {
		t.Errorf("voided 이후 전이 err = %v, want ErrInvalidContractTransition", err)
	}
	if err := CanTransitionContract(ContractStatusDraft, ContractStatusSigned); err != ErrInvalidContractTransition {
		t.Errorf("err = %v, want ErrInvalidContractTransition", err)
	}
}
