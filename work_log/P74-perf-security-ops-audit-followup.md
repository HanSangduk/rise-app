---
id: P74
title: 성능·보안·운영 감사 후속(계약 v2.38) — 맥 첫 실검증 · 3팀 감사 · 수리 15건 · 의존성 보안 갱신 · 변이 검사
status: 완료
domain: cross
created: 2026-09-26
completed: 2026-10-16
---

# P74 — "그럼 완성인가"에 대한 답: 성능·보안·운영·의존성 축

## 목표 (람 요청)
- 2026-09-26: P73(정합·UX)이 끝난 뒤 한 번도 감사 축이 아니었던 **성능·보안·운영·의존성**을 돈다
  (클라우드 세션이 수행 — 계약 `docs/API계약_v1.md` v2.38 절이 그 결과물).
- 2026-10-15 람: "지금 변경된 파일들 확인하고 커밋 푸시 안 된 부분들 확인 후 작업 — `/ram-verify-loop`로 완성도 높이기".

## 착수 시점 상태 (2026-10-15 실측)
- 브랜치 `feat/contract-esign-admin-usability` = `origin` (앞섬 0 · 뒤짐 0). **푸시 안 된 커밋은 없다** —
  남은 것은 전부 미커밋(착수 때 159건: P71·P72·P73·P74 작업분).
- P71~P73: 2026-09-26 15:13 맥 3회차 검증 전부 그린(flutter 1532 · 변이 14/14). 문서·인덱스 완비.
- **P74: 맥에서 한 번도 실행되지 않았다.** 클라우드 VM(go·flutter 없음)에서 15:13 이후 작성 →
  - 이 work_log 파일이 없었다(계약 v2.38·`backend/README.md`·`ratelimit.go`가 "work_log P74"를 인용하는데 대상 부재).
  - 의존성 스캔(`docs/temp/p74_scan.sh`)·검증·변이 묶음(`p74_all.command`)을 만들어 두었지만 실행 흔적이 없었다.
  - `docs/temp/p73_mutate.sh`의 P74 변이 18건(⑬~㉚)이 **`exit 0` 뒤에** 놓여 한 번도 돌 수 없는 죽은 코드였다.
  - 맥 트리는 클라우드 최종 스냅샷(`p73_logs/r3_cloud_md5_r2.txt`, 107파일)과 md5 **전수 일치**.
- 같은 트리에서 다른 세션(ptdesk-82)이 **P75**(iOS 전화 인증 reCAPTCHA 복귀)를 동시에 진행 — 파일 범위를
  메시지로 나눴다(아래 "동시 세션").

## P74 범위 (계약 v2.38에서 재구성)
- **백엔드**: ① 요청 빈도 제한 429 `rate_limited`(`ratelimit.go` — 회원 uid/공개 IP 토큰 버킷, 스태프 면제,
  키 표 1만 상한 fail-open) · ② `POST /v1/body-photos` `storage_path` 소유 검증 400(`domain.BodyPhotoPathOwnedBy`) ·
  ③ 접속기록이 429를 거부로 기록 · ④ 읽기 범위 축소(`ListHwChecksByMember`·`ListPaymentsByPass/ByMember`) ·
  `GET /v1/members` 병렬화(`forEachParallel` — 취소·상한·첫 오류·패닉 격리).
- **어드민**: 9개 화면 `React.lazy` · 로그아웃 시 체형사진 blob 캐시 비움 · 회원 목록 `useMemo`.
- **앱**: 홈·마이·기록 탭 독립 요청 동시 실행(`Settled`) · 수업 기록 10건 + 더 보기 20건 · 체형사진 캐시 LRU 40장.
- **배포·규칙**: `firebase.json` 보안 헤더 5종 + `/api/v1/public/center` 캐시 · `storage.rules` contentType 래스터 3종.

