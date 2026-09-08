---
id: P69
title: 가입 요청 큐를 회원 관리로 — 어드민 가시성 + 회원앱 대기실(Lobby) v2 디벨롭
status: 완료
domain: cross
created: 2026-09-08
completed: 2026-09-08
---

# P69 — 가입 신청 회원이 어드민에 안 보인다 · 대기실 디벨롭

## 목표 (람 요청)
1. 앱에서 센터에 가입 요청을 보내면 **어드민에서 신청한 회원을 볼 수 있는 곳이 없다** — 기획 팀 여러 개로 교차 검증·자문자답 후 자율 작업으로 완성.
2. `~/Downloads/KakaoTalk_Photo_2026-09-08-22-31-27.jpeg`(대기실 pending 화면 실사) — 친구(센터 측)가 생각한 대기실과 다르다 → 디벨롭.

## 착수 시점 실태 (실측)
- 어드민: 가입 요청 큐는 **설정·직원 탭(대표 전용) 하단 "가입 요청 승인" 카드**에만 있고, 대시보드 "해야 할 일"에 건수 한 줄. 회원 관리 탭·좌측 네비 어디에도 흔적이 없다. 트레이너는 아예 볼 수 없다(서버 owner 전용).
- 앱 대기실(`center_confirm_screen.dart`, P55/P63): 제목·부제·대기 카드([연결됐는지 확인][다시 요청])·연락 카드·하단 링크. 화면 절반이 빈 여백. "다시 요청"은 서버가 pending을 들고 있으면 항상 409.
- 멀티센터(v2.33) 이후 `/v1/me.join_request`에 center_id가 없어 대기실 연락 카드가 **기본 센터**를 찍는다.

## 결정 사항 (기획 3팀 교차검증 — A 어드민 데스크 운영 / B 대기실 UX / C 기술·계약)

### D1. 큐의 정위치 = 회원 관리 탭 최상단(대표 전용), 설정 카드는 링크 한 줄로
"신청한 회원"을 찾는 곳은 회원 관리인데 큐는 설정 8장 중 6번째 카드였다(A §1 1순위). "둘 다"는
같은 문 두 개 금지 규약과 충돌, 별도 탭은 하루 0~2건이라 대부분 빈 화면 → 기각. 네비 배지 +
대시보드 줄(이름 3개, 목적지 회원 관리). 트레이너는 서버 owner 전용이라 1차는 부제 한 줄만.

### D2. 승인 전 중복 감지 — 화면 힌트 + **서버 가드**(v2.34)
승인은 `jr.Phone`으로 새 레코드를 만든다. 같은 번호의 활성 회원이 있으면 회원이 2명이 된다(C-2
변종). 어드민은 정규화 번호(`NormalizePhone` TS 이식)·이름·탈퇴자 3톤 힌트 + 확인 창 경고,
서버 `JoinApprove`는 409로 막는다(탈퇴자 제외 — 재가입 유일 경로). A의 H7(기존 회원으로 연결
API)은 **후속** — 번호 정정 → 회원 재인증 동선으로 닫힌다.

### D3. CRITICAL 발견(C 1-b): 2호점에 보낸 요청이 `/v1/me`에 안 실렸다
`latestJoinRequest`가 Principal 센터(미연결 uid = 기본 센터 폴백) 큐만 훑었다. v2.33이 연 센터
선택을 v2.27 조회가 못 따라갔고, 앱은 "요청 없음" → 재요청 → 409 루프. → uid 기준 조회
(`ListJoinRequestsByUID`) + `join_request.center_id`(3칸). 409 본문에 `code:"join_pending"`으로 앱이
pending 승격. 판정 범위는 **센터별 유지**(철회 동사 없이 전 센터로 넓히면 가둔다 — 한 쌍 후속).

### D4. 대기실 v2 = 로비(진행 상황) 본체 + 쇼룸 한 장(B §1)
거짓 문구 3곳("자동으로 연결돼요"·"바로") 제거, "다시 요청"은 서버 확답 pending이면 숨김(항상
409였다), 자동 확인(포그라운드 30s→백오프, 앱 재개 즉시, 간격은 provider 주입 — 기존 위젯 테스트
31건이 `pumpAndSettle`이라 무한 타이머는 전부 타임아웃), 스텝퍼+확인 상태 줄, 센터 카드(고른
센터의 상호·주소→지도·수업 시간·전화), 코치 한 줄(센터 일치 시), "연결되면 이 앱에서" 미리보기.
접수처(미등록자 상담 신청)·FCM 푸시는 후속. 수업 시간은 `/v1/public/center`에 additive.

