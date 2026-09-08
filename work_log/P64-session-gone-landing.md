---
id: P64
title: 세션 소멸 지뢰 — 종료 이유별 착지 · SessionGoneFailure · 셸 게이트 가드(P56 후속 5)
status: 완료
domain: app
created: 2026-09-06
completed: 2026-09-06
---

# P64 — 셸이 그려진 채 세션이 비는 순간의 정직성

## 목표
P56 후속 5번("4탭 뷰모델의 `AuthFailure('로그인이 필요해요')` 지뢰 — 게이트를 홈으로 옮기는 순간 되살아난다")의
읽기 전용 판정 → 수리. **전제 정정**: 'memberId 없는 세션'은 타입상 존재하지 않는다(`AppSession.memberId`
non-nullable). 실제 트리거는 **셸이 떠 있는 채 세션이 null이 됨** — 캐시 세션 재검증의 미연결 확답(D1·D2), dio 401,
로그아웃, 탈퇴. 그 순간 4탭이 '문제가 생겼어요 / 로그인이 필요해요 / [다시 시도]'를 그렸고(연결 해제면 문장이 거짓,
버튼은 세션을 만들지 못함), `app.dart` 리스너는 원인 불문 전화번호 화면으로 보내 **SMS 재인증을 강제**했으며,
촬영 탭은 손에 든 사진을 두고 조용히 return했다(D6). 플랫폼 초기 라우트가 `/home`이면 세션 없이 셸에 착지하는
구멍(D4)은 코드가 아니라 AndroidManifest의 VIEW 필터 **부재**에 기대고 있었고, 그걸 고정하는 테스트가 없었다(D5).

이 변경은 **스토어 1.0(4)에 들어가지 않는다** — 다음 빌드용. D1 노출은 ≤1프레임, D2는 드문 경로(다른 기기 탈퇴·연결 해제)라 핫픽스 사유가 아니다.

## 결정 사항
- **뷰모델은 문구를 말하지 않고 타입만 낸다; 원인과 착지는 세션을 비운 쪽이 말한다.** 뷰모델은 세션이 *왜* 비었는지
  모르므로 어떤 문장을 넣어도 절반은 거짓이다(401이면 "연결이 끊겼어요"가, 연결 해제면 "로그인이 필요해요"가 거짓).
  거짓 문장을 다른 거짓 문장으로 바꾸지 않는다.
- `SessionEndReason { signedOut, unauthorized, deleted, notLinked }` + `Session.clear({required reason})`(선택 인자
  금지 — 기본값을 두면 새 호출부가 조용히 전화번호 화면으로 떨어진다) + `lastEndReason`(notifier 필드 — 리스너는 null이 된
  **뒤에** 불리므로 상태에 실을 수 없다; `set()`이 지운다; 리스너는 읽은 뒤 되돌리지 않는다 — 재등록 시 두 번 읽힐 수 있다) +
  순수 함수 `sessionEndRoute(reason)`: notLinked → `/login/center-confirm`, 나머지 → `/login`.
- **[람이 되돌릴 수 있는 제품 판단] 연결 해제 확답 시 착지를 전화번호 화면(SMS 재인증)에서 대기실로 바꿨다.** 신원(Firebase)
  은 살아 있고 센터 연결만 사라진 상태라 재인증(건당 비용)을 시킬 이유가 없고, 대기실이 서버 상태(거절·대기)를 보여 준다.
  "연결이 끊긴 사람은 처음부터 다시 인증시키고 싶다"는 운영 의도가 있으면 `sessionEndRoute`의 notLinked 한 줄만 지우면 된다.
- **콜드스타트 착지 규칙도 함께 바뀜(검증 반영)**: `restoreLandingRoute`의 notLinked가 `sessionEndRoute(notLinked)`(대기실)로
  고정됐다 — 종전엔 로컬 대기 기록이 없으면 null(전화번호 화면)이라 같은 회원·같은 서버 상태가 **캐시 유무**로 갈렸다
  (캐시 있음 → 홈 → 재검증 → 대기실 / 캐시 없음 → SMS 재인증). 착지 문자열을 한 함수에서 가져와 두 경로가 갈릴 수 없다.
  `hasPending` 인자는 삭제(착지에 더는 관여하지 않는다). 대기실 신원(phone·로컬 대기 기록 복귀)은 `seedLobbyIdentity`가
  콜드스타트·재검증 양쪽에서 세운다.
