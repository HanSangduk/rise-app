---
id: P24
title: Home Work 세트·횟수 소실(회원 앱에 처방이 안 보이던 결함)
status: 완료
domain: app
created: 2026-08-25
completed: 2026-08-25
---

# P24 — Home Work 세트·횟수 소실

## 목표

[P21 감사](P21-hollow-feature-audit.md)가 후속 목록 ②로 남긴 "홈워크 sets/reps 소실"을 닫는다.

코치가 배정한 처방(몇 세트 · 몇 회)이 회원 앱 어디에도 표시되지 않았다. 회원이 보는 건
운동 **이름뿐**이라 "플랭크"를 몇 세트 몇 초 하라는 건지 앱 안에서 알 방법이 없었다.
배정의 알맹이가 처방인데 그 알맹이만 빠진 상태.

## 결정 사항

### 1. 서버·DTO는 무결 — 손실은 **앱 도메인 경계 한 곳**

계약(`docs/API계약_v1.md` v1.3)과 서버를 먼저 확인했고, 둘 다 정상이었다:

- 계약: `Homework.items[].sets`는 int, `reps`는 **문자열**("10-12"·"30초"·"각 15회")
- Go `domain.HwItem`: `Sets int` / `Reps string` — JSON 태그 정상
- `Service.ListHomeworks`의 role=member 가림막은 `target_member_ids`·`excluded`만 지운다
  (P39 민감정보) — `items`는 손대지 않는다
- Flutter `HomeworkItemDto`: `sets`·`reps` 둘 다 받고 있었고 codegen도 정상

**서버 수정은 필요 없다.** 손실은 DTO→도메인 매핑 한 줄에서 났다.

### 2. `sets`의 0과 null을 같게 취급

미지정의 표현이 출처마다 다르다 — 어드민 폼은 빈 칸을 `null`로 보내고(`ItemsEditor`),
Go의 `HwItem.Sets`는 int라 미지정이 zero value `0`으로 직렬화된다. 어느 쪽이 오든
"세트 개념이 없는 과제"(걷기 30분)이므로 표기에서 빠져야 한다.

### 3. 표기 규약은 기록 탭 수업기록 카드와 **동일**

`workout_log_list.dart`의 `_entryLabel`과 같은 규칙을 `HomeworkItem.prescription`에 둔다.
같은 성격의 값(sets int + reps string)이 두 화면에서 다르게 읽히면 회원이 다른 것으로
오해한다. 빈 세그먼트 조합("0×15"·"3×")을 만들지 않는 게 요점:

```
sets>0 && reps 있음 -> "3×40초"
sets>0 만          -> "3세트"
reps 만            -> "30분"
둘 다 없음          -> null (호출측이 자리를 비운다)
```

`reps`는 파싱하지 않는다 — 문자열 표기가 계약이다.

### 4. 처방은 이름과 **다른 위젯**으로 (+ 폭 상한)

이름 Text에 이어붙이면 이름·메모가 긴 항목에서 `Expanded`의 말줄임이 뒤쪽부터 먹어
정작 회원이 봐야 할 "3×40초"가 먼저 사라진다. 오른쪽 고정 + `bodyStrong`으로 분리했다
(수업기록 `RiseRow` trailing과 같은 자리·같은 강조).

**폭 상한 120은 실측 근거가 있다**: `reps`는 코치 자유 입력이라 계약상 길이 상한이 없는데,
상한 없이 두면 실기기 폭(360dp)에서 Row가 **71px 넘쳐** 카드 위에 오버플로 줄무늬가 그려진다
(기본 테스트 화면 800dp에선 재현되지 않아 놓치기 쉬운 자리 — 테스트도 360dp로 고정했다).

## 진행 단계

- [x] 계약·서버 확인 → 서버 무결 판정(수정 불필요)
- [x] 손실 지점 확정: `home_repository_impl.dart` DTO→도메인 매핑
- [x] 선작성 테스트 2파일 8건 (리포지토리 4 + 위젯 4) — RED 확인
- [x] 도메인(`sets`·`reps`·`prescription`·copyWith 보존) → 매핑 → 렌더 순으로 수정
- [x] 오버플로 실측(360dp) 후 폭 상한 + 회귀 테스트 추가
- [x] 뮤테이션 4종 kill
- [x] analyze 0 · flutter test 821 그린 · go build/test 그린

## 변경 파일

| 파일 | 변경 |
|---|---|
| `app/lib/features/home/domain/home_models.dart` | `HomeworkItem`에 `sets`/`reps` 필드 + `prescription` 게터 + copyWith 보존 |
| `app/lib/features/home/data/home_repository_impl.dart:185-186` | **손실 지점** — 매핑에 `sets`·`reps` 추가 |
| `app/lib/features/home/presentation/widgets/homework_checklist_card.dart:94` | 처방 렌더(분리 Text + 폭 상한 120 + 말줄임) |
| `app/test/features/home/data/homework_sets_reps_test.dart` | 신규 4건 |
| `app/test/features/home/presentation/widgets/homework_checklist_prescription_test.dart` | 신규 4건 |

codegen 불필요 — `HomeworkItem`은 freezed가 아닌 수기 클래스이고 DTO는 무변경.

## 검증

**뮤테이션 4/4 kill** (수정을 되돌려 테스트가 죽는지 확인 후 복구):

| # | 되돌린 것 | 결과 |
|---|---|---|
| M1 | 리포지토리 매핑의 `sets:`·`reps:` | 리포지토리 4건 전부 실패 — `Expected: <3> / Actual: <null>` (원 결함 재현) |
| M2 | `copyWith`의 `sets`·`reps` 보존 | copyWith 1건만 실패(+3 -1) — 토글 경로 정확히 조준 |
| M3 | 카드의 처방 렌더 | 위젯 3건 실패 — `Found 0 widgets with text "3×40초"` |
| M4 | `prescription`의 빈 세그먼트 가드 | `Actual: '0×30분'` — 가드가 막는 잔해 그대로 |

**최종**: `flutter analyze` 0 issues · `flutter test` **821 passed / 0 failed**(연속 2회 동일) ·
`go build ./...` OK · `go test ./...` 전 패키지 ok.

기준선 주의: 최초 기준선 측정은 `+804 -1`이었는데 그 실패는
`test/features/bodycheck/presentation/camera_screen_permission_test.dart`(작업 범위 밖, 다른 변경
진행 중)의 **플래키**였다 — 단독 3회 재실행 6/6 통과, 최종 전체 실행에서도 그린. 실패가 그 파일
나머지를 중단시켜 카운트가 눌렸던 것이고, 본 작업과 무관하다.

## 후속 작업

- P21 후속 목록의 나머지: ① 스토어 심사 3종 ③ 계약 서명 후 재열람 ④ Pass 만료 파생 상태
  ⑤ 체크인 읽기 경로
- 어드민 `Homework.tsx`는 이미 sets/reps를 편집·전송한다 — 앱만 못 받던 구조라 추가 작업 없음

## 참조

- 감사 출처: [P21-hollow-feature-audit.md](P21-hollow-feature-audit.md) 후속 ②
- 계약: `docs/API계약_v1.md` v1.3 "Homework.items[].reps = string"
- 표기 규약 원본: `app/lib/features/records/presentation/widgets/workout_log_list.dart` `_entryLabel`
