---
id: P63
title: 대기실 문구 정리(P56 후속 7) + 미연결 계정 삭제 고지 정직화(P56 후속 9)
status: 완료
domain: app
created: 2026-09-06
completed: 2026-09-06
---

# P63 — 대기실 문구 중복 정리 · 삭제 고지의 "보낸 가입 요청" 정직화

## 목표
1. **대기실(center_confirm) 6단계의 문구 중복 제거** — notFound는 "등록 번호가 다를 수 있다"를 부제·경고 카드·연락
   카드 세 자리에서 말했고, rejected·declined·connectionUnknown·pending도 제목/부제/카드가 같은 말을 2~3번 했다.
   각 단계의 역할을 **제목+부제 = 서버가 아는 사실 / CTA = 할 수 있는 일 / 연락 카드 힌트 = 왜 데스크가 도움이
   되는지(원인 가설, 헤지)** 셋으로 고정한다.
2. **미연결 계정 삭제 고지가 서버가 실제로 지울 것을 말하게** — 종전엔 "보낸 가입 요청 (이름·전화번호)"를 요청 유무와
   무관하게 무조건 열거했고, 거절된 요청(서버가 이미 이름·번호를 비운 껍데기)에도 같은 문장을 썼으며, 완료 안내도
   무조건 "계정과 보낸 가입 요청을 삭제했어요"였다.

이 변경은 **스토어 1.0(4)에 들어가지 않는다** — 다음 빌드(1.0(5)+)용이다. 1.0(4)는 심사 진행 중(P60).

## 결정 사항
- **JoinRequestTrace는 3값 `unknown` / `pending` / `settled` — `none`은 만들지 않는다.** 설계 초안은 `none`(요청 없음)을
  두었으나 적대 검토 2건이 뒤집었다: 앱은 "요청 없음"을 알 수 없다. 코드 인증 직후의 대기실은 GET /v1/me를 부른 적이 없고
  (`_matchAfterSignIn`은 로컬 기록만 본다), 서버도 `join_request` 키 부재로 "없음"과 "조회 실패"를 구분해 주지 않는다.
  기기를 바꿔 로그인한 사람은 서버에 pending(이름·번호 원본)을 둔 채 notFound에 서고, 그때 "인증 계정만 지워져요"는
  **과소 고지 = 거짓**이다. 모르면 "있다면"으로 말한다. 판정은 `AuthState.joinRequestTrace` 한 곳(서버 상태 > 로컬 기록).
- **삭제되는 정보 행**: unknown → '보낸 가입 요청이 있다면 그 요청 (이름·전화번호)' / pending → '보낸 가입 요청
  (이름·전화번호)' / settled → '가입 요청 기록 (처리 상태·요청 시각)' + 항상 '앱 로그인 계정 (인증한 전화번호)'.
  경고 상자·확인 다이얼로그도 같은 trace를 따른다(한 화면이 두 말 금지). "이 화면부터"류 자기지시 금지 —
  '센터 연결 화면부터'로 대상을 명시.
- **완료 안내는 서버가 실제로 한 일**: `AccountDeletionSummary.fromJson`이 `purged.join_requests`(없으면 0)와 `member_id`
  (없으면 '')를 읽는다. 미연결 경로(member_id 빈 값)면 join_requests>0 ? '계정과 보낸 가입 요청을 삭제했어요.' :
  '계정을 삭제했어요.'; member_id가 있으면 회원 완료 문구. **unknown scope도 scope가 아니라 서버 응답으로 고른다.**
  회원 scope만은 세션에 member_id가 있어 회원 경로가 확정이라 서버 칸을 보지 않는다(구서버의 빈 응답 `{}`이 회원에게
  "계정을 삭제했어요"로 떨어지면 안 된다).
- **전달 방식은 생성자 스냅샷** `AccountDeletionScreen(scope:, joinRequestTrace:)`(기본 unknown). provider watch 금지 —
  삭제 성공 직후 `restartWithNewPhone()`이 auth 상태를 비워 고지가 unknown으로 다시 그려진다(스낵바 직전 깜빡임).
  마이 탭의 `const AccountDeletionScreen()` 호출은 무변경.
