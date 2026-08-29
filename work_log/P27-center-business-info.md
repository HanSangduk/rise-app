---
id: P27
title: 사업자 정보를 어드민 등록 → API 제공 → 법정 문서 자동 채움
status: 완료
domain: cross
created: 2026-08-25
completed: 2026-08-26
---

## 목표

P22(법정 문서 갈래)가 남긴 `{{...}}` 플레이스홀더 64자리(12종)를 **하드코딩이 아니라 등록된
데이터**로 채운다. 람의 지적이 정확하다 — 사업자명·대표자·등록번호·보호책임자는 코드에 박을
값이 아니라 센터가 등록하는 값이고, 바뀌면 문서 5장을 손으로 고치는 게 아니라 한 곳만 고쳐야 한다.

## 결정 사항

### D1. `Business`는 `Policy` 안이 아니라 **옆에** 둔다 (`CenterResponse.business`)

`Policy`는 서비스 동작을 바꾸는 운영 다이얼, `Business`는 동작을 하나도 바꾸지 않는 법적 신원이다.
안에 넣었을 때 실제로 깨지는 것 셋:

1. `Policy.Validate`가 두 종류의 실패를 한 sentinel(`ErrInvalidPolicy`)로 뭉뚱그리게 된다.
2. 어드민 `PolicyEditForm`의 "바뀐 필드만 저장" 비교가 `baseline[k] !== initial[k]`인데, 중첩
   객체는 재조회마다 참조가 달라져 **늘 "다른 창에서 정책이 바뀌었어요" 경고**가 뜬다(P14 M5가
   좁혀 둔 의미가 그 자리에서 도로 사라진다).
3. 무인증 공개 응답에서 정책을 걷어내는 일을 매번 손으로 하게 된다 — 한 번 빠뜨리면 연 매출
   목표가 익명에게 나간다.

### D2. 저장은 같은 문서, 대신 `SavePolicy`를 머지 쓰기로 바꾼다

`centers/{centerID}` 문서가 곧 정책 문서였고(`fromDoc[domain.Policy](snap.Data())`),
`SavePolicy`는 통 `Set`이었다. 여기에 `business` 필드를 얹으면 **정책 저장이 사업자 정보를
지운다**. `firestore.MergeAll`로 바꿔 닫았다. Memory는 맵이 둘이라 재현되지 않는 결함이라
공통 계약 스위트에 넣어 에뮬레이터 러너에서 잡히게 했다(뮤테이션으로 실증 — 아래 검증).

### D3. 저장 가능 조건과 게시 가능 조건을 분리한다

- `Validate()` — 채워진 칸의 **형식만** 본다. 빈 칸 통과. 부분 입력은 오류가 아니다.
- `IsComplete()` — 12칸 전부. 공백만 있는 칸은 빈 칸으로 센다.
- `complete` — 서버가 계산해 응답에 싣는 파생값(저장 안 함).

전부 채워야 저장되게 하면 대표는 아는 칸부터 채울 수가 없어 결국 메모장에 적어 둔다. 반대로
부분 입력을 완성으로 취급하면 처리방침이 보호책임자 연락처 없이 "시행 중"으로 게시된다 —
형식 미비가 아니라 법정 기재사항 누락이다.

`complete`를 클라이언트가 다시 세지 않게 한 이유는 P14 C1과 같다: 층마다 세면 어느 문서는
시행 중이고 어느 문서는 초안인 상태가 만들어진다.

### D4. 사업자 정보 PUT은 **통 교체**(정책은 머지 — 반대다)

근거는 `PUT /v1/staff/{uid}/profile`과 같다. 폼이 늘 12칸을 제출하고, **잘못 적은 칸을 비워서
지우는 일**이 실제로 필요하다. 머지면 한 번 들어간 오타를 지울 수단이 없다. 정책이 머지인 건
자주 만지는 다이얼이라 동시 편집 충돌이 실재하기 때문이고, 사업자 정보는 개업 때 한 번 넣는 값이다.

### D5. 공개 엔드포인트는 전용 응답 타입으로 잠근다 (마스킹 아님)