## 진행 단계
- [x] 실태 조사 + P69 클레임
- [x] 기획 3팀 병렬 투입(어드민 데스크 운영 / 회원앱 대기실 UX / 기술·계약 검증)
- [x] 교차검증 + 자문자답 → 우선순위
- [x] 백엔드 v2.34(스토어 동사·uid 조회·409 code·승인 가드·공개 시간) + 테스트 · 뮤테이션 3/3
- [x] 어드민(큐 이동·배지·중복 감지·검색 정규화) — tsc 0 · build 성공 · 번들 grep 실증
- [x] 앱(대기실 v2) — analyze 0 · 1384→1465 pass · 뮤테이션 5/5
- [x] 검증(go test/-race · tsc/build · flutter analyze/test) + 계약 v2.34 · README · P69

## 변경 파일
**백엔드(v2.34)** — `store/store.go`·`memory.go`·`firestore.go`(`ListJoinRequestsByUID`) · `store/conformance_test.go`
(+`testListJoinRequestsByUID`) · `api/service.go`(`MeJoinRequest.CenterID` · `latestJoinRequest` uid 조회 ·
`JoinRequestCreate` 409 `joinPendingError` · `JoinApprove` 번호 중복 가드 · `PublicCenter`→`PublicCenterView` hours) ·
`api/util.go`(`codeJoinPending`·`joinPendingError`·writeErr 분기) · `api/service_join_lobby_test.go`(3키·wire 409 본문 ·
+`TestMeJoinRequestFollowsSelectedCenter`·`TestJoinApproveRefusesDuplicatePhoneOfActiveMember`) ·
`api/service_public_center_test.go`(5키·정책 변경 반영) · `docs/API계약_v1.md`(헤더 2줄·v2.27 개정 표기·**v2.34 절**) · `backend/README.md`.

**어드민** — `features/JoinRequests.tsx`(신설 — 큐 카드·승인/거절 모달 이동·상대 시각·경과 강조·중복 감지 3톤·
승인 창 경고/동의 체크/연결됨 비활성·focus 강조) · `features/Members.tsx`(최상단 마운트·`focusJoinRequestId`·
승인 직후 자동 선택·검색 `normalizePhoneKR`·번호 표기 통일·트레이너 부제) · `features/Settings.tsx`(카드·모달 제거,
"센터·앱 연결"에 회원 관리 링크 한 줄) · `features/Dashboard.tsx`(이름 3개 링크 · 목적지 회원 관리) ·
`App.tsx`(`NavJoinBadge`·`joinFocusId` — P68 변경 보존) · `lib/format.ts`(`normalizePhoneKR` Go 이식·`formatPhoneKR`·
`maskPhoneKR`·`formatRelativeKo`·`formatDateTimeKo`) · `lib/api.ts`(`joinApprove`→`Member`) · `lib/queries.ts`·`lib/types.ts` 주석 · `admin/README.md`.

**앱** — `core/icons/rise_icons.dart`(phone·mapPin·clock) · `core/result/failure.dart`(`MemberNotLinkedFailure.centerId/joinCenterId`·
`JoinPendingFailure`) · `core/network/api_result_guard.dart`(409 `code=join_pending` 분기) · `core/api/dto/join_dto.dart`(+생성물,
`centerId`) · `auth/presentation/center_contact_provider.dart`(family `?center=`·hours) · `auth/domain/join_request_store.dart`
(`centerId` v2, 구 JSON 호환) · `auth/presentation/auth_state.dart`(`LobbyStep`·`joinCenterId`·`centerId`·`lastCheckedAt`·
`lastCheckFailedAt`·`canRetryJoinRequest`) · `auth_view_model.dart`(`requestJoin`→`JoinRequestOutcome`+409 승격 · 확인 시각) ·
`auth_repository_impl.dart`·`session_restore.dart`(센터 두 칸 전달) · `center_confirm_screen.dart`(거짓 문구 4곳 · 대기 카드
→ 스텝퍼+상태 줄+조건부 재요청 · `_CenterCard` 주소→지도·수업 시간·"요청한 센터" · `_RequestResultRow` · `_CoachPreviewRow` ·
`_AfterConnectPreview`) · **신설** `widgets/lobby_auto_check.dart`(`lobbyAutoCheckIntervalProvider` · 포그라운드 30→60→120s ·
resumed 즉시 · busy/시트 열림 스킵) · `widgets/lobby_progress.dart`(`LobbyProgress`·`CheckStatusLine`) · 테스트 10파일
(신규 `lobby_auto_check_test` 11건 포함).

