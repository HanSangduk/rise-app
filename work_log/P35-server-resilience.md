---
id: P35
title: 서버 견고화 — 죽지 않게, 죽어도 살아나게
status: 완료
domain: backend
created: 2026-08-29
completed: 2026-08-29
---

## 목표

운영 서버(Cloud Run `rize-api`)가 (1) 죽지 않도록 코드·인프라를 하드닝하고, (2) 죽더라도
스스로 복구되도록, (3) 죽은 걸 사람이 즉시 알도록 만든다. P34 사고(리라이트 유실을 15시간+
아무도 모름)가 직접 동기.

## 결정 사항

### D1. 조사 — 관점 다른 3팀 병렬 감사 + 교차검증

① Go 코드 복원력 ② Cloud Run 인프라·감시 ③ 전달 경로·캐시 실패모드. 세 팀이 **서로 다른
층에서 같은 결론에 수렴**: P34류 사고(캐시가 장애를 고착)의 방어가 서버·클라이언트·CDN 세 층
모두 부재했고, 감시는 사용자 경로(Hosting /api)를 안 보고 Cloud Run 원본만 봤다.

교차검증에서 걸러진 것: 팀①이 "http.Client 외부 호출 위험"을 조사했으나 notify 패키지는 빈
디렉터리(외부 HTTP 의존 0) — 위험 자체가 없음 확인. 팀②의 "max-instances 미설정 비용 폭주"
우려는 실측(20 설정됨)으로 기각. 팀③이 "Flutter 앱도 같은 사고 노출" 가설을 조사 — Cloud Run
직결 + dio 무캐시라 **구조적으로 면역**임을 확인(사고 당시 회원 앱이 멀쩡했던 이유).

### D2. 캐시 방어는 3층 전부에 건다 (한 층만으로는 각각 빈틈이 있다)

- **서버**: `writeJSON` 기본 `Cache-Control: no-store`(이미 값이 있으면 존중 — PublicBusiness의
  `public, max-age=300`은 유지). chi 기본 404/405도 계약 포맷 + no-store 핸들러로 교체(테스트가
  이 구멍을 실제로 잡았다).
- **클라이언트**: admin `fetch`에 `cache: "no-store"` — 서버/CDN 설정과 무관하게 브라우저 캐시를
  확정적으로 끊는 유일한 방어선(이미 박힌 캐시는 어떤 서버 수정으로도 못 지운다).
- **CDN**: firebase.json `/api/**` → no-store 헤더 규칙(+ public/business만 max-age=300 예외).
  Hosting이 Cloud Run 리라이트 응답에 이 규칙을 적용하는지는 문서상 불확실 → 배포 후 실측.

### D3. 헬스체크 역할 분리 — liveness와 모니터링은 다른 질문이다

