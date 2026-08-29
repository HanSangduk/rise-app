---
id: P12
title: 앱 시간축(KST) 정렬 + 홈·기록·체형 잔여 결함
status: 완료
domain: app
created: 2026-08-23
completed: 2026-08-23
---

# P12 — 앱 시간축(KST) 정렬 + 홈·기록·체형 잔여 결함

## 목표

P12 앱 감사가 남긴 **인계 항목**을 마무리한다. 앞 팀(`P12-app-booking-judgment`)은
`core/utils/date_format.dart`에 시간축 유틸(`kstOffset`/`toKst`/`nowKst`/`todayKst`)을 만들고
예약 탭까지만 적용한 뒤 종료했다. 남은 것은 두 묶음이다:

1. **시간축 미적용 지점 5곳** — 홈(예약 판정·Home Work 날짜) · 기록(주 경계) · 체형(촬영 시각·날짜 pill)
2. **홈·기록·체형의 잔여 결함 3건** — 종료된 회원권의 기본 선택 · 촬영→기록 탭 stale · 포즈 필터

⚠️ `features/booking/**`은 다른 에이전트가 동시 작업 중이라 **읽기만** 했다.

## 결정 사항

### 1. "지금"만 KST로 올리고 표현은 건드리지 않았다

`slotKeyToDateTime`은 그대로다. slotKey의 벽시계 숫자를 DateTime 필드에 그대로 담는 표현이라
표시(`hhmm`·`monthDayWeekday`)와 날짜 단위 비교(`PassHold.contains`, 유효기간)가 기기 TZ와
무관하게 "센터가 말하는 그 시각"을 가리킨다. 절대 시각으로 바꾸면 해외 기기에서
8/15 09:00(KST) 슬롯이 8/14로 읽혀 하루씩 어긋난다. 그 판단은 앞 팀이 검증했고 그대로 따랐다.

### 2. hw-check 날짜는 **읽기·쓰기 세 곳을 함께** 바꿔야 했다

이게 이 작업에서 가장 위험한 지점이었다. 종전엔 배정 필터(`isActiveOn`)·조회(`GET ?date=`)·
쓰기(`POST` body date)가 **전부 로컬**이라 **틀린 채로 서로 일관**했다. 한쪽만 KST로 올리면
해외에서 회원이 체크한 값이 다른 날짜 문서에 저장되고, 다음 로드가 그걸 못 읽어 **체크가
저절로 풀린 것처럼** 보인다 — 고치기 전보다 나쁘다.

리포지토리에서 `todayKst`/`todayIso`를 **한 번만 계산해** 세 곳이 같은 값을 쓰게 했고,
뷰모델의 쓰기도 같은 `DateFmt.todayKst()`로 맞췄다. 서버도 date 생략 시 KST 오늘로 채우므로
앱이 보내는 값이 곧 서버 값이다. 회귀는 "읽기 date == 쓰기 date"를 직접 단언하는 테스트로 고정했다.

### 3. `capturedAt`을 KST로 — epochMillis가 절대 시각이 아니게 되는 건 문제가 아니다

`capturedAt`은 두 곳에 박힌다: Storage 경로의 **날짜 앞머리**(`{yyyyMMdd}-…`, storage.rules가
날짜 폴더를 금지해 파일명에 넣는 구조)와 서버로 가는 `date`. 로컬이면 해외에서 파일명 날짜와
서버 기록이, 그리고 화면의 날짜 pill과도 하루씩 갈린다.

경로 꼬리의 `millisecondsSinceEpoch`는 벽시계 표현을 그대로 넣으므로 더 이상 진짜 epoch가
아니다. 그래도 문제 없다 — 그 값의 역할은 "같은 날 같은 포즈를 다시 찍었을 때의 충돌 회피"뿐이고
(BodyPhotoStoragePath 주석), 한 기기 안에서는 여전히 단조 증가한다. 코드에 근거를 남겼다.

### 4. 종료된 회원권 문제는 **던지지 않고** `hasUsablePass` 플래그로 올렸다

권고는 "active → scheduled → 없으면 '이용 가능한 회원권 없음' 상태로"였다. 상태를 만드는 방법이
둘이었다.

- **(A) `EmptyPassesFailure`의 하위 타입을 새로 던진다** — 홈 하나만 보면 가장 깔끔하다.
- **(B) `HomeSummary.hasUsablePass=false`로 올리고 화면이 판단한다** — 채택.