- **대기실 문구 표** (matched는 카드 제목만 — 아래 "검증 반영" 7):
  | stage | 제목 | 부제 | 카드 | 연락 카드 힌트 |
  |---|---|---|---|---|
  | notFound | 유지 | '인증한 번호로 등록된 회원을 찾지 못했어요' (원인 단정 '달라서' 제거) | _NotFoundCard 삭제 | '센터에 등록된 번호가 다르거나 아직 등록 전이면 자동 연결이 안 돼요. 데스크에서 번호를 고친 뒤 같은 번호를 다시 인증하면 연결돼요.' |
  | rejected | 유지 | '요청에 적힌 번호가 등록된 번호와 다를 수 있어요' | _RejectedCard 삭제 | '데스크에 확인한 뒤 다시 요청할 수 있어요.' |
  | declined | '이 번호로는 연결하지 않았어요' (취소할 연결이 없었다) | 유지 | _DeclinedCard 삭제 | '내 번호가 다른 회원에게 등록된 것 같다면 데스크에서 고쳐드려요. 아직 회원이 아니라면 아래에서 가입 요청할 수 있어요.' |
  | connectionUnknown | 유지 | 유지 | 한 문장 '이미 연결된 회원이라면 다시 확인했을 때 그대로 홈으로 들어가요.' + 경고 아이콘 제거(RiseIcons에 info 계열 없음) | (없음) |
  | pendingApproval | 유지 | 유지 | 본문 '승인됐는지 아래 버튼으로 확인할 수 있어요.' 한 문장, 배지 '승인 대기 중' 삭제 | '승인이 늦으면 데스크에 문의할 수 있어요.' |
  - **'다른 센터' 표현 금지** — v1은 단일 센터(계약 v2.27 center_id 규약). 검토가 잡은 설계 초안의 rejected 부제 승격 기각.
  - **pending 쿨다운 문장 넣지 않음** — 버튼 라벨 '다시 요청 (N초 후)'가 실시간으로 말하고 정적 문장은 30초 뒤 거짓.
  - **힌트 '다음 확인부터 연결돼요' 기각** — notFound엔 확인 버튼이 없고 번호 매칭(`join/match`)은 코드 인증 직후에만
    돈다. 실제 경로 '같은 번호를 다시 인증'을 적고, 하단 링크를 '다른 번호로 다시 시도' → **'번호 다시 인증하기'**로
    (같은 번호 재인증 경로를 겸한다).
  - `_CenterContactCard`는 `hint`를 받고 hasPhone 분기 문장을 없앴다(전화 버튼 유무는 종전 규약). 종전 문장 '앱에 등록된
    번호'는 주어 오류(다른 것은 센터에 등록된 번호).
- **문서**: 계약 v2.29 절 끝에 소비자 메모 2줄(새 절 번호 없음 — 계약 변경이 아니다). appstore.md 심사 노트에 대기실
  '계정 삭제' 경로 추가 + '연결 요청' → '가입 요청' 용어 통일. docs/design/스플래쉬_*.md의 _ConnectionUnknownCard 인용은
  **스냅샷이라 갱신하지 않는다**. 법정문서(account-deletion.html 126-127)는 능력 서술이라 무변경. 서버·어드민 무변경.

## 진행 단계
- [x] 설계(design_APPCOPY) + 적대 검토 2건 반영 → 최종 결정
- [x] `AuthState.joinRequestTrace` + enum(auth_state.dart)
- [x] account_deletion.dart — 목록/경고/다이얼로그 문구 함수 3종, `joinRequests`·`memberId`·`ranUnlinkedPath`·
      `unlinkedCompletionMessage`(getter)
- [x] account_deletion_screen.dart — 생성자 스냅샷, 목록·경고·다이얼로그·완료 문구 분기, unknown 배너 헤지
- [x] center_confirm_screen.dart — 문구 표, 카드 3종 삭제, `_Hints`, `_CenterContactCard(hint:)`, 링크 라벨,
      `_openAccountDeletion(context, state)`
