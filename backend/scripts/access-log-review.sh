#!/usr/bin/env bash
# 접속기록 월 1회 점검 리포트 — 「개인정보의 안전성 확보조치 기준」(고시 제2026-9호, 2026.7.1. 일부개정·같은 날 시행) §8②
# ("접속기록을 확인·점검하는 주기·방법·사후조치절차를 내부 관리계획으로 정하고 이행") · P61.
#
# 내부 관리계획(backend/README.md '접속기록' 절): 주기 매월 첫 영업일 · 담당 람 · 방법 이 스크립트 ·
# 산출물 work_log/access-review/YYYY-MM.md(점검 "기록"이 곧 이행 증거) · 사후조치 이상 uid →
# 스태프 deactivate(POST /v1/staff/{uid}/deactivate) + 정보주체 통지 판단.
#
# `gcloud logging read`만 쓴다(Log Analytics 미사용 — --enable-analytics는 불가역이라 켜지 않았다).
# 라인 스키마는 계약 v2.30(docs/API계약_v1.md) — 키 이름이 바뀌면 여기도 바뀐다.
#
# LogEntry 모양 주의: Cloud Logging은 stdout JSON의 `time`·`severity`·`logging.googleapis.com/trace`를
# jsonPayload에서 **떼어** LogEntry 최상위(timestamp·severity·trace)로 승격한다. 그래서 시각은
# `e.timestamp`에서 읽고 jsonPayload.time은 폴백일 뿐이다(로컬 stdout을 직접 저장한 파일 대비).
#
# 실행: ./backend/scripts/access-log-review.sh [YYYY-MM]                      (기본: 지난달)
#      ./backend/scripts/access-log-review.sh --dry-run FILE [--out PATH] [YYYY-MM]
#        gcloud 대신 저장된 LogEntry 배열(JSON)을 읽는다 — 스크립트 스모크·리포트 형식 확인용.
#        dry-run의 출력 기본은 /tmp/access-review-<월>.md (work_log/access-review/를 더럽히지 않는다).
#      --out PATH 는 두 모드 모두에서 출력 경로를 덮어쓴다.
set -euo pipefail

PROJECT=rize-218c1
LOCATION=asia-northeast3
BUCKET=access-log-2y
FILTER_BASE='jsonPayload.log_type="access"'

DRY_RUN_FILE=""
OUT_OVERRIDE=""
MONTH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) [ $# -ge 2 ] || { echo "--dry-run FILE 필요" >&2; exit 2; }; DRY_RUN_FILE=$2; shift 2 ;;
    --out)     [ $# -ge 2 ] || { echo "--out PATH 필요" >&2; exit 2; }; OUT_OVERRIDE=$2; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*)        echo "알 수 없는 옵션: $1" >&2; exit 2 ;;
    *)         MONTH=$1; shift ;;
  esac
done
if [ -z "$MONTH" ]; then
  MONTH=$(date -v-1m +%Y-%m 2>/dev/null || date -d 'last month' +%Y-%m)
fi
case "$MONTH" in
  [0-9][0-9][0-9][0-9]-[0-1][0-9]) ;;
  *) echo "월 형식은 YYYY-MM: $MONTH" >&2; exit 2 ;;
esac

# 월 경계는 KST — 접속기록의 timestamp는 UTC이므로 조회 창을 KST 기준으로 옮긴다.
START="${MONTH}-01T00:00:00+09:00"
if date -v+1m >/dev/null 2>&1; then
  END=$(date -j -v+1m -f '%Y-%m-%d' "${MONTH}-01" +%Y-%m-01)T00:00:00+09:00
else
  END=$(date -d "${MONTH}-01 +1 month" +%Y-%m-01)T00:00:00+09:00
fi
FILTER="$FILTER_BASE AND timestamp>=\"$START\" AND timestamp<\"$END\""

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
if [ -n "$OUT_OVERRIDE" ]; then
  OUT=$OUT_OVERRIDE
elif [ -n "$DRY_RUN_FILE" ]; then
  OUT="/tmp/access-review-$MONTH.md"
else
  OUT="$ROOT/work_log/access-review/$MONTH.md"
fi
mkdir -p "$(dirname "$OUT")"

