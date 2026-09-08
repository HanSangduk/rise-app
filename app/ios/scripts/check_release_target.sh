#!/bin/sh
# Xcode "Run Script"(Flutter build) 앞단 가드(P60) — 릴리스/프로파일 빌드가 스크린샷 캡처용
# 설정(integration_test 진입점 · localhost dart-define)을 실어 나가지 못하게 한다.
#
# 2026-09-01 App Store 리젝(1.0(3))의 원인: store/screenshots/capture.sh(flutter drive)가 남긴
# ios/Flutter/Generated.xcconfig의 `FLUTTER_TARGET=integration_test/...`와
# `API_BASE_URL=http://localhost:8081`을 Xcode Archive가 그대로 읽어 **통합테스트를 앱으로
# 컴파일**했다. lib/main.dart의 localhost 가드(api_config.dart)는 진입점이 바뀌면 아예 돌지
# 않으므로, Dart가 아니라 **빌드 페이즈**에서 막는다. 이 스크립트는 project.pbxproj의
# Flutter "Run Script" 페이즈가 xcode_backend.sh 앞에서 호출한다.
set -eu

# Archive는 Release만 쓴다(Runner.xcscheme ArchiveAction buildConfiguration="Release"). Profile은
# `flutter run --profile`(실기기+LAN 서버)·`flutter drive --profile`(성능 측정)이 정상 개발 경로라
# 검사하지 않는다. 플레이버 구성명("Release-prod")도 Flutter와 같은 기준(소문자 release 포함)으로 잡는다.
mode=$(printf '%s' "${FLUTTER_BUILD_MODE:-${CONFIGURATION:-}}" | tr 'A-Z' 'a-z')
cfg=$(printf '%s' "${CONFIGURATION:-}" | tr 'A-Z' 'a-z')

# permission_handler_apple의 카메라 코드는 PERMISSION_CAMERA=1 매크로가 있어야 컴파일된다(Podfile post_install).
# 없으면 iOS 권한 프롬프트가 아예 뜨지 않고 permanentlyDenied가 돌아와 앱이 곧장 "설정 열기"를 보인다
# — 2026-09-07 App Store 리젝 1.0(7) 5.1.1(iv)(work_log/P67). 매크로는 **모든 구성**에 있어야 하므로
# Debug/Profile(실기기 flutter run)에서도 본다 — 이 결함은 시뮬레이터에 카메라가 없어 개발 중 눈에 띄지 않았다.
# 판정 대상은 Pods 프로젝트 파일(post_install이 build_settings를 쓰는 곳).
# SPM은 pubspec.yaml `flutter.config.enable-swift-package-manager: false`로 저장소 차원에서 꺼 두었다.
# 플러그인이 생성 SPM 패키지에 들어 있으면 그 설정이 풀린 것이다 — SPM 경로의 Package.swift는 매크로를
# Info.plist에서 유도하지만 Xcode.app에서 시작한 Archive는 cwd가 /라 앱을 못 찾아 전부 0으로 떨어진다
# (플러그인 매니페스트 주석). 조용히 넘기지 않고 실패시킨다.
spm_pkg="${SRCROOT:-.}/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
if [ -f "$spm_pkg" ] && grep -q 'permission_handler_apple' "$spm_pkg"; then
  echo "error: [check_release_target] permission_handler_apple이 SPM 패키지로 빌드된다 — pubspec.yaml flutter.config.enable-swift-package-manager: false 가 풀렸다(PERMISSION_CAMERA 매크로 경로가 Podfile을 벗어남, P67)" >&2
  exit 1
else
  pods_pbx="${PODS_ROOT:-${SRCROOT:-.}/Pods}/Pods.xcodeproj/project.pbxproj"
  if [ ! -f "$pods_pbx" ]; then
    echo "error: [check_release_target] $pods_pbx 없음 — pod install이 안 된 트리다(cd app/ios && pod install, 또는 cd app && flutter build ios --config-only)" >&2
    exit 1
  fi
  if ! grep -q 'PERMISSION_CAMERA=1' "$pods_pbx"; then
    echo "error: [check_release_target] Pods 프로젝트에 PERMISSION_CAMERA=1 이 없다 — permission_handler_apple 카메라 코드가 빠져 iOS 권한 프롬프트가 뜨지 않는다(Podfile post_install 확인 후 cd app/ios && pod install)" >&2
    exit 1
  fi
