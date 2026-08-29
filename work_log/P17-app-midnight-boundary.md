---
id: P17
title: 자정 경계 잔여 결함(예약 탭 마비 · Home Work 문서 덮어쓰기 · 홀딩 배지)
status: 완료
domain: app
created: 2026-08-23
completed: 2026-08-23
---

# P17 — 자정 경계 잔여 결함

## 목표

[P16](P16-app-time-frozen-judgments.md)이 "시각 판정이 로드 시점에 굳는" 클래스를 닫으면서
전수 조사로 찾아 두고 범위 밖이라 남긴 것들 중, **자정 경계**에 걸린 것을 마무리한다.
P16의 도구(`TimeBoundaryBuilder`의 `atMidnight` 플래그, `package:clock`)를 그대로 쓴다.

우선순위대로 넷:

1. **예약 탭이 자정 이후 통째로 못 쓰는 화면이 된다**(기능 전면 마비)
2. **Home Work 자정 경계에서 어제 목록이 오늘 문서를 덮는다**(조용한 데이터 손실)
3. 마이 탭 홀딩 배지 + 재개 버튼이 자정에 굳는다
4. 취소 확인 다이얼로그를 열어 둔 채 컷오프를 넘기면 무차감 문구를 읽고 확인하게 된다

## 결정 사항

### 1. 예약 탭 — 선택 날짜를 **당긴다**(되돌리지 않는다)

`SelectedBookingDate`의 초기 state는 `todayKst()`인데, 예약 탭이
`StatefulShellRoute.indexedStack`에 상주해 구독이 끊기지 않으므로 `build()`가 **앱 프로세스
수명 내내 한 번만** 돈다. 자정을 넘긴 회원이 보는 것:

- `DateStrip`은 매 build마다 `todayKst()`부터 14일을 그리는데 선택 날짜는 어제 →
  **선택된 칩 0개**
- 뷰모델은 어제 날짜로 슬롯을 로드 → **13칸 전부 "지남"**

처방은 `rolloverToToday()` — `selectedDate < todayKst()`면 오늘로 민다. **앞으로만** 민다:
스트립이 오늘부터 14일이라 과거 날짜를 고를 경로가 없고, 따라서 "선택 날짜 < 오늘"은
자정을 넘겼다는 뜻 하나뿐이다. 회원이 고른 미래 날짜는 건드리지 않으므로 그 경우
state가 그대로고 슬롯 재조회도 없다(왕복 0).

**트리거는 provider가 아니라 화면이 쥔다.** provider 안에 타이머를 두면 다른 탭에 있을
때도, 앱이 백그라운드일 때도 돈다 — 그 판단(비활성 탭 게이팅 · 앱 재개 재평가)은 이미
`TimeBoundaryBuilder`에 들어 있다. `BookingScreen`의 `body` 전체를 감싸서 세 가지가 같은
자정에 함께 맞게 했다: ① 선택 날짜 롤오버 ② `DateStrip`의 14일 목록 재생성(후속 9번,
`date_strip.dart:18`이 여기서 함께 닫혔다) ③ `MyBookingsList`의 다가오는 예약 필터.
`async.when` **바깥**에 둬서 로딩·에러 상태에서도 돈다.

provider 쓰기는 `addPostFrameCallback`으로 프레임 뒤로 미룬다 — build 중 provider 수정은
Riverpod가 막는다("Tried to modify a provider while the widget tree was building").

### 2. Home Work — **재조회한다**(P16의 "왕복 0" 원칙과 갈리는 지점)

⚠️ 이게 이번 P에서 방향을 판단한 자리다.

P16의 원칙은 "바뀐 게 시계뿐이면 서버를 다시 부르지 않는다"였고, 셀프 체크인 버튼에서
그건 옳았다 — 창이 열렸다는 사실은 손에 든 `startAt` 하나로 다시 계산되고 예약 자체는
그대로다.