`GET /v1/public/business` — 인증 그룹 **밖**에 붙인 유일한 v1 경로. 응답은 `BusinessView`
(12칸 + complete)뿐이라 `GET /v1/center`에 필드가 늘어도 새지 않는다. 마스킹 목록 관리
방식이었다면 언젠가 하나를 빠뜨린다. 테스트가 **키 집합을 통째로** 고정한다.

내보내지 않는 것: policy 전체, `revenue_target`, `center_id`, 회원·직원·예약 일체.
파라미터도 받지 않는다(익명이 center_id를 고를 수 있으면 센터 존재 여부를 훑는 수단이 된다).
`GetBusiness`는 지연 시딩을 하지 않는다 — 무인증 읽기가 쓰기를 유발하면 안 된다.

### D6. 문서에는 `{{...}}` 를 **한 글자도 남기지 않는다**

JS가 채우는 게 아니라, 파일 자체가 이미 `(항목명 미정)`으로 렌더돼 있고 스크립트가 그 위에
덮어쓴다. fetch 실패·JS 비활성 어느 쪽이든 원시 플레이스홀더가 **보일 수 없는 구조**다.
초안 배너는 `complete && effective_date && 화면에 남은 미기재 0` 셋 다일 때만 사라진다.

### D7. 사업자등록번호 체크섬은 서버가 보지 않는다 — 어드민에서 경고만

형식(10자리)은 차단하되 체크디짓은 차단하지 않는다. 오탐 한 번이 **유일하게 고칠 수 있는
사람**을 영구히 막는다. P18의 "PBF 항등식은 서버가 안 보므로 경고만"과 같은 자리.

## 진행 단계

- [x] 1. 도메인 선작성 테스트 11건 + `Business` 구현
- [x] 2. 스토어(Memory/Firestore) 왕복 + `SavePolicy` 머지 전환 + 공통 계약 스위트
- [x] 3. 서비스·핸들러·라우터(공개 경로) + API 테스트 8건
- [x] 4. 어드민 폼(12칸 · 서버 검증 미러 · 미기재 목록 · 초안 고지 · 체크디짓 경고)
- [x] 5. 법정 문서 5장(플레이스홀더 64자리 → data-biz 훅 + 사전 렌더 폴백 + 채우기 스크립트)
- [x] 6. 계약 v2.13
- [x] 7. 게이트

## 변경 파일

```
backend/internal/domain/business.go              신규 — Business·Validate·IsComplete·MissingFields·Normalize
backend/internal/domain/business_test.go         신규 — 선작성 11건
backend/internal/api/service.go                  CenterResponse.business · BusinessView · UpdateCenterBusiness · PublicBusiness
backend/internal/api/handlers_me.go              UpdateCenter가 {policy?,business?} · PublicBusiness 핸들러
backend/internal/api/router.go                   무인증 /v1/public/business + /api/v1 미러
backend/internal/api/util.go                     ErrInvalidBusiness → 400 매핑
backend/internal/api/service_business_test.go    신규 — API 8건(권한·통교체·클로버·노출범위·무인증)
backend/internal/store/store.go                  Get/SaveBusiness 인터페이스
backend/internal/store/memory.go                 businesses 맵
backend/internal/store/firestore.go              Get/SaveBusiness + SavePolicy 머지 전환
backend/internal/store/conformance_test.go       BusinessAndPolicyDoNotClobberEachOther
admin/src/lib/types.ts                           CenterBusiness · CenterBusinessView · 라벨/상수/미기재 미러 · EMPTY_BUSINESS
admin/src/lib/api.ts                             updateCenterBusiness(통 교체)
admin/src/lib/queries.ts                         useUpdateCenterBusiness
admin/src/features/Settings.tsx                  사업자 정보 카드 + BusinessEditForm + 칸별 검증 미러
admin/public/legal/{terms,privacy,sensitive-consent,account-deletion,index}.html
docs/API계약_v1.md                                v2.13
work_log/README.md                               P27 인덱스
```

### 어드민에서 추가로 막은 것

- `pickBusiness()` — 응답의 파생값 `complete`를 벗기고 12칸만 보낸다. 그대로 되돌려 보내면
  `DisallowUnknownFields`가 요청 전체를 400으로 떨군다(실측 확인).
- `EMPTY_BUSINESS` + `businessOf()` — 배포 순서가 뒤집혀 `business`가 없는 응답이 오면 **설정
  화면 전체가 흰 화면**이 된다(직원·정책·가입 승인까지 같이 죽는다). 미등록과 같은 모양으로
  접어 장애를 "아직 등록 전"으로 바꿨다.
