#!/usr/bin/env bash
# iOS 빌드 가드 두 개(P60/P67)의 자립 테스트 하네스 — 저장소는 읽기만 하고 픽스처는 전부 $TMPDIR 아래.
#   app/ios/scripts/check_release_target.sh: 가짜 Pods 트리 + 환경변수 매트릭스
#   store/scripts/verify-ios-archive.sh: 가짜 .xcarchive(실제 clang으로 만든 Mach-O라 strings·nm -u 둘 다 도는다)
# 사용: bash store/scripts/test-build-guards.sh [repo-root]
# P60은 수동 매트릭스(8+8건)만 기록했고 P67의 적대 검토가 이 하네스를 만들었다 — 가드를 고칠 때마다 돌린다.
set -euo pipefail
g() { echo "$2"; }   # 두 번째 인자 = 현재(패치 반영) 기대값. 첫 인자는 패치 전 동작 기록용으로 남긴다.
REPO="${1:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
[ -f "$REPO/app/ios/scripts/check_release_target.sh" ] || { echo "repo root not found: $REPO (pass it as arg 1)"; exit 2; }
CHECK="$REPO/app/ios/scripts/check_release_target.sh"
VERIFY="$REPO/store/scripts/verify-ios-archive.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
expect() { # expect <label> <want_rc> <cmd...>
  local label="$1" want="$2"; shift 2
  local out rc=0; out=$("$@" 2>&1) || rc=$?
  if [ "$rc" = "$want" ]; then pass=$((pass+1)); printf '  ok   %-64s rc=%s\n' "$label" "$rc"
  else fail=$((fail+1)); printf '  FAIL %-64s rc=%s want=%s\n       %s\n' "$label" "$rc" "$want" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"; fi
}

echo "== check_release_target.sh =="
mk_pods() { mkdir -p "$1/Pods.xcodeproj"; printf 'GCC_PREPROCESSOR_DEFINITIONS = (\n\t"$(inherited)",\n%s);\n' "$2" > "$1/Pods.xcodeproj/project.pbxproj"; }
mk_pods "$T/good"    '	"PERMISSION_CAMERA=1",'
mk_pods "$T/nomacro" ''
mkdir -p "$T/empty"                      # PODS_ROOT without Pods.xcodeproj
mkdir -p "$T/src with space"; cp -R "$T/good" "$T/src with space/Pods"
run_check() { env -i PATH="$PATH" "$@" /bin/sh "$CHECK"; }
b64() { printf '%s' "$1" | base64; }
expect "Debug without macro (patched: checked in every config)" "$(g 0 1)" run_check CONFIGURATION=Debug   PODS_ROOT="$T/nomacro"
expect "Profile without macro (patched: checked)"           "$(g 0 1)" run_check CONFIGURATION=Profile PODS_ROOT="$T/nomacro"
expect "Debug with macro passes"                            0 run_check CONFIGURATION=Debug   PODS_ROOT="$T/good"
expect "Release + macro present"                            0 run_check CONFIGURATION=Release PODS_ROOT="$T/good"
expect "Release + macro missing -> fail"                    1 run_check CONFIGURATION=Release PODS_ROOT="$T/nomacro"
expect "Release-prod flavor + macro missing -> fail"        1 run_check CONFIGURATION=Release-prod PODS_ROOT="$T/nomacro"
expect "FLUTTER_BUILD_MODE=release overrides Debug config"  1 run_check CONFIGURATION=Debug FLUTTER_BUILD_MODE=release PODS_ROOT="$T/nomacro"
expect "PODS_ROOT unset -> SRCROOT/Pods fallback (good)"     0 run_check CONFIGURATION=Release SRCROOT="$T/src with space"
expect "[gap] Release with no Pods dir at all -> warn only"  "$(g 0 1)" run_check CONFIGURATION=Release SRCROOT="$T/absent_src"
expect "[gap] PODS_ROOT dir without Pods.xcodeproj -> warn only" "$(g 0 1)" run_check CONFIGURATION=Release PODS_ROOT="$T/empty"
mkdir -p "$T/spm/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"; printf '.package(name: "permission_handler_apple", path: "..")\n' > "$T/spm/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
expect "plugin listed in SPM package -> fail (SPM pinned off in pubspec)" 1 run_check CONFIGURATION=Release SRCROOT="$T/spm"
expect "pbxproj unreadable -> fails closed"                 1 sh -c 'p="$1"; mkdir -p "$p/Pods.xcodeproj"; : > "$p/Pods.xcodeproj/project.pbxproj"; chmod 000 "$p/Pods.xcodeproj/project.pbxproj"; env -i PATH="$PATH" CONFIGURATION=Release PODS_ROOT="$p" /bin/sh "$2"; r=$?; chmod 644 "$p/Pods.xcodeproj/project.pbxproj"; exit $r' _ "$T/unreadable" "$CHECK"
expect "FLUTTER_TARGET=integration_test/... -> fail"        1 run_check CONFIGURATION=Release PODS_ROOT="$T/good" FLUTTER_TARGET=integration_test/store_screenshots_test.dart
expect "FLUTTER_TARGET absolute lib/main.dart ok"           0 run_check CONFIGURATION=Release PODS_ROOT="$T/good" FLUTTER_TARGET=/abs/path/lib/main.dart
expect "DART_DEFINES localhost -> fail"                     1 run_check CONFIGURATION=Release PODS_ROOT="$T/good" DART_DEFINES="$(b64 API_BASE_URL=http://localhost:8081)"
expect "DART_DEFINES last item (no trailing newline) seen"  1 run_check CONFIGURATION=Release PODS_ROOT="$T/good" DART_DEFINES="$(b64 FOO=bar),$(b64 DEV_SESSION=true)"
expect "DART_DEFINES http LAN API_BASE_URL -> fail"         1 run_check CONFIGURATION=Release PODS_ROOT="$T/good" DART_DEFINES="$(b64 API_BASE_URL=http://192.168.0.10:8080)"
expect "DART_DEFINES https API_BASE_URL ok"                 0 run_check CONFIGURATION=Release PODS_ROOT="$T/good" DART_DEFINES="$(b64 API_BASE_URL=https://example.com),$(b64 DEV_SESSION=false)"
# Known gaps (documented as findings; expected values reflect CURRENT behaviour so the harness is green until the script is patched):
expect "[gap] CONFIGURATION=Release but FLUTTER_BUILD_MODE=debug" "$(g 0 1)" run_check CONFIGURATION=Release FLUTTER_BUILD_MODE=debug PODS_ROOT="$T/good"
expect "[gap] both PODS_ROOT and SRCROOT unset -> raw 'unbound variable'"     1 run_check CONFIGURATION=Release

