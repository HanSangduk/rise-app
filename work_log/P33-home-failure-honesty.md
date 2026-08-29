---
id: P33
title: 홈 — 모르는 걸 사실처럼 말하지 않기
status: 진행 중
domain: app
created: 2026-08-29
completed:
---

## 목표

P32 교차검증이 남긴 세 건. 공통점이 있다 — **셋 다 앱이 모르는 것을 아는 척하거나,
실패를 숨긴다.**

| # | 증상 | 회원이 겪는 일 |
|---|---|---|
| ① | `/v1/center` 실패 시 폴백 정책을 **사실처럼** 표시 | "24시간 전까지 취소 가능"을 믿고 30시간 전에 취소했는데 차감된다(센터 실제 기준이 48시간이면) |
| ② | 회원권 칩 탭 실패가 **홈 전체를 에러 화면으로** 교체 | 잘 보고 있던 홈이 통째로 사라지고 "다시 시도" 버튼만 남는다 |
| ③ | 만료 회원권 상태에서 새로고침 실패가 **화면에 안 보임** | 새로고침을 눌러도 아무 반응이 없다 — 앱이 멈춘 걸로 읽힌다 |

## 결정 사항

### D1. 폴백은 "값"이 아니라 "모름"이다

`centerPolicyProvider`가 조회 실패 시 `CenterPolicy.fallback`(24h/2회/30일)을 돌려주는데,
받는 쪽은 그게 **서버가 준 값인지 폴백인지 구별할 방법이 없었다.** 그래서
`next_booking_card`가 `'$cutoffHours시간 전까지 취소 가능'`을 그대로 찍는다.

**폴백 자체는 옳다** — 값이 없다고 화면을 못 그리게 하면 더 나쁘다. 문제는 그 값에
**출처 표시가 없다**는 것이다. `isFallback`을 달아서, 모르는 상태에서는 **숫자를
말하지 않는다.**

### D2. 실패했다고 보고 있던 것을 뺏지 않는다

`selectPass`가 `state = result.fold(...)`로 실패를 `AsyncError`에 그대로 넣는다.
그러면 직전까지 멀쩡하던 `AsyncData`가 사라져 홈이 통째로 에러 화면이 된다.

칩 탭은 **부분 갱신**이다. 실패하면 바뀌지 않았다고 알리면 되지, 화면을 치울 이유가
없다. 이 앱엔 이미 그 규약이 있다 — Home Work 토글 실패가 스낵바로 알리고 낙관적
업데이트를 되돌린다(`homeworkToggleErrorProvider`).

### D3. 빈 상태가 실패를 삼키지 않는다

`noUsablePass ? EmptyPassesView(...) : async.when(...)` 구조라, `noUsablePass`가 참인
동안에는 **`async.when`에 아예 도달하지 않는다.** 그리고 riverpod은 새로고침 중에도
직전 값을 유지하므로(`async.value`), 만료 상태에서 새로고침이 실패하면 `noUsablePass`가
계속 참이라 에러가 영영 안 뜬다.

## 진행 단계

- [x] `CenterPolicy.isFallback` + 모르는 값 숨기기
- [x] `selectPass` 실패가 데이터를 지우지 않게
- [x] 만료 상태에서도 실패가 보이게
- [x] 뮤테이션 8종 kill · 실기기 확인

## 변경 파일

- `core/policy/center_policy.dart` — `isFallback` 신설(폴백에만 true)
- `features/home/presentation/widgets/next_booking_card.dart` — `cutoffUnknown`이면 시간을 말하지 않는다
- `features/home/presentation/home_view_model.dart` — `selectPass` 실패가 데이터를 지우지 않는다
- `features/home/presentation/home_screen.dart` — `noUsablePass`에 `!async.hasError`, 스낵바 문구 일반화

## 검증

- **앱 1,014건 그린 · analyze 무이슈 · 백엔드 무변경(빌드·테스트 통과)**
- **뮤테이션 8종 kill** — 폴백 표기 3 · 병렬 로드 3 · 화면 배선 2 + 스낵바 문구 1
- **실기기**: Wi-Fi를 끄고 회원권 칩을 눌렀더니 **홈이 그대로 남고** 하단에
  "연결이 불안정해요"만 떴다. 종전이면 화면 전체가 "다시 시도" 버튼으로 바뀌었다.

## 테스트를 두 번 썼다 — 첫 판이 헛돌았다

②·③을 처음엔 **판정 규칙을 테스트 안에서 재현해** 잠갔다. 통과했지만 뮤테이션에서
살아남았다 — 화면 배선(`home_screen.dart`)을 끊어도 규칙 사본은 그대로였기 때문이다.
**규칙을 베끼면 화면이 그 규칙을 쓰는지는 아무도 안 본다.**

진짜 `HomeScreen`을 띄우는 하네스가 이미 있어서(`no_usable_pass_view_test.dart`)
그걸 빌려 다시 썼고, 그제서야 네 뮤테이션이 전부 죽었다.

작업 중 하나 더: ③ 테스트가 **한 번짜리 실패**로는 재현되지 않았다. `pumpAndSettle`이
도는 사이 다음 로드가 성공해 상태가 되돌아갔기 때문이다. 지속 실패로 바꿔야 실제
상황(연결이 계속 안 되는 상태)이 재현됐다.

## 참조

- `docs/design/스플래쉬_교차검증.md` §B
