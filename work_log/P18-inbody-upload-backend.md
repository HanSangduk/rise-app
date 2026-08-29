---
id: P18
title: 인바디 수기 입력 v1 — 서버 안전장치(값 검증·미래일·중복·삭제 API)
status: 완료
domain: backend
created: 2026-08-23
completed: 2026-08-23
---

# P18 — 인바디 수기 입력 v1(백엔드)

## 목표

회원 앱에 **인바디 수기 입력 폼**을 열기 전에, 서버가 먼저 갖춰야 하는 안전장치를 깐다.
결과지 이미지 저장·OCR은 v1 범위 밖이다(설계00 §OUT에 이미 있는 결정 — 이번에 뒤집지 않았다).

착수 전 `CreateInbody`의 실제 상태(코드 확인, 추정 아님):

| 결함 | 코드 근거 |
|---|---|
| 6개 숫자를 **한 번도 검증하지 않는다** | `service.go`의 `rec := &domain.Inbody{...}`가 요청값을 그대로 대입 |
| 미래 측정일이 통과한다 | 날짜 검증이 `time.Parse` 형식 검사뿐(v2.5) |
| 같은 회원·같은 날 중복이 무제한 | 중복 확인 코드 없음 |
| **정정 수단이 0개** | 라우터에 `/inbody`는 GET·POST 둘뿐, Store에 `Update/DeleteInbody` 부재 |

이 상태로 폼을 열면 오타 한 번이 회원 차트에 영구 고정되고, 복구 경로는 Firestore 콘솔
수기 편집뿐이다. **그래서 폼보다 안전장치가 먼저다.**

## 결정 사항

### 1. `source`는 요청이 아니라 Principal로 판정한다

`domain.Inbody`에 `Source string`(`"member_self"` | `"staff"` | `""`) 추가.
`decodeJSON`이 `DisallowUnknownFields`라 앱이 `source`를 실으면 **400**이고, 그게 의도다 —
이 값이 곧 **삭제 권한의 근거**(회원은 `member_self`만 지울 수 있다)라 클라이언트가 정할 수
있으면 안 된다. HTTP 계약 테스트에 그 400을 못박아 뒀다.

`""`(v2.9 이전 레코드)는 **백필하지 않는다**. Firestore 저장이 `toDoc`/`fromDoc` json
라운드트립이라 기존 문서는 자동으로 `""`로 언마샬되고, `""`는 "회원 본인이 넣었다는 근거가
없다"는 뜻이라 삭제 판정에서 staff와 같은 취급을 받는 게 안전한 기본값이다.

### 2. 값 검증은 **도메인**에 둔다 — 개별 범위 + 교차 3개

`domain.Inbody.Validate()` 신설(`ErrInvalidInbody` sentinel → `writeErr`에서 400).

범위는 **생리학적 하한이 아니라 "오입력 판별선"**이다. 진짜 측정값을 막지 않을 만큼 넓게 잡고
오타(부호·자릿수·빈 칸의 0.0·다른 지표 옮겨 적기)만 걸러낸다:

| 지표 | 범위 | 상한 초과 시 힌트 |
|---|---|---|
| 체중 | 20~300 kg | — |
| 골격근량(SMM) | 5~120 kg | — |
| 체지방량(BFM) | 1~200 kg | "제지방량(FFM) 칸이 아니에요" |
| 체지방률(PBF) | 1~70 % | — |
| 내장지방레벨(VFL) | 1~30 | "내장지방'레벨'이에요 — 단면적(cm²)이 아니에요" |
| 기초대사량(BMR) | 500~5000 kcal | — |

**0을 전부 거부하는 게 이 표의 핵심**이다: JSON에서 미입력 숫자는 `0.0`으로 직렬화되므로
"선택 입력" 필드를 두면 곧 "0kg 체중"이 되고, 0은 차트 바닥으로 내려가 추이 자체를 망가뜨린다.
→ 앱 폼의 **6개 필수**는 이 결정에서 파생된 것이다(선택 필드가 성립할 수 없다).

