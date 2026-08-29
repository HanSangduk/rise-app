---
id: P12
title: 앱 홀딩 판정 ↔ 서버 계약 정합(상한 사전검증·후보 필터·재개·서명)
status: 완료
domain: app
created: 2026-08-23
completed: 2026-08-23
---

# P12 — 앱 홀딩 판정 ↔ 서버 계약 정합

## 목표

`P12-app-booking-judgment.md`의 "후속 작업"에 주인 없이 남아 있던 두 항목(MEDIUM 12 홀딩 상한
사전 검증 · `hold_request_sheet`의 후보 필터)을 처리하고, `features/my` 안에서 **같은 클래스**의
결함 — "서버가 400/403을 줄 동작에 살아 있는 버튼을 주는 자리" — 를 전수로 훑는다.

예약 팀은 "마이 탭 영역"이라, 마이 탭 팀은 "예약 팀이 찾은 결함"이라 서로 넘겼던 항목이다.
판정식의 원본은 문서나 기억이 아니라 **서버 코드**로 두고, 앱 쪽 판정을 순수 함수로 떼어
테스트 + 뮤테이션으로 고정한다.

## 결정 사항

### 1. 판정을 `HoldRules`(순수 함수)로 떼고, 서버의 **거부 순서까지** 옮겼다

`app/lib/features/my/domain/hold_rules.dart` 신설. `BookingRules`와 같은 형태
(sealed 상태 + `abstract final class` 정적 판정)로, 서버 세 지점을 그대로 미러한다:

| 앱 | 서버 원본 |
|---|---|
| `canRequestFor` (active만) | `api/service.go` `HoldPass` — `pass.Status != active` → 400 |
| `HoldRangeReversed`·`StartsInPast`·`StartsAfterValidUntil`·`OverlapsExisting` | `domain/pass.go` `ValidateHoldWindow` |
| `HoldCountExceeded`·`HoldTotalDaysExceeded` | `domain/pass.go` `ValidateNewHold` |
| `durationDays` (양끝 포함) | `domain/pass.go` `HoldDurationDays` |

순서를 맞춘 이유는 `BookingRules`와 같다 — 두 제약이 겹칠 때 앱이 서버와 다른 이유를
안내하면, 회원은 안내대로 고쳐도 다른 이유로 또 거부당한다. 순서 자체를 테스트 3건으로 고정했다
(상태 > 구간 > 횟수 > 일수).

### 2. 무제한 판정은 `<= 0` — 서버 가드를 글자 그대로 옮겼다

계약 v1.3은 무제한을 `-1`로 표현하지만, 서버 `ValidateNewHold`의 실제 가드는
`maxCount > 0` / `maxTotalDays > 0`이다(0 이하는 전부 무제한 취급). 앱이 `== -1`로 좁히면
0이 들어왔을 때 **서버는 통과시키는데 앱만 막는** 반대 방향 불일치가 된다. 정상 로드 경로에선
`Policy.NormalizeHoldLimits`가 0을 기본값으로 승격하고 `Policy.Validate`도 0을 거부하므로
실제로는 도달 불가한 값이지만, "앱이 서버보다 엄해지지 않는다"를 원칙으로 서버 가드를 따랐다.

### 3. 표시와 판정을 **같은 모듈**에 붙였다

요구가 명확했다 — "1회 남았다고 써 있는데 거부당한다"가 생기면 안 된다. 그래서
`HoldRules.usageLabel`(표시)과 `HoldRules.evaluate`(판정)가 같은 파일에서 **같은 정책 필드**
(`maxHoldsPerPass`/`maxHoldTotalDays`)와 **같은 무제한 술어**(`countUnlimited`/`daysUnlimited`)를
쓴다. "표시가 '2회 중 1회'면 판정은 통과, '2회 중 2회'면 판정은 거부"를 한 테스트 안에서
같은 입력으로 함께 검증한다.

시트에는 정책 문장(`policy.holdLimitLabel` — "최대 2회/30일")과 **잔량 한 줄**
("이 회원권은 최대 2회/30일 중 1회·3일을 썼어요")이 나란히 뜬다. 종전엔 정책만 있어서
"내가 몇 번 썼는지"는 거부당해야 알 수 있었다.

