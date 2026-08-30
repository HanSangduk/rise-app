#!/usr/bin/env bash
# 사용자 경로 uptime 감시 신설 (P35 — 팀② C1)
#
# 기존 감시는 Cloud Run 원본(run.app/health)만 직접 봐서, Hosting의 /api 리라이트가 유실돼도
# (P34 사고 — 15시간+ 미감지) 초록불이었다. 이 스크립트는 사용자가 실제 지나는 경로
# (rize-218c1.web.app/api/health)를 5분 주기로 감시하고, 실패 시 기존 알림 채널(이메일)로
# 알림을 보내는 정책을 만든다. 기존 감시는 그대로 둔다 — 두 감시의 차이로 "백엔드가 죽었나,
# 경로가 끊겼나"를 알림만 보고 구분할 수 있다.
#
# 실행: ./setup-monitoring.sh   (gcloud 로그인 필요 — rizejoy91@gmail.com)
set -euo pipefail

PROJECT=rize-218c1
HOST=rize-218c1.web.app
CHANNEL=projects/rize-218c1/notificationChannels/5517977555087325416
TOKEN=$(gcloud auth print-access-token)

api() { # method path [json]
  curl -s -m 20 -X "$1" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "https://monitoring.googleapis.com/v3/projects/$PROJECT/$2" ${3:+-d "$3"}
}

# 이미 있으면 다시 만들지 않는다(멱등).
# host **와 path**를 함께 본다. host만 보면 같은 도메인의 다른 체크(예: 루트 / 감시)를
# 자기 것으로 오인해 /api/health를 아무도 감시하지 않는데 알림만 초록불이 된다 —
# 8/27 사고(루트는 200, /api만 404)에서 정확히 무력한 구성이다.
# 조회 응답의 error를 빈 목록으로 오독하면(키가 없으니 []) 실행할 때마다 체크가 늘어난다.
EXISTING=$(api GET uptimeCheckConfigs | HOST="$HOST" python3 -c "
import sys, json, os
d = json.load(sys.stdin)
if 'error' in d:
    raise SystemExit('uptime check 조회 실패: ' + json.dumps(d['error'])[:200])
for c in d.get('uptimeCheckConfigs', []):
    if (c.get('monitoredResource', {}).get('labels', {}).get('host') == os.environ['HOST']
            and c.get('httpCheck', {}).get('path') == '/api/health'):
        print(c['name'].split('/')[-1]); break")

if [ -n "$EXISTING" ]; then
  CHECK_ID=$EXISTING
  echo "✓ uptime check 이미 존재: $CHECK_ID"
else
  CHECK_ID=$(api POST uptimeCheckConfigs '{
    "displayName": "rize hosting /api/health (사용자 경로)",
    "monitoredResource": {"type": "uptime_url", "labels": {"project_id": "'"$PROJECT"'", "host": "'"$HOST"'"}},
    "httpCheck": {"path": "/api/health", "port": 443, "useSsl": true, "validateSsl": true,
                  "requestMethod": "GET", "acceptedResponseStatusCodes": [{"statusClass": "STATUS_CLASS_2XX"}]},
    "period": "300s", "timeout": "10s"
  }' | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'error' in d: raise SystemExit('uptime check 생성 실패: ' + json.dumps(d['error'])[:300])
print(d['name'].split('/')[-1])")
  echo "✓ uptime check 생성: $CHECK_ID"
fi

# 런북 — 알림 메일 본문에 그대로 실린다. 폰으로 알림을 받은 사람이 **맥 없이** 판단하고
# 복구할 수 있어야 하므로, 진단 분기와 탭 가능한 콘솔 링크를 여기에 담는다(P35).
export RUNBOOK='**사용자 진입 경로(Hosting /api → Cloud Run) 장애입니다.**

**1) 어디가 끊겼는지 판단**
- "rize-api 다운 감지" 알림도 함께 왔다 → 백엔드가 죽은 것. Cloud Run은 스스로 재시작하므로 5~10분 기다렸다 회복되는지 볼 것. 안 되면 아래 2-B.
- 이 알림만 왔다 → **백엔드는 살아있고 Hosting 리라이트가 끊긴 것**(2026-08-27 사고와 같은 유형). 아래 2-A.

