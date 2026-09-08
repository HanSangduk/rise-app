package api

// 직렬화 계약 "배열 필드는 항상 [] (null 금지)"의 **읽기 쪽 바닥**(v2.28, P56 A3).
//
// 계약(docs/API계약_v1.md 직렬화·정책 규약)은 Member.flags · Pass.holds · Staff.offdays를
// 항상 배열로 약속했고, 생성 경로(CreateMember·CreatePass·JoinApprove)가 nil→[]로 정규화해
// 그 약속을 지켰다. 그런데 **두 구멍**이 있었다:
//
//  1. Payment.installments는 형제 배열인데 정규화 목록에 없었다 — 일시불 결제는 installments
//     생략으로 들어오고, 스토어는 JSON 왕복이라 한 번 null이면 문서에 영구히 null이다.
//     어드민 Members.tsx가 `pay.installments.filter`를 무가드로 부르므로 그런 문서 1건이
//     회원 상세를 여는 순간 어드민 전체 폴백이다(P55 C-1과 같은 폭발 반경).
//  2. 정규화가 **생성 경로에만** 있었다. 이미 null로 굳은 문서는 PUT 머지로도 낫지 않고
//     (`slices.Clone(nil) == nil`), 읽기는 문서를 그대로 흘렸다 — 프로덕션에 그런 문서가
//     있으면 쓰기를 고쳐도 영원히 안 낫는다.
//
// 그래서 **읽기 직전에도** 정규화한다. 응답 직전 한 자리에서 nil→[]를 보장하면 문서의 과거가
// 어떻든 와이어는 계약대로다. 저장 쪽 정규화는 그대로 둔다(문서를 고치는 것은 그쪽 몫이고,
// 읽기 정규화는 고쳐지지 않은 문서를 위한 바닥이다 — "쓰기+읽기 이중 방어", PaidSum과 같은 구조).
//
// **nil이 의미를 갖는 배열에는 쓰지 않는다.** Member.BodyPoses는 nil="센터 기본 사용"이라
// 여기 넣으면 의미가 깨진다(도메인 주석 참고) — 그쪽은 EffectiveBodyPoses가 응답을 채운다.

import "github.com/ramsang/rise-backend/internal/domain"

// normalizeMemberWire — Member.flags nil→[]. 목록·PUT 응답 직전 + PUT 저장 직전(문서 치유).
func normalizeMemberWire(m *domain.Member) {
	if m == nil {
		return
	}
	if m.Flags == nil {
		m.Flags = []domain.MemberFlag{}
	}
}

// normalizePassWire — Pass.holds nil→[]. hydratePassRemaining(목록)·stampPassStatus(단건)가
// 모든 패스 응답의 관문이라 그 둘에서 부른다.
func normalizePassWire(p *domain.Pass) {
	if p == nil {
		return
	}
	if p.Holds == nil {
		p.Holds = []domain.Hold{}
	}
}

// normalizePaymentWire — Payment.installments nil→[]. 생성 저장 직전 + 목록·납부 응답 직전.
// 결제는 PUT 경로가 없어 "다시 저장해서 고친다"가 성립하지 않으므로 읽기 정규화가 유일한 바닥이다.
func normalizePaymentWire(p *domain.Payment) {
	if p == nil {
		return
	}
	if p.Installments == nil {
		p.Installments = []domain.Installment{}
	}
}
