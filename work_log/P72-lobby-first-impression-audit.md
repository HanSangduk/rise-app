---
id: P72
title: 대기실 첫인상 검수 — 앱 최초 설치자 관점 기획·디자인 교차검증
status: 완료
domain: app
created: 2026-09-13
completed: 2026-09-13
---

# P72 — "앱 처음 깔았는데 이 화면이 어색하지 않나"

## 목표 (람 요청)
회원이 앱을 **처음 설치**했을 때 대기실(`/login/center-confirm`)이 어색하거나 이상하지 않은지,
기획 3팀 · 디자인 3팀 병렬 투입 → 교차검증 → 자문자답 → 완성도 개선.

## 착수 시점 구조 (실측, P55/P63/P69 누적)
- 대기실 = 로그인 스택 3번째 화면 1장. 셸 밖, AppBar·백 없음(`PopScope` 확인 다이얼로그).
- `CenterConfirmStage` 6갈래가 제목·부제·본문·CTA를 **단독 결정**(auth_state.dart).
- 신규 설치자 경로: 전화번호 → SMS → `POST /v1/join/match` **1회** → 미매칭이면 `notFound`.
- pending: `LobbyAutoCheck` 30s 폴링 + 스텝퍼 + 확인 상태 줄 + 센터 카드.

## 자 (스킬 §0 — 고치기 전에 만든 것)
| 자 | 착수 | 완료 |
|---|---|---|
| `flutter analyze` | 0 issues | 0 issues |
| 전체 스위트 | **1477 pass** | **1497 pass** (+20) |
| 대비비(WCAG 2.1 계산) | 측정 수단 없음 | `test/core/theme/contrast_test.dart` 7건 |
| 대기실 최소 글자 | 10.0px | 11.5px (`lobby_accessibility_test`) |
| 320×568 주 CTA 위치 | **재는 자 없음**(`find`가 화면 밖도 잡아 초록) | 접힘 안 단언 |
| `features/auth` Semantics | **0건** | 스텝퍼 4단계 + liveRegion 2곳 |

## 조사 (읽기 전용 6팀 · 파일:줄 근거 · [근거]/[추측] 분리)
G1 신규 설치자 0~90초 · G2 카피/용어/정보구조 · G3 운영현실/전환/엣지 ·
D1 시각위계/레이아웃 · D2 접근성/타이포/대비 · D3 상태전이/모션/피드백. 총 48개 지적.

**교차검증 — 핵심 주장 8건을 직접 열어 확인**(조사 결과를 그대로 믿지 않는다):
JoinApprove 409 가드 문구 · `checkConnection`이 `join/match`를 안 부름 ·
`text_scale_overflow_test.dart` 부재 · `_CenterCard` 보더 없음 · `isVertical` 임계 ·
`features/auth` Semantics 0건 · `bottomSheetTheme` 없음 · `darkTheme` 없음 → **전부 사실**.

## 결정 사항

