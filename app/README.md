# 라이즈 컨디셔닝 — 회원 앱 (rise_member)

> PT샵 SaaS "라이즈"의 회원용 Flutter 앱. 로그인(전화번호 인증 → 센터 자동매칭 →
> 이름확인 1탭) · 홈 · 예약 · 체형 분석 카메라 · 기록 · 마이.
> API 계약: `../docs/API계약_v1.md` (이 문서가 단일 진실).
> 시각 스펙: `../목업_회원앱_라이즈_2026-08-14.html`.

## 아키텍처

**Clean Architecture + MVVM + Feature-First** — wodshot(`../../wodshot/`) 컨벤션을 그대로 계승.

```
presentation  Views · ViewModels(Riverpod Notifier/AsyncNotifier)
     ↓
domain        Entities · Repository 인터페이스        ← 순수 Dart(프레임워크 0, codegen 0) → 유닛 테스트 대상
     ↑
data          RemoteDataSource(dio) · Repository 구현 · DTO(freezed, 계약 JSON 그대로)
```

- **DI = Riverpod**(get_it 미사용). `@riverpod` 코드생성(riverpod_generator) 사용.
- **에러 = Dart 3 sealed `Result<T>`/`Failure`**(core/result) — 의존성 0.
- **freezed는 DTO 전용**(core/api/dto/*). 도메인 엔티티·UI State는 모두 평범한 Dart 클래스라
  `dart run build_runner build` 없이도 `flutter test`(도메인 테스트)가 통과한다.
- **아이콘 = 커스텀 SVG 세트**(core/icons) — 이모지 전면 금지. `flutter_svg` +
  `SvgTheme.currentColor`로 색을 주입하는 `RiseIcon` 위젯 하나로 전부 렌더링.
- **짧은 액션 = 바텀시트**(예약 확정, 일시정지 신청, 동의 관리, 센터 찾기) — 라우트 아님.

## 구조

```
lib/
  core/
    theme/       AppColors·AppTypography·AppRadius·buildAppTheme (light + red #e11d48)
    icons/       RiseIcons(SVG 문자열) + RiseIcon 위젯
    network/     ApiConfig(API_BASE_URL·CHECKIN_QR_TOKEN) · DevSession(X-Dev-Role/X-Dev-Uid) · dioProvider · guardApi
    api/         cross-feature 공용 API 클라이언트(me/member/staff/passes/bookings) + DTO(contract 포함)
    config/      AppConfig(센터명 로컬 상수 — 멀티센터 전환 시 GET /v1/center로 대체)
    policy/      CenterPolicy — GET /v1/center 정책 실값(취소 컷오프·홀딩 상한·슬롯 용량) 캐시
    permissions/ 카메라 권한 상태·요청(permission_handler 래퍼) — QR 스캔·체형 촬영 공용
    session/     로그인 후 세션(AppSession) Riverpod 프로바이더(keepAlive)
    router/      go_router — 로그인 스택 + 바텀탭 5목적지 StatefulShellRoute
    utils/       DateFmt(slotKey↔DateTime, 날짜 표시 포맷)
    widgets/     RiseCard·RiseBadge·RiseChip·RiseButton 등 공용 UI 아톰
    result/      Result<T> / Failure(sealed)
  features/
    auth/        전화번호 → 인증번호 → 센터 자동매칭({phone} 전송) → 이름확인 1탭(P48)
    home/        패스 스위처 · 다음 예약 · Home Work 체크리스트(스케줄 규칙 필터) · 잔여 링(CustomPaint)
                 + qr_scan_screen.dart(셀프 체크인 QR 스캐너 — mobile_scanner)
    booking/     내 코치/전체 토글 · 슬롯 상태(BookingRules, 순수 — 슬롯 날짜 기준 유효기간) · 예약 확정 시트 · 내 예약
    bodycheck/   체형 분석 실카메라 — 그리드/수평계(가속도계)/포즈시퀀스/고스트/배경인물 경고
                 + body_photo_uploader.dart(Firebase Storage 업로드) · body_photo_storage_path.dart(경로 규칙)
    records/     운동 · 인바디(차트) · 체형 분석(타임라인+비교) 세그먼트
    my/          회원권 · 원장(이용내역) · 일시정지(정책 상한) · 계약(실 API) · 동의
    shell/       바텀 내비 셸(5탭, 가운데 촬영 탭 강조)
test/            57개 파일 · 약 600 케이스(도메인 순수 함수 + 위젯/뷰모델). 대표적으로는
  features/booking/domain/booking_rules_test.dart        슬롯 예약 UI 상태(P35) — 슬롯 날짜 기준 유효기간 포함
  features/bodycheck/domain/level_state_test.dart        수평계 각도→색상 상태 임계값(1°)
  features/bodycheck/domain/body_photo_storage_path_test.dart  Storage 경로 규칙(세그먼트 4개·memberId 키)
  features/bodycheck/presentation/level_simulator_test.dart    가속도계 → 각도, 시뮬 토글이 센서를 잠그는지
  features/home/domain/homework_schedule_rules_test.dart Home Work 스케줄(weekly 요일·기간, once) "오늘" 판정
  features/home/data/self_checkin_token_test.dart        스캔값 우선 / 빈 값일 때만 CHECKIN_QR_TOKEN 폴백
  features/my/domain/ledger_summary_test.dart            환불 골든값(P5) · 원장 합계 · 원화 포맷
integration_test/live_flow_test.dart                     실기기 워크스루용(`flutter test`에는 포함되지 않음)
```

## 빌드 · 실행

```bash
flutter pub get
dart run build_runner build   # riverpod_generator + freezed 코드 생성 (--delete-conflicting-outputs는 build_runner 2.15에서 제거됨)
flutter test        # 도메인 테스트는 순수 Dart라 codegen 없이도 통과.
                    # 위젯·뷰모델 테스트는 `.g.dart`가 있어야 하므로 전체 실행 전엔 build_runner를 한 번 돌린다
flutter run
```

> **2026-08-23 검증**: Flutter 3.44 로컬에서 `pub get` → `build_runner build` →
> `flutter analyze`(**이슈 0**) → `flutter test`(테스트 파일 57개) 통과를 확인했습니다.
> 백엔드 실서버(E2E)와의 요청/응답 계약은 계약 문서(../docs/API계약_v1.md) v2.x 기준으로
> 교차검증됐고, 실기기(갤럭시 S21 울트라 / Android 14) 전 화면 워크스루도 돌렸습니다
> (work_log/P01·P11 — 아래 "실기기 검증" 절).

## dev 모드 (백엔드 로컬 연동)

API계약_v1.md: `로컬 개발: X-Dev-Role: owner|trainer|member + X-Dev-Uid 허용`.
`core/network/dev_session.dart`의 `DevSession`이 이 헤더를 자동으로 붙입니다
(회원 앱이므로 role은 항상 `member`). 백엔드 base URL은 기본값
`http://localhost:8080`이며, 배포 시 `--dart-define=API_BASE_URL=https://...`로 교체하세요.

```bash
flutter run --dart-define=API_BASE_URL=https://api.rise-conditioning.example.com \
            --dart-define=CHECKIN_QR_TOKEN=<데스크 QR 토큰>   # 기본값 rise-desk-checkin(백엔드 dev 기본값과 동일)
```

셀프 체크인(P44)은 `{source:"self_qr", qr_token}` 방식입니다 — 서버가 시간창(±30분) 안의
내 confirmed 예약을 스스로 찾아 체크인하므로 booking_id를 보내지 않습니다.

**QR은 실제로 스캔합니다**(P11, `mobile_scanner 7.4.0`). 홈의 체크인 버튼이
`qr_scan_screen.dart`를 rootNavigator로 띄우고(go_router 라우트가 아닙니다 — 탭 셸 위에
전체화면으로 덮어야 해서), `barcode.rawValue`를 그대로 `Navigator.pop`으로 돌려줍니다.
**앱은 토큰 모양을 검증하지 않습니다** — 대조는 전부 서버(`CHECKIN_QR_TOKEN` 환경변수와
문자열 일치)라 앱에서 한 번 더 판정하면 규칙이 두 곳으로 갈립니다.

`CHECKIN_QR_TOKEN` dart-define은 이제 **dev 폴백**입니다: 스캔값이 비어 있을 때만 쓰입니다
(`home_remote_data_source.dart`의 `selfCheckIn(scannedToken:)`, 테스트
`test/features/home/data/self_checkin_token_test.dart`가 우선순위를 고정). 데스크에 붙일
QR 자체는 어드민이 만듭니다 — 설정 화면의 "데스크 체크인 QR"(`admin/src/features/CheckinQr.tsx`,
대표 전용). 어드민도 토큰을 서버에서 받아오지 않고 대표가 직접 입력합니다(그 값을 돌려주는
API가 없어서). 즉 운영에서 일치해야 하는 값은 **백엔드 Cloud Run 환경변수 ↔ 어드민이 QR로
찍어낸 문자열** 두 자리이고, 앱의 dart-define은 스캐너를 못 쓰는 개발 환경용 세 번째 자리입니다.

## Firebase 실연동 (P06 — 완료)

전화번호 인증이 **Firebase Phone Auth 실연동**입니다(프로젝트 `rize-218c1`, 번들·패키지
`ai.stra.rize`). 스텁은 제거됐습니다.

- **초기화**: `lib/firebase_options.dart`(수기 유지 — 값 출처는 `android/app/google-services.json`
  · `ios/Runner/GoogleService-Info.plist`)를 `main()`에서 `Firebase.initializeApp(options:)`.
  콘솔에서 앱을 재등록하면 이 파일도 함께 갱신해야 합니다.
- **인증 흐름**: `AuthRepositoryImpl`이 `verifyPhoneNumber` 4콜백을 모두 처리합니다 —
  `codeSent`는 `PhoneVerificationSession{verificationId, resendToken}`으로, 재전송(30초 버튼)은
  `forceResendingToken`으로 이어지고, Android 즉시 인증(`verificationCompleted`)은 자동
  `signInWithCredential` 후 `verifyCode`가 `currentUser.phoneNumber` 일치로 스킵합니다.
  `FirebaseAuthException` 13개 코드를 한국어 Failure로 매핑.
- **디버그 빌드**는 `setSettings(appVerificationDisabledForTesting: true)` — 콘솔 등록 테스트
  번호(`+82 10-1234-5678` / `123456`)로 시뮬레이터에서 실 SMS·과금 없이 개발합니다.
- **헤더 이중화**: `dio_client.dart`가 로그인 상태면 `Authorization: Bearer <idToken>`을 항상
  싣고 dev 헤더(`lib/core/network/dev_session.dart`)도 유지 — 백엔드가 모드별로 하나만
  사용하므로 로컬↔프로덕션 무중단 스왑이 됩니다. `POST /v1/join/match`·`confirm`도 서버가
  토큰의 `phone_number`를 우선 진실로 씁니다(계약 v1.2 주석의 실현).
- **세션 복원·로그아웃**: 앱 시작 시 `session_restore.dart`가 `currentUser`가 있으면
  `GET /v1/me`로 복원해 `/home` 직행, 실패하면 기존 온보딩. 마이 탭 하단에 로그아웃 행.

### 시각 완성도 (P09 — 완료)

- **Pretendard 번들**(`assets/fonts/PretendardVariable.ttf`, SIL OFL). 종전엔 `fontFamily`만
  선언돼 있고 파일이 없어 **전 화면이 폴백 폰트**(iOS SF Pro / Android Roboto+Noto)로 렌더됐다.
  0.5pt 단위 타입 스케일이 Pretendard의 x-height·한글 자간을 전제한 값이라, 이걸 두고 타이포를
  손대면 잘못된 기준 위의 미세조정이 된다. 가변폰트 1개로 전 굵기 커버(정적 6종 9MB보다 작다).
- **아이콘은 `RiseIcons` 하나로 통일** — `Icon(Icons.*)` 잔존 0건. `RiseIcon`은 `IconTheme.size`를
  읽지 않으므로 **호출 시 size를 반드시 명시**한다.
- **터치 타깃 44dp** — 시각 크기는 그대로 두고 히트 영역만 키운다(`RiseChip`은 배경을 칠하는
  `Container` 바깥에 패딩, `RiseRow`는 `minHeight`). 날짜 스트립은 고정 높이를 버리고 내용 기반으로
  바꿨다 — 고정 높이는 폰트가 바뀌면 라벨이 알약 밖으로 새어 나온다.
- **텍스트 배율 1.35까지 대응**(`app.dart` 클램프). iOS Dynamic Type 비접근성 최대치와 일치.
  그 이상은 고정 높이 3곳(탭바·체형 타임라인·인바디 차트) 때문에 아직 잘린다 — 남은 빚으로 명시.
- **`AppSpacing` 삭제**. 참조 0회였고 실사용 여백의 47%가 토큰 밖이었다 — 이 앱의 여백은 디자인
  스케일이 아니라 목업 CSS px의 1:1 이식이라 흡수하면 렌더가 바뀌고, 값마다 이름을 붙이면
  스케일이 아니라 별칭표가 된다. 반경은 역할이 뚜렷해 `AppRadius`로 남겼다(`app_radius.dart`).
- **스낵바 팔레트**(`rise_snack_bar.dart`) — 종전엔 성공·실패가 시각적으로 동일해 사진 저장
  결과를 색으로 구분할 수 없었다. 배지 쌍 색을 재사용해 대비 AA를 통과시켰다(흰 글씨는 미달).

### 인증 여정 보완 (P08 — 완료)

- **가입 요청이 기기에 남습니다**(`join_request_store.dart`). 종전엔 메모리에만 있어 앱을 껐다
  켜면 요청한 적 없는 것처럼 처음부터 다시 시작했고, 사용자가 중복 요청을 보내 대표 화면에 같은
  사람이 두 줄 쌓였습니다. 대기 화면에는 **"연결됐는지 확인"** 버튼이 있습니다(승인 알림이 없어
  종전엔 재요청이 유일한 방법이었습니다).
- **어떤 상태에서도 "다른 번호로 다시 시도"가 있습니다.** "본인이 아니에요"를 누르거나 가입 요청을
  보내면 CTA가 통째로 사라져 나갈 길이 없었고(AppBar·뒤로가기 없음), 안드로이드 시스템 백은
  **앱을 종료**했습니다. 세 로그인 화면 모두 `PopScope`로 처리합니다.
- **즉시 인증(안드로이드)은 코드 화면을 건너뜁니다.** SMS 없이 인증이 끝났는데 오지 않을 코드의
  재전송 카운트다운을 돌리던 문제. 단, `codeSent` **이후**에 자동회수가 오는 경우는 아직
  자동 진행되지 않습니다(확인 버튼은 동작 — 후속 과제).
- **세션 복원이 실패 종류를 구분합니다.** 네트워크 오류를 "회원 미연결"로 오독해 이미 연결된
  회원이 지하철에서 앱을 켜면 대기 화면으로 떨어졌습니다. 애매하면 온보딩이 아니라 **재확인
  화면**으로 보냅니다 — 잘못 판단해도 한 번 더 누르면 되지만, 반대로 틀리면 전화 인증을
  처음부터 다시 해야 합니다.
- **퇴사한 코치 표기**(계약 v2.0). `StaffDto.status`(필드 부재는 active로 승격 — 구버전 서버와
  마스킹 응답 모두 안전) 기준으로 담당 코치가 퇴사했으면 이름은 유지하되 `(퇴사)`를 붙이고
  아바타를 흑백 처리합니다. 표기는 **"담당이 누구인가"를 말하는 자리에만** 답니다(홈 헤더·패스
  칩, 예약 칩, 마이 패스 행) — 슬롯마다 반복하면 목록이 도배됩니다. 코치 프로필 시트는
  퇴사 / 캐시 미로드 / 프로필 미등록을 구분해 안내합니다.

프로덕션 빌드 플래그:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://rize-api-773077624928.asia-northeast3.run.app \
  --dart-define=CHECKIN_QR_TOKEN=<운영 QR 토큰>
```

`DEV_SESSION`은 릴리스 빌드에서 자동으로 꺼집니다(`DevSession.defaultEnabled`의 기본값이
`kDebugMode`). 디버그 빌드로 프로덕션 백엔드를 붙여볼 때만 `--dart-define=DEV_SESSION=false`를
명시하세요. `CHECKIN_QR_TOKEN`은 백엔드 Cloud Run 환경변수와 값이 같아야 셀프 체크인이 됩니다.

dart-define은 **이 3개가 전부**입니다(`String.fromEnvironment`/`bool.fromEnvironment` 전수 확인):

| 키 | 타입 | 기본값 | 정의 위치 |
|---|---|---|---|
| `API_BASE_URL` | String | `http://localhost:8080` | `core/network/api_config.dart` |
| `CHECKIN_QR_TOKEN` | String | `rise-desk-checkin` | `core/network/api_config.dart` |
| `DEV_SESSION` | bool | `kDebugMode`(디버그 on / 릴리스 off) | `core/network/dev_session.dart` |

## 실기기 검증 (P11)

시뮬레이터로는 **QR 스캔·실카메라·가속도계 셋 다 확인할 수 없습니다.** 실기기 검증은
갤럭시 S21 울트라(Android 14 / SDK 34)에서 돌렸고, 다음 3종을 심어 디버그 빌드로 붙입니다:

```bash
flutter run -d <device-id> \
  --dart-define=API_BASE_URL=https://rize-api-773077624928.asia-northeast3.run.app \
  --dart-define=DEV_SESSION=false \
  --dart-define=CHECKIN_QR_TOKEN=<운영 QR 토큰>
```

- `DEV_SESSION=false`가 **필수**입니다. 디버그 빌드는 기본이 `kDebugMode=true`라 dev 헤더가
  실려 나가는데, 운영 백엔드는 `FIREBASE_PROJECT`가 있어 dev 헤더를 무시합니다 — 끄지 않으면
  "왜 토큰이 안 먹히지"를 헤더 쪽에서 헤매게 됩니다.
- **테스트 전화번호는 실기기에서도 그대로 동작합니다**(`+82 10-1234-5678` / `123456`).
  디버그 빌드가 `setSettings(appVerificationDisabledForTesting: true)`를 켜므로 실 SMS·과금
  없이 등록 플로우 전체를 실기기에서 돌릴 수 있습니다. 릴리스 빌드에서는 이 우회가 없습니다.
- 실기기 워크스루에서 배운 함정은 work_log/P11에 있습니다 — 요지는 **설치본이 최신인지부터
  확인**하라는 것입니다. 스테일 APK가 `localhost:8080`을 보고 있으면 화면엔 "연결이
  불안정해요"만 떠서 백엔드 회귀처럼 보입니다.
- `integration_test/live_flow_test.dart`는 이 워크스루용이며 `flutter test`에 포함되지 않습니다.

## 하드웨어 실연동 (P11 — 완료)

세 하드웨어가 껍데기 UI가 아니라 실물 API를 씁니다. 버전은 2026-08-23 기준 stable을
pub.dev에서 확인해 고정했습니다.

| 기능 | 패키지 | 실제로 부르는 것 |
|---|---|---|
| 셀프 체크인 QR | `mobile_scanner 7.4.0` | `MobileScannerController`(`qr_scan_screen.dart`) |
| 체형 촬영 | `camera 0.12.0+2` | `CameraController`(`body_camera_provider.dart`) |
| 체형사진 업로드 | `firebase_storage 13.4.6` | `Reference.putData`(`body_photo_uploader.dart`) |
| 수평계 | `sensors_plus 7.1.0` | `accelerometerEventStream(SensorInterval.uiInterval)` |
| 권한 | `permission_handler 13.0.1` | `Permission.camera`(`core/permissions/camera_permission.dart`) |

### 체형사진 Storage 경로 — 규칙이 먼저, 코드가 나중

```
members/{memberId}/body/{yyyyMMdd}-{pose}-{direction}-{epochMillis}.jpg
```

이 모양은 취향이 아니라 **배포된 `../storage.rules`에서 역산한 제약**입니다
(`lib/features/bodycheck/domain/body_photo_storage_path.dart`에 근거 주석, 테스트로 고정):

- **세그먼트 정확히 4개.** 규칙이 `match /members/{memberId}/body/{fileName}`이라 날짜를 폴더로
  파면 `{fileName}` 와일드카드가 매칭되지 않아 업로드가 통째로 403이 됩니다.
- **경로 키는 uid가 아니라 memberId.** 규칙이 Firestore `users/{uid}`(UserIndex)를 건너가
  `member_id`를 대조합니다.
- **`image/*` + 10MB 미만.** 클라이언트가 10MB 이상이면 규칙에 닿기 전에 먼저 거부합니다
  (403보다 "다시 촬영해주세요"가 낫습니다). content-type은 항상 `image/jpeg`로 명시합니다.
- **삭제 금지**(규칙 `allow delete: if false`). 파일만 지우면 서버 메타데이터가 가리키는 곳이
  비어 고아가 됩니다.
- `getDownloadURL`은 **일부러 쓰지 않습니다** — 서버에 넘기는 `storage_path`는 버킷 내부
  경로여야 하고, 재시도는 같은 경로를 재사용해 실패 조각이 유령으로 쌓이지 않게 합니다.

업로드 성공 후에야 `POST /v1/body-photos`로 메타데이터(JSON)를 보냅니다. 실패하면
`pendingRetry`로 상태를 보존해 같은 경로로 재시도합니다(`camera_view_model.dart`).

### 수평계 — 센서는 실연동, "기울기 시뮬" 버튼은 의도적으로 남겼다

`level_simulator_provider.dart`는 이름만 옛것이고 실제로는 가속도계 스트림을 구독해
`LevelAngle.isReliable → fromAccelerometer → smooth`로 각도를 냅니다. 그런데도 촬영 화면의
**"기울기 시뮬" 버튼을 지우지 않은 이유**는 두 환경에서 서로 다른 일을 하기 때문입니다:

- **센서가 있는 실기기**: 누르면 `_manual` 플래그가 켜져 **센서 값이 각도를 덮어쓰지 못하게
  잠그고** 3.4°로 고정합니다 — 기울어짐 경고 UI를 손으로 재현해 보는 수단입니다(기기를 실제로
  기울이면 카메라 프리뷰도 같이 기울어져 무엇을 보는지 알 수 없습니다). 다시 누르면 센서 복귀.
- **센서가 없는 환경**(에뮬레이터·플러그인 부재): 구독이 실패해 `_sensorUnavailable`이 서고,
  버튼은 종전대로 0° ↔ 3.4° 토글이 됩니다.

이 동작은 `test/features/bodycheck/presentation/level_simulator_test.dart`가 고정합니다
("시뮬을 켜 두면 센서 값이 덮어쓰지 않는다").

### 하드웨어 권한 — 왜 이렇게 선언했나

**Android** (`android/app/src/main/AndroidManifest.xml`)

- 선언: `INTERNET`, `CAMERA`, 그리고 `uses-feature android.hardware.camera*`는
  `required="false"`(카메라 없는 기기에서도 설치는 되게 — 예약·기록 탭은 카메라가 필요 없습니다).
  `camera.any`에는 `tools:replace="android:required"`가 붙습니다(플러그인이 `true`로 병합하려
  들어서).
- **`RECORD_AUDIO`는 `tools:node="remove"`로 지웁니다.** `camera_android_camerax`가 동영상
  녹화용으로 매니페스트에 병합해 넣는데, 이 앱은 `enableAudio: false`로 정지 사진만 찍습니다.
  두면 **스토어 권한 목록에 마이크가 뜨고**, 쓰지도 않는 권한을 심사에서 설명해야 합니다.
- **`compileSdk = 37`** (하드코딩). `permission_handler 13.0.1`이 끌고 오는
  `permission_handler_android 14.0.0`이 compileSdk 37로 컴파일되기 때문입니다 — 낮추면 빌드가
  깨집니다. `minSdk`·`targetSdk`는 Flutter 기본값(`flutter.minSdkVersion`/`targetSdkVersion`)에
  위임하므로 **실행 대상은 targetSdk 36 그대로**입니다. compileSdk를 올린 것은 컴파일 문제이지
  동작 대상을 옮긴 게 아닙니다.

**iOS** (`ios/Runner/Info.plist`) — usage description 3종, 전부 한국어:

- `NSCameraUsageDescription` — **두 용도(체크인 QR·체형 촬영)와 열람 범위를 한 문장에** 적었습니다.
  같은 권한을 두 기능이 쓰는데 한쪽만 적으면 다른 쪽에서 요청될 때 설명이 어긋납니다.
- `NSPhotoLibraryUsageDescription` · `NSMotionUsageDescription`(수평계 가속도계).

### 남은 Firebase 트랙(이번 범위 밖)

1. **실기기 실번호 인증** — Android 디버그 SHA-1/256은 콘솔 등록 완료. iOS 실기기는 APNs
   인증키(.p8) 업로드가 필요하고, 릴리스 빌드는 릴리스 키스토어 SHA를 추가 등록해야 합니다.
   (위 "실기기 검증"은 **테스트 번호** 경로라 이 항목과 별개입니다.)
2. **체형사진 열람은 아직 회원 앱 안에서만** — 어드민은 `storage_path` 메타데이터만 보여주고
   이미지를 렌더하지 않습니다(어드민에 Storage SDK 미도입, 서명 URL 발급 API도 계약에 없음).
   `../admin/README.md`의 "알려진 한계" 참고.

## API계약 갭 현황 (2026-08-23 — v1.x 정합 패치로 대부분 해소)

초기 구현 때 계약에 없어 임시 정의했던 조회 경로들이 계약의 v1.1("가정 승인")·v1.2(3계층
교차검증) 패치로 정식화됐고, 코드도 확정 경로로 전환 완료됐습니다.

| 기능 | 상태 | 확정 경로/방식 | 위치 |
|---|---|---|---|
| 내 패스 목록 | ✅ 해소(v1.1) | `GET /v1/passes?member=` | `core/api/passes_api.dart` |
| 내 예약 목록 | ✅ 해소(v1.1) | `GET /v1/bookings?member=&from=` | `core/api/bookings_api.dart` |
| Home Work 체크 조회 | ✅ 해소(v1.1+v1.2) | `GET /v1/hw-checks?member=&date=` (date는 v1.2) | `features/home/data/home_remote_data_source.dart` |
| 내 프로필(동의 상태) | ✅ 해소(v1.2) | `GET /v1/members` → member는 본인 1건 반환 확정 | `core/api/member_api.dart` |
| 동의 수정 | ✅ 해소(v1.2) | `PUT /v1/members/{id}` member 본인 consent 허용(전이 시각 서버 기록) | `core/api/member_api.dart` |
| 일시정지·환불계산 | ✅ 해소(v1.2) | member 본인 패스 셀프서비스(홀딩 상한: 기본 2회/총 30일) | `features/my/data/my_remote_data_source.dart` |
| 전자계약 | ✅ 해소(v1.1) | `GET /v1/contracts?member=` 실 API — mock 삭제됨 | `core/api/dto/contract_dto.dart` 등 |
| 셀프 체크인 | ✅ 확정(v1.2) + 실스캔(P11) | `{source:"self_qr", qr_token}` — booking_id 불필요. qr_token은 `mobile_scanner` 스캔값(빈 값일 때만 dart-define 폴백) | `features/home/presentation/qr_scan_screen.dart`, `features/home/data/home_remote_data_source.dart` |
| 체형사진 업로드 | ✅ 확정(v1.2) + 실업로드(P11) | Firebase Storage `putData` → 실 `storage_path` → JSON 메타데이터 POST | `features/bodycheck/data/body_photo_uploader.dart`, `.../domain/body_photo_storage_path.dart` |
| 운동 세트/무게/코치 코멘트 | ✅ 해소(v1.4) | `GET /v1/workout-logs?member=` 실 API — mock 삭제, 주간 홈워크 요약도 `GET /v1/hw-checks` 실집계 | `core/api/dto/workout_log_dto.dart` 등 |
| 계약 서명 | ✅ 해소(v1.4) | `POST /v1/contracts/{id}/sign` — sent 계약 탭 → 동의 체크 → 서명(서명일·IP 서버 기록) | `features/my/presentation/widgets/contract_sign_sheet.dart` |
| 정책 하드코딩 문구 | ✅ 해소(v1.4) | `GET /v1/center` 실정책 연동 — 취소 컷오프·홀딩 상한·슬롯 용량 문구가 전부 동적(BookingRules도 cutoffHours 파라미터) | `core/policy/` |
| 대기 신청(waitlist) | 🚫 v1 제외 | 백엔드에 생성 경로 없음 + 알림 인프라 없는 자동 승격은 노쇼 함정(계약 v1.3에 예약어로만 유지) — 만석은 비활성 표시 | `features/booking/presentation/widgets/slot_list.dart` |

**2026-08-22 갱신 — v1.4 기능 패치(기능 갭 리서치·UX 여정 검수, work_log/P02):**

- **기록 탭 실데이터** — 운동 로그(코치가 완료 처리 때 남긴 수업 기록)와 주간 홈워크 요약이
  전부 실 API. 시장 기준(포인티·더잘 등 1:1 PT 제품군)의 핵심 기능이자 코어 루프의 마지막 조각.
- **계약 서명** — "서명 대기"가 실제로 끝나는 여정: 서명 시트(동의 체크 → 서명), 서명 완료 후
  어드민 미서명 카운트도 실제로 감소.
- **정책 실값** — 일시정지 상한("최대 2회/30일")·취소 컷오프("24시간 전")·시간당 팀 수가
  센터 설정을 따라 동적으로 표시(대표가 정책을 바꾸면 앱 문구·판정도 함께 변경).
- **여정 마감** — 원장 패스 선택 칩(2개 이상일 때)·홀드 시트 패스 선택·홈 카드 일시정지 배지·
  예약 탭 빈 회원권 상태 통일·"내 회원권 전체" 라벨·가입 요청 후 "승인 대기" 카드(중복 제출
  방지)·인증번호 재전송(30초)·체크인 스낵바에 차감 시점 안내.
- 검증: `flutter analyze` 0 issues · `flutter test` **49/49** · DEV_SEED 백엔드 실연동
  (member1 데모 계정) E2E 확인.

**2026-08-22 보완 — P03 검수 라운드(새눈 검수 12건 반영):** 예약 탭 빈 상태 새로고침이 실제로
재조회하도록 수정(홈 캐시 에러 재수령 버그), **정책 캐시 고착 해소**(실패 시 캐시하지 않고 성공
시에만 keepAlive + 모든 새로고침 경로에서 정책 동반 재조회 — 대표가 컷오프를 바꿔도 새로고침으로
반영), 예약/취소/홀딩 성공 시 홈 카드 즉시 동기화, 홀딩 구간 슬롯 사전 비활성("일시정지 중" 칩),
서명 실패 시 목록 실상태 동기화, 부분 실패(주간 기록·계약)를 빈 상태로 위장하지 않고 구분 표시,
취소 진행중 표시·시트 스크롤·표기 방어 등. 테스트 **50/50**.

**2026-08-18 갱신 — 2라운드(UI/UX 목업 대조 + 로직 재검증) 반영:**

- **기능 버그 수정** — "본인이 아니에요" 무반응(copyWith null 클리어 불가), 인증번호 화면
  뒤로가기 GoError, 오늘의 지난 시간대 슬롯 예약 가능(→ "지남" 비활성), center_notice
  홈워크가 트레이너 필터에 걸러지던 문제, 계약 조회 실패가 마이 탭 전체를 죽이던 문제,
  홈워크 토글 실패 롤백이 다른 항목까지 되돌리던 문제.
- **보안 연동(계약 v1.3)** — `join/confirm`에 인증한 전화번호를 함께 보내 서버가 재대조
  (유출된 member_id만으로 타인 레코드에 연결되는 체인 차단).
- **UX 완성** — 4개 탭 에러 뷰에 "다시 시도", 패스 0개 신규 회원 전용 안내 뷰(데드엔드 제거),
  pull-to-refresh(콘텐츠 짧아도 동작), 홀딩 성공 스낵바 + "일시정지 중" 배지·재개 버튼,
  체크인 완료 잠금 + 시간창 힌트, 가입 요청 시트 제출중/인라인 에러/성공 스낵바.
- **표기 정리** — 코치 조사("~가"→"~코치가"), 패스 상태 한글 매핑, 실제 상품명 표기,
  D-day 음수→"만료", "최초 1회 유예", 초대코드 잔재 문구 제거.
- 검증: `flutter analyze` 0 issues · `flutter test` **45/45**(clearMatch·PassHold 등 7개 신규).

**2026-08-22 보완 — v1.5 정산 반영 + v1.6 트레이너 프로필(work_log/P04·P05):**

- **빈 시간대 예약 가능** — 예약 탭이 운영시간(09~21시) 빈 슬롯을 합성해 표시(종전엔 예약이
  있던 시간대만 보여 셀프 예약 여정이 끊겼음). 용량은 센터 정책 실값.
- **환불 안내 정합** — 마이 탭 환불 다이얼로그가 서버 견적(실수납 기준)을 우선 표시, 클라 추정은
  정책 요율 실값 사용(10% 하드코딩 제거). 계약 "무효(환불)" 상태 표시.
- **트레이너 프로필(v1.6)** — 코치 아바타(사진 또는 이니셜)와 프로필 시트(직함·경력·전문분야·
  자격증·수상·소개): 예약 탭 "내 코치" 칩 재탭, 전체 보기 코치 태그 탭, 온보딩 매칭 카드에서
  진입. 재등록 상담·수업 선택 참고용(설계03 §9 복원).
- 슬롯 응답 최소노출(타인 예약 식별자 비수신) 대응 확인.

## 테스트 (테스트 파일 57개 · 약 600 케이스 — 2026-08-23)

> 종전 README의 "57/57"은 **파일 수**를 케이스 수로 잘못 적은 것이었습니다. `test/` 아래
> `*_test.dart`가 57개이고, `test(`/`testWidgets(` 호출은 약 600개입니다.

도메인 계층은 Flutter/코드생성 의존이 0이라(순수 Dart) 그 부분만 골라 돌리면 codegen 없이
통과합니다. 위젯·뷰모델 테스트는 `.g.dart`가 필요합니다.

- `booking_rules_test.dart` — 잔여 n/3, 코치 수업중, 만석, 내 예약, **슬롯 날짜 기준**
  유효기간(시작 전·만료 후·경계 당일 포함 — 백엔드 v1.2와 같은 축), 24시간 컷오프.
- `homework_schedule_rules_test.dart` — weekly 요일·기간, once, days 빈 값(매일) "오늘" 판정.
  **서버(`domain.HwSchedule`)와 같은 규칙**입니다 — 계약 v2.3이 이 순수 함수를 진실의 기준으로
  삼아 서버 판정을 맞췄습니다(갈리면 같은 배정이 앱과 어드민에서 다르게 보입니다).
- `level_state_test.dart` / `level_angle_test.dart` / `level_simulator_test.dart` —
  `|각도| < 1°`면 정렬(OK), 가속도계 → 각도 변환·평활, 시뮬 토글이 센서를 잠그는지.
- `body_photo_storage_path_test.dart` — Storage 경로 규칙(세그먼트 4개·memberId 키·확장자).
- `self_checkin_token_test.dart` — 스캔값 우선, 공백·빈 값일 때만 `CHECKIN_QR_TOKEN` 폴백.
- `ledger_summary_test.dart` — 환불 골든값(1,000,000·20회·7회사용·10%→refund 550,000),
  원장 합계 골든(발급 +20, 이전 11건 + 화면 2건 사용 → 잔여 7), 원화 표시 포맷팅.
