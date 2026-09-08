---
id: P59
title: 회원앱 결함 수리 — 미연결 계정 삭제 문(A1·B4·B5) · isFallback 전파(H1/H3/H4) · 제출 중 시트 잠금(M1/M2) · FAB 색 안내(M4)
status: 완료
domain: app
created: 2026-09-04
completed: 2026-09-04
---

# P59 — 회원앱 결함 수리(P56 후속, app/ 전용)

## 목표
P56 감사가 남긴 앱 항목을 우선순위 순으로 닫는다. **`app/`만 만졌다** — backend·admin·docs·
`app/assets/legal/*.md`는 다른 갈래(P57·P58)가 동시에 편집 중이라 불가침.

1. **A1+B4+B5 (CRITICAL·개인정보보호법 §36)** — 대기실 계정의 앱 내 삭제 문 + 마이 탭
   로그아웃·탈퇴·법정고지를 데이터 로드와 분리 + 로그인 전 화면 법정 링크.
2. **H1/H3/H4 (HIGH)** — `CenterPolicy.isFallback`을 읽는 곳이 8곳 중 1곳뿐. 폴백 숫자를
   사실처럼 찍는 자리(문구)와 폴백 상한으로 서버가 통과시킬 신청을 막는 자리(동작).
3. **M1/M2 (MEDIUM)** — 제출 중 시트를 쓸어 닫으면 실패가 삼켜지는 7곳 + 탈퇴 화면.
4. **M4 (LOW)** — "아래 가운데 빨간 버튼"(FAB는 P54부터 네이비).

## 결정 사항

### A1 — 미연결 삭제의 고지는 회원 고지와 **목록 자체가 다르다**
서버 `deleteUnlinkedAccount`(v2.27)가 실제로 하는 일은 셋뿐(Firebase 계정·가입 요청·로그인
매핑). 회원 화면을 그대로 쓰면 회원권도 사진도 없는 사람에게 "체형사진이 삭제되고 회원권
내역은 5년 보관돼요"라고 말하게 된다 — 없는 것에 대한 고지는 소음이고, `account_deletion.dart`
헤더가 경고한 "서버가 하는 일과 한 줄씩 대응"이 깨진다. `AccountDeletionScope` 3값:
- `member` — 종전 그대로.
- `unlinked` — 제목 "계정 삭제", 파기 목록 2줄(`unlinkedDeletionPurgedItems`), 5년 보존 카드
  **대신** "여기서 지워지지 않는 정보"(데스크 등록 회원 카드는 앱 계정과 별개 — 센터에 직접
  요청), 회원권 상자 없음, 완료 문구 "계정과 보낸 가입 요청을 삭제했어요"(탈퇴라 쓰지 않음).
- `unknown` — `connectionUnknown` stage 전용. 이미 연결된 회원이 네트워크 실패로 대기실에 선
  것일 수 있고 그때 서버는 회원 경로(전체 파기)를 돈다 → **회원 고지를 그대로** + 배너. 과소
  고지는 거짓이지만 과다 고지는 아니다. 요청서의 "모든 stage"는 지키되 이 stage만 고지가 다르다.

### A1 — 성공 뒤 정리는 `restartWithNewPhone()` + 로컬 대기 기록 삭제
종전 `_signOut`은 `FirebaseAuth.signOut()`만 불러 keepAlive `authViewModelProvider`에 지운 계정의
번호·매칭·대기 상태가 남았다(my_screen `_logout`이 이미 경고한 가족 공용폰 사고). 대기실 계정은
`JoinRequestStore`의 로컬 기록도 지워야 한다 — 서버가 가입 요청을 파기했으므로 남기면 같은
번호로 재인증 시 보낸 적 없는 "승인 대기 중"이 뜬다. 회원 scope에도 같은 경로를 태운다(무해).

### B4 — 로그아웃·탈퇴·약관은 `async.when` **바깥**, 로딩 중에도 보인다
지속 403 계정(권한 상실·탈퇴 잔여 인덱스)은 401이 아니라 세션이 안 비워져 재설치가 유일한
탈출구였다. `RefreshIndicator > ListView[ ...when(...), LegalLinksCard, _CenterCard ]`로 재배치 —
에러 뷰와 행이 **함께** 보인다(숨기는 게 아니다). 새로고침도 상태와 무관하게 열림.