## 자 (손대기 전에 잰 것 — 2026-10-15 23:17, 맥, 같은 트리)
| 단계 | 착수(base) | 마지막 회차 |
|---|---|---|
| `go vet ./...` | 0 | 0 |
| `go test ./... -count=1` | **FAIL 1**(`TestForEachParallelEmptyAndParentCancel`) · 721 pass | **733 pass** · 0 fail |
| `go test -race` | 그린(같은 시험이 이 회차엔 통과 — 비결정) | 그린 |
| Firestore 에뮬레이터 컨포먼스 | 38 pass | **39 pass**(새 사례 1) |
| govulncheck(프로젝트 툴체인 go1.26.0) | **41건**(모듈 3 + 표준 라이브러리) | **4건**(전부 chi — 아래 "안 한 것") |
| admin `npm run build` | 그린 · 첫 진입 515.76 kB | 그린 · 516.41 kB(+0.65 — 새로고침 처리기·계정 전환) |
| `flutter analyze` | 0 issues | 0 issues |
| `flutter test` | **1542 pass** | **1561 pass**(이쪽 +12 · P75 세션 +7) |
| `TZ=America/New_York` 시간대 시험 | 29 pass | 29 pass |
| iOS 빌드 가드 하네스 | 24/24 | 33/33(이쪽 4칸 + P75 5칸) |
| 어드민 사진 캐시 하네스(신설) | — | 5/5 |
| **변이 검사**(이름 기준 · 복사본) | P74 18건은 한 번도 실행된 적 없음 | **69/69 KILLED** |

## 조사 (읽기 전용 3팀 · sonnet · 파일:줄 근거 · [근거]/[추측])
백엔드 · 앱 · 어드민+배포 설정 — **세 팀 모두 CRITICAL·HIGH 0건**. MEDIUM 5 · LOW 다수. 대표가 전건을 직접 열어
확인했고, 두 건은 운영 실측으로 판정했다(아래 D9·정정).

## 결정 사항 (수리 — 각 건 "고치기 전 빨강 → 수리 → 같은 자로 초록")

### D1 (백엔드) `forEachParallel`이 이미 취소된 ctx로도 최대 limit개를 시작했다 — 실제 실행이 잡은 첫 결함
- 40회 반복 **20회 실패**(1회 실행 14 · 2회 실행 6 — 이론치 50%). Go `select`는 준비된 갈래 중 무작위라 빈 자리와
  취소가 함께 준비되면 절반은 자리를 집는다. 주석("남은 항목은 시작하지 않는다")을 코드가 보장하지 않았다.
- 수정: 자리를 집은 뒤 `gctx.Err()` 재확인. 시험은 한 번의 `go test`로 확정되도록 200판을 돈다. 200회 반복 0 실패.

### D2 (백엔드 MEDIUM) 통계 HW 완료율이 매 호출 센터 hwChecks **전량**을 읽고, 실패하면 조용히 0%
- 감사 실측(HEAD vs P74): 빈 센터 0→1 전량 · 배정 없는 트레이너 scope=me 0→1 전량 · 트레이너 2→1 전량. 그 컬렉션은
  회원×날짜로 끝없이 자라고 어드민은 데스크 뮤테이션마다 stats를 다시 부른다. 주입 실패 → hw_rate 0.5→0(무오류).
- 수정: **활성 배정의 대상 회원만, 회원당 1번**(중복 제거·동시 8). 활성 배정이 없으면 0회. 실패는 그 회원만 분자에서
  빠짐(HEAD와 같은 단위) + 로그. `TestStatsReadsHwChecksOnce`(1차 설계 고정)를 새 계약 시험 2개로 교체 — 스크래치
  복사본에 1차 구현을 되돌려 넣으면 새 시험이 전부 빨갛다(전량 1회·배정 없는 트레이너가 읽음 등).

### D3 (앱 MEDIUM) 체형사진 캐시 상한 시험이 실제 배선을 재지 않았다
- 시험이 시험 전용 static(`debugPut`·`debugPeek`)만 불러, `peek`·`load`가 캐시를 우회해도 초록이었다.
- 수정: Storage 가짜(`getData`만)로 실제 `peek`·`load`를 잰다(히트는 다시 받지 않음 · 받은 바이트가 상한을 따름).
  `debugPeek` 삭제(쓰는 곳 0).

