---
id: P14
title: 센터 정책 — 화면·계약서·환불·회원앱이 같은 숫자를 말하게
status: 완료
domain: cross
created: 2026-08-23
completed: 2026-08-23
---

## 목표

정책 화면(`Settings.tsx`)이 "저장됐어요"라고 말한 값과 실제로 집행되는 값이 어긋나는 결함군을
닫는다. 핵심은 위약금율(C1) — 어드민 30% / 계약서 30% / 실제 환불 10% / 회원앱 30%.
정책 화면은 대표가 **돈과 약관을 정하는 자리**라 "저장됐어요"가 무엇을 뜻하는지 정확해야 한다.

## 결정 사항

**C1 — 캡을 남기고 경고하는 쪽이 아니라, 정책이 상한을 말하게 했다.**
두 갈래(입력 상한을 내리고 서버도 거부 / 캡은 두고 저장 전 경고 + 스냅샷만 캡핑) 중 전자.
근거: 후자는 저장된 값 0.3이 **아무 곳에서도 집행되지 않으면서** 어드민 푸터·회원앱
`GET /v1/center`·계약서에 계속 나타난다 — 거짓말하는 자리를 줄이는 게 아니라 늘린다.
상한이 진짜 정책이므로 상한이 정책의 언어로 말해야 한다: 집행하지 않을 조항은 발행하지 않고,
발행할 조항은 반드시 집행한다.
`RefundQuote`의 런타임 캡은 **남겼다** — 계약 스냅샷은 과거에 서명된 값이라 정책과 무관하게
남아 있다(P14 이전 30% 서명 계약이 실재). 돈이 나가기 직전의 마지막 방어선은 코드여야 한다.

**C1 부수 — 구문서는 저장이 아니라 읽기에서 접는다**(`Policy.Normalize`).
접지 않으면 ① 초과값이 계약 스냅샷·회원앱으로 그대로 새고 ② 머지 시맨틱 PUT이 초과값을
이어받아 `Validate`에 걸려 **용량 하나 바꾸려 해도 400**이 되는 잠금 상태가 된다.

**H1 — 예약 단위 컷오프 스냅샷은 하지 않았다.** 채택: 문구 정정 + 컷오프 **상향 시에만**
확인 창 + 영향받는 확정 예약 실건수 노출.
기각 근거: 예약에 컷오프를 스냅샷하면 앱의 `freeCancel` 판정(`home_repository_impl.dart:91`,
센터 정책값 사용)과 서버 판정이 **예약마다 갈린다** — 앱이 "무료 취소 가능"이라 표시한 예약을
서버가 차감하는 새로운 3자 불일치가 생기는데, 이번 작업에서 `app/`은 건드릴 수 없다.
고치려던 것과 같은 종류의 결함을 하나 더 만드는 선택이라 접었다(후속 작업 참조).

**M2 — `0`을 "홀딩 금지"로 재해석하지 않았다.** `0 = 필드 부재`는 `NormalizeHoldLimits`가
구문서 승격에 쓰는 의미라 재사용하면 v1.2 이전 문서에서 상한이 조용히 풀린다. 대신 화면이
"0은 안 되고, 최소 1회는 항상 허용되며, 홀딩을 완전히 막는 설정은 없다"를 **사실대로** 말하게 했다.

## 진행 단계

- [x] C1 위약금율 — 선작성 테스트(도메인 3 + 서비스 2) → 구현 → 뮤테이션 6/6 kill → 실서버 실측
- [x] H1 소급 문구 정정 + 컷오프 상향 확인 창 + 영향 건수
- [x] H2 인쇄 안내문 ↔ 앱 실물 대조(앱은 읽기만) + A4 1장 실측
- [x] M1 홀딩 상한 한정어 / M2 0 차단 / M3 blockers isError / M4 목표 0 / M5 patch 시맨틱
- [x] L1 입력 클램프 / L2 placeholder / L3 휴무 과거일·저장 안내 / L4 `IsOffday` 배선