- `_revalidate` notLinked 분기는 **콜드스타트 경로와 같은 규약**으로 `applyServerJoinStatus(f.joinStatus, requestedAt:)`를
  먼저 부른다 — 이 호출이 없으면 대기실이 서버 상태를 모른 채 빈 화면으로 뜬다(종전엔 이 경로만 이 값을 읽지 않았다).
  판정 본문을 `applyRevalidation(read:, result:, joinStore:)`로 분리해 FirebaseAuth·위젯 수명 의존 없이 세 갈래를 테스트한다.
- `SessionGoneFailure extends AuthFailure`(기존 `is AuthFailure` 분기·재시도 정책 그대로 성립). 4탭 화면 error 브랜치는
  `e is SessionGoneFailure` → `SessionGoneView`(스피너 + **3초 뒤 '로그인 화면으로'** — 리스너가 이동하지 못했을 때의,
  세션을 요구하지 않는 탈출구; 착지는 리스너와 같은 `sessionEndRoute`). **[다시 시도] 없음.** 마이 탭의 로그아웃·탈퇴 행은
  `when` 바깥(P56 B4)이라 전환 뷰에 갇혀도 남는다.
- 촬영 `capture`/`confirmReview`/`retryPendingUpload`의 조용한 return 3곳 → `state.error = SessionGoneFailure()`.
  `review`/`pendingRetry`는 **리스너가 화면을 내릴 때까지 상태를 무너뜨리지 않는다**는 뜻이지 바이트를 살려 두겠다는 약속이
  아니다 — 화면이 내려가면 autoDispose로 바이트도 사라지며 이는 의도다(세션 없는 사진은 올릴 주인이 없다; 검증 반영으로 정정).
  홈의 부분 갱신(`selectPass`·`toggleHomework`) 조용한 return은 유지(잃을 바이트가 없고 알릴 상대가 없다 — 주석으로 명시).
- 라우터: `overridePlatformDefaultLocation: true`. go_router는 플랫폼 기본 라우트가 '/'가 아니면 `initialLocation`을 덮어쓴다
  (`_effectiveInitialLocation`) — 이 앱엔 딥링크가 없다. 딥링크 도입 시 이 플래그를 풀고 redirect에 "복원 null이면 셸 경로를
  /login으로" 가드를 넣어야 하며, `shell_gate_test`가 그 회귀를 잡는다.
- 정적 가드(`test/tool/session_message_guard_test.dart`): `lib/` 코드에 `'로그인이 필요해요'` **정확한 리터럴** 0건(주석 제외;
  진짜 401을 말하는 다른 문구는 대상 아님) + 인자 없는 `sessionProvider.notifier).clear()` 0건 + 이유 있는 호출 ≥4(가드가
  헛돌지 않는지).
- 게이트를 홈으로 옮기지 않는다(P55/P56 유지). 서버·계약·법정문서 무변경(4칸: 서버는 이미 `member_id` 키 부재 + `join_request`를
  싣고, 와이어 변경 없음, 개인정보 흐름 불변).

## 진행 단계
- [x] 판정(design_MINE) — 전제 정정·D1~D6·(c)+(b) 채택(적대 검토는 한도 초과로 오케스트레이터 직접 검토)
- [x] `SessionEndReason`·`clear(reason:)`·`lastEndReason`·`sessionEndRoute` + 호출부 4곳(401·로그아웃·탈퇴·재검증)
- [x] `applyRevalidation` 분리 + notLinked 분기의 `applyServerJoinStatus`
- [x] `app.dart` 리스너 이유별 착지 · `SessionGoneFailure` · `SessionGoneView` · 4탭 VM/화면 · 촬영 3곳
- [x] `overridePlatformDefaultLocation: true` + D4 주석
- [x] 테스트 T1~T8 + 정적 가드 + 뮤테이션 3건 + 전체 flutter test
- [x] P64 + README
- [x] 검증 반영 11건(아래 절) + 뮤테이션 2건 + 전체 flutter test

## 변경 파일
- `app/lib/core/session/session_provider.dart` — enum·`sessionEndRoute`·`lastEndReason`·`clear({required reason})`
- `app/lib/core/session/session_gone_view.dart` — 신설(전환 뷰, `escapeAfter` 기본 3초)
- `app/lib/core/result/failure.dart` — `SessionGoneFailure`
- `app/lib/core/router/app_router.dart` — `overridePlatformDefaultLocation: true` + 근거 주석, 헤더 주석 갱신
- `app/lib/app.dart` — 리스너가 `sessionEndRoute(lastEndReason ?? unauthorized)`로 착지
- `app/lib/features/auth/presentation/session_restore.dart` — `applyRevalidation` 분리, notLinked 분기 보강
- `app/lib/core/network/dio_client.dart`(unauthorized) · `features/my/presentation/my_screen.dart`(signedOut) ·
  `features/my/presentation/account_deletion_screen.dart`(deleted, clear 1줄만)