### B5 — 대기실 하단 링크 + 대기실을 **스크롤 가능**하게
링크 한 줄(≈44dp)을 더하자 320×568에서 고정 Column이 34px 넘쳤다(기존 좁은 화면 테스트가
잡았다). 글자 배율 1.35에선 그 전부터 넘쳤을 자리 → `LayoutBuilder + SingleChildScrollView +
ConstrainedBox(minHeight) + IntrinsicHeight`(Spacer 보존). 전화·코드 화면은 **넣지 않았다** —
Column이 비스크롤이고 키보드가 올라오면 568dp에서 넘칠 위험이 커서 후속으로 남긴다.

### H4 — 폴백이면 상한 판정을 **끈다**, 표시는 "확인하지 못했어요"
`HoldRules.evaluate/allowance(capsUnknown:)` 신설. 판정과 표시가 같은 파일·같은 플래그를 받아
"남았다고 써 있는데 거부당한다/막혀 있는데 남았다고 쓴다" 불일치가 구조적으로 안 생긴다.
-1(무제한)로 넘기는 편법을 기각 — 무제한은 서버가 준 사실이고 폴백은 아무것도 못 받은 상태라
`HoldAllowance`가 "제한 없음"이라 말하게 된다. 정책과 무관한 검사(상태·구간·겹침)는 그대로.

### H3 — 취소 마감뿐 아니라 **위약금율의 폴백**도 같은 취급
`c.penaltyRate ?? policy.penaltyRate`에서 스냅샷 없는 레거시 계약 + 폴백이면 10%를 사실처럼
찍었다. v1.5 이후 계약은 스냅샷이 있어 도달 어려운 모서리지만 같은 클래스라 함께 닫았다
(문구만 — 서명 차단은 하지 않는다: P44 §D ④ "전문 열람 불가가 서명을 막아선 안 된다"와 같은
결로 요약 고지 경로는 유지).

### M1 — 래퍼 옵션 `showRiseSheet(submitting: ValueListenable<bool>)`
`isDismissible/enableDrag`는 라우트 생성 시점에 굳어 제출 순간에 켤 수 없다. 래퍼가 본문을 감싸
세 경로를 막는다: 스크림 탭·시스템 백은 `PopScope(canPop:false)`(둘 다 `maybePop`), **쓸기는
PopScope가 못 막는다** — `BottomSheet.onClosing → Navigator.pop`(SDK 실측) — 잠금 중 본문 바깥에
세로 드래그 인식기를 두어 아레나에서 먼저 이긴다. 트리 모양은 잠금과 무관하게 같다(감싸는
식이면 State가 재생성돼 잠금 신호 자체가 사라진다).
**신호 저장소는 노티파이어 하나** — 시트 State의 `_submitting`은 getter(`widget.submitting.value`).
bool 필드 미러링을 기각한 이유: 실패 분기 한 곳에서 미러를 빠뜨리면 시트가 영원히 잠긴다.
7곳 배선(예약 확정·홀딩·동의·계약 서명·인바디·재등록·가입 요청). `_reading`(인바디 OCR)은
범위 밖으로 남겼다.

### 테스트 하네스의 "폴백 기본값"을 서버 정책으로
`hold_precheck_test`·`cancel_flow_test`의 pump 기본값이 `CenterPolicy.fallback`이었다 — 이제
폴백은 "정책을 모르는 상태"라 판정 문구가 안 나오는 게 정답이다. 숫자가 같은 서버 정책 상수로
바꾸고 폴백 동작은 별도 그룹으로. **발견**: `cancel_flow_test`의 다이얼로그 4건은 P56 H2(9/3
08:21 반영)와 이미 어긋나 있었다(폴백 기본값으로 "세션 1회가 차감돼요"를 기대) — 내 변경과
무관한 기존 불일치. H2 폴백 다이얼로그 테스트도 없어서 함께 추가.

## 진행 단계
- [x] P 클레임 + 실태 조사(P55·P56·대상 파일 전수 읽기)
- [x] 기반: `showRiseSheet(submitting:)` · `openLegalDocument` · `HoldRules.capsUnknown` · 탈퇴 scope
- [x] A1/B4/B5 — 대기실 footer·삭제 진입·스크롤 · 탈퇴 화면 3-scope · 마이 탭 when 바깥
- [x] H1/H3/H4 — 6자리 전파(bookings note·pass_list 2·sign sheet 2·hold sheet)
- [x] M1/M2 — 시트 7곳 배선 · 탈퇴 화면 PopScope
- [x] M4
- [x] 테스트 + 뮤테이션 16/16 + analyze/test 전건

