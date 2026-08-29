---
id: P25
title: 회원권 상태를 유효기간에서 계산 — expired·scheduled가 한 번도 안 쓰이던 결함
status: 진행 중
domain: cross
created: 2026-08-25
completed:
---

# P25 — 회원권 상태 파생

## 목표

P21 감사가 올린 항목: "Pass expired/scheduled 전이 코드 0곳(재등록률 영구 분모 0 실측)".

## 발견

`PassStatusExpired`·`PassStatusScheduled`는 상수로만 존재했다. 프로덕션 코드에서 **대입하는
곳이 한 줄도 없었다** — `CreatePass`가 무조건 `active`를 박고, 그 뒤로 상태를 바꾸는 건
환불(`refunded`)뿐이다.

결과:

| 증상 | 실제 |
|---|---|
| 유효기간 지난 회원권 | 앱·어드민에서 영원히 "이용 중" |
| 재등록률(§8) | 분모가 `status=expired` 개수라 **영구 0** |
| 미래 시작(선등록) 회원권 | 발급 즉시 "이용 중" |
| 예약 | **무사** — 날짜를 직접 비교(`slotDate > ValidUntil`)한다 |

즉 돈이 새는 결함이 아니라 **말이 사실과 다른** 결함이다. 앱·어드민은 두 상태의 라벨과
필터를 이미 갖고 있었는데(`'expired' => '만료'`, 배지 tone 분기) 값이 안 와서 죽어 있었다.

## 결정 사항

### 배치 잡이 아니라 읽는 시점 계산

`domain.Pass.EffectiveStatus(today)` — refunded(저장된 종단 상태) → scheduled → expired → active.

이 저장소가 이미 쓰는 방식이다: `Remaining`도 원장 합산의 캐시일 뿐 저장값을 믿지 않는다.
배치 잡은 "안 돌면 조용히 틀린다"는 실패 모드를 새로 만들고, 홀딩이 유효기간을 늘렸을 때
굳어버린 expired를 되살리지 못한다.

경계는 예약 검사와 **같다** — 시작일·종료일 당일은 유효하다. 두 판정이 갈리면
"이용 중인데 예약이 안 되는" 날이 생긴다.

### 날짜가 망가진 레코드는 추측하지 않는다

빈 `ValidUntil`을 문자열 비교하면 어떤 today보다도 작아 **전부 expired로 뒤집힌다**.
멀쩡히 쓰던 회원권이 하루아침에 "만료"로 보이는 쪽이 모르는 채 두는 것보다 나쁘다.
파싱 실패면 저장값을 그대로 돌려준다.

### 응답에만 싣고 저장하지 않는다

`hydratePassRemaining`(이미 Remaining을 채우던 자리)에 한 줄. 생성·홀딩·재개·환불 응답은
원장을 다시 읽을 필요가 없어 그 함수를 안 거치므로 `stampPassStatus`로 따로 찍는다 —
안 찍으면 **방금 만든 화면에서는 "이용 중", 새로고침하면 "예정"** 으로 보인다.

`HoldPass`/`ResumePass`는 트랜잭션 안에서 **저장된** 상태를 읽으므로 영향 없다(의도적).

### 예약 게이트의 모순이 드러났다

게이트는 `pass.Status != domain.PassStatusActive`인데, **바로 아래 주석**은
"valid_from이 미래인 재등록 패스도 유효기간 안의 슬롯이면 선예약 허용"이라고 적혀 있었다.
저장된 상태가 늘 active라 두 문장이 충돌하는 걸 아무도 못 봤다.

상태를 계산하기 시작하자마자 **기존 테스트 `TestBookingUsesSlotTimeAxis`가 즉시 실패**하며
이 모순을 잡았다(내가 쓴 테스트가 아니라 원래 있던 것 — 의도된 동작이 무엇인지의 증거다).

→ `domain.Pass.BookableStatus()` 신설(화이트리스트: active + scheduled). 날짜 적합성은
호출부가 슬롯별로 따로 본다. 화이트리스트인 이유는 나중에 상태가 늘었을 때
"모르는 상태 = 예약 가능"으로 기울면 안 되기 때문이다.

