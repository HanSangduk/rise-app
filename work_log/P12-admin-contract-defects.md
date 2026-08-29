---
id: P12
title: 어드민 계약 결함 15건 — 요청/응답 타입 겸용이 기능 하나를 통째로 죽이고 있었다
status: 완료
domain: admin
created: 2026-08-23
completed: 2026-08-23
---

# P12 — 어드민 결함 수정(감사 어드민팀 분)

P12 전면 감사 스윕의 **어드민 팀 지적사항 15건** 수정. 백엔드 분은
[P12-write-path-scope-guards.md](P12-write-path-scope-guards.md), 감사 원본은
[P12-audit-sweep.md](P12-audit-sweep.md).

## 목표

감사에서 **백엔드 요청 구조체와 필드 단위 대조**로 확인된 어드민 결함을
CRITICAL → HIGH → MEDIUM 순으로 닫는다. 필드명·타입은 추정하지 않고
`backend/internal/api/service.go`의 실제 구조체를 읽어서 맞춘다.

## 결정 사항

### 1. `Partial<엔티티>`를 요청 타입으로 쓰던 관행을 끊었다 (근본 원인)

CRITICAL 1(Home Work 배정 전면 불능)의 원인은 오타가 아니라 **타입 설계**였다.
`api.createHomework(h: Partial<Homework>)` — `Homework` **엔티티**에 `excluded`가 있어서
(서버가 계산해 응답에만 싣는 파생값) 요청에 실어도 컴파일이 통과했다. 서버는 전 핸들러가
`DisallowUnknownFields`라 `excluded: []`만으로 400. 부상 회원이 0명이어도 빈 배열이 **항상**
나가서 어떤 입력으로도 성공할 수 없었다.

→ `types.ts`에 요청 전용 타입 4종(`HomeworkCreateRequest` · `PaymentCreateRequest` ·
`BodyPhotoCreateRequest` · `InbodyCreateRequest`)을 만들고 서버 구조체 json 태그와 1:1로 맞췄다.
왜 겸용이 위험한지도 그 자리에 남겼다 — 규칙만 적으면 다음 사람이 또 `Partial<>`을 쓴다.

**`Partial<Member>`는 그대로 뒀다.** POST/PUT `/v1/members`만은 서버가 **엔티티 자체**
(`domain.Member`)를 디코딩 대상으로 쓴다 — 엔티티의 모든 키가 곧 허용 키라 구조적으로 안전한
유일한 경우다. 일괄 변환이 아니라 경로별로 판정했다.

### 2. 같은 클래스 전수 점검 — 나머지 쓰기 경로 18곳은 깨끗했다

감사는 `excluded` 한 건만 찾았지만 재확인이 요구사항이었다. 백엔드에서
`decodeJSON`/`strictUnmarshal`을 부르는 **모든** 핸들러(29곳)를 뽑아 요청 구조체를 덤프하고
`api.ts` 시그니처와 대조했다. `excluded`가 유일한 unknown-field였다. 검증 범위:

- 익명 구조체까지 확인: `{phone}` · `{request_id}` · `{policy}` · `{offdays}` · `{to_uid}` ·
  `{left_at}` · `{profile}` · `{used}`
- 중첩 객체 json 태그 대조: `domain.StaffProfile` · `domain.Policy` · `domain.Payout` ·
  `domain.Installment` · `domain.Exercise` · `domain.HwItem`/`HwSchedule`
- 바디 없는 POST(resume·send·complete·noshow·pay·reactivate)가 `decodeJSON`을 부르지 않는지 확인

### 3. HIGH 2는 "필드 이름만 바꾸면" 안 됐다 — 무엇을 보내느냐가 바뀐다

서버는 `include`로 수동 포함을 받고 **제외를 자기가 다시 계산**한다
(`domain.ResolveTargets`). 그래서 클라이언트가 이미 걸러낸 목록(`finalTargets`)을
`target_member_ids`로 보내면 되살릴 대상이 애초에 후보에 없어 `include`가 무시된다.
→ **후보 전체**(부상 회원 포함)를 보내고 `include`로 지목하는 형태로 바꿨다.

`target_member_ids: []`(서버가 스코프 전체를 후보로)도 가능했지만 명시 목록을 골랐다:
화면이 보여준 "대상 N명"과 서버가 실제로 배정한 대상이 어긋나지 않고, 백엔드에서 동시에
진행 중인 `target_member_ids` 검증 강화가 "비어 있으면 거부" 방향이어도 깨지지 않는다.

### 4. HIGH 3은 지표 정의 자체를 바꿨다

분모가 "제출된 체크의 칸 수"라 미참여자가 통계에서 사라졌다(10명 중 1명이 3항목 체크 →
`3/3` 100% 초록). 더 나쁜 건 **이탈할수록 분모가 줄어 완료율이 올라간다**는 점 — 바로 아래
"완료율 하락은 이탈 신호" 카피가 가리키는 지표가 구조적으로 하락 불가였다.

→ 분모 = **배정 인원**(서버가 확정한 `target_member_ids − excluded`), 분자 = 완료 체크를
1개 이상 남긴 배정 회원 수. 항목 단위 집계는 버리지 않고 펼침 영역의 보조 지표로 내렸다.
표시는 `format.ts ratioState` 3상태 규약(value / none / unknown)에 태웠다 — 이 화면만 규약
밖이었다. 분모를 모르는 자리(조회 실패·로딩)엔 **게이지를 그리지 않는다**. 빈 게이지는 0%로
읽히기 때문이다.