- `app/lib/features/{home,booking,records,my}/presentation/*_view_model.dart` — throw/Err → `SessionGoneFailure`
- `app/lib/features/{home,booking,records,my}/presentation/*_screen.dart` — error 브랜치 `SessionGoneView` 분기
  (booking의 `?? ''` 폴백에 '한 프레임용' 주석)
- `app/lib/features/bodycheck/presentation/camera_view_model.dart` — 조용한 return 3곳
- 테스트 신설: `test/core/router/shell_gate_test.dart`(T1·T2) · `test/core/session/session_end_route_test.dart`(T4, 6건) ·
  `test/core/session/session_gone_view_test.dart`(4건) · `test/features/auth/presentation/session_revalidate_test.dart`(T3, 4건) ·
  `test/features/{home,booking,records,my}/presentation/*_session_gone_test.dart`(T5, 각 1건) ·
  `test/tool/session_message_guard_test.dart`(T7, 2건)
- 검증 반영 변경: `core/session/session_provider.dart`(`sessionListenerRoute`·clear 재진입 가드) · `core/session/session_gone_view.dart`
  (`sessionGoneEscapeLabel`) · `core/widgets/rise_snack_bar.dart`(`showFailureSnackBar`·`action`) · `core/result/failure.dart`(dartdoc) ·
  `features/auth/presentation/session_restore.dart`(착지 규칙·`seedLobbyIdentity`·`applyRevalidation(phone:)`·null 가드) ·
  `features/auth/presentation/auth_view_model.dart`(`restoreSignedInPhone`·requestJoin 빈 번호 가드) ·
  `features/bodycheck/presentation/camera_screen.dart`·`camera_view_model.dart` · `features/{home,booking}/presentation/*_screen.dart` ·
  `features/records/presentation/widgets/{inbody_recent_list,body_photo_viewer}.dart` · `features/my/presentation/{my_screen,account_deletion_screen}.dart` · `app.dart`
- 검증 반영 테스트 신설: `test/core/session/session_listener_route_test.dart`(4) · `test/core/widgets/failure_snack_bar_test.dart`(3) ·
  `test/features/bodycheck/presentation/camera_screen_session_gone_test.dart`(2). 갱신: `session_restore_test`·`session_revalidate_test`(+4) ·
  `session_end_route_test`(+2) · `session_gone_view_test`(+1) · `auth_view_model_test`(+1) · `tool/session_message_guard_test`(+1)
- 테스트 갱신: `camera_view_model_test.dart`(T6 그룹 3건 — 셔터 테스트는 프로필 future를 먼저 안착시킨다: 뷰모델이
  `myProfileProvider`를 watch해 그 future가 도중에 풀리면 재빌드로 error가 씻긴다) ·
  `session_clears_cache_test.dart`·`session_clears_photo_cache_test.dart`(`clear(reason:)`)
- `work_log/P64-session-gone-landing.md`, `work_log/README.md`