교차 검증 3개(`smm < weight`, `bfm < weight`, `smm+bfm <= weight`)는 **체/제 오기**를 잡는
자리다. FFM(제지방량)은 보통 체중의 70~90%라 개별 범위는 태연히 통과하지만, 골격근량과
더하면 체중을 넘는다.

⚠️ 세 검사는 서로 겹친다(SMM>체중이면 SMM+BFM도 당연히 체중을 넘는다). 그래서 테스트가
**sentinel만이 아니라 문구까지** 검증한다 — 그러지 않으면 앞의 두 검사를 지워도 테스트가
통과한다(1차 뮤테이션에서 실제로 2개가 살아남아 그때 보강했다). 회원에게는 "어느 두 칸을
비교해 보라는 것인지"가 전부다.

### 3. 중복 차단은 **실용적 차단**이다 — 경합은 남는다(계약 갭)

같은 회원·같은 date가 이미 있으면 **409**. 쓰기 직전 `ListInbody` 1회를 감수했다.

**한계를 명시해 둔다**: 동시 요청 경합은 남는다(같은 순간 두 요청이면 둘 다 통과 가능).
완전 차단은 `(회원,날짜)` 합성 문서 ID upsert나 트랜잭션이 필요한데(hwChecks가 쓰는 방식)
그건 컬렉션 ID 체계 변경이라 기존 문서 마이그레이션이 따라온다. v1 실사용에서 실제로 흔한
사고는 "저장 성공 응답을 놓치고 한 번 더 누르는 것"이고, 그건 순차 요청이라 이걸로 잡힌다.

### 4. 정정은 DELETE만 — **PUT을 만들지 않는다**

`DELETE /v1/inbody/{id}`. 삭제 후 재입력이면 충분하고(원본이 사라져 중복 차단에 걸리지 않는다),
API 면적이 절반이다. 6개 숫자짜리 레코드에 부분 수정의 이점이 없다.

권한 순서: `GetInbody` → `GetMember` → `checkMemberScope` → **회원 본인은 `source ==
"member_self"`일 때만**. 코치가 기기 측정값을 옮겨 적은 기록까지 회원이 지울 수 있으면,
마음에 안 드는 수치를 없애 상담 근거 자체가 사라진다.

**동의(sensitive)는 보지 않는다.** 삭제는 동의 철회 이후에 더 필요한 동작이지, 동의를 전제로
하는 동작이 아니다(생성만 P8 게이트를 지난다).

응답은 `200 {"deleted":true}` — 204는 fetch 계열 클라이언트가 본문 없는 응답을 에러와 구분하기
번거로워, 이 API의 다른 동사들과 통일했다.

### 5. 정렬 타이브레이커 — `order.go`에 공용 비교자로

`sortInbody`(date desc → 동률 시 ID asc)를 `order.go`에 넣고 Memory·Firestore가 공유한다.
`sortPasses`와 같은 자리·같은 이유다: 날짜만으로 정렬하면 **같은 날짜 2건**(v2.9 이전 데이터)의
상대 순서가 Memory에선 맵 순회라 호출마다 뒤바뀌고 Firestore에선 문서 ID로 고정된다 —
"로컬에선 새로고침마다 다르고 프로덕션에선 고정"이라는, 개발 중엔 재현조차 어려운 차이다.
인바디는 앱 차트의 추이선과 "직전 대비 증감"의 입력이라 **순서가 곧 화면**이다.

### 6. 손대지 않은 것

- **`storage.rules` 무변경.** v1에 결과지 이미지가 없으므로 규칙 변경 사유가 없다. 건드리는
  순간 오늘 정상화된 IAM(`firebaserules.firestoreServiceAgent`)과 **평가당 고유 Firestore
  문서 2개 상한**을 실기기로 다시 검증해야 하고, TestRuleset은 그 결함을 못 잡는다.
  현재 규칙이 정확히 2문서(users/{uid}, members/{id})라 한계에 걸쳐 있다.
- `firestore.rules` · `firebase.json` 무변경.
- `ListInbody`의 스코프를 `checkMemberScope` → `checkBodyPhotoAccess`로 바꾸지 않았다
  (운영 파급이 있는 별도 결정 — 아래 후속 작업에 기록).
- `app/**` 한 줄도 건드리지 않았다(다른 에이전트 담당).

