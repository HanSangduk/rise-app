---
id: P76
title: P74 보류 항목 후속 — 시각 동률 정렬 · 체형사진 메타 멱등 · 클라이언트 IP 신뢰 경계 · 커밋·푸시
status: 완료
domain: cross
created: 2026-10-16
completed: 2026-10-16
---

# P76 — "하지 않은 부분에서 필요한 것"을 마저

## 목표 (람 요청)
- 2026-10-16 람: "하지 않은 부분에서 필요한 부분 /ram-verify-loop 진행해서 완성도 높여서 작업 후 문제없으면 커밋 푸시".
- 대상(P74 "안 하기로 한 것"): chi `RealIP` 신뢰 경계 · 체형사진 메타 POST 멱등 · 앱 의존성 메이저 갱신.

## 착수 (2026-10-16 08:4x)
- 같은 트리의 P75 세션(iOS 전화 인증)이 완료 — pbxproj를 P73 몫(리터럴 6줄 삭제)만 남게 되돌림 확인.
- P71~P75를 **로컬 커밋 3f9f054**(185파일, `docs/temp/` 제외 — 덩어리가 섞인 파일 3개 때문에 저장소 관례대로 범위 커밋).
  커밋 직전 전체 검증에서 **Go 시험 1건 실패** → 아래 E1(HEAD부터 있던 결함, P71~P75 무관).
  커밋된 트리를 `git archive`로 풀어 go vet/test·어드민 빌드 재확인.

## 자
| 자 | 착수 | 마지막 |
|---|---|---|
| `TestMeJoinRequestFollowsSelectedCenter` 300회 반복 | **72/300 실패(24%)** | **0/300** |
| `go test ./...` | 733 pass(+간헐 실패 1) | **742 pass** |
| Firestore 에뮬레이터 컨포먼스 | 39 | **41**(새 사례 2) |
| 변이 검사(이름 기준 · 백엔드 복사본) | — | **26/26 KILLED** |

## 결정 사항

### E1 (백엔드 · HEAD부터) 생성 시각이 같으면 "최신 가입 요청"이 무작위였다 — 결함 부류: 1차 키 단독 정렬
- 두 스토어 모두 `CreatedAt`만으로 `sort.Slice`(불안정 정렬) — 동률이면 순서가 실행마다 갈린다. 맥의 실시각 해상도는 1µs라
  시험에서 연달아 만든 두 요청이 같은 시각을 받는다(**72/300**). `/v1/me`의 join_request는 목록의 **첫 항목 = 현재 상태**.
  운영(Firestore)은 입력이 문서 ID 순으로 고정이라 사실상 결정적이고 별개 요청이 같은 µs를 받기도 어렵다 — 피해는 로컬·시험.
- 부류 전수(`sort.Slice` 34곳 분류): `order.go`가 이미 "두 스토어 같은 순서" 규약을 문서화했는데 **1차 키가 겹칠 수 있는
  단독 정렬 18곳**(가입 요청 4 · 원장 3 · 회원 2 · 스태프 2 · 예약 3 · 체형사진 2 · 수업 기록 2)이 비켜 가 있었다. 이미 동률
  처리된 곳(상담 요청 2 · 회원권 · 인바디) · 키가 고유한 곳(ID 정렬 · 슬롯 키)은 그대로.
- 수정: `order.go` 공용 비교자 7개(1차 키 → 문서 ID). 최신 먼저인 시각 목록은 ID 내림차순(Memory 시퀀스상 나중 것이 앞),
  나머지는 `sortInbody` 관례대로 ID 오름차순. 재측정 **0/300**. 시험: 비교자 단위(섞은 입력 50판) + 적합성
  `ListsTieBreakByDocID`(동률을 일부러 만들어 8번 조회 — **Memory·Firestore 에뮬레이터 둘 다 통과**).