## 검증 반영 (2026-09-06, 이슈 11건 전부)
| # | 이슈 | 처리 |
|---|------|------|
| 1 | [HIGH] 콜드스타트 notLinked 착지 ≠ 재검증 착지 | `restoreLandingRoute` notLinked → `sessionEndRoute(notLinked)` 고정, `hasPending` 삭제. `seedLobbyIdentity`(phone 세팅 + 번호 맞는 로컬 기록 복귀)를 콜드스타트·재검증이 공유. `session_restore_test` 순수 함수 케이스 갱신(notLinked 2건 + null 금지 1건) |
| 2 | [MEDIUM] 재검증 경로 phone '' | `applyRevalidation(phone:)` 필수 인자(호출부가 `FirebaseAuth.currentUser?.phoneNumber` 전달, 미초기화면 null). `AuthViewModel.restoreSignedInPhone`(정규화, setPhone과 달리 발송 세션·매칭을 건드리지 않음). `requestJoin`은 `phone.isEmpty`면 로컬 기록을 저장하지 않는다(서버는 토큰 번호로 접수). 테스트: revalidate (a) phone 단언(로컬 기록 없이) + (a′)(a″), auth_view_model_test 1건 |
| 3 | [LOW] applyRevalidation 세션 null 가드 | 첫 줄 `if (read(sessionProvider) == null) return;` — 먼저 비운 쪽의 착지·캐시 삭제를 덮어쓰지 않는다. 테스트 (d) |
| 4 | [MEDIUM] SessionGoneFailure danger 스낵바 | 공통 헬퍼 `showFailureSnackBar(context, failure)`(rise_snack_bar.dart) 신설 — `is SessionGoneFailure`면 건너뜀. 4탭 액션 5곳(홈워크 토글·체크인·예약 취소·인바디 삭제·사진 삭제) + 촬영 리스너가 이 헬퍼를 지난다. `failure.dart` dartdoc을 사실대로. 테스트 `failure_snack_bar_test` 3건 |
| 5 | [MEDIUM] 촬영 바이트 보존 과잉 약속 | camera_view_model 주석·이 문서 정정("리스너가 내릴 때까지 무너뜨리지 않는다; 내려가면 autoDispose로 사라지며 의도"). camera_screen은 SessionGoneFailure에 중립 스낵바 '로그인 정보가 바뀌어 촬영을 닫아요' + 탈출 액션(라벨·착지는 SessionGoneView와 같은 규칙). `riseSnackBar`에 `action` 선택 인자. 테스트 `camera_screen_session_gone_test` 2건 |
| 6 | [MEDIUM] app.dart 리스너 미검증 | `sessionListenerRoute(prev, next, reason)` 순수 함수(session_provider.dart) — prev==null ∥ next!=null → null, 아니면 `sessionEndRoute(reason ?? unauthorized)`. 리스너는 읽고 옮기기만. 테스트 `session_listener_route_test` 4건 |
| 7 | [LOW] 탈출 버튼 라벨 | `sessionGoneEscapeLabel(reason)`: notLinked → '연결 상태 확인하러 가기', 그 외 '로그인 화면으로'. gone_view 테스트 갱신 + 라벨 단위 테스트 1건 |
| 8 | [LOW] 이중 이동 하드코딩 | my_screen `context.go(sessionEndRoute(signedOut))`. account_deletion_screen은 직접 이동 유지 + '대기실 scope는 세션이 없어 리스너가 안 돈다' 주석 + `sessionEndRoute(deleted)` |
| 9 | [LOW] `_signOut` mounted 게이트 | notifier·저장소·세션 notifier를 await 앞에서 잡고 mounted와 무관하게 `clear(reason: deleted)`. `Session.clear()`는 state가 이미 null이면 재진입으로 무시(이유·캐시 손대지 않음). session_end_route_test: '마지막 이유가 이긴다' → '재진입 무시'로 뒤집고 2건 추가 |
| 10 | [LOW] 정적 가드 정규식 | 파일 전체 텍스트(주석 제외, sessionProvider 등장 파일)에 `\.clear\(\s*reason:`(multiLine) 카운트 ≥4. bare 검사는 `sessionProvider.notifier)\s*.clear(\s*)` 직접 호출 + notifier를 변수에 담은 형태(`x = ref.read(sessionProvider.notifier)` → `x.clear()`) 둘 다. 지시의 `\.clear\(\s*\)` 무조건 적용은 `joinStore.clear()`·`sessionStore.clear()`를 오탐하므로 수신자를 한정했다. 추가로 `clear({required SessionEndReason reason})` 시그니처 자체를 고정하는 테스트 1건 |
| 11 | [LOW] go_router 버전 | 17.2.3 → 16.3.0(pubspec.lock). lib 주석엔 버전 인용이 없었다 |

- 뮤테이션 2건(전부 KILLED, 원복 확인):
  1. `restoreLandingRoute` notLinked → `null` 되돌림 → `session_restore_test` 'notLinked → 대기실' · '재검증 경로와 한 규칙' · 'null 금지' 3건 사망
  2. `seedLobbyIdentity`의 `restoreSignedInPhone` 호출 제거 → `session_revalidate_test` (a)(로컬 기록 없이 phone 단언) · (a″) 사망.
     처음엔 (a″)만 죽었다 — (a)의 로컬 기록이 번호와 맞아 `restorePendingJoinRequest`가 phone을 채워 누락을 가렸다. (a)를 기록 없이 시작하도록 바꿔 다시 실측.
