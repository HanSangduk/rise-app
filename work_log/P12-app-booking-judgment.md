---
id: P12
title: 앱 예약 판정 ↔ 서버 계약 정합(잔여·취소·휴무일·패스 상태)
status: 완료
domain: app
created: 2026-08-23
completed: 2026-08-23
---

# P12 — 앱 예약 판정 ↔ 서버 계약 정합

## 목표

P12 감사(앱팀 — 백엔드 도메인 소스와 판정식 대조)가 찾은 **예약 판정이 서버 계약과 어긋나는 결함**을
고친다. 공통 증상은 두 방향이다:

- 서버가 **100% 거부할 액션**에 살아 있는 버튼이 뜬다(잔여 0 · 휴무일 · 환불 패스).
- 서버가 **일부러 열어 둔 액션**을 앱이 막는다(컷오프 지난 취소).

## 결정 사항

### 1. 판정 순서를 `CreateBooking`의 거부 순서에 그대로 맞췄다

`BookingRules.evaluate`는 이제 status → 잔여 → 유효기간 → 홀딩 → 휴무일 → 슬롯 사정 순으로 본다
(`AlreadyBookedByMe`만 예외적으로 맨 앞 — "새 예약 가능 여부"가 아니라 이미 확정된 사실이다).
두 제약이 겹칠 때 앱이 서버와 다른 이유를 안내하면, 회원은 안내대로 고쳐도 또 거부당한다.

### 2. `evaluate`가 인자 나열 대신 `BookablePass`를 통째로 받는다

원인이 여기였다. 예전 시그니처는 `passValidFrom`/`passValidUntil`/`holds`만 받았고, **서버가 반드시
검사하는 잔여(remaining)가 판정에서 통째로 빠져 있어도 컴파일이 통과했다**. 실제로 뷰모델이
`home.passes`의 `PassOption`(잔여 보유)을 `BookablePass`로 옮기며 잔여를 버렸다.
모델이 필드를 들고 판정이 그 모델을 읽게 하고, `remaining`은 **기본값 없는 필수 인자**로 뒀다 —
기본값을 주면 같은 누락이 다시 조용히 통과한다.

### 3. 잔여 0은 엣지케이스가 아니라 모든 회원의 종착 상태다

백엔드에 패스를 `expired`로 넘기는 코드가 **없다**(`PassStatusExpired`는 통계에서 읽기만 한다).
20회를 다 쓴 패스도 유효기간이 남는 한 영원히 `active`로 온다. 즉 status만 보는 필터로는 절대
걸러지지 않고, 회원 전원이 언젠가 "눌리는데 100% 실패하는 예약 버튼"에 도달한다.
그래서 퇴사 코치와 **같은 처방**을 적용했다 — 행은 숨기지 않고(숨기면 이유를 알 길이 없다) 버튼을
죽이고, 이유와 다음 행동은 목록 상단에서 한 번만.

### 4. 취소는 항상 열어 두고, 컷오프는 **문구만** 가른다

백엔드 `CancelBooking` 주석이 명시적이다 — *"취소 자체는 항상 허용한다(막으면 노쇼로 위장할 유인만
커짐)"*. `CancelAtomic`은 무조건 실행되고 컷오프 경과는 원장 페널티(정책상 최초 1회 유예)만 붙인다.
앱이 그 문을 닫으면 회원에게 남는 선택지는 **노쇼뿐**이다 — 차감은 똑같이 일어나고 코치는 통보조차
못 받는다. 같은 카드의 "취소는 N시간 전까지 무료예요" 문구와도 모순이었다.

`BookingRules.canCancel` → **`isFreeCancel`로 개명**했다. 이름이 곧 오독의 원인이었다("취소 가능?"으로
읽혀 버튼을 감췄다). 홈의 `NextBooking.canCancel`도 `freeCancel`로 함께 바꿨다.

**유예 잔여는 앱이 모른다** — 그 판정은 원장 이력(noshow / noshow_waived 존재 여부)에 달려 있는데
예약 탭은 원장을 로드하지 않는다(마이 탭 몫). 그래서 "유예돼요"라고 단정하지 않고 두 경우를 다 말하고
(*"최초 1회는 유예되지만, 이미 유예를 받았다면 이번엔 차감돼요"*) 확인처를 마이 탭으로 안내한다.
정책이 유예를 끄면(`policy.grace_once=false`) 그 문장 자체를 뺀다 — 그래서 `CenterPolicy`에
`graceOnce`를 추가했다(DTO엔 이미 있었고 도메인 모델에서만 버려지고 있었다).

### 5. "payout/offdays는 원장·트레이너 전용" 주석이 틀렸다

`ListStaff`는 role=member 응답에서 **payout만 비우고**(그리고 퇴사자 profile만 마스킹하고) offdays는
그대로 내려준다. 그 전제를 믿고 파싱조차 안 해서, 서버가 400("담당 코치의 휴무일이에요")으로 거부할
슬롯이 앱에선 정상 "예약 가능"으로 보였고 확정 시트까지 간 뒤에야 거부됐다.

