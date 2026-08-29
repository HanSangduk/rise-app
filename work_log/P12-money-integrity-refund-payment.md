---
id: P12
title: 돈 무결성 4건 — 환불 기준액에 상한이 없었다
status: 완료
domain: backend
created: 2026-08-23
completed: 2026-08-23
---

# P12 — 환불·결제·발급 금액 결함(C1·C2·H5·M5)

## 목표

P12 감사에서 **curl 실측으로 전부 재현된** 돈 관련 결함 4건을 막는다. 네 건은 각각 다른
엔드포인트에 있었지만 한 문장으로 묶인다: **서버가 "이 거래로 실제 오간 돈이 얼마인지"를
스스로 판정하지 않고 클라이언트가 보낸 기록을 그대로 믿었다.**

| ID | 증상(실측) |
|---|---|
| C1 | 같은 패스에 결제가 중복 기록되면 환불액이 그대로 배가 — 1,000,000 패스 → 환불 1,550,000 / 550,000 패스에 5,500,000 오타 → 환불 5,445,000 |
| C2 | `installments` 미기재(일시불) 결제는 실수납 0으로 계산 — 360,000 완납 회원의 refund-quote 0원, 환불 확정, 되돌릴 API 없음 |
| H5 | `CreatePass`가 `total_sessions`/`paid_amount` 무검증 — 0회 패스(영원히 예약 불가)·`{"delta":-5,"reason":"issue"}`가 원장에 append-only로 박힘 |
| M5 | `installments[].paid_at`을 클라이언트 값 그대로 수용 — 미래 시각도 통과, 즉시 환불 기준액에 반영 |

## 결정 사항

### 환불 기준액의 상한은 계약가(`pass.paid_amount`)다 — 도메인에서 캡핑
`domain.SettleRefund`에서 `paidSum = min(max(paidSum,0), paid)`. **`MaxPenaltyRate`와 같은
자리**다: 설정·입력이 무엇이든 돈이 나가기 직전의 마지막 방어선은 코드여야 한다. 서비스
레이어(`refundBasis`)에 두지 않은 이유는 견적·실행 두 경로가 함께 보호돼야 하고, 순수
함수라 골든값으로 고정할 수 있어서다.
트레이드오프를 주석에 남겼다: 계약가가 실제보다 낮게 잘못 입력된 패스는 덜 환불된다. 검증되지
않은 기록을 믿고 더 주는 쪽보다 낫고(나간 돈은 못 돌아온다), 계약가는 회당 단가·위약금의
기준이기도 해서 그 값이 틀렸다면 환불이 아니라 패스를 정정할 사안이다.

### 원장은 지우지 않는다 — 대신 "쓰기 게이트 + 읽기 캡" 이중 방어
append-only 규약(P3)상 이미 박힌 중복 결제 레코드는 삭제하지 않는다. 그래서 C1·M5 둘 다
**쓰기에서 막고, 읽기(정산)에서 한 번 더 거른다**. 감사가 프로덕션에 남긴 레코드가 실제로
있으므로 읽기 방어선이 없으면 지금 당장 돈이 나간다.
캡이 걸린 사건은 조용히 넘기지 않고 서버 로그(`logPaymentOverContract`)로 남긴다 — 캡은
지혈이고, 중복 기록 자체는 사람이 정정해야 한다.

### C2는 "installments 필수화"가 아니라 "PaidSum 폴백"으로
계약(`docs/API계약_v1.md`)이 `installments`를 필수로 못박지 않았고, 어드민의 일시불 경로가
실제로 이 필드 없이 보낸다 — 필수화는 클라이언트를 깨는 breaking change다.
결정적 근거는 따로 있다: **`Outstanding()`은 이미 회차 없는 결제를 "낼 것 없음(0)"으로 세고
있었다.** 같은 레코드를 두고 청구 쪽은 "다 받았다", 수납 쪽은 "받은 적 없다"고 말하던
모순이 결함의 본체다. 폴백은 그 둘을 일치시킨다 — 불변식 `PaidSum + Outstanding == Total`.

### `paid_amount = 0`은 허용, `total_sessions = 0`은 거부
무료 체험권·서비스 제공은 실제 영업 조건이고 금액 0은 어떤 계산도 망가뜨리지 않는다(견적
0원, 매출 0 가산). 반면 0회 패스는 그 자체로 쓸 수 없는 회원권이다. 음수는 둘 다 거부.