- [x] 테스트 갱신·추가(아래 검증) + 뮤테이션 3건
- [x] 문서(계약 메모·appstore.md) + P63 + README

## 변경 파일
- `app/lib/features/auth/presentation/auth_state.dart` — `enum JoinRequestTrace`, `AuthState.joinRequestTrace`
- `app/lib/features/auth/presentation/center_confirm_screen.dart` — 부제 3곳·제목 1곳, switch 재배치, `_Hints`,
  `_NotFoundCard`·`_DeclinedCard`·`_RejectedCard` 삭제, `_ConnectionUnknownCard` 1문장·아이콘 제거, `_PendingApprovalCard`
  본문·배지, `_CenterContactCard(hint:)`, `_restartLabel`, `_openAccountDeletion(AuthState)`
- `app/lib/features/my/domain/account_deletion.dart` — `unlinkedDeletionPurgedItems(trace)`, `unlinkedDeletionWarning`,
  `unlinkedDeletionConfirmText`, `AccountDeletionSummary.joinRequests/memberId/ranUnlinkedPath`, fromJson 2칸,
  `unlinkedCompletionMessage` getter
- `app/lib/features/my/presentation/account_deletion_screen.dart` — `joinRequestTrace` 파라미터, `_WarningBox(text:)`,
  완료 문구 scope×서버 응답, 배너 문장
- `app/test/features/auth/presentation/center_confirm_screen_test.dart` — 앵커 7곳 갱신, 신규 그룹 4개(삭제 고지 trace 2건 ·
  문구 표 7건 · 중복 금지 5건 · 320×568+1.35 배율 2건), lies 목록 +3
- `app/test/features/auth/presentation/auth_state_test.dart` — `joinRequestTrace` 그룹 8건
- `app/test/features/auth/presentation/login_back_test.dart` — 링크 라벨 앵커 2곳
- `app/test/features/my/presentation/account_deletion_test.dart` — pump에 trace, 가짜 저장소 `summary`, unlinked 그룹 재작성,
  trace 그룹 6건, unknown scope 완료 문구 2건, 단위 3건
- `app/test/features/my/data/account_deletion_api_test.dart` — member_id·join_requests 파싱 2건
- `docs/API계약_v1.md` — v2.29 절 끝 소비자 메모 2줄
- `store/metadata/appstore.md` — 심사 노트 용어·계정 삭제 경로
- `work_log/P63-lobby-copy-and-deletion-notice.md`, `work_log/README.md`

## 검증
- `cd app && flutter analyze` → No issues found.
- `flutter test test/features/auth/presentation/ test/features/my/` → 432 통과 / `flutter test` 전체 → **1313 통과**.
- 뮤테이션 3건(전부 KILLED, 원복 diff 확인):
  1. `joinRequestTrace`를 항상 unknown → auth_state_test 5건 + center_confirm_screen_test '삭제 고지 trace' 2건 사망
  2. `unlinkedCompletionMessage`가 서버 건수 무시(항상 "계정과 보낸 가입 요청") → account_deletion_test 3건 사망
     (unknown 0건 완료 문구 · unknown scope 미연결 경로 · 단위)
  3. `_CenterContactCard`가 `hint` 무시(고정 문장) → 문구 표 4건(notFound·rejected·declined·pending) 사망
- 자문자답: 320×568 + 배율 1.35에서 pending·notFound 예외 0(스크롤 구조가 세로를 받고 Wrap이 버튼을 접는다) /
  '같은 문장 두 번' 테스트는 `' · '`·빈 문자열 제외·시트 미오픈 — 첫 실행부터 초록 / 'matched+pending' 조합 테스트는 프로덕션이
  만들지 못하는 상태라 만들지 않았다(대신 'matched → unknown' 단위 테스트로 로그인 경로의 사실을 고정).