echo "== verify-ios-archive.sh =="
# Copy the script into a fake tree so ROOT/app/pubspec.yaml is under our control.
mkdir -p "$T/tree/store/scripts" "$T/tree/app"; cp "$VERIFY" "$T/tree/store/scripts/"; printf 'name: x\nversion: 1.0.0+8\n' > "$T/tree/app/pubspec.yaml"
mk_archive() { # mk_archive <dir> <ver> <build> <runner-marker-mode: good|nomacro|photosonly|none>
  local a="$1/Products/Applications/Runner.app"; mkdir -p "$a/Frameworks/App.framework"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $2" -c "Add :CFBundleVersion string $3" -c "Add :CFBundleIdentifier string com.han.rise" "$a/Info.plist" >/dev/null
  printf 'https://rize-api-773077624928.asia-northeast3.run.app/v1\n+821000000000\nlocalhost\n' > "$a/Frameworks/App.framework/App"
  case "$4" in
    good)       printf 'extern const void *AVMediaTypeVideo; const char *s="requestAccessForMediaType:completionHandler:", *t="permissionStatus:", *u="AudioVideoPermissionStrategy"; void *f(void){return (void*)AVMediaTypeVideo;}\n' | xcrun clang -x c -c - -o "$a/Runner" ;;  # real Mach-O: strings + nm -u both work
    nomacro)    printf 'AudioVideoPermissionStrategy\ncheckPermissionStatus:\n' > "$a/Runner" ;;   # what 1.0(6) really looks like
    photosonly) printf 'AudioVideoPermissionStrategy\npermissionStatus:\nPhotoPermissionStrategy\n' > "$a/Runner" ;;  # PERMISSION_PHOTOS=1, camera OFF
    none)       : ;;
  esac
}
mk_archive "$T/arch_good"   1.0.0 8 good
mk_archive "$T/arch_old"    1.0.0 6 nomacro
mk_archive "$T/arch_photos" 1.0.0 8 photosonly
mk_archive "$T/arch_norunner" 1.0.0 8 none
V="$T/tree/store/scripts/verify-ios-archive.sh"
expect "good archive passes"                                0 bash "$V" "$T/arch_good"
expect "old archive: version + camera both flagged, summary printed" 1 bash "$V" "$T/arch_old"
out=$(bash "$V" "$T/arch_old" 2>&1 || true); grep -q '2건 실패' <<<"$out" && echo "  ok   summary counts 2 failures (no early abort)" || { echo "  FAIL summary missing: $out"; fail=$((fail+1)); }
expect "[gap] PERMISSION_PHOTOS-only binary (false pass)"     "$(g 0 1)" bash "$V" "$T/arch_photos"
before=$(ls "${TMPDIR:-/tmp}" | grep -c '^tmp\.' || true)
expect "[gap] Runner binary missing -> aborts before summary"   1 bash "$V" "$T/arch_norunner"
after=$(ls "${TMPDIR:-/tmp}" | grep -c '^tmp\.' || true)
echo "  info mktemp files in TMPDIR before=$before after=$after (delta>0 = RUNNER_STR leaked)"; [ "$after" -gt "$before" ] && { echo "  FAIL script leaks mktemp file"; fail=$((fail+1)); } || true
echo; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
