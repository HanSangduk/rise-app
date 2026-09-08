#!/usr/bin/env bash
# iOS 아카이브 실물 검사(P60) — 업로드 전에 "이 바이너리가 진짜 회원 앱인가"를 문서가 아니라
# 산출물로 확인한다. 2026-09-01 리젝은 아카이브 3개가 전부 통합테스트+localhost로 컴파일된
# 채 올라간 사고였고, 이 검사 하나면 업로드 전에 잡혔다.
#
# 사용: bash store/scripts/verify-ios-archive.sh [Runner.xcarchive 경로]
#   경로 생략 시 app/build/ios/archive/Runner.xcarchive (`flutter build ipa` 산출물).
#   Xcode Organizer 아카이브는 ~/Library/Developer/Xcode/Archives/<날짜>/<이름>.xcarchive
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARCHIVE="${1:-$ROOT/app/build/ios/archive/Runner.xcarchive}"
APP_DIR="$ARCHIVE/Products/Applications/Runner.app"
BIN="$APP_DIR/Frameworks/App.framework/App"
PROD_HOST="rize-api-773077624928.asia-northeast3.run.app"
BUNDLE_ID="com.han.rise"
REVIEW_PHONE="+821000000000"

[ -f "$BIN" ] || { echo "🚫 App 바이너리가 없다: $BIN"; exit 1; }
[ -f "$APP_DIR/Runner" ] || { echo "🚫 Runner 바이너리가 없다: $APP_DIR/Runner"; exit 1; }

fails=0
ok()  { echo "✓ $1"; }
bad() { echo "🚨 $1"; fails=$((fails+1)); }

ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Info.plist")
bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Info.plist")
echo "아카이브: $ARCHIVE"
echo "버전 $ver ($build) · 번들 $bundle"

STR=$(mktemp); RUNNER_STR=$(mktemp); trap 'rm -f "$STR" "$RUNNER_STR"' EXIT
strings "$BIN" > "$STR"

if [ "$bundle" = "$BUNDLE_ID" ]; then ok "번들 ID $BUNDLE_ID"; else bad "번들 ID가 $BUNDLE_ID 가 아니다: $bundle"; fi

