---
id: P67
title: App Store 리젝(1.0(7)) 5.1.1(iv) 대응 — iOS 카메라 권한 프롬프트가 한 번도 뜨지 않았다
status: 완료
domain: app
created: 2026-09-08
completed: 2026-09-08
---

# P67 — iOS 카메라 권한: 프롬프트 없이 "설정 열기"로 보내던 빌드 결함

## 목표 (람 요청)
Apple 리젝(2026-09-07, iPad Air 11-inch M3, 1.0(7)) — Guideline 5.1.1(iv):
"The user is redirected to the Settings app to grant access before showing the permission request."
→ iOS에서 시스템 카메라 권한 프롬프트가 먼저 뜨게 하고, 재발을 빌드 단계에서 막는다.

## 결정 사항

### D1. 원인은 Dart가 아니라 **Podfile 매크로 누락**
`permission_handler_apple`(9.6.1, podspec 9.4.8 표기)은 권한별 네이티브 코드를 `PERMISSION_*`
전처리 매크로로 잘라 컴파일한다(ITMS-90683 회피). CocoaPods 경로에서는 이 매크로를 Podfile
`post_install`이 줘야 하는데 우리 Podfile은 Flutter 기본 그대로였다. 매크로가 0이면
`AudioVideoPermissionStrategy`가 `UnknownPermissionStrategy`를 상속해:
- `checkPermissionStatus` → **denied**
- `requestPermission` → **permanentlyDenied** (AVCaptureDevice 호출 0회)

앱 게이트(`camera_permission.dart`)는 denied면 한 번 request하고, permanentlyDenied면
"카메라 권한이 꺼져 있어요 / 설정 열기"를 그린다. 즉 QR 스캔·체형 촬영·인바디 촬영 모두
**시스템 프롬프트를 한 번도 띄우지 않고** 설정 앱으로 보냈다 — 리젝 문구 그대로.
Android는 매크로 개념이 없어 정상이었고, 그래서 개발 중 눈에 띄지 않았다.

### D2. 켜는 매크로는 `PERMISSION_CAMERA` 하나
Dart가 부르는 건 `Permission.camera`뿐이다. `Permission.photos`는 쓰지 않는다(인바디 앨범 선택은
image_picker의 PHPicker — 권한 불필요). 매크로를 켜면 해당 권한 API가 링크되므로 Usage
Description이 있는 것만 켠다(NSCameraUsageDescription ✓). 타깃도 `permission_handler_apple`로
한정해 다른 Pod의 전처리 정의를 건드리지 않는다.

### D3. 방어선은 빌드 페이즈 (P60과 같은 판단)
Dart에서는 "진짜 거부"와 "매크로 누락"을 구분할 수 없다(둘 다 permanentlyDenied). 그래서
`ios/scripts/check_release_target.sh`(Release 빌드마다 xcode_backend 앞에서 도는 가드)에
`Pods.xcodeproj/project.pbxproj`의 `PERMISSION_CAMERA=1` 존재 검사를 추가했다 — Podfile 되돌림·
`pod install` 누락을 아카이브 전에 잡는다.

### D4. 앱 UX는 그대로 둔다
권한 요청은 기능 진입 시점(QR 스캔 화면·촬영 탭·결과지 촬영)에서만 일어나고, 거부 뒤에만
설정 링크를 준다 — Apple이 권장하는 형태다. Info.plist 문구가 이유를 설명한다. 사전 설명 화면을
추가로 끼우지 않는다(요청 전 화면이 하나 더 생기는 것이 오히려 5.1.1 지적 대상이 될 수 있다).

### D5. 교차검증(리뷰 에이전트 3: iOS 네이티브/빌드 · Flutter 권한 흐름 · 스크립트 적대) 결과 반영
합산 후 중복·오탐을 제거하고 우선순위로 정리했다. 상충 1건은 아래 D6.