## 검증 반영 (2026-09-06, 검증 이슈 11건 전부)
| # | 이슈 | 반영 |
|---|---|---|
| 1 HIGH | matched의 '계정 삭제'가 unlinked 고지 — 재인증한 기존 회원은 principal에 member_id가 있어 서버가 **회원 경로**를 돈다(과소 고지) | `_openAccountDeletion`: matched → `AccountDeletionScope.unknown` + 새 `AccountDeletionUnknownReason.phoneMatched`(배너 첫 줄 '이 번호로 등록된 회원이 있어요 — 이미 이 계정에 연결돼 있었다면 아래 내용대로 모두 삭제돼요.' / connectionUnknown 배너는 유지). `AccountDeletionScope.unlinked` 정의에서 matched 제외, 관련 주석 정정 |
| 2 MED | `joinRequestTrace`가 로컬 기록만으로 pending 단정 — 코드 인증 직후 경로는 서버를 묻지 않아 그 사이 거절·삭제된 요청도 '보낸 가입 요청 (이름·전화번호)' | pending은 `serverJoinStatus == 'pending'`일 때만(requestJoin 성공·서버 응답·콜드스타트 반영). 로컬 기록 단독 = unknown("있다면"). `centerConfirmStage`(화면)는 종전대로 로컬 기록으로 대기 카드 |
| 3 LOW | `copyWith`가 serverJoinStatus를 null로 못 지움 | `clearServerJoinStatus` 플래그. `applyServerJoinStatus(null)`·`checkConnection` MemberNotLinked(joinStatus null)에서 명시적으로 지운다 |
| 4 MED | declined 힌트에 재인증 단계 누락 | '…데스크에서 고쳐드려요 — 고친 뒤 같은 번호를 다시 인증하면 연결돼요. 아직 회원이 아니라면…' |
| 5 LOW | notFound 힌트 정밀화 | '…데스크에서 번호를 고치거나 등록한 뒤 같은 번호를 다시 인증하면 이름 확인 한 번으로 연결돼요.' |
| 6 LOW | pending 힌트가 전화·주소 없으면 거짓 | '승인이 늦으면 센터 데스크에 문의해주세요.' |
| 7 MED | matched 카드 '제가 아니거나 다른 센터예요' — v1 단일 센터 | 제목 '제가 아니에요'(부제 유지), 클래스 `_JoinOtherCenterCard` → `_NotMeCard`. lies 검사어 '다른 센터로' → '다른 센터', seeds에 matched·declined 추가해 **6단계 전부** stage별 테스트 |
| 8 LOW | 옛 라벨 인용 주석 | `grep -rn '다른 번호로' app/lib` = 0건('번호 다시 인증하기' / `_restartLabel` 참조 표현) |
| 9 LOW | 계약 메모 위치 | API계약 v2.27 'DELETE /v1/me — 미연결 계정' 응답 예시 아래 역참조 한 줄 |
| 10 LOW | settled 완료 문구 | `unlinkedCompletionMessage(trace)` 메서드: settled·건수>0 → '계정과 가입 요청 기록을 삭제했어요.', 그 외 >0 → '계정과 보낸 가입 요청을 삭제했어요.', 0 → '계정을 삭제했어요.' |
| 11 LOW | privacy.html:225 기기 사본 삭제 시점 | '계정 연결이 끝나거나 앱에서 계정을 삭제하면 삭제됩니다.' |

- 테스트: auth_state_test(+3, 로컬 단독 → unknown / 서버 pending+로컬 / clearServerJoinStatus), auth_view_model_test(+2,
  checkConnection null 지움 / applyServerJoinStatus(null)), center_confirm_screen_test(lies 6단계 분리 + '제가 아니에요' 앵커 +
  서버 pending 기준 갱신 + 로컬 단독 헤지 + matched → 회원 고지·배너 + 힌트 상수 3종), account_deletion_test(단위 2건 + settled
  완료 위젯 + phoneMatched 배너), account_deletion_api_test(메서드 호출).