(A)를 버린 이유는 **예약 탭이 홈 요약을 그대로 받아쓰기 때문**이다
(`booking_view_model.dart:61`이 `homeViewModelProvider.future`를 watch하고 `home.selectedPassId`를
`primaryPassId`로 쓴다). 앞 팀이 바로 그 경로에서 환불 패스를 `PassNotUsable`로 안내하도록
방금 만들어 뒀다 — 홈이 던지기 시작하면 그 안내가 통째로 사라지고, 예약 탭은 자기 문구를
고칠 수 없는(내가 못 건드리는) 상태로 "아직 회원권이 없어요"를 띄우게 된다. 회원권을 산 적 있는
회원에게는 거짓말이다.

그래서 `_defaultUsablePass`는 active → scheduled → **null**을 돌려주되, `selectedPassId`는
`passes.first`로 **실재하는 id를 유지**한다(예약 탭 안내 보존). 홈만 `hasUsablePass=false`를 보고
헤더 배지 + 본문을 통째로 빼고 전용 빈 상태로 떨어진다. 예약 탭 동작은 **0바이트도 바뀌지 않는다.**

곁가지 판단:
- **칩을 직접 누른 선택(`preferredPassId`)은 존중한다.** 만료 칩을 눌렀는데 화면이 지워지면
  스스로 누른 칩이 화면을 지우는 셈이다. 기본 선택만 바꿨다.
- **빈 상태 뷰는 `EmptyPassesView`를 재사용**하되 `title`/`message`를 옵션으로 뚫었다.
  두 상태에 다른 모양의 뷰를 만들면 같은 자리에서 앱이 두 개처럼 보인다(state_view_parity 규약).
  기본값이 종전 문구라 예약 탭 호출부는 그대로다.
- **헤더도 함께 껐다.** 헤더는 `async.when` 밖이라 본문만 바꾸면 빈 상태 위에
  "PT 20회 · 잔여 8"과 "담당 정혜린 코치"가 그대로 떠 있는다.

### 5. 촬영→기록 무효화는 **순환을 없애서** 기존 패턴 그대로 썼다

`records_view_model.dart`가 `camera_view_model.dart`를 import하고 있어 역방향이 막혀 있었다.
신호 provider를 새로 두는 대신 **원인을 없앴다**: 그 import는 오직 `bodyCheckRepositoryProvider`
하나 때문이었고, 그 provider는 소비자가 둘(촬영이 쓰고 기록이 읽는다)인데 **한쪽 화면의 뷰모델
파일**에 얹혀 있던 게 잘못이었다. `features/bodycheck/data/body_check_repository_provider.dart`로
빼내니 순환이 사라졌고, 홈→기록(`toggleHomework`)과 **똑같은 한 줄**
(`ref.invalidate(recordsViewModelProvider)`)로 끝났다.

코드베이스에 `ref.listen` 기반 크로스탭 신호 패턴은 **하나도 없다**(전부 직접 invalidate).
새 패턴을 들이는 것보다 배치를 고쳐 기존 패턴에 맞추는 쪽이 맞다고 봤다.

### 6. 포즈 필터 — 데이터에서 걷어내고 화면이 고르게 했다

`records_repository_impl.dart:98`이 `ohsquat`만 남겨, 4장 찍은 회원이 1장만 다시 볼 수 있었다.
나머지 3장은 저장은 되지만 앱 어디에도 나타나지 않는다. `BodyPhotoAlbum`(포즈 → 사진 목록)을
도메인에 추가하고 리포지토리는 전부 실어 보낸다.

**기본 포즈를 "사진이 가장 많은 포즈"로 정했다**(동수면 촬영 순서에서 앞선 쪽, 전부 0장이면 `stand`).
- `ohsquat` 고정이 나빴던 이유: 촬영 시퀀스의 **마지막** 포즈라 도중에 그만둔 회원에겐 늘 0장이고,
  첫 진입이 대개 "아직 촬영한 사진이 없어요"였다. 사진을 보러 온 회원에게 가장 나쁜 첫 화면이다.
- "가장 많은 포즈"인 이유: 이 탭의 목적은 전/후 **비교**이고 2장 이상이라야 성립한다(1장이면 카드가
  "2장 이상 필요해요"로 막힌다). 장수 최대가 비교 성립 확률이 가장 높다. 최빈값이라 새로고침마다
  흔들리지도 않는다.
