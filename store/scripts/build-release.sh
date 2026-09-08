#!/usr/bin/env bash
# 스토어 제출용 릴리스 빌드(P46 → P60) — 스토어 바이너리를 만드는 **유일한 경로**.
#
# iOS는 반드시 여기서 만든다. `flutter build ipa`가 ios/Flutter/Generated.xcconfig를 lib/main.dart
# 진입점 + 릴리스 dart-define으로 다시 쓰기 때문이다. Xcode Organizer에서 직접 Archive하면 마지막
# `flutter run/drive`가 남긴 설정(스크린샷 캡처의 integration_test 진입점 + localhost API)이 그대로
# 실린다 — 2026-09-01 App Store 리젝 1.0(3)이 정확히 그 사고였다(work_log/P60).
#
# 사용:
#   bash store/scripts/build-release.sh android   # → app/build/app/outputs/bundle/release/app-release.aab
#   bash store/scripts/build-release.sh ios       # → app/build/ios/ipa/*.ipa + 아카이브 실물 검사
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../../app"

# API 주소는 **주입하지 않는 것이 기본**이다 — 릴리스 기본값이 이미 프로덕션이고
# (lib/core/network/api_config.dart), 여기서 다시 박으면 두 곳이 갈릴 수 있다.
# 스테이징 등으로 덮어쓸 때만 API_BASE_URL 환경변수를 준다(그 값이 이긴다).
DEFINES=(--dart-define=DEV_SESSION=false)
if [ -n "${API_BASE_URL:-}" ]; then
  DEFINES+=(--dart-define=API_BASE_URL="$API_BASE_URL")
  echo "API_BASE_URL 재정의: $API_BASE_URL"
fi

case "${1:-}" in
  android)
    if [[ ! -f android/key.properties ]]; then
      echo "⚠ android/key.properties 없음 — debug 키로 서명됩니다(Play 업로드 불가)."
      echo "  먼저: bash store/scripts/make-keystore.sh"
      exit 1
    fi
    flutter build appbundle --release "${DEFINES[@]}"
    echo "AAB: build/app/outputs/bundle/release/app-release.aab"
    ;;
  ios)
    # Automatic signing(팀 ZG9DP757ZM)으로 아카이브 + App Store용 IPA 내보내기.
    # Xcode 빌드 페이즈 가드(ios/scripts/check_release_target.sh)가 캡처 설정을 한 번 더 막는다.
    # `flutter build ipa`는 아카이브 뒤 IPA 내보내기(exportArchive)가 실패해도 **exit 0**으로 끝난다
    # (P60 실측: "No signing certificate iOS Distribution found" — 로그인 키체인이 잠긴 뒤 실행하면 난다).
    # 그래서 IPA가 이번 아카이브보다 새 파일인지 직접 확인한다 — 옛 IPA를 새 것으로 착각해 올리는 사고 방지.
    rm -f build/ios/ipa/*.ipa
    flutter build ipa --release --export-method app-store "${DEFINES[@]}"
    IPA=$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)
    if [ -z "$IPA" ] || [ ! "$IPA" -nt build/ios/archive/Runner.xcarchive/Info.plist ]; then
      echo "🚫 아카이브는 됐지만 IPA 내보내기가 실패했다(build/ios/ipa에 새 .ipa 없음)."
      echo "   흔한 원인: 로그인 키체인 잠김(화면 잠금 후) 또는 Xcode 계정 세션 만료 → 키체인을 열고(잠금 해제) 다시:"
      echo "   xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive -exportOptionsPlist build/ios/ipa/ExportOptions.plist -exportPath build/ios/ipa -allowProvisioningUpdates"
      echo "   또는 open build/ios/archive/Runner.xcarchive → Organizer > Distribute App"
      exit 1
    fi
    echo "아카이브: build/ios/archive/Runner.xcarchive · IPA: $IPA"
    # 업로드 전 실물 검사 — 프로덕션 주소 · 로컬 주소 0 · 통합테스트 잔재 0 · 심사 번호.
    bash "$SCRIPT_DIR/verify-ios-archive.sh" "$PWD/build/ios/archive/Runner.xcarchive"
    echo "업로드: Transporter 앱에 build/ios/ipa/*.ipa 를 넣거나, open build/ios/archive/Runner.xcarchive → Organizer > Distribute App"
    ;;
  *)
    echo "사용: $0 android|ios"; exit 1 ;;
esac