### E2 (백엔드 · HEAD부터) 체형사진 메타 POST 재시도가 레코드를 하나 더 만들었다
- 앱은 Storage 업로드 뒤 메타 POST가 실패하면 **같은 경로로 POST만 다시**(고아 파일 방지). 첫 POST가 커밋되고 응답만
  잃었으면 레코드가 둘 → 하나를 지우면 파기가 파일을 지워 나머지가 영구 실패 타일. 시험 3개가 수리 전 전부 빨강
  (재시도 = 새 레코드 · 동시 8건 = 서로 다른 레코드 · 유예 삭제된 사진이 재시도로 되살아남).
- 수정: 문서 ID = `bp_` + SHA-256(storage_path) 앞 32자. 저장소 `CreateBodyPhoto`는 ID가 주어지면 **없을 때만 생성**
  (Firestore `Create` → `AlreadyExists`, Memory 락 안 확인) → 서비스가 기존 레코드를 돌려줌(200), 유예 삭제 상태면 409.
  확인 후 생성이 아니라 원자 연산이라 동시 재시도도 하나. 새 Firestore 쿼리가 없어 운영 인덱스 위험 0.
  적합성 `BodyPhotoGivenIDIsCreateOnce`(Memory·에뮬레이터 둘 다 통과). 앱 변경 없음(응답 모양 동일).

### E3 (백엔드) 클라이언트 IP 신뢰 경계 — 이전 대신 **계측**(근거가 부족한 이전은 안 한다)
- 조사(sonnet + 운영 로그 30일, IP 마스킹 집계): Hosting 경유(`/api/v1`)는 XFF가 20,695/20,695줄 정확히 `사용자, Google 에지`,
  에지는 **goog.json** 대역(cloud.json 0건 — chi 주석이 가리키는 목록으론 안 덮인다), Cloud Run의 `remoteIp`는 그 에지.
  앱 직결(`/v1`)은 회원 성공 요청이 기록 대상이 아니라 모양을 볼 수 없었고, 컨테이너의 TCP 피어는 RealIP가 덮어 로그에 없다.
  공식 문서(Cloud Run·Firebase Hosting)엔 XFF 서술이 없다. chi v5.4+ `ClientIPFromXFF(신뢰 CIDR)`만 두 경로를 한 설정으로
  맞출 수 있는데 피어 대역·직결 XFF 모양을 모르면 잘못 고른 순간 모든 요청이 프록시 IP 하나로 모인다(공개 경로 일제 429).
- 수정(동작 무변경): RealIP **앞**에 `capturePeer` → 접속기록에 `peer_addr`(원래 TCP 피어, 포트 제외) · `ip_headers`
  (True-Client-IP·X-Real-IP·Forwarded·Fastly-Client-IP·X-Client-IP의 **존재만**). 다음 배포 뒤 두 경로의 실제 모양이 남는다.
  시험: 위조 헤더 + 기본 피어(192.0.2.1)로 순서까지 고정(캡처가 RealIP 뒤면 7.7.7.7이 돼 빨강).

### E4 반박 라운드(opus) 후속
| 라운드 | CRITICAL | HIGH | MEDIUM | LOW | 결과 |
|---|---|---|---|---|---|
| 반박 R1 | 0 | **1(내 실수)** | 0 | 3 + 문서 3 | 아래 수리 · E1~E3 기능 결함은 0 |