## 검증
- **백엔드**: `go build` · `go test ./...` · `-race` 전건 그린. 신규 5건(uid 조회로 2호점 요청이 /v1/me에 실림 · 승인 번호
  중복 409 · wire 409 본문 3키 · 공개 센터 5키+정책 반영 · 스토어 conformance ByUID). **뮤테이션 3/3 KILLED**(센터 조회로
  되돌리기 / 번호 가드 제거 / 409 code 본문 제거).
- **어드민**: `tsc --noEmit` 0 · `npm run build` 성공 · 번들 grep("앱에서 온 가입 요청이 없어요" 1 · "이미 있는 회원과 번호가
  같아요" 1) · `normalizePhoneKR` 8케이스 백엔드 주석 예시와 일치 · P68 변경 보존 확인. 브라우저 실행은 미확인(람).
- **앱**: `flutter analyze` 0 · `flutter test` **1384 → 1465 pass**(회귀 0). **뮤테이션 5/5 KILLED**(자동 확인 타이머 제거 /
  "다시 요청" 조건 무시 / `?center=` 미전달 / 409 승격 제거 / 시트 열림 가드 제거).
- **자문자답(오케스트레이터)**: ① 전 센터 409로 넓히지 않은 이유 — 철회 동사가 없어 가둔다(한 쌍 후속) ② 승인 번호 가드가
  탈퇴자 재가입을 막나 → 탈퇴는 번호 파기 + IsWithdrawn 제외, 기존 테스트 그린 ③ 공개 시간이 "미설정 기본값"을 사실처럼
  찍나 → 그 값이 곧 예약 격자가 여는 시간이라 지어낸 사실이 아님 ④ 폴링 Timer가 기존 31개 위젯 테스트를 깨나 → 간격
  provider 주입(null)로 회피, 실측 회귀 0 ⑤ 시트 입력 중 자동 연결로 시트가 고아가 되나 → `ModalRoute.isCurrent` 가드 +
  테스트 ⑥ 구서버+새 앱 → DTO 기본값·문구 매칭 미사용으로 종전 동작 ⑦ 심사 중 1.0(8) → 생성 파서가 지정 키만 읽어 안전.

## 후속 작업
1. **[CRITICAL] 배포(람 실행)** — 순서 ① `gcloud run deploy rize-api --source backend --region asia-northeast3 --project rize-218c1 --set-build-env-vars GOOGLE_BUILDABLE=./cmd/server` ② `./deploy-hosting.sh` ③ 앱은 심사 중 1.0(8) 통과 후 `1.0.0+9`로 빌드·제출.
   서버 배포 전: 새 앱은 종전 동작(기본 센터 카드·시간 행 없음), 어드민 승인 409 문구는 서버 배포 후.
2. **[HIGH] 실기기 확인** — 미연결 번호로 대기실 pending·notFound·rejected 3화면(스텝퍼 세로 전환 320×568, iOS `maps://` 지도 열기, 자동 확인 후 홈 진입).
3. **[HIGH] 어드민 브라우저 확인** — 회원 관리 상단 큐·네비 배지·중복 힌트(같은 번호 회원 등록 후 요청).
4. **[MEDIUM] `DELETE /v1/join/request`(본인 pending 철회) + 전 센터 409** — 한 쌍으로.
5. **[MEDIUM] 트레이너 큐 열람**(`GET /v1/join/requests` staff 개방, 승인·거절은 owner 유지).
6. **[LOW] 승인 푸시(FCM)** · 미등록자 상담 접수(join_request kind/note) · 어드민 vitest 도입.
7. P56 L7(센터 신원·사업자 정보 입력)은 여전히 대기실 센터 카드의 전제 — 비어 있으면 전화·주소 행이 없다.

## 참조
- P55(대기실 재작성) · P63(문구 정리) · P66(센터 선택) · P58(어드민 거절) · P68(App.tsx 동시 편집 — 보존)
- 기획 산출물: scratchpad `plan_A_admin.md`(데스크 운영) · `plan_B_lobby.md`(대기실 UX) · `plan_C_tech.md`(기술·계약)
- 계약 v2.34 절(`docs/API계약_v1.md`)