### D4 (앱·어드민 — 같은 결함 클래스 "세션 경계를 넘는 캐시") 받는 **도중** 로그아웃하면 사진이 다음 세션 캐시에 남았다
- 앱 `body_photo_loader.dart`: `await getData` 뒤 무조건 `_put` → 세대 표식(`_epoch`, clear 때 증가)으로 건너뜀.
  시험 "받는 도중 세션이 끝나면…"이 수리 전 `['members/A/body/a.jpg']`로 빨강 → 수리 후 초록.
- 어드민 `bodyPhotoBlob.ts`: 같은 틈 + blob URL을 만들면 아무도 revoke하지 않음 → 세대가 바뀌었으면 URL을 만들지
  않고 버림. 같은 김에 **30장 상한**(최근 사용 순, 밀려난 URL revoke) · 같은 사진 동시 두 번 받기 시 여분 URL 누수 차단.
  어드민엔 시험 러너가 없어 esbuild로 모듈만 묶는 노드 하네스(`docs/temp/p74_admin_blob_check.mjs`, 5칸)를 만들었다.
- 형제 분류: P73 C2(staffMap) 수리됨 · 앱 Flutter `ImageCache`는 키가 `Uint8List` 신원이라 **다음 사람에게 그려질 수
  없다**(메모리 잔류만) → 안 고침(아래) · 어드민 react-query 캐시 → D5.

### D5 (어드민 LOW) 다른 탭에서 **다른 계정으로 곧장** 로그인하면 이 탭의 캐시가 남았다
- Firebase가 탭 사이에 uid를 동기화하면 이 탭은 `null`을 거치지 않고 새 사용자를 받는다 → 로그아웃 정리가 안 돌아
  이전 계정의 목록(staleTime 60초)·blob이 새 계정 화면에 보인다(쿼리 키에 uid·센터 없음).
- 수정: 직전 uid를 기억해 바뀌면 `setMe(null)` + `qc.clear()` + blob 비움. **시험 없음**(어드민 러너 부재) — 반박 리뷰로 대신.

### D6 (어드민 MEDIUM) 배포 직후 열려 있던 탭이 새 화면 조각을 못 받는다(P74 코드 분할이 만든 새 실패 부류)
- 옛 해시 청크는 새 배포에 없고 Hosting은 없는 경로에 index.html을 준다 → 오류 카드 + 수동 새로고침.
- **운영 실측 2026-10-16**: `/index.html`은 `no-cache`인데 사용자가 여는 `/`는 Hosting 기본 `max-age=3600`.
- 수정: `firebase.json`에 `/` no-cache · `main.tsx`에 `vite:preloadError` → 1회 자동 새로고침(30초 안 재발이면 오류 카드,
  저장소가 막힌 환경도 카드). 산출물(`dist/assets/index-*.js`)에 처리기 문자열이 든 것 확인. 실브라우저 확인 못 함.

### D7 (앱 LOW) 패스별 원장을 **상한 없이** 동시에 불렀다
- P74가 직렬 → 무제한 동시로 바꿨다. 패스는 재등록마다 하나씩 쌓인다(2년이면 20~30개) — 연결·TLS가 그 수만큼 동시에.
- 수정: `settleEach(items, call, limit: 4)` 공용화(입력 순서 보존·실패는 그 칸만). 시험: 단위 5칸 + 마이 탭 배선
  (패스 10개 → 원장 10번, 동시 최대 정확히 4 — 상한이 빠지면 10, 직렬이면 1).

### D8 (백엔드 LOW→수리) 체형사진 **파기**는 생성 검사를 거치지 않은 옛 레코드의 경로를 그대로 지웠다
- ② 생성 검사(400)는 새 레코드만 막는다. v2.38 이전 레코드가 남의 경로(`staff/photos/…` — 사진 URL로 노출되는 이름)를
  가리키면 회원 즉시 삭제·30일 유예·**탈퇴 파기**가 남의 파일을 지우는 원시 연산이 된다(감사: 그런 레코드의 존재 증거는 없음).
