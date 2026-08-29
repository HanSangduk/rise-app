---
id: P16
title: 시각 판정이 로드 시점에 굳는 결함(셀프 체크인·취소 컷오프·"지남"·D-day)
status: 완료
domain: app
created: 2026-08-23
completed: 2026-08-23
---

# P16 — 시각 판정이 로드 시점에 굳는 결함

## 목표

실기기 실측(갤럭시 S21, 운영 서버)에서 나온 결함:

1. 19:00 예약. 18:26에 홈을 열면 셀프 체크인 버튼 비활성 + "셀프 체크인은 수업 시작
   전후 30분에 열려요".
2. 앱을 켜 둔 채 18:32까지 기다린다(창은 18:30~19:30이므로 **이미 열려 있어야 한다**).
3. 버튼은 여전히 회색이고 눌러도 아무 일이 없다.
4. 당겨서 새로고침해야 열린다.

회원이 겪는 일: 18:25에 도착 → 회색 버튼과 "30분 전부터 열려요"를 보고 로비에서
기다림 → 18:35에도 회색 → 새로고침해야 한다는 걸 알 방법이 없으니 데스크로 감.
**셀프 체크인이 없애려던 바로 그 왕복이다.**

원인은 버튼 하나가 아니라 **설계 패턴**이다: 시각에 의존하는 값을 repository가
로드 시점에 계산해 모델의 bool 필드에 담았다. 그 값은 다음 재조회까지 굳는다.
같은 클래스를 전수로 찾아 손해가 큰 것부터 닫는 게 이 P의 범위다.

## 결정 사항

### 1. 스냅샷 필드 → `now`를 받는 파생 계산 (근본 수정)

`NextBooking.canCheckIn` / `.freeCancel` **필드를 없앴다.** 모델은 `startAt`만 들고
가고, 판정은 `canCheckInAt(now)` / `isFreeCancelAt(now, cutoffHours:)` /
`isTodayAt(now)`로 옮겼다. `HomeRepository.loadHome`의 `cancelCutoffHours` 인자도
함께 제거 — 정책값은 화면이 `centerPolicyProvider`에서 직접 읽는다.

파급(테스트 fake 6곳 + 호출 4곳)을 감수한 이유: 필드로 두는 한 "언제 계산했는가"가
화면에서 보이지 않아 같은 결함이 조용히 되돌아온다. 지금은 `now` 없이는 판정 자체가
불가능하다 — 타입이 강제한다.

`HomeViewModel.build()`의 `await ref.watch(centerPolicyProvider.future)`는 값을
안 쓰지만 **남겼다**: 카드가 정책을 직접 읽는데 홈 데이터가 먼저 도착하면 컷오프
문구가 폴백 24시간으로 한 프레임 떴다가 실값으로 바뀐다.

### 2. 재평가 트리거 — 주기 폴링이 아니라 경계 일회성 타이머

새 위젯 `core/widgets/time_boundary_builder.dart`.

- **경계 시각에 딱 한 번씩만 깨운다.** 창 열림(시작 −30분)·닫힘(+30분)·컷오프
  (시작 −N시간)는 전부 미리 계산 가능한 시각이다. 1분 티커는 경계에서 최대 59초
  늦고 아무 일 없는 분에도 시간당 60번 리빌드한다.
- **`atMidnight` 플래그**는 매 예약 시점의 `now`에서 "다음 자정"을 새로 계산한다.
  경계 목록에 자정을 하나 넣는 방식이면 **하루만 넘고 이튿날부터 다시 굳는다.**
- **보이지 않으면 타이머를 놓는다.** 탭은 `StatefulShellRoute.indexedStack`이라
  떠나도 위젯이 살아 있다. 하드웨어팀이 카메라·센서에 쓴
  `TickerMode.valuesOf(context).enabled`(camera_screen.dart)를 그대로 재사용 —
  InheritedWidget이라 탭 복귀가 곧 리빌드다.
- **앱 재개(`resumed`)에도 재평가.** 회원이 앱을 백그라운드에 두고 기다리는 쪽이 더
  흔하고, OS가 재우는 동안 타이머는 제때 깨지 않는다.

### 3. 재평가는 로컬 계산 — 서버를 다시 부르지 않는다

