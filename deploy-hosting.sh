#!/usr/bin/env bash
# 운영 Hosting 배포 스크립트 (P34 신설 → P35 강화 → P35 적대 리뷰 반영)
#
# 2026-08-27 사고: hosting config가 통째로 빈 채(rewrites: null) 배포돼 /api/**가 Cloud Run에
# 못 닿고 Hosting 404로 떨어졌다. 15시간 넘게 아무도 몰랐다.
#
# 이 스크립트의 원칙 — **모르면서 안다고 말하지 않는다.**
#   · 검증은 "정상 / 고장 / 확인 불가" 3상태다. 자동 롤백은 **고장이 확실할 때만** 한다
#     (조회 실패·권한 오류를 고장으로 읽으면 멀쩡한 배포를 되돌린다).
#   · 롤백 대상은 "직전"이 아니라 **"직전 정상"**이다(직전 자체가 깨진 배포일 수 있다 —
#     실제로 8/27 릴리스가 그 상태로 이력에 남아 있다).
#   · 롤백 후에도 **스모크를 다시 돌려 확인**한 뒤에만 성공이라고 말한다.
#
# 사용법:  ./deploy-hosting.sh            빌드 + 배포 + 검증
#          ./deploy-hosting.sh --no-build  admin/dist 그대로 배포
set -euo pipefail

cd "$(dirname "$0")"

PROJECT=rize-218c1
SITE_URL=https://rize-218c1.web.app
SMOKE_BODY=$(mktemp)
WORK_JSON=$(mktemp)
trap 'rm -f "$SMOKE_BODY" "$WORK_JSON"' EXIT

# ── 0) firebase CLI 로그인 확인 ───────────────────────────────────────────────
# 파이프로 grep에 넘기지 않는다: `set -o pipefail`에서 `grep -q`가 첫 매칭에 종료하면
# 생산자가 SIGPIPE(141)로 죽어 파이프라인이 "실패"가 된다 — 즉 **로그아웃을 감지하고도
# if가 거짓이 되어 그대로 배포로 진행**할 수 있다. 판정은 변수에 받아서 한다.
login_out=$(firebase login:list 2>/dev/null || true)
case "$login_out" in
  *"No authorized accounts"*)
    echo "🚫 firebase CLI가 로그아웃 상태다. 먼저 실행: firebase login  (rizejoy91@gmail.com 계정)"
    exit 1 ;;
esac

# ── 1) 배포 전 검증: 리라이트 존재 + 순서 ────────────────────────────────────
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

# ── 2) 어드민 빌드 ───────────────────────────────────────────────────────────
if [ "${1:-}" != "--no-build" ]; then
  (cd admin && npm run build)
elif [ ! -f admin/dist/index.html ]; then
  echo "🚫 --no-build인데 admin/dist/index.html이 없다 — 빈 dist를 올릴 뻔했다. 배포 중단"
  exit 1
fi

# ── 3) 배포 ──────────────────────────────────────────────────────────────────
firebase deploy --only hosting --project "$PROJECT"

# ── 검증 도구 ────────────────────────────────────────────────────────────────
TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)

# fetch_releases — 최근 릴리스 목록을 $WORK_JSON에 받는다. 0=성공, 1=조회 불가.
fetch_releases() {
  [ -n "$TOKEN" ] || return 1
  curl -s -m 20 -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
    "https://firebasehosting.googleapis.com/v1beta1/sites/$PROJECT/releases?pageSize=10" \
    -o "$WORK_JSON" || return 1
  # 응답이 JSON이고 releases 키가 있어야 "조회됨"이다 — 403 본문도 JSON이라 키까지 봐야 한다.
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if isinstance(d.get("releases"), list) else 1)' "$WORK_JSON" 2>/dev/null || return 1
}

# 릴리스 하나가 "정상"인지 판정하는 공통 파이썬(배포 전 검증과 같은 기준: 존재 + 순서).
HEALTHY_PY='
def healthy(v):
    if v.get("status") not in (None, "FINALIZED"):
        return False           # DELETED 버전으로는 릴리스를 만들 수 없다(400).
    rw = v.get("config", {}).get("rewrites") or []
    api = next((i for i, r in enumerate(rw)
                if r.get("glob") == "/api/**" and r.get("run", {}).get("serviceId") == "rize-api"), None)
    spa = next((i for i, r in enumerate(rw)
                if r.get("glob") == "**" and r.get("path") == "/index.html"), None)
    return api is not None and spa is not None and api < spa
'

# smoke — 한 경로를 캐시 우회로 친다. "코드 컨텐트타입"을 출력.
smoke() {
  curl -s -m 15 -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
    -o "$SMOKE_BODY" -w '%{http_code} %{content_type}' \
    "$SITE_URL$1?cb=$(date +%s)$RANDOM" || echo "000 -"
}