`/healthz` = 프로세스 생존(의존성 안 봄 — DB 블립으로 전 인스턴스 동시 재시작 방지).
`/health` = Firestore 얕은 확인(정책 문서 1읽기, 2초 타임아웃, 15초 캐시) — 종전엔 DB가 완전히
죽어도 uptime check가 초록불이었다. `/api/health` 미러 신설 — 사용자 진입 경로(web.app/api/**)
를 감시하려면 컨테이너에 이 경로가 실재해야 한다(Hosting은 접두사를 안 벗긴다).
GetPolicy는 양쪽 스토어 모두 부재 시 기본 정책 자가 생성 → 신규 센터 오탐 없음(자문자답으로 검증).

### D4. HTML 응답은 "전달 경로 장애"라는 별개 축이다

P34에서 라우팅 유실이 "요청한 데이터를 찾을 수 없어요"(404 폴백)로 표시돼 오진을 유도했다.
admin api.ts가 content-type을 봐서 비JSON이면 전용 문구 + console.error(본문 200자)로 가른다.
2xx HTML(SPA 폴백이 /api를 삼킨 부분 배포)도 같은 방식으로 차단 — 이 케이스는 상태코드만 보는
기존 배포 가드를 통과했었다(팀③ C-1).

### D5. 서버 타임아웃은 chi Timeout이 대신 못 한다

`middleware.Timeout(30s)`은 ctx 데드라인일 뿐 net.Conn 레벨 블록(슬로우 바디·안 읽는 클라이언트·
방치 keep-alive)을 못 끊는다 → `http.Server`에 Read 30s/Write 60s/Idle 120s + 바디 1MiB 상한
(`MaxBytesReader`). shutdown 15s → 8s(Cloud Run SIGKILL 유예 10s보다 짧아야 완주한다).

### D6. 침묵 실패 제거 — 로그 없는 장애는 없는 장애가 아니라 못 찾는 장애다

401 원인(JWKS 페치 실패 등 전면 인증 장애 포함) 로깅 + SDK 에러 원문 응답 노출 차단,
5xx 로그에 reqid/경로/uid(writeErr 시그니처에 r 추가, 88곳 일괄), 권한 강등(enrich 폴백) 로깅,
사진 파기 스윕 실패 로깅 + 3초 자체 예산(읽기 요청의 인질화 방지), 패닉을 구조화 JSON 한 줄
(severity=ERROR) + 계약 포맷 500으로.

### D7. 배포 가드(deploy-hosting.sh) 재강화

배포 전: 리라이트 존재 + **순서**(/api가 ** 앞) 검증. 배포 후: ① Hosting REST로 라이브 릴리스
rewrites 직접 조회(로컬 파일 검증은 대리 지표일 뿐) ② 캐시 우회 스모크 2종(공개 200 JSON 본문
필드 + 무인증 401 JSON — 후자는 캐시 불가 경로라 CDN 잔존 200에 안 속는다) ③ sleep 3 → 폴링
6회. --no-build 시 dist 존재 확인. 커스텀 404.html 추가(UX용 — 캐시 해법 아님을 주석에 명시).

### D8. 의도적 보류 (근거와 함께)

- **/stats 전체 컬렉션 로드(팀① C-2, OOM 경로)**: 실측 7일 에러 0건 + 현재 데이터 규모(단일
  센터 v1)에서 즉시 위험 아님. 집계 쿼리 전환은 store 계약 변경이라 별도 P로. 트리거: 회원
  수백·예약 수천 도달 시.
- **min-instances=1(팀② H1)**: 월 비용이 발생하는 결정이라 사용자 승인 필요.
- **CHECKIN_QR_TOKEN Secret Manager 이전(팀② H3)**: 기동 실패 리스크가 있는 인프라 변경이라
  별도 창에서. 알림 채널 다변화(H2)·전용 SA(M2)도 동일. (probe M1은 D9-2로 해결)
- **Flutter 5xx/네트워크 문구 분리(팀③ M-3)**: 앱 도메인이라 별도 P로.

### D9. 자동 롤백은 "배포 직후"에만 건다 — 운영 중 장애에는 걸지 않는다

같은 "자동 롤백"이라도 두 상황의 위험이 정반대라 갈랐다.

- **배포 직후 검증 실패 → 자동 롤백(적용함, deploy-hosting.sh `auto_rollback`)**. 상황이
  좁고 확실하다: 사람이 방금 배포했고 그게 잘못됐다. 되돌리는 건 방금 올린 것의 취소라
  잃는 게 없다. 사람을 기다리면 그 시간만큼 사용자가 깨진 사이트를 본다 — 8/27엔 15시간이었다.
  Hosting REST로 직전 릴리스를 다시 릴리스한다(4단계 config 검증·5단계 스모크 양쪽에서 발동).
- **운영 중 헬스체크 실패 → 자동 롤백(안 함)**. 원인이 열려 있다(DB 블립·일시 부하·외부 장애).
  멀쩡한 최신 배포가 되돌려지고 최악엔 롤백↔재배포가 반복된다. 여기선 알림만 보낸다.

### D9-2. Cloud Run 자가 복구의 실제 경계 (setup-selfheal.sh)

이미 자동인 것: **크래시 → 자동 재기동**, **새 리비전 기동 실패 → 트래픽 미전환**(잘못된 백엔드
배포는 무해하게 끝난다). 비어 있던 구멍: **살아는 있으나 응답 못 하는 hang** — 크래시가 아니라
Cloud Run이 모르고, 포트가 열려 있어 기본 TCP startup 체크도 통과한다. liveness probe를
`/healthz`에 건다(30s × 3회 = 90초 이상 불능일 때만 재시작). **`/health`가 아닌 이유**: 의존성을
보는 쪽에 걸면 Firestore 블립에 전 인스턴스가 동시 재시작해 순간 장애가 전면 장애로 증폭된다 —
재시작으로 고쳐지는 문제만 재시작한다.

### D9-3. 사람이 끝내 필요한 자리 (없앨 수 없는 것)

이미 라이브인 상태에서 **시간이 지나 망가진 경우**(외부 의존 변화, 설정 만료 등)는 원인이
열려 있어 기계가 판단할 수 없다. 여기는 알림 + 런북 + 폰 3탭으로 간다(D10). Claude는 세션이
열려 있을 때만 존재하므로 상시 감시자가 될 수 없다 — 자동화는 전부 클라우드 쪽에 심었다.

### D10. 런북은 알림 메일 본문에 산다

폰으로 알림을 받은 사람이 맥 없이 판단·복구할 수 있어야 감시가 의미를 갖는다. 두 알림 모두
documentation에 (a) 어느 층이 끊겼는지 가르는 분기 (b) 탭 가능한 롤백 콘솔 링크 (c) 복구 확인
URL을 담는다. 백엔드 알림은 "**먼저 5~10분 기다려라**(자동 복구되는 경우)"를 1번으로 둔다 —
자동 복구를 모르면 멀쩡히 낫는 중인 서버를 사람이 건드려 더 망친다.


### D11. 2차 적대 리뷰(3팀) — 내가 만든 결함을 찾기 위한 재검토

1차 실행 후 **새 눈 3팀**(Go 백엔드 / 복구 스크립트 SRE / 클라이언트+3층 합성)을 다시 투입했다.
견고화 코드 자체가 틀리면 "방어가 없는 것보다 나쁘다"(거짓 안심)는 게 재검토의 근거다.
실제로 **내가 1차에서 넣은 결함 7건**이 나왔고, 그중 하나는 보안 결함이었다.

| # | 내가 만든 결함 | 왜 위험한가 | 조치 |
|---|---|---|---|
| 1 | `MaxBytesReader(nil,…)` + `defer r.Body.Close()` | 상한 초과 시 "커넥션 재사용 금지" 신호가 사라지고 미소비 바디가 소켓에 남는다 → **요청 스머글링/응답 desync**(GFE가 커넥션을 풀링하는 Cloud Run 뒤에서 특히) | `decodeJSON(w,r,v)`로 시그니처 변경(26곳), Close 제거 |
| 2 | `/health`가 요청 ctx로 DB 확인 | 익명 호출자가 붙었다 끊기만 해도 그 취소가 15초 캐시돼 **DB 정상인데 503+거짓 알림**. 원격 트리거 가능 | `context.Background()` 파생으로 분리 |
| 3 | 리스너 에러 시 종료코드 0 | 포트 충돌 등으로 한 번도 요청을 못 받고 죽는데 Cloud Run이 정상 종료로 읽어 **배포 실패가 크래시 루프로 안 드러난다** | defer 수행 후 `os.Exit(1)` |
| 4 | `recoverJSON`이 시작된 응답 뒤에 JSON 덧붙임 | 200 본문 뒤 `{"error":…}`가 이어붙어 클라이언트가 파싱에서 깨진다(요청 바디에선 우리가 금지하는 그 형태) | `statusWriter`로 기록 여부 추적, 이미 시작됐으면 `ErrAbortHandler` |
| 5 | 401 본문에 영문/dev 헤더명 노출 | 두 클라이언트가 서버 error 문자열을 폴백보다 **우선 표시**한다 → `unauthorized`, `X-Dev-Uid…`가 사용자 화면에 뜬다 | 본문은 항상 한국어, 구분은 기계 판독 `code` 필드로 |
| 6 | 합성 502가 재시도 대상 | 전달 경로 장애는 배포 전까지 100% 결정적인데 4회 재시도 → 대시보드 9쿼리 × 4 = **36요청 + 7초 지연**. 빠른 진단이라는 목적과 정반대 | `ApiError.transport` 플래그로 재시도 제외 |
| 7 | 자동 롤백이 "확인 불가"를 "고장"으로 취급 | Hosting REST 403/타임아웃 하나로 **멀쩡한 배포를 되돌리고** "정상 동작한다"고 단언 | 정상/고장/확인불가 3상태로 분리, 확인불가에선 롤백 금지 |

### D12. "검증이 실패를 관측할 수 있는가"를 검증한다

가장 값어치 있는 발견은 결함이 아니라 **검증 자체가 무의미했던 자리**들이었다.

- **자가복구 스크립트의 5초 검증**: probe가 100% 잘못돼도 첫 재시작까지 `initialDelay(10)+period(30)×threshold(3)` ≈ 100초다. `sleep 5` 후 curl 한 번은 **어떤 오설정에서도 통과**한다. → 4분 관측 + 기동 로그 반복 횟수 계수 + 실패 시 직전 리비전으로 자동 트래픽 롤백(`PREV_REV`를 적용 **전에** 확보)으로 교체. `httpGet.port` 하드코딩도 제거(생략하면 컨테이너 포트를 따른다 — 누가 `--port`를 바꾸면 전 인스턴스를 죽이던 자리).
- **런북 패치의 성공 보고**: `curl -s` + 상태 미확인이라 403이어도 "✓ 갱신"을 찍었다. → 상태코드 확인 + **보낸 내용과 되읽은 내용 대조**. 처음엔 "길이 100자 초과"로 검사했는데 드라이런에서 **옛 런북(128자)이 통과**해 다시 고쳤다.
- **uptime check 멱등 판정이 host만 비교**: 같은 도메인의 다른 체크(루트 `/` 감시 등)를 자기 것으로 오인하면 `/api/health`는 아무도 안 보는데 알림만 초록불이 된다 — 8/27 사고(루트 200, /api만 404)에서 정확히 무력한 구성. → host+path 동시 비교, 조회 응답의 `error`를 빈 목록으로 오독하던 것도 차단.
- **내 뮤테이션 도구의 오판정**: 치환이 문법 오류를 만들어 빌드가 깨진 것을 "테스트 통과=생존"으로 셌다. 빌드 성공 여부를 먼저 확인하도록 고친 뒤 재실행해 실제 kill을 확인했다.

### D13. 테스트가 "통과만 하는" 자리를 뮤테이션으로 걷어냈다

`/health` 취소 오염 테스트는 처음에 **버그를 되살려도 통과**했다 — Memory 스토어의 `GetPolicy`가
`_ context.Context`라 취소를 무시하기 때문이다(Firestore는 존중하므로 **운영에서만** 터진다).
ctx를 존중하는 테스트 스토어를 만들어 kill을 확인했다. 같은 방식으로 리뷰가 지적한 갭 3곳
(recoverJSON 라우터 배선 / 405 / 헬스 캐시 TTL)에 테스트를 추가하고 각각 뮤테이션 kill을 확인했다.
`writeJSON`의 4xx no-store 강제는 라우터 경유로는 잡히지 않아(현재 캐시 헤더를 세운 뒤 에러로
빠지는 핸들러가 없다) `writeJSON`을 직접 치는 테스트로 고정했다 — 미래 코드를 위한 방어다.

## 진행 단계

- [x] 1단계: 병렬 조사(3팀) 완료
- [x] 2단계: 교차검증 — 수렴/기각/면역 확인, CRITICAL→LOW 확정
- [x] 3단계 실행: 백엔드 코드(캐시·타임아웃·헬스·로깅·패닉) + 계약 테스트 6종
- [x] 3단계 실행: admin(fetch no-store·HTML 감지·재시도 정책) 빌드 통과
- [x] 3단계 실행: firebase.json /api 헤더 + 404.html + deploy-hosting.sh 강화
- [x] 4단계: Cloud Run 배포(rize-api-00022-gxq) + 실측 — no-store가 직접·Hosting 경유 모두
      확인, /api/health 운영 Firestore 체크 200, 무인증 401 no-store 확인
- [x] 4단계: Hosting 배포 완료(09:01) — 라이브 릴리스에 headers 4규칙(/api/** no-store 포함)
      + 리라이트 순서 정상 반영 확인
- [x] 4단계: 사용자 경로 uptime check(`rize-hosting-api-health-B52Ggu8e9BI`) + 알림 정책
      생성 완료. 알림 런북에 **폰 복구 절차**(Hosting/Cloud Run 롤백 콘솔 링크) 삽입 —
      알림 메일만 보고 맥 없이 복구 판단이 가능해야 의미가 있다
- [x] 5단계: 자동화 보강 — 배포 검증 실패 시 자동 롤백(deploy-hosting.sh), Cloud Run
      liveness probe 스크립트(setup-selfheal.sh), 백엔드 알림 런북 채움
- [ ] 5단계: 사용자 실행 대기 — `./setup-monitoring.sh`(백엔드 런북) · `./setup-selfheal.sh`(probe)
- [x] 4단계: 회귀 확인(go test 전체 그린 + admin tsc 빌드) + 최종 보고
- [x] 7단계 배포·라이브 검증(2026-08-29): Cloud Run `rize-api-00023-nlk` 100% 서빙 ·
      Hosting 재배포(가드 3단계 전부 통과) · 알림 런북 양쪽 반영. 라이브 실측으로
      **새 코드가 실제로 서비스 중임을 확인**: `/api/v1/me` 무인증이 한국어 문구 +
      `code:"missing_token"`(구버전은 영문 `unauthorized`) · `/api/health` 200 no-store ·
      두 알림 런북 664·745자에 롤백 링크·폰 복구 절차 포함
- [x] 6단계: 2차 적대 리뷰 3팀 + 자문자답 — 결함 7건 수정, 검증 무의미 지점 4곳 교체,
      테스트 갭 4곳 보강(전부 뮤테이션 kill 확인), go test 전체 그린 + admin 빌드 통과

## 변경 파일

- backend/internal/api/util.go — writeJSON no-store 기본값·바디 1MiB 상한·writeErr(w,r,err) 로깅
- backend/internal/api/auth.go — 401 로깅·원문 노출 차단·권한 강등 로깅
- backend/internal/api/health.go (신규) — /health 의존성 체크 + recoverJSON 미들웨어
- backend/internal/api/router.go — recoverJSON·/health·/api/health·계약 포맷 404/405
- backend/internal/api/handlers_*.go — writeErr 호출 88곳 시그니처 반영
- backend/internal/api/service.go — 사진 파기 스윕 로깅 + 3초 예산
- backend/internal/api/resilience_test.go (신규) — 계약 테스트 6종
- backend/cmd/server/main.go — 서버 타임아웃·shutdown 8s·리스너 에러 공통 종료 경로
- admin/src/lib/api.ts — cache no-store·비JSON 감지(에러/2xx 양쪽)
- admin/src/main.tsx — 재시도 정책(4xx 제외 3회 백오프)·refetchOnWindowFocus
- admin/public/404.html (신규)
- firebase.json — /api/** no-store + public/business max-age=300 헤더 규칙
- deploy-hosting.sh — 순서 검증·릴리스 REST 검증·캐시 우회 스모크 2종·폴링·**검증 실패 시 자동 롤백**
- setup-monitoring.sh (신규) — 사용자 경로 uptime check + 알림 정책 + 양쪽 알림에 폰 복구 런북
- setup-selfheal.sh (신규) — Cloud Run liveness probe(hang 자동 재시작)

## 검증

- `go test ./...` 전체 그린(신규 resilience 테스트 6종 포함 — 계약 404가 no-store 없이 나가는
  실구멍을 테스트가 잡아 라우터 수정으로 이어짐). admin `npm run build`(tsc) 통과.
- Cloud Run 신규 리비전(00022-gxq) 실측: run.app `/health` 200 + `cache-control: no-store`,
  `/v1/me` 무인증 401 + no-store, Hosting 경유 `web.app/api/health` 200 + no-store(x-cache MISS).
- 라이브 실측(배포 후): `web.app/api/v1/public/business` 200 JSON `max-age=300`(의도적 예외 유지),
  `/api/v1/me` 401 JSON `no-store`, `/api/health` 200 JSON `no-store`. 라이브 릴리스 config에
  rewrites 2·headers 4 정상.
- **deploy-hosting.sh 첫 실행에서 버그 발견·수정**: `curl | python3 - <<EOF`는 heredoc이 stdin을
  덮어써 파이프가 사라진다(JSONDecodeError). 배포는 성공했으나 검증이 못 돌았다 — 응답을
  임시파일로 받고 `python3 -c`로 파싱하도록 교체. 검증 스크립트 자신이 조용히 실패하면
  가드가 없는 것과 같으므로, 이 계열(파이프+heredoc)은 다시 쓰지 않는다.
- 자문자답으로 닫은 것: ① no-store 기본값이 PublicBusiness의 max-age=300을 덮지 않음(기존 헤더
  존중 + 테스트 고정) ② /health가 신규 센터에서 오탐하지 않음(GetPolicy 자가 생성) ③ 1MiB 바디
  상한이 실제 최대 페이로드를 막지 않음(서명도 바디 없는 요청 — 확인) ④ refetchOnWindowFocus
  요청 폭증 없음(staleTime 15s 흡수, useJoinRequests 선례) ⑤ 401 문구 일반화가 클라이언트를
  깨지 않음(admin·앱 모두 status로 분기, dev 안내 sentinel은 유지).

## 후속 작업

- **`./setup-selfheal.sh` 미실행** — liveness probe(hang 자동 재시작)만 아직 적용 전이다.
  4분 관측 + 실패 시 자동 트래픽 롤백이 들어 있어 안전하게 돌릴 수 있다.
- 알림 채널 다변화(현재 Gmail 1개) — 모바일 푸시 추가 시 setup-monitoring.sh의 CHANNEL에
  채널 ID를 추가하고 재실행하면 런북까지 함께 붙는다
- /stats 집계 쿼리 전환(트리거: 데이터 규모 성장) — D8
- min-instances=1 여부 사용자 결정 — 월 비용 안내 후
- CHECKIN_QR_TOKEN → Secret Manager, 전용 서비스 계정(최소 권한)
- Flutter: 5xx/네트워크 문구 분리·GET 재시도 인터셉터·sendTimeout

## 참조

- [P34 — Hosting 리라이트 유실 사고](P34-hosting-rewrite-guard.md)
- [P07 — 호스팅·uptime 알림](P07-staff-onboarding-hosting.md)
- [P12 — 인프라 하드닝(PITR·백업)](P12-audit-sweep.md)
