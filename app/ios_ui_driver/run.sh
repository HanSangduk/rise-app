#!/usr/bin/env bash
# iOS 실기기 UI 드라이버(P77) — 설치된 라이즈 앱(com.han.rise)을 XCUITest로 사람처럼 조작한다.
# 왜 따로 있나: Flutter 통합 테스트는 Flutter 위젯만 누른다 — reCAPTCHA 사파리 시트를 스와이프로 닫는 것 같은
# **네이티브 화면 조작**은 못 한다. 이 드라이버는 번호 입력·버튼·시트 닫기 제스처를 실제 터치로 보낸다.
#
# 전제(기기에서 처음 한 번 — 사람 손 필요):
#   아이폰 설정 › 개발자 › "UI 자동화 활성화" 켜기 → 첫 실행 때 폰에 뜨는 자동화 모드 승인(암호).
#   승인 전에는 1분 만에 "Timed out while enabling automation mode"로 끝난다(2026-10-16 실측).
# 대상 앱: 실제 앱(lib/main.dart) 릴리스 빌드가 깔려 있어야 한다 — --install 이 빌드·설치까지 한다.
#
# 사용(app/에서): bash ios_ui_driver/run.sh [--install] [시험 이름, 예: test02_dismissByEdgeSwipe]
#   IOS_UDID=<기기 UDID> 로 기기를 고를 수 있다(없으면 연결된 첫 iPhone).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$HERE/.." && pwd)"
FLUTTER="${FLUTTER:-flutter}"
INSTALL=0; FILTER=""
for a in "$@"; do
  case "$a" in --install) INSTALL=1 ;; *) FILTER="$a" ;; esac
done
command -v python3 > /dev/null || { echo "python3가 필요하다(기기 탐지 JSON 해석)"; exit 2; }

# 임시 파일 정리 + **빌드가 실패하거나 중단돼도** pbxproj를 빌드 전 사본으로 되돌린다(P77 반박 검토 M1 —
# set -e로 빌드 실패 시 복원 줄에 닿기 전에 끝나 추적 파일이 수정된 채 남았다).
J=""; BAK=""; PBX=""
restore_pbx() { if [ -n "$BAK" ] && [ -f "$BAK" ]; then cp -p "$BAK" "$PBX"; rm -f "$BAK"; BAK=""; fi; }
trap 'restore_pbx; [ -z "$J" ] || rm -f "$J"' EXIT
trap 'exit 130' INT TERM

if [ -z "${IOS_UDID:-}" ]; then
  J="$(mktemp)"
  xcrun devicectl list devices --json-output "$J" > /dev/null 2>&1 || true
  IOS_UDID="$(python3 -I -c '
import json, sys
try:
    devs = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
# tunnelState는 devicectl 작업 중에만 connected다(평소 disconnected — 실측) — 페어링·연결 경로·부팅으로 고른다.
for d in devs:
    hw, cp, dp = d.get("hardwareProperties", {}), d.get("connectionProperties", {}), d.get("deviceProperties", {})
    if (hw.get("deviceType") == "iPhone" and cp.get("pairingState") == "paired"
            and cp.get("transportType") in ("wired", "localNetwork") and dp.get("bootState") == "booted"):
        print(hw.get("udid", "")); break
' "$J")"
fi
[ -n "${IOS_UDID:-}" ] || { echo "연결된 iPhone을 못 찾았다 — IOS_UDID=<UDID> 로 지정"; exit 2; }
echo "기기: $IOS_UDID"

if [ "$INSTALL" = 1 ]; then
  # flutter build가 추적 파일 project.pbxproj를 고친다(Flutter 마이그레이션 objectVersion · pod install 재직렬화)
  # — 빌드 전 사본으로 되돌린다(P77 실측).
  PBX="$APP/ios/Runner.xcodeproj/project.pbxproj"; BAK="$(mktemp)"; cp -p "$PBX" "$BAK"
  STAMP="$(mktemp)"; touch "$STAMP"
  (cd "$APP" && "$FLUTTER" build ios --release)
  restore_pbx
  # build/ios/iphoneos/Runner.app 사본은 서명이 깨져 설치가 안 된다 — Xcode 실제 산출물을 쓴다.
  REL="$APP/build/ios/Release-iphoneos/Runner.app"
  { [ "$REL/Runner" -nt "$STAMP" ] || [ "$REL/Info.plist" -nt "$STAMP" ]; } || { rm -f "$STAMP"; echo "낡은 산출물: $REL"; exit 3; }
  rm -f "$STAMP"
  codesign --verify --deep --strict "$REL"
  # 설치가 한 번씩 0xe8008001(Flutter.framework 서명 검증)로 튕기고 재시도는 붙는다(P77 실측) — 1회 재시도.
  xcrun devicectl device install app --device "$IOS_UDID" "$REL" || { sleep 5; xcrun devicectl device install app --device "$IOS_UDID" "$REL"; }
fi

T="${TMPDIR:-/tmp}"; T="${T%/}"
DD="$T/rise_ui_driver_dd"
RB="$T/rise_ui_driver_$(date +%Y%m%d-%H%M%S).xcresult"
ONLY=()
[ -n "$FILTER" ] && ONLY=(-only-testing:"DriverUITests/DriverUITests/$FILTER")
set +e
xcodebuild test -project "$HERE/RiseUIDriver.xcodeproj" -scheme DriverUITests -destination "id=$IOS_UDID" \
  -derivedDataPath "$DD" -resultBundlePath "$RB" -allowProvisioningUpdates ${ONLY[@]+"${ONLY[@]}"} > "$RB.log" 2>&1
rc=$?
set -e
grep -E '\[P75D\]|Test Case .*(passed|failed)|Timed out while enabling automation|error:' "$RB.log" || true
echo "종료 코드 $rc · 로그 $RB.log · 결과 번들 $RB"
echo "스크린샷: xcrun xcresulttool export attachments --path $RB --output-path <폴더>"
exit $rc