### 4. 후보 필터의 진짜 범인은 `isScheduled`가 아니라 **폴백**이었다

`isActive || isScheduled`도 틀렸지만(서버 `HoldPass`는 active만), 그보다
`usable.isEmpty ? widget.passes : usable`가 더 나빴다 — 후보가 비면 **만료·환불 패스를 다시
드롭다운에 올린다**. 예약 팀이 `PassNotUsable`에서 찾은 것과 같은 구조다: 환불 패스는
`RefundPass`가 status만 바꾸고 유효기간·holds는 그대로 두므로 화면상 살아 있는 회원권으로 보인다.

폴백을 없애고, 후보가 0이면 폼 대신 이유를 띄운다(회원권이 하나면 그 상태로 구체적으로,
여럿이면 공통 사실만 — 어느 하나를 지목하면 나머지엔 틀린 말이 된다). 막았으면 빠져나갈 길을
준다는 규약대로 "닫기"를 남겼다(동의 시트의 "다시 불러오기"와 같은 형식).

### 5. 전수 훑기에서 추가로 나온 것 — 재개 버튼 · 계약 서명 · 환불 견적

- **재개 버튼(`pass_list.dart`)**: `PassDetail.activeHold`만 보고 배지+버튼을 띄웠는데,
  서버 `ResumePass`는 **active만** 받는다(400 "이용 가능한 상태의 패스만 재개할 수 있어요").
  환불·만료 패스도 `holds`를 그대로 들고 있어(`RefundPass`는 status만 바꾼다) 오늘이 구간 안이면
  죽은 버튼이 떴다. 상태가 아닌 패스에선 "일시정지 중" 배지까지 함께 감춘다 — '환불' 배지 옆의
  '일시정지 중'은 회원에게 "아직 살아 있는 회원권"으로 읽힌다.
- **계약 서명(`contracts_row.dart`)**: `SignContract`는 전이 검사 외에 **패스가 refunded면
  거부**한다("환불 처리된 거래의 계약은 서명할 수 없어요"). 보통 `RefundPass`가 미서명 계약을
  voided로 넘기지만 그 단계는 환불 처리의 **뒤쪽**이라, 중간 실패 시 "패스는 refunded인데 계약은
  sent"가 남는다. 목록만 보면 멀쩡한 '서명 대기' 행이라 탭 → 시트 → 서명 → 400까지 갔다.
  `refundedPassIds`를 마이 화면에서 내려 탭을 막고 이유를 한 줄로 말한다. **상태 배지는 서버가
  준 값 그대로 둔다** — 없는 상태를 지어내지 않는다(`ContractItem.statusLabel`의 폴백 규약).
- **환불 견적(`my_screen.dart`)**: 서버 `RefundQuote`는 `used > total`을 400으로 거부한다.
  잔여는 원장 합이라 음수로 내려갈 수 있어(코드 주석이 실제 사례를 언급한다) `used`가 총 횟수를
  넘을 수 있었다. 하한만 조이던 것을 `clamp(0, totalSessions)`로 양끝 다 조였다.

### 6. 동의 저장 경로는 **결함 없음**으로 확인

`UpdateMember`의 member 분기가 400을 내는 조건은 `req.Consent == nil`(= consent 외 필드를
보낸 경우)뿐인데, 앱 `MemberApi.updateConsent`는 항상 `{"consent":{...}}`만 보낸다.
`normalizeConsentTransition`은 거부가 아니라 기록이고, `SensitiveConsentValid`는 인바디·체형
저장 시점에 걸리는 별개 관문이다(그건 이미 P12에서 처리됨). 손대지 않았다.

### 자문자답

- **날짜 미입력도 버튼을 잠글까?** 아니다. 미입력은 "거부"가 아니라 "미완성"이다. 이유 없이
  잠긴 버튼은 무엇을 더 해야 하는지 알려주지 않는다 — 눌러서 "시작일과 종료일을 선택해주세요"를
  받게 두고, 서버가 확실히 거부할 조합일 때만 잠근다.
