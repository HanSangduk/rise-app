#!/usr/bin/env bash
# 운영 Hosting 배포 스크립트 (P34 신설 → P35 강화) — 2026-08-27 리라이트 유실 사고 재발 방지.
#
# 그날 라이브 릴리스는 hosting config가 통째로 비어(rewrites: null) /api/**가 Cloud Run에
# 못 닿고 Hosting 404로 떨어졌다. 이 스크립트는 그 계열 사고의 구멍들을 막는다:
#   (1) 어디서 실행하든 항상 ptdesk 루트의 firebase.json으로 배포
#   (2) 배포 전: /api 리라이트 존재 + SPA 폴백 존재 + **순서**(/api가 ** 앞) 검증 — 부분 유실은
#       404가 아니라 "200 + HTML"(SPA 폴백이 /api를 삼킴)이 되므로 순서까지 봐야 한다(P35 C-1)
#   (3) 배포 후: 캐시를 우회해(CDN에 남은 이전 200에 속지 않게 — P35 H-4) 상태코드 + JSON
#       여부 + 본문 필드까지 3중 확인, 재시도 폴링으로 전파 지연 오탐 방지
#   (4) 배포 후: Hosting REST API로 **실제 라이브 릴리스의 rewrites**를 직접 조회 — 로컬 파일
#       검증은 대리 지표일 뿐, 릴리스에 뭐가 들었는지는 이것만이 직접 답한다(P35 M-6)
#
# 사용법:  ./deploy-hosting.sh          # 빌드 + 배포 + 검증
#          ./deploy-hosting.sh --no-build  # admin/dist 그대로 배포(빌드 생략)
set -euo pipefail
cd "$(dirname "$0")"

PROJECT=rize-218c1
SITE_URL=https://rize-218c1.web.app

# 0) firebase CLI 로그인 확인 — 로그아웃 상태면 배포 명령이 "Failed to get project"로 죽는다.
if firebase login:list 2>/dev/null | grep -q "No authorized accounts"; then
  echo "🚫 firebase CLI가 로그아웃 상태다. 먼저 실행: firebase login  (rizejoy91@gmail.com 계정)"
  exit 1
fi

# 1) 배포 전 검증: 리라이트 존재 + 순서
python3 - <<'EOF'
import json, sys
cfg = json.load(open('firebase.json'))
rw = cfg.get('hosting', {}).get('rewrites', [])
api_idx = next((i for i, r in enumerate(rw)
                if r.get('source') == '/api/**' and r.get('run', {}).get('serviceId') == 'rize-api'), None)
spa_idx = next((i for i, r in enumerate(rw)
                if r.get('source') == '**' and r.get('destination') == '/index.html'), None)
if api_idx is None:
    sys.exit('🚫 firebase.json에 /api/** → rize-api 리라이트가 없다 — 배포 중단')
if spa_idx is None:
    sys.exit('🚫 firebase.json에 SPA 폴백(** → /index.html)이 없다 — 배포 중단')
if api_idx > spa_idx:
    sys.exit('🚫 /api/** 리라이트가 SPA 폴백(**) 뒤에 있다 — /api가 index.html에 삼켜진다. 배포 중단')
print('✓ 배포 전 검증: /api 리라이트 + SPA 폴백 + 순서 확인')
EOF

# 2) 어드민 빌드
if [ "${1:-}" != "--no-build" ]; then
  (cd admin && npm run build)
elif [ ! -f admin/dist/index.html ]; then
  echo "🚫 --no-build인데 admin/dist/index.html이 없다 — 빈 dist를 올릴 뻔했다. 배포 중단"
  exit 1
fi

# 3) 배포 — 프로젝트를 명시해 .firebaserc 오독/alias 실수를 차단
firebase deploy --only hosting --project "$PROJECT"

# 4) 배포 후 검증 ① — 실제 라이브 릴리스의 rewrites를 REST로 직접 조회(로컬 파일과 무관한 진실)
TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)
if [ -n "$TOKEN" ]; then
  # 응답을 파일로 받는다 — `curl | python3 - <<EOF`는 heredoc이 stdin을 덮어써서 파이프가
  # 통째로 사라진다(첫 실행에서 이 조합이 JSONDecodeError로 터졌다). 파싱은 -c로 넘긴다.
  RELEASE_JSON=$(mktemp)
  curl -s -m 15 -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
    "https://firebasehosting.googleapis.com/v1beta1/sites/$PROJECT/releases?pageSize=1" \
    -o "$RELEASE_JSON"
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
try:
    rw = d["releases"][0]["version"].get("config", {}).get("rewrites") or []
except (KeyError, IndexError):
    sys.exit("🚨 라이브 릴리스 조회 실패 — 응답: " + json.dumps(d)[:200])
ok = any(r.get("glob") == "/api/**" and r.get("run", {}).get("serviceId") == "rize-api" for r in rw)
if not ok:
    sys.exit("🚨 방금 올라간 라이브 릴리스에 /api/** 리라이트가 없다(8/27 사고 재현) — 즉시 롤백할 것")
print("✓ 라이브 릴리스 config: /api 리라이트 반영 확인")
' "$RELEASE_JSON"
  rm -f "$RELEASE_JSON"
else
  echo "⚠ gcloud 토큰 없음 — 릴리스 config 직접 검증은 건너뜀(아래 스모크가 2차 방어선)"
fi

# 5) 배포 후 검증 ② — 캐시 우회 스모크 2종(공개 JSON + 무인증 401 JSON), 폴링으로 전파 대기
smoke() { # path expected_status expected_fragment
  curl -s -m 15 -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
    -o /tmp/rize_smoke_body -w '%{http_code} %{content_type}' "$SITE_URL$1?cb=$(date +%s)$RANDOM"
}
verify() { # path expected_status expected_fragment label
  local out code ctype
  for i in 1 2 3 4 5 6; do
    out=$(smoke "$1") || out="000 -"
    code=${out%% *}; ctype=${out#* }
    if [ "$code" = "$2" ] && [[ "$ctype" == *json* ]] && grep -q "$3" /tmp/rize_smoke_body; then
      echo "✓ $4: $1 -> $code (JSON, 본문 확인)"
      return 0
    fi
    echo "  … $4 대기($i/6): $1 -> $code ($ctype)"
    sleep 5
  done
  echo "🚨 배포 후 검증 실패: $1 -> $code (기대: $2 + JSON + '$3')"
  echo "   본문 앞부분: $(head -c 200 /tmp/rize_smoke_body)"
  echo "   Firebase 콘솔 > Hosting에서 직전 릴리스로 즉시 롤백:"
  echo "   https://console.firebase.google.com/project/$PROJECT/hosting"
  exit 1
}
# 공개 경로: 200 + JSON + 실제 필드 — SPA 폴백이 삼킨 "200 HTML"은 여기서 걸린다.
verify /api/v1/public/business 200 '"biz_name"' "공개 API"
# 무인증 /me: 401 + JSON — 캐시 불가 경로라 CDN 잔존 200에 속지 않고, 인증 미들웨어 생존도 확인.
verify /api/v1/me 401 '"error"' "인증 경계"

echo "✅ 배포 + 라이브 검증 완료 (릴리스 config · 공개 API · 인증 경계)"
