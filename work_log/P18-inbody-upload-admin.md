---
id: P18
title: 인바디 수기 입력 v1 — 어드민(폼 v2.9 정합·행 삭제·409 동선)
status: 완료
domain: admin
created: 2026-08-23
completed: 2026-08-23
---

# P18 — 인바디 수기 입력 v1(어드민)

## 목표

백엔드 갈래([P18 백엔드](P18-inbody-upload-backend.md))가 v2.9로 깐 안전장치(6지표 범위+교차
검증 · 미래 측정일 400 · 같은 날 중복 409 · `DELETE /v1/inbody/{id}` · `source` Principal 판정)에
**어드민 인바디 입력 폼을 정합**시킨다. 적대적 검증 CRITICAL — 이대로 백엔드를 배포하면
어드민 입력이 100% 실패한다(홈워크 unknown-field 사태와 같은 클래스).

착수 전 실제 상태(코드 확인, 추정 아님):

| 결함 | 코드 근거 |
|---|---|
| 6칸 전부 `useState(0)` 시작 + 제출 게이트가 `weight <= 0` **하나뿐** | `BodyPhotos.tsx` InbodyForm — 체중만 채우면 나머지 5칸이 0으로 전송돼 서버 v2.9에서 **무조건 400** |
| 안내 문구가 "체중만 필수"라고 단정 | "체중(kg)을 입력하면 기록할 수 있어요 — 0kg 기록 방지" |
| 측정일 `<Input type="date">`에 `max` 없음 | 미래일 선택 가능 → 서버 400 |
| 인바디 **삭제 경로가 어드민에 0개** | `api.ts`에 `inbody`(GET)·`createInbody`(POST)뿐 — 중복이 409로 막히고 PUT이 없으니 그날 오타를 고칠 수단이 없다 |
| VFL cm² 오기 힌트가 사용자에게 도달 불가 | 서버 힌트는 상한 초과 400에만 실리는데, 클라이언트 사전 검증이 요청을 막으면 영영 안 보인다 |

## 결정 사항

### 1. 범위 미러는 **서버 코드에서 옮겨 적고 출처 주석** — 서버가 진실

`INBODY_FIELDS` 표(6지표 × min/max/unit/overMaxHint)를
`backend/internal/domain/measurement.go`의 `inbodyRanges`에서 그대로 옮겼다:

| 지표 | 범위 | 상한 초과 힌트 |
|---|---|---|
| 체중 | 20~300 kg | — |
| 골격근량(SMM) | 5~120 kg | — |
| 체지방량(BFM) | 1~200 kg | "제지방량(FFM) 칸이 아니에요" |
| 체지방률(PBF) | 1~70 % | — |
| 내장지방레벨(VFL) | 1~30 | "내장지방'레벨'이에요 — 단면적(cm²)이 아니에요" |
| 기초대사량(BMR) | 500~5000 kcal | — |

라벨 문자열도 서버 에러 문구의 지표명과 동일하게 맞췄다 — 미러가 어긋나 서버 400이 새어
나와도 사용자가 어느 칸인지 바로 짚을 수 있다. 어긋남의 최종 판정은 항상 서버(400 문구 그대로
노출).

### 2. 빈 칸은 에러가 아니라 미완성 — 6칸 빈 입력 시작

`useState(0)` → `useState("")`(문자열 상태). 빈 칸은 붉히지 않고 버튼만 잠근다(입력 전부터
6칸이 새빨간 폼은 사용자를 혼내는 폼). 값이 있으면 서버와 같은 범위로 **칸 단위** 에러를
그 칸 밑에 표시. placeholder에 범위(`20~300kg`)를 상시 노출. 이전 감사에서 LOW로 지적된
"0 채움 UX"도 이걸로 함께 해소.

### 3. 교차 검증 미러 — 서버와 같은 순서·같은 문구·같은 부동소수점

`inbodyCrossError`: `smm >= weight` → `bfm >= weight` → `smm+bfm > weight`(서버
`domain.Inbody.Validate()`와 동일 순서, 문구 동일). 개별 범위를 통과한 뒤에만 본다(서버도
범위가 먼저). 덧셈이 양쪽 다 IEEE754 배정밀도(Go float64 = JS number)라 경계값에서 서버와
판정이 갈리지 않는다 — 엡실론 보정을 **일부러 안 넣었다**(넣으면 오히려 서버와 어긋난다).

### 4. VFL 힌트는 에러 이전에 **상시 노출**

서버 힌트는 상한 초과 400에만 실리는데 사전 검증이 요청을 막으면 도달 불가(MEDIUM 지적).
VFL 칸 헬퍼 텍스트로 "'레벨'(1~30)이에요 — 결과지의 단면적(cm²)이 아니에요"를 상시 표시
(인바디 770 등은 결과지에 cm² 단면적이 100 근처로 찍혀 그대로 옮겨 적는 실수가 실제로 난다).

### 5. 삭제 = confirmId 2단 확인 + 409 동선 완성

- `api.deleteInbody(id)`(`DELETE /v1/inbody/{id}`, 응답 `{deleted:true}`) +
  `useDeleteInbody({id, memberId})` — 목록 캐시가 회원 단위 키라 memberId로 무효화.
- `InbodyList`에 행 단위 삭제: Schedule.tsx 고정 스케줄 삭제와 같은 confirmId 규약
  (행 강조 → "확인 중 ↓" → 하단 확인 박스 → 삭제 확정/돌아가기, pending 중 잠금,
  openConfirm에서 `reset()`으로 앞 삭제의 에러 문구 청소).
- 확인 문구는 결과를 구체적으로: 날짜 + 값 3개 요약, "되돌리는 기능이 없어요", "지운 뒤 위
  폼에서 같은 날짜로 다시 입력하면 돼요"(같은 날 저장이 막혀 있어 삭제가 정정의 유일한 방법).
