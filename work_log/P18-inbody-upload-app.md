---
id: P18
title: 인바디 수기 입력 v1 — 회원 앱(6지표 표시·방향 델타·수기 입력 폼·삭제)
status: 완료
domain: app
created: 2026-08-23
completed: 2026-08-23
---

# P18 — 인바디 수기 입력 v1(회원 앱)

## 목표

회원이 **결과지를 보고 숫자 6개를 손으로 옮겨 적는** 화면을 만든다. 카메라도 OCR도 없다.
백엔드 갈래([P18 백엔드](P18-inbody-upload-backend.md))가 깐 안전장치(범위·교차 검증 ·
미래일 거부 · 같은 날 409 · `source` Principal 판정 · `DELETE /v1/inbody/{id}`) 위에
앱을 올린다.

착수 전 실제 상태(코드 확인, 추정 아님):

| 결함 | 코드 근거 |
|---|---|
| 인바디 6지표 중 **2개(SMM/PBF)만** 화면에 온다 | `records_screen.dart`의 하드코딩 2행 — weight/bfm/vfl/bmr은 서버→DTO→도메인까지 다 와서 화면 직전에 버려졌다 |
| 목업에 있는 델타(`▲0.4`/`▼0.9`)가 미구현 | `목업_회원앱_라이즈_2026-08-14.html:226-232` vs 앱 렌더 |
| 방향 인식 델타는 **어드민에만** 있다 | `admin/src/features/BodyPhotos.tsx`의 `Delta`(SMM↑ ok / PBF↑ danger) |
| 앱은 인바디를 **읽기 전용**으로만 쓴다 | `records_remote_data_source.dart`에 GET 3개뿐 |
| 서버가 준 `id`를 화면 직전에 버린다 | `records_repository_impl.dart`의 매핑 — 삭제 대상을 특정할 수 없다 |

## 결정 사항

### 1. 스코프 순서 — 델타/6지표가 먼저, 입력 폼이 다음

목업 인바디 카드에는 **입력 버튼이 없고 델타는 있다**. 즉 6지표+델타는 "미구현분 이행"이고
입력 폼은 "목업에 없는 신규 UI"다. 이 비대칭이 순서를 정했다 — A 묶음(읽기)은 서버와 무관해
단독으로 머지 가능하다.

### 2. 진입점은 카드 헤더 `trailing` — FAB도, 촬영 탭도 아니다

`RiseCardHeader(trailing:)` 슬롯이 이미 있고(`rise_card.dart`) 같은 탭의 체형 카드가 그 자리를
쓰고 있어(`body_photo_timeline.dart`) 구조 변경이 0이다.

- **FAB 탈락**: 앱 전체에 `FloatingActionButton`이 0개이고, 셸 주석이 가운데 촬영 탭을 "FAB
  아님"이라 못박았다(`app_shell.dart`). 기록 탭 Scaffold에 달면 운동·체형 서브탭에서도 뜬다.
- **촬영 탭 탈락**: 포즈 시퀀스·고스트·수평계가 전부 "사람 몸" 전제로 좌표까지 고정된 목업
  이식이고, 카메라 provider가 TickerMode+포그라운드 판정에 묶인 체형 전용 수명주기다.

### 3. 규칙은 도메인, 픽셀은 presentation

`inbody_metrics.dart`(순수, Flutter 의존 0)가 라벨·단위·입력 범위·방향·델타 생략 문턱을 **한
곳에서** 정한다. 위젯이 하는 일은 `InbodyTrend`를 팔레트 색으로 옮기는 것뿐이라, 색과 해석이
어긋날 자리가 한 군데로 줄어든다(`homework_week_rules.dart`와 같은 규약).

방향 테이블 — 어드민 2개 + 4개 확장:

| 지표 | 방향 | 근거 |
|---|---|---|
| SMM 골격근량 | ↑ 좋음 | 어드민 `goodWhenUp` 그대로 |
| PBF 체지방률 | ↑ 나쁨 | 어드민 그대로 |
| BFM 체지방량 | ↑ 나쁨 | 확장 |
| VFL 내장지방 | ↑ 나쁨 | 확장 |
| 체중 | **중립(muted)** | 증량/감량 목표가 사람마다 반대다 |
| BMR 기초대사량 | **중립(muted)** | 체중에 딸려 움직여 단독 해석이 위험하다 |

`|Δ| < 0.05` 생략은 어드민 `Delta`의 경계 그대로다. 두 화면이 다른 문턱을 쓰면 같은 기록이
한쪽에선 "변화 없음", 다른 쪽에선 "▲0.0"이 된다.