| 우선순위 | 발견 | 조치 |
|---|---|---|
| HIGH | 검증한 바이너리는 pbxproj 하드코드 제거 **전** 빌드라 (7)이었다. Organizer에는 결함 있는 (7) 아카이브 2개가 남아 있다 | 재빌드로 (8) 실증(아래 검증). Organizer의 "Runner 9-6-26" (7) 아카이브 2개는 **람이 삭제**(Organizer에서 옛것을 집어 올리면 verify 스크립트를 우회한다) |
| HIGH | Flutter 3.44는 **SPM 기본 ON**. 지금은 `~/.config/flutter/settings`가 꺼 둔 상태라 CocoaPods지만, 새 머신·CI에선 Package.swift를 가진 플러그인(permission_handler_apple 포함 11/13)이 Podfile을 떠나 매크로가 증발한다. SPM 경로의 매크로는 Info.plist에서 유도되지만 Xcode.app Archive는 cwd가 /라 앱을 못 찾아 전부 0 → 리젝 재현 | pubspec `flutter.config.enable-swift-package-manager: false`로 **저장소가 결정**. 가드는 플러그인이 SPM 패키지에 보이면 실패 |
| HIGH | 아카이브 검사 마커가 카메라 전용이 아니었다: `AudioVideoPermissionStrategy`는 매크로 없이도 빈 클래스로 남고(1.0(6) 실측 1건), `permissionStatus:`는 Photo/Location/Event 전략도 정의해 PERMISSION_PHOTOS=1만 있어도 통과 | 마커를 `requestAccessForMediaType:completionHandler:`(strings) **AND** `_AVMediaTypeVideo`(nm -u, 카메라 블록만 참조)로 교체. 동적 프레임워크로 바뀌는 경우도 Frameworks/ 경로를 본다 |
| MEDIUM | 매크로 검사가 Release에만 걸려 **실기기 `flutter run`에서는 못 잡는다** — 이 결함이 심사까지 살아남은 이유(시뮬레이터엔 카메라가 없다) | 검사를 모드 게이트 앞으로 — Debug/Profile 포함 매 빌드 |
| MEDIUM | Pods.xcodeproj가 없으면 경고만 하고 통과 | 하드 실패(pod install 안 된 트리) |
| MEDIUM | `NSCameraUsageDescription`이 "회원 본인과 담당 코치만"으로 실제(센터 대표도 동의 시 열람, `checkBodyPhotoAccess`)보다 **좁게** 말했다 — 앱 내 문구는 이미 고쳐졌는데(camera_preview_layer) 시스템 프롬프트만 옛 주장 | "회원 본인과 담당 코치, 센터 대표(동의 시)만" |
| MEDIUM | 게이트가 `limited`(iOS 사진 전용 상태)에서 불필요하게 request — 신규 단위 테스트가 잡음 | 조건에 `!isLimited` 추가 |
| LOW | 영구 거부 안내 "설정 > 권한 > 카메라"는 안드로이드 경로 — iOS엔 "권한" 항목이 없다 | 플랫폼 중립 "설정 앱에서 이 앱의 카메라 권한을 켠 뒤" |
| LOW | `CONFIGURATION=Release` + `FLUTTER_BUILD_MODE=debug`면 모든 검사를 조용히 건너뛰었다(xcode_backend는 경고만 내고 디버그 엔진을 아카이브) | 실패 처리 |
| LOW | `SRCROOT` 미설정 시 raw "unbound variable" · verify 스크립트 mktemp 누수(Runner 없을 때) | `${SRCROOT:-.}` · trap에 포함 |
| LOW | Podfile Ruby가 기존 값이 String이면 `<<`로 문자열 이어붙임 | String이면 split, 배열로 정규화 + uniq |
| LOW | 사용 설명 문구가 한국어뿐 — 영어 기기의 심사자는 못 읽는다 | **미반영**(후속): InfoPlist.strings 로컬라이즈는 pbxproj 변형 그룹 편집이 필요해 재심사 직전에 손대지 않는다. 심사 노트에 영문 설명으로 보완 |
| INFO | 다른 플러그인(mobile_scanner·camera_avfoundation·image_picker_ios·sensors_plus)은 자체 요청이고 매크로 게이트 없음. image_picker 앨범은 PHPicker라 권한 프롬프트 자체가 없다. `TARGETED_DEVICE_FAMILY=1`은 모든 아카이브가 동일해 iPad 호환 모드 심사에 영향 없음 | 변경 없음 |
| INFO | `app/ios/scripts/`가 **untracked**인데 Xcode 빌드 페이즈가 이 파일을 필수로 부른다 — 체크아웃에 없으면 Debug 빌드까지 실패 | 커밋 대상에 포함(람 커밋 시) |