**Home Work는 그 조건에 해당하지 않는다.** 여기서 날짜는 판정의 입력이 아니라 **어느
문서를 읽고 쓸지 고르는 키**다(`GET/POST /v1/hw-checks?date=`, 서버 `store.SaveHwCheck`의
`(회원,배정,날짜)` 합성 키). 자정을 넘기면 화면에 남은 목록은 "낡은 판정"이 아니라
**다른 문서의 내용**이고, 배정 자체가 요일 스케줄(`HomeworkScheduleRules.isActiveOn`)로
달라져 항목 수까지 바뀐다 — 오늘 목록을 로컬에서 만들 방법이 없다. 그래서 여기만
**자정에 재조회**한다.

왕복은 이렇게 묶었다:

- 자정 경계에만 깨운다(`atMidnight`) — 폴링이 아니다
- 홈 탭이 **보일 때만**(`TickerMode`) + 앱이 foreground일 때만
- **날짜가 실제로 어긋났을 때만**(같으면 즉시 반환) — 앱 재개·탭 복귀의 리빌드는
  여기까지 오지 않는다
- 재조회해도 날짜가 안 맞으면(서버·기기 시계가 계속 어제를 준다) `_rolloverRequestedFor`
  메모가 **그날치 재시도를 한 번으로** 막는다. 이 가드가 없으면 "화면은 어제 → 재조회 →
  여전히 어제 → 재조회"가 매 프레임 돌면서 홈 로드 5~6 왕복을 무한 반복한다

**그리고 왕복 0의 최종 방어선을 함께 둔다.** 재조회가 못 닿은 경우(오프라인, 카드가
스크롤 밖이라 위젯이 없는 경우)를 위해, `toggleHomework`가 **읽기 시점 날짜 ≠ 지금 날짜**면
아예 보내지 않는다. `HomeSummary.homeworkChecksFailed`와 같은 처방이다 — 모르는(혹은 다른)
상태에서 문서 전체를 덮지 않는다. 막는 데서 끝내지 않고 재조회를 한 번 더 유도해
스스로 풀리게 했다.

배선은 `HomeSummary.homeworkDate`(신규, **required**) 하나다. repository가 배정 필터·
`GET ?date=`에 실제로 쓴 날짜를 그대로 요약에 실어 올리고, 쓰기는 **그 값을 되돌려
보낸다**(`date: current.homeworkDate`). 축을 KST로 맞추는 것만으로는 부족했다 — 시계를
두 번 읽는 한 그 사이에 자정이 끼면 값이 갈린다. `required`로 둔 이유는 P16과 같다:
기본값을 주면 fake·새 호출부가 조용히 가드를 무력화한다.

### 3. 마이 탭 홀딩 배지 + 재개 버튼

홈 회원권 카드와 같은 처방(`atMidnight`)으로 닫혔다. 재개는 **되돌릴 수 없는 소진**이고
(서버는 조기 종료된 홀딩도 횟수 상한에 포함한다), 그 확인 다이얼로그가 굳은 판정 위에
뜨던 게 위험의 실체였다. 서버 왕복 0.

### 4. 남긴 것 중 **회원이 손해 보는 것 하나**만 추가로 고침

취소 확인 다이얼로그(`booking_screen.dart`)를 열어 둔 채 컷오프를 넘기면, 회원은
"그냥 취소할까요?"만 읽고 확인하는데 서버는 그 시각 기준으로 세션 1회를 차감한다
(노쇼와 같은 원장 처리). 창이 좁아도 결과가 비가역이라 고쳤다 — 경계는 컷오프 시각
하나뿐이라 `TimeBoundaryBuilder(boundaries: [cutoff])` 한 줄이다.

나머지는 손해가 없거나 이미 정확히 고지되고 있어 남겼다(아래 "후속 작업").

## 진행 단계

- [x] P16 후속 목록 재확인 + 각 지점의 실제 코드 경로 확인(읽기/쓰기 축 분리 여부)
- [x] `HomeSummary.homeworkDate` 신설 + repository 배선 + `copyWith` 보존
- [x] `toggleHomework` 날짜 가드 + 쓰기를 읽기 날짜로 고정
- [x] `HomeViewModel.refreshIfDateRolled` + 재시도 메모, 홈 화면 `atMidnight` 트리거
- [x] `SelectedBookingDate.rolloverToToday` + `BookingScreen` body `atMidnight` 래핑
- [x] `PassList` `atMidnight` 래핑
- [x] 취소 확인 다이얼로그 컷오프 경계
- [x] 테스트 신규 3파일 + 기존 2파일 보강(21건), 기존 fake 6곳 정리
- [x] 뮤테이션 11종(10 kill / 1 equivalent), TZ 4종 전량 통과, `flutter analyze` 0