- 뮤테이션 2건(전부 KILLED, 원복 확인):
  1. `_openAccountDeletion`의 matched → unknown 분기 제거 → center_confirm_screen_test 'matched에서 계정 삭제 → 회원 고지 + 배너' 1건 사망
  2. `joinRequestTrace`가 로컬 기록(joinRequestedAt)으로도 pending → auth_state_test '로컬 기록만 있으면 unknown', auth_view_model_test
     2건(checkConnection null 지움·applyServerJoinStatus(null)), center_confirm_screen_test '로컬 기록만 있는 대기 화면은 "있다면"으로 헤지' — 4건 사망
- 자문자답: (a) 이슈 2로 requestJoin 직후 고지가 unknown이 되지 않나 → 아니다, `requestJoin`은 `serverJoinStatus: 'pending'`을 함께
  세운다(P56). (b) matched를 unknown으로 열면 처음 온 사람(진짜 미연결)은 과다 고지를 읽는다 → 배너가 "아직 연결 전이라면 로그인
  계정과, 보낸 가입 요청이 있다면 그것만"으로 밝히고, 완료 안내는 서버 `member_id`로 사실을 말한다(기존 규약). (c) `checkConnection`이
  joinStatus null로 옛 pending을 지워도 로컬 `joinRequestedAt`은 남아 화면은 대기 카드 유지 — 화면과 고지의 근거를 일부러 분리했다
  (화면은 틀려도 재확인 버튼이 있어 손해가 없고, 고지는 지워질 문서의 모양을 말하는 자리).

## 후속 작업
- 이 변경을 실을 빌드 번호(1.0(5)) 확정과 스토어 트랙 분리 — 람 결정.
- P56 후속 목록 7·9 완료 표기 + 이 P 링크 — P56 파일은 이 체인의 범위 밖이라 건드리지 않았다(오케스트레이터가 합친다).
- docs/design/스플래쉬_기동경로.md:289·스플래쉬_교차검증.md:306의 `_ConnectionUnknownCard` 인용은 스냅샷 — 다음 문서 개정 때.
- 센터 전화가 채워지면(P56 L7) 연락 카드에 통화 버튼이 자리를 채운다 — 힌트 문장은 hasPhone과 무관해 그대로.

## 참조
- 설계·검토: scratchpad `design_APPCOPY.md`, `review_APPCOPY_1.md`, `review_APPCOPY_3.md`
- P56 후속 7·9(감사 원본) · P59 A1(삭제 문·스크롤 구조) · P55(대기실 단일 판별자) · P57/계약 v2.27·v2.28(거절 시 이름·번호 비움,
  미연결 삭제 응답 키) · account_deletion_screen.dart 헤더 "과소 고지는 거짓"

## 에뮬레이터 실측 (2026-09-06, 오케스트레이터 — 디버그 빌드 + 프로덕션 백엔드, 테스트 번호 010-5555-6666)
| 화면 | 확인 |
|---|---|
| notFound | 제목 '아직 연결된 센터가 없어요' · 부제 '인증한 번호로 등록된 회원을 찾지 못했어요' · 경고 카드 없음 · 연락 카드 힌트("…같은 번호를 다시 인증하면 연결돼요") · CTA · '번호 다시 인증하기' · 하단 링크 (n1.png) |
| 계정 삭제(unknown) | 경고 상자·목록 모두 '보낸 가입 요청이 있다면 …'로 헤지 (n2.png) |
| pending | 카드 본문 한 문장 · 배지 없음 · 힌트 '승인이 늦으면 데스크에 문의할 수 있어요.' (n3.png); 강제 종료 후 재실행 → 대기 화면 복원 |
| 계정 삭제(pending) | 목록 '보낸 가입 요청 (이름·전화번호)' · 다이얼로그 '보낸 가입 요청과 인증 계정을 삭제해요…' (n6.png) |
| 완료 | 스낵바 '계정과 보낸 가입 요청을 삭제했어요.'(서버 purged.join_requests=1) → 로그인 화면 (n7.png) |
| 서버 | join_requests 1→2→1 원상 · Identity Toolkit 테스트 번호 계정 0건 |
