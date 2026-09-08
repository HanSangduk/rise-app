---
id: P46
title: 스토어 배포 준비 — store/ 자산(실행 캡처 스크린샷·ASO 메타·그래픽·설문) + 릴리스 갭 수리
status: 완료
domain: app
created: 2026-08-29
completed: 2026-08-30
---

# P46 — 스토어 배포 준비 (AOS + iOS)

## 목표
Google Play·App Store 제출에 필요한 것 전부를 `store/`에 실물로: **앱을 실제 실행해 찍은**
스크린샷(양 플랫폼) + ASO 캡션 프레임, 등록 메타데이터(한국어), 그래픽(512 아이콘·피처
그래픽), 데이터 보안/App Privacy 설문 답, 심사 노트, 제출 체크리스트. 릴리스 설정 갭도 수리.

## 결정 사항
- **준비도 감사**: 식별자(ai.stra.rize)·표시명·권한 문구·법정 URL·계정삭제·무추적 전부 준비 완료.
  유일 CRITICAL = Android 릴리스 서명 부재 → gradle `key.properties` 조건 배선 + `make-keystore.sh`
  (실행은 사용자 몫 — keystore 분실은 비가역).
- **스크린샷은 "앱 테스트하듯" 실행 캡처**: `flutter drive` + integration_test로 시드 백엔드(8081)에
  붙은 앱을 실기동해 7화면 순회. **로그인은 세션 직접 주입으로 우회** — Firebase SMS 인증이 드라이브
  하네스 안에서 완주되지 않는다(reCAPTCHA/APNs). API 신원은 `--dart-define=DEV_UID=member1` dev
  헤더가 시드 김민지를 가리키므로 이후 화면은 전부 실서버 데이터.
- **체형 분석 데모 사진**: AI 생성 4장(Higgsfield nano_banana_pro — 운동복·중립 포즈, IARC 전체이용가
  안전). 실 Storage에 올리지 않는다(프로덕션 신원 규칙 + P8 민감정보 자리). 시드 메타 + 캡처 전용
  로컬 HTTP 로더 오버라이드(8082)로 주입.
- **ASO 2팀 교차검증 반영**: 이름 `라이즈 컨디셔닝 - PT 회원 앱`(양 스토어 통일 — "라이즈" 단독은
  게임·RIIZE에 묻힘), iOS 부제 "수업 예약·…"(PT 중복 제거), 키워드 96/100자 전면 교체, 짧은 설명
  "회원 전용" 문두, 심사 노트 확장(가입 불가 사유·동의 상태·4.8 방어), **User ID 신고 추가**(양 팀
  공통 발견 — Play 데이터보안·App Privacy 모두 누락이었다), 스크린샷 순서 홈→예약→인바디→체형→
  수업기록→마이→코치 + 캡션 확정. 팀 간 충돌(코치 목록 vs 프로필)은 A안(목록) 채택.
- **P번호 3차 경합 정리**: 계약 축 세션과 P43 충돌 → 이 문서를 **P46**으로 재번호(피어 합의 규약).
- 계약 버전 경합(피어 세션): 상담요청 v2.17 → **v2.20** 전체 인용 이동.

## 체형 사진 계측 격자 — 기능 완성도 (람 요청)
"촬영할 때 있는 눈금이 찍힌 사진에도 있어야 얼마나 바뀌었는지 안다" → 닫았다.
- **결함의 실체**: 격자는 프리뷰 위 CustomPaint였고 `takePicture()`는 카메라 원본 JPEG을
  그대로 준다 → 다 찍고 나면 눈금이 사라져 비교 화면이 반쪽이었다(코드 주석이 이미 자각).
- **굽지 않고 표시할 때 그린다**(`MeasureGridPhoto`): 픽셀에 구우면 (a) 비가역 (b) 선이 덮은
  몇 픽셀이 판독 오차 (c) 세션마다 다른 밀도로 구워지면 **두 사진의 눈금이 서로 달라 비교가
  성립하지 않는다**. 표시 시 그리면 두 장에 언제나 같은 눈금이 올라간다. 원본 무변경.