- 수정: `ownedBodyPhotoPath` — 회원 폴더 안일 때만 파일 삭제, 밖이면 메타만 지우고 로그. 탈퇴 경로도 같은 규칙.

### D9 시험 고정(감사가 "되돌려도 초록"으로 찾은 자리) — 백엔드 6 · 앱 4 · 하네스 1
- 빈도 제한 배선 전수: 가입 3경로 · 공개 center 두 마운트 · 같은 IP 뒤 회원 둘(uid 키) · 포트 떼기.
- 읽기 범위 3곳: 계약가 상한 · 계약서 결제방법(다른 패스 결제가 섞이면 법정 기재 사항이 "카드, 현금"으로 틀린다) · 탈퇴 보존 집계.
- 회원 목록: 저장 잔여를 일부러 999로 틀어 원장 재계산(hydrate) 고정 · 동시성 "겹치되 상한 이하".
- 스토어 적합성 `ListHwChecksByMember`(m1/m10 접두사 경계·센터 경계·빈 슬라이스) — Memory + **에뮬레이터 39 pass**.
- 앱: 더 보기 정확히 20건씩(35건 10→30→35) · 기록 탭 "늦은 실패 흡수"(마이 탭에만 있던 것) · 펼침 행 버튼 의미.
- iOS 빌드 가드: P73이 넣은 "pbxproj 버전 리터럴 금지" 검사에 하네스 칸이 없었다 → 4칸(실제 Runner pbxproj 포함).

### D10 의존성(govulncheck — P74 스캔을 맥에서 처음 돌림)
- 프로젝트 툴체인(go1.26.0) 기준 **41건**: 표준 라이브러리(net/http·crypto/tls·html/template·net/url 등) +
  x/net HTTP/2 5건 · grpc 1건 · otel 1건 · chi 4건.
- 갱신(2026-10-16 기준 최신 stable, 공개일 확인): grpc 1.82.1→**1.84.0**(09-17) · x/net→**0.61.0**(10-09) ·
  otel→**1.47.0**(10-02) · `toolchain go1.26.9` + tidy 연쇄(crypto·sys·genproto 등). 재스캔 **4건**(chi만).
- 앱(pub): 보안 권고 0건(메이저 갱신 다수 밀림 — 아래). 어드민(npm): `@grpc/grpc-js`(Node 전용 — 브라우저 번들에
  안 들어감) · `source-map-js`(빌드 도구) — 런타임 도달 없음.

### D11 운영 도구 정리
- `check_release_target.sh` 실행 비트 손실(755→**600**, 클라우드 동기화 부작용) 원복 — Xcode·하네스는 `/bin/sh 스크립트`로
  불러 동작엔 영향이 없었지만 커밋에 모드 변경이 섞인다(`ram-commit-audit` ❌).
- `p73_mutate.sh` 꼬리의 `exit 0`을 끝으로(⑬~㉚이 처음으로 실행 가능). 이름 기준 판정 명세 `docs/temp/p74_mutations.json` 신설.
- `p74_scan.sh`의 `flutter pub outdated --no-pub`(없는 플래그, exit 64) 정정 · `.gitignore`에 `firebase-debug.log`(에뮬레이터 잔재).

## 반박 라운드 (새 컨텍스트 opus — 이번 수리 8묶음을 깨뜨려 보라고 원본째 넘김)
| 라운드 | CRITICAL | HIGH | MEDIUM | LOW | 결과 |
|---|---|---|---|---|---|
| 3팀 감사(sonnet) | 0 | 0 | 5 | 다수 | D2~D9로 수리 |
| 반박 R1(opus) | 0 | 0 | 1(기존 결함) | 3 + 문서 2 | 아래 D12~D15로 수리 · 이번 수리 8묶음은 **전부 버팀** |