휴무일은 **문자열("YYYY-MM-DD") 그대로** 들고 비교한다 — 백엔드도 슬롯 날짜를 같은 포맷으로 찍어
`containsStr(st.Offdays, slotDate)`로 대조하므로, 파싱 왕복 없이 같은 판정을 한다. 느슨하게 맞추면
(예: `2026-8-14`도 허용) 앱만 막고 서버는 통과하는 **반대 방향 불일치**가 생긴다.

### 6. 휴무일을 홈 repository에서 해석한다 — 예약 뷰모델이 아니라

처음엔 예약 뷰모델이 `staffMapReader`를 직접 읽게 했는데, 그러면 예약 탭 로드가 스태프 조회를
한 번 더 기다리게 되고(홈이 이미 기다린 것을) 같은 사실의 출처가 둘로 갈린다 — 퇴사 여부에서
이미 겪은 문제다. 이름·퇴사 여부를 해석하는 바로 그 자리(`HomeRepositoryImpl`)에서 offdays도 함께
해석해 `PassOption`에 싣고, 예약 뷰모델은 다른 필드처럼 전달만 한다. 새 await가 늘지 않는다.

### 7. `isUsable`을 active 하나로 좁혔다(잠재 결함 정리)

앱은 `active || scheduled`를 "쓸 수 있음"으로 봤지만 서버는 예약(`CreateBooking`)도
홀딩(`HoldPass`)도 `PassStatusActive`만 통과시킨다. 백엔드가 scheduled를 한 번도 쓰지 않아
(CreatePass는 항상 active) 드러나지 않던 잠재 결함이다.

정리하다 보니 **실제로 발생 중인** 형제 결함이 나왔다: **refunded 패스**는 환불 플로우가 실제로
만들고 유효기간이 남아 있을 수 있는데, 그게 대표 패스면 "내 코치" 모드에 살아 있는 예약 버튼이
떴다(`PassExpiredForSlot`은 유효기간만 보므로 못 잡는다). `PassNotUsable` 상태를 신설해 함께 막았다.

### 자문자답

- **행을 숨길까?** 아니다. 숨기면 회원은 빈 화면만 보고 왜 안 되는지·다음에 뭘 할지 알 수 없다.
  기존 퇴사 코치 처리와 같은 원칙(행 유지 + 버튼 비활성 + 상단 안내 1회).
- **안내를 여러 개 띄울까?** 아니다. 한 번에 하나만, "풀기 어려운 것"부터 — 퇴사(센터 문의) →
  잔여 0(재등록) → 휴무(날짜 변경). 겹쳐 띄우면 정작 다음 행동이 흐려진다.
- **휴무 안내를 "내 회원권 전체" 모드에도?** 아니다. 휴무는 코치별 사정이라 한 문장으로 뭉칠 수
  없다. 그 모드는 코치 태그가 패스마다 "○○ 휴무"로 말한다.
- **상단 안내 조건을 손으로 다시 쓰면?** 유효기간·홀딩이 함께 걸린 날에 행은 "8/10까지"라 하고
  상단은 "휴무"라 하는 모순이 난다. 휴무 안내는 **같은 규칙 엔진에 빈 슬롯 하나를 물어**서 판정한다
  (회귀 테스트로 고정).
- **잔여 0인데 이미 잡힌 예약은?** 예약 시점에 이미 차감된 자리다. `AlreadyBookedByMe`가
  맨 앞이라 "확정" 그대로 — 덮으면 확정된 수업이 취소된 것처럼 보인다.
- **잔여가 음수로 오면?** 서버 판정이 `<= 0`이라 거부다. `== 0`으로 짰으면 갈렸을 자리(테스트로 고정).

## 진행 단계

- [x] 백엔드 소스 대조(`service.go` CreateBooking/CancelBooking/ListStaff, `domain/pass.go`, `domain/staff.go`)
- [x] CRITICAL 1 — `BookablePass.remaining` 신설(필수) + `NoRemainingSessions` 판정 + UI(행/상단 안내)
- [x] HIGH 8 — `StaffDto.offdays` 파싱 + `PassOption`/`BookablePass` 배선 + `TrainerOffday` 판정 + UI
- [x] HIGH 4 — 취소 상시 허용 + `canCancel`→`isFreeCancel` 개명 + 결과 고지 확인 다이얼로그 + 홈 카드 자물쇠 제거
- [x] MEDIUM 13 — `isUsable`을 active로 좁힘 + `PassNotUsable` 신설(refunded 실발생 케이스 포함)
- [x] 테스트 추가(도메인 경계값 + 위젯 + 취소 플로우) · 뮤테이션 검증
- [x] `flutter analyze` 0 · `flutter test` 472 통과

## 변경 파일