# pubspec의 version(예: 1.0.0+4)과 일치해야 "지금 트리로 만든 아카이브"다 — 리젝된 3개는 1·2·3이었고
# Organizer 목록에서 옛것을 집어 올리는 실수를 여기서 잡는다.
pub=$(grep -E '^version:' "$ROOT/app/pubspec.yaml" | sed -E 's/^version:[[:space:]]*//; s/[[:space:]]+$//')
pub_name=${pub%%+*}; pub_build=${pub##*+}
if [ "$ver" = "$pub_name" ] && [ "$build" = "$pub_build" ]; then ok "pubspec 버전 일치($pub)"; else bad "pubspec($pub)과 아카이브($ver ($build))의 버전이 다르다 — 옛 아카이브이거나 pubspec을 올리고 다시 빌드하지 않았다"; fi

n=$(grep -c "$PROD_HOST" "$STR" || true)
if [ "$n" -ge 1 ]; then ok "프로덕션 API 주소 포함(${n}건)"; else bad "프로덕션 API 주소($PROD_HOST)가 바이너리에 없다 — 캡처/로컬 설정으로 빌드됐다"; fi

# URL 형태만 본다: api_config.dart의 가드 코드가 'localhost'·'127.0.0.1' 리터럴을 contains 인자로
# 들고 있어 그 낱말 자체는 정상 릴리스에도 있다. 사설망(LAN 개발 서버) http 주소도 같은 사고다.
local_urls=$(grep -E 'https?://(localhost|127\.[0-9.]+|10\.[0-9.]+|192\.168\.[0-9.]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9.]+)(:[0-9]+)?' "$STR" | sort -u | tr '\n' ' ' || true)
if [ -z "$local_urls" ]; then ok "로컬·사설망 API 주소 0건"; else bad "로컬·사설망 API 주소가 박혀 있다: $local_urls"; fi

n=$(grep -c "integration_test" "$STR" || true)
if [ "$n" -eq 0 ]; then ok "integration_test 문자열 0건"; else bad "integration_test 문자열 ${n}건 — 통합테스트가 진입점으로 컴파일됐다"; fi
n=$(grep -c -E "store_screenshots|takeScreenshot" "$STR" || true)
if [ "$n" -eq 0 ]; then ok "캡처 하네스 마커(store_screenshots·takeScreenshot) 0건"; else bad "캡처 하네스 마커 ${n}건 — 스크린샷 테스트 코드가 바이너리에 있다"; fi

# integration_test.framework(네이티브 플러그인 셸)는 dev_dependency인데도 Flutter 3.44 iOS 릴리스 번들에
# 항상 링크된다(P60에서 정상 빌드로 실측). 판정 근거는 **Dart 쪽 문자열**(위)이고 이 줄은 정보다.
if [ -d "$APP_DIR/Frameworks/integration_test.framework" ]; then echo "ℹ integration_test.framework 링크됨(정상 릴리스에도 포함 — dev_dependency 플러그인 셸, 판정 무관)"; fi

# iOS 카메라 권한 프롬프트(P67): permission_handler_apple은 PERMISSION_CAMERA=1 매크로가 있어야
# AudioVideoPermissionStrategy의 실제 구현(+permissionStatus: · AVCaptureDevice 요청)을 컴파일한다.
# 매크로가 빠진 1.0(7)은 프롬프트 없이 permanentlyDenied를 돌려줘 5.1.1(iv) 리젝. 이 셀렉터는
# Runner 바이너리(정적 링크)에서 카메라 블록 고유 마커의 존재로 판정한다(1.0(6) 아카이브 실측 0건 → 새 빌드 1건).
# 판정 문자열은 카메라 블록(#if PERMISSION_CAMERA)에서만 나오는 것이어야 한다: `AudioVideoPermissionStrategy`는
# 매크로가 없어도 빈 클래스로 컴파일돼 항상 있고(1.0(6) 실측 1건), `permissionStatus:`는 Photo/Location/Event
# 전략도 같은 이름으로 정의해 PERMISSION_PHOTOS=1만 있어도 나온다. `_AVMediaTypeVideo` 외부 심볼은 카메라 블록
# (permissionStatus:AVMediaTypeVideo · mediaType = AVMediaTypeVideo)만 참조한다 — strings엔 안 보이고 nm -u로 본다.
# 플러그인은 static_framework(podspec)라 Runner에 정적 링크되지만, 동적으로 바뀌면 Frameworks/ 아래 프레임워크를 본다.
cam_bin_ok() { [ -f "$1" ] || return 1; strings "$1" > "$RUNNER_STR"; grep -qx 'requestAccessForMediaType:completionHandler:' "$RUNNER_STR" && nm -u "$1" 2>/dev/null | grep -qx '_AVMediaTypeVideo'; }
cam_ok=0
if cam_bin_ok "$APP_DIR/Runner" || cam_bin_ok "$APP_DIR/Frameworks/permission_handler_apple.framework/permission_handler_apple"; then cam_ok=1; fi
if [ "$cam_ok" -eq 1 ]; then ok "permission_handler 카메라 구현 링크됨(PERMISSION_CAMERA=1)"; else bad "permission_handler 카메라 구현이 바이너리에 없다 — Podfile post_install의 PERMISSION_CAMERA=1 · pod install 확인(iOS 권한 프롬프트가 안 뜬다, P67)"; fi

n=$(grep -c -- "$REVIEW_PHONE" "$STR" || true)
if [ "$n" -ge 1 ]; then ok "심사 계정 번호 포함(APNs/reCAPTCHA 우회 스위치 살아 있음)"; else bad "심사 계정 번호($REVIEW_PHONE)가 없다 — 심사자 로그인이 앱 검증에 걸릴 수 있다"; fi

if [ "$fails" -eq 0 ]; then
  echo "✅ 아카이브 검사 통과 — 업로드해도 된다 ($ver ($build))"
else
  echo "❌ ${fails}건 실패 — 업로드하지 말 것. 복구: cd app && flutter build ios --config-only --release 후 bash store/scripts/build-release.sh ios"
  exit 1
fi