버틴 것(반박자가 시도한 것): HW 집계를 HEAD 논리+탈퇴 반영 참조 구현과 **시드 400개 차분 비교 전부 일치**(탈퇴·없는 ID·
중복 대상·끝난 배정·회원별 조회 실패·필터 5종·by_trainer 인덱스 재사용) · 정상 사진인데 파일이 안 지워지는 경로 없음
(운영 회원 ID는 Firestore 자동 ID, 앱 경로 빌더는 최초 커밋 이후 불변, 규칙이 4단계 경로만 허용) · 계정 전환
(같은 탭 재로그인·데모·토큰 갱신·StrictMode·A→null→B) · go.mod(`tidy -diff` 무차이, otelgrpc v0.68 ↔ otel v1.47 링크 확인).

### D12 (백엔드 MEDIUM · HEAD부터 있던 결함) 트레이너가 `scope`만 바꾸면 센터 매출이 보였다
- `scope`가 `me`가 아니면 센터 전체로 집계하는데 금액을 비우는 조건은 `scope == "center"` 하나뿐 → 트레이너가
  `all`·`ME`·`"center "`를 보내면 `ytd=900000`. 어드민은 me·center만 보내지만 토큰이 있으면 API를 직접 부를 수 있다.
- 수정: 계약대로 `me|center` 밖은 400. 시험 `TestStatsRejectsUnknownScope`(수리 전 5칸 전부 빨강 — ytd 900,000 노출).

### D13 (백엔드 LOW) HW 집계 워커가 패닉하면 남은 회원이 조용히 빠진 200
- `forEachParallel`이 패닉을 오류로 바꾸고 나머지를 취소하는데 그 오류를 버렸다(회원 40·첫 회원 패닉 → 7/40, HEAD는 500).
- 수정: 패닉·요청 취소는 오류로 올린다(회원의 **스토어 오류**는 종전대로 그 회원만). 시험 `TestStatsHwWorkerPanicFailsRequestNotSilently`.

### D14 (어드민 LOW) 자동 새로고침 가드가 30초라 느린 망에서 끝없이 돌 수 있었다
- 부팅→청크 실패가 매번 30초를 넘으면 늘 창 밖 → 횟수 상한 없음. 창을 **10분**으로.

### D15 문서·관측
- `service_stats.go` "두 방식 어느 쪽보다도 많이 읽지 않는다" → Firestore는 빈 쿼리도 최소 1건 과금이라 부정확 — 정정.
- `service.go` "남은 파일은 버킷 대조가 다시 본다" → 대조는 `members/*/body/`만 나열해 폴더 밖 파일은 볼 수 없다 — 정정.
- 작업 기록의 "toolchain은 하한이라 어느 쪽이든 안전" → **틀림**: 빌더가 `GOTOOLCHAIN=local`이면 무시된다. 서버 시작 로그에
  `go=runtime.Version()`을 남겨 다음 배포부터 운영 Go 버전을 Cloud Run 로그로 확인할 수 있게 했다.

## 정정 (틀린 이전 주장 → 반증 → 고친 것)
- 계약 v2.38 ④ "`GET /v1/stats`는 종전 코치 수 + 1번 읽던 것을 1번으로" — **틀림**: HEAD는 배정×대상회원마다 읽었다
  (감사 실측) → D2의 새 서술로 교체.
- 계약 v2.38 ① "무인증 경로의 키(RealIP = XFF 첫 값)" — 부정확: chi RealIP는 `True-Client-IP` → `X-Real-IP` → XFF 첫 값 순
  (감사가 `X-Real-IP`로 피해자 IP를 429로 만드는 재현) → 정정 + 접속기록 `remote_ip`도 같은 값임을 명시.
- 계약 v2.38 클라이언트 규약 "대기실 자동 확인의 물러남(30→60→120초)처럼" — 물러남은 `GET /v1/me` 실패에만 걸리고
  매칭 재조회의 429는 "아직"으로 삼켜진다 → 정정.
- 어드민 감사 "Hosting 규칙이 원본을 이기면 오류가 5분간 모두에게 재생된다"(P35의 '문서상 불확실') — **운영 실측으로 반증**:
  404·401은 원본 `no-store` 그대로 나간다 → 계약에 실측 기록.

