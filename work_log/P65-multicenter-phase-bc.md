---
id: P65
title: 멀티센터 Phase B·C — 어드민 센터 생성/슈퍼어드민 UI · 센터명 동적화 · 회원 가입의 센터 차원
status: 완료
domain: cross
created: 2026-09-06
completed: 2026-09-06
---

# P65 — 멀티센터 Phase B·C (설계04 잔여 단계)

## 목표
"우리가 센터를 등록해 주면 그 센터 대표가 어드민에 들어가 자기 센터를 관리한다"를 실제로 되게 한다.
회원 앱은 등록된 센터로 자연스럽게 연결된다.

## 착수 시점 실태 (2026-09-06 확인)
- **Phase A(백엔드 관리 평면)는 완료**(P41, 계약 v2.16): `RoleSuperadmin`·`IsSuperadmin()`,
  `POST /v1/admin/centers`·`GET /v1/admin/centers`, storage.rules 센터 세그먼트 탈하드코딩.
- **Phase B(어드민 UI) 미착수**: `admin/src`에 `superadmin` 0건. 센터 생성·목록·최초 owner 초대
  화면이 없어 센터 등록이 여전히 Firestore 콘솔 수작업이다.
- **Phase C(회원앱) 부분 진행**: P56 L10이 센터 상호를 `GET /v1/public/center`에서 읽게 해
  `AppConfig.centerFullName`은 폴백으로 강등됐다.
- **남은 구조적 갭(착수 전 확인분)**: ① 가입 플로우가 `DEFAULT_CENTER_ID` 고정이라 2호점 회원의
  가입 요청이 라이즈 큐로 간다 ② `PublicBusiness`/`PublicCenter`가 `DefaultCenterID`를 하드코딩해
  법정 문서 5장이 특정 센터를 가리킨다(람 지적: "여러 센터를 쓰는 앱인데 우리 사업자명이 필요한가")
  ③ 어드민 센터명 하드코딩 3곳 ④ superadmin 부트스트랩 경로.

## 진행 단계
- [x] P 클레임 · 설계04/P41 실태 확인 · 동시 세션 조율
- [x] 1단계: 조사 — 3팀 병렬 에이전트가 **전부 사용량 한도(429)로 중단**되어 본 세션이 직접 수행
- [x] 2단계: 결정(아래) + 자문자답
- [x] 3단계: 구현(백엔드 v2.32 · 어드민 Phase B)
- [x] 4단계: 검증(테스트·뮤테이션 8/8·race·로컬 E2E 10단계·번들 실측)

## 결정 사항

### D1. 회원의 센터는 **전화번호**가 정한다 (핵심)
착수 전 "앱은 등록된 센터로 자연스럽게 될 것 같다"는 람의 가정을 검증했더니 **정반대였다.**
`JoinMatch`/`JoinConfirm`이 `Principal.CenterID`로 회원을 찾는데, 앱을 처음 켠 uid는 UserIndex가
없어 `auth.enrich`가 **`DEFAULT_CENTER_ID`("rise")를 꽂아 준다**. 즉 **2호점이 회원을 등록해도 그
회원은 앱에서 영원히 연결되지 않는다** — 센터를 만들 수 있게 해도 쓸 수가 없는 상태였다.

→ 두 endpoint가 `p.CenterID`를 **쓰지 않는다**. 검증된 번호(Firebase `phone_number`)로 전 센터를
훑어 회원이 있는 센터를 찾는다. 회원은 센터를 고르지 않는다(설계04 §4). 클라이언트가 센터를
지정하던 구멍은 P41이 봉인했고 이 경로도 같은 규율이다 — **센터는 언제나 서버가 정한다.**

- 살아 있는 회원 2건 이상 → **고르지 않고 409로 막는다.** UserIndex가 uid당 센터 1건이라
  한쪽을 고르면 그 선택이 굳고, 회원은 다니지 않는 센터의 회원권을 본다.
- **앱 변경 0.** 서버만 고쳐서 닫았다 — 제출 중인 1.0(4)를 다시 아카이브하지 않아도 된다
  (생성 파서가 미지 필드를 무시하는 것을 `join_dto.g.dart`로 확인).

### D2. `ListCenters`만 믿지 않는다 — 정반대 사고를 막은 줄
`ListCenters`는 **상호가 등록된 센터만** 돌려준다(유령 문서 거르기). 그런데 **1호 고객 라이즈가
정확히 그 상태다**(프로덕션 실측 `GET /v1/public/center` → `name:""`). 목록만 훑었다면 이 수정이
**기존 라이즈 회원 전원의 앱 연결을 끊었다.** 후보 목록에 기본 센터를 항상 먼저 넣고, 그 사실을
테스트(`TestJoinMatchStillFindsDefaultCenterWithoutIdentity`)가 잡고 있다.

### D3. superadmin은 **셸 자체를 가른다**
서버가 superadmin에게 `/v1/admin/*`·`/v1/me` 외 전부를 403으로 막으므로, 기존 NAV를 필터해
보여 주면 어느 탭을 눌러도 403 화면이다. "눌러보고 403을 받는 UI를 만들지 않는다"는 규약을
**화면 단위가 아니라 셸 단위**로 적용해 superadmin 전용 네비(센터 관리 1개)를 별도로 뒀다.
기존 owner/trainer 경험은 한 줄도 바뀌지 않는다(NAV·필터·게이트 모두 그대로).