### C1 (CRITICAL) 대기실이 보던 문과 연결이 만들어지는 문이 달랐다
회원이 요청을 보낸 뒤 **데스크가 그 사람을 직접 등록하면**(가장 자연스러운 순서) 대표는 큐에서
승인할 수 없다 — `JoinApprove`가 중복 번호 409로 막는다("같은 번호로 등록된 회원이 이미 있어요
… 회원에게 앱에서 '번호 다시 인증하기'를 눌러 달라고 안내해주세요"). 그런데 `GET /v1/me`는
uid→UserIndex만 보므로 앱은 영원히 "아직"을 받고, 연결을 만드는 유일한 호출
`POST /v1/join/match`는 **코드 인증 직후 1회**만 돌았다. 즉 그 창을 놓친 사람은 SMS 재인증
말고는 구조적으로 연결 불가였고, 화면은 "센터가 승인하면 연결돼요"라고 약속하며 폴링만 했다.
서버 문구가 **사람의 안내를 전제**하고 있다는 사실이 이 경로의 실재 증거다.

→ `checkConnection`이 notYet일 때 `join/match`를 1회 더 묻는다(`_rematchInLobby`). JoinMatch는
읽기 전용·멱등이고 프로덕션은 번호를 토큰에서 강제로 가져오므로 새 표면이 없다. 새 결과
`ConnectionCheck.nowMatched` — 화면은 `matched`로 바뀌고 **홈으로 보내지 않는다**(남의 계정에
붙지 않게 막는 이름 확인 1탭을 건너뛸 수 없다).
→ `notFound`·`declined`에도 자동 확인 + [지금 확인]을 연다. 그 단계엔 확인 수단이 **아예
없었다** — 힌트가 "데스크에서 번호를 고친 뒤"를 지시하면서 끝났는지 물어볼 버튼이 없었다.
→ 기다리는 대상이 다르므로 꼬리 문장을 가른다(`CheckAwaiting`): 승인 ↔ **등록**.
**P63이 "다음 확인부터 연결"을 기각한 사유("지금 앱이 매칭을 다시 하지 않는다")는 여기서 소멸한다.**

### C2 전제가 실패한 뒤에야 처음 등장했다
이 앱이 성립하는 전제("센터에 등록한 번호로 인증")가 화면에 처음 나오는 곳이 `_Hints.notFound`,
즉 이미 SMS 왕복을 마친 뒤였다. → `phone_screen`에 사전 고지 2줄 + 약관·방침 링크(수집 **전**,
개인정보보호법 §15② — P59 B5가 "비스크롤 Column이라 넘친다"고 **유보**한 항목이고, 대기실의
스크롤 골격을 옮겨 그 사유를 없앴다) + `autofillHints`(번호·OTP, 앱 전체 0건이었다).

### C3 3화면 제목이 24 → 18 → 16으로 역행했다
가장 오래 머물고 설명이 가장 많이 필요한 화면에서 브랜드가 0픽셀이고 글자가 가장 작았다.
→ `RiseMark(34)` + 제목 19px w800 + 부제 11.5px. 10~10.5px 8곳 제거(iOS 11pt·M3 12sp 미달).
`RiseButton(small)` 10.5 → 11.5는 **앱 전역 23곳** — 전부 짧은 라벨이라 회귀 0(전체 스위트 확인).

### C4 접근성 — 이미 있던 규약이 새 자리에만 적용되지 않았다
`bottomSheetTheme` 부재로 시트 배경이 M3 기본 tone 96 → muted·danger가 **4.37:1**(AA 미달).
`brandLight` 면 위 muted 4.26:1 → `badgeMutFg`(이미 있던 토큰). 44dp 미달 3곳(주소 행 18dp ·
코치 행 26dp · 센터 선택 행 37.5dp) — 같은 화면의 밑줄 링크는 이미 44dp를 지키고 있었다.
스텝퍼 4단계 + 확인 상태 줄/에러 `liveRegion` + 이름 필드 `labelText`/`helperText`.

### C10 자동 틱이 30초마다 탈출구를 잠갔다
`checkingConnection`이 `busy`를 켰고 화면의 **모든** 컨트롤이 그 하나를 봤다 — "번호 다시
인증하기"(모든 stage의 유일한 출구)·"본인이 아니에요"·"계정 삭제"가 함께 회색이 됐다.
→ `autoChecking`을 갈라 `busy`에서 뺀다. 자동 틱은 **자기 줄만** 잠그고 문구가 '확인 중'으로
바뀌는 것이 "살아 있다"는 신호가 된다. 자동 틱 실패는 빨간 문구를 남기지 않는다(깜빡임 제거).

### C9·C11·C12·C13 그 밖
승인/매칭 순간의 침묵 → 스낵바(비事건인 `notYet`만 토스트가 있고 정작 기다리던 일은 무음이었다) ·
stage 전이 1프레임 하드컷 → `AnimatedSwitcher` 220ms(특히 `connectionUnknown → notFound`는
같은 좌표의 전폭 버튼이 읽기전용 확인 → 큐에 줄 쌓는 쓰기로 예고 없이 바뀌었다) ·
경과 시각(데스크만 24h/72h를 세고 앱 화면은 1분째와 3일째가 같았다 — 경계값은 어드민과 동일) ·
연락 수단 0일 때 '문의 방법 보기'(`LegalLinks.support` — 이 화면을 설명하는 유일한 문서에
닿는 길이 스토어 페이지뿐이었다) · 문구 6건(용어 축 "사람=승인 / 앱=확인" 통일 포함).

## 진행 단계
- [x] 현행 구조 실측 + P72 클레임
- [x] 기획 3팀 / 디자인 3팀 병렬 조사(읽기 전용, 파일:줄 근거)
- [x] 교차검증(핵심 주장 8건 직접 확인) + 자문자답
- [x] Phase 1 CRITICAL → 5 실행, 단계마다 재측정
- [x] 변이 검사 11건
- [x] 안 하기로 한 것 기록

## 변경 파일
**앱(lib)** — `core/widgets/underline_link.dart`(신설 — 사제 `_UnderlineLink` 공용화, 비활성이
`line`으로 증발하던 것을 alpha 0.45로) · `core/theme/app_theme.dart`(`bottomSheetTheme`) ·
`core/widgets/rise_button.dart`(small 10.5→11.5) · `core/config/legal_links.dart`(`support`) ·
`features/auth/presentation/auth_state.dart`(`autoChecking`·`anyCheckInFlight`) ·
`auth_view_model.dart`(`ConnectionCheck.nowMatched`·`_rematchInLobby`·`checkConnection(auto:)`) ·
`center_confirm_screen.dart`(C1 배선·문구 6·타이포·마크·`tight` 게이트·44dp·Semantics·
`AnimatedSwitcher`·문의 방법 보기) · `widgets/lobby_auto_check.dart`(`onMatched`·`immediate`·auto) ·
`widgets/lobby_progress.dart`(`CheckAwaiting`·트랙선·임계 400·`dense`·경과·Semantics·liveRegion) ·
`phone_screen.dart`(사전 고지·법정 링크·스크롤 골격·autofill) · `code_screen.dart`(OTP autofill).

**시험** — 신설 `test/core/theme/contrast_test.dart`(7) ·
`test/features/auth/presentation/lobby_accessibility_test.dart`(5) ·
갱신 `auth_view_model_test`(C1 3건) · `center_confirm_screen_test`(앵커 다수 + 접힘 자 + 꼬리
배선 실행 시험) · `lobby_auto_check_test`(C10 2건) · `account_deletion_test`(앵커 원복).

## 검증
- `flutter analyze` **0 issues** · `flutter test` **1497 pass**(착수 1477, 신규 20, 회귀 0)
- **변이 검사 11건**: ① C1 재매칭 배선 제거 → KILL · ②′ 꼬리 배선 되돌림 → KILL ·
  ③ notFound 확인 줄 제거 → KILL · ④ 스텝퍼 Semantics 라벨 → KILL · ⑤ liveRegion 제거 → KILL ·
  ⑥ `bottomSheetTheme` 제거 → KILL · ⑦ 주소 행 44dp 제거 → KILL · ⑧ 자동 틱 auto 플래그 제거 →
  KILL · ⑨ 마크 tight 게이트 제거 → KILL · ⑩ 경과 표기 제거 → KILL · ⑪ 세로 임계 되돌림 → KILL.

### 변이 검사가 실제로 건진 것 (이 절차의 값어치)
- **② 함수 시험은 배선을 안 잰다**(함정 ⑩): `statusText(awaiting: registration)`를 직접 부르는
  순수 함수 시험은 초록인데, 화면의 `registration`을 `approval`로 되돌려도 **안 죽었다**.
  그려서 재는 실행 시험으로 바꾼 뒤에야 잡혔다.
- **⑪ 자를 두 번 고쳤다**: 세로 전환 임계를 `availableWidth: 350`(=390dp 폰)으로 재려 했는데
  그 값은 **옛 임계에서도 이미 세로**라 되돌림이 조용히 통과했다. 구간을 실제로 가르는 값은
  372(412dp)·390(430dp)이었다.
- **`find`는 화면 밖 위젯도 찾는다**: 320×568 회귀 시험이 `takeException == null` +
  `findsOneWidget`만 봐서, 주 CTA가 접힘 아래(y≈580 > 568)에 있어도 전부 초록이었다. 내 추가분이
  그 사각지대를 드러냈고(탭이 hit test를 벗어남), `getRect(...).bottom <= 568` 자를 새로 박았다.

## 안 하기로 한 것 (그리고 그 이유)
- **글자 배율 상한 1.35 → 1.6** (D2 CRITICAL): 클램프는 `app.dart`의 **전역** 설정이고, 막는
  것은 대기실 밖의 고정 높이 3곳(탭바 62 · 체형사진 130 · 인바디 차트 80)이다. 그 세 화면을
  재지 않고 올리면 다른 데가 깨진다. 대신 대기실 본문 하한을 11.5로 올려 실효 배율을 확보했다.
  D2 본인도 이 부분은 [추측]이라 밝혔다. → **후속(전역 배율 스윕)**.
- **다크모드**: 일관되게 미지원이라 "절반만 깨진 다크"는 없다. v1 범위 밖 · 람 결정 사항.
- **FCM 승인 푸시**: G3가 "여전히 후속이 맞다"고 근거와 함께 판정(첫 몇 분은 폴링이 덮고,
  실제 연결은 데스크 방문으로 확정된다). P69 후속 6 유지. 대신 note 문구를 사실로 정렬했다.
- **미등록자 상담 접수처 · `JoinRequest.kind`**: 서버 계약 + 어드민 화면이 함께 움직인다.
  단, "거절이 신규 리드를 파기한다"는 부분만 앱에서 막을 수 있는 만큼 닫았다(문의 방법 보기).
- **스텝퍼 2단계 라벨을 주 CTA와 같은 글자로**(G2 제안): P63이 실제 배포 사고 뒤 박은
  "같은 문장을 두 번 그리지 않는다"와 정면 충돌 — **멈추는 조건 ②**. 더 강한 규약을 남겼다.
- **코치 줄을 좁은 화면에서 접기**(D2 제안): P69가 stage별 노출을 시험 6건으로 고정한 기능이라
  세로 예산을 벌자고 그 결정을 덮지 않는다. 필요한 공간은 마크(46dp) + 스텝퍼 dense(18dp)로 났다.
- **계정 삭제 링크의 danger 색 → muted**(D1 LOW): P63이 의도적으로 고른 색이고, 반대 근거가
  전환율·시선 데이터 없는 [추측]뿐이다.
- **분석 SDK**: `support.html`이 "광고·분석·추적 SDK를 쓰지 않는다"를 **공개 선언**했다.
  도입은 고지 개정을 동반한다. 어드민 쪽 큐 결말 집계(서버에 이미 있는 데이터)만 후속 후보.
- **`_CenterCard` 내부 순서 재배열**(G2): 본인이 [추측]으로 표시했고 stage별 분기 비용 대비
  이득이 불명. 실기기 확인 후 판단.

## 후속 작업
1. **람 확인 필요 — 어드민 센터 신원 3칸**: 대기실 연락 카드의 전화·주소·수업 시간이 전부
   거기서 온다. 2026-08-30 실측 메모 기준 프로덕션은 세 칸이 비어 있고, 그 상태에서는
   거절 화면이 **양방향 연락이 동시에 끊긴** 유일한 상태가 된다(서버가 거절 시 이름·번호를
   지운다). 코드 어떤 변경보다 효과가 크다. 이번에 넣은 '문의 방법 보기'는 그때의 최소 방어선.
2. **Play 등록 정보 수정**(코드 아님): `store/metadata/play.md`가 "등록되지 않은 번호로는
   로그인할 수 없으며 별도 회원가입은 지원하지 않습니다"라고 쓰는데 실제로는 로그인되고
   주 버튼이 [가입 요청 보내기]다. 같은 저장소의 `appstore.md`는 정확하다 — 두 스토어 문서가
   서로 다른 말을 한다.
3. `support.html:128`의 "센터가 승인하면 앱에서 **자동으로** 연결됩니다" — P69 C1이 앱에서
   일부러 지운 표현이 문서에 남아 있다.
4. 어드민 "초대 보내기(보조) · 카톡/문자 설치 링크"는 **버튼도 링크도 없는 순수 텍스트 행**이다
   (`Settings.tsx`). 스토어 URL 상수 + 복사 버튼 + QR 인쇄(기존 `CheckinQr` 인쇄 시트 재사용).
5. 전역 글자 배율 상한 스윕(위 "안 하기로 한 것" 1번).
6. 실기기 스크린샷 대조(320×568 · 390×844 · 430×932) — D1의 높이 수치는 Pretendard 메트릭
   추정에 기댄 값이라 실측으로 대체해야 등급이 확정된다.

## 참조
- work_log/P55-center-join-onboarding.md · P63-lobby-copy-and-deletion-notice.md ·
  P69-join-queue-visibility-and-lobby-v2.md · P56-broken-promises-audit.md
- 스킬: `~/.claude/skills/ram-verify-loop`(자 먼저 · 변이 검사 · 멈추는 조건 · 함정 ⑩)