## 변경 파일

**backend**
- `internal/domain/policy.go` — `Validate` 위약금율 상한 `MaxPenaltyRate`, `EffectivePenaltyRate()`, `Normalize()` 신설
- `internal/domain/refund.go` — `MaxPenaltyRate` 주석(왜 런타임 캡을 남기는지)
- `internal/domain/policy_test.go` — **신규**, 3 테스트
- `internal/api/service.go` — 계약 스냅샷 2곳·`refundBasis`가 `EffectivePenaltyRate()` 경유,
  `GetCenter` 주석, 휴무 판정을 `st.IsOffday()`로(L4)
- `internal/api/service_test.go` — 금액 단언 2 테스트 + `uncappedPolicyStore` 하네스
- `internal/store/firestore.go`, `internal/store/memory.go` — `GetPolicy` 읽기 정규화 통일

**admin**
- `src/lib/types.ts` — `MAX_PENALTY_RATE` / `MAX_PENALTY_PCT`
- `src/lib/api.ts`, `src/lib/queries.ts` — `updateCenterPolicy(patch: Partial<CenterPolicy>)`
- `src/lib/format.ts` — `slotKeyStart()`
- `src/features/Settings.tsx` — `PolicyEditForm` 전면(C1·H1·M1·M2·M5·L1), `OffdaysModal`(L3),
  `DeactivateStaffModal` blockers(M3), 페이지 부제
- `src/features/Sales.tsx` — 환불 계산기 상한(C1 보강), 매출 목표 0(M4)
- `src/features/CheckinQr.tsx` — 인쇄 안내문·화면 안내(H2), placeholder(L2)
- `src/index.css` — 인쇄 시트 `padding-top` 20mm→12mm(A4 1장 유지)

## 검증

- `go build ./... && go vet ./... && go test ./... -race` 전부 통과
- **뮤테이션 6/6 kill**: Validate 상한 제거 / Normalize 접기 제거 / 계약 스냅샷 가드 제거 /
  `EffectivePenaltyRate` 항등화 / memory 정규화 제거 / RefundQuote 런타임 캡 제거
- **실서버 실측**(:8096, DEV_SEED): `penalty_rate 0.3` → **400**, `0.05` → 200 →
  발급 계약 스냅샷 `0.05` → `refund-quote` penalty **50,000** (= 계약서 5% × 1,000,000, MATCH) →
  회원 `GET /v1/center` `penalty_rate 0.05`. **네 자리 일치**
- `npm run build`(tsc 포함) 통과
- 인쇄 시트: headless Chrome PDF **1페이지**(Apple SD Gothic Neo / Pretendard 양쪽, 여유 2줄)

## 후속 작업

- **예약 컷오프 스냅샷**(H1 미채택분) — 서버 `Booking`에 컷오프를 스냅샷하려면 앱의
  `freeCancel` 판정도 그 값을 읽도록 함께 고쳐야 한다(app/backend 동시 변경 필요)
- **"홀딩 금지"를 표현할 방법이 없다**(M2) — 필요하면 `0` 재해석이 아니라 별도 필드
- **P14 이전에 30%로 서명된 계약**은 계약 문서에 0.3이 남아 있고 어드민 계약 행(`Members.tsx:499`)이
  그 값을 그대로 보여준다. 실제 공제는 10%(런타임 캡). 서명된 문서를 소급 수정하지 않는다는
  판단이지만, 표시에 "실제 공제 10%" 각주가 필요한지는 대표와 확인 필요

## 참조

- `admin/src/features/Settings.tsx` `POLICY_EFFECT_NOTE` — 즉시·소급 / 계약 고정의 유일한 구분
- 앱 대조 파일(읽기만): `next_booking_card.dart`, `home_screen.dart`,
  `home_repository_impl.dart`, `ledger_summary.dart`