### 4. 차트는 **건드리지 않는다** — 2시리즈(SMM/PBF) 유지

`inbody_chart.dart`는 시리즈별로 min/max 정규화를 하지만 **축 라벨이 없다**. 6지표를 한
캔버스에 넣으면 BMR(≈1400)과 PBF(≈26)가 같은 높이에 겹쳐 그려져 어느 선이 무엇인지 읽을 수
없다. 색으로 범례를 대신하는 구조라 라벨을 칠하는 것도 SMM/PBF 둘로 한정했다 — 선이 없는
지표를 칠하면 없는 범례를 가리킨다.

### 5. 범위는 서버 v2.9와 **한 자리도 다르지 않게**

착수 시엔 서버 범위검증이 없어 앱이 넓게 잡아 뒀다가, 백엔드가 착지한 뒤
`backend/internal/domain/measurement.go`의 `inbodyRanges`에 정확히 맞췄다(SMM 100→120,
BFM 150→200, PBF 75→70). 어긋남은 **두 방향 다 사고**다:

- 앱이 좁으면 → 서버가 받아 줄 값을 앱만 막아 회원에게 막다른 길
- 앱이 넓으면 → 6칸을 다 채운 뒤 400

`inbody_metrics_test.dart`가 6지표 min/max를 서버 표와 대조해 못 박는다.

### 6. 교차 검증은 **막고**, PBF 항등식은 **경고만**

서버 `Inbody.Validate()`가 확실히 거부하는 세 조합(`smm >= weight`, `bfm >= weight`,
`smm+bfm > weight`)은 `crossFieldError`로 버튼을 잠근다 — 체/제 오기(BFM 칸에 FFM)가 실질적으로
여기서 잡힌다(FFM은 보통 체중의 70~90%라 개별 범위는 태연히 통과하지만 SMM과 더하면 체중을 넘는다).

`PBF ≈ BFM/weight×100` 항등식은 **서버가 검증하지 않으므로 막지 않는다** — 앱이 막으면 서버가
받아 줄 값을 앱만 거부한다. 이 경고가 담당하는 구간은 교차 검증을 통과해 버리는 꼬리다
(SMM이 작으면 `SMM+FFM ≤ 체중`이 성립해 서버는 태연히 저장한다).

한계는 정직하게: **SMM·VFL·BMR은 검산 근거가 아예 없어 조용히 틀린다.** 화면 경고는 뜨지만
회원 입력값을 상담 근거로 쓸 땐 코치가 한 번 봐야 한다.

### 7. 미입력은 "거부"가 아니라 "미완성"

버튼을 잠그는 건 **서버가 확실히 거부할 값**일 때만이다. 빈 칸은 잠그지 않고, 눌러서 무엇이
빠졌는지 안내를 받게 둔다(`hold_request_sheet.dart`의 사전 판정 규약 그대로).

6칸이 전부 필수인 이유는 UX 취향이 아니다 — JSON에서 미입력 숫자는 `0.0`으로 직렬화되고
서버 범위 하한이 전부 0보다 크므로, "선택 입력"은 곧 확정 400이다.

### 8. 409 문구 — 서버 문구를 **우선**한다