**판정·모델(앱)**
- `app/lib/features/booking/domain/booking_models.dart` — `remaining`(필수)·`trainerOffdays` 추가,
  `isUsable` active 전용, `hasRemaining`·`isTrainerOffday` 신설, `isSelectable`에 잔여 반영
- `app/lib/features/booking/domain/booking_rules.dart` — `evaluate`가 `BookablePass`를 받도록 변경,
  `PassNotUsable`/`NoRemainingSessions`/`TrainerOffday` 상태 신설(서버 거부 순서대로),
  `canCancel` → `isFreeCancel` 개명 + 사용 규약 문서화

**배선**
- `app/lib/core/api/dto/staff_dto.dart` — `offdays` 파싱(+ 틀린 "회원 응답엔 없다" 주석 정정)
- `app/lib/features/home/domain/home_models.dart` — `PassOption.trainerOffdays`,
  `NextBooking.canCancel` → `freeCancel`
- `app/lib/features/home/data/home_repository_impl.dart` — offdays 해석, `isFreeCancel` 호출
- `app/lib/features/booking/presentation/booking_view_model.dart` — `remaining`·`trainerOffdays` 전달
- `app/lib/core/policy/center_policy.dart`, `center_policy_provider.dart` — `graceOnce` 추가

**UI**
- `app/lib/features/booking/presentation/widgets/slot_list.dart` — 새 상태 렌더,
  `_NoRemainingNotice`·`_OffdayNotice` 신설, 안내 우선순위 단일화, `selectedDate` 입력 추가
- `app/lib/features/booking/presentation/widgets/my_bookings_list.dart` — 취소 버튼 상시 노출,
  하단 안내 문구 정정("이후엔 세션 1회가 차감돼요")
- `app/lib/features/booking/presentation/booking_screen.dart` — 컷오프 경과 시 결과 고지 확인 문구
- `app/lib/features/home/presentation/widgets/next_booking_card.dart` — 자물쇠 "취소 마감" 칩 제거

**테스트**
- `app/test/features/booking/domain/booking_rules_test.dart` — 잔여/휴무/패스상태/우선순위 그룹 추가(경계값 포함)
- `app/test/features/booking/domain/booking_models_test.dart` — `isSelectable`·`isTrainerOffday`
- `app/test/features/booking/presentation/widgets/slot_list_test.dart` — 잔여 0·휴무·환불 UI
- `app/test/features/booking/presentation/cancel_flow_test.dart` — **신규**, 취소 상시 허용 + 문구
- `app/test/core/api/dto/staff_dto_test.dart` — offdays 파싱

## 검증

- `flutter analyze` — No issues found
- `flutter test` — 472 passed
- **뮤테이션 검증 4종, 전부 kill**
  | 뮤테이션 | 잡은 테스트 |
  |---|---|
  | `evaluate`에서 잔여 판정 제거 | 6건 (도메인 4 + 위젯 2) |
  | `evaluate`에서 휴무일 판정 제거 | 5건 (도메인 3 + 위젯 2) |
  | 컷오프 지난 취소 버튼을 "확정" 배지로 되돌림 | 5건 (cancel_flow) |
  | `isUsable`에 scheduled 복원 | 2건 |
  복구 후 재검증 완료(analyze 0 / 예약·홈·코어 252 통과).

## 후속 작업

- **MEDIUM 12(홀딩 상한 사전 검증) 미착수** — 전부 `features/my`(hold_request_sheet·pass_list)에 있고
  예약 쪽엔 홀딩 생성 경로가 없다. 작업 중 확인해 보니 마이 탭 담당이 같은 파일에서 상한 노출
  ("N회 중 M회를 썼어요")을 이미 작업 중이라 충돌을 피해 넘긴다. 남은 일은 `_submit()` 전에
  `domain.ValidateNewHold`와 같은 판정(과거 홀딩 횟수 + 총 일수)을 클라이언트에서 먼저 보는 것.
- **`hold_request_sheet`의 `isActive || isScheduled` 후보 필터** — 서버 `HoldPass`는 active만 받는다.
  MEDIUM 13과 같은 결함의 마이 탭 쌍이고, 위와 같은 이유로 넘긴다.
- **scheduled 상태 표시** — `isUsable`을 좁힌 결과, 만약 서버가 언젠가 scheduled를 쓰기 시작하면
  "내 회원권 전체" 모드에서 그 패스는 선택지에서 빠지고 상단 안내는 침묵한다(만료·환불과 동일한
  기존 갭). 백엔드가 scheduled를 실제로 쓰게 되는 시점에 안내 문구를 함께 정하면 된다.

## 참조

- `backend/internal/api/service.go` — `CreateBooking`(:1075~), `CancelBooking`(:1170~), `ListStaff`(:2344~), `HoldPass`(:709~)
- `backend/internal/domain/pass.go` — `PassStatus*`, `ValidateNewHold`
- `backend/internal/domain/staff.go` — `Staff.Offdays`
- P12 부모 감사: `P12-audit-sweep.md`