# 한 달 스태프 요청 ~10만 건 상한(현재 규모 ~3천/일). 넘으면 잘렸다고 리포트에 적는다.
LIMIT=100000
if [ -n "$DRY_RUN_FILE" ]; then
  [ -r "$DRY_RUN_FILE" ] || { echo "dry-run 파일을 읽을 수 없다: $DRY_RUN_FILE" >&2; exit 1; }
  RAW=$DRY_RUN_FILE
  echo "dry-run: $DRY_RUN_FILE → $OUT (월 $MONTH — 창 필터는 적용하지 않는다)"
else
  RAW=$(mktemp)
  trap 'rm -f "$RAW"' EXIT
  echo "조회: $MONTH ($START ~ $END) — 버킷 $BUCKET"
  ERR=$(mktemp)
  # 조회 실패와 0건을 구분한다 — 실패를 빈 리포트로 삼키면 "이상 없음"이 거짓 이행 증거가 된다.
  if ! gcloud logging read "$FILTER" --project="$PROJECT" --bucket="$BUCKET" --location="$LOCATION" \
      --view=_AllLogs --limit="$LIMIT" --format=json > "$RAW" 2> "$ERR"; then
    echo "gcloud logging read 실패 — 리포트를 만들지 않는다:" >&2
    cat "$ERR" >&2
    rm -f "$ERR"
    exit 1
  fi
  rm -f "$ERR"
fi

python3 - "$RAW" "$OUT" "$MONTH" "$LIMIT" <<'PY'
import json, sys, collections, datetime
raw, out, month, limit = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
entries = json.load(open(raw, encoding="utf-8"))
if not isinstance(entries, list):
    sys.exit(f"LogEntry 배열(JSON list)이 아니다: {type(entries).__name__}")
truncated = len(entries) >= limit

KST = datetime.timezone(datetime.timedelta(hours=9))

def kst(ts):
    # "2026-09-06T03:09:38.681344Z" → KST datetime. 나노초 정밀도는 fromisoformat이 못 받으므로 6자리로 줄인다.
    if not ts:
        return None
    s = ts.replace("Z", "+00:00")
    if "." in s:
        head, tail = s.split(".", 1)
        frac = tail[:-6] if tail[-6] in "+-" else tail
        tz = tail[len(frac):]
        s = f"{head}.{frac[:6]}{tz}"
    return datetime.datetime.fromisoformat(s).astimezone(KST)

def cell(v):
    # 마크다운 표 셀 — `|`가 열을 깨고, 개행이 행을 깬다(UA·path는 클라이언트가 채운다).
    return str(v if v not in (None, "") else "-").replace("|", "\\|").replace("\n", " ")

rows = []
for e in entries:
    p = e.get("jsonPayload") or {}
    if p.get("log_type") != "access":
        continue
    # time·severity는 LogEntry로 승격돼 jsonPayload에 없다 — 최상위를 먼저, jsonPayload는 폴백.
    r = dict(p)
    r["_ts"] = e.get("timestamp") or p.get("time")
    r["_severity"] = e.get("severity") or p.get("severity") or "-"
    r["_kst"] = kst(r["_ts"])
    rows.append(r)

def when(r):
    return r["_kst"].strftime("%m-%d %H:%M") if r["_kst"] else "-"

def ip_cells(r):
    # remote_ip는 위조 가능(RealIP: True-Client-IP → X-Real-IP → XFF 첫 값) — xff_last(프록시가 덧붙인
    # 마지막 값)를 나란히 둔다. Hosting 경유는 xff_last가 Hosting 프록시라 x_forwarded_for의 끝에서 둘째를 본다.
    return f"{cell(r.get('remote_ip'))} | {cell(r.get('xff_last'))} | {cell(r.get('x_forwarded_for'))}"

by_uid_route = collections.Counter((r.get("uid") or "-", r.get("method"), r.get("route")) for r in rows)
denials = [r for r in rows if r.get("status") in (401, 403)]
night = [r for r in rows if r.get("uid") and r["_kst"] and not (6 <= r["_kst"].hour < 23)]
sensitive = collections.Counter(r.get("uid") or "-" for r in rows
                                if any(seg in (r.get("route") or "") for seg in ("/body-photos", "/inbody")))
