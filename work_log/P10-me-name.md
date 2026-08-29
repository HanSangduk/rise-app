---
id: P10
title: /v1/me 에 표시 이름 추가 — 두 계층이 같은 우회를 하고 있었다
status: 완료
domain: cross
created: 2026-08-23
completed: 2026-08-23
---

# P10 — `Me.name`

## 목표

`GET /v1/me`가 이름을 주지 않아 **앱과 어드민이 각자 다른 우회**를 하고 있다. 하나를 추가해 둘을
동시에 없앤다.

- **앱**(P09 실기기 점검에서 발견): 세션 복원 후 홈 헤더가 "김민지 님"이 아니라 **센터명**으로
  떨어진다. 최초 로그인 때는 매칭 응답에 이름이 있어 보이지만, 앱을 껐다 켜면 `/v1/me`만으로
  세션을 세우므로 이름이 없다. 같은 화면이 실행 시점에 따라 다르게 보인다.
- **어드민**(P08에서 확인): 헤더가 이메일 원문(`rizejoy91@gmail.com`)을 노출하던 것을,
  `GET /v1/staff` 목록을 받아 `uid → 이름`으로 조인해 우회 중이다
  (`Dashboard.tsx`의 `staffName.get(me.uid)`). 이름 하나 때문에 목록 조회에 의존한다.

## 결정 사항

- **이름 조회는 best-effort — 실패해도 `/v1/me`는 성공한다.** 이 엔드포인트는 모든 클라이언트가
  가장 먼저 부르는 부트스트랩이라, 여기서 에러를 올리면 앱은 온보딩을 시작조차 못 하고 어드민은
  로그인 화면에 갇힌다. 표시용 이름 하나 때문에 그 위험을 질 이유가 없다. 조회 실패·레코드 부재는
  빈 값으로 두고 클라이언트가 기존 폴백을 쓴다(`omitempty`).
- 출처는 역할로 가른다 — staff면 `Staff.name`, 연결된 member면 `Member.name`. 미연결 계정은 없음.
- `Me`가 순수 Principal 투영이었으므로 **시그니처에 ctx를 추가**했다(스토어 접근 필요).
  호출부는 핸들러 1곳뿐이라 파급이 없다.

## 진행 단계

- [x] 1. 계약 v2.2 정의(엔드포인트 요약 줄 + 전용 절)
- [x] 2. 백엔드 — `Me`가 스토어에서 이름을 채운다(best-effort) + 회귀 4케이스
- [x] 3. 앱·어드민 소비(2팀 병렬)
- [x] 4-1. 배포(rev 00011) + **프로덕션 확인** — 실제 로그인 후 `/v1/me`가
      `{"...","name":"김민지"}` 반환. 미연결·유령 스태프에서도 호출 성공 확인(테스트).
- [x] 4-2. 3계층 매트릭스 + 실기기 확인 + 문서 마감

## 변경 파일

**backend** — `api/service.go`(`MeResponse.Name` + `Me(ctx, p)` 스토어 조회) ·
`api/handlers_me.go`(ctx 전달) · `api/service_test.go`(`TestMeCarriesDisplayName` 4케이스)

**app** — `core/api/dto/join_dto.dart`(`name` **nullable** — 기본값을 주면 "best-effort"가
타입에서 사라진다) · `auth/data/auth_repository_impl.dart`(경계 한 곳에서 정규화) ·
`core/session/app_session.dart`(`withMemberName`) · `auth/presentation/auth_view_model.dart`
(두 세션 생성 지점 통합) · 테스트 신규 2·수정 2(총 **286 passed**)

**admin** — `lib/types.ts`(`Me.name?`) · `lib/format.ts`(`firstNonEmpty`) ·
`lib/queries.ts`(`useStaff(enabled)`) · `App.tsx`(헤더 우선순위 + 조건부 조회) ·
`features/Dashboard.tsx`(myName 통일) · `lib/auth.tsx`(**`refreshMe`** — 실패해도 세션 유지) ·
`features/Settings.tsx`(본인 정정 시 헤더 갱신)

**docs** — `API계약_v1.md` 엔드포인트 요약 줄 + **v2.2 절**

## 검증

- backend `gofmt` 클린 · `go test ./... -race` 4패키지 그린 · 신규 `TestMeCarriesDisplayName`
  (스태프 이름 · 회원 이름 · **미연결이어도 호출 성공** · **레코드 없는 uid도 호출 성공**)
- 프로덕션(rev 00011) 실측: 테스트 번호로 로그인 → `/v1/me` → `"name": "김민지"` 확인
- app `flutter analyze` 0 issues · `flutter test` **286 passed**(P10 시작 266 → +20)
- admin `tsc` 0 · `build` 0 · 호스팅 재배포
- **실기기 합격 기준 통과** — 안드로이드 에뮬레이터에서 앱 데이터를 지우고 최초 로그인 →
  헤더 `김민지 님 · 담당 정혜린 코치`. **강제 종료 후 재실행 → 완전히 동일.**
  종전엔 이 지점에서 센터명으로 떨어졌다.

### 부수효과(정리 필요 없음, 기록만)
검증 스크립트가 끝에 테스트 계정을 지우는데, Firebase 전화 인증은 **같은 번호에 같은 uid를**
돌려주므로 그 정리가 **에뮬레이터에 로그인해 둔 세션까지 함께 끊었다**. 데모 회원·트레이너·
회원권은 그대로 남아 있고, 앱에서 같은 번호로 다시 로그인하면 매칭 → 연결로 복구된다.

## 후속 작업

- **앱: 두 경로의 출처를 통일했다**(구현팀 판단) — 최초 로그인도 매칭 응답이 아니라 `/v1/me`의
  이름을 1순위로 쓴다. 계약이 있어도 출처가 둘이면 "실행 시점에 따라 달라지는" 구조가 남기 때문.
  잔여 리스크: 서버의 best-effort 조회가 실패하면 복원 경로엔 폴백할 매칭 응답이 없어 센터명으로
  떨어진다(설계대로지만 그 순간엔 여전히 다르게 보인다).
- **어드민: `useStaff`를 지우지 않고 게이트했다**(구현팀 판단) — `name`이 best-effort라 조인을
  없애면 name 없는 응답이 곧장 이메일 원문으로 떨어져 이 우회가 막으려던 문제가 되살아난다.
  `useStaff(!meName)`로 필요할 때만 켠다. staff를 쓰지 않는 탭에서 헤더 때문에 나가던 요청은 사라짐.
- **이 변경이 만든 회귀를 함께 닫았다** — 헤더가 `me.name`을 1순위로 쓰면서, 설정에서 자기 이름을
  바꿔도 staff 캐시 무효화가 헤더에 닿지 않게 됐다. `refreshMe`(실패해도 세션 유지)를 만들어
  본인 정정 시 호출한다. `fetchMe`를 재사용하지 않은 이유는 그쪽이 실패 시 세션을 내려
  로그인 화면으로 튕기기 때문 — 이름 갱신 하나에 지기엔 큰 부작용이다.
- `NoAccess` 화면은 여전히 이메일 우선(그 화면의 목적이 "어느 계정으로 들어와 있는가"라 의도적).
- 퇴사자 본인 헤더엔 `(퇴사)`가 붙지 않는다(종전 조인도 원본 이름을 썼으므로 동작 동일).

## 참조

- work_log/P09-completeness-sweep.md 실기기 점검 절(관찰 항목)