- **데이트피커의 `lastDate`를 유효기간으로 줄일까?** 아니다. active 패스라도 만료 배치가 없어
  `validUntil`이 과거일 수 있고(백엔드에 패스를 expired로 넘기는 코드가 없다 — 예약 팀 P12 §3),
  그러면 `firstDate > lastDate`로 `showDatePicker`가 assert로 죽는다. 판정 문구로 안내하는 쪽이
  안전하다.
- **`CenterPolicy.holdLimitLabel`의 `== -1`도 `<= 0`으로 고칠까?** 하지 않았다. `core/policy`는
  이번 작업 범위(`features/my`) 밖이고, 0은 서버 `Policy.Validate`·`NormalizeHoldLimits`가
  양쪽에서 막아 도달 불가하다. 시트 안의 표시(`usageLabel`)와 판정은 같은 술어를 쓰므로
  이 시트에서 둘이 갈릴 일은 없다. → **후속 작업**에 남긴다.
- **거부 문구에서 상한을 어떻게 말할까?** 정책 실값만. 서버는 "일시정지 가능 횟수/일수를
  초과했어요(센터 정책)"로 두 상한을 합쳐 보내지만, 앱은 어느 쪽에 걸렸는지·얼마 남았는지를
  알고 있으므로 그 값을 쓴다. 무제한(-1)이면 "최대 N회" 문장 자체를 만들지 않는다.
- **"다음 행동"을 뭐라고 쓸까?** 횟수 상한·남은 일수 0은 회원이 스스로 풀 수 없다 —
  스태프는 서버에서 상한을 건너뛸 수 있으므로(`HoldPass`의 member 분기) "센터에 문의해주세요"가
  참이다. 일수가 남아 있으면 "N일 이내로 줄여주세요"처럼 회원이 지금 할 수 있는 일을 말한다.
- **`durationDays`를 `DateTime.difference`로?** 서머타임 지역에서 23/25시간 구간이 하루를
  흘린다. 서버 `time.Parse`는 UTC 고정이라 그런 흔들림이 없으므로, UTC 자정으로 정규화하고 뺀다.

## 진행 단계

- [x] 서버 소스 대조(`api/service.go` HoldPass/ResumePass/SignContract/RefundQuote, `domain/pass.go`, `domain/policy.go`, `api/util.go` 에러 문구)
- [x] `HoldRules` 신설 — 상태·구간·상한 판정 + 표시 문구를 한 모듈로
- [x] `hold_request_sheet` — 후보 필터 active 전용·폴백 제거, 실시간 사전 판정 + 버튼 잠금 + `_submit` 이중 방어, 잔량 표시
- [x] 전수 훑기 — 재개 버튼 상태 게이트, 계약 서명 환불 게이트, 환불 견적 상한 클램프
- [x] 테스트 46건(도메인 33 · 위젯 13) · 뮤테이션 11종 전부 kill
- [x] `flutter analyze` 0 · `flutter test` 522 통과

## 변경 파일

**판정(앱)**
- `app/lib/features/my/domain/hold_rules.dart` — **신규**. `HoldRequestState` sealed 계층
  (`HoldAllowed` + 거부 6종, 각 거부가 화면 문구를 들고 있다) + `HoldRules.evaluate`/`candidates`/
  `durationDays`/`usedDays`/`countUnlimited`/`daysUnlimited`/`usageLabel`

**UI**
- `app/lib/features/my/presentation/widgets/hold_request_sheet.dart` — 후보 필터를
  `HoldRules.candidates`로(active 전용·원본 폴백 제거), 후보 0이면 `_NoCandidateBody`,
  build마다 사전 판정 → 인라인 사유 + 버튼 잠금, `_submit`이 판정을 한 번 더 통과시킴,
  잔량 한 줄 추가, 패스·날짜 변경 시 낡은 서버 문구 소거
- `app/lib/features/my/presentation/widgets/pass_list.dart` — `_resumableHold`(active 게이트)
- `app/lib/features/my/presentation/widgets/contracts_row.dart` — `refundedPassIds` 입력,
  `_signable` 신설(탭·셰브런·44dp 히트영역이 전부 이 판정을 따름), 환불 거래 사유 문구
- `app/lib/features/my/presentation/my_screen.dart` — `refundedPassIds` 배선,
  환불 견적 `used`를 `clamp(0, totalSessions)`로

