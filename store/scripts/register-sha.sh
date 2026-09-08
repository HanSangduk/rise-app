#!/usr/bin/env bash
# Firebase에 Android 서명 인증서(SHA-1/SHA-256) 등록(P46).
#
# **왜 필요한가**: Firebase 전화 인증은 Android에서 Play Integrity로 앱을 검증하는데,
# 그 판정은 **APK를 서명한 인증서의 SHA 지문이 Firebase에 등록돼 있느냐**로 갈린다.
# 등록이 없으면 reCAPTCHA 웹뷰로 떨어지거나(UX 저하) 인증이 실패한다.
# 지금 등록된 건 **디버그 키**뿐이라 릴리스 빌드는 무방비다.
#
# 등록해야 하는 인증서는 **둘**이다:
#   ① 업로드 키(이 스크립트가 자동 등록) — android/upload-keystore.jks
#   ② **Play 앱 서명 키**(수동) — Play Console > 테스트 및 출시 > 앱 무결성 >
#      앱 서명 키 인증서의 SHA-1/SHA-256. 사용자가 실제로 설치하는 APK는 Google이
#      다시 서명하므로 **이쪽이 없으면 실사용자 전화 인증이 깨진다.**
#      (AAB를 처음 업로드한 뒤에야 확인 가능 — 그래서 자동화할 수 없다.)
#
# 사용: bash store/scripts/register-sha.sh            # 업로드 키 등록
#       bash store/scripts/register-sha.sh <SHA1> <SHA256>   # 값 직접 지정(Play 서명 키)
set -euo pipefail
cd "$(dirname "$0")/../.."

PROJECT=rize-218c1
APP_ID=1:773077624928:android:66408d0259a5f46ab0fb05
API="https://firebase.googleapis.com/v1beta1/projects/$PROJECT/androidApps/$APP_ID/sha"
TOKEN=$(gcloud auth print-access-token)

norm() { echo "$1" | tr -d ': ' | tr 'A-Z' 'a-z'; }

if [[ $# -eq 2 ]]; then
  SHA1=$(norm "$1"); SHA256=$(norm "$2")
else
  KS=app/android/upload-keystore.jks
  if [[ ! -f "$KS" ]]; then
    echo "업로드 키가 없습니다: $KS"
    echo "  먼저: bash store/scripts/make-keystore.sh"
    echo "  (Play 앱 서명 키를 넣으려면: $0 <SHA1> <SHA256>)"
    exit 1
  fi
  read -r -s -p "keystore 비밀번호: " PW; echo
  OUT=$(keytool -list -v -keystore "$KS" -alias upload -storepass "$PW" 2>/dev/null)
  SHA1=$(norm "$(grep -m1 'SHA1:' <<<"$OUT" | sed 's/.*SHA1://')")
  SHA256=$(norm "$(grep -m1 'SHA256:' <<<"$OUT" | sed 's/.*SHA256://')")
fi

existing=$(curl -s "$API" -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT")
for pair in "SHA_1:$SHA1" "SHA_256:$SHA256"; do
  type="${pair%%:*}"; hash="${pair#*:}"
  if grep -qi "$hash" <<<"$existing"; then
    echo "이미 등록됨($type): $hash"
    continue
  fi
  resp=$(curl -s -X POST "$API" -H "Authorization: Bearer $TOKEN" \
    -H "x-goog-user-project: $PROJECT" -H "Content-Type: application/json" \
    -d "{\"shaHash\":\"$hash\",\"certType\":\"$type\"}")
  if grep -q '"error"' <<<"$resp"; then
    echo "등록 실패($type): $(python3 -c 'import json,sys;print(json.load(sys.stdin)["error"]["message"][:200])' <<<"$resp")"
    exit 1
  fi
  echo "등록 완료($type): $hash"
done

echo
echo "⚠ Play 앱 서명 키도 등록해야 실사용자 전화 인증이 정상 동작합니다."
echo "  Play Console > 앱 무결성 > 앱 서명 키 인증서에서 SHA-1/SHA-256을 복사해:"
echo "  bash store/scripts/register-sha.sh <SHA1> <SHA256>"