## 진행 단계
- [x] 판단 전 점검(원격 0/0 · 다른 ptdesk 세션) · 미커밋 분류 · 클라우드 스냅샷 md5 대조(107/107)
- [x] 기준선 측정 → D1 발견·수정·재측정
- [x] 관점별 조사 3팀 → 교차검증(전건 직접 확인 · 2건 운영 실측)
- [x] 수리 D2~D11 · 계약 v2.38 정정·보강 · 동시 세션(P75)과 파일 범위 조율
- [x] 변이 검사(복사본 · 이름 기준) 1차 67/67 · 반박 라운드(opus) → D12~D15 수리
- [x] 변이 재실행 69/69 · 최종 재검증 전부 그린 · 인덱스 · 커밋 전 점검

## 변경 파일 (이번 회차)
- **backend**: `cmd/server/main.go`(D15 시작 로그 go 버전) · `internal/api/parallel.go`(D1) · `service_stats.go`(D2·D12·D13) · `service.go`(D8 `purgeBodyPhoto`·`ownedBodyPhotoPath`) ·
  `service_account.go`(D8 탈퇴) · 시험 `parallel_test.go` · `ratelimit_test.go` · `service_read_scope_test.go` ·
  `service_body_photo_purge_owned_test.go`(신규) · `internal/store/conformance_test.go` · `go.mod`·`go.sum`(D10)
- **app**: `lib/core/utils/settled.dart`(D7) · `lib/features/bodycheck/data/body_photo_loader.dart`(D3·D4) ·
  `lib/features/my/data/my_repository_impl.dart`(D7) · `lib/features/records/presentation/widgets/workout_log_list.dart` ·
  `lib/features/my/presentation/widgets/ledger_list.dart`(버튼 의미) · `lib/features/home/data/home_repository_impl.dart`(주석) ·
  시험 `test/core/utils/settled_each_test.dart`(신규) · `body_photo_loader_cache_cap_test.dart` · `my_parallel_load_test.dart` ·
  `records_parallel_load_test.dart` · `workout_log_list_paging_test.dart` · **생성 파일 8개**(`*.g.dart` — P71~P74에서
  원본만 바뀌고 다시 만들지 않아 낡은 provider 해시 7개 + 문서 주석 1곳. P73 후속 2번. 복사본에서 `build_runner`를 돌려
  원본이 같은 파일만 옮겼다 — 핫 리로드 판단용 값이라 운영 무관)
- **admin**: `src/main.tsx`(D6·D14) · `src/lib/auth.tsx`(D5) · `src/lib/bodyPhotoBlob.ts`(D4)
- **루트/운영**: `firebase.json`(D6) · `.gitignore` · `docs/API계약_v1.md`(v2.38 정정·보강) ·
  `store/scripts/test-build-guards.sh`(버전 리터럴 4칸 — 아카이브 절은 P75 소관) · `app/ios/scripts/check_release_target.sh`(모드만)
- **검증 도구(untracked `docs/temp/`)**: `p74_mutations.json` · `p74_admin_blob_check.mjs` · `p73_mutate.sh`(exit 위치) ·
  `p74_scan.sh`(플래그) · 로그 `p74_logs/`

## 검증
- **최종 회차**(2026-10-16 00:38~00:41, 맥, 실제 작업 트리 — `docs/temp/p74_logs/final2/`): `go vet` 0 · `go test` **733 pass** ·
  `-race` 그린 · Firestore 에뮬레이터 컨포먼스 **39/39** · govulncheck **4건(chi만)** · admin `npm run build` 그린 ·
  `flutter analyze` 0 · `flutter test` **1561 pass** · `TZ=America/New_York` 29 · 어드민 사진 캐시 하네스 5/5 · iOS 빌드 가드 33/33.