### 앱·어드민도 같은 규칙으로

앱 `BookablePass.isUsable` 주석은 이 순간을 정확히 예고하고 있었다 — "계약값이 실제로
쓰이는 순간 터진다. 서버가 거부할 예약에 살아 있는 버튼이 뜬다." 이번엔 반대 방향이었다:
**서버는 받아주는데 앱이 거부**한다. `active || scheduled`로 넓혔다.

어드민은 `isPassBookable()` 헬퍼를 `lib/types.ts`에 두고 세 자리에 적용:
- 예약/고정스케줄 회원권 선택(`Schedule.tsx` ×2) — 선예약 대상이라 포함
- 결제 미기록 목록(`Dashboard.tsx`, `Members.tsx`) — 선판매도 돈은 받았다. 빼면 미기록 매출이 사라진다

**넓히지 않은 것**: 만료임박 KPI(scheduled는 임박이 아니다), 잔여 부족 알림, 홀딩 배지·버튼
(시작 전 회원권이 "일시정지 중"이면 이상하다).

## 진행 단계

- [x] `EffectiveStatus` + 도메인 테스트 4종(경계·환불종단·망가진 날짜·홀딩 연장)
- [x] `hydratePassRemaining` + `stampPassStatus` 4개 응답 경로
- [x] 통계 `ListPasses` 사본에 적용 — 재등록률 분모 복구
- [x] `BookableStatus` + 예약 게이트 2곳
- [x] API 테스트 4종 + 뮤테이션 4/4 kill
- [x] 앱 `isUsable` 확장 + 기존 테스트 2건을 새 계약으로 갱신
- [x] 어드민 `isPassBookable` 3자리
- [ ] 어드민 tsc (회원탈퇴 작업 완료 후 — `withdrawn` 미완성분과 겹침)
- [ ] 계약 문서 v2.x 절 추가
- [ ] 배포 후 프로덕션 확인

## 변경 파일

**backend**
- `internal/domain/pass.go` — `EffectiveStatus` · `BookableStatus` · `validDate`
- `internal/domain/pass_status_test.go` (신규 4종)
- `internal/api/service.go` — `hydratePassRemaining` · `stampPassStatus` · 예약 게이트 2곳
- `internal/api/service_stats.go` — 통계 로드 직후 상태 확정
- `internal/api/service_pass_status_test.go` (신규 4종)

**app**
- `lib/features/booking/domain/booking_models.dart` — `isUsable`
- `lib/features/booking/domain/booking_rules.dart` — 주석 정합
- `test/features/booking/domain/booking_models_test.dart` · `booking_rules_test.dart` — 새 계약 반영

**admin**
- `src/lib/types.ts` — `isPassBookable`
- `src/features/Schedule.tsx` ×2 · `Dashboard.tsx` · `Members.tsx`

## 검증

- `go build ./... && go test ./...` 그린
- 뮤테이션 4/4 kill (되돌리면 실패 → 복구 확인)
  - hydrate에서 상태 확정 제거 → 3건 실패
  - refunded 종단 처리 제거 → 4건 실패
  - `BookableStatus`에서 scheduled 제외 → 3건 실패
  - 망가진 날짜 가드 제거 → 1건 실패
- `flutter analyze` 0 · 예약 테스트 136건 그린

## 후속 작업

- `HoldPass`는 만료된 회원권도 저장상 active라 통과시킨다 — 다만 `ValidateHoldWindow`가
  `next.From > validUntil`을 막아 실제로는 못 건다. 이중 방어가 필요한지 판단 필요
- 재등록률이 실제 값을 내기 시작하면 골든값(설계03 §14 R10 4/20=20%) 재확인

## 참조

- `work_log/P21-hollow-feature-audit.md` — 이 항목의 출처
- `internal/api/service_test.go` `TestBookingUsesSlotTimeAxis` — 선예약이 의도된 동작이라는 증거