**2-A) Hosting 롤백 (폰에서 가능)**
[Firebase Hosting 콘솔](https://console.firebase.google.com/project/rize-218c1/hosting/sites) → 릴리스 기록에서 직전 정상 버전의 ⋮ → 롤백.

**2-B) Cloud Run 롤백 (폰에서 가능)**
[Cloud Run 리비전](https://console.cloud.google.com/run/detail/asia-northeast3/rize-api/revisions?project=rize-218c1) → 트래픽 관리 → 직전 정상 리비전에 100%.

**3) 맥이 있으면**
`cd ptdesk && ./deploy-hosting.sh` — 재배포 + 자동 검증까지 한 번에.

**4) 복구 확인**
https://rize-218c1.web.app/api/health 가 {"status":"ok"} 를 주면 정상. HTML이 보이면 아직 리라이트가 끊긴 상태.'

# 백엔드 다운 알림의 런북 — 정작 서버가 죽었을 때 오는 알림인데 종전엔 "확인하세요"뿐이라
# 폰으로 받아도 할 수 있는 게 없었다. 자동 복구되는 경우와 사람이 손대야 하는 경우를 가른다.
export RUNBOOK_BACKEND='**백엔드(rize-api)가 응답하지 않습니다.**

**1) 먼저 5~10분 기다려 볼 것**
컨테이너가 죽은 것이라면 Cloud Run이 **자동으로 새로 띄웁니다.** 저절로 복구 알림이 오면 끝 — 원인만 나중에 로그로 확인하면 됩니다.

**2) 계속 죽어 있으면 = 최근 배포가 원인일 가능성이 높음**
[Cloud Run 리비전](https://console.cloud.google.com/run/detail/asia-northeast3/rize-api/revisions?project=rize-218c1) → 트래픽 관리 → **직전 정상 리비전에 100%** (폰에서 가능).

**3) 원인 보기**
[Cloud Run 로그](https://console.cloud.google.com/run/detail/asia-northeast3/rize-api/logs?project=rize-218c1) — `panic` 또는 `설정 오류`를 검색. 설정 오류면 환경변수 문제라 롤백으로 풀립니다.

**4) 복구 확인**
https://rize-api-773077624928.asia-northeast3.run.app/health 가 {"status":"ok"}면 정상. `{"status":"degraded"}`면 서버는 살았고 **Firestore 연결**이 문제입니다.'