## 변경 파일

**신규**
- `app/test/features/booking/presentation/booking_date_rollover_test.dart` — 6건
- `app/test/features/home/presentation/homework_midnight_refetch_test.dart` — 4건
- `app/test/features/my/presentation/widgets/pass_list_midnight_test.dart` — 3건

**수정(lib)**
- `app/lib/features/home/domain/home_models.dart` — `HomeSummary.homeworkDate` 신설 + copyWith
- `app/lib/features/home/data/home_repository_impl.dart` — 읽은 날짜를 요약에 실어 올림
- `app/lib/features/home/presentation/home_view_model.dart` — 날짜 가드 · `refreshIfDateRolled`
- `app/lib/features/home/presentation/home_screen.dart` — Home Work 카드 `atMidnight` + 재조회 트리거
- `app/lib/features/booking/presentation/booking_view_model.dart` — `rolloverToToday`
- `app/lib/features/booking/presentation/booking_screen.dart` — body `atMidnight` + 롤오버,
  취소 다이얼로그 컷오프 경계
- `app/lib/features/my/presentation/widgets/pass_list.dart` — `atMidnight`

**수정(test)**
- `homework_toggle_guard_test.dart` — 자정 그룹 7건 추가, fake에 날짜·호출수 훅
- `cancel_flow_test.dart` — 다이얼로그 체류 중 컷오프 넘김 2건
- `HomeSummary` fake 6곳에 `homeworkDate: DateFmt.todayKst()`

## 계약

**서버 계약 변경 없음.** 앱이 보내는 `POST /v1/hw-checks`의 `date`는 종전과 같은 KST
날짜다 — 달라진 건 "어느 시점에 읽은 날짜를 보내는가"뿐이다.

백엔드에 요청할 변화도 없다. `store.SaveHwCheck`의 `.Set()`(문서 전체 교체)은 그대로
두는 게 맞다 — done 배열이 형제 항목 전체를 뜻하는 이상 부분 갱신은 오히려 인덱스
불일치를 숨긴다. 클라이언트가 "어느 날짜의 어느 배열인지"를 잃지 않는 쪽이 옳은 층이다.

(참고로 서버가 `date` 생략 시 KST 오늘로 채우는 동작도 그대로다. 앱은 항상 명시한다.)

## 검증

- `flutter analyze` — **이슈 0**
- `flutter test` — **647건 전량 통과**(작업 전 625 그린 → 신규 22, 회귀 0)
- TZ 4종 전량 통과: `UTC` / `Pacific/Honolulu` / `Asia/Seoul` / `Pacific/Auckland`
- 재현은 전부 `withClock`으로 결정적이다 — "23:50에 로드 → 00:05에 조작"을 실제로 기다리지
  않고 그대로 재현한다(UTC로 주입하고 기대값은 KST로 읽어 TZ 독립).

뮤테이션 11종 — **10 kill / 1 equivalent**:

| # | 뮤테이션 | 결과 |
|---|---|---|
| 1 | `rolloverToToday`를 no-op으로 | 5건 사망 |
| 2 | `BookingScreen`의 롤오버 호출 제거 | 4건 사망 |
| 3 | `BookingScreen`의 `atMidnight`를 false로 | 3건 사망 |
| 4 | Home Work 쓰기 날짜 가드 제거 | 5건 사망 |
| 5 | 쓰기 날짜를 시계에서 다시 읽기(`date: todayKst()`) | **생존 — equivalent** |
| 6 | `refreshIfDateRolled`의 재시도 메모 제거 | 2건 사망 |
| 7 | `refreshIfDateRolled`를 no-op으로 | 4건 사망 |
| 8 | 홈 화면의 자정 재조회 트리거 제거 | 2건 사망 |
| 9 | `PassList`의 `atMidnight`를 false로 | 1건 사망 |
| 10 | 취소 다이얼로그의 컷오프 경계 제거 | 1건 사망 |
| 11 | `HomeSummary.copyWith`가 날짜를 다시 읽음 | 1건 사망 |