- **HIGH — 기존 회귀 시험 4개를 지웠다(내 실수)**: 비교자 단위 시험을 셸 리다이렉트(`cat >`)로 `store/order_test.go`에 썼는데
  **이미 있던 파일(248줄)을 통째로 덮었다** — `TestSortByDocIDIsAscending`·`TestSortPassesByValidFromThenID`(P13 M1 회귀
  방어)·`TestHwCheckSortKeyIsTheFirestoreDocID`(hwChecks 문서 ID 규칙)·`TestMemoryListsAreOrderedByDocID`. 반박자가 변이로
  보였다: hwChecks 구분자 `_`→`-`, 회원권 동률 제거가 전체 시험을 통과했다. 내 변이 명세(22/22)는 **새 코드만** 변이해서
  이 삭제를 볼 수 없었다. → 3f9f054 원본을 되살리고 새 시험을 뒤에 덧붙임(3f9f054 대비 +64줄·삭제 0) · 그 두 변이를 명세에
  추가(KILLED). 3f9f054 자체도 직전 커밋 대비 사라진 시험 이름을 전수 대조 — 3건 모두 P72의 의도된 교체(임계 360→400 등).
  재발 방지: 저장소 경로엔 셸 리다이렉트로 쓰지 않는다(Write 도구는 읽지 않은 기존 파일 덮어쓰기를 거부한다) · 새 파일도
  `test -e`로 먼저 확인 · 커밋 전 `ram-commit-audit`의 시험 삭제 경고.
- LOW — 같은 경로·**다른 내용**(pose·방향·날짜·회원)의 요청도 기존 레코드를 200으로 돌려줬다 → 멱등은 같은 요청에만, 다르면 409.
- LOW — 문서 ID 공식이 리터럴로 고정되지 않았다(`sum[:16]`→`[:8]`이 전체 시험 통과) → 고정값 시험(`TestBodyPhotoDocIDIsStable`).
- LOW(문서) — 라우터 머리 주석의 미들웨어 순서 · 계약 요약 줄(POST /v1/body-photos) · 접속기록 예시에 새 필드 ·
  v2.39 ③의 과장("두 경로 모양을 남긴다" → 앱 직결은 기록 대상인 401·403·429 줄에서만) 정정.
- 안 고친 것(사유): ① 회원 본인 삭제(즉시 파기) **뒤** 늦게 온 같은 경로 재시도는 지워진 파일을 가리키는 레코드를 다시
  만든다 — 지금 앱에선 도달 불가(카메라는 PopScope 가드 전체화면이고 화면을 떠나면 pendingRetry가 사라진다), 직접 API로만.
  막으려면 POST마다 Storage 존재 확인이 필요해 지연·비용이 든다. ② Firestore의 ID 오름차순 목록(회원·스태프·예약·체형사진·
  수업 기록)은 Firestore가 원래 문서 ID 오름차순으로 주고 옛 비교자도 그 순서를 유지해 **출력이 같다** — 변이로 가를 수 없는
  동등 변이라 시험으로 닫지 않는다(내림차순 목록인 가입 요청은 에뮬레이터 변이로 KILLED).

## 진행 단계
- [x] 착수 점검 · P71~P75 로컬 커밋 · 커밋 트리 재검증
- [x] E1 시각 동률 정렬(부류 전수) · E2 체형사진 메타 멱등 · E3 클라이언트 IP 계측 · 운영 Go 버전 확인 시도
- [x] 변이 26/26 · 반박 R1(opus) → E4 수리 · 최종 검증 · 커밋(P71~P75 3f9f054 · P76 이 커밋)
- [ ] 푸시 — `git push`가 GitHub 403("Permission … denied to SC-Deogi"): git 자격 증명이 gh **활성 계정** SC-Deogi를 쓰는데
  이 저장소(HanSangduk/rise-app) 쓰기 권한이 없다. HanSangduk 계정도 로그인돼 있으나 비활성 — 전환은 다른 세션·저장소에도
  걸리는 전역 설정이라 람이 한다(후속 0).

## 변경 파일
- **backend/internal/store**: `order.go`(비교자 7) · `memory.go`·`firestore.go`(정렬 18곳 · 체형사진 생성-한-번) · `store.go`(인터페이스 주석) ·
  `errors.go`(`ErrAlreadyExists`) · 시험 `order_test.go`(**원본 복원** + 비교자 단위) · `conformance_test.go`(`ListsTieBreakByDocID`·`BodyPhotoGivenIDIsCreateOnce`)