당초 계획은 앱이 409 문구를 갈아끼우는 것이었는데, 서버가 착지한 뒤 보니 서버 메시지가 날짜까지
넣어 더 구체적이었다("2026-08-17 인바디 기록이 이미 있어요 — 기존 기록을 지우고 다시
저장해주세요"). 앱이 지어낸 문장으로 덮으면 나빠진다. 그래서 **서버가 본문을 안 준 경우의
폴백으로만** 남겼다 — `guardApi` 기본 폴백('요청을 처리할 수 없어요')은 다음 행동을 말하지 않고,
수정(PUT)이 없으므로 회원이 할 수 있는 일은 지우고 다시 넣는 것뿐이라는 걸 그때는 앱이 말해야 한다.

### 9. `source`는 nullable, 그리고 `""`는 null과 같다

서버 `Inbody.Source`는 `omitempty`가 아니라 v2.9 이전 레코드가 `"source": ""`로 내려온다.
DTO는 `String?`(required로 두면 그 레코드 전부가 fromJson에서 던져 기록 탭 셋을 통째로 죽인다 —
전례가 `records_repository_impl.dart` 날짜 가드 주석에 있다), 매핑에서 `""`를 null로 정규화한다.
둘 다 "회원 본인이 넣었다는 근거가 없다"는 같은 뜻이라 화면이 두 갈래로 말하면 안 된다.

삭제 액션은 `source == 'member_self'`일 때만 붙는다. `null`은 "출처 미상"이지 "본인"이 아니다.

### 10. 정정 경로는 **생략 불가** — 입력 폼과 한 묶음

인바디 카드 하단에 최근 5건 요약 + 본인 기록에만 삭제. 확인 다이얼로그는 비가역 동작이라
결과를 구체적으로 말한다(어느 날 기록인지 · 되돌릴 수 없다 · 추이 그래프에서도 사라진다 ·
잘못 넣었으면 지운 뒤 다시 입력). 수정(PUT)은 만들지 않았다 — 삭제 후 재입력으로 충분하고
API 면적이 절반이다.

## 진행 단계

- [x] A. 읽기 개선 — `inbody_metrics.dart`(순수 도메인) + `inbody_metric_rows.dart`(6지표+델타)
- [x] A. `records_screen.dart` `_InbodyTab` 하드코딩 2행 → 위젯 호출로 교체
- [x] B. DTO `String? source` 추가 + codegen
- [x] B. `InbodyRecord`에 `id`/`source`/`isMemberSelf` 추가, 매핑에서 `""`→null 정규화
- [x] B. `RecordsRepository`에 `createInbody`/`deleteInbody`, 데이터소스에 POST/DELETE
- [x] B. `inbody_input_rules.dart` — 범위·교차 검증·비차단 경고·`InbodyDraft`
- [x] B. `inbody_add_sheet.dart` — 동의 분기 · 날짜 · 6칸 · 사전 잠금 · 409 · 성공 pop
- [x] B. `inbody_recent_list.dart` — 최근 5건 + 본인 기록 삭제 + 확인 다이얼로그
- [x] B. `records_view_model.dart` — 쓰기/삭제 **성공 시에만** invalidate
- [x] C. 테스트 91건(선작성) + 뮤테이션 18종
- [x] 백엔드 착지 후 계약 재정렬(범위 3개 · 교차 검증 3개 · 409 문구 · `""` 정규화)

## 변경 파일

신규(앱):
- `app/lib/features/records/domain/inbody_metrics.dart`
- `app/lib/features/records/domain/inbody_input_rules.dart`
- `app/lib/features/records/presentation/widgets/inbody_metric_rows.dart`
- `app/lib/features/records/presentation/widgets/inbody_add_sheet.dart`
- `app/lib/features/records/presentation/widgets/inbody_recent_list.dart`

수정(앱):
- `app/lib/core/api/dto/inbody_dto.dart` (+ `.freezed.dart` / `.g.dart`)
- `app/lib/features/records/domain/records_models.dart`
- `app/lib/features/records/domain/records_repository.dart`
- `app/lib/features/records/data/records_remote_data_source.dart`
- `app/lib/features/records/data/records_repository_impl.dart`
- `app/lib/features/records/presentation/records_view_model.dart`
- `app/lib/features/records/presentation/records_screen.dart`

신규 테스트:
- `app/test/features/records/domain/inbody_metrics_test.dart`
- `app/test/features/records/domain/inbody_input_rules_test.dart`
- `app/test/features/records/data/records_inbody_write_test.dart`
- `app/test/features/records/presentation/inbody_write_invalidate_test.dart`
- `app/test/features/records/presentation/records_inbody_tab_test.dart`
- `app/test/features/records/presentation/widgets/inbody_metric_rows_test.dart`
- `app/test/features/records/presentation/widgets/inbody_add_sheet_test.dart`
- `app/test/features/records/presentation/widgets/inbody_recent_list_test.dart`

수정 테스트(인터페이스 확장에 따른 fake 보강만 — 기존 의도 무변경):
- `app/test/features/bodycheck/presentation/camera_view_model_test.dart`
- `app/test/features/home/presentation/homework_toggle_guard_test.dart`

무변경(의도적):
- `inbody_chart.dart` — 2시리즈 유지(§4)
- `records_repository_failure_test.dart` — "인바디 5xx는 탭 실패"라는 기존 의도 유지
- `pubspec.yaml` / `android/` / `ios/` — 신규 의존성 0(v1에 OCR 없음)
- `backend/**` · `docs/**` · `storage.rules` · `admin/**` — 담당 밖

## 검증

- `flutter analyze` — 이슈 0
- `flutter test` — **738건 그린**(착수 시 647 → +91). `TZ=UTC` · `TZ=Pacific/Honolulu`에서도 동일
- 뮤테이션 **18/18 kill**:

| # | 되돌린 것 | 죽은 테스트 |
|---|---|---|
| 1 | `deltaEpsilon` 0.05 → 0.0 | 2 |
| 2 | PBF `goodWhenUp` false → true | 4 |
| 3 | DTO `source`를 required로 | **15** (기존 failure_test 포함 — 탭 3개가 죽는 그 회귀) |
| 4 | POST 바디에 `source` 추가 | 1 |
| 5 | 409 분기 제거 | 1 |
| 6 | 동의 분기 제거(항상 폼) | 1 |
| 7 | 프로필 조회 실패도 차단 | 1 |
| 8 | `todayKst()` → `DateTime.now()` | 2 (`TZ=UTC`에서만 보인다) |
| 9 | 실패해도 invalidate | 2 |
| 10 | `isMemberSelf` → `source != null` | 2 |
| 11 | 사전 버튼 잠금 제거 | 2 |
| 12 | 실패 시 시트 닫기 | 2 |
| 13 | 확인 다이얼로그 결과 무시 | 1 |
| 14 | `previous` 배선 제거(화면) | 1 |
| 15 | SMM max를 서버와 다르게 | 1 |
| 16 | 교차 검증을 비차단으로 | 2 |
| 17 | `""` source 정규화 제거 | 1 |
| 18 | 409 앱 문구가 서버 문구를 덮게 | 1 |

뮤테이션 9가 처음엔 **살아남았다** — "실패하면 무효화하지 않는다" 테스트가 무효화 직후
재읽기를 하지 않아, 무조건 invalidate로 바꿔도 통과했다(`invalidateSelf`는 즉시 재빌드하지
않는다). 테스트에 `await container.read(...future)`를 넣어 실제 재로드까지 확인하도록 고친 뒤
kill됐다. 뮤테이션 패스가 없었으면 이 테스트는 계속 아무것도 지키지 않았다.

## 적대적 검증 반영 (2026-08-23, 3렌즈 지적 6건 수리)

백엔드 409 문구 분기(기존 기록이 센터 입력분이면 "담당 코치에게 요청" / 셀프면 "지우고
다시")는 별도 수리됐고, 여기는 앱 갈래만. `backend/`·`admin/` 무변경.

### HIGH 1 — 권한 안내가 서버와 다른 말을 했다 (P8 정직성)

`camera_permission_view.dart:62`의 "사진은 촬영 즉시 나와 담당 코치만 볼 수 있게
저장돼요"는 두 겹 거짓이었다: ① 서버 `checkBodyPhotoAccess`(service.go)는 **대표(owner)도**
동의 유효 시 허용 — 열람 범위를 좁혀 말했다. ② 사진을 저장하지도 않는 QR 스캔 화면에
같은 문장이 붙었다(공용 위젯에 문장이 박혀 있어서).

수리: 뒤 문장을 `note` 파라미터로 분리(기본 null = 아무 말도 안 붙임). 체형 촬영만
"나와 담당 코치, 센터 대표만 볼 수 있게 저장돼요"를 넘기고 QR은 넘기지 않는다(코드
변경 없이 문장이 빠진다). 지적 목록에 없던 **같은 클래스 1건 추가 수리**:
`camera_screen.dart:208`의 상시 안내문 "사진은 나와 담당 코치만 봅니다"도 대표를 숨긴
같은 거짓이라 함께 고쳤다.

### HIGH 2 — 409에서 재조회하지 않아 안내를 따라갈 수 없었다

409는 실패 중 유일하게 "앱이 들고 있는 목록이 서버와 다르다"는 신호인데, "성공 시에만
무효화" 규약이 그대로 적용돼 충돌을 일으킨 기존 기록이 화면에 안 보였다 — "지우고 다시"
안내가 막다른 길.

수리: `ConflictFailure extends RejectedFailure` 신설(**타입** 분기 — 문자열 매칭은 서버
문구를 다듬는 순간 조용히 깨진다, `MemberNotLinkedFailure`와 같은 판단. 하위 타입이라
기존 `is RejectedFailure` 분기는 그대로 성립). 저장소가 409를 이 타입으로 던지고(서버
문구 우선, 본문 없을 때만 폴백 — 기존 §8 유지), ViewModel은 `Ok`와 `ConflictFailure`에서만
refresh. 400·네트워크는 종전대로 무효화하지 않는다. 시트의 에러 문구는 서버 문구 그대로
(이제 행동 가능한 안내다).

### MEDIUM 3 — 삭제가 최신 5건에만 붙었다

입력 시트는 2년 소급을 허용하는데 리스트는 `reversed.take(5)` — 5건 밖 날짜의 셀프
기록은 화면에 없어 지울 수 없고, 409 안내를 따를 수 없었다. 수리: "이전 기록 N건 더
보기"(44dp 타깃 · 감춰진 건수 명시)로 전체 확장. 접기는 두지 않았다 — 펼침은 옛 기록을
찾는 중이라는 뜻이고, 삭제 후 재조회로 목록이 갈려도 펼친 채 남아야 지운 자리를 확인한다.

### MEDIUM 4 — VFL cm² 힌트가 회원에게 닿을 길이 없었다

서버가 VFL 범위 초과 400에 붙이는 "내장지방 '레벨'이에요 — 단면적(cm²)이 아니에요"는
앱이 같은 범위를 사전 판정해 요청이 아예 안 나가므로 영영 안 보였다(770/970 결과지의
cm²값 ~100을 그대로 옮겨 적는 실수가 실제로 난다). 수리: VFL 헬퍼 상시 노출
"내장지방 레벨 — 단면적(cm²) 아니에요"(BFM 헬퍼와 같은 판단 — 틀린 뒤에 말하면 늦다).

### LOW 5 — 타이핑 도중 정상 값에 에러가 명멸했다

`fieldError`가 키 입력마다 판정해 "7"(체중 70의 첫 타)·"14"(BMR 1420의 도중)에 붉은
에러가 떴다. 수리: **지금 포커스가 있는 칸은 표시를 판정하지 않는다**(FocusNode 직접
소유 + 포커스 변화 리스너). 버튼 잠금은 종전대로 실시간 — 미루는 건 표시뿐이다.
"제출 시도 시 표시"는 별도 상태 없이 성립한다: 범위 에러가 있으면 버튼이 이미 잠겨
제출 자체가 안 되고, 값은 타이핑으로만 들어오므로 "안 만진 칸"은 비어 있어 fieldError가
null이다.

### LOW 6 — 정렬 타이브레이커

Dart `List.sort`는 불안정 정렬이라 date만 비교하면 동률(회원+코치가 같은 날 동시에
넣으면 실제로 생긴다 — §한계 2)의 순서가 입력 순서에 끌려간다. 수리: date 동률은 id
오름차순(서버 문서 ID 축) — 같은 목록이면 조회마다 같은 순서, "직전 기록" 델타가
흔들리지 않는다.

### 변경 파일(검증 반영분)

- `app/lib/core/result/failure.dart` — `ConflictFailure` 신설
- `app/lib/core/widgets/camera_permission_view.dart` — `note` 파라미터, 거짓 문장 제거
- `app/lib/features/bodycheck/presentation/widgets/camera_preview_layer.dart` — 체형용 note
- `app/lib/features/bodycheck/presentation/camera_screen.dart` — 상시 안내문 열람 범위 정정
- `app/lib/features/records/data/records_repository_impl.dart` — 409→ConflictFailure, 정렬 2차 키
- `app/lib/features/records/presentation/records_view_model.dart` — Conflict에서만 예외적 refresh
- `app/lib/features/records/presentation/widgets/inbody_add_sheet.dart` — VFL 헬퍼, 포커스 기반 에러 표시
- `app/lib/features/records/presentation/widgets/inbody_recent_list.dart` — 더 보기 확장
- 테스트: `camera_permission_view_test.dart`(신규) · `qr_scan_screen_test.dart` ·
  `camera_screen_permission_test.dart` · `records_inbody_write_test.dart` ·
  `inbody_write_invalidate_test.dart` · `inbody_add_sheet_test.dart` · `inbody_recent_list_test.dart`

### 검증(반영분)

- `flutter analyze` 이슈 0 · `flutter test` **751건 그린**(738 → +13, 회귀 0).
  `TZ=UTC` · `TZ=Pacific/Honolulu` 동일.
- 뮤테이션 **11/11 kill**(각각 되돌리고 실패 확인 후 복구):

| # | 되돌린 것 | 죽은 테스트 |
|---|---|---|
| 1 | VM: 409에도 무효화 안 함(성공 시에만으로 회귀) | 1 |
| 2 | VM: 모든 실패에 무효화 | 2 (기존 네트워크 + 신규 400) |
| 3 | repo: 4xx 전부 Conflict로 분류 | 2 |
| 4 | repo: 409를 RejectedFailure로(타입 소실) | 2 |
| 5 | 정렬 id 2차 키 제거 | 1 |
| 6 | errorText 키 입력마다 판정(회귀) | 2 |
| 7 | errorText 아예 없음 | 3 (기존 702kg 테스트 포함) |
| 8 | 더 보기 눌러도 5건 고정 | 1 |
| 9 | 캡 제거(항상 전체) | 3 |
| 10 | 거짓 문장을 공용 위젯에 다시 하드코딩 | 4 (3파일에 걸쳐) |
| 11 | VFL 헬퍼 원복 | 1 |

### 자문자답(반영분)

- **포커스 판정의 남은 구멍**: 마지막 칸에 범위 밖 값을 넣고 포커스를 유지하면 버튼은
  잠겼는데 이유가 안 보인다(모바일 기본 동작은 밖을 탭해도 언포커스 안 됨). 남긴 이유 —
  다른 칸을 만지는 순간 드러나고, 6칸 폼에서 마지막 칸만 만진 채 멈추는 경로가 좁다.
  대안(제출 시도 시 강제 표시)은 버튼이 잠겨 있어 도달 불가라 실익이 없다.
- **deleteInbody의 404도 "목록이 낡았다" 신호 아닌가**: 맞지만 이번 지적 범위 밖. 삭제
  404는 "이미 없음 = 목적 달성"이라 재조회가 맞는지 별도 판단이 필요해 남겼다.
- **workoutLogs 정렬도 date만 본다**: 인바디와 달리 동률의 서버 확정 순서(무엇이 2차
  키인지)를 확인하지 못해 추측으로 넣지 않았다. 남김.

## 후속 작업

1. **실기기 미검증.** 오늘 확인한 건 테스트뿐이다. 시트 키보드 인셋 · 2열 그리드가
   작은 화면(SE급)에서 잘리지 않는지 · 큰 글꼴 배율에서 helperText 3줄이 넘치지 않는지는
   실기기 확인이 필요하다. iOS는 이 영역이 통째로 미검증이다(`app/ios`에 Podfile 자체가 없다).
2. **동시 중복은 여전히 통과 가능.** 서버가 쓰기 직전 읽기 1회로 막으므로 회원과 코치가 같은
   순간에 같은 날 기록을 넣으면 2건이 들어간다(백엔드 P18 §한계). 앱은 손댈 자리가 없다.
3. **동의 철회 회원의 인바디가 어드민에서 계속 보인다** — `ListInbody`는 `checkMemberScope`만
   보고 `hasSensitiveConsent`를 요구하지 않는다(체형사진과 비대칭). 알고 남긴 것이고, 고치면
   철회 회원의 인바디가 어드민에서 통째로 사라져 운영에 영향이 있다. 별도 판단 필요.
4. **차트에 축 라벨이 없다.** 2시리즈가 각자 정규화되므로 선의 높이가 절대값과 무관하다 —
   "SMM 24.1이 PBF 26.8보다 아래"처럼 읽힐 수 있다. 6지표를 넣지 않은 이유이기도 하고,
   축·범례를 붙이는 건 별건이다.
5. **OCR은 v2 게이트 전엔 착수 금지**(설계 §3의 5개 조건). v1에서 만든 이 폼이 곧 v2의 실패
   경로다 — 인식 0건/부분 인식/값 이상 셋 다 "빈 칸으로 두고 사람이 채운다"로 떨어진다.

## 참조

- [P18 백엔드 갈래](P18-inbody-upload-backend.md) — 범위·교차 검증 · 미래일 · 409 · `source` · DELETE
- [P12 — 앱 시간축(KST) 정렬 + 홈·기록·체형 잔여 결함](P12-app-time-axis-records.md) — 촬영→기록 무효화 규약, 인바디 날짜 스킵 가드
- [P16](P16-app-time-frozen-judgments.md) · [P17](P17-app-midnight-boundary.md) — `package:clock` 시계 주입, KST 축 테스트 규약
- `목업_회원앱_라이즈_2026-08-14.html:226-232` — 델타 표기의 원본
- `admin/src/features/BodyPhotos.tsx` — 방향 규칙·폼 라벨의 원본(어드민 파일은 무변경)
- `PT데스크_설계_00_제품정의_자문자답_2026-08-14.md:115,152,233` — 수기 입력 전제 / 결과지 파싱 OUT(v1)