## 진행 단계

- [x] 선작성 테스트 — 도메인 5개 함수 + API 6개 함수 + 스토어 계약 2개
- [x] `domain`: `Source` 필드 + 상수 2개 + `ErrInvalidInbody` + `Validate()`
- [x] `api/util.go`: `ErrInvalidInbody`를 400 매핑 목록에 등록
- [x] `api/service.go`: `CreateInbody` 5단(형식 → 미래일 → 중복 → Validate → source) + `DeleteInbody` 신설
- [x] `api/router.go` + `api/handlers_media.go`: `DELETE /v1/inbody/{id}` 배선
- [x] `store`: 인터페이스 2개 추가 + Memory/Firestore 구현 + `order.go` `sortInbody`
- [x] `store/conformance_test.go`: 두 구현 공통 계약 2건 + 기존 2건에 인바디 케이스 추가
- [x] 기존 픽스처 정비(6지표 완비) — `service_inbody_date_test.go`, `service_test.go`
- [x] `seed.go` 데모 인바디에 `source=staff`
- [x] 뮤테이션 검증 18/18 kill
- [x] `go build` / `go vet` / `go test -race` 전량 통과

## 변경 파일

**도메인**
- `backend/internal/domain/measurement.go` — `Source` 필드, `InbodySourceMemberSelf`/`Staff`,
  `ErrInvalidInbody`, `inbodyRanges` 표, `Validate()`
- `backend/internal/domain/measurement_test.go` (신규) — 5개 테스트

**API**
- `backend/internal/api/service.go` — `CreateInbody` 확장, `DeleteInbody` 신설
- `backend/internal/api/util.go` — `ErrInvalidInbody` 400 매핑
- `backend/internal/api/router.go` — `r.Delete("/inbody/{id}", …)`
- `backend/internal/api/handlers_media.go` — `DeleteInbody` 핸들러(chi import 추가)
- `backend/internal/api/service_inbody_test.go` (신규) — 서비스 6개 + HTTP 계약 1개
- `backend/internal/api/service_inbody_date_test.go` — 픽스처 6지표 완비
- `backend/internal/api/service_test.go` — 픽스처 6지표 완비(`TestSensitiveWritesRespectScope`)

**스토어**
- `backend/internal/store/store.go` — `GetInbody`/`DeleteInbody` 인터페이스 + 정렬 규약 주석
- `backend/internal/store/order.go` — `sortInbody`
- `backend/internal/store/memory.go` — `GetInbody`/`DeleteInbody`, `sortInbody` 적용
- `backend/internal/store/firestore.go` — 동일(존재 확인 선행 삭제)
- `backend/internal/store/conformance_test.go` — `InbodyListOrderedByDateThenID`,
  `InbodyGetDeleteRoundTrip`, `GetInbody("")`, `DeleteInbody(ghost)`
- `backend/internal/store/seed.go` — 데모 인바디 `source=staff`

## 검증

```
cd backend && go build ./... && go vet ./... && go test ./... -race
ok  internal/api   2.485s
ok  internal/config 1.257s
ok  internal/domain 2.621s
ok  internal/store  1.667s
```

`gofmt -l`: 내가 만지거나 만든 파일 전부 clean.
(`internal/store/conformance_test.go`·`internal/domain/policy_test.go`에 남은 diff는 내 편집
라인과 무관한 기존 노이즈 — 주석 들여쓰기·함수 리터럴 줄바꿈.)

### 뮤테이션 검증 — 18/18 kill

고친 곳을 하나씩 되돌려 테스트가 **실제로** 깨지는지 확인하고 복구했다.

