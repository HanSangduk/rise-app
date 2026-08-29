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
EXISTING=$(api GET uptimeCheckConfigs | python3 -c "
import sys, json
d = json.load(sys.stdin)
for c in d.get('uptimeCheckConfigs', []):
    if c.get('monitoredResource', {}).get('labels', {}).get('host') == '$HOST':
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

# 알림 정책 — 기존 "rize-api 다운 감지"와 같은 구조(check_passed false 5분)로 복제.
HAS_POLICY=$(api GET alertPolicies | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(any('사용자 경로' in p.get('displayName','') for p in d.get('alertPolicies', [])))")
if [ "$HAS_POLICY" = "True" ]; then
  echo "✓ 알림 정책 이미 존재"
else
  api POST alertPolicies '{
    "displayName": "rize 사용자 경로 다운 감지 (hosting /api)",
    "combiner": "OR",
    "enabled": true,
    "notificationChannels": ["'"$CHANNEL"'"],
    "conditions": [{
      "displayName": "hosting /api/health 체크 실패 (5분 이상)",
      "conditionThreshold": {
        "filter": "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id = \"'"$CHECK_ID"'\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 1,
        "duration": "300s",
        "trigger": {"count": 1},
        "aggregations": [{"alignmentPeriod": "300s", "perSeriesAligner": "ALIGN_NEXT_OLDER",
                          "crossSeriesReducer": "REDUCE_COUNT_FALSE", "groupByFields": ["resource.label.host"]}]
      }
    }],
    "documentation": {"content": "사용자 진입 경로(Hosting /api → Cloud Run) 장애. run.app 직접 감시(rize-api 다운 감지)가 조용하면 백엔드는 살아있고 Hosting 리라이트가 끊긴 것 — ptdesk에서 ./deploy-hosting.sh 재배포로 복구(P34/P35 참고).", "mimeType": "text/markdown"}
  }' | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'error' in d: raise SystemExit('알림 정책 생성 실패: ' + json.dumps(d['error'])[:300])
print('✓ 알림 정책 생성:', d['name'])"
fi

echo "✅ 완료 — 이제 Hosting /api 경로 장애도 5~10분 내 이메일 알림이 온다"