### 계약가 상한은 "건수"가 아니라 "합계"에 건다
카드 일부 + 현금 일부처럼 한 패스에 결제를 나눠 기록하는 것은 정상 영업이다(어드민의 "결제만
기록" 모드가 계약가 미만 입력을 명시적으로 지원한다). 패스당 1건 제한은 과잉 — `Σ Payment.Total
≤ pass.paid_amount`만 강제한다. 기준축을 `Total`로 잡은 이유는 매출 집계(`revenueByMonth`)가
같은 축이라서다: 중복 기록은 환불액과 매출을 **함께** 부풀린다.

### 시계 오차 허용치는 쓰기·읽기가 같은 값을 쓴다
`paid_at`은 미래 거부하되 `paidAtClockSkew = 5분`을 허용한다(데스크 PC 시계가 조금 앞선 것까지
거부하면 정상 입력이 랜덤하게 400). 정산의 `asOf`도 같은 경계(`now + 5분`)를 쓴다 — 게이트가
받아준 결제를 정산이 몇 분간 "받은 적 없는 돈"으로 떨어뜨리면 그 사이 환불액이 달라진다.

## 진행 단계

- [x] 1. 실패하는 테스트 선작성 → 4/4 실측 재현(환불 1,550,000 / 일시불 0원 / 원장 `delta:-5` / 미래 paid_at 통과)
- [x] 2. C1·C2·H5·M5 수정(도메인 캡 + 서비스 게이트)
- [x] 3. 뮤테이션 검증 6/6 kill + 전체 회귀 그린
- [x] 4. 계약 변화 정리(문서 반영은 요청자)

## 변경 파일

**backend**
- `internal/domain/refund.go` — `SettleRefund` 계약가 상한·음수 clamp
- `internal/domain/payment.go` — `PaidSum(asOf)`: 일시불 폴백 + 미래 `paid_at` 제외(시그니처 변경)
- `internal/api/service.go` — `CreatePass` 금액·회차 검증 · `CreatePayment` 계약가 상한·미래 `paid_at` 거부 · `recordedPaymentTotal` 신규 · `refundBasis` 이상 로그
- `internal/api/util.go` — `logPaymentOverContract`
- `internal/api/service_money_test.go`(신규 — 회귀 6건) · `internal/domain/{payment,refund}_test.go`(3건) · `internal/api/service_test.go`(기존 게이트 테스트를 999,800+200 분할 기록으로 조정)

## 검증

- **선작성 테스트가 수정 전 전부 실패** — 감사 실측값을 그대로 재현(`refund 1,550,000`,
  `paid_sum 0`, 원장에 `{Delta:-5, Reason:issue}` 4건 적재, 미래 `paid_at` `err = <nil>`).
- **뮤테이션 검증 6/6 kill.** 원본 트리를 다른 에이전트가 동시 편집 중이라 스냅샷 사본에서
  수행(검증 후 사본 폐기 — 실제로 in-place 뮤테이션 한 번이 동시 쓰기에 덮여 사라졌다):

  | 되돌린 방어선 | 결과 |
  |---|---|
  | C1 쓰기 — `CreatePayment` 계약가 상한 | FAIL `err = <nil>`(중복 기록 통과) |
  | C1 읽기 — `SettleRefund` 캡 | FAIL `paid_sum 2,000,000 / refund 1,550,000` |
  | C2 — `PaidSum` 일시불 폴백 | FAIL `paid_sum 0 / refund 0` |
  | H5 — 발급 금액·회차 검증 | FAIL(4케이스 통과 + 원장 4건 적재) |
  | M5 쓰기 — 미래 `paid_at` 거부 | FAIL `err = <nil>` |
  | M5 읽기 — 정산에서 미래분 제외 | FAIL `paid_sum 1,000,000 / refund 900,000` |

- `gofmt -l internal/` 클린 · `go build ./...` · `go vet ./...` · `go test ./...` 4패키지 그린.
- 어드민 영향 확인: `Members.tsx`의 `canSubmit`이 이미 `totalSessions > 0 && paidAmount > 0`을
  강제하므로 H5 게이트는 정상 흐름을 막지 않는다. "결제만 기록" 모드의 계약가 미만 입력도 통과.

## 후속 작업

- **어드민 "결제만 재시도" 문구**: 이제 400 + "앞선 결제가 이미 처리됐는지 확인해주세요"가 온다.
  에러 토스트가 아니라 "이미 기록됨" 안내로 처리하는 편이 맞다(응답 유실이 원인이므로 사용자는
  실패로 읽는다).
- **계약가 정정 API 부재**: `paid_amount`가 잘못 입력된 패스는 이제 결제 기록도 막힌다.
  `PUT /v1/passes/{id}`(계약가·상품명 정정)가 없어 재발급이 유일한 경로다.
- **환불 취소(되돌리기) API 부재**: C2가 실측에서 확정 환불까지 갔는데 복구 수단이 없었다.
  원장주의상 "역전 원장(reverse)"으로 설계해야 한다.
- **프로덕션 잔존 데이터**: 감사가 남긴 중복 결제·미래 `paid_at` 레코드는 그대로 있다(정산은
  캡으로 막힘). `payment over contract` 로그로 대상을 뽑아 사람이 정정 필요.
- **미수금 집계의 미래 `paid_at`**: 정산에서는 제외했지만 `Outstanding()`은 여전히 "납부됨"으로
  본다(미수금에 안 잡힘). 잔존 레코드 정정으로 해소되는 범위라 손대지 않았다.

## 참조

- `docs/API계약_v1.md` v1.5 정산·정합 패치(실수납 기준 정산의 출처) · v2.3(현재 계약 버전)
- `work_log/P04-booking-payment-contract-audit.md` — 실수납 기준 정산(`SettleRefund`)이 도입된 라운드