**#5가 equivalent인 이유**: 가드(`current.homeworkDate != today` → return)와 `date:` 인자
평가 사이에 `await`가 하나도 없다. 가드를 통과한 시점에서 두 값은 **증명 가능하게 같다**.
그래도 `current.homeworkDate`를 쓰는 쪽을 남긴 이유는, 나중에 이 사이에 `await`가 하나
끼면(예: 확인 다이얼로그) 곧바로 갈리기 때문이다 — 불변식을 코드로 드러내 둔다.

## 후속 작업

같은 클래스에서 **이번에도 안 고친 것**(P16 후속 목록의 잔여 + 재평가):

1. **홈 "다음 예약" 지난 예약 필터**(`home_repository_impl.dart:98`) — 시작 1시간 뒤까지
   남기는 건 의도지만 그 뒤로도 재조회 전엔 안 사라진다. 자리를 채울 **다음 예약 정보
   자체가 서버에서 와야** 하므로 왕복 없이는 못 고친다. Home Work와 달리 재조회가
   "지금 화면이 틀렸다"를 고치는 게 아니라 "다음 데이터를 당겨온다"라, 자정보다
   `startAt+1h` 경계가 맞는 트리거다 — 지금 자리에서는 판단할 근거(빈도·체감)가 없다.
2. **기록 탭 주 경계**(`records_repository_impl.dart:61`) — 일요일 23:50 로드가 월요일
   이후에도 "이번 주"로 남는다. 금전 손해 없음, 재조회 필요(주간 집계는 서버 계산).
3. **`my_bookings_list.dart:57`의 3시간 버퍼** — 지난 예약의 취소 버튼이 남는다.
   **부분적으로 개선됨**: 예약 탭 body가 이제 자정에 다시 그려지므로 날짜가 바뀌는
   경우엔 걸러진다. 남은 건 같은 날 안에서 3시간이 지나는 경우인데, 그때 취소하면
   생기는 차감은 어차피 노쇼로도 똑같이 일어나고 다이얼로그가 그 사실을 정확히
   고지한다 — **회원이 추가로 손해 보는 게 없어서** 고치지 않았다.
4. **`hold_request_sheet.dart:94`** — 시트를 열어 둔 채 자정을 넘기면 `HoldStartsInPast`가
   안 떠 신청 버튼이 살아 있고 서버 400. 마찰이지 손해는 아니다(돈·회차 변화 없음,
   서버 문구가 정확하다). 시트 body를 `atMidnight`로 감싸면 닫히지만, 시트에 머무는
   시간이 자정을 걸칠 확률이 낮아 우선순위를 두지 않았다.
5. **`camera_screen.dart:135`** — 촬영 시각 표기 오차 수준.

기타(P16에서 이어짐):
- `TimeBoundaryBuilder`는 웹을 고려하지 않았다(JS `setTimeout`이 ~24.8일에서 포화).
  이번에 늘어난 사용처도 전부 자정 이내 또는 컷오프 경계라 모바일에선 문제없다.
- TZ 4종 실행은 여전히 **사람이 손으로 하고 기록**한다 — CI가 없다.
  `.github/workflows`가 생기면 `TZ` 매트릭스를 강제하는 게 맞다.

## 참조

- 선행: [P16 시각 판정이 로드 시점에 굳는 결함](P16-app-time-frozen-judgments.md)
  (`TimeBoundaryBuilder` · `package:clock` · "재평가는 왕복 0" 원칙의 출처)
- 서버 원본: `backend/internal/store`의 `SaveHwCheck`(`(회원,배정,날짜)` 합성 키 `.Set()`),
  `backend/internal/api/service.go`의 `today()`(KST 고정),
  `backend/internal/domain/pass.go`(조기 종료된 홀딩도 상한에 포함)
- 시간축 규약: `app/lib/core/utils/date_format.dart` 클래스 주석,
  [P12 앱 시간축(KST) 정렬](P12-app-time-axis-records.md)
- 같은 처방의 선례: `HomeSummary.homeworkChecksFailed`
  ([P12 앱 시간축·기록 갈래](P12-app-time-axis-records.md) — 조회 실패 시 토글이 서버
  완료 기록을 덮던 건)