- 칩은 **0장 포즈도 남긴다**(라벨에 장수 표기). 목록에서 빼면 회원은 그 포즈를 찍을 수 있다는
  사실 자체를 모른다. 조회 실패 시에는 칩을 숨긴다 — 전부 "0장"이 사실처럼 보인다.
- 포즈를 바꾸면 날짜 인덱스를 다시 잡는다. 5장짜리에서 고른 인덱스가 2장짜리에 clamp되어 남으면
  엉뚱한 두 장이 선택된 것처럼 보인다.

### 자문자답

- **`nowKst()` 한 번 vs `todayKst()` 두 번, 자정 경쟁은?** 두 호출이 마이크로초 간격이라 실질
  위험이 없고, 날짜 판정은 `todayKst` 하나로 모아 세 소비자가 같은 값을 보게 했다.
- **`isActiveOn(date:)`에 자정으로 자른 값을 넘겨도 되나?** `HomeworkScheduleRules`는 `_isoDate`와
  `weekday`만 쓴다 — 시각 성분을 보지 않아 무해하다.
- **`hasUsablePass` 기본값을 true로?** 그렇다. 기존 생성자 호출부(테스트 픽스처 포함)의 의미가
  "정상 회원권"이라 기본값이 곧 종전 동작이다. `copyWith`에서 떨어뜨리면 낙관적 토글 한 번에
  빈 상태가 정상 홈으로 되돌아가므로 `homeworkChecksFailed`와 같은 규약으로 이어받게 했다.
- **`hasUsablePass=false`면 센터 공지(scope=center_notice) Home Work도 가려진다.** 인지하고 감수했다 —
  쓸 수 있는 회원권이 없는 회원에게 오늘의 운동 체크리스트를 띄우는 게 더 이상하다. 되살리려면
  공지 전용 섹션이 필요한데 그건 별건이다(후속 작업에 남김).
- **`BodyPhotoTimeline`을 지울까?** 남겼다. 카드 내부가 여전히 "한 포즈의 시간순 목록"으로 동작하고
  `BodyPhotoAlbum.timelineFor`가 그 타입을 돌려준다.

## 진행 단계

- [x] `date_format.dart` 규약·서버 소스(`domain/booking.go`, `api/service.go`) 대조
- [x] 시간축 5곳 적용 — 홈 `now`/hw-check 날짜 3곳 · 기록 주 경계 · 체형 `capturedAt`/날짜 pill
- [x] `_defaultUsablePass`(active→scheduled→null) + `HomeSummary.hasUsablePass` + 홈 전용 빈 상태
- [x] `bodyCheckRepositoryProvider` 추출로 순환 해소 → 업로드 성공 시 기록 탭 invalidate
- [x] `BodyPhotoAlbum` + 포즈 칩 + 데이터 계층 포즈 필터 제거 + 기본 포즈 재정의
- [x] 테스트 신규 5파일 + 기존 4파일 보강 · 4개 TZ 실행 · 뮤테이션 검증 13종
- [x] `flutter analyze` 0 · `flutter test` 570 통과

## 변경 파일

**시간축(KST)**
- `app/lib/features/home/data/home_repository_impl.dart` — `now`를 `DateFmt.nowKst()`로,
  hw-check "오늘"을 `todayKst`/`todayIso` 하나로 모아 배정 필터·조회·클라이언트 방어가 공유
- `app/lib/features/home/presentation/home_view_model.dart` — 토글 쓰기 date를 `DateFmt.todayKst()`로
- `app/lib/features/records/data/records_repository_impl.dart` — 주 집계 기준일 `DateFmt.nowKst()`
- `app/lib/features/bodycheck/presentation/camera_view_model.dart` — `capturedAt` KST
- `app/lib/features/bodycheck/presentation/camera_screen.dart` — 날짜 pill `DateFmt.todayKst()`

**대표 패스 · 빈 상태**
- `app/lib/features/home/data/home_repository_impl.dart` — `_defaultPass` → `_defaultUsablePass`(nullable)
- `app/lib/features/home/domain/home_models.dart` — `HomeSummary.hasUsablePass`(+copyWith 보존)
- `app/lib/features/home/presentation/home_screen.dart` — 전용 빈 상태 분기 + 헤더 동반 차단
- `app/lib/core/widgets/empty_passes_view.dart` — `title`/`message` 옵션(기본값 = 종전 문구)

