#!/usr/bin/env bash
# Cloud Run 자가 복구 설정 (P35) — "죽어도 사람 없이 살아나게"의 마지막 조각.
#
# 이미 자동인 것(설정 불필요):
#   - 컨테이너가 크래시하면 Cloud Run이 새 인스턴스를 띄운다.
#   - 새 리비전이 **기동에 실패하면** 트래픽을 넘기지 않는다.
# 이 스크립트가 채우는 구멍:
#   - **살아는 있는데 응답을 못 하는 상태(hang)**. 크래시가 아니라 Cloud Run이 모르고,
#     포트는 열려 있어 기본 TCP startup 체크도 통과한다. liveness probe만이 잡아 재시작한다.
#
# ⚠ 이 변경은 위 "기동 실패 보호"의 **밖**에 있다. probe가 잘못돼도 컨테이너 기동 자체는
#   성공하므로 새 리비전이 트래픽을 100% 받고, 그 다음부터 무한 재시작에 들어간다.
#   그래서 이 스크립트는 (1) 직전 리비전을 먼저 기억하고 (2) probe가 실제로 재시작을
#   유발하는지 **충분히 오래 관측한 뒤** (3) 이상하면 스스로 트래픽을 되돌린다.
#
# 왜 /healthz인가(=/health가 아니라): /healthz는 프로세스 생존만 본다(의존성 미확인).
# DB를 보는 /health를 걸면 Firestore가 잠깐 흔들릴 때 **전 인스턴스가 동시 재시작**해
# 순간 장애가 전면 장애로 증폭된다. 재시작으로 고쳐지는 문제(hang)만 재시작한다.
#
# 실행: ./setup-selfheal.sh   (gcloud 로그인 필요, 약 4분 소요 — 관측 시간이다)
set -euo pipefail

PROJECT=rize-218c1
REGION=asia-northeast3
SERVICE=rize-api
PUBLIC_HEALTH=https://rize-218c1.web.app/api/health

svc() { gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT" "$@"; }

# ── 0) 되돌릴 지점을 먼저 확보한다 ───────────────────────────────────────────
PREV_REV=$(svc --format='value(status.latestReadyRevisionName)')
if [ -z "$PREV_REV" ]; then
  echo "🚫 현재 리비전을 확인할 수 없다 — 되돌릴 지점 없이는 진행하지 않는다."
  exit 1
fi
echo "현재 리비전(롤백 지점): $PREV_REV"

CUR_PROBE=$(svc --format='value(spec.template.spec.containers[0].livenessProbe)')
if [ -n "$CUR_PROBE" ]; then
  echo "⚠ 이미 liveness probe가 설정돼 있다: $CUR_PROBE"
  echo "  덮어쓰고 계속한다(같은 설정이면 무해)."
fi

# ── 1) probe 적용 ────────────────────────────────────────────────────────────
# httpGet.port를 **지정하지 않는다** — 생략하면 Cloud Run이 컨테이너 포트를 쓴다.
# 8080을 하드코딩하면 누군가 나중에 --port를 바꿔 재배포하는 순간 이 probe가 전
# 인스턴스를 죽인다. 그때는 이 스크립트를 돌린 사람이 곁에 없다.
#
# 30s × 3회 = 약 90초 이상 응답 불능일 때만 재시작한다. 짧게 잡으면 GC 지연·일시적
# 부하로 멀쩡한 인스턴스가 죽는다(재시작이 원인이 되는 사고).
echo "liveness probe 적용 중 (/healthz · 30초 주기 · 3회 연속 실패 시 재시작)…"
gcloud run services update "$SERVICE" \
  --region "$REGION" --project "$PROJECT" \
  --liveness-probe=httpGet.path=/healthz,initialDelaySeconds=10,periodSeconds=30,timeoutSeconds=5,failureThreshold=3 \
  --quiet

NEW_REV=$(svc --format='value(status.latestReadyRevisionName)')
echo "새 리비전: $NEW_REV"

rollback() {
  echo "↩ 트래픽을 이전 리비전으로 되돌린다: $PREV_REV"
  if gcloud run services update-traffic "$SERVICE" --region "$REGION" --project "$PROJECT" \
       --to-revisions "$PREV_REV=100" --quiet; then
    echo "   ✅ 롤백 완료 — probe 없는 이전 상태로 서비스 중이다."
  else
    echo "   🚨 자동 롤백 실패 — 콘솔에서 즉시 수동 롤백할 것:"
    echo "   https://console.cloud.google.com/run/detail/$REGION/$SERVICE/revisions?project=$PROJECT"
  fi
}

# ── 2) 관측 — 여기가 이 스크립트의 핵심이다 ─────────────────────────────────
# probe가 100% 실패해도 첫 재시작까지 initialDelay(10) + period(30)×threshold(3) ≈ 100초가
# 걸린다. 종전처럼 `sleep 5` 후 curl 한 번으로 판정하면 **어떤 오설정에서도 통과**한다
# (그 시점엔 아직 아무 재시작도 안 일어났다). 그래서 그 창을 넘겨 3분 이상 관측하고,
# 컨테이너가 반복 기동하는 흔적(기동 로그 반복)을 직접 센다.
echo "관측 중 — probe 실패는 약 100초 뒤부터 나타나므로 3분 이상 지켜본다…"
fail=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do   # 12 × 20초 = 4분
  sleep 20
  body=$(curl -s -m 15 "$PUBLIC_HEALTH?cb=$(date +%s)$RANDOM" || true)
  case "$body" in
    *'"status":"ok"'*)  fail=0 ;;
    *'"degraded"'*)
      # Firestore 블립은 probe와 무관하다(/api/health는 DB까지 본다). 재시작 근거로 쓰지 않는다.
      echo "  [$i/12] /api/health degraded — DB 흔들림(probe와 무관), 계속 관측" ;;
    *)  fail=$((fail + 1))
        echo "  [$i/12] 응답 없음/이상 (연속 $fail회)" ;;
  esac
  if [ "$fail" -ge 3 ]; then
    echo "🚨 연속 3회 응답 불능 — probe 오설정으로 재시작 루프에 빠진 것으로 판단한다."
    rollback
    exit 1
  fi
done

# ── 3) 재시작 흔적 확인 — 응답이 되더라도 뒤에서 계속 죽고 있을 수 있다 ─────
# 새 리비전이 4분 사이에 여러 번 기동했다면(기동 로그가 여러 줄) probe가 컨테이너를
# 반복해서 죽이고 있다는 뜻이다. 인스턴스가 여럿일 수 있어 1~2회는 정상 범위로 본다.
starts=$(gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.revision_name=\"$NEW_REV\" AND textPayload:\"listening on\"" \
  --project "$PROJECT" --freshness 6m --limit 20 --format='value(timestamp)' 2>/dev/null | wc -l | tr -d ' ')
echo "새 리비전 기동 로그 횟수(6분 내): $starts"
if [ "${starts:-0}" -gt 4 ]; then
  echo "🚨 기동이 $starts회 반복됐다 — 재시작 루프로 판단한다."
  rollback
  exit 1
fi

echo "✅ 완료 — probe가 적용됐고 4분 관측 동안 재시작 루프 징후가 없다."
echo "   이제 응답 불능(hang) 상태가 되면 약 100초 뒤 Cloud Run이 자동으로 재시작한다."
