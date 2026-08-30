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

## 변경 파일
- `store/` 신설 전체 — README(제출 순서) · metadata/{play,appstore}.md · privacy/{play-data-safety,
  apple-app-privacy}.md · graphics/{icon-512,feature-graphic-1024x500}.png · screenshots/{capture.sh,
  frame.py,ios/{raw,final},android/{raw,final}} · scripts/{make-keystore,build-release}.sh ·
  demo-photos/(AI 생성 4장)
- `app/integration_test/store_screenshots_test.dart`(신설) · `app/test_driver/integration_test.dart`(신설)
- `app/ios/Runner/Info.plist`(URL 스킴) · `app/ios/Podfile` · `app/ios/Runner.xcodeproj/project.pbxproj`(15.5)
- `app/android/app/build.gradle.kts`(릴리스 서명 조건 배선)
- `app/lib/core/network/dev_session.dart`(DEV_UID dart-define)
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

## 후속 작업 (사용자 액션)
1. **[CRITICAL] Android 업로드 키 생성** — `bash store/scripts/make-keystore.sh` (gradle 배선 완료,
   실행만 남음. keystore·비밀번호 분실은 비가역이라 백업 필수)
2. **[HIGH] 버전 상향** — `app/pubspec.yaml` `0.1.0+1` → `1.0.0+1`
3. **[HIGH] 심사용 테스트 번호 확인** — Firebase 콘솔에 `+82 10-1234-5678 / 123456` 등록 여부 +
   프로덕션에 그 번호의 **승인된 회원**(회원권·기록 보유, 민감정보 동의 ON) 존재 확인
   (ASO B 지적: 동의 OFF면 심사자가 인바디·체형 화면을 못 봐 리젝 사유)
4. **[MEDIUM] 피처 그래픽 영문 표기 확인** — 그래픽은 "RISE CONDITIONING", 번들·도메인은 `rize`.
   센터 공식 영문 표기로 통일 필요(ASO A 지적)
5. [MEDIUM] Apple 신규 연령 등급 설문(2026-01-31 이후 필수) 기준 재답변 — 결과는 4+ 예상
6. [LOW] Play Console "건강 앱(Health apps)" 선언 폼 — 개인 피트니스 기록·Health Connect 미사용

## 참조
- work_log/P19-app-icon.md(런처 아이콘) · P22(계정 삭제) · P26(법정 고지 HTML)