### D4. 최초 owner를 센터 생성 폼에서 함께 받는다
닭-달걀이다: 스태프 초대(`POST /v1/staff`)는 **그 센터의 owner만** 부를 수 있어 owner 없는 새
센터에는 아무도 초대할 수 없다. 서버가 이미 role을 owner로 강제하고 있고(P41), 화면이 그 계약을
그대로 따른다. 첫 로그인은 **비밀번호 재설정**이다 — `EnsureUser`가 아무도 모르는 임시 비밀번호로
계정을 만들기 때문(provision.go 실측). 화면이 그 절차를 문장으로 안내한다.

### D5. 어드민 크롬에서 특정 센터 상호를 걷어낸다
로그인 화면이 "라이즈 컨디셔닝 센터 어드민"이라고 단언하고 있었다 — 2호점 대표가 로그인하는
화면이다. 로그인 전에는 어느 센터인지 알 방법도 없다(세션이 없다). "PT데스크 센터 어드민"으로
바꾸고, 로그인 후 사이드바가 서버 값으로 자기 센터 상호를 띄운다(종전 `centerDisplayName` 재사용).

### D6. **하지 않은 것** — 가입 요청의 센터 차원(의도적 보류)
미등록 번호의 가입 요청은 여전히 기본 센터 큐로 간다. 서버는 그 사람이 어느 센터를 원하는지
**알 방법이 없고**, 설계04 §4의 정답(센터별 초대 코드/QR)은 **앱 화면 변경**을 동반한다. 지금은
1.0(4)가 App Store 재심사 대기 중이라(P60) 앱을 흔들지 않는다. 후속 1번.

## 변경 파일
| 파일 | 무엇을 |
|---|---|
| `backend/internal/api/service_join_center.go` **신설** | 번호 기반 센터 해석 — `joinCenterIDs`(기본 센터 ∪ ListCenters, 정렬·중복 제거) · `resolveMemberByPhone`(살아있음 1/2+/탈퇴 4갈래) · `joinCenterView`(상호 없으면 생략) |
| `backend/internal/api/service.go` | `JoinMatch`·`JoinConfirm`이 `p.CenterID` 대신 번호로 해석 · `JoinMatchResponse.center` 추가 · confirm의 방어선 순서 반전(서버가 고르고 클라이언트 지목은 대조) · 미해석 시 400(오라클 방지 문구) |
| `backend/internal/api/service_join_center_test.go` **신설** | 8 케이스 — 타 센터 매칭·연결 센터·상호 미등록 기본 센터 회귀·미매칭·모호 409·member_id 불일치·미해석 400·후보 정렬/중복 |
| `admin/src/lib/types.ts` | `Role`에 `superadmin` · `AdminCenter`·`CenterCreateBody`·`CenterCreated`·`CENTER_ID_PATTERN`(서버 정규식과 동일) |
| `admin/src/lib/api.ts` | `adminCenters()`·`createCenter()` |
| `admin/src/lib/queries.ts` | `keys.adminCenters`·`useAdminCenters()`·`useCreateCenter()`(성공 시 목록 무효화) |
| `admin/src/features/Centers.tsx` **신설** | 센터 목록 + 생성 마법사(센터 신원 + 최초 owner) + 등록 결과 카드(대표 안내) · 상호 미등록 센터가 목록에 없다는 사실 명시 |
| `admin/src/App.tsx` | `Section` `centers` · `SUPERADMIN_NAV` · `isSuperadmin` 셸 분기 · 역할 게이트 |
| `admin/src/features/Login.tsx`·`NoAccess.tsx` | 특정 센터 상호 제거(멀티센터) |
| `docs/API계약_v1.md` | **v2.32** 절 신설 |
| `backend/README.md` | 관리 평면 현황 · superadmin 시딩 주의(owner 계정과 분리) · 첫 로그인 비밀번호 재설정 |

## 검증
- **백엔드**: `go build ./...` · `go test ./...` 전 패키지 그린 · `-race` 그린.
- **뮤테이션 8/8 kill** — ① 기본 센터 후보 제거 ② JoinMatch를 `p.CenterID`로 회귀 ③ SaveMember를
  기본 센터로 ④ UserIndex를 기본 센터로 ⑤ 모호할 때 조용히 첫 건 선택 ⑥ member_id 대조 제거
  ⑦ 중복 제거 무력화 ⑧ 미해석 400 매핑 제거. 전부 대응 테스트가 죽였다.
- **로컬 E2E 10단계**(dev 백엔드 :8099, 실제 HTTP): superadmin 센터 생성 → 목록 → superadmin이
  `/v1/members` 403 → 2호점 owner가 회원 등록 → 2호점 owner는 자기 회원만 · 라이즈 owner에게는
  안 보임 → **신규 uid가 2호점 번호로 매칭**(응답 `center`에 2호점 상호) → 확인 → 연결 →
  `GET /v1/me`가 `center_id: gangnam-2` → **기존 라이즈 회원도 여전히 매칭**(회귀 없음).
