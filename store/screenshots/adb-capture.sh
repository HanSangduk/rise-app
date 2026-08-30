#!/usr/bin/env bash
# Android 실캡처 워커(P46) — drive 로그의 `[CAPTURE] {name}` 마커를 보고 그 순간
# `adb exec-out screencap`으로 기기 화면을 찍는다.
#
# 왜 integration_test의 takeScreenshot을 안 쓰나: 에뮬레이터에서 그 경로
# (convertFlutterSurfaceToImage → PixelCopy)가 "Window doesn't have a backing surface!"로
# **앱을 죽인다**(실측). adb 캡처는 실제 기기 화면이라 더 정확하고 앱을 건드리지 않는다.
#
# 사용: bash store/screenshots/adb-capture.sh <로그경로> <출력디렉터리>
set -euo pipefail
LOG="${1:?로그 경로}"
OUT="${2:?출력 디렉터리}"
# 실기기가 함께 꽂혀 있으면 adb가 "more than one device"로 죽는다 — 대상은 호출자가
# ANDROID_SERIAL로 정한다. **배열로 둔다**: 문자열에 -s를 이어 붙이면 "$ADB"가
# 통째로 파일명으로 해석돼 "No such file or directory"가 난다(실측).
ADB=("$HOME/Library/Android/sdk/platform-tools/adb")
if [ -n "${ANDROID_SERIAL:-}" ]; then ADB+=(-s "$ANDROID_SERIAL"); fi
mkdir -p "$OUT"

tail -n +1 -F "$LOG" | while IFS= read -r line; do
  case "$line" in
    *"[CAPTURE] "*)
      name="${line##*\[CAPTURE\] }"
      name="$(echo "$name" | tr -d '\r' | awk '{print $1}')"
      sleep 1.2   # 화면 정착(리스트 페인트·이미지 디코드)
      "${ADB[@]}" exec-out screencap -p > "$OUT/$name.png"
      echo "[SHOT] $OUT/$name.png ($(wc -c < "$OUT/$name.png") bytes)"
      ;;
    *"All tests passed"*|*"Some tests failed"*)
      exit 0 ;;
  esac
done