- **변이 검사 69/69 KILLED**(`docs/temp/p74_logs/mutation.md`): P73 14건 재확인 · P74 19건(⑬~㉚ + D1 — 처음 실행) · 이번 수리 36건.
  전부 «기대한 시험 이름»의 실패로 판정(빌드 실패 빨강 0) · 기준선 초록 · 복구 sha256 일치 · 다른 세션과 겹치지 않게 복사본에서.
  1차에서 1건이 WRONG_RED였다 — 시험 이름을 «(peek·load)»→«(peek)»로 바꾼 뒤 명세의 기대 이름을 안 고친 것(같은 시험이 잡음) → 정정 후 KILLED.
- 운영 실측(읽기 전용 GET, 2026-10-16): `/` `max-age=3600` · `/index.html` `no-cache` · 공개 API 404/401은 `no-store` 유지.
- 고치기 전 빨강을 먼저 본 것: D1(40회 중 20) · D2(1차 구현 복사본에서 새 시험 전부 빨강) · D4 앱(`['members/A/body/a.jpg']`) ·
  D12(ytd 900,000 노출 5칸) · D13(패닉에 성공 응답).

## 안 하기로 한 것 (그리고 그 이유)
- **chi `RealIP` → `ClientIPFrom*` 이전**(govulncheck 남은 3건): chi v5.3.0+는 RealIP를 폐기 표시만 했고 동작은 같다 —
  버전만 올리면 스캐너만 조용해진다. 올바른 이전은 신뢰 프록시 홉 수(Cloud Run 직결 vs Hosting 경유가 다를 수 있다)를
  알아야 하는데 지금은 근거가 없다(운영 XFF 원문을 남긴 적이 없다). 홉 수를 틀리면 모든 요청이 프록시 IP 하나로 모여
  공개 경로가 일제히 429가 된다. **다시 열 조건**: XFF 원문을 한 번 로그로 남기는 배포 뒤 두 경로에서 실측.
  같은 이유로 접속기록 `remote_ip`도 위조 가능(스태프가 헤더로 바꿀 수 있다) — 계약에 명시했다.
- **chi 버전만 올리기**: 위 이유(동작 동일) + 5.5.0이 이틀 된 판. RedirectSlashes 취약점(GO-2025-3770)은 미사용.
- **앱 의존성 메이저 갱신**(firebase_* 7/5/14 · go_router 18 · riverpod 3.4/4 · freezed 4 등 27개 제약): 보안 권고 0건이고
  코드 생성·API가 함께 바뀌는 이주 작업이다. 다음 앱 릴리스 주기에 별도 P로.
- **어드민 npm audit 5건**: 런타임 도달 없음(위 D10). `npm audit fix --force`는 firebase를 9.14로 **내리는** 엉뚱한 제안.
- **Flutter `ImageCache` 세션 경계 비우기**: 키가 원본 바이트의 신원이라 다음 사람 화면에 그려질 경로가 없다(메모리만).
  세션 로직에 바인딩 의존을 넣는 비용이 더 크다.
- **장애 시 요청 증폭**(appRetry 3회 × 탭당 4~5요청): 병렬화의 의도된 대가 — 4xx(429 포함)는 재시도하지 않는다.
- **`centerContact`가 429를 빈 연락처로 접기**: P46부터의 의도(부가 정보가 화면을 막지 않음), 화면을 다시 열면 다시 묻는다.
- **취소된 요청의 GET /v1/members 500**: HEAD(Firestore 직렬)도 같다 — 회귀 아님.
- **앱 체형사진 메타 POST 재시도의 멱등성**(반박자가 범위 밖으로 짚음 · HEAD부터): 재시도가 같은 `storage_path`로 다시
  POST하는데 서버에 멱등 처리가 없어, 첫 POST가 실제로 커밋됐다면 레코드 2개가 파일 하나를 가리킨다(하나를 지우면 다른
  하나가 영구 실패 타일). 앱·서버를 함께 바꾸는 일(멱등 키 또는 `storage_path` 유일 조건)이라 별도 P. **다시 열 조건**:
  체형사진 '사진 파일을 찾지 못했어요' 타일 신고 또는 같은 `storage_path`를 가진 레코드가 운영 DB에 생길 때.