- **어드민**: `tsc --noEmit` 0 · `npm run build` 성공 · **프로덕션 번들 grep 실측** — 새 문구
  "센터 관리"·"새 센터 등록"·"superadmin" 존재, 걷어낸 "라이즈 컨디셔닝 센터 어드민"·"라이즈 어드민" **0건**.
- **앱 영향 0 확인**: `join_dto.g.dart`의 생성 파서가 알려진 키만 읽어 새 `center` 필드를 무시한다
  → 제출 중인 1.0(4) 재아카이브 불필요.
- **자문자답으로 검증한 것**: ① 전자계약이 남의 사업자 정보를 인쇄하나 → **아니다**
  (`contract_template.go:318`이 `GetBusiness(ctx, centerID)`로 센터 스코프) ② 새 owner는 어떻게
  첫 로그인하나 → 임시 비밀번호를 아무도 모르므로 **비밀번호 재설정 필수**(화면에 명시)
  ③ 기존 owner 계정을 superadmin으로 올리면? → **자기 센터에서 잠긴다**(README에 경고 추가)
  ④ 프로덕션에 superadmin이 있나 → **없다**(users 5건: member 3·trainer 1·owner 1) → 후속 1번.

## 후속 작업
> **1·2번은 2026-09-06 P66에서 완료됐다** — superadmin(`richramsang@gmail.com`) 시딩·로그인 검증,
> 백엔드 `rize-api-00031-pxv` + Hosting 배포. 아래 원문은 기록으로 남긴다.

1. **[CRITICAL · 람] 최초 superadmin 시딩** — 이게 없으면 새 화면을 쓸 수 없다(프로덕션 실측:
   superadmin 0건). ① 어드민에서 쓸 **새 이메일**로 Firebase Auth 계정 생성(콘솔 > Authentication >
   사용자 추가) ② Firestore `users/{그 uid}` = `{role:"superadmin", center_id:""}`
   ③ 그 계정으로 어드민 로그인 → **센터 관리** 탭.
   ⚠ **기존 owner 계정을 쓰지 말 것** — 역할이 uid당 1개라 라이즈 어드민에서 잠긴다.
2. **[HIGH · 배포] 백엔드 v2.32** — 이 변경은 서버에만 있다. 배포 전까지 2호점 회원은 연결되지
   않는다. 어드민(Hosting)도 함께 배포해야 센터 관리 화면이 뜬다. (배포는 람 실행 — P61·P62의
   v2.30·v2.31도 아직 라이브 00030에 없다.)
3. **[HIGH · 다음 앱 빌드] 대기실이 자기 센터를 말하게 한다** — 앱은 센터 상호를 무인증
   `GET /v1/public/center`(기본 센터 고정)에서 읽어 **2호점 회원에게 1호점 상호를 보여준다.**
   v2.32가 `join/match` 응답에 `center`를 실어 두었으므로 앱이 그걸 읽으면 정정된다.
   (1.0(4) 재심사 중이라 이번 빌드에는 넣지 않았다.)
4. **[HIGH · 결정 필요] 가입 요청의 센터 차원** — 미등록 번호의 요청이 기본 센터 큐로 간다.
   설계04 §4 권고는 **센터별 초대 코드/QR**(데스크 안내판). 앱 화면 + 대기실 테스트의 금지어
   규약("다른 센터") + P55 결정 개정을 동반한다.
5. **[HIGH · 결정 필요] 법정 문서의 센터 차원** — `PublicBusiness`/`PublicCenter`가
   `DefaultCenterID` 고정이라 법정 문서 5장이 **특정 센터 하나**를 개인정보처리자로 인쇄한다.
   센터가 둘이 되는 순간 나머지 센터에는 거짓이다. 람이 이미 제기한 문제(2026-09-06 대화).
   선택지: (a) 센터별 문서 + 스토어에는 플랫폼 방침 (b) 운영사를 처리자로 올리는 구조 변경
   (c) 공통 문서 + 센터별 부속 고지. **전자계약은 이미 센터 스코프라 안전하다**(검증 완료).
   함께 확인된 것: 처리위탁 조항에 Google LLC만 있고 **앱 운영자가 빠져 있다**.
6. [MEDIUM] 어드민 브랜드 마크가 아직 "RISE 어드민"이다(사이드바·로그인 로고·파비콘).
   멀티센터라면 제품명(PT데스크)이 맞지만 디자인 자산 교체를 동반해 이번 범위에서 제외했다.
7. [LOW] 센터 수가 수십 개가 되면 번호 조회가 센터 수만큼 돈다 → Firestore 컬렉션 그룹 쿼리
   (`phone_norm` 인덱스). v1 규모에서는 불필요.

## 참조
- PT데스크_설계_04_멀티센터_롤계층_2026-08-29.md (Phase A~D 계획 · §4 회원-센터 연결 권고)
- work_log/P41-multicenter-phase-a-coaches-review.md (Phase A 구현)
- work_log/P40-multicenter-roles-trainer-seed.md (3팀 조사 원본)