**순환 해소 · 크로스탭 무효화**
- `app/lib/features/bodycheck/data/body_check_repository_provider.dart` — **신규**(provider 이전)
- `app/lib/features/bodycheck/presentation/camera_view_model.dart` — 업로드 성공 시 기록 탭 invalidate
- `app/lib/features/records/presentation/records_view_model.dart` — import를 새 provider 파일로

**포즈 필터**
- `app/lib/features/records/domain/records_models.dart` — `BodyPhotoAlbum`(+`defaultPose`),
  `RecordsData.bodyPhotos` 타입 변경
- `app/lib/features/records/data/records_repository_impl.dart` — ohsquat 필터 제거
- `app/lib/features/records/presentation/records_screen.dart` — `album:` 전달
- `app/lib/features/records/presentation/widgets/body_photo_timeline.dart` — 포즈 칩 + 포즈별 상태

**테스트(신규 5)**
- `app/test/features/home/home_kst_axis_test.dart` — 시각 판정 4 + 읽기·쓰기 날짜 일치 3
- `app/test/features/home/data/home_default_pass_test.dart` — 대표 패스 선택 10
- `app/test/features/home/presentation/no_usable_pass_view_test.dart` — 빈 상태 UI 4
- `app/test/features/records/domain/body_photo_album_test.dart` — 앨범·기본 포즈 10
- `app/test/features/records/presentation/widgets/body_photo_pose_chips_test.dart` — 포즈 칩 7

**테스트(보강 4)**
- `app/test/features/bodycheck/presentation/camera_view_model_test.dart` — 시간축 3 + 무효화 3
- `app/test/features/bodycheck/presentation/camera_screen_permission_test.dart` — 날짜 pill 1
- `app/test/features/records/data/records_repository_failure_test.dart` — 포즈 3 + 주 경계 2
- `app/test/features/home/presentation/homework_toggle_guard_test.dart` — 앨범 타입 반영

## 검증

- `flutter analyze` — No issues found
- `flutter test` — **585 passed** (착수 시점 baseline 473. 증가분에는 booking·my 갈래가 같은 시간에
  추가한 테스트가 섞여 있어 이 숫자는 내 몫만은 아니다 — 내가 추가한 건 신규 5파일 34건 + 보강 9건)
- **TZ 4종 전부 통과**: `TZ=UTC` / `TZ=America/New_York` / `TZ=Pacific/Auckland` / `TZ=Asia/Seoul`
  (각 585 통과)
- **뮤테이션 검증 13종 중 12 kill**

  | # | 뮤테이션 | TZ | 결과 |
  |---|---|---|---|
  | M1 | 홈 `now` → `DateTime.now()` | UTC | kill (3) |
  | M2 | 홈 `todayKst` → `DateTime.now()` | Pacific/Honolulu | kill (3) |
  | M3 | **쓰기 date만** → `DateTime.now()` | Pacific/Honolulu | kill (1 — 읽기·쓰기 일치 테스트) |
  | M4 | 기록 주 기준일 → `DateTime.now()` | UTC·Honolulu | **survive**(아래 설명) |
  | M4b | 기록 주 기준일 −7일 | Asia/Seoul | kill (2) |
  | M5 | `capturedAt` → `DateTime.now()` | UTC | kill (1) |
  | M6 | 날짜 pill → `DateTime.now()` | Pacific/Honolulu | kill (1) |
  | M7 | `_defaultUsablePass`의 scheduled 분기 제거 | — | kill (1) |
  | M8 | `_defaultUsablePass` → `passes.first`(종전) | — | kill (7) |
  | M9 | 홈 화면이 `hasUsablePass` 무시 | — | kill (3) |
  | M10 | 데이터 계층 ohsquat 필터 복원 | — | kill (3) |
  | M11 | `defaultPose` → `ohsquat` 고정 | — | kill (8) |
  | M12 | 업로드 성공 시 invalidate 제거 | — | kill (1) |

  복구 후 재검증 완료(analyze 0 · 570 통과 · 잔여 뮤테이션·백업 파일 0).