| 뮤테이션 | 죽인 테스트 |
|---|---|
| 미래 날짜 거부 제거 | `TestCreateInbodyRejectsFutureDate` |
| 같은 날 중복 차단 제거 | `TestCreateInbodyRejectsDuplicateDate` |
| `Validate()` 호출 제거 | `TestCreateInbodyRejectsOutOfRangeValues` |
| `source`를 항상 staff로 | `TestCreateInbodyStampsSourceFromPrincipal` |
| 회원 삭제 출처 가드 제거 | `TestDeleteInbodyScope` |
| 삭제 스코프 검사 제거 | `TestDeleteInbodyScope` |
| 정렬 타이브레이커 제거 / 1차 키 방향 반전 | `TestMemoryStoreConformance`, `TestListInbodyOrderIsDeterministic` |
| Memory `DeleteInbody` 미존재를 성공으로 | `TestMemoryStoreConformance/UpdateOnMissingIDIsNotFoundAndCreatesNoGhost` |
| Memory `GetInbody` 미존재를 빈 레코드로 | `TestMemoryStoreConformance`, `TestDeleteInbodyScope` |
| 체중 하한을 0으로 / BMR 상한 제거 / VFL 힌트 제거 | 도메인 범위·문구 테스트 |
| 교차검증 3개 각각 제거 | `TestInbodyValidateRejectsImpossibleCombinations` |
| DELETE 라우트 등록 제거 / 핸들러가 URL id 무시 | `TestInbodyHTTPContract` |

1차 실행에서 **4개가 살아남았다**(체중 하한, 교차검증 2개 + 스토어 셀렉터 오류). 보강한 것:
- 하한 바로 아래 경계 케이스(체중 19.9 + SMM/BFM 최소) — 교차 검증이 가려 주던 자리
- 교차 검증 3개에 **문구 단위 단정** — 세 검사가 겹쳐 잡으므로 sentinel만 보면 구분 불가

### 미검증(정직하게)

- **Firestore 구현의 실제 동작**은 에뮬레이터 없이 확인하지 못했다. `conformance_test.go`에
  케이스를 넣어 뒀으므로 `-tags firestore_emulator`로 러너를 돌리면 같은 함수가 두 구현을
  함께 검증한다. Memory만 통과한 상태다.
- Storage 규칙은 **변경하지 않았으므로** TestRuleset 평가를 돌리지 않았다(평가 대상 변화 0).

## 후속 작업

1. **앱 담당에게**: 서버가 선배포돼야 한다(`DisallowUnknownFields`). 앱은 요청 바디에
   `source`를 **넣지 말고**, 응답 DTO의 `source`는 **반드시 nullable**로 둔다(기존 레코드는 `""`).
2. **에뮬레이터 러너 실행** — `go test ./internal/store/ -tags firestore_emulator`로 Firestore
   쪽 `GetInbody`/`DeleteInbody`/`sortInbody`를 실측.
3. **`ListInbody` 스코프 재검토(계약 갭)** — 현재 `checkMemberScope`라 owner는 동의 없이도
   인바디 목록을 읽는다. 체형사진(`checkBodyPhotoAccess`)은 owner도 동의 게이트를 지난다.
   같은 P8 민감정보인데 비대칭이다. 바꾸면 운영 파급이 있어 별도 결정 사항으로 남긴다.
4. **중복 차단 경합(계약 갭)** — 위 §3. 실사용에서 실제로 관측되면 합성 문서 ID로 옮긴다.
5. **어드민 정정 UI** — DELETE가 열렸으니 `admin/src/features/BodyPhotos.tsx`의 `InbodyList`에
   삭제 액션을 붙일 수 있다(파괴적 액션이라 2단 확인 — P12 어드민 규약).
6. **v2 OCR 게이트** — 이번 작업이 게이트 ①(범위검증 + DELETE API)을 닫았다. 나머지 넷
   (기종 확정 · 실물 20~30장 필드별/6개동시 정답률 실측 · iOS 비용 · 플랫폼 비대칭)은 그대로.

## 참조

- 설계: `PT데스크_설계_00_제품정의_자문자답_2026-08-14.md:115,152,233`(수기 입력 전제 · OUT 목록)
- 목업: `목업_회원앱_라이즈_2026-08-14.html:226-232`(델타 표기는 목업 복원, 입력 폼은 신규)
- 선례: `internal/store/order.go` `sortPasses`(정렬 타이브레이커), `service.go`의
  `paid_at` 미래 차단(P12 감사 M5), `checkBodyPhotoAccess`(P37 owner 동의 게이트)
- 계약: `docs/API계약_v1.md` v2.9 절 — **이 파일은 내가 쓰지 않았다**(반환값으로 넘김)
