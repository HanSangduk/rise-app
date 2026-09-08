---
id: P61
title: 개인정보처리시스템 접속기록 — 2년 보관·위변조 방지·월 1회 점검(안전성 확보조치 기준 §8, P56 L9) — 람 실행 대기
status: 진행 중
domain: backend
created: 2026-09-06
completed:
---

# P61 — 접속기록 2년 보관·점검 (P56 L9) — **람 실행 대기**

> 코드·계약·운영문서는 완료. 남은 것은 전부 람의 손: **서버 배포 → `setup-access-log.sh` → README sink 시작일 →
> privacy.html v1.1 행 → Hosting → 잠금 결정**. 그 전까지 privacy.html의 "2년·위변조 방지·점검"은 아직 거짓이다.

## 목표
privacy.html이 약속하는 "개인정보처리시스템 접속기록 2년 이상 보관 · 위·변조 방지 · 점검"(:275·:499·:534)을
서버·인프라·계약·운영 절차로 **참으로 만든다**. 종전엔 chi 평문 요청 로그뿐이라 uid·정보주체·수행업무가
없어 고시 §2의 '접속기록'이 아니었고, 그마저 _Default 버킷 30일 뒤 사라졌다(P56:87-99). 설계 근거
`scratchpad/design_L9.md`(적대 검토는 한도 초과로 실패 → 오케스트레이터 직접 검토 후 결정 11개를 덮어씀).

## 결정 사항
- **법령**: 「개인정보의 안전성 확보조치 기준」 현행 = 고시 제2026-9호(law.go.kr 헤더 '2026. 7. 1., 일부개정' —
  시행일은 law.go.kr 헤더 [시행 2026. 7. 1.]로 확인 — 개정과 같은 날 시행. 코드·문서 4곳 모두 '2026.7.1. 일부개정·같은 날 시행'으로 통일). §8①2호(민감정보
  처리 시스템 → 2년 이상 — 체형사진·체성분을 민감정보로 취급하므로 회원 수 무관), §8②(점검 주기·방법·
  사후조치는 **내부 관리계획으로 정하고 이행** — 현행 조문에 "월 1회" 없음, 우리가 정한 값), §8③(안전 보관).
- **구조**: v1 클로저 안 `auth.Middleware` **앞**에 `accessLog` — 401을 기록하려면 auth 앞이어야 하고,
  값 타입 Principal은 auth의 파생 컨텍스트 밖에서 안 보이므로 **포인터 엔트리를 앞에서 심고 auth가 2줄로
  역주입**한다. 라인은 응답 뒤 defer에서 쓴다(chi v5.2.1은 서브라우터 미들웨어 진입 시점에 RoutePattern이
  "/v1/*" — next 뒤에만 완전 패턴·URLParam이 읽힌다. 401·404는 "/v1/*"로 남아 path를 병기).
- **패닉**: defer의 `recover()`로 잡아 500·ERROR 라인을 쓴 뒤 **같은 값으로 재패닉** — 바깥 recoverJSON이
  계약 포맷 500을 만든다. 안 잡으면 ww.Status()=0이라 500 라인이 안 남는다.
- **severity**: 2xx/3xx/4xx INFO · 401/403 WARNING · 5xx ERROR. 항상 명시(Cloud Run 평문 기본값에 안 기댐).
- **출력 주입**: NewRouter 시그니처 무변경. `Handlers.accessOut` + `WithAccessLogWriter(io.Writer)`(nil → stdout).
  project는 `h.svc.cfg.GCPProject`(trace 필드 접두 — 비면 생략).