**테스트**
- `app/test/features/my/domain/hold_rules_test.dart` — **신규** 33건. 경계값(상한 직전/도달,
  총 일수 정확히 채움/+1일, 남은 날 0, 과거 홀딩 0건, 무제한 -1/0/1), 구간 경계(오늘 시작 통과 /
  어제 거부, 유효기간 마지막 날 통과 / +1일 거부, 겹침 끝점 포함 / 다음 날 통과),
  판정 순서 3건, 표시-판정 일치 검증
- `app/test/features/my/presentation/widgets/hold_precheck_test.dart` — **신규** 13건.
  상한 도달 시 POST가 안 나가는 것과 **상한 직전엔 그대로 나가는 것**을 함께,
  후보 필터·폴백 제거·대표 패스 정규화, 재개 버튼 상태 게이트, 계약 서명 환불 게이트

## 검증

- `flutter analyze` — No issues found
- `flutter test` — 522 passed (착수 시점 473 + 이번 46 + 동시 진행 타 작업분)
- **뮤테이션 검증 11종, 전부 kill** (판정을 되돌려 실패를 확인한 뒤 복구·재검증)

  | 뮤테이션 | 결과 |
  |---|---|
  | 횟수 상한 off-by-one (`used+1 > max+1`) | 5건 실패 |
  | 총 일수 상한 off-by-one (`> max+1`) | 3건 실패 |
  | `durationDays`에서 양끝 포함(+1) 제거 | 10건 실패 |
  | `canRequestFor`에 scheduled 복원 | 3건 실패 |
  | `candidates`의 원본 폴백 복원 | 3건 실패 |
  | 과거 시작 검사 제거 | 2건 실패 |
  | 기존 홀딩 겹침 검사 제거 | 1건 실패 |
  | 유효기간 밖 시작 검사 제거 | 1건 실패 |
  | 횟수 무제한 판정 제거(-1도 상한 취급) | 8건 실패 |
  | 재개 버튼 active 게이트 제거 | 2건 실패 |
  | 계약 서명 환불 게이트 제거 | 1건 실패 |

  복구 후 재확인: 46건 전부 통과, 원본과 바이트 동일(diff 0).

## 후속 작업

- **`CenterPolicy.holdLimitLabel`의 무제한 술어** — `== -1`이라 서버 가드(`> 0`)와 0에서 갈린다.
  서버가 0을 양쪽에서 막아 현재는 도달 불가하고, `core/policy`가 이번 범위 밖이라 손대지 않았다.
  누군가 `core`를 만질 때 `<= 0`으로 맞추면 표시-판정 술어가 앱 전역에서 하나가 된다.
- **홈 탭의 "일시정지 중" 배지(`home_screen.dart:152`)** — 마이 탭과 같은 구조
  (`selectedPass.activeHold`만 보고 상태를 안 본다)지만 배지 전용(버튼 없음)이라 서버 거부와는
  무관하다. 동시 진행 중인 타 작업 영역이라 넘긴다. 마이 탭과 같은 이유로 상태 게이트를 붙이면
  표현이 일치한다.
- **홀딩 신청 후 서버 400 문구** — 사전 판정이 대부분을 잡지만, 정책이 방금 바뀐 경우 등
  경합에서는 여전히 서버 문구가 뜬다. 그건 정상 경로다(최종 검증은 서버).

## 참조

- `backend/internal/domain/pass.go` — `ValidateHoldWindow`(:78~), `ValidateNewHold`(:101~), `HoldDurationDays`(:136~), `ResumeHold`(:169~)
- `backend/internal/domain/policy.go` — `NormalizeHoldLimits`, `Validate`(무제한 -1 규약)
- `backend/internal/api/service.go` — `HoldPass`(:719~), `ResumePass`(:766~), `RefundPass`(:822~ 계약 voided 처리), `SignContract`(:2430~), `RefundQuote`(:799~)
- `backend/internal/api/util.go` — `friendlyDomainMessages`(서버가 회원에게 실제로 보내는 문구)
- 형제 갈래: `P12-app-booking-judgment.md`(이 작업의 출처 — "후속 작업" 2건), 부모 감사: `P12-audit-sweep.md`