### D6. 상충 — SPM 경로에서 가드가 "생략"이냐 "실패"냐
스크립트 리뷰는 SPM 패키지에 플러그인이 있으면 검사를 건너뛰자고 했고(Package.swift가 매크로를 유도하니까),
빌드 리뷰는 그 유도가 Xcode.app Archive에서 깨진다고 했다. 후자가 1차 출처(플러그인 매니페스트 주석)라
**실패**로 정했다 — pubspec으로 SPM을 껐으니 플러그인이 SPM 패키지에 보이는 것 자체가 설정 이탈이다.
하네스의 해당 케이스 기대값도 1로 바꿨다.

### D7. Dart 단위 테스트를 추가한 이유
네이티브 결함은 Dart에서 재현할 수 없다(매크로 누락과 "허용 안 함"이 같은 값). 그래도 게이트의 Dart 절반 —
"denied(아직 안 물어봄)면 request를 정확히 한 번 · 그 밖의 상태면 request 없음"은 프롬프트가 뜨기 위한
필요조건이라 `PermissionHandlerPlatform.instance`를 가짜로 바꿔 못 박았다(7건). 그 과정에서 D5의 `limited`
누락이 드러났다.

## 진행 단계
- [x] 원인 규명(permission_handler_apple 소스 실독 — AudioVideoPermissionStrategy.h `#else` 상속 확인)
- [x] Podfile post_install: `PERMISSION_CAMERA=1` (permission_handler_apple 타깃 · Debug/Profile/Release)
- [x] `pod install` → Pods 프로젝트 3구성에 정의 실증
- [x] check_release_target.sh 가드 추가
- [x] pubspec `1.0.0+8`
- [x] camera_permission.dart 주석(다음 사람이 같은 구멍을 다시 파지 않게)
- [x] `flutter build ios --release --no-codesign` 컴파일 검증 + 바이너리 마커 실증
- [x] pbxproj에 손으로 박힌 `FLUTTER_BUILD_NUMBER = 7` 3건 제거(P60 단일 소스 복원) → showBuildSettings 1.0.0 (8)
- [x] verify-ios-archive.sh 아카이브 단계 검사 추가(옛 1.0(5) 아카이브가 실제로 실패함을 확인)
- [x] 교차검증(에이전트 3) → D5 표 반영 · 가드 하네스 24/24 · 게이트 단위 테스트 7건
- [ ] 람: Organizer의 (7) 아카이브 2개 삭제 · 실기기(iPhone/iPad) 첫 진입 시 시스템 프롬프트 확인 → `bash store/scripts/build-release.sh ios` → 업로드 → 심사 회신

## 변경 파일
- `app/ios/Podfile` — post_install에 permission_handler_apple 전처리 정의
- `app/ios/scripts/check_release_target.sh` — Pods pbxproj `PERMISSION_CAMERA=1` 검사
- `app/pubspec.yaml` — version 1.0.0+8
- `app/lib/core/permissions/camera_permission.dart` — 주석 + `limited`는 request 없이 통과
- `app/lib/core/widgets/camera_permission_view.dart` · `test/core/widgets/camera_permission_view_test.dart` — 영구 거부 안내 경로 문구 플랫폼 중립
- `app/test/core/permissions/camera_permission_gate_test.dart` — 신규(게이트 단위 테스트 7건)
- `app/pubspec.yaml` — `flutter.config.enable-swift-package-manager: false` · dev_dependencies `plugin_platform_interface ^2.1.8`(pub.dev 최신 동일) · `permission_handler_platform_interface ^4.4.0`(락 4.4.0, pub.dev 4.4.1)
- `app/ios/Runner/Info.plist` — NSCameraUsageDescription 열람 범위를 서버 규칙과 일치
- `store/scripts/test-build-guards.sh` — 신규(가드 하네스 24건, 적대 검토 산출물 채택)
- `app/ios/Runner.xcodeproj/project.pbxproj` — Runner Debug/Release/Profile의 `FLUTTER_BUILD_NUMBER = 7` 하드코드 3건 제거(람이 Xcode에서 (7) 올리며 생긴 것으로 보임 — 두면 pubspec +8이어도 아카이브가 다시 (7)로 찍혀 업로드 거부)
- `store/scripts/verify-ios-archive.sh` — Runner 바이너리에 `permissionStatus:`·`AudioVideoPermissionStrategy` 셀렉터 존재 검사
- `app/ios/Pods/**`(untracked 산출물) — pod install 재생성