창이 열렸다고 홈을 재조회하면 예약 있는 모든 회원이 창이 열릴 때마다 **5~6 왕복**을
낸다. 바뀐 건 시계뿐이고 예약 사실은 그대로다.

"그 사이 예약이 데스크에서 취소됐으면?" — 그 경우 체크인 POST를 서버가 정확히
거절한다(`findUpcomingBooking`이 confirmed만 훑고, 없으면 400 "시간창 안의 예약을
찾을 수 없음"). 회원이 **실제로 누를 때 한 번** 왕복하는 쪽이 싸고 결과도 같다.
앱 안에서 한 취소는 예약 탭이 이미 `homeViewModelProvider`를 invalidate한다.

### 4. 시계 주입 — `package:clock`

`DateFmt.nowKst()`를 `toKst(clock.now())`로 바꿨다. `clock.now()`의 기본값이 곧
`DateTime.now()`라 운영 동작은 그대로고, 테스트만 `withClock`으로 "지금"을 고정한다.
존 스코프라 전역 가변 훅과 달리 테스트 간 누수가 없고, 위젯 테스트의
`tester.pump(duration)`과도 함께 쓰인다(프로브로 확인).

### 5. 고친 범위 — 회원이 실제로 손해 보는 것

| 대상 | 굳은 결과 | 고침 |
|---|---|---|
| 셀프 체크인 창 | 창이 열려도 회색 → 데스크 왕복 → 노쇼 시 1회 차감 | ✅ 파생 + 경계 타이머 |
| 무료 취소 컷오프 문구(홈 카드) | "24시간 전까지 무료"가 컷오프 후에도 남음 → 차감 | ✅ 파생 + 경계 타이머 |
| 예약 탭 "지남" | 지난 슬롯에 살아 있는 "예약" 버튼 → 눌러야 400을 받는다 | ✅ 슬롯 시작 시각 경계 |
| 유효기간 D-day · 홀딩 배지(홈) | 자정을 넘겨도 "D-1" → 마지막 날을 놓치면 잔여 회차 전액 소멸 | ✅ `atMidnight` |
| '오늘' 배지 | 자정 경계 오표기 | ✅ `atMidnight`(같은 카드) |

### ⚠ 정정 — "서버도 지난 슬롯을 받아 준다"는 틀렸다

작업 중 "예약 탭 지남" 항목의 근거를 **서버가 지난 슬롯 예약을 수락한다**로 적었는데,
사실이 아니다. `internal/api/service.go`의 `CreateBooking`이 첫 검증으로 막는다:

```go
start, err := domain.SlotStart(req.SlotKey)
if start.Before(time.Now()) {
    return nil, errors.Join(errBadRequest, errors.New("이미 지난 시간이에요"))
}
```

즉 13:55에 열어 둔 화면의 14:00 슬롯을 14:05에 눌러도 **confirmed가 되지 않는다** — 400이다.
따라서 "노쇼 1회 차감 + 예약 예산 잠식"은 **일어나지 않는다.** 회원이 겪는 실제 손해는
"눌러야 거부당한다"는 헛클릭 하나뿐이다.

고친 것 자체는 유효하다(서버가 거부할 버튼을 살려 두지 않는다 — 이 코드베이스가 잔여 0·휴무일·
환불 패스에서 반복해 세운 원칙 그대로). 다만 **심각도는 돈이 아니라 UX**이고, 근거를 그대로
두면 다음 사람이 "서버에 지난 시각 가드가 없다"고 믿고 잘못된 곳을 파게 된다.

교훈: 클라이언트 결함의 심각도를 서버 동작 추정 위에 세우지 말 것 — 서버 코드를 열어 확인해야 한다.

## 진행 단계

- [x] 실기기 재현 경로 확인(홈 카드 → repository → 모델 필드)
- [x] 전수 조사 — `nowKst`/`todayKst`/`DateTime.now()` 호출 22곳 분류(굳음/파생/액션순간)
- [x] `package:clock` 도입 + `DateFmt.nowKst()` 배선, 위젯 테스트 프로브로 zone 도달 확인
- [x] `CheckinRules` 신설(서버 `domain.CheckinWindow` 거울), `NextBooking` 파생화
- [x] `TimeBoundaryBuilder` 신설 + `NextBookingCard`·`SlotList`·홈 회원권 카드 적용
- [x] `loadHome`에서 `cancelCutoffHours` 제거 + fake 6곳·호출 4곳 정리
- [x] 테스트 신규 2파일 + 기존 2파일 보강, KST 축 테스트를 판정과 함께 이전
- [x] 뮤테이션 6종 검증(1건 생존 → 코드·테스트 보강 후 전부 kill)
- [x] `flutter analyze` 0 + TZ 4종 전량 통과

## 변경 파일

**신규**
- `app/lib/core/widgets/time_boundary_builder.dart` — 경계 재평가 위젯
- `app/lib/features/home/domain/checkin_rules.dart` — ±30분 창(서버 거울)
- `app/test/core/widgets/time_boundary_builder_test.dart` — 8건
- `app/test/features/home/presentation/widgets/next_booking_card_test.dart` — 18건

**수정**
- `app/pubspec.yaml` — `clock: ^1.1.2`(2026-08-23 pub.dev 확인)
- `app/lib/core/utils/date_format.dart` — `nowKst()` → `clock.now()`, 시간축 주석 보강
- `app/lib/features/home/domain/home_models.dart` — `NextBooking` 파생화
- `app/lib/features/home/domain/home_repository.dart` · `data/home_repository_impl.dart` ·
  `presentation/home_view_model.dart` — `cancelCutoffHours` 제거, 굳던 계산 삭제
- `app/lib/features/home/presentation/widgets/next_booking_card.dart` — 경계 재평가
- `app/lib/features/home/presentation/home_screen.dart` — 회원권 카드 `atMidnight`
- `app/lib/features/booking/presentation/widgets/slot_list.dart` — "지남" 경계 재평가
- 테스트 fake·호출 정리 10곳, `home_kst_axis_test.dart`·`slot_list_test.dart` 보강

## 계약

**서버 계약 변경 없음.** `CheckinRules`는 `backend/internal/domain/checkin.go`의
`CheckinWindow = 30 * time.Minute`과 닫힌 구간 `[start−30m, start+30m]`을 그대로
미러한다(초 단위 비교 — `inMinutes` 절삭은 30분 0~59초 구간을 열어 보이게 한다).

## 검증

- `flutter analyze` — **이슈 0**
- `flutter test` — **625건 전량 통과**(작업 전 600건대 그린 유지, 회귀 0)
- TZ 4종 전량 통과: `UTC` / `Pacific/Honolulu` / `Pacific/Auckland` / `Asia/Seoul`
- 뮤테이션 6/6 kill:
  | # | 뮤테이션 | 결과 |
  |---|---|---|
  | 1 | 경계 타이머 미예약 | 9건 사망(3파일 전부) |
  | 2 | `resumed` 재평가 제거 | 1건 사망 |
  | 3 | `TickerMode` 게이팅 제거 | 2건 사망 |
  | 4 | `atMidnight`를 1회성 고정 자정으로 | **초회 생존** → 스케줄러에 `isAfter(now)` 가드 추가 후 1건 사망 |
  | 5 | `nowKst()` → `DateTime.now()` | TZ=UTC 11건 / TZ=Asia/Seoul 10건 사망 |
  | 6 | `CheckinRules` 초→분 절삭 | **초회 생존** → "30분 30초" 경계 테스트 추가 후 1건 사망 |

## 후속 작업

전수 조사에서 나온 **같은 클래스, 이번에 안 고친 것**(위험도순):

1. **`SelectedBookingDate`(booking_view_model.dart:36)** — `@riverpod`의 초기 state가
   `DateFmt.todayKst()`. 예약 탭이 indexedStack에 상주해 구독이 안 끊기므로 **앱
   프로세스 수명 내내 갱신되지 않는다.** 자정을 넘기면 선택 날짜가 어제로 남아
   날짜 칩이 하나도 선택되지 않고, 슬롯 13칸이 전부 "지남"이 된다 — 앱을 완전히
   재시작하기 전엔 예약 자체가 불가. **남은 것 중 영향이 가장 크다.**
   (돈은 안 걸렸지만 기능 전면 마비. 자정 롤오버 시 `selectedDate < todayKst()`면
   오늘로 당기는 게 후보 — 회원이 과거 날짜를 고를 경로는 없으므로 안전하다.)
2. **Home Work 자정 넘김(읽기/쓰기 축 불일치)** — 읽기는
   `home_repository_impl.dart:129`에서 굳고 쓰기는 `home_view_model.dart:113`이 그때
   시계를 읽는다. 23:50에 홈을 열고 00:05에 체크하면 **어제 목록으로 만든 done 배열이
   오늘 날짜 문서를 통째로 덮는다**(`store.SaveHwCheck`는 `.Set()`). 배정 항목 수가
   다르면 인덱스가 어긋난다. 데이터 파손이라 우선순위는 높지만, 고치려면 "자정에
   Home Work 섹션을 재조회"가 필요해 이 P의 "왕복 0" 원칙과 갈린다 — 별도 판단 필요.
3. **마이 탭 홀딩 배지 + "재개" 버튼**(`my_models.dart:61` → `pass_list.dart:100`) —
   홀드 마지막 날 자정을 넘겨도 재개 버튼이 살아 있어 서버 `ResumePass`가 거부한다.
   되돌릴 수 없는 액션(1회 소진)의 확인 다이얼로그가 굳은 판정 위에 뜬다.
   홈 회원권 카드와 같은 처방(`atMidnight`)이면 닫힌다.
4. **홈 "다음 예약" 지난 예약 필터**(`home_repository_impl.dart:98`) — 시작 1시간 뒤까지
   남기는 건 의도지만, 그 뒤로도 재조회 전엔 안 사라진다. 자리를 채울 다음 예약
   정보가 서버에서 와야 하므로 왕복 없이는 못 고친다.
5. **기록 탭 주 경계**(`records_repository_impl.dart:61`) — 일요일 23:50 로드가 월요일
   00:00 이후에도 "이번 주"로 남는다. 금전 손해 없음.
6. **`my_bookings_list.dart:57`** — 다가오는 예약 필터(3시간 버퍼)가 굳어 지난 예약의
   취소 버튼이 남는다. 다이얼로그가 차감을 정확히 고지하므로 위험은 낮다.
7. **`hold_request_sheet.dart:94`** — 시트를 열어 둔 채 자정을 넘기면 `HoldStartsInPast`가
   안 떠 신청 버튼이 살아 있고 서버 400.
8. **`booking_screen.dart:330` 취소 확인 다이얼로그** — 탭 순간 계산이라 안전하지만,
   다이얼로그를 열어 둔 채 컷오프를 넘기면 무차감 문구를 읽고 확인하게 된다. 창이
   좁아 순위는 낮다.
9. **`date_strip.dart:18` · `camera_screen.dart:135`** — 표기 오차 수준.

기타:
- `TimeBoundaryBuilder`는 웹을 고려하지 않았다. JS `setTimeout`은 ~24.8일에서
  포화하므로, 웹 포팅 시 예약 지연에 상한(예: 24시간)을 걸어야 한다. 현재는
  `atMidnight`가 카드 경계를 24시간 이내로 묶고, 슬롯 경계는 날짜 스트립 14일 안이라
  모바일에서는 문제가 없다.
- TZ 4종 실행은 여전히 **사람이 손으로 하고 주석에 기록**한다 — CI가 없다.
  `.github/workflows`가 생기면 `TZ` 매트릭스를 강제하는 게 맞다.

## 참조

- 서버 원본: `backend/internal/domain/checkin.go`(`CheckinWindow`),
  `backend/internal/api/service.go`(`Checkin` self_qr 분기 · `findUpcomingBooking`)
- 선례: `app/lib/features/bodycheck/presentation/camera_screen.dart`
  (`TickerMode.valuesOf` + `WidgetsBindingObserver` — 하드웨어 수명주기, P11)
- 시간축 규약: `app/lib/core/utils/date_format.dart` 클래스 주석,
  P12 갈래 [앱 시간축(KST) 정렬](P12-app-time-axis-records.md)
- 컷오프 판정의 뜻(취소는 항상 열려 있다): [P12 앱 예약 판정](P12-app-booking-judgment.md),
  [P14 센터 정책 진실성](P14-center-policy-truth.md)