- **좌표계**: 타일 3:4 · 사진 9:16이라 `contain` 레터박스가 생긴다 → 이미지 실비율을
  `ImageStream`으로 받아(추가 디코드 없음 — 캐시에 편승) `AspectRatio`로 페인트 박스를
  이미지에 포갠다. 뷰어는 격자를 `InteractiveViewer` **안**에 둬 확대·이동에 따라붙는다.
- **공유 기준선**: 두 사진에 같은 높이로 그어지는 빨간 선을 드래그(제스처는 두 타일을 감싼
  영역이 받는다 — 타일마다 두면 눈금자가 두 개가 된다). 어깨에 맞추면 반대쪽에서 그 선이
  어깨 위/아래 어디 걸리는지가 곧 변화량.
- 눈금 on/off + 밀도(성김/촘촘/아주 촘촘) 토글, 정직 문구("눈금은 사진에 남지 않고 볼 때만
  그려요"), 타일→뷰어로 설정 승계. 테스트 4건(실영역 페인트·off 시 미생성·기준선 전달·재페인트).

## 데모 사진 처리 (람 요청)
- 출처: **AI 생성**(Higgsfield nano_banana_pro) — 실존 인물 아님. 그래도 사람으로 읽히므로
  얼굴 픽셀레이트(타원 페더 합성) 처리. 재현 스크립트 `store/demo-photos/blur-faces.py`.
- 정면 after가 "거울/화면 촬영 + 영문 캡션"으로 생성돼 비교 사진으로 부적합 → before를
  레퍼런스로 재생성해 프레이밍 일치시킴.

## 릴리스 빌드 실버그 2건 (람이 `flutter build apk --release`로 발견)
1. **R8이 릴리스 빌드를 중단** — `Missing class ...ChineseTextRecognizerOptions` 외 5건.
   ML Kit 플러그인의 `TextRecognizer.initialize()`가 5개 스크립트 옵션을 **한 메서드에서
   전부 참조**하는데 우리는 한국어 모델만 의존에 넣었다(APK 비대 방지). → `android/
   proguard-rules.pro` 신설: 안 쓰는 3언어 `-dontwarn` + **한국어는 `-keep`**(플러그인이
   compileOnly로만 참조해 R8이 지우면 실기기에서 사진 고르는 순간 NoClassDefFoundError —
   build.gradle.kts 주석이 기록한 그 사고 자리). 디버그는 R8이 안 돌아 안 드러났다.
2. **CupertinoIcons 폰트 미포함 경고** — 앱 코드는 Cupertino를 안 쓰지만 **Flutter
   프레임워크의 Cupertino 경로**(텍스트 선택 툴바·네비바)가 참조해 도달 가능하다. 폰트가
   없으면 그 경로가 그려질 때 두부(□)가 뜬다 → `cupertino_icons ^1.0.9`(pub.dev 최신 확인)
   추가. 트리셰이킹이 257KB → **848바이트**로 줄여 비용은 무시 가능.

## API 주소 기본값 + 스토어 심사 계정 (람 요청)
- **기본값을 빌드 모드로 가름**(`api_config.dart`): 디버그 → `localhost:8080`(개발자가 매번
  dart-define을 붙이지 않아도 됨), **릴리스·프로파일 → 프로덕션 Cloud Run**. dart-define을
  주면 모드와 무관하게 그 값이 이긴다(스테이징·에뮬레이터 10.0.2.2). 종전엔 릴리스도 기본이
  localhost라 주입을 빠뜨린 빌드가 **조용히 전멸**했다 — 람이 실기기에서 만난 "연결이
  불안정해요"의 정체가 이것이었다(NetworkFailure = 서버에 못 닿음, 등록 여부와 무관).
  가드는 남긴다: 이제 막는 대상이 "빠뜨린 주입"이 아니라 **잘못 넣은 주입**(에뮬레이터
  별칭 `10.0.2.2`를 그대로 둔 스토어 빌드)이라 그 별칭도 금지 목록에 추가.
  `build-release.sh`는 URL을 더 이상 박지 않는다(두 곳이 갈릴 수 있어서).
- **심사 계정 `010-0000-0000` / 코드 `000000`**(`AuthConfig`): 국내 미할당 대역이라 실제
  가입자가 없고 Firebase 테스트 번호로 등록하면 SMS가 나가지 않는다. **릴리스에서도 이
  번호일 때만** `appVerificationDisabledForTesting`을 켠다 — 심사자 환경에서 APNs 사일런트
  검증이나 reCAPTCHA 웹뷰가 한 번이라도 걸리면 로그인 못 한 채 리젝이 오고 왕복이 며칠이다.
  스위치가 켜진 상태의 Firebase는 **콘솔 등록 테스트 번호만** 받으므로 실번호 우회 통로가
  되지 않는다. 테스트 4건으로 표기형↔E.164 일치·대역·코드 형식·입력 변형 정규화 고정.
- **셋업 2단계를 실제로 넣고 검증했다**(2026-08-30, 람이 gcloud 로그인 제공):
  ① Identity Toolkit admin API(`admin/v2/projects/{p}/config`)로 테스트 번호 등록 —
     PATCH가 맵을 통째 교체하므로 **기존 테스트 번호 2개를 읽어 병합**해서 썼다.
  ② 프로덕션 Firestore에 심사 회원·회원권·원장·인바디·수업기록 직접 기록.
     서버 API를 쓰려면 owner ID 토큰이 필요한데 그건 서비스 계정 `signJwt` 권한을 새로
     부여해야 해서(프로젝트 IAM 변경) 택하지 않았다 — 대신 **기존 문서를 읽어 저장 형태를
     그대로 복제**하고(Go `toDoc`=json.Marshal이라 시각은 RFC3339 문자열) 결과를 실앱으로 검증.
  - 실측으로 배운 것: **잔여는 패스 문서가 아니라 원장 합이 진실**이다
    (`service.hydratePassRemaining`) — 문서에 14를 적어도 서버가 원장(+20)으로 덮었다.
    완료 원장 6건을 넣어 14/20을 만들었다. 담당 코치 미배정이면 홈 코치 카드가
    "프로필을 불러오지 못했어요"로 떠서, 재직·사진 있는 정혜린 코치를 배정했다.
  - **심사자 경로 전 구간 실검증**(릴리스 APK, 에뮬레이터): 번호 → 인증번호 받기 →
    000000 → 자동 매칭 → 홈(코치 사진·잔여 링) → 기록(수업 2건·인바디 추이 곡선).

### 릴리스 산출물 검증
- `flutter build apk --release` ✅ · `flutter build appbundle --release`(프로덕션 API 주입) ✅
- AAB 86.7MB지만 **기기 다운로드는 ABI당 ~30MB** — 나머지는 디버그 심볼(~66MB)과 난독화
  맵(48MB)이라 Play가 기기로 내려보내지 않는다(구성: flutter.so 11 + mlkit OCR 10.6 + app.so 9).
- **R8 최적화 후 실기동 확인**: 에뮬레이터에 릴리스 APK 설치 → 로그인 화면 정상 렌더,
  logcat FATAL/NoClassDefFound 0건(난독화가 리플렉션 경로를 깨지 않았음을 실물로 확인).
- **릴리스 바이너리 실물 검사**(`strings libapp.so`): 프로덕션 URL 1건 · 심사 번호 1건 ·
  **`localhost:8080` 0건** — 기본값 전환이 실제 산출물에 반영됐음을 문서가 아니라 바이너리로 확인.
- 앱 테스트 **1171 pass**(API 기본값 4건 + 심사 계정 4건 추가)

## 캡처 과정에서 드러난 실버그 6건 (전부 수리)
1. **iOS Phone Auth 크래시 (사용자 발견)** — 시뮬레이터에서 "인증번호 받기" 순간
   `PhoneAuthProvider.swift:108` fatal. reCAPTCHA 폴백을 열려는데 URL 스킴이 없었다.
   실기기는 APNs 사일런트 검증 경로라 P09 실측에서 안 드러났다. → `Info.plist`
   `CFBundleURLTypes`에 인코딩 앱 ID 스킴 등록(이 프로젝트는 REVERSED_CLIENT_ID가 없다).
2. **iOS 배포 타겟** — ML Kit pod이 15.5를 요구해 `pod install`이 아예 실패(15.0). Podfile
   `platform :ios, '15.5'` + pbxproj 3곳 상향. (감사에서 "선택"으로 미뤘던 결정을 빌드가 강제)
3. **gradle 서명 배선 오류** — `android {}` 블록 안에서 `java.util.Properties`가 DSL의 `java`와
   충돌해 "Unresolved reference 'util'". 상단 import + top-level로 이동.
5. **iOS 빌드가 새 Dart 코드를 안 실었다** — SwiftPM 생성 패키지가 `.iOS("13.0")`으로 고정돼
   firebase 15.0 요구와 충돌, Xcode가 Flutter 자산 재생성을 건너뛰어 **커널 블롭이 1시간 전
   것으로 남았다**(격자 코드가 화면에 안 나와 발견 — 커널 문자열 grep으로 확정). ML Kit도
   SwiftPM 미지원이라 CocoaPods 경로로 통일(`flutter config --no-enable-swift-package-manager`)
   + Podfile `platform :ios, '15.5'`.
6. **adb 워커가 실기기 연결 시 죽음** — 갤럭시가 함께 꽂히자 `more than one device`. 대상
   지정을 `ANDROID_SERIAL` 배열 인자로(문자열 이어붙이기는 "$ADB"가 통째 파일명이 돼 실패).
4. **Android 캡처 경로가 앱을 죽임** — integration_test의 `convertFlutterSurfaceToImage` +
   `takeScreenshot`이 에뮬레이터에서 `IllegalArgumentException: Window doesn't have a backing
   surface!`(PixelCopy)로 fatal. → Android만 **adb 실캡처**로 전환: 테스트는 `[CAPTURE] name`
   마커만 흘리고 호스트 워커(`adb-capture.sh`)가 그 창에서 `adb exec-out screencap`. 실제 기기
   화면이라 더 정확하고 앱을 건드리지 않는다.

## 시드 보완(캡처 실측 반영)
- 홈워크 스케줄이 월·수·금이라 캡처일에 따라 홈 화면이 비었다 → 매일로.
- 체형 사진 날짜가 정면/측면 같은 날이라 비교가 "정면 vs 측면"으로 열렸다 → 측면 쌍을 중간
  날짜로 밀어 최신·최고참이 모두 정면이 되게(기본 비교 = 정면 vs 정면).

## 진행 단계
- [x] 릴리스 준비도 감사(식별자·서명·권한·법정 URL·심사 리스크)
- [x] 스크린샷 파이프라인 + iOS 7장 캡처(1320×2868 = 6.9" 요건) + 프레임 이미지 7장
- [x] store/ 메타데이터·그래픽·설문 + ASO 2팀 교차검증 반영
- [x] Android 캡처(adb 실캡처, 1080×2400)·프레임 7장
- [x] 최종 검증(analyze/test) + 남은 사용자 액션 정리
- [x] 패키지 `ai.stra.rize` → `com.han.rise`(Firebase 앱 재등록·SHA 재등록·AAB/APK 재빌드·
      심사 로그인 재검증: 번호 → 000000 → 센터 자동 매칭 → 홈 잔여 14회)

## 변경 파일
- `store/` 신설 전체 — README(제출 순서) · metadata/{play,appstore}.md · privacy/{play-data-safety,
  apple-app-privacy}.md · graphics/{icon-512,feature-graphic-1024x500}.png · screenshots/{capture.sh,
  frame.py,ios/{raw,final},android/{raw,final}} · scripts/{make-keystore,build-release}.sh ·
  demo-photos/(AI 생성 4장)
- `app/integration_test/store_screenshots_test.dart`(신설) · `app/test_driver/integration_test.dart`(신설)
- `app/ios/Runner/Info.plist`(URL 스킴) · `app/ios/Podfile` · `app/ios/Runner.xcodeproj/project.pbxproj`(15.5)
- `app/android/app/build.gradle.kts`(릴리스 서명 조건 배선 + proguardFiles)
- `app/android/proguard-rules.pro`(신설 — ML Kit R8 규칙)
- `app/pubspec.yaml`(cupertino_icons 추가)
- `app/lib/core/network/dev_session.dart`(DEV_UID dart-define)
- `app/lib/core/network/api_config.dart`(모드별 기본 주소 + 가드 확장) · `test/core/network/api_config_release_test.dart`
- `app/lib/features/auth/domain/auth_config.dart`(신설 — 심사 계정) · `auth_repository_impl.dart`(심사 번호 무결성 우회) · `test/features/auth/review_account_test.dart`(신설)
- `store/screenshots/adb-capture.sh`(신설 — Android 실캡처 워커)
- `backend/internal/store/seed.go`(체형 사진 4장 + 홈워크 매일 + 사진 날짜 조정)
- `app/lib/features/records/presentation/widgets/photo_measure_grid.dart`(신설 — 계측 격자)
- `app/lib/features/records/presentation/widgets/body_photo_timeline.dart`(눈금 컨트롤·공유 기준선 드래그·타일 연결·문구 정정)
- `app/lib/features/records/presentation/widgets/body_photo_viewer.dart`(뷰어 격자 승계)
- `app/test/features/records/presentation/widgets/photo_measure_grid_test.dart`(신설 4건)
- `store/demo-photos/blur-faces.py`(신설 — 얼굴 가림 재현 스크립트)

## 검증
- **스크린샷 14장**: iOS 7(1320×2868 = 6.9" 필수 슬롯) + Android 7(1080×2400), 전부 앱 실행 캡처
  → ASO 캡션 프레임 14장. 상태바는 양 플랫폼 9:41·풀배터리·풀시그널로 정돈.
- 앱: `flutter analyze` 0 issues · `flutter test` **1137 pass / 0 fail**(계측 격자 +5, 회귀 없음)
- 백엔드: `go build ./...` 그린(시드 변경 반영)
- 자문자답: 체형 비교가 "정면 vs 측면"으로 열리던 것(사진 날짜 동일)을 시드 날짜 조정으로
  정면 vs 정면 확정 / 홈워크가 요일 스케줄이라 캡처일에 따라 비던 것 → 매일로 / 코치 소개
  시트가 지연 로딩 ListView라 `ensureVisible` 무력 → `scrollUntilVisible`로 교체

## Firebase 등록 상태 점검 (람 질문: "firebase에 앱 등록은 안 해도 되나?")
앱 3종(Android·iOS·웹 어드민)은 이미 등록돼 있었다. 문제는 **등록 여부가 아니라 그 안의 값**:
- **Android SHA 지문이 디버그 키 하나뿐**이었다(실측: `~/.android/debug.keystore`의 SHA-1과
  일치). 전화 인증은 서명 인증서 지문으로 Play Integrity를 통과하므로, 릴리스는 무방비였다.
  더 위험한 건 **Play 앱 서명 키**다 — 사용자가 설치하는 APK는 Google이 다시 서명하는데
  그 지문이 없으면 실사용자 인증이 깨진다. 심사 계정은 앱 검증을 건너뛰므로 **심사는
  통과하고 출시 후에 터지는** 종류다. → `store/scripts/register-sha.sh` 신설(업로드 키는
  keystore에서 읽어 자동 등록, Play 서명 키는 인자로 받음. 중복 등록은 건너뛴다).
- **iOS teamId 미설정** → `ZG9DP757ZM`로 등록 완료.
- **iOS APNs 인증 키 미업로드**(권장) — 없으면 전화 인증이 reCAPTCHA 웹뷰로 떨어진다.
  URL 스킴은 이미 넣어 뒀으므로 동작은 하고, 심사에는 지장 없다.

## 패키지 이름 변경 `ai.stra.rize` → `com.han.rise` (람 요청)
이전 회사(stra) 네임스페이스가 스토어에 영구히 박히는 걸 막기 위해 **첫 제출 전에** 바꿨다.
출시 후에는 Play·App Store 모두 식별자 변경이 불가능해 사실상 마지막 기회였다.

핵심은 **Firebase 앱은 이름을 못 바꾼다**는 점 — 패키지/번들 ID가 앱의 키라서 새로 등록해야 했다.
- 최종 등록: Android `1:773077624928:android:66408d0259a5f46ab0fb05` ·
  iOS `1:773077624928:ios:3b39ab1c6c889eb0b0fb05`(teamId `ZG9DP757ZM` 포함)
- 설정 파일 2개 재발급 + `firebase_options.dart` 앱 ID·`iosBundleId` 수기 동기화

**철자 사고 — 두 번 갈아엎었다 (`rize` → `rise`)**
1차로 `com.han.rize`(z)로 전부 갈아끼우고 검증까지 끝냈는데, 람이 AAB를 올리자 Play가
"패키지 이름에는 `com.han.rise`가 있어야 합니다"로 거부했다. 람이 Play Console에서 앱을
만들 때 **브랜드 그래픽 "RISE CONDITIONING"을 따라 `s`로** 친 것이다. z와 s 한 글자.
- 이건 사실 감사에서 이미 적어 둔 불일치가 터진 것이다 — 후속 작업 4번 "그래픽은 RISE,
  번들·도메인은 rize, 영문 표기 통일 필요". **표기 불일치를 방치하면 사람이 둘 중 하나를
  고르는 순간에 사고가 난다**는 걸 실물로 배웠다.
- Play 패키지명은 **생성 시 확정·영구 불변**(삭제해도 그 이름 재사용 불가)인 반면 Firebase
  앱은 자유롭게 추가·삭제된다. 즉 **불변인 쪽이 진실**이고 나머지가 따라가야 한다 → 코드를
  `rise`로 맞췄다. 브랜드 그래픽과도 일치해 오래 남을 불일치가 같이 사라졌다.
- 1차에서 만든 `com.han.rize` Firebase 앱 2개는 `:remove`로 삭제. 설정 파일을 **삭제 후
  다시 받아** 잔재 클라이언트를 걷어냈다(안 하면 죽은 클라이언트가 계속 딸려 온다).
- **`Info.plist` URL 스킴 필수 교체** — 인코딩 앱 ID 기반이라 앱 ID가 바뀌면 스킴도 바뀐다.
  안 바꾸면 iOS 전화 인증이 reCAPTCHA 폴백에서 다시 크래시한다(위 실버그 1과 같은 모양).
- **SHA 지문 재등록** — 지문은 앱 단위라 새 앱엔 아무것도 없다. 디버그 키(SHA-1/256) 등록 완료.
  Play 앱 서명 키는 여전히 AAB 첫 업로드 후 수동(후속 작업 참조).
- `register-sha.sh`의 `APP_ID`도 새 앱으로 갱신(안 하면 구 앱에 계속 등록된다).

**사고 1건**: `cd app && … ; rm -rf …/ai` 에서 `cd`가 실패(이미 app 디렉터리)해 `&&` 체인이
끊겼는데 `;` 뒤의 `rm -rf`는 그대로 실행돼 `MainActivity.kt`가 이동 전에 삭제됐다. git에서
복구(스톡 4줄이라 내용 손실 없음, `git show HEAD:…`와 패키지 줄만 다름을 diff로 확인).
교훈: 파괴적 명령을 `;`로 잇지 말 것 — `&&`였다면 아무 일도 안 일어났다.

검증: APK 뱃징 `package: name='com.han.rise'` ·
`launchable-activity: name='com.han.rise.MainActivity'` — 문서가 아니라 산출물로 확인.

## 비공개 테스트 실기기에서 드러난 2건 (람 발견)
**① "앱 인증에 실패했어요" — Play 앱 서명 키 SHA 미등록**
Play에서 받은 앱으로 전화 인증이 `app-not-authorized` 계열로 떨어졌다. 원인은 예고된 자리다
(`register-sha.sh` 주석·아래 후속 작업): **업로드 키와 앱 서명 키는 다른 키**다. AAB는 내
`upload-keystore.jks`(`CN=Rize, OU=stra, O=stra.ai`, SHA-1 `ebd16b0f…`)로 서명해 올리지만,
Google이 그 서명을 벗기고 **Play 앱 서명 키로 다시 서명**해 기기에 내려보낸다. Firebase엔
디버그 키와 업로드 키만 있었으니 설치본의 지문은 아무 데도 없었다 → Play Integrity 실패.
람이 Play Console에서 앱 서명 키 SHA-1/256을 직접 등록해 해소(현재 8건 등록 = 디버그·업로드·
앱 서명 각 쌍). **업로드 키스토어 분실은 비가역이니 별도 백업 필요.**

**② 회원권이 없으면 빈 상태가 뜨기까지 38초 — Riverpod 기본 재시도**
"홈·예약 로딩이 한참 돌다가 '아직 회원권이 없어요'가 뜬다". 재시도 정책의 사고였다.
- Riverpod 3.4.2 `defaultRetry`는 **`Error`와 `ProviderException`만** 거른다. 이 앱은
  `home_view_model:51`에서 도메인 `Failure`를 **그대로 던져** 화면이 타입으로 분기하는데
  (`e is EmptyPassesFailure` → 온보딩 뷰), `Failure`는 `Error`가 아니라 필터를 통과한다.
- 그래서 **답이 바뀔 리 없는 "회원권 0개"를 10번 재시도**했다. 지연 합계
  `200+400+800+1600+3200+6400×5 = 38.2초`, 홈 리포지토리는 한 빌드에 요청 5개를 띄우므로
  **왕복 55회**. 그동안 스피너인 이유는 `element.dart` `triggerRetry`가 재시도 중에
  `AsyncError`가 아니라 `AsyncLoading(retrying: true)`을 흘리기 때문 — `when(loading:)`이 받는다.
- 회원권뿐 아니라 **던져지는 모든 도메인 실패**(거부·미연결·검증·409)가 같은 38초를 먹고 있었다.
- 수정: `lib/core/result/retry_policy.dart` 신설 + `ProviderScope(retry: appRetry)`.
  기준은 **"다시 시도하면 답이 달라질 수 있는가"** — `NetworkFailure`만 재시도하되 3회(≈1.4초),
  나머지 `Failure`는 즉시 화면으로, `Failure`가 아닌 예외는 기본 정책에 위임.
  테스트 13건으로 고정(확정 실패 8종 무재시도 · 네트워크 3회 상한 · 총 대기 2초 미만 · `Error` 제외).

## 후속 작업 (사용자 액션)
1. **[CRITICAL] Android 업로드 키 생성** — `bash store/scripts/make-keystore.sh` (gradle 배선 완료,
   실행만 남음. keystore·비밀번호 분실은 비가역이라 백업 필수)
2. **[HIGH] 버전 상향** — `app/pubspec.yaml` `0.1.0+1` → `1.0.0+1`
3. **[HIGH] 심사용 테스트 번호 확인** — Firebase 콘솔에 `+82 10-1234-5678 / 123456` 등록 여부 +
   프로덕션에 그 번호의 **승인된 회원**(회원권·기록 보유, 민감정보 동의 ON) 존재 확인
   (ASO B 지적: 동의 OFF면 심사자가 인바디·체형 화면을 못 봐 리젝 사유)
4. ~~**[MEDIUM] 피처 그래픽 영문 표기 확인**~~ — **해소.** 패키지를 `com.han.rise`로 맞춰
   그래픽 "RISE CONDITIONING"과 일치시켰다(방치했다가 Play 업로드에서 터진 그 건).
   다만 **백엔드 도메인·Firebase 프로젝트는 아직 `rize`**(`rize-api-…` / `rize-218c1`) —
   내부 인프라라 스토어 노출은 없지만, 새로 만드는 리소스는 `rise`로 통일할 것.
5. [MEDIUM] Apple 신규 연령 등급 설문(2026-01-31 이후 필수) 기준 재답변 — 결과는 4+ 예상
6. [LOW] Play Console "건강 앱(Health apps)" 선언 폼 — 개인 피트니스 기록·Health Connect 미사용

## 참조
- work_log/P19-app-icon.md(런처 아이콘) · P22(계정 삭제) · P26(법정 고지 HTML)
