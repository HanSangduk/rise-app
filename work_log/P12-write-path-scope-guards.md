---
id: P12
title: 쓰기 경로 담당 경계 4곳 — 읽기는 촘촘한데 쓰기가 뚫려 있었다
status: 완료
domain: backend
created: 2026-08-23
completed: 2026-08-23
---

# P12 — 쓰기 경로 권한 구멍(H1·H2·H3·M3)

## 목표

감사에서 **curl 실측(DEV_SEED=true)으로 전부 재현된** 쓰기 경로 4곳을 막는다. 공통 증상은
하나다 — 목록·조회 계열은 `memberScopeID`/`checkMemberScope`로 촘촘한데, 같은 리소스의
**생성 경로만 스코프를 안 본다**. 그래서 "화면엔 안 보이는데 만들 수는 있는" 레코드가 생겼다.

| # | 자리 | 실측 | 파급 |
|---|---|---|---|
| H1 | `CreateWorkoutLog` | t2 → t1 담당 회원에 `booking_id` 없이 생성 → **200** | 회원 앱에 모르는 코치의 수업기록 |
| H2 | `CreateHomework` | t2 → `my_members` + 남의 부상회원 ID → **200, excluded:null** | P39(부상 회원 금기 운동 배정)가 통째로 우회 |
| H3 | `CreateHwCheck` | 없는 `hw_id` → 200 · `date` 생략 → `date:""` | 화면엔 미완료, 통계엔 완료(정반대) + 남의 완료율 조작 |
| M3 | `Checkin(tap)` | t2 → t1 담당 예약 체크인 → 200 + `last_visit_at` 갱신 | 장기미출석 통계 오염 · 같은 예약의 세 액션이 서로 다른 권한 |

## 결정 사항

- **새 권한 패턴을 만들지 않는다.** 네 곳 모두 이미 있는 헬퍼(`checkMemberScope`,
  `p.IsTrainer() && x.TrainerID != p.UID`)를 그대로 쓴다. 읽기 경로가 이미 정답을 갖고 있었다.
- **H1은 `booking_id` 유무로 판정을 가른다.** 회원은 코치별로 패스를 따로 가질 수 있어(앱 패스
  스위처) `mem.trainer_id`(주담당)와 그 회차를 실제로 가르친 코치가 다를 수 있다. `booking_id`가
  있으면 기존 교차검증이 더 정확하고, 없으면 담당 경계가 유일한 방어선이다.
- **H2는 "후보와 부상 맵을 같은 집합에서 뽑는다"가 본질.** 종전엔 후보=요청 배열, 부상 맵=pool로
  출처가 둘이라 pool 밖 ID가 두 검사를 동시에 빠져나갔다. `resolveHomeworkTargets`가 요청 ID를
  **회원 레코드로 되돌리고**, 그 레코드가 그대로 `ResolveTargets`의 members 인자가 된다.
  - `individual`도 담당 경계는 건다(미존재 ID는 404). **부상 자동제외는 여전히 안 건다** —
    P39의 의도된 규칙("개인 지정은 코치가 인지하고 고른 것", `ResolveTargets` 주석)이라 유지.
  - `my_members`의 subset은 `trainerID`의 담당인지까지 본다. owner 대행이 `checkMemberScope`를
    전부 통과하므로, subset 없는 경로의 pool(`ListMembers(trainerID)`)과 어긋나지 않으려면 필요.
- **H3의 빈 date는 400이 아니라 오늘(KST)로 채운다.** 근거는 세 가지 —
  ① 같은 파일 `CreateWorkoutLog`가 이미 "생략=오늘, 형식불량=400"이고 두 쓰기 경로가 같은
  이름의 필드를 다르게 다루면 그 자체가 함정, ② 체크는 회원이 이미 화면에서 누른 행동이라
  (앱은 낙관적 갱신 후 실패 시 롤백) 서버가 아는 값 때문에 되돌릴 이유가 없다,
  ③ 실제 해악은 "클라이언트가 date를 안 보냈다"가 아니라 **"어떤 질의로도 찾을 수 없는 레코드가
  저장됐다"**였다 — 문서 ID가 (회원,배정,날짜) 합성 키라 `date:""`는 앱의 `?date=오늘`에 영원히
  안 잡히는데 `homeworkCompletion`은 날짜를 안 보고 `anyDone`만 세서 완료로 집계했다.
- **H3의 `done` 길이 = 배정 항목 수 강제.** 앱은 `hw.items` 인덱스 순서로 배열을 만든다
  (`home_repository_impl.dart`) — 길이가 어긋나면 인덱스가 밀려 다른 운동이 완료로 표시된다.
- **`hwDeliveredTo`를 읽기·쓰기가 공유한다.** `ListHomeworks`의 배달 판정(center_notice는 명단
  밖도 배달, excluded는 어디서도 미배달)을 함수로 뽑아 `CreateHwCheck`가 같은 걸 본다.
  읽기와 쓰기가 다른 판정을 쓰면 "목록엔 없는데 체크는 되는" 상태가 다시 생긴다.
