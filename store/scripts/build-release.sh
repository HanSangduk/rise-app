#!/usr/bin/env bash
# 스토어 제출용 릴리스 빌드(P46) — API_BASE_URL 주입을 절대 빠뜨리지 않는 단일 경로.
# (주입을 빠뜨린 릴리스는 앱이 기동 시 StateError로 스스로 멈춘다 — api_config.dart)
#
# 사용:
#   bash store/scripts/build-release.sh android   # → app/build/app/outputs/bundle/release/app-release.aab
#   bash store/scripts/build-release.sh ios       # → Xcode 아카이브용 빌드(업로드는 Xcode Organizer)
set -euo pipefail
cd "$(dirname "$0")/../../app"

API_BASE_URL="${API_BASE_URL:-https://rize-api-773077624928.asia-northeast3.run.app}"
DEFINES=(--dart-define=API_BASE_URL="$API_BASE_URL" --dart-define=DEV_SESSION=false)

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
    # --no-codesign 없이: Automatic signing(팀 4RQD93MV57)으로 서명까지.
    # 업로드는 `open ios/Runner.xcworkspace` → Product > Archive > Distribute.
    flutter build ipa --release "${DEFINES[@]}"
    echo "IPA: build/ios/ipa/ (또는 Xcode Organizer에서 업로드)"
    ;;
  *)
    echo "사용: $0 android|ios"; exit 1 ;;
esac
