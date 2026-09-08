#!/usr/bin/env bash
# 접속기록 2년 보관 인프라 — 「개인정보의 안전성 확보조치 기준」(고시 제2026-9호, 2026.7.1. 일부개정·같은 날 시행) §8①2호
# (민감정보를 처리하는 개인정보처리시스템 → 2년 이상) · P61(P56 L9).
#
# 무엇을 만드나: Cloud Logging 전용 버킷(asia-northeast3, 보존 740일) + 그 버킷으로
# jsonPayload.log_type="access" 라인만 라우팅하는 sink. 서버(backend/internal/api/accesslog.go)가
# stdout에 쓰는 접속기록 JSON 한 줄이 이 sink를 타고 2년 버킷에 쌓인다.
#
# 멱등: 있으면 건너뛰고(보존일이 낮으면 올린다), sink는 필터 드리프트를 교정한다.
# 기본은 **잠그지 않는다** — `--lock`은 불가역(버킷 수정·삭제 불가, 보존 변경 불가)이라 람이
# 첫 라인이 들어온 것을 확인하고 1~2주 운영한 뒤 따로 결정한다. 라인 0건인 버킷은 잠그지 않는다
# (잘못 만든 빈 버킷을 740일 동안 영구화하는 사고 방지).
#
# `--enable-analytics`는 넣지 않는다 — 되돌릴 수 없는 옵션이고 점검(access-log-review.sh)은
# `gcloud logging read`만으로 충분하다.
#
# 비소급: sink는 생성 이후의 새 엔트리만 라우팅한다. 이 스크립트를 실행한 날이 "2년 보관"의
# 시작일이다 — 실행 후 backend/README.md 접속기록 절의 "sink 시작일"을 기입한다.
#
# 실행: ./backend/scripts/setup-access-log.sh            버킷+sink 생성/확인 + 최근 5건 조회
#      ./backend/scripts/setup-access-log.sh --lock     위에 더해 버킷 잠금(yes 확인)
# (gcloud 로그인 필요 — rizejoy91@gmail.com / 프로젝트 rize-218c1)
set -euo pipefail

PROJECT=rize-218c1
# privacy.html "데이터는 대한민국(서울) 리전에 보관" — global 금지. 버킷 위치는 생성 후 변경 불가.
LOCATION=asia-northeast3
BUCKET=access-log-2y
SINK=access-log-2y
# 2년(윤년 포함 731일) + 여유 9일. 고시 §8① "2년 이상"이라 731이 하한.
RETENTION_DAYS=740
FILTER='resource.type="cloud_run_revision" AND resource.labels.service_name="rize-api" AND jsonPayload.log_type="access"'
DEST="logging.googleapis.com/projects/$PROJECT/locations/$LOCATION/buckets/$BUCKET"

if [ "${1:-}" != "" ] && [ "${1:-}" != "--lock" ]; then
  echo "알 수 없는 인자: $1 (허용: --lock)" >&2
  exit 2
fi

# ---- 버킷(멱등) ----
if gcloud logging buckets describe "$BUCKET" --location="$LOCATION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "✓ 버킷 존재: $BUCKET ($LOCATION)"
  CUR=$(gcloud logging buckets describe "$BUCKET" --location="$LOCATION" --project="$PROJECT" --format='value(retentionDays)')
  if [ "${CUR:-0}" -lt "$RETENTION_DAYS" ]; then
    echo "  보존일 $CUR → $RETENTION_DAYS 상향"
    gcloud logging buckets update "$BUCKET" --location="$LOCATION" --project="$PROJECT" --retention-days="$RETENTION_DAYS"
  fi
  LOCKED=$(gcloud logging buckets describe "$BUCKET" --location="$LOCATION" --project="$PROJECT" --format='value(locked)')
  echo "  잠금 상태: ${LOCKED:-False}"
else
  echo "버킷 생성: $BUCKET ($LOCATION, ${RETENTION_DAYS}일)"
  gcloud logging buckets create "$BUCKET" --location="$LOCATION" --project="$PROJECT" \
    --retention-days="$RETENTION_DAYS" \
    --description="개인정보처리시스템 접속기록(안전성 확보조치 기준 §8, 2년 이상). 위변조 방지=잠금(--lock). P61"
fi

# ---- sink(멱등) ----
# 같은 프로젝트의 로그 버킷이 목적지면 sink가 자동 인가된다(configure_export_v2) — IAM 부여 단계 없음.
if gcloud logging sinks describe "$SINK" --project="$PROJECT" >/dev/null 2>&1; then
  echo "✓ sink 존재: $SINK — 필터·목적지 교정(멱등)"
  gcloud logging sinks update "$SINK" "$DEST" --project="$PROJECT" --log-filter="$FILTER"
else
  echo "sink 생성: $SINK → $DEST"
  gcloud logging sinks create "$SINK" "$DEST" --project="$PROJECT" --log-filter="$FILTER" \
    --description="access 라인만 2년 버킷으로 (P61). 생성일 = 2년 보관 시작일(비소급)"
fi
# _Default 버킷에는 그대로 둔다(30일 운영 뷰 유지). 중복 수집량은 월 수 MB — 50GiB 무료 한도 안.

# ---- 확인 ----
# 조회 **실패**와 **0건**을 구분한다 — `|| true`로 실패를 0건으로 삼키면 "아직 안 쌓였네"로 읽혀
# 권한·버킷 이름 오류가 며칠 숨는다(그리고 0건은 잠금 거부 조건이라 실패가 잠금을 막는 것과 겹친다).
ERR=$(mktemp)
if ! TS=$(gcloud logging read "$FILTER" --project="$PROJECT" --bucket="$BUCKET" --location="$LOCATION" \
    --view=_AllLogs --limit=5 --format='value(timestamp)' 2> "$ERR"); then
  echo "gcloud logging read 실패 — 버킷/권한/필터를 확인할 것:" >&2
  cat "$ERR" >&2
  rm -f "$ERR"
  exit 1
fi
rm -f "$ERR"
COUNT=$(printf '%s\n' "$TS" | grep -c . || true)
echo "버킷 내 최근 라인: $COUNT 건 (sink는 비소급 — 생성 이후 요청부터 쌓인다)"
echo "→ README '접속기록' 절의 sink 시작일에 오늘 날짜를 기입할 것: $(date +%Y-%m-%d)"

# ---- 잠금(선택, 불가역) ----
if [ "${1:-}" = "--lock" ]; then
  if [ "$COUNT" -eq 0 ]; then
    echo "라인이 0건인 버킷은 잠그지 않는다(잘못 만든 버킷을 ${RETENTION_DAYS}일 동안 영구화하는 사고 방지)" >&2
    exit 1
  fi
  read -r -p "불가역 잠금: 버킷 수정·삭제 불가, 보존 ${RETENTION_DAYS}일 고정. 계속? (yes) " ans
  [ "$ans" = yes ] || { echo "취소"; exit 1; }
  gcloud logging buckets update "$BUCKET" --location="$LOCATION" --project="$PROJECT" --locked
  echo "✓ 잠금 완료 — README '잠금 상태'를 '적용($(date +%Y-%m-%d))'으로 갱신할 것"
fi