- **409 동선**: 409 → 서버 문구(날짜 명시) + 폼 밑에 "아래 목록에서 그 날짜 행을 삭제한 뒤
  다시 저장" 안내(ApiError.status === 409 판별) → 목록은 날짜 내림차순이라 행을 바로 찾는다
  → 삭제 → 입력값은 성공 전엔 지우지 않으므로 "기록 추가" 재클릭으로 완결.

### 6. `source`는 응답 전용 — 요청에 싣지 않는다

`types.ts` `Inbody`에 `source: "member_self" | "staff" | ""` 추가(v2.9 응답 필드).
`InbodyCreateRequest`는 **무변경**(8키 그대로) — `DisallowUnknownFields`라 실으면 400.
목록에서 `member_self`에 "회원 입력" 배지, 삭제 확인 문구에 "회원이 직접 입력했어요 —
지우면 회원 화면에서도 사라져요"를 덧붙인다. 스태프는 스코프 안에서 출처 무관 삭제 가능
(서버 규칙)이라 배지는 차단이 아니라 **알고 지우게** 하는 장치다.

### 7. `key={memberId}`로 회원 전환 시 폼 리셋

6칸이 이제 값을 유지하므로, 회원을 바꿨을 때 앞 회원의 입력값이 다음 회원 이름으로 저장되는
사고를 리마운트로 원천 차단(뮤테이션 상태도 함께 리셋 — 앞 회원의 409 문구가 남지 않는다).

### 8. 손대지 않은 것

- `app/**` · `backend/**` 한 줄도 안 건드림(백엔드는 읽기만 — 범위·문구의 출처).
- 측정일 미래 판정의 타임존: `todayStr()`(로컬) 사용 — 어드민은 한국 데스크에서 쓰므로 서버
  KST와 같은 판. 별도 KST 고정은 넣지 않았다(코드베이스 전반이 같은 전제).
- 사진 타임라인·동의 게이트·Delta 표시는 무변경.

## 진행 단계

- [x] 서버 코드 정독 — `measurement.go` `inbodyRanges`/`Validate()`, `service.go`
      `CreateInbody`/`DeleteInbody`, `router.go` DELETE 배선, 409/400 문구
- [x] `types.ts` — `Inbody.source` 추가 + `InbodyCreateRequest` 금지 주석
- [x] `api.ts` — `deleteInbody(id)` + createInbody v2.9 주석
- [x] `queries.ts` — `useDeleteInbody`(회원 단위 캐시 무효화)
- [x] `BodyPhotos.tsx` — 폼 재작성(빈 입력 시작·칸 단위 범위 에러·교차 검증·date max·VFL
      상시 힌트·409 안내) + `InbodyList` 행 삭제(confirmId 2단) + `key={memberId}`
- [x] `npm run build`(tsc 2패스 + vite) 통과

## 변경 파일

- `admin/src/lib/types.ts` — `Inbody.source`(응답 전용 주석), `InbodyCreateRequest` 주석
- `admin/src/lib/api.ts` — `deleteInbody`, `createInbody`/`inbody` v2.9 주석
- `admin/src/lib/queries.ts` — `useDeleteInbody`
- `admin/src/features/BodyPhotos.tsx` — `INBODY_FIELDS` 미러 표(출처 주석), `inbodyFieldError`,
  `inbodyCrossError`, InbodyForm 재작성, NumField(문자열 값·에러·헬퍼), InbodyList 삭제 액션

## 검증

```
cd admin && npm run build
tsc -p tsconfig.json && tsc -p tsconfig.node.json && vite build → ✓ built in 1.67s
```

(청크 500kB 경고는 기존 노이즈 — 이번 변경과 무관.)

자문자답으로 확인한 것:
- 범위 6종·교차 3종·문구가 `measurement.go` 84~91행·117~127행과 1:1 대조로 일치.
- 요청 바디는 종전과 같은 8키 — unknown field 400 불가.
- `source`가 없는 응답(서버 v2.9 선배포 전)에서도 `undefined === "member_self"`가 false라
  배지만 조용히 빠진다(런타임 안전).
- "0" 입력 → 범위 에러 표시, 빈 칸 → 버튼 잠금 + 안내, 미래일 타이핑 → dateError(max는
  피커만 막으므로 이중 방어).
- 409 후 폼 값 보존(성공 시에만 리셋) → 삭제 후 재저장이 재입력 없이 된다.

미검증(정직하게): 실서버 상대 수동 E2E(생성 400/409/삭제 왕복)는 돌리지 않았다 — 백엔드
배포 순서(서버 먼저)에 묶여 있다. 어드민 단위 테스트 러너는 이 프로젝트에 없다(빌드가 게이트).

## 후속 작업

1. 백엔드 v2.9 배포 후 실서버로 400(범위·교차·미래일)/409/DELETE 왕복 수동 확인.
2. 서버 `inbodyRanges`가 바뀌면 `INBODY_FIELDS`를 함께 갱신(출처 주석이 그 신호).
3. 목록이 길어지면 InbodyList 페이징/최근 N건 — 지금은 전량 렌더.

## 참조

- 서버 진실: `backend/internal/domain/measurement.go`(`inbodyRanges`·`Validate()`),
  `backend/internal/api/service.go`(`CreateInbody`·`DeleteInbody`), `backend/internal/api/router.go:88-90`
- 갈래: [P18 백엔드](P18-inbody-upload-backend.md) · [P18 회원 앱](P18-inbody-upload-app.md)
- 규약 선례: `admin/src/features/Schedule.tsx` confirmId 2단 확인(고정 스케줄 삭제)
