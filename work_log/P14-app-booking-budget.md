---
id: P14
title: 앱 예약 예산 판정(잔여 − 이미 잡힌 confirmed) ↔ P13 서버 계약 정합
status: 완료
domain: app
created: 2026-08-23
completed: 2026-08-23
---

# P14 — 앱 예약 예산 판정 ↔ 서버 계약 정합

## 목표

P13(저장 계층 원자성) H1이 `POST /v1/bookings`에 **새 거부 사유**를 만들었다:

```
생성 가능 = pass.remaining − (이 패스의 살아있는 confirmed 예약 수)
```

잔여는 완료 시점에만 차감되므로(P4) 예약을 잡아도 줄지 않는다 — 뺄셈이 없던 동안
잔여 2회 패스에 4건이 잡히고 4건이 완료돼 원장이 −2로 내려갔다. 서버가 그 구멍을
닫은 결과 **`remaining > 0`인데도 400이 나는 상태가 새로 생겼고**, 앱은 그걸 모른 채
"잔여 2회"라고 적힌 화면에 살아 있는 예약 버튼을 계속 띄우고 있었다.

직전 P12 갈래에서 `BookablePass.remaining`과 `NoRemainingSessions`가 들어왔지만
**확정 예약 수를 빼지 않는다** — 이번 서버 수정이 만든 딱 그만큼의 간극을 닫는다.

## 결정 사항

### 앱이 확정 건수를 셀 수 있는가 — 셀 수 있다(서버 변경 불필요)

관건은 "예약이 어느 패스에 속하는지 앱이 아는가"였다. 세 가지를 확인했다:

1. `domain.Booking`의 JSON에 `pass_id`가 있고, `ListBookings`는 슬롯(`ListSlots`)과
   달리 **회원 응답 최소노출 처리가 없다** — 마스킹 없이 그대로 내려온다.
2. 앱 `BookingDto`는 예전부터 `pass_id`를 파싱하고 있었다. 버려진 곳은 도메인 매핑
   (`MyBooking`) 한 곳뿐이었다.
3. 앱의 `GET /v1/bookings?member=`는 **`from` 없이** 부른다 = 서버
   `countOpenPassBookings`가 쓰는 `ListBookingsByMember`와 같은 모집단(지난 회차 포함).

→ 서버에 새 필드를 요청할 이유가 없다.

### 판정 순서 — 서버 `CreateBooking`의 자리를 그대로

서버는 `잔여 <= 0` 바로 다음, **시간축(과거·유효기간·홀딩·휴무일) 앞**에서 예산을 본다.
앱도 같은 자리에 넣었다: `status → 잔여 → 예약 예산 → 유효기간 → 홀딩 → 휴무일 → 슬롯`.
순서가 어긋나면 회원이 앱 안내대로 날짜를 옮기고 서버에서 또 거부당한다.

### 잔여 0과 "이미 다 잡아둠"은 **다른 상태로 분리**

같은 "예약 불가"지만 다음 행동이 정반대다.

| | 원인 | 다음 행동 |
|---|---|---|
| `NoRemainingSessions` | 실제 소진 | 재등록(센터 문의) |
| `AllRemainingBooked`(신규) | 회차는 남고 자리만 다 잡음 | **기존 예약 취소** |

뭉치면 이미 회차를 가진 회원에게 "재등록해주세요"= 돈을 더 내라는 안내가 된다.
잔여 숫자가 멀쩡히 보이는 상태라("잔여 2회인데 왜 안 되지") 문구는 두 숫자를 함께
말한다 — 행 `잔여 2회 · 예약 2건`, 안내 `남은 2회를 이미 잡아 둔 예약 2건이 모두 채웠어요`.

### `isSelectable`에는 예산을 **넣지 않았다** (판단이 갈린 지점)

일관성만 보면 `hasRemaining`처럼 `isSelectable`에 넣는 게 자연스럽다. 넣지 않은 이유:

- "잔여만큼 이미 잡아 둠"은 퇴사·환불·잔여 0과 달리 **성실한 회원의 정상 상태**다
  (잔여 10회를 10주치 고정으로 채운 회원이 곧 이 상태).
- `isSelectable`에 넣으면 "내 회원권 전체" 뷰의 패스 목록이 통째로 비고
  (`_AllCoachSlotRow`의 `passes.isEmpty` 분기), **그 회원이 이미 잡아 둔 자기 예약의
  "확정" 배지까지 사라진다** — 예약을 다 잡았다는 이유로 예약이 안 보이는 화면.

대신 `canBookNew = isSelectable && hasBookingBudget`를 따로 두고, **다음 행동을
안내하는 자리는 전부 이쪽을 본다**("다른 회원권으로 예약해주세요"가 예산 0인 패스를
가리키면 회원은 칩을 바꾸고 또 거부당한다).

### 고정 스케줄(`POST /v1/recurrings`) — 회원 앱에 노출 없음(확인만)

서버는 같은 예산 규칙을 걸지만 `CreateRecurring`은 `p.IsMember()`면 즉시 403이고,
앱 `lib/` 전체에 호출부가 없다(repository/data source에 메서드만 남아 있다).
`MyBooking.isRecurring`은 "고정" 배지 읽기 전용. 사전 판정할 자리 자체가 없어 코드
변경 없이 근거만 `booking_repository.dart` 주석에 남겼다. 반대 방향은 이미 맞다 —
고정이 만든 예약도 confirmed라 `countOpenBookings`가 그대로 센다.

## 진행 단계

- [x] 서버 실코드 판독(`service.go` `CreateBooking`·`countOpenPassBookings`·`CreateRecurring`,
      `store/memory.go`·`firestore.go`의 `BookAtomic` 재판정) — 문구가 아니라 계산식 기준
- [x] 앱이 패스별 confirmed를 셀 수 있는지 확인(계약·DTO·쿼리 3단 검증)
- [x] `MyBooking.passId` 복원 + `BookablePass.openBookings`/`bookingBudget`/`canBookNew`
- [x] `BookingRules.countOpenBookings` 신설, `evaluate`에 `AllRemainingBooked` 삽입(서버와 같은 자리)
- [x] 뷰모델 조립(같은 예약 목록으로 패스별 카운트) + repository 매핑
- [x] UI — 행 subtitle·코치 태그·상단 안내(잔여 0과 분리된 문구), 안내 우선순위 갱신
- [x] 테스트 30건 추가(경계·모집단·우선순위·문구 분리·확정 배지 보존)
- [x] 뮤테이션 13/13 kill
- [x] `flutter analyze` 0 · `flutter test` 600/600
- [x] (추가 과제) 예약 테스트 픽스처 시간축을 KST로 정렬 — 5개 TZ 동일 결과

## 변경 파일

| 파일 | 내용 |
|---|---|
| `lib/features/booking/domain/booking_models.dart` | `MyBooking.passId` 복원, `BookablePass.openBookings`(required)·`bookingBudget`·`hasBookingBudget`·`canBookNew` |
| `lib/features/booking/domain/booking_rules.dart` | `AllRemainingBooked` 상태, `countOpenBookings`, `evaluate`에 예산 판정(잔여 다음·시간축 앞) |
| `lib/features/booking/domain/booking_repository.dart` | 계약 주석 갱신(예산 규칙·고정 스케줄 미러 근거) |
| `lib/features/booking/data/booking_repository_impl.dart` | `pass_id` 도메인까지 매핑 |
| `lib/features/booking/presentation/booking_view_model.dart` | 같은 예약 목록으로 패스별 `openBookings` 조립 |
| `lib/features/booking/presentation/widgets/slot_list.dart` | 행·태그·`_AllBookedNotice`, 안내 판정을 `canBookNew` 기준으로, 우선순위에 신규 상태 삽입 |
| `test/features/booking/domain/booking_rules_test.dart` | 예산 경계·모집단·거부 순서 12건 |
| `test/features/booking/domain/booking_models_test.dart` | 예산 게터·`isSelectable` 비포함 근거 4건 |
| `test/features/booking/data/booking_repository_impl_test.dart` (신규) | `pass_id` 생존·모집단(`from` 없음)·취소 제외 4건 |
| `test/features/booking/presentation/booking_view_model_test.dart` (신규) | 조립 지점(예산이 0으로 죽지 않는지) 2건 |
| `test/features/booking/presentation/widgets/slot_list_test.dart` | 문구 분리·확정 배지 보존·안내 우선순위 8건 + 픽스처 KST 정렬 |
| `test/features/booking/presentation/booking_screen_test.dart` | 픽스처 KST 정렬 |
| `test/core/widgets/long_label_overflow_test.dart` | `MyBooking.passId`, 픽스처 KST 정렬 |