## 변경 파일
**lib** — `core/widgets/rise_sheet.dart`(submitting 옵션·`_SubmitLock`) · `core/widgets/legal_document_link.dart`(신규) ·
`core/policy/`(무변경) · `features/my/domain/{hold_rules,account_deletion}.dart` ·
`features/my/presentation/{account_deletion_screen,my_screen}.dart` ·
`features/my/presentation/widgets/{legal_links_card,hold_request_sheet,contract_sign_sheet,consent_toggles,pass_list}.dart` ·
`features/auth/presentation/center_confirm_screen.dart` ·
`features/booking/presentation/widgets/{booking_confirm_sheet,my_bookings_list}.dart` ·
`features/records/presentation/widgets/{inbody_add_sheet,body_photo_timeline}.dart` ·
`features/consult/presentation/widgets/consult_request_sheet.dart`

**test** — 신규 `core/widgets/rise_sheet_submit_lock_test.dart` · `features/my/presentation/my_screen_shell_rows_test.dart` ·
확장 `center_confirm_screen_test` · `account_deletion_test` · `hold_precheck_test` · `contract_sign_flow_test` ·
`cancel_flow_test` · `destructive_confirm_test` · `hold_rules_test` · `body_photo_timeline_test`

## 검증
- `flutter analyze` 0 · `flutter test` **1265 pass**(착수 1221 → +44, 회귀 0)
- 실기기·에뮬레이터 미사용(다른 세션과 충돌 방지) — 전부 위젯 테스트
- 뮤테이션 **16/16 KILLED** (되돌린 것 → 죽인 테스트):

| # | 항목 | 되돌린 것 | 죽인 테스트 |
|---|---|---|---|
| M1 | A1/B5 | 대기실 `_LobbyFooterLinks` 제거 | center_confirm_screen_test 10건(stage 6·진입·unknown·44dp·320px) |
| M2 | B4 | 약관·센터 카드를 `data` 브랜치 안으로 | my_screen_shell_rows_test 실패·로딩 2건 |
| M3 | H3 | 취소 마감 `isFallback` 분기 제거 | contract_sign_flow_test 폴백 |
| M4 | H4 | 시트 `_rejection`의 `capsUnknown` 제거 | hold_precheck ④ 2건 |
| M5 | H1 | 내 예약 노트 분기 제거 | cancel_flow_test 안내 문구 폴백 |
| M6 | H1 | pass_list 진입 행 분기 제거 | hold_precheck ④ 라벨 |
| M6b | H1 | pass_list 재개 다이얼로그 분기 제거 | destructive_confirm_test 폴백 |
| M7a | M1 | 래퍼 `PopScope(canPop:true)` | submit_lock_test 스크림·백(쓸기는 생존 = 경로 독립 실증) |
| M7b | M1 | 래퍼 드래그 인식기 콜백 null | submit_lock_test 쓸기 |
| M8a | M1 | 홀딩 시트 `submitting:` 인자 제거 | hold_precheck ⑤ |
| M8b | M1 | 가입 요청 시트 `submitting:` 제거 | center_confirm_screen_test 가입 시트 |
| M9 | M2 | 탈퇴 화면 `PopScope(canPop:true)` | account_deletion_test M2 |
| M10 | M4 | "빨간 버튼" 복원 | body_photo_timeline_test |
| M11 | H4 | `HoldRules.evaluate`의 `capsUnknown` 조기 반환 제거 | hold_rules_test 2건 + hold_precheck ④ |
| M12 | A1 | 탈퇴 화면 scope 무시(회원 목록 고정) | account_deletion_test unlinked + 대기실 진입 |
| M13 | A1 | `_signOut`의 대기 기록 삭제 제거 | account_deletion_test unlinked 성공 경로 |

## 자문자답
1. **미연결 삭제 확인 문구가 회원 삭제와 어떻게 달라야 하나?** 목록 자체가 다르다 — 서버가
   실제로 하는 일(v2.27 ②⑤⑦)만 적고, 5년 보존 카드는 그리지 않는다(보존할 기록이 없다).
   대신 실제로 남는 것 하나(데스크가 따로 등록한 회원 카드)와 그것을 지우는 다음 행동을 말한다.
   완료 문구도 "탈퇴"가 아니라 "계정과 보낸 가입 요청을 삭제했어요".
