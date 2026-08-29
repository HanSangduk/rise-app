---
id: P34
title: 운영 Hosting 리라이트 유실 사고 — 진단 + 배포 가드
status: 완료
domain: cross
created: 2026-08-29
completed: 2026-08-29
---

## 목표

운영 어드민(`rize-218c1.web.app`)에서 로그인 포함 **모든 API 호출이 404**로 떨어지는 사고의
원인 규명 + 재발 방지. "로그인이 안 된다"로 보고됐지만 실체는 인증 문제가 아니라 라우팅 유실.

## 결정 사항

### D1. 원인 — 2026-08-27 23:11 KST 배포분의 hosting config가 통째로 빈 채 라이브에 올라감

Hosting Releases API로 릴리스 이력을 대조해 확정:

| 릴리스 | config |
|---|---|
| 8/27 08:10 KST (`72c43ffc`) | `/api/** → run: rize-api` + `** → /index.html` **정상** |
| 8/27 23:11 KST (`13d96f90`, 현재 라이브) | `config: {}` — **리라이트 0개** |

- Cloud Run `rize-api` 자체는 정상(직접 호출 `/health` 200, `/v1/me` 무인증 401 — 올바른 거부).
- 로컬 [firebase.json](../firebase.json)에는 리라이트가 멀쩡히 있음(8/23 이후 무변경) →
  마지막 배포가 이 파일이 안 읽히는 위치/방식으로 실행된 것으로 추정(정확한 실행 경로는 미상).
- 파생 증상: SPA 폴백도 빠져 딥링크 새로고침도 404.

### D2. 재발 방지 — 배포 스크립트에 사전·사후 검증을 내장 ([deploy-hosting.sh](../deploy-hosting.sh))

사고의 구멍 셋을 각각 막는다:
1. `cd "$(dirname "$0")"` — 어디서 실행하든 항상 ptdesk 루트의 firebase.json으로 배포
2. **배포 전**: firebase.json에 `/api/**→rize-api` 리라이트 + SPA 폴백이 있는지 파싱 검증, 없으면 중단
3. **배포 후**: 라이브 `GET /api/v1/public/business`(무인증 공개 라우트)가 200인지 확인 —
   리라이트가 빠지면 Hosting 404 HTML이 오므로 이 한 번의 curl로 판별된다. 실패 시 콘솔 롤백 안내.

부수: `--project rize-218c1` 명시(alias 오독 차단), CLI 로그아웃 상태 사전 감지(오늘 사용자가
겪은 `Failed to get Firebase project` — 원인은 firebase CLI `No authorized accounts`),
`--no-build` 옵션.

### D3. 스모크 경로는 `/api/v1/public/business`

`/api/healthz`는 Go 라우터에 등록돼 있지 않아(등록된 건 `/healthz`·`/health`·`/api/v1/**`)
리라이트가 정상이어도 404가 난다 — 검증 경로로 쓰면 오탐. 무인증 공개 라우트 중
router.go에 실재하는 `/api/v1/public/business`를 쓴다(직접 호출로 200 확인 완료).

## 진행 단계

- [x] 운영 404 재현·원인 격리(Hosting 404 HTML ↔ 백엔드 JSON 구별, Cloud Run 직접 호출로 백엔드 무혐의 입증)
- [x] Releases API로 리라이트 유실 릴리스 특정
- [x] deploy-hosting.sh 작성(사전 검증 + 빌드 + 배포 + 사후 스모크)
- [x] 스크립트 문법·사전 검증 로직 실행 확인
- [x] 사용자 `firebase login` 후 `./deploy-hosting.sh` 실행 — 배포 성공, 라이브 스모크 200

## 변경 파일

- `deploy-hosting.sh` (신규) — 검증 내장 Hosting 배포 스크립트

## 검증

- `bash -n` 통과, 사전 검증 파서가 현재 firebase.json에 대해 pass 반환 확인.
- 실배포(8/29): `./deploy-hosting.sh` 전 단계 통과 — 사전 검증 ✓ → admin 빌드 ✓ → release ✓ →
  라이브 `/api/v1/public/business` 200 ✓. 추가로 `/api/v1/me` 무인증 401 JSON(백엔드 도달 확인),
  딥링크 `/members` 200(SPA 폴백 복원) 확인. 배포 에러의 최종 원인도 확정: firebase CLI 자체
  로그인 부재 → 5월자 타계정 ADC 폴백(rize 프로젝트 미노출). `firebase login`으로 해소.

## 후속 작업

- 배포 직후 라이브에서 실로그인 1회 확인(데모 아닌 Firebase 이메일 계정).
- (선택) P07의 uptime 알림이 `/api` 경로를 감시하는지 점검 — 이번 사고를 15시간+ 동안 못 잡았다.
  감시 대상이 `/`(정적 200)라면 `/api/v1/public/business`로 바꿔야 같은 유형을 즉시 잡는다.

## 참조

- [P07 — 어드민 호스팅 + `/api` 리라이트 도입](P07-staff-onboarding-hosting.md)
- backend/internal/api/router.go:116-134 — `/api/v1` 미러 및 접두사 미제거 근거 주석