## 계약
변경 없음.

## 검증
- Pods/Pods.xcodeproj/project.pbxproj: `PERMISSION_CAMERA=1` 3건(Debug/Release/Profile · PRODUCT_NAME=permission_handler_apple)
- `flutter build ios --release --no-codesign --dart-define=DEV_SESSION=false` → ✓ Built (exit 0)
- 바이너리 셀렉터(strings Runner.app/Runner): 1.0(5) 아카이브 `permissionStatus:` 0 · `requestAccessForMediaType:completionHandler:` 0 → 새 빌드 각 1건(실제 AVCaptureDevice 요청 코드가 링크됨)
- check_release_target.sh: 정상 Pods → OK · 정의 없는 가짜 Pods → exit 1(신규 검사가 동작)
- verify-ios-archive.sh: 옛 1.0(5) 아카이브에서 신규 항목 🚨(검사가 옛 결함을 잡는다)
- `xcodebuild -showBuildSettings -configuration Release`: CURRENT_PROJECT_VERSION=8 · FLUTTER_BUILD_NAME=1.0.0
- `flutter analyze lib/core/permissions` 0건
- **교차검증 후 재빌드**(pbxproj 하드코드 제거·Podfile 정규화·pubspec SPM 핀 반영): `flutter build ios --release --no-codesign` ✓ → Runner.app **1.0.0 (8)** · `requestAccessForMediaType:completionHandler:` 1 · `nm -u _AVMediaTypeVideo` 1 · NSCameraUsageDescription 새 문구 · Frameworks/에 permission_handler 없음(정적 링크 확인)
- 가드 하네스 `store/scripts/test-build-guards.sh` **24/24**(Debug 매크로 누락 실패 · SPM 패키지 실패 · Pods 없음 실패 · PHOTOS-only 바이너리 실패 · mktemp 누수 0)
- 실제 트리에서 check_release_target.sh Debug/Release 모두 OK
- `flutter test` **1384 pass**(+7 게이트 단위 테스트)
- 미검증: **실기기에서 시스템 프롬프트가 뜨는 것** — 시뮬레이터엔 카메라가 없어 람의 실기기 확인이 필요

## 후속 작업
- 심사 회신(App Store Connect) 초안: 아래 참조.
- 실기기 확인 절차: 앱 삭제 → 재설치 → 홈 "체크인" QR 스캔 진입 → **iOS 시스템 다이얼로그**가 먼저 떠야 한다.
  "허용 안 함" 뒤에만 "설정 열기" 화면.

### 심사 회신 초안 (영문)
> Thank you for the review. We found the root cause: on iOS our permission plugin was compiled without the
> camera module, so the system camera permission prompt never appeared and the app fell through to its
> "permission is off" screen with a link to Settings. Build 1.0 (8) fixes this: when a user first opens the
> QR check-in scanner or the body-photo camera, iOS shows the standard camera permission dialog with our
> usage description. The Settings link is now shown only after the user has declined the permission.

## 참조
- Apple Submission ID 2d8ebc91-0dfd-45f1-a3d8-1b3609ec2b7d · 리뷰 2026-09-07 · iPad Air 11-inch (M3)
- permission_handler_apple README "Swift Package Manager" 절 — CocoaPods는 Podfile 매크로 필수
- work_log/P60 (빌드 페이즈 가드 선례) · P11 (권한 게이트 도입)