2. **`matched` stage에서 삭제하면 센터 회원 레코드가 지워지나?** 아니다 — 확인 전이라 principal에
   `member_id`가 없어(`JoinConfirm`이 `SaveUserIndex`) 서버는 미연결 경로를 돈다. 그래서 unlinked
   고지가 맞고, 데스크 레코드가 남는다는 사실을 "여기서 지워지지 않는 정보"가 말한다.
3. **`connectionUnknown`에서도 문을 열어야 하나?** 열되 고지를 바꾼다. 닫으면 §36 접근이
   네트워크에 가로막히고, unlinked 고지로 열면 연결된 회원의 사진·기록 파기를 숨기는 거짓이 된다.
   회원 고지 + 배너가 유일하게 거짓이 없는 조합이다.
4. **H4에서 폴백 시 사전 차단을 끄면 서버 400을 보는 사용자가 늘지 않나?** 는다 — 하지만
   그게 낫다. (a) 늘어나는 건 "정책 조회가 실패한 상태에서 상한 근처인 회원"의 서버 응답 1회이고,
   그 400 문구는 서버가 실값으로 계산한 **정확한** 사유다. (b) 종전 동작은 센터 정책이 5회/90일인
   회원의 3·4·5회차 신청을 앱이 **영구히** 막았다(재시도해도 폴백은 그대로) — 서버가 통과시킬
   요청을 앱이 거부하는 것은 hold_rules 헤더가 명시적으로 금지한 동작이다. 사전 차단은 "확실히
   거부될 헛걸음 제거"이지 권한이 아니고, 확신이 없으면 서버가 판정해야 한다. (c) 폴백 상태는
   pull-to-refresh로 정책을 재조회하면 풀리므로 정상 상태에선 종전 UX 그대로다.
5. **M1을 래퍼 옵션(ValueNotifier)으로 할지, 시트 안 선언적 위젯으로 할지?** 래퍼 옵션 — 요청대로이고
   잠금이 라우트 루트에 걸려 본문 구조와 무관하다. 대신 "미러 누락 → 영구 잠금" 위험을
   저장소 단일화(getter)로 구조적으로 없앴다. 쓸기가 PopScope로 안 막힌다는 SDK 사실을 실측해
   두 경로를 따로 막고 따로 뮤테이션했다(M7a에서 쓸기 테스트가 살아남은 것이 그 증거).
6. **H3에서 위약금율까지 건드릴 필요가 있었나?** 스냅샷이 없는 레거시 계약에서만 도달하는
   모서리지만, 동의 직전에 폴백 요율을 사실처럼 찍는 자리라 같은 클래스다. 문구만 바꾸고 서명은
   막지 않았다(요약 고지 경로는 P28이 적법화한 기준선).

## 후속 작업
1. **[MEDIUM] 전화·코드 화면의 약관 링크** — 대기실에만 넣었다. 두 화면은 비스크롤 Column이라
   키보드가 올라온 568dp에서 넘칠 위험이 있어, 스크롤 가능하게 바꾼 뒤 같은 footer를 넣을 것.
2. **[LOW] `expiringDays` 폴백(7일)** — 홈 회원권 경고 임계가 폴백이면 센터 기준과 갈릴 수 있다.
   돈이 아니라 소프트 경고라 이번 범위 밖.
3. **[LOW] 인바디 시트 `_reading`(OCR 중) 잠금** — 제출 중과 같은 클래스(닫으면 결과가 사라짐).
4. **[LOW] 대기실 글자 배율 1.35 테스트** — 스크롤로 넘침은 해소됐지만 배율 테스트는 없다.
5. **[NOTE] `cancel_flow_test` 4건은 착수 시점에 이미 H2와 어긋나 있었다** — P56의 "1221 pass"는
   H2 반영 전 수치로 보인다. 이번에 하네스 기본값을 서버 정책으로 바꿔 정합시켰다.

## 참조
- P56(감사) · P55(대기실·v2.27) · P54(showRiseSheet 래퍼 선례) · P33(isFallback 도입) · P22/P53(탈퇴 고지)