- **M3에 시간창 검증은 넣지 않았다**(후속 참조) — 담당 경계와 달리 운영 흐름(늦게 온 회원의
  데스크 체크인)을 깨뜨릴 수 있어 별도 판단이 필요하다.

## 진행 단계

- [x] 1. 실패하는 테스트 4건 선작성 → 4/4 실측 재현(전부 `<nil>`, want 403/404)
- [x] 2. H1·H2·H3·M3 수정(기존 헬퍼 재사용)
- [x] 3. 뮤테이션 검증 10/10 kill + 전체 회귀(`go test ./... -race` 그린)
- [x] 4. 계약 변화 정리(문서 반영은 요청자)

## 변경 파일

**backend** — `internal/api/service.go`
(`Checkin` tap 담당 경계 · `CreateWorkoutLog` booking 없는 경로 `checkMemberScope` ·
`hwDeliveredTo`/`memberIDs`/`resolveHomeworkTargets` 신규 · `CreateHomework` pool 일원화 ·
`CreateHwCheck` 배정 실존·배달 대상·done 길이·date 검증 · `ListHomeworks` 판정 함수 공유) ·
`internal/api/service_scope_test.go`(신규 — 회귀 4건)

## 검증

- **선작성한 테스트 4건이 수정 전 전부 실패**(감사 실측 그대로 재현: 403이어야 할 자리가 `<nil>`)
  → 수정 후 4/4 통과.
- **뮤테이션 검증 10/10 kill.** 고친 가드를 하나씩 되돌려 해당 테스트가 실제로 깨지는지 확인
  (원본 트리는 다른 에이전트가 동시 편집 중이라 스냅샷 사본에서 수행, 검증 후 사본 폐기):

  | 되돌린 가드 | 결과 |
  |---|---|
  | tap 체크인 담당 경계 | FAIL(kill) |
  | 수업기록 `checkMemberScope`(정확히 원상복구 — `_ = mem`) | FAIL, `= <nil>`로 **원래 버그 재현** |
  | 배정 대상 담당 경계 | FAIL(kill) |
  | my_members subset ∩ pool(코치 일치) | FAIL(kill) |
  | 후보를 요청 배열 그대로(부상 맵과 출처 분리) | FAIL(kill) |
  | hw 실존·배달 대상 검사 | FAIL(kill) |
  | 대행 입력 담당 경계 | FAIL(kill) |
  | 빈 date 그대로 저장 | FAIL(kill) |
  | done 길이 검사 | FAIL(kill) |
  | (기준선/복구) | PASS/PASS |

  첫 시도에서 H1 뮤테이션이 **엉뚱한 자리**를 건드렸다(`if req.BookingID == "" {`가 `Checkin`에도
  있어 perl이 앞쪽 것을 바꿨다) — 그때만 테스트가 통과해서 잡아냈다. 앵커를 유일하게 바꿔 재실행.
- `gofmt -l internal/` 클린 · `go build ./...` · `go vet ./...` · `go test ./... -race` 4패키지 그린.

## 계약에 반영이 필요한 변화(문서 수정은 요청자)

```
POST /v1/workout-logs      booking_id 없이 보내면 담당 회원만 가능(trainer). booking_id가 있으면
                           종전대로 예약 기준 판정 — 담당 아닌 코치도 **자기 예약**엔 기록 가능
POST /v1/homeworks         target_member_ids 검증: 미존재 404 · 스코프 밖 403 ·
                           my_members의 subset은 trainer_id 담당과의 교집합 ·
                           individual은 target_member_ids 필수(빈 배열 400) · 중복 ID는 1건으로
POST /v1/hw-checks         hw_id 실존(404) · 그 회원에게 배달되는 배정이어야 함(403) ·
                           done 길이 = items 수(400) · date 생략=오늘(KST), 형식 불량 400 ·
                           스태프 대행은 담당 회원만(403)
POST /v1/checkin (tap)     trainer는 본인 담당 예약만(403) — complete/noshow와 동일 규칙
```

## 후속 작업

- **tap 체크인 시간창**: `self_qr`은 ±30분(`domain.ValidateSelfCheckin`)인데 tap은 무제한이다.
  운영상 지각 체크인을 막을 수 있어 이번엔 손대지 않았다 — 정책 판단 필요.
- **미래 날짜 hw-check**: `homeworkCompletion`이 날짜를 안 보므로 미래 날짜 체크로 완료율을
  미리 올릴 수 있다. 단말 타임존이 KST보다 앞선 사용자를 거부하게 될 위험이 있어 보류.
- **`individual` scope의 부상 미필터**: 규칙상 의도된 것이지만, 코치가 부상 사실을 모른 채
  개별 배정하는 경우엔 안전망이 없다. 앱/어드민이 배정 UI에서 부상 플래그를 노출하는 편이 맞다.

## 참조

- `docs/API계약_v1.md` v1.3(홈워크 배달 규칙) · v1.5(tap 체크인 confirmed 제한)
- `internal/domain/homework.go` `ResolveTargets` — scope별 부상 필터 규칙의 출처