- 사업자등록번호 체크디짓은 **경고만** — D7 참고.

## 검증

### 뮤테이션 13/13 kill

| # | 무력화한 가드 | 죽인 테스트 |
|---|---|---|
| M1 | `IsComplete` 부분입력을 완성으로 | `TestBusinessPartialIsNotComplete` |
| M2 | 사업자등록번호 자릿수 검사 제거 | `TestBusinessRegNoFormat` |
| M3 | 이메일 형식 검사 무력화 | `TestBusinessEmailFormat` |
| M4 | 시행일 YYYY-MM-DD 검사 제거 | `TestBusinessEffectiveDateFormat` |
| M5 | 빈 레코드 저장 금지(미등록을 오류로) | `TestBusinessEmptyIsValidButNotComplete` |
| M6 | 공백만 있는 칸을 채워진 것으로 | `TestBusinessWhitespaceOnlyIsMissing` |
| M7 | 대표 전화 형식 검사 제거 | `TestBusinessPhoneFormat` |
| M8 | 공개 응답에 정책 노출 | `TestPublicBusinessNeedsNoAuth` |
| M9 | complete 무조건 true | `TestPublicBusinessEmptyWhenUnregistered` |
| M10 | PUT이 보낸 덩어리만 처리 → 항상 둘 다 | `TestPolicyUpdateDoesNotWipeBusiness` |
| M11 | 사업자 정보 편집 owner 게이트 제거 | `TestUpdateCenterBusinessOwnerOnly` |
| M12 | 통 교체 → 머지 | `TestCenterBusinessReplacesNotMerges` |
| M13 | `SavePolicy` 머지 → 통 `Set` (**Firestore 에뮬레이터**) | `Conformance/BusinessAndPolicyDoNotClobberEachOther` |

M13은 Memory에서 재현되지 않는 종류다. 에뮬레이터에서 되돌리자 사업자 정보가 **전 칸 빈 값**
으로 돌아왔다 — 이 갈래에서 가장 값어치 있는 확인이었다.

### 법정 문서 4상태 실측 (실제 서버 :8099 + 배포되는 HTML에서 스크립트를 그대로 추출해 실행)

| 상태 | 채워짐 | 초안 배너 | 중괄호 노출 |
|---|---|---|---|
| A 미등록(0칸) | 0/60 | 유지 | 없음 |
| B 부분 입력(4칸) | 29/60 | 유지 | 없음 |
| C 완성(12칸) | 60/60 | **자동 제거** | 없음 |
| D fetch 실패(서버 다운) | 0/60 | 유지 | 없음 |

빌드 산출물(`admin/dist/legal/`)로도 같은 확인 — 60/60 채움 · 배너 제거 · 중괄호 0.

### 게이트

```
backend   go build ./... · go vet ./... · go test ./...        전부 그린
          firebase emulators:exec ... -tags firestore_emulator  그린(10.2s, 동시성 포함)
admin     npx tsc --noEmit                                     출력 없음
          npm run build                                        ✓ built (703.27 kB — 500 kB 경고는 기존)
```

### 통합 실측(실서버 :8099)

```
어드민이 실제로 보내는 12키 바디            → 200
complete를 되돌려 보낸 바디(pickBusiness 없었다면) → 400 "지원하지 않는 필드가 포함돼 있어요"
trainer의 사업자 정보 수정 시도             → 403
```

## 후속 작업

- 람이 어드민 **설정 → 사업자 정보**에 12칸 등록 + 약관 시행일 지정 → 배포 → 스토어 등록
  (P22 체크리스트 6번이 여기서 닫힌다)
- 사업자등록번호는 어드민 경고만 뜨므로 **사업자등록증과 사람이 대조**해야 한다
- 문서 본문(약관 조항 자체)의 법적 타당성은 이 작업 범위 밖 — 여전히 사람 검토 필요

## 참조

- P26(앱 약관 접근)이 **같은 문서를 앱에서 연다** — 이 갈래가 채우는 값이 그 화면에 그대로 보인다

- work_log/P22-legal-documents.md — 플레이스홀더를 남긴 갈래
- docs/API계약_v1.md v2.13