### 5. 파괴적 액션 3종에 같은 2단 확인 패턴을 붙였다

노쇼·취소(`Schedule`)·납부 처리(`Members`) — 셋 다 원장/미수금을 바꾸는데 **서버에 되돌리는
동사가 없다**. 같은 코드베이스가 훨씬 덜 파괴적인 고정 스케줄 삭제·환불에는 이미 2단 확인을
붙여뒀다. 새 패턴을 만들지 않고 그 `confirmId`/확인 박스 모양을 그대로 재사용했다.

문구는 결과를 구체적으로 적었다("세션 1회가 차감되고 되돌릴 수 없어요"). 취소는 "페널티 없이
취소" 체크 여부로 문구를 갈라, 무차감인지 차감인지를 누르기 전에 알 수 있게 했다.

### 6. Go의 nil 슬라이스 마샬링 방어를 함께 넣었다

`domain.Homework.Excluded`/`TargetMemberIDs`, `HwCheck.Done`은 omitempty가 없어 비어 있으면
`[]`가 아니라 **`null`**로 온다. `ResolveTargets`는 제외자가 없으면 `excluded`를 nil로 돌려주므로
**정상 배정에서도** `excluded: null`이 실려 온다 — 종전 코드는 그 행에서 `.includes()`로
화면이 죽었다(감사 리포트에 없던 건). TS 타입이 `string[]`이라 컴파일러가 못 잡는 자리다.

## 진행 단계

- [x] 백엔드 요청 구조체 전수 덤프 + `api.ts` 대조
- [x] CRITICAL 1 — 요청/응답 타입 분리 + `excluded` 제거
- [x] HIGH 2 — `include` 전송 + 후보 전체 전송으로 전환
- [x] HIGH 3 — 완료율 분모를 배정 인원으로, `ratioState` 적용
- [x] HIGH 4 — 노쇼·취소 2단 확인
- [x] HIGH 5 — 납부 처리 2단 확인 + 회차별 pending/에러
- [x] MEDIUM 6~15 (전부)
- [x] `npm run build`(tsc × 2 + vite) 통과

## 변경 파일

| 파일 | 내용 |
|---|---|
| `admin/src/lib/types.ts` | 요청 전용 타입 4종 신설 + "왜 겸용 금지인지" 규약 주석 |
| `admin/src/lib/api.ts` | `createHomework`/`createPayment`/`createBodyPhoto`/`createInbody` 시그니처 교체 |
| `admin/src/lib/queries.ts` | 위 3훅 타입 교체 · `useCreatePass`에 `["contracts"]` 무효화 추가(M8) |
| `admin/src/features/Homework.tsx` | C1 · H2 · H3 · M11 · M12 · M15 + nil 슬라이스 방어 |
| `admin/src/features/Schedule.tsx` | H4 · M6 · M11 · M14 |
| `admin/src/features/Members.tsx` | H5 · M7 · M10 · M13 |
| `admin/src/features/BodyPhotos.tsx` | M9 · M11 |

## 검증

- `npm run build` (= `tsc -p tsconfig.json && tsc -p tsconfig.node.json && vite build`) 통과.
  `strict` + `noUnusedLocals` + `noUnusedParameters` 켜진 설정.
- 백엔드 쓰기 핸들러 29곳 × 요청 구조체 대조 — unknown-field 잔여 0건.
- 라우팅 파일(`App.tsx`)·신규 `CheckinQr.tsx`는 건드리지 않음(동시 작업 회피).

## 후속 작업

**백엔드에 요청하고 싶은 변화 3건** (전부 어드민만으로는 못 닫는다):

1. **납부 취소 동사가 없다.** `POST /v1/payments/{id}/installments/{i}/pay`의 역동사가 없어
   오클릭이 곧 완납 확정 + 미수금 KPI 오염이다. 2단 확인은 완화지 해결이 아니다.
   원장주의를 따른다면 삭제가 아니라 `unpay`(취소 표식) 형태가 맞다.
2. **노쇼·취소의 되돌리기가 없다.** `LedgerReason`에 `revert`(취소 복구)가 이미 있는데 그걸
   만드는 API가 없다. 어드민은 "되돌릴 수 없어요"라고 안내하는 것 말고 할 수 있는 게 없다.
3. **`HomeworkCreateRequest.target_member_ids`의 의미가 응답 필드와 다르다**(요청=후보,
   응답=해석 결과). 같은 이름이 두 뜻인 게 이번 사고의 배경이다. 요청 쪽을
   `candidate_member_ids`로 개명하면 클라이언트가 다시 헷갈릴 여지가 사라진다(계약 변경 필요).

**어드민 잔여**: 없음(15건 전부 처리).

## 참조

- `backend/internal/api/service.go` — `HomeworkCreateRequest`(1514) · `PaymentCreateRequest`(1813)
  · `RefundPass` used 정합 검사(826) · `PayInstallment` 멱등 가드(1890)
- `backend/internal/api/util.go:144` — `decodeJSON` + `DisallowUnknownFields`
- `backend/internal/domain/homework.go:52` — `ResolveTargets`(include 오버라이드)
- `admin/src/lib/format.ts:25` — `ratioState` 3상태 규약
