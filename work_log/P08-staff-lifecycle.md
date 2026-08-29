---
id: P08
title: 직원 생애주기(정정·퇴사) + P06·P07 교차검증
status: 완료
domain: cross
created: 2026-08-22
completed: 2026-08-23
---

# P08 — 직원 생애주기 완성 + 교차검증

## 목표

P07로 초대가 열렸지만 **되돌리기가 없다**. 이름 오타·역할 오지정·정산 조건 변경·퇴사를
처리할 경로가 계약에 없어, 잘못 초대하면 영구히 남는다. 여기에 P06·P07에서 인증·전화번호·
스태프·배포 토폴로지가 크게 바뀌었으므로 그 변경분을 새눈으로 교차검증한다.

## 결정 사항

### 보안(검증 중 발견 — 생애주기보다 먼저 처리)
- **계정 탈취 차단(CRITICAL)**: v1.7의 "토큰에 번호가 **있으면** 진실" 조건부 규칙이, 번호 없는
  토큰(이메일 계정)을 바디 폴백으로 흘려보냈다. 자체 가입이 열려 있고 웹 API 키가 배포 번들에
  공개돼 있어 **누구나 계정을 만들어 남의 번호로 그 회원에 연결**할 수 있었다. 조건부 → 필수.
- **센터 락아웃 차단(HIGH)**: join/confirm·approve가 호출자 UserIndex를 무조건 member로 덮었다.
  대표가 한 번 호출하면 자기 권한을 잃고 되돌릴 API가 없다 → 스태프 계정은 이 경로에서 거절.
- **권한 검사를 조회보다 앞으로**: 프로덕션 실측에서 없는 member_id에 404가 나와 발견. 자격 없는
  호출자가 404/403 차이로 회원 ID 존재 여부를 캐낼 수 있었다(존재 오라클).
- **테스트가 배포 분기를 지나지 않고 있었다** — 전부 dev 모드라 수정을 넣어도 하나도 깨지지
  않았다. `newProdModeService()`를 만들어 운영 모드 회귀 가드 5종을 추가.
- 어드민 데모 진입점이 **라이브에 노출**돼 있었다(빌드 후 호스팅 재배포를 빠뜨림). 빌드 게이트로
  번들에서 제거 + **이미 누른 브라우저 구제**(운영 빌드는 저장된 데모 신원을 복원하지 않고 삭제).

