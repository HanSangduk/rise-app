#!/usr/bin/env bash
# 스토어 스크린샷 캡처(P46) — 시드 백엔드(8081) + integration_test 드라이브.
# iOS: iPhone 16 Pro Max(6.9", 1320x2868 — App Store 요건 충족)
# AOS: rise_test AVD(Pixel 계열)
#
# 사용: bash store/screenshots/capture.sh ios|android
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/app"

# flutter drive는 ios/Flutter/Generated.xcconfig에 캡처용 진입점(integration_test)과 localhost
# dart-define을 남긴다. 그 뒤 Xcode Organizer에서 Archive하면 그 파일을 그대로 읽어 **통합테스트를
# 앱으로 컴파일**한다 — 2026-09-01 App Store 리젝 1.0(3)의 원인(P60). 어떻게 끝나든 복원한다.
# (Xcode 빌드 페이즈 가드 ios/scripts/check_release_target.sh가 2차 방어선이다.)
# android 분기에는 걸지 않는다 — Android `flutter drive`는 iOS xcconfig를 쓰지 않는다(flutter_tools
# `updateGeneratedXcodeProperties` 호출처는 iOS/macOS 경로뿐). ios 분기에서 trap을 등록한다.
restore_xcconfig() {
  echo "[capture] ios/Flutter/Generated.xcconfig 복원 — flutter build ios --config-only --release (pod install이 낄 수 있어 10~30초)"
  if ! flutter build ios --config-only --release 2>&1 | tail -3; then
    echo "⚠ xcconfig 복원 실패 — 아카이브 전에 반드시: (cd app && flutter build ios --config-only --release)"
  fi
}

# 시드 백엔드(사진 트레이너 t1/t2/t3 + 김민지 패스 2개) — 이미 떠 있으면 재사용.
if ! curl -sf http://localhost:8081/health >/dev/null 2>&1; then
  (cd "$ROOT/backend" && DEV_SEED=true PORT=8081 go run ./cmd/server &)
  sleep 4
fi

photo_server() {
  if ! curl -sf http://localhost:8082/stand-front-before.jpg >/dev/null 2>&1; then
    (cd "$ROOT/store/demo-photos" && python3 -m http.server 8082 >/dev/null 2>&1 &)
    sleep 1
  fi
}

drive() {
  STORE_SHOT_DIR="$ROOT/store/screenshots/$1/raw" flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/store_screenshots_test.dart \
    -d "$2" --dart-define=API_BASE_URL="$3" --dart-define=DEMO_PHOTO_BASE="$4" --dart-define=DEV_UID=member1
}

# 캡처 뒤 제출용 프레임 이미지: store/screenshots/frame.py 참고(README).

case "${1:-}" in
  ios)
    trap restore_xcconfig EXIT
    UDID=$(xcrun simctl list devices available | grep "iPhone 16 Pro Max" | head -1 | grep -oE '[0-9A-F-]{36}')
    xcrun simctl boot "$UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$UDID" -b
    xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
    photo_server
    drive ios "$UDID" http://localhost:8081 http://localhost:8082
    ;;
  android)
    ~/Library/Android/sdk/emulator/emulator -avd rise_test -no-snapshot -no-boot-anim &
    ~/Library/Android/sdk/platform-tools/adb wait-for-device
    until [[ "$(~/Library/Android/sdk/platform-tools/adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do sleep 2; done
    # **제스처 내비게이션을 강제한다**(P54). AVD 설정은 재부팅해도 남아서, 누군가
    # 3버튼으로 바꿔 테스트한 뒤 그대로 찍으면 스토어 이미지 하단에 **검은 띠 + 버튼
    # 잔상**이 박힌다(데모 모드는 상태바만 정리하고 내비바는 손대지 않는다).
    # 제스처면 얇은 핸들만 남아 스토어 이미지로 쓸 수 있다.
    ~/Library/Android/sdk/platform-tools/adb shell cmd overlay enable com.android.internal.systemui.navbar.gestural || true
    sleep 2
    # 데모 모드 상태바(시계 고정·알림 숨김) — 에뮬레이터 API 23+.
    ~/Library/Android/sdk/platform-tools/adb shell settings put global sysui_demo_allowed 1
    ~/Library/Android/sdk/platform-tools/adb shell am broadcast -a com.android.systemui.demo -e command enter
    ~/Library/Android/sdk/platform-tools/adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
    ~/Library/Android/sdk/platform-tools/adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
    ~/Library/Android/sdk/platform-tools/adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
    ~/Library/Android/sdk/platform-tools/adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
    # 에뮬레이터 → 호스트는 10.0.2.2.
    photo_server
    # Android는 integration_test의 takeScreenshot이 에뮬레이터에서 앱을 죽인다
    # (PixelCopy "Window doesn't have a backing surface!") — 테스트가 `[CAPTURE] name`
    # 마커만 흘리고, 이 워커가 그 순간 adb로 실기기 화면을 찍는다.
    LOG=/tmp/drive_android.log
    : > "$LOG"
    bash "$ROOT/store/screenshots/adb-capture.sh" "$LOG" "$ROOT/store/screenshots/android/raw" &
    drive android emulator-5554 http://10.0.2.2:8081 http://10.0.2.2:8082 2>&1 | tee -a "$LOG"
    ~/Library/Android/sdk/platform-tools/adb shell am broadcast -a com.android.systemui.demo -e command exit
    ;;
  *) echo "사용: $0 ios|android"; exit 1 ;;
esac