- **기록 범위**: 스태프(owner/trainer/superadmin) 전부 + 역할 무관 401/403. 회원 정상 요청은 **기록하지
  않는다**(§8① 정보주체 제외 + 최소수집). 클로저 밖(/healthz·/health·/v1/public/*)은 자동 제외.
- **절대 기록 금지**: 본문·Authorization/X-Dev-*·쿠키·쿼리 원문(화이트리스트 `member`만 subject로)·
  Principal.Phone·이름. `remote_ip`는 포트를 뗀다(구현 중 실측: XFF 없으면 RealIP가 "ip:port"를 그대로 둔다).
- **chi middleware.Logger 제거** — RequestURI에 `?q=이름·번호`가 실려 30일 운영 로그에 평문(P56 L9).
  **정직 고지**: 쿼리 문자열은 Cloud Run 요청 로그(30일)에는 **여전히 남는다** — 없앤 것은 컨테이너 로그의
  두 번째 사본이고, 접속기록(2년)에 싣지 않는다는 것이 이번 보장의 전부.
- **정보주체 훅** `setAccessSubject(ctx, memberID)`: 본문에만 id가 있는 POST 12곳, 성공 응답의 id 사용.
  `CreateHomework`는 배정 대상이 여럿일 수 있어 **1명일 때만** 확정(여럿을 한 칸에 넣으면 uid×member
  집계가 깨진다 — 설계에 없던 판단).
- **인프라**: 버킷 `access-log-2y`(asia-northeast3 — privacy.html:136 서울 리전, 위치 변경 불가; 740일) +
  sink(`jsonPayload.log_type="access"`). `--lock` 기본 꺼짐·0건 버킷 잠금 거부·yes 확인.
  **`--enable-analytics`는 넣지 않는다**(불가역) — 점검은 `gcloud logging read`만. _Default는 그대로.
- **내부 관리계획**: 주기 매월 첫 영업일 · 담당 람 · 방법 `access-log-review.sh` → `work_log/access-review/
  YYYY-MM.md` · 사후조치 스태프 deactivate + 정보주체 통지 판단. 파일 다운로드 기능은 없으므로 §8②의
  "다운로드 상황"은 목록 GET을 route로 식별.
- **privacy.html은 이번에 건드리지 않는다** — 인프라 적용 전엔 문구가 아직 거짓이고, 문서에서 의무를 지우는
  것은 답이 아니다(P56:92). 적용 후 개정 이력 행 + 점검 주기 명시(후속 작업에 문안).

## 진행 단계
- [x] 설계 읽기·결정 11개 반영 계획
- [x] `accesslog.go` 신설(엔트리·훅·미들웨어·라인 조립·trace·remoteIP)
- [x] `auth.go` Principal 역주입 2줄 · `router.go` Logger 제거 + accessLog(auth 앞) · `handlers_me.go` accessOut 필드
- [x] 핸들러 훅 12곳
- [x] `accesslog_test.go` 10건(설계 9건 + severity 표) — 전건 그린, 기존 회귀 4건 그린
- [x] 뮤테이션 4건 kill (검증 절)
- [x] `backend/scripts/setup-access-log.sh` · `access-log-review.sh` 신설(`bash -n`만 — 실행은 람)
- [x] `backend/README.md` 접속기록 절 · `docs/API계약_v1.md` v2.30 절
- [x] 검증 이슈 10건 반영(2026-09-06 2차): 점검 스크립트 LogEntry `timestamp` 읽기 + `--dry-run FILE`/`--out PATH` +
  샘플 testdata로 **실제 실행 확인** · `xff_last`(신뢰 접속지) · 타임아웃 504/헤더 후 패닉 `aborted` · 헤더 512자 클립 ·
  리포트 `|` 이스케이프·목록 라우트 화이트리스트 · setup 조회 실패/0건 분리 · 기록 범위 문구·고시 표기 통일 · 계약 참조 정정
- [ ] **람 실행 대기** — 서버 배포 → `setup-access-log.sh` 실행 → README sink 시작일 기입 → privacy.html v1.1 행 → Hosting 배포
- [ ] **람 실행 대기** — 잠금(`--lock`) 결정 · 첫 월 점검 실행

## 변경 파일
- `backend/internal/api/accesslog.go` — 신설. accessEntry(포인터 컨텍스트 값)·accessEntryFrom·setAccessSubject·
  WithAccessLogWriter·accessLine 스키마·accessLog 미들웨어(defer + recover 재패닉)·writeAccessLine·remoteIP·traceField
- `backend/internal/api/accesslog_test.go` — 신설. 10건
- `backend/internal/api/auth.go` — resolve 성공 직후 역주입 2줄(주석 포함)
- `backend/internal/api/router.go` — `middleware.Logger` 삭제, v1 클로저 auth 앞 `accessLog`, `accessLogProject`, NewRouter 주석
- `backend/internal/api/handlers_me.go` — `Handlers.accessOut io.Writer`, JoinApprove 훅
- `backend/internal/api/handlers_{bookings,passes,payments,contracts,media,workout,homework,members}.go` — setAccessSubject 훅 11곳
- `backend/scripts/setup-access-log.sh` · `backend/scripts/access-log-review.sh` — 신설(디렉터리 신설). 2차: review에
  `--dry-run FILE`·`--out PATH`·LogEntry `timestamp` 우선·`xff_last` 컬럼·셀 이스케이프·목록 라우트 화이트리스트, setup에
  조회 실패(exit 1)/0건 분리
- `backend/scripts/testdata/access-log-entries.sample.json` — 신설. 실제 LogEntry 모양(`timestamp`·`severity` 최상위,
  jsonPayload에 `time`/`severity` **없음**) 4건 — 200 PUT(subject)·심야 body-photos GET·401(path에 `|`)·504
- `backend/README.md` — "### 접속기록(안전성 확보조치 기준 §8) — 2년 버킷 · 월 1회 점검 (v2.30, P61)" 절(Storage 절 뒤, 알려진 갭 앞)
- `docs/API계약_v1.md` — 파일 끝 "## v2.30 접속기록 관측 규약"
- `work_log/README.md` — P61 인덱스 한 줄

## 검증
- `cd backend && go build ./... && go test ./... -count=1` → api·config·domain·store **ok** · `go vet ./internal/api/` 무출력
- 신규 10건: RecordsStaffRequest(5요소·status=응답코드·RFC3339Nano·subject) · NeverContainsSecretsOrBody(토큰·쿠키·
  번호·이름·`q=`·`X-Dev` 부재 + `member=`는 옮겨짐) · SkipsUnauthenticatedSurface(7경로 0줄) · RecordsDenials(401
  WARNING uid "" path · 403 WARNING uid/role) · OmitsMemberSelfAccess(회원 200 → 0줄, 회원 403 → 1줄) · MirrorPaths ·
  SubjectFromBodyViaHook(members·passes·bookings 3연쇄) · SurvivesPanic(테스트 전용 라우터, 500 계약 포맷 + ERROR
  라인 + route 유지) · TraceField(있음/없음) · SeverityByStatus(6값)
- 기존 회귀: TestResponsesDefaultToNoStore · TestPublicBusinessKeepsItsOwnCacheHeader · TestRecoverJSONKeepsContractFormat ·
  TestAPIPrefixMirror 그린
- 뮤테이션(코드를 실제로 바꿔 실행 후 복원, diff로 복원 확인):
  - (a) auth.go 역주입 2줄 제거 → RecordsStaffRequest·RecordsDenials·OmitsMemberSelfAccess·SurvivesPanic **FAIL**
  - (b) `Path: r.URL.RequestURI()`로 쿼리 원문 싣기 → NeverContainsSecretsOrBody **FAIL**
  - (c) recover 후 `panic(rec)` 제거 → SurvivesPanic **FAIL**(응답이 계약 포맷 500이 아님)
  - (d) 기록 범위 판정을 `if false`로 → OmitsMemberSelfAccess **FAIL**
- 스크립트(1차): `bash -n` 2건 통과(shellcheck 미설치). gcloud 경로는 **실행하지 않았다.**
- 실측 라인(테스트 피크): 401 → `route:"/v1/*"`, `path:"/v1/me"`, uid ""; 404(스태프) → route "/v1/*" + path;
  `/v1/staff/{uid}/offdays` → `subject.staff_uid`.
- **2차(검증 이슈 반영, 2026-09-06)**: `go build ./... && go vet ./internal/api/ && go test ./... -count=1` → api·config·domain·store **ok**.
  신규 4건 + 확장 1건: `TestAccessLogRemoteIPSpoofableXFFLastTrusted`(X-Real-IP 위조값이 remote_ip에 실리고 xff_last는
  XFF 마지막 값·공백 제거, XFF 없으면 필드 생략) · `TestAccessLogTimeoutIs504`(chi Timeout 20ms + ctx 존중 핸들러 →
  504·ERROR·aborted 없음) · `TestAccessLogPanicAfterHeaderKeepsStatus`(200 헤더 후 패닉 → status 200 유지·aborted true·
  ERROR·bytes>0·재패닉 값 보존) · `TestAccessLogClipsLongHeaders`(UA/XFF 512룬 + "…", xff_last는 온전, 한글 경계 안전) ·
  `TestAccessLogOmitsMemberSelfAccess`에 회원 404 → 0줄 추가.
  뮤테이션(코드를 실제로 바꿔 실행 후 `diff -q`로 복원 확인): (e) 504 분기 제거(status 0 → 항상 500) → **TimeoutIs504 FAIL**;
  (f) `XFFLast` 대입 제거 → **RemoteIPSpoofableXFFLastTrusted·ClipsLongHeaders FAIL**.
  스크립트 실행: `bash backend/scripts/access-log-review.sh --dry-run backend/scripts/testdata/access-log-entries.sample.json 2026-08`
  → `/tmp/access-review-2026-08.md` 4건 정상 생성(2절 401 행에 xff_last·`\|` 이스케이프, 3절 심야 1건 KST 01:30, 4절 trainer7,
  5절 `/v1/body-photos`만 — `/v1/members/{id}`·`/v1/*`는 화이트리스트 밖). `--out` 지정·존재하지 않는 파일(exit 1)·
  미지 옵션(exit 2)·월 형식 오류(exit 2) 확인. `work_log/access-review/`는 생성되지 않음.

## 후속 작업
1. **람 — 서버 배포**(gcloud run deploy, README 배포 절 명령). 배포 순간부터 access 라인이 _Default(30일)에 쌓인다.
2. **람 — 인프라**: `./backend/scripts/setup-access-log.sh` (gcloud 로그인 rizejoy91@gmail.com, rize-218c1). 출력의
   날짜를 `backend/README.md` 접속기록 절 표 "sink 시작일" 칸에 기입. 과금 항목 신설(월 수 센트 추정).
3. **람 — 잠금 결정**: 첫 라인 확인 후 1~2주 운영 → `./backend/scripts/setup-access-log.sh --lock`(yes 확인, 불가역).
   잠근 뒤 README "잠금 상태"를 `적용(YYYY-MM-DD)`으로.
4. **람 — privacy.html 개정**(인프라 적용 후, `admin/public/legal/privacy.html`):
   - :534 `<li><b>접속기록의 보관과 점검</b> — 개인정보처리시스템의 접속기록을 보관하고 위·변조를 방지합니다.</li>`
     → `<li><b>접속기록의 보관과 점검</b> — 개인정보처리시스템의 접속기록을 2년 이상 보관하고 위·변조를 방지하며, 매월 1회 점검합니다.</li>`
   - 개정 이력 표(:632 부근 `<tbody>`)의 v1.0 행 **뒤**에
     `<tr><td>v1.1</td><td>YYYY-MM-DD</td><td>접속기록 보관 체계 적용 — 전용 로그 저장소(서울 리전, 2년) · 월 1회 점검</td></tr>`
     (YYYY-MM-DD = sink 생성일). :275·:499 문구는 유지. 이어 `deploy-hosting.sh`.
5. **람 — 첫 점검**: 다음 달 첫 영업일 `./backend/scripts/access-log-review.sh` → `work_log/access-review/YYYY-MM.md` 6절 판정 기입.
6. ~~work_log/P56-broken-promises-audit.md L9 절 미수정~~ → **P56 :87·후속 3 갱신됨**(L9 제목에 "→ P61에서 수리 · 인프라 적용은 람 실행", 후속 3 취소선 + P61 링크).
7. 선택: 요청 로그(`run.googleapis.com/requests`)도 sink에 포함할지(신뢰 IP 2년 vs 회원 IP 2년 보관 = 최소수집 후퇴) ·
   `_Default` sink에 `?q=` 제외 필터를 걸지(요청 로그 전체가 디버깅에 쓰임). 둘 다 기본은 "안 한다".
8. softDelete·B13(service_staff*.go)과 무관 — 그쪽 파일은 건드리지 않았다.

## 참조
- 설계: `scratchpad/design_L9.md` · 감사: `work_log/P56-broken-promises-audit.md` §L9
- 법령: 개인정보보호위원회고시 제2026-9호 §2·§8 (law.go.kr admRulSeq=2100000281400)
- Cloud Logging: structured-logging · buckets(retention/locked 불가역) · configure_export_v2(같은 프로젝트 버킷 자동 인가, sink 비소급)
- 계약: `docs/API계약_v1.md` v2.30 · 운영: `backend/README.md` 접속기록 절