- 자문자답: `Session.clear()` 재진입 무시는 대기실 scope 탈퇴(세션 null)에서 `lastEndReason`이 안 남는다는 뜻인데, 그 화면은 리스너가 아니라 직접 `sessionEndRoute(deleted)`로 가므로 무해 / `seedLobbyIdentity`는 unknown 착지에도 번호를 세운다 — 종전엔 로컬 기록이 맞을 때만 채웠는데, 재확인 화면의 `checkConnection`은 phone을 읽지 않아 동작 변화 없음, 대기실에서 보내는 가입 요청의 로컬 기록만 올바른 번호로 저장된다 / `showFailureSnackBar`는 시트 안의 인라인 에러(`_error = failure.message`, inbody_add_sheet·booking_confirm_sheet)를 건드리지 않는다 — 그 표면엔 중립 문구가 보이며 failure.dart dartdoc이 이를 말한다.

## 검증
- `cd app && flutter analyze` → No issues found.
- `flutter test` 전체 → **1338 통과**(P63 기준 1313 + 이 P 25건: shell_gate 2 · end_route 6 · gone_view 4 · revalidate 4 ·
  4탭 4 · guard 2 · camera 3). 검증 반영 후 재실행 → **1370 통과**(analyze 0건).
- **T1은 옛 코드에서 먼저 실패했다**(D4 증거): `overridePlatformDefaultLocation: true`를 뺀 상태에서 shell_gate_test 첫 테스트가
  "세션 없이 셸에 들어갔다"로 실패 → 플래그 복원 후 통과. 둘째 테스트(대기실 착지)는 플래그 없이도 통과 — 복원이 라우트를
  돌려주는 한 redirect가 살아 있어서, 그쪽이 지키는 규칙은 별개다(파일 주석에 명시).
- 뮤테이션 3건(전부 KILLED, 원복 확인):
  1. `sessionEndRoute`를 항상 `/login` → `session_end_route_test` 'notLinked → 대기실' + `session_gone_view_test` '탈출 버튼은
     리스너와 같은 규칙' 사망
  2. `applyRevalidation` notLinked 분기의 `applyServerJoinStatus` 호출 제거 → `session_revalidate_test` (a) 사망
     (`serverJoinStatus` expected 'rejected', actual null)
  3. `overridePlatformDefaultLocation: true` 제거 → `shell_gate_test` T1 사망
- 자문자답: 4탭 테스트는 `pumpAndSettle`을 못 쓴다(전환 뷰의 스피너가 영원히 돈다) → pump 2회 / 저장소 provider는
  `throw StateError`로 덮어 "뷰모델이 세션 검사에서 멈춘다"까지 함께 고정 / `Session.clear()`가 캐시를 지우므로 재검증의 명시적
  `sessionStore.clear()`와 합쳐 2회 지운다 — 무해(명시 await는 세션이 뒤집히기 전에 캐시가 사라지는 순서를 보장), 테스트는 ≥1로
  단언 / 위젯 테스트의 가짜 시계에서 `Timer`는 `pump(Duration)`으로만 돈다.

## 후속 작업
- **람 결정**: notLinked 착지 = 대기실(재인증 없음) 유지 여부. 되돌리려면 `sessionEndRoute` notLinked 한 줄.
- 포함 빌드(1.0(5)+) 확정 — 스토어 1.0(4) 트리엔 지뢰가 그대로 있다(노출 ≤1프레임, D2는 해당 회원이 체감).
- D3(재검증 완료 전 4탭 403 → '요청을 처리할 수 없어요')는 캐시-선진입 설계의 본질적 창이라 남긴다. 403을 MemberNotLinked로
  재분류하는 건 정상 거절과 섞여 하지 않는다.
- 딥링크 도입 시 `overridePlatformDefaultLocation` 해제 + redirect 셸 가드 — `shell_gate_test`가 알려준다.
- P56 후속 5번 갱신(전제 정정 + 이 P 링크) — P56 파일은 이 체인 범위 밖(오케스트레이터가 합친다).
- (선택) `docs/API계약_v1.md` v2.27 절에 '캐시 세션 재검증에서도 `join_request`를 읽는다' 한 줄 — 와이어 변경 없어 이번엔 넣지 않았다.

## 참조
- 설계: scratchpad `design_MINE.md`(D1~D6, T1~T8) · P56 후속 5(:226) · P55(:37-40 최초 진단) · P32(clear 단일 지점) ·
  P54/P46(재시도 정책) · go_router 16.3.0(pubspec.lock 실제 버전) `router.dart` `_effectiveInitialLocation`
