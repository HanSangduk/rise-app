---
id: P35
title: 서버 견고화 — 죽지 않게, 죽어도 살아나게
status: 진행 중
domain: backend
created: 2026-08-29
completed:
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
  별도 창에서. 알림 채널 다변화(H2)·probe(M1)·전용 SA(M2)도 동일.
- **Flutter 5xx/네트워크 문구 분리(팀③ M-3)**: 앱 도메인이라 별도 P로.

## 진행 단계

- [x] 1단계: 병렬 조사(3팀) 완료
- [x] 2단계: 교차검증 — 수렴/기각/면역 확인, CRITICAL→LOW 확정
- [x] 3단계 실행: 백엔드 코드(캐시·타임아웃·헬스·로깅·패닉) + 계약 테스트 6종
- [x] 3단계 실행: admin(fetch no-store·HTML 감지·재시도 정책) 빌드 통과
- [x] 3단계 실행: firebase.json /api 헤더 + 404.html + deploy-hosting.sh 강화
- [x] 4단계: Cloud Run 배포(rize-api-00022-gxq) + 실측 — no-store가 직접·Hosting 경유 모두
      확인, /api/health 운영 Firestore 체크 200, 무인증 401 no-store 확인
- [ ] 4단계: Hosting 배포(admin no-store 클라이언트 + /api 헤더 규칙 + 404.html) — **권한 정책상
      사용자 실행 필요**: `cd ptdesk && ./deploy-hosting.sh`. 배포 후 CDN 헤더 불확실성 2건
      (Hosting headers가 리라이트 응답·404에 적용되는지) 실측으로 닫을 것
- [ ] 4단계: 사용자 경로 uptime check + 알림 — **사용자 실행 필요**: `./setup-monitoring.sh`
- [x] 4단계: 회귀 확인(go test 전체 그린 + admin tsc 빌드) + 최종 보고

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
- deploy-hosting.sh — 순서 검증·릴리스 REST 검증·캐시 우회 스모크 2종·폴링

## 검증

- `go test ./...` 전체 그린(신규 resilience 테스트 6종 포함 — 계약 404가 no-store 없이 나가는
  실구멍을 테스트가 잡아 라우터 수정으로 이어짐). admin `npm run build`(tsc) 통과.
- Cloud Run 신규 리비전(00022-gxq) 실측: run.app `/health` 200 + `cache-control: no-store`,
  `/v1/me` 무인증 401 + no-store, Hosting 경유 `web.app/api/health` 200 + no-store(x-cache MISS).
- 자문자답으로 닫은 것: ① no-store 기본값이 PublicBusiness의 max-age=300을 덮지 않음(기존 헤더
  존중 + 테스트 고정) ② /health가 신규 센터에서 오탐하지 않음(GetPolicy 자가 생성) ③ 1MiB 바디
  상한이 실제 최대 페이로드를 막지 않음(서명도 바디 없는 요청 — 확인) ④ refetchOnWindowFocus
  요청 폭증 없음(staleTime 15s 흡수, useJoinRequests 선례) ⑤ 401 문구 일반화가 클라이언트를
  깨지 않음(admin·앱 모두 status로 분기, dev 안내 sentinel은 유지).

## 후속 작업

- /stats 집계 쿼리 전환(트리거: 데이터 규모 성장) — D8
- min-instances=1 여부 사용자 결정 — 월 비용 안내 후
- CHECKIN_QR_TOKEN → Secret Manager, 알림 채널 다변화, liveness/startup probe, 전용 SA
- Flutter: 5xx/네트워크 문구 분리·GET 재시도 인터셉터·sendTimeout

## 참조

- [P34 — Hosting 리라이트 유실 사고](P34-hosting-rewrite-guard.md)
- [P07 — 호스팅·uptime 알림](P07-staff-onboarding-hosting.md)
- [P12 — 인프라 하드닝(PITR·백업)](P12-audit-sweep.md)