fi

case "$cfg$mode" in
  *release*) ;;
  *) exit 0 ;;   # Debug·Profile(flutter run · drive · 시뮬레이터)는 로컬 주소가 정상 사용이다.
esac
# Release 구성인데 FLUTTER_BUILD_MODE가 debug/profile이면 xcode_backend는 경고만 내고 디버그 엔진을 아카이브한다
# (xcode_backend.dart parseFlutterBuildMode · ACTION=install 경고). flutter_tools는 이 변수를 Generated.xcconfig에
# 쓰지 않으므로 손으로 박힌 xcconfig 오염이다 — 조용히 통과시키지 않는다.
case "$cfg" in *release*)
  case "$mode" in *release*) ;; *) echo "error: [check_release_target] CONFIGURATION=$CONFIGURATION 인데 FLUTTER_BUILD_MODE=${FLUTTER_BUILD_MODE:-} — 릴리스 구성이 비릴리스 Flutter 엔진을 빌드한다(xcconfig에서 FLUTTER_BUILD_MODE 제거)" >&2; exit 1 ;; esac ;;
esac

fail() {
  echo "error: [check_release_target] $1" >&2
  echo "error:   복구: cd app && flutter build ios --config-only --release   (Generated.xcconfig 재생성)" >&2
  echo "error:   또는 처음부터: bash store/scripts/build-release.sh ios" >&2
  exit 1
}

target="${FLUTTER_TARGET:-lib/main.dart}"
case "$target" in
  lib/main.dart|*/lib/main.dart|"") ;;   # `flutter run -t /절대경로/lib/main.dart`도 같은 진입점이다.
  *) fail "FLUTTER_TARGET=$target — 릴리스 진입점은 lib/main.dart 여야 한다(Generated.xcconfig가 캡처 설정으로 오염됨)" ;;
esac

# DART_DEFINES는 "base64,base64,…" — 항목마다 풀어서 본다.
if [ -n "${DART_DEFINES:-}" ]; then
  # `|| [ -n "$item" ]`: 마지막 항목은 개행이 없어 read가 거짓을 돌려준다 — 없으면 마지막 define을 건너뛴다.
  decoded=$(printf '%s' "$DART_DEFINES" | tr ',' '\n' | while IFS= read -r item || [ -n "$item" ]; do
    printf '%s' "$item" | base64 --decode 2>/dev/null || true
    printf '\n'
  done)
  for bad in 'localhost' '127.0.0.1' '10.0.2.2' 'DEV_SESSION=true' 'DEV_UID=' 'DEMO_PHOTO_BASE='; do
    if printf '%s\n' "$decoded" | grep -q -- "$bad"; then
      fail "DART_DEFINES에 '$bad' 포함 — 릴리스에 로컬/개발 설정이 실려 있다: $(printf '%s' "$decoded" | tr '\n' ' ')"
    fi
  done
  # 주소 재정의는 https만 — 실기기 개발용 LAN 주소(http://192.168.x.x:8080)가 실려 나가는 것도 같은 사고다.
  # (api_config.dart의 Dart 가드는 localhost·127.0.0.1·10.0.2.2만 보고, 진입점이 바뀌면 아예 돌지 않는다.)
  for key in API_BASE_URL LEGAL_BASE_URL; do
    if printf '%s\n' "$decoded" | grep -q "^$key=" && ! printf '%s\n' "$decoded" | grep -q "^$key=https://"; then
      fail "$key 가 https가 아니다 — 릴리스는 https 주소만 허용: $(printf '%s\n' "$decoded" | grep "^$key=")"
    fi
  done
fi

echo "[check_release_target] OK — target=$target, dart-defines 검사 통과 (${CONFIGURATION:-$mode})"