# "다운로드 상황"(§8②) — 이 서비스에 파일 다운로드 기능은 없다. 대량 조회 = 목록 GET.
# router.go의 목록 GET 라우트 화이트리스트(/v1·/api/v1 접두 제거 후 비교). {id} 단건·/me·/stats·/center는 제외.
LIST_ROUTES = {
    "/join/requests", "/consult-requests", "/members", "/passes", "/slots", "/bookings", "/recurrings",
    "/homeworks", "/hw-checks", "/payments", "/contracts", "/workout-logs", "/body-photos", "/inbody",
    "/staff", "/admin/centers",
}
def list_route(route):
    for pre in ("/api/v1", "/v1"):
        if route.startswith(pre):
            return route[len(pre):] in LIST_ROUTES
    return False
bulk = collections.Counter((r.get("uid") or "-", r.get("route")) for r in rows
                           if r.get("method") == "GET" and r.get("status") == 200 and list_route(r.get("route") or ""))
errors = [r for r in rows if (r.get("status") or 0) >= 500 or r.get("aborted")]
no_ts = sum(1 for r in rows if not r["_kst"])

L = []
L.append(f"# 접속기록 점검 — {month}\n")
L.append(f"- 점검일: {datetime.date.today().isoformat()} · 담당: 람 · 방법: backend/scripts/access-log-review.sh · 근거: 안전성 확보조치 기준 §8②")
L.append(f"- 총 라인 {len(rows)}건" + (f" — **상한 {limit}건에 걸려 잘렸다(창을 줄여 재실행)**" if truncated else "")
         + (f" — **시각 없는 라인 {no_ts}건(심야 집계에서 빠짐)**" if no_ts else ""))
L.append(f"- 거부(401/403) {len(denials)}건 · 심야(23~06 KST) 스태프 접속 {len(night)}건 · 5xx/aborted {len(errors)}건\n")
L.append("## 1. uid × 수행업무(method route) 건수 상위 40\n")
L.append("| uid | method | route | 건수 |\n|---|---|---|---|")
for (uid, m, rt), n in by_uid_route.most_common(40):
    L.append(f"| {cell(uid)} | {cell(m)} | {cell(rt)} | {n} |")
L.append("\n## 2. 거부(401·403) — IP·시각\n")
L.append("remote_ip는 클라이언트가 위조할 수 있다(RealIP가 True-Client-IP/X-Real-IP/XFF 첫 값을 믿는다). 신뢰 값은 xff_last(Hosting 경유는 x_forwarded_for의 끝에서 둘째).\n")
L.append("| 시각(KST) | status | uid | role | method | path | remote_ip | xff_last | x_forwarded_for |\n|---|---|---|---|---|---|---|---|---|")
for r in denials[:200]:
    L.append(f"| {when(r)} | {cell(r.get('status'))} | {cell(r.get('uid'))} | {cell(r.get('role'))} | {cell(r.get('method'))} | {cell(r.get('path'))} | {ip_cells(r)} |")
if len(denials) > 200:
    L.append(f"\n(+{len(denials)-200}건 생략)")
L.append("\n## 3. 심야(23~06 KST) 스태프 접속\n")
L.append("| 시각(KST) | uid | method | route | subject | remote_ip | xff_last | x_forwarded_for |\n|---|---|---|---|---|---|---|---|")
for r in night[:200]:
    subj = json.dumps(r.get("subject"), ensure_ascii=False) if r.get("subject") else "-"
    L.append(f"| {when(r)} | {cell(r.get('uid'))} | {cell(r.get('method'))} | {cell(r.get('route'))} | {cell(subj)} | {ip_cells(r)} |")
L.append("\n## 4. 민감정보 경로(/body-photos·/inbody) 접근 상위 uid\n")
L.append("| uid | 건수 |\n|---|---|")
for uid, n in sensitive.most_common(20):
    L.append(f"| {cell(uid)} | {n} |")
L.append("\n## 5. 대량 조회(목록 GET 200) — '다운로드 상황' 대응\n")
L.append("| uid | route | 건수 |\n|---|---|---|")
for (uid, rt), n in bulk.most_common(20):
    L.append(f"| {cell(uid)} | {cell(rt)} | {n} |")
L.append("\n## 6. 판정·사후조치\n")
L.append("- [ ] 이상 없음")
L.append("- [ ] 이상 uid: ______ → 조치: 스태프 deactivate(POST /v1/staff/{uid}/deactivate) / 정보주체 통지 판단 / 기타: ______")
open(out, "w", encoding="utf-8").write("\n".join(L) + "\n")
print(f"→ {out} ({len(rows)}건)")
PY