## 계약

서버 변경 없음. 앱이 기존 응답(`Booking.pass_id`)을 다시 읽기 시작했을 뿐이다.

## 검증

- `flutter analyze` — 0 issues
- `flutter test` — **600 passed** (착수 시 570 → +30, 회귀 0)
- 시간대 5종(`UTC` / `America/New_York` / `Pacific/Auckland` / `Pacific/Honolulu` /
  `Asia/Seoul`) 전부 600/600 동일

### 뮤테이션 13/13 kill

| 변이 | 죽인 테스트 |
|---|---|
| 예산 검사 제거(옛 동작 복귀) | 경계 — 잔여 2·확정 2면 불가 |
| 경계 `> 0` → `>= 0` | 같음 |
| `countOpenBookings` status 필터 제거 | 취소·완료·노쇼·대기는 세지 않는다 |
| `countOpenBookings` pass 필터 제거 | 이 패스의 confirmed만 센다 |
| 예산 판정을 유효기간 뒤로 이동 | 예산 소진이 유효기간·홀딩·휴무보다 먼저 |
| `isSelectable`에 예산 추가 | 다 잡아 뒀어도 이미 잡힌 내 예약은 "확정" 그대로 |
| `_hasOtherBookablePass`를 `isSelectable`로 | 다른 회원권도 다 잡아 뒀으면 그쪽을 권하지 않는다 |
| 잔여 0 안내로 뭉치기 | 다음 행동은 재등록이 아니라 기존 예약 취소 |
| 잔여 0 안내 억제 판정을 `isSelectable`로 | 잔여 0과 함께 막혔으면 잔여 0을 먼저 말한다 |
| 퇴사 안내 억제 판정을 `isSelectable`로 | 퇴사와 함께 막혔으면 퇴사를 먼저 말한다 |
| repository가 `pass_id`를 버림 | `pass_id`가 도메인까지 살아서 온다 |
| 뷰모델이 `openBookings`를 0으로 고정 | 내 예약 목록의 confirmed 건수가 패스별로 실린다 |

## 후속 작업

- **`isSelectable`의 `hasRemaining`도 같은 함정을 갖고 있다**(잔여 0 패스가 필터로
  빠지면 "내 회원권 전체" 뷰에서 그 패스로 잡아 둔 예약의 "확정" 배지가 사라진다).
  이번엔 범위를 넘어 손대지 않았다 — 예산과 달리 잔여 0에서 미래 예약이 남아 있는
  조합은 드물다(취소 시 무차감 반환이라 보통 잔여가 먼저 회복된다). 별도 판단 필요.
- 회원 앱에 고정 스케줄 생성 경로가 열리면 `evaluate`와 같은 판정을 `createRecurring`
  앞에도 미러해야 한다(근거는 `booking_repository.dart` 주석).

## 참조

- `backend/internal/api/service.go` — `CreateBooking`, `countOpenPassBookings`, `CreateRecurring`
- `backend/internal/store/memory.go` / `firestore.go` — `BookAtomic` 안의 재판정
- [P13 — 저장 계층 원자성](P13-store-atomicity.md) (H1이 이 계약을 만들었다)
- [P12 — 앱 예약 판정 ↔ 서버 계약 정합](P12-app-booking-judgment.md) (잔여 0·휴무일·환불 판정)