- **M4가 살아남은 이유(원리상 한계)** — `HomeworkWeekRules.summarize`는 시각이 아니라 **날짜만**
  쓴다. 그래서 KST 날짜와 로컬 날짜가 **같은 주 안에 있으면** 로컬 축이어도 답이 같다. 오프셋
  최대치(±14h)로도 날짜는 하루밖에 못 움직이므로, 실제로 갈리는 건 두 날짜가 월요일 경계를
  사이에 두는 날뿐이다(대략 주 1회). 검증 시점이 KST 일요일 8/23이라 어떤 TZ로도 같은 주였다.
  대신 **주를 한 칸 미는 뮤테이션(M4b)** — 축이 갈리는 날 실제로 나타나는 증상 그 자체 — 은
  두 테스트가 모두 잡는다. 이 한계는 테스트 파일 주석에 그대로 적어 뒀다.

- **`nowKst()` 계열 전반의 한계(앞 팀 주석과 동일)** — 호스트가 KST면 `nowKst() == DateTime.now()`라
  회귀가 **원리상 보이지 않는다.** 시각 판정(M1·M5)은 오프셋 9시간이 판정 창(30분~24시간)보다
  커서 KST 아닌 TZ면 언제 돌려도 죽지만, 날짜 판정(M2·M3·M6)은 두 날짜가 갈리는 시간대에만
  죽는다(검증에 `TZ=Pacific/Honolulu`를 쓴 이유 — 당시 KST 8/23 17시, HST 8/22 22시).

## 후속 작업

- **`features/booking` 테스트의 TZ 취약성(미수정 — 다른 팀 영역)** — `TZ=Pacific/Honolulu`로
  전체를 돌리면 booking 위젯 테스트 **14건이 깨진다**(`slot_list_test.dart` 13 · `booking_screen_test.dart` 1).
  원인은 테스트 픽스처가 `DateTime.now().add(1일)`로 "내일"을 만드는데(`slot_list_test.dart:21`,
  `booking_screen_test.dart:81`) 프로덕션 기본 날짜는 `DateFmt.todayKst()`(`selectedBookingDateProvider`)라,
  로컬 날짜가 KST보다 하루 뒤인 TZ에서 "내일(로컬)"이 "오늘(KST)"과 겹치기 때문이다.
  **내 변경과 무관함을 확인했다**: `slot_list_test.dart`/`slot_list.dart`의 import 그래프에 내가
  고친 파일이 하나도 없고, `booking_screen_test`는 자체 `_FakeHomeRepository`를 주입해
  `_defaultUsablePass`를 타지 않는다(요구된 TZ 4종에서는 전부 통과). 픽스처의 `DateTime.now()`를
  `DateFmt.todayKst()`로 바꾸면 끝나는 한 줄짜리 수정이라 booking 담당에게 넘긴다.
- **`hasUsablePass=false`에서 센터 공지가 가려진다** — 쓸 수 있는 회원권이 없어도 센터 공지
  (`scope=center_notice`)는 봐야 할 수 있다. 되살리려면 빈 상태 화면에 공지 전용 섹션이 필요하다.
- **환불 칩을 직접 누른 경우의 본문** — 기본 선택만 고쳤으므로, active 패스가 따로 있는 회원이
  환불 칩을 직접 누르면 여전히 잔여 링이 그려진다. 칩에 "(환불)"이 붙어 있고 명시적 선택이라
  이번엔 두지만, 카드 자체를 상태에 맞춰 죽이는 편이 더 정직하다.
- **체형 사진 실이미지** — 타임라인은 아직 플레이스홀더다(`storage_path` 서명 URL 미연동).
  포즈 칩이 붙으면서 "포즈별 장수"가 화면에 드러나므로, 실이미지 연동 시 포즈별 로딩 비용도 함께 볼 것.

## 참조

- `app/lib/core/utils/date_format.dart` — 시간축 규약(앞 팀 작업)
- `app/test/core/utils/date_format_test.dart` — TZ 검증 선례·주의사항
- `backend/internal/domain/booking.go:9-11` — `KST = time.FixedZone("KST", 9*60*60)`
- `backend/internal/api/service.go` — `today()`, `POST /v1/hw-checks`의 date 기본값(KST 오늘)
- `app/lib/features/bodycheck/domain/body_photo_storage_path.dart` — 경로 규칙(날짜 앞머리 이유)
- 앞 팀 작업: `P12-app-booking-judgment.md` · 부모 감사: `P12-audit-sweep.md`