- **backend/internal/domain**: `measurement.go`(`BodyPhotoDocID`) · 시험 `body_photo_doc_id_test.go`(신규, 고정값)
- **backend/internal/api**: `service.go`(멱등 생성 · 삭제 409 · 내용 불일치 409) · `router.go`·`accesslog.go`(`capturePeer` · `peer_addr` · `ip_headers`) ·
  시험 `service_body_photo_idempotent_test.go`(신규 4) · `accesslog_test.go`(+1)
- **문서**: `docs/API계약_v1.md` v2.39 절 + 요약 줄 + 접속기록 예시 · `backend/README.md` 접속기록 표 · 이 문서 · `work_log/README.md`
- **검증 도구(untracked)**: `docs/temp/p76_mutations.json` · 로그 `docs/temp/p76_logs/`

## 검증
- 최종(2026-10-16 09:3x, 맥, 실제 작업 트리 — `docs/temp/p76_logs/final/`): `go vet` 0 · `gofmt`(건드린 파일) 0 · `go test` **742 pass** ·
  `-race` 그린 · Firestore 에뮬레이터 **41/41** · `TestMeJoinRequestFollowsSelectedCenter` **0/300**(수리 전 72/300).
- **변이 26/26 KILLED**(`docs/temp/p76_logs/mutation.md`) — Memory·Firestore(에뮬레이터) 배선 · 비교자 7 · 멱등 4 · 계측 3 · 되살린 시험 2.
  1차에서 회원 배선 변이 1건이 생존(시험이 확률적이었다 — 작은 맵 순회가 삽입 순서의 회전) → 삽입 순서를 c,a,d,b로 바꿔 결정적으로.
- 커밋 전: P71~P75는 커밋 3f9f054(`git archive`로 풀어 go vet/test·어드민 빌드 재확인). 앱·어드민은 P76이 건드리지 않았다.

## 후속 작업
0. **람 — 푸시**: `gh auth switch -u HanSangduk && git -C ~/development/2026-06-workout-app/ptdesk push && gh auth switch -u SC-Deogi`
   (전환·푸시·원복을 한 줄로 — 다른 세션이 SC-Deogi로 일하는 창을 짧게).
1. **람 — 백엔드 배포**(P71~P76 서버 변경 전부): 저장소 루트에서
   `gcloud run deploy rize-api --source backend --region asia-northeast3 --project rize-218c1 --set-build-env-vars GOOGLE_BUILDABLE=./cmd/server`
   → Cloud Run 로그 시작 줄의 `go=`(운영 Go 버전 — 빌드 단계 로그는 별도 버킷이라 이번에도 못 읽었다) · 접속기록의 `peer_addr`·`ip_headers`.
2. **chi RealIP 이전 판단**: 배포 뒤 스태프 요청(Hosting 경유)과 앱 직결의 401·403·429 줄이 쌓이면 `peer_addr` 대역·XFF 모양을 보고
   `ClientIPFromXFF(신뢰 CIDR)` 여부를 정한다. 더 빨리 보려면 람 승인 하에 무인증 GET 2회(직결 `/v1/me`·Hosting `/api/v1/me`, 위조 헤더
   포함)로 실측 — 접속기록 버킷에 줄 2개가 보존 기간 동안 남는다.
3. **앱 의존성 메이저 갱신**(안 한 것): 보안 권고 0건 · P75의 새 iOS 빌드 심사가 걸려 있어 네이티브 플러그인 메이저 갱신은 심사 뒤 별도 P.
4. PR·머지는 람이 P75/P77 세션에 맡김 — 그 세션에 커밋 해시를 넘겼다.

## 참조
- work_log/P74(보류 항목 원출처) · P75·P77(동시 세션) · P13(회원권 동률 M1 — 되살린 시험의 원출처) · 커밋 3f9f054(P71~P75)