# verify_path — path·기대코드·기대본문조각·라벨. 0=통과, 1=실패(폴링 후).
verify_path() {
  local path="$1" want="$2" frag="$3" label="$4" i out code ctype
  for i in 1 2 3 4 5 6; do
    out=$(smoke "$path")
    code=${out%% *}; ctype=${out#* }
    if [ "$code" = "$want" ] && [[ "$ctype" == *json* ]] && grep -qF -e "$frag" "$SMOKE_BODY"; then
      echo "✓ $label: $path -> $code (JSON, 본문 확인)"
      return 0
    fi
    if [ "$i" -lt 6 ]; then
      echo "  … $label 대기($i/6): $path -> $code ($ctype)"
      sleep 5
    fi
  done
  echo "🚨 $label 실패: $path -> $code (기대: $want + JSON + '$frag')"
  echo "   본문 앞부분: $(head -c 200 "$SMOKE_BODY")"
  return 1
}

# run_smokes — 스모크 2종. 공개 경로는 "200 HTML"(SPA 폴백이 /api를 삼킴)을 잡고,
# 무인증 401은 캐시 불가 경로라 CDN 잔존 응답에 안 속으며 인증 미들웨어 생존도 본다.
run_smokes() {
  verify_path /api/v1/public/business 200 '"biz_name"' "공개 API" || return 1
  verify_path /api/v1/me 401 '"error"' "인증 경계" || return 1
}

# ── 자동 롤백 ────────────────────────────────────────────────────────────────
# **고장이 확실할 때만** 부른다. 되돌리는 건 방금 올린 것의 취소라 잃는 게 없고,
# 사람을 기다리면 그 시간만큼 사용자가 깨진 사이트를 본다(8/27엔 15시간이었다).
manual_rollback_notice() {
  echo "   콘솔에서 수동 롤백할 것: https://console.firebase.google.com/project/$PROJECT/hosting"
}

auto_rollback() {
  echo "↩ 자동 롤백 시도: 가장 최근의 '정상' 릴리스로 되돌린다"
  if ! fetch_releases; then
    echo "   ⚠ 릴리스 목록 조회 실패 — 자동 롤백 불가(대상을 모른다)."
    manual_rollback_notice
    return 1
  fi
  local prev
  prev=$(python3 -c "
import json, sys
$HEALTHY_PY
rs = json.load(open(sys.argv[1])).get('releases', [])
for r in rs[1:]:
    if healthy(r['version']):
        print(r['version']['name']); break
" "$WORK_JSON") || prev=""
  if [ -z "$prev" ]; then
    echo "   ⚠ 되돌릴 만한 '정상' 릴리스가 이력에 없다 — 자동 롤백 불가."
    manual_rollback_notice
    return 1
  fi

  local resp code
  resp=$(curl -s -m 25 -w '\n%{http_code}' -X POST \
    -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
    "https://firebasehosting.googleapis.com/v1beta1/sites/$PROJECT/releases?versionName=$prev" \
    || echo $'\n000')
  code=${resp##*$'\n'}
  if [ "$code" != "200" ]; then
    echo "   🚨 자동 롤백 요청 실패(HTTP $code)."
    manual_rollback_notice
    return 1
  fi
  # 응답이 실제로 그 버전을 가리키는지 대조한다 — "JSON이 왔다"는 성공이 아니다.
  if ! printf '%s' "${resp%$'\n'*}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if d.get('version', {}).get('name') == sys.argv[1] else 1)" "$prev"; then
    echo "   🚨 롤백 응답이 기대한 버전($prev)을 가리키지 않는다."
    manual_rollback_notice
    return 1
  fi

  echo "   릴리스 완료 — 실제로 복구됐는지 스모크로 확인한다"
  if run_smokes; then
    echo "   ✅ 롤백 확인 완료 — $prev 이 다시 서비스 중이고 API 경로가 정상이다."
    echo "      원인을 고친 뒤 다시 배포할 것."
    return 0
  fi
  echo "   🚨 롤백은 됐으나 스모크가 여전히 실패한다 — 사람이 봐야 한다."
  manual_rollback_notice
  return 1
}

# ── 4) 배포 후 검증 ① — 라이브 릴리스의 rewrites(로컬 파일과 무관한 진실) ────
# 3상태로 가른다: 0=정상, 1=고장 확실, 2=확인 불가(권한·네트워크). 2에서 롤백하면
# IAM 문제 하나가 멀쩡한 배포를 되돌린다.
release_state=2
if fetch_releases; then
  if python3 -c "
import json, sys
$HEALTHY_PY
rs = json.load(open(sys.argv[1])).get('releases', [])
if not rs:
    sys.exit(2)
sys.exit(0 if healthy(rs[0]['version']) else 1)
" "$WORK_JSON"; then
    release_state=0
  else
    release_state=$?
  fi
fi
case "$release_state" in
  0) echo "✓ 라이브 릴리스 config: /api 리라이트 + SPA 폴백 + 순서 확인" ;;
  1) echo "🚨 방금 올라간 라이브 릴리스에 /api 리라이트/순서가 잘못됐다(8/27 사고 재현)"
     auto_rollback || true
     exit 1 ;;
  *) echo "⚠ 라이브 릴리스 config를 확인하지 못했다(권한·네트워크) — 롤백하지 않는다."
     echo "  아래 스모크가 실제 동작을 직접 확인하므로 그것으로 판정한다." ;;
esac

# ── 5) 배포 후 검증 ② — 캐시 우회 스모크(가장 신뢰도 높은 방어선) ───────────
if run_smokes; then
  echo "✅ 배포 + 라이브 검증 완료 (릴리스 config · 공개 API · 인증 경계)"
else
  echo "배포된 사이트가 실제로 응답하지 않는다 — 자동 롤백으로 넘어간다"
  auto_rollback || true
  exit 1
fi