### 직원 생애주기 (계약 v2.0)
- **하드 삭제 금지, `Staff.status` 소프트 전이.** 근거: 원장 append-only(행위자 uid 삭제 불가) ·
  by_trainer 행이 스태프 목록 구동(삭제 시 정산 이력 소급 파괴) · 7개 엔티티에 평문 uid + FK 없음 ·
  근기법 3년/국세기본법 5년 보존. 시장 관행도 일치(핏투비 "퇴사처리", ClubReady "reclassified,
  historical reference remains", PushPress "remain intact" — 조사한 12개 중 익명화하는 곳 0곳).
- `bool` 아닌 **문자열 enum** — Member/Pass/Booking/Contract가 전부 문자열 status인데 Staff만
  없었다. **필드 부재는 로드 시 active로 승격**(v1.3 Policy 상한 승격과 동형) → 마이그레이션 불필요.
- **이관은 차단형(blocking)**. 이관 없이 비활성화하면 담당 회원이 "목록엔 미배정으로 보이는데
  미배정 필터·KPI엔 안 잡히는" 발견 불가능 상태가 된다. 한국에선 트레이너 퇴사가 사업자 귀책으로
  해석돼 잔여 회차 환급 리스크로 이어지므로 재배정은 편의가 아니라 손해 방지 장치.
- 이관 `scope` 파라미터는 **버렸다** — 퇴사 인수인계는 전부 옮기는 것이 정의다. 부분 이관은
  실패 모드만 늘린다. 대신 **인수자 슬롯 충돌 예약은 옮기지 않고 conflicts로 보고**한다
  (트레이너 동시 1건 규칙을 이관이 우회하면 안 되고, 남은 예약이 계속 퇴사를 막는 게 정직하다).
- 이관 이벤트는 **원장에 기록**(`reason:"transfer"`, delta 0). 설계 03 §9가 요구한 것이고,
  이 enum 값은 v1부터 선언만 된 채 한 번도 쓰이지 않은 예약된 자리였다.
- **Firebase 계정은 지우지 않고 비활성화**. 지우면 재고용 시 새 uid가 발급돼 기존 참조 196곳과
  끊긴다. **즉시성은 UserIndex가 담당**(인증이 요청마다 읽고 캐시가 없다), Firebase 비활성화는
  재로그인 차단용 2차 방어선. 토큰 폐기 확인(`VerifyIDTokenAndCheckRevoked`)으로 승격하지
  **않는다** — 매 요청 Firebase 왕복 비용을 치를 만큼의 이득이 없다(최대 1시간 잔존은 감수).
- **락아웃 3중 가드**: 자기 자신 금지 · 마지막 활성 owner 비활성화 금지 · owner→trainer 강등도
  같은 카운트에 포함(강등이 우회로가 되지 않게).
- `by_trainer`는 **활동이 있으면 남긴다** — `active OR (기간 내 sessions>0 || revenue>0)`.
  정산 이력 보존과 현재 팀 목록 정합을 동시에 만족.
- **재초대 409 판정에서 inactive 제외** — 그러지 않으면 재고용이 영구 차단된다.
- **부수 발견(별건 인가 구멍)**: `PUT /v1/members/{id}`가 권한 검사 뒤 바디로 `trainer_id`를
  덮어쓰는데 재검증이 없어 **트레이너가 자기 담당 회원을 임의 uid로 넘길 수 있었다**.
  POST와 동일하게 본인 강제로 통일 — 담당 이관은 owner 전용 경로로만.
- **미루는 것**: 실존 스태프 검증 부활(별건 — DEV_SEED 미사용 로컬 흐름을 깰 수 있음),
  보존기간 파기 배치(`left_at`만 남기고 나중에), 5인 미만 사업장 근기법 적용 여부(노무사 확인).

## 진행 단계

- [x] 1. 검증 3팀 병렬 투입 — 백엔드 새눈 감사 / UI·UX 교차검증 / 트레이너 비활성화 영향 분석
      (마지막 팀은 3계층 trainer_id 참조 **196곳** 전수 조사 + 국내외 12개 제품 관행 리서치)
- [x] 2. 결과 교차검증 + 자문자답 → CRITICAL 2건(계정 탈취·센터 락아웃)을 생애주기보다 먼저 처리
      결정으로 확정. 보고된 지적은 내가 코드로 재확인한 것만 채택(색상 중복 지적은 오탐으로 기각).
- [x] 3-1. 보안 수정 + 프로덕션 실증(공격 시나리오 재현 6/6 PASS) + 계약 v1.9
- [x] 3-2. 어드민 라이브 정리 — 데모 진입점 번들 제거 + **이미 누른 브라우저 구제** + 재배포
- [x] 3-3. 백엔드 데이터 정합 4건(엑셀 선행 0 · 매칭 결정성 · 설정 fail-closed · center_id 고정)
- [x] 3-4. 어드민 UX 4건(역할 게이트 · 가입요청 노출 · 빈 센터 온보딩 · 헤더 이름)
- [x] 3-5. 앱 인증 여정 5건(즉시인증 순서 · 막다른 길 · 대기상태 영속 · 플래그 분리 · 번호 편집)
- [x] 3-6. 앱 인증 여정 마감 4건(즉시인증 화면 스킵 · 시스템 백 · 대기 화면 확인 버튼 · 복원 오독)
      — 테스트 64 → 91 → **129**
- [x] 3-7. **민감정보 쓰기 스코프 구멍**(P08 최대 발견 중 하나) — 체형사진·인바디 쓰기에 권한
      검사가 아예 없었다(동의만 확인). 인증만 되면 **남의 체형사진을 기록**할 수 있었고, 읽기는
      막혀 있어 읽기/쓰기가 비대칭이었다. 홈워크 체크는 미연결 회원이 주인 없는 기록을 남겼다.
      원인: 체형사진 테스트가 **한 건도 없었다**. 세 곳에 읽기와 동일 게이트 + 회귀 가드.
- [x] 4-1. 직원 생애주기 v2.0 백엔드(4 엔드포인트 + 상태 승격 + 락아웃 3중 가드 + 이관 원장 +
      by_trainer 활동 규칙 + 재고용 + inactive 예약 거부 + PUT /members trainer_id 강제)
- [x] 4-2. 어드민 생애주기 UI — 재직/퇴사 그룹 분리 + 모달 4종. 퇴사 모달이 **blockers를 회원
      이름·예약 시각으로 해석**해 보여주고 곧바로 이관으로 잇는다. 이관의 conflicts가 남아 있으면
      "퇴사 계속하기"를 아예 노출하지 않는다(누르면 또 409). 401 → 자동 로그아웃(403은 제외 —
      권한 밖 기능을 눌렀을 뿐인 정상 상황과 구분되지 않는다). Settings 970 → 1658줄.
- [x] 4-3. 앱 — `StaffDto.status`(부재=active 승격) + 해석 지점 전수 + `(퇴사)` 앵커 표기 +
      아바타 흑백 + 프로필 시트 3분기(퇴사 / 캐시 미로드 / 미등록) + 캐시 15분 TTL·당겨서 새로고침
      무효화. 테스트 129 → **165**.
- [x] 4-4. 앱 변경분 새눈 리뷰 → **실제 버그 5건** 수정. 테스트 165 → **207**.
      · **기본 예약 모드에서 퇴사 코치 예약 버튼이 살아 있었다** — 필터가 "전체 코치" 분기에만
        걸려 있었는데 회원의 기본 화면은 "내 코치" 모드다(서버가 400 줄 예약을 권함).
        행을 숨기지 않고 **비활성 버튼 + 상단 안내 1회**로(13칸 note 도배 회피), 다른 예약 가능
        패스 유무에 따라 문구를 분기.
      · **"퇴사 여부"의 출처가 둘이라 화면 안에서 모순** — 신선한 도메인 플래그 vs 15분 캐시.
        "(퇴사)" 라벨 옆 총천연색 아바타, **퇴사를 설명하는 유일한 자리인 프로필 시트가 퇴사를
        모름**. 도메인 플래그를 진실로 통일(캐시는 사진·색·소개 전담) — 캐시는 "모르면 현직"
        승격 때문에 **퇴사를 놓칠 수만 있고 없는 퇴사를 만들지는 못한다**는 비대칭이 근거.
      · trim 규칙이 반쪽(판정은 trim, 보간은 원본) → `nameOrNull`로 정규화 지점을 단일화.
      · A·B·C·E는 **뮤테이션 검증**(수정을 되돌려 테스트가 실제로 깨지는지) 확인.
- [x] 5-1. 프로덕션 E2E **24/24**(초대→회원·회원권→퇴사 차단 409+blockers→이관(원장 transfer,
      잔여 불변)→퇴사(inactive·left_at)→재입사 / 락아웃 가드 3종 / 미배정 회수 / inactive 예약 거부)
      — 첫 회차의 2건 실패는 **내 테스트 설계 결함**(임시 대표에 직원 레코드 미생성 → 404,
      이관 후 담당 불일치로 다른 사유의 400)이라 조건을 바로잡아 재검증했다. 생성물 전부 정리.
- [x] 5-2. 3계층 최종 매트릭스 + 호스팅 재배포 + 라이브 번들 검사
- [x] 6. 문서(계약 v1.9·v2.0 · 3 README · 본 로그) 마감

## 변경 파일

**backend** — 보안: `service.go`(joinPhone·guardNotStaff·권한 검사 선행·민감정보 쓰기 스코프 3곳),
`domain/phone.go`(엑셀 선행 0), `store/{memory,firestore,store}.go`(결정적 매칭·ReassignBookingTrainer·
UpdateRecurring·Normalize), `config/config.go`+`cmd/server/main.go`(fail-closed) ·
생애주기: `api/service_staff.go`(신규) · `domain/staff.go`(status·left_at·StaffUpdate) ·
`api/provision.go`(DisableUser/EnableUser) · `domain/stats.go`+`api/service_stats.go`(by_trainer status)
· `api/handlers_staff.go`·`router.go`·`util.go` · 테스트: `service_staff_test.go`·`domain/staff_test.go`·
`store/memory_test.go`·`config/config_test.go`(신규) + `service_test.go`·`phone_test.go` 보강

**admin** — `features/NoAccess.tsx`(신규) · `App.tsx`(역할 게이트·헤더 이름) ·
`Login.tsx`(데모 빌드 게이트·탈출구) · `lib/auth.tsx`(데모 신원 purge·401 핸들러) ·
`lib/api.ts`(ApiError.data·401 인터셉터·생애주기 4종) · `lib/{types,queries,format}.ts` ·
`Settings.tsx`(생애주기 모달 4종) · `Members.tsx`·`Schedule.tsx`·`Sales.tsx`·`Dashboard.tsx`(퇴사 표기·
빈 상태·온보딩·가입요청) · `components/ui.tsx`(colSpan 타입)

**app** — `core/api/dto/staff_dto.dart`(status·left_at) · `core/utils/coach_label.dart`(신규) ·
`core/api/staff_directory.dart`(15분 TTL) · `core/widgets/trainer_avatar.dart` ·
`core/result/failure.dart`(MemberNotLinkedFailure) · `features/auth/**`(즉시인증·PopScope·연결 확인·
복원 분기·대기 영속 `join_request_store`) · home/booking/my 표시 12개 화면 · 테스트 64 → **165**

**docs** — `API계약_v1.md` **v1.9**(가입 경로 보안: 검증 번호 필수·스태프 강등 차단·승인 멱등·
연결 전 응답 최소화) · **v2.0**(직원 생애주기: status·4 엔드포인트·차단형 이관·락아웃 가드·
by_trainer 활동 규칙·재고용) · 3 README

## 검증

- backend `gofmt` 클린 · `go vet` 클린 · `go test ./... -race` **4패키지 전부 그린**
- app `flutter analyze` 0 issues · `flutter test` **207 passed**(P08 시작 시점 64개 → 3.2배)
- **네이티브 빌드 양 플랫폼 재확인** — 이번에 `shared_preferences`(승인 대기 영속화)가 새로
  들어왔다. 플러그인 추가는 `flutter test`가 통과해도 네이티브 링크에서 깨지는 종류라 실제
  빌드로 확인했다: Android `assembleDebug` exit 0(APK 생성) · iOS `build ios --no-codesign`
  exit 0(`Runner.app` 22.9MB, 번들 `ai.stra.rize`).
- admin `npx tsc --noEmit` exit 0 · `npm run build` exit 0
- **프로덕션 보안 실증 6/6** — 공개 API 키로 실제 공격자 계정을 만들어 피해자 번호로 가입 경로
  3종 시도 → 전부 403. `/v1/me`는 통과(가입 부트스트랩 보존), 전화 인증 계정은 정상(과잉 차단 없음).
- **프로덕션 생애주기 E2E 24/24** — 초대 → 회원·회원권 → 퇴사 409+blockers(실제 ID) → 이관
  (moved 집계·원장 transfer·잔여 20회 불변) → 퇴사(inactive·left_at) → 재입사 / 자기 퇴사·자기 강등
  거부 / 다른 대표 퇴사 허용 / 미배정 회수 / inactive 고정스케줄 400. 생성물 전부 정리(Firestore
  8개 컬렉션 재확인 — 대표 1명·직원 1건만 잔존).
- **라이브 번들 직접 검사** — `박관장`·`로컬 개발용`·`:8080`·`backend README`·`시딩` 전부 0건,
  생애주기 UI 문자열 존재 확인, `/api/v1` 리라이트 401 JSON, `/health` 200.

## 후속 작업

- **미해결(보고됨)**: `CreatePass`가 트레이너 실존·활성을 확인하지 않아 퇴사자 담당 회원권을 새로
  발급할 수 있다(즉시 퇴사 차단 조건이 다시 생긴다) · `ListStaff`에 역할 게이트가 없어 미연결
  계정도 명단을 읽는다 · 안드로이드 SMS 자동회수가 `codeSent` **이후** 오는 경우는 여전히
  자동 진행되지 않는다(확인 버튼은 동작) · 승인 대기 자동 갱신 없음(수동 확인 버튼만)
- Memory 스토어 List 7종이 정렬 없이 맵 순서 반환 — Firestore와 순서가 달라 앱의 기본 패스 선택이
  로컬에서 흔들린다(항목 ②와 같은 종류의 로컬/운영 불일치)
- 앱 `normalizeKoreanPhone`이 백엔드 정규화와 규칙이 갈린다(0도 82도 아닌 입력을 전부 `+82{digits}`로)
- 앱의 home/booking/my repository 3곳이 `staffMapProvider`를 거치지 않고 `fetchAll()`을 직접 부른다 —
  탭 진입마다 `GET /v1/staff`가 중복되고 퇴사 여부의 출처가 이원화된 근본 원인이다(이번엔 도메인
  플래그를 진실로 삼아 증상은 막았지만, 데이터 레이어 단일화가 정공법)
- `blockers.bookings`에 slot_key를 실으면 어드민이 예약 목록을 한 번 더 조회할 필요가 없다
- 미배정 회수(`to_uid:""`) 후 그 회원들은 예약 불가 — 회원 화면에도 재배정 안내가 필요
- 보존기간 파기 배치(`left_at`만 남겨둠) · 5인 미만 사업장 근기법 적용 여부(노무사 확인)

## 참조

- work_log/P07-staff-onboarding-hosting.md(초대 도입) · P06(인증 실연동) · docs/API계약_v1.md v1.7·v1.8