- **어드민 진입 번들 516 kB**(Vite 500 kB 경고): Firebase SDK·React가 대부분 — `manualChunks` 분리는 첫 화면 체감 실측과 함께 별도로.

## 확인 못 한 것 (수단 부재) — 안 한 것과 따로
- 운영 백엔드의 Go 버전(Cloud Build 로그 본문이 2줄만 읽힘). `toolchain go1.26.9`는 빌더가 `GOTOOLCHAIN=auto`일 때만
  강제된다(반박 D15) — 다음 배포 뒤 Cloud Run 로그의 시작 줄 `go=…`로 확인한다.
- 어드민 배포 직후 자동 새로고침의 실브라우저 동작(이 세션에 브라우저 도구 없음) — 산출물 문자열·타입 검사·반박 리뷰로 대신.
- D5(다른 탭 계정 전환)의 실동작 — 시험 러너 부재.
- 배포 뒤 `/`의 `Cache-Control: no-cache` — 배포가 람 몫(아래).

## 동시 세션 (P75 — ptdesk-82)
- 같은 트리에서 iOS 전화 인증 reCAPTCHA 복귀(P75) 진행. 메시지로 범위를 나눴다: 그쪽은 Info.plist·AndroidManifest·
  app_router(주석)·통합 시험·`verify-ios-archive.sh`·하네스 아카이브 절, 이쪽은 위 변경 파일.
- 하네스 아카이브 2칸이 한때 실패 — P75가 검증기에 새 검사를 넣고 픽스처를 맞추기 전이었다(그쪽이 수리, 33/33).
- 변이 검사는 그쪽 시험이 변이된 파일을 보지 않도록 **작업 트리 복사본**에서 돌렸다.

## 후속 작업
1. **람 — 커밋**: P71~P74 전부 미커밋(브랜치 `feat/contract-esign-admin-usability`, 원격과 앞섬·뒤짐 0). P75는 다른 세션이 진행 중.
   `docs/temp/`(검증 도구·로그)는 untracked — 넣을지 지울지 람 결정(이번에 쓴 하네스: `p74_mutations.json`·`p74_admin_blob_check.mjs`).
2. **람 — 배포**(분류기가 막는 명령이라 람이 실행):
   - 백엔드: `gcloud run deploy rize-api --source backend --region asia-northeast3 --project rize-218c1 --set-build-env-vars GOOGLE_BUILDABLE=./cmd/server`
     → Cloud Run 로그 시작 줄의 `go=`가 go1.26.9 이상인지 확인(D15).
   - 어드민·Hosting 헤더: 저장소 루트에서 `./deploy-hosting.sh` → `curl -sI https://rize-218c1.web.app/ | grep -i cache-control`이 `no-cache`.
   - Storage 규칙: `firebase deploy --only storage --project rize-218c1` → 실제 앱에서 체형사진 1장 업로드(storage.rules 주석 규약).
   - 앱: `1.0.1+9`(P73)에 이번 앱 수리 포함 — 심사 빌드는 `bash store/scripts/build-release.sh ios` 한 경로(P60).
3. chi `RealIP` → `ClientIPFrom*` 이전: XFF 원문을 한 번 로그로 남기는 배포 뒤 Cloud Run 직결·Hosting 경유 두 경로에서 홉 수 실측(위 "안 한 것").
4. 체형사진 메타 POST 멱등(위 "안 한 것") · 앱 의존성 메이저 갱신 · 어드민 진입 번들 분리 — 각각 별도 P.

## 참조
- `docs/API계약_v1.md` v2.38 절 · `backend/README.md` "요청 빈도 제한" 절
- 로그: `docs/temp/p74_logs/base/`(착수) · `r2/`(의존성 갱신 뒤 Go·에뮬레이터·govulncheck) · `docs/temp/p73_logs/r3/`(의존성 스캔)
- work_log/P73(직전 감사 · 보류 항목 원출처) · P35(Hosting 헤더 '배포 후 실측' 원출처) · P46(centerContact 무재시도)
