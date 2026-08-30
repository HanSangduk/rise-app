#!/usr/bin/env bash
# Android 릴리스 keystore 생성(P46) — 최초 1회만. 생성물은 절대 커밋 금지.
#
# ⚠ 이 keystore를 잃어버리면 같은 앱으로 업데이트를 영영 못 올린다(Play 앱 서명을
#   쓰더라도 업로드 키 재설정 절차가 필요). 비밀번호와 함께 1Password 등에 백업할 것.
#
# 사용: bash store/scripts/make-keystore.sh
set -euo pipefail
cd "$(dirname "$0")/../../app/android"

KS=upload-keystore.jks
if [[ -f "$KS" ]]; then
  echo "이미 존재: android/$KS — 덮어쓰지 않습니다."
  exit 1
fi

read -r -s -p "keystore 비밀번호(새로 정하세요): " PW; echo
keytool -genkey -v -keystore "$KS" -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload -storepass "$PW" -keypass "$PW" \
  -dname "CN=Rize, OU=stra, O=stra.ai, L=Seoul, C=KR"

cat > key.properties <<EOF
storePassword=$PW
keyPassword=$PW
keyAlias=upload
storeFile=upload-keystore.jks
EOF
chmod 600 key.properties

echo
echo "완료: android/$KS + android/key.properties (둘 다 .gitignore 대상)"
echo "다음: bash store/scripts/build-release.sh android"