# 알림 정책 — 기존 "rize-api 다운 감지"와 같은 구조(check_passed false 5분)로 복제.
POLICY_NAME=$(api GET alertPolicies | python3 -c "
import sys, json
d = json.load(sys.stdin)
for p in d.get('alertPolicies', []):
    if '사용자 경로' in p.get('displayName',''):
        print(p['name']); break")
# patch_runbook <policy_full_name> <런북을_담은_환경변수_이름> — 알림의 documentation만 갱신.
#
# 본문은 파일로 만들어 `-d @file`로 넘긴다. `-d "$(python3 -c "...{'a':1,'b':2}...")"`는
# zsh가 `{a,b}`를 **브레이스 확장**으로 먼저 쪼개 python 호출이 두 조각으로 갈라진다
# (첫 실행에서 SyntaxError 2회 + curl blank argument로 터진 자리다).
patch_runbook() {
  local body code; body=$(mktemp)
  RUNBOOK_VAR="$2" python3 -c 'import json, os, sys
content = os.environ[os.environ["RUNBOOK_VAR"]]
json.dump({"documentation": {"content": content, "mimeType": "text/markdown"}}, open(sys.argv[1], "w"))' "$body"
  # 상태코드를 **반드시 본다**. -s로 에러를 숨긴 채 성공 메시지를 찍으면, 이 스크립트의 존재
  # 이유(폰으로 받은 알림에 복구 절차가 실려 있는 것)가 장애 당일에야 거짓이었음이 드러난다.
  code=$(curl -s -m 20 -o /dev/null -w '%{http_code}' -X PATCH \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "https://monitoring.googleapis.com/v3/$1?updateMask=documentation" -d @"$body" || echo 000)
  rm -f "$body"
  [ "$code" = "200" ] || { echo "   🚨 런북 갱신 실패(HTTP $code): $1"; return 1; }
  # 되읽어 **보낸 내용과 같은지** 대조한다. 200 응답이 곧 저장은 아니고, "길이가 충분한가"
  # 같은 느슨한 검사는 옛 런북이 남아 있어도 통과한다(실제로 128자 구버전이 통과했다).
  local same
  same=$(curl -s -m 15 -H "Authorization: Bearer $TOKEN" "https://monitoring.googleapis.com/v3/$1" \
    | RUNBOOK_VAR="$2" python3 -c "
import sys, json, os
d = json.load(sys.stdin)
got = (d.get('documentation') or {}).get('content', '')
print('yes' if got == os.environ[os.environ['RUNBOOK_VAR']] else 'no')" 2>/dev/null || echo no)
  [ "$same" = "yes" ] || { echo "   🚨 런북이 반영되지 않았다(되읽기 불일치): $1"; return 1; }
  return 0
}

# 백엔드 다운 알림(기존 정책)의 런북도 함께 채운다 — 정작 서버가 죽었을 때 오는 알림이
# "확인하세요" 한 줄이면 폰으로 받아도 할 수 있는 게 없다.
BACKEND_POLICY=$(api GET alertPolicies | python3 -c "
import sys, json
for p in json.load(sys.stdin).get('alertPolicies', []):
    if 'rize-api 다운' in p.get('displayName',''):
        print(p['name']); break")
if [ -n "$BACKEND_POLICY" ]; then
  if patch_runbook "$BACKEND_POLICY" RUNBOOK_BACKEND; then
    echo "✓ 백엔드 다운 알림 런북 갱신(자동복구 대기 → 롤백 절차)"
  fi
fi

if [ -n "$POLICY_NAME" ]; then
  # 이미 있으면 런북만 최신으로 갱신한다(멱등) — 폰 복구 절차가 알림에 실려야 의미가 있다.
  if patch_runbook "$POLICY_NAME" RUNBOOK; then
    echo "✓ 알림 정책 이미 존재 — 런북(폰 복구 절차) 갱신"
  fi
else
  # 본문은 python으로 조립한다 — 런북이 여러 줄·마크다운이라 셸 따옴표로 끼워 넣으면 깨진다.
  BODY=$(CHECK_ID="$CHECK_ID" CHANNEL="$CHANNEL" python3 -c '
import json, os
print(json.dumps({
  "displayName": "rize 사용자 경로 다운 감지 (hosting /api)",
  "combiner": "OR",
  "enabled": True,
  "notificationChannels": [os.environ["CHANNEL"]],
  "conditions": [{
    "displayName": "hosting /api/health 체크 실패 (5분 이상)",
    "conditionThreshold": {
      "filter": ("resource.type = \"uptime_url\" AND metric.type = "
                 "\"monitoring.googleapis.com/uptime_check/check_passed\" AND "
                 "metric.labels.check_id = \"%s\"" % os.environ["CHECK_ID"]),
      "comparison": "COMPARISON_GT",
      "thresholdValue": 1,
      "duration": "300s",
      "trigger": {"count": 1},
      "aggregations": [{"alignmentPeriod": "300s", "perSeriesAligner": "ALIGN_NEXT_OLDER",
                        "crossSeriesReducer": "REDUCE_COUNT_FALSE",
                        "groupByFields": ["resource.label.host"]}],
    },
  }],
  "documentation": {"content": os.environ["RUNBOOK"], "mimeType": "text/markdown"},
}))')
  api POST alertPolicies "$BODY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'error' in d: raise SystemExit('알림 정책 생성 실패: ' + json.dumps(d['error'])[:300])
print('✓ 알림 정책 생성:', d['name'])"
fi

# 알림 채널이 살아 있는지 확인한 뒤에만 "알림이 온다"고 말한다. 채널이 삭제·미인증이면
# 위 설정이 다 맞아도 메일은 오지 않는다. 감지 지연도 실제 값(주기 300s + 조건 300s)으로 적는다.
ch_state=$(curl -s -m 15 -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/$CHANNEL" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('missing' if 'error' in d else ('enabled' if d.get('enabled') else 'disabled'))" 2>/dev/null || echo unknown)
case "$ch_state" in
  enabled) echo "✅ 완료 — 알림 채널 정상. 장애 발생 시 약 10~15분 내 이메일이 온다(체크 주기 5분 + 조건 5분)." ;;
  *) echo "⚠ 설정은 됐으나 알림 채널 상태가 '$ch_state'다 — 메일이 오지 않을 수 있다."
     echo "  확인: https://console.cloud.google.com/monitoring/alerting/notifications?project=$PROJECT" ;;
esac
