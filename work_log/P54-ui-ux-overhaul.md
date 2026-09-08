---
id: P54
title: 회원앱 UI/UX 전면 검수 — 브랜드 색 재정의 + 시스템 UI 안전영역 + 접근성
status: 진행 중
domain: app
created: 2026-08-30
completed:
---

# P54 — 회원앱 UI/UX 전면 검수

## 목표
람의 두 지적에서 출발했다.
1. **"바텀시트가 하드웨어 네비게이션 바에 걸린다"** — 개별 화면이 아니라 **결함 클래스**로 보고
   시스템 UI(제스처 바·노치·키보드·상태바) 전 구간을 감사한다.
2. **"지금 빨간색이 너무 이상하다. 레드를 쓸 필요 없다. PT 앱 사용자에게 편한 색으로"**

람이 자율 작업 권한을 주며 디자이너 팀 복수 구성 → 교차검증 → 자문자답을 요청했다.
A팀(브랜드/색채)·B팀(시스템 UI)·C팀(접근성/일관성)을 겹치지 않게 갈라 병렬 투입했다.

## 결정 사항

### 1. 브랜드 색: 레드 → 브랜드 보드 네이비 `#3B4C60`
**A팀의 결정적 발견 — 이 앱엔 이미 브랜드 색이 있고, 레드가 아니었다.**
`design/brand/` 보드(`~/Downloads/rise.jpeg`)는 네이비 `#3B4C60` · 베이지 `#CEBBAA` ·
크림 `#F6F4EF`이고 "REHABILITATE · REALIGN · RISE" 재활·정렬 포지셔닝이다. 이 색이 이미
런처 아이콘(`pubspec.yaml:123`)·안드로이드 창 배경(`colors.xml:17`)·스플래시
(`splash_gate.dart:186`)·마크(`rise_mark.dart:22`)·어드민에 박혀 있는데 **회원앱 테마만
안 따르고 있었다** — 크림+네이비 아이콘 → 크림+네이비 스플래시 → 로즈레드 앱으로
첫 프레임에서 브랜드가 갈아치워졌다.
- `design/brand/README.md`가 이 분열을 이미 "다른 팔레트"로 적어 두고 **"마크를 앱 색으로
  다시 칠하지 말 것"**이라 경고했는데, 옳은 방향은 그 반대였다 — 앱이 마크를 따른다.
- 레드의 유일한 출처는 목업 CSS 변수 `--red:#e11d48` 하나였다(형제 목업은 오렌지·바이올렛도
  시험했다 — **확정된 선택이 아니라 잔재**였다). 람의 "이상하다"는 직감이 정확했다.

**왜 빨강이면 안 되는가 — 시장 취향이 아니라 구조 문제다.**
- `#E11D48`(HCT hue 15.1)과 danger `#DC2626`(24.6)은 **색상각 9.5°·대비 1.03:1**로 같은 색이다.
  실제 충돌 지점: "오늘" 배지 vs 경고 배지(같은 카드), 골격근량 **증가**(brand) vs **악화**
  (danger)가 한 행(`inbody_metric_rows.dart:33,39`), 탈퇴 동의 체크박스 vs 탈퇴 버튼(같은 화면),
  사진 에러 문구 바로 아래 "다시 시도" 링크(`body_photo_timeline.dart:783,794`).
- **Material 3가 이 충돌을 강제한다**: `material_color_utilities`가 error 팔레트를
  `TonalPalette.of(25.0, 84.0)`으로 **하드코딩**한다. seed가 빨강인 한 primary와 error는
  10° 안에서 겹치고 채도는 error가 2배라 **화면에서 가장 선명한 빨강이 브랜드가 아니라 에러**가 된다.
  네이비 seed는 231° 떨어진다.
- Material 공식은 semantic color 교체를 금한다 — **움직일 수 있는 건 브랜드 쪽뿐**이었다.
- 접근성도 이미 미달이었다: `#E11D48`은 페이지 배경 위 4.39:1, 배지 글자 4.28:1.

**시장 조사(참고, 결정 근거 아님)**: 국내외 19종 실측에서 레드 프라이머리는 약 1/4(InBody
`#971B2F` 공식 CI·눔 `#FB513B` 등)이고, **국내 운동기록 앱은 블루/민트로 수렴**(번핏
`#329EFF`, 플랜핏 `#1BEDC7`, 핏데이 블루). 인바디 본인들도 신규 B2C 앱 InBody+에서는
레드를 버리고 다크네이비+시안으로 갔다. 즉 "레드가 이상하다"까지는 아니지만 우리 경우는
**브랜드 보드가 이미 답을 갖고 있어** 새 색을 발명할 필요가 없었다.

### 2. 바텀시트: `useSafeArea`가 아니라 인셋 주입 래퍼
**착수 가설이 틀렸다.** "13곳에 `useSafeArea` 지정 0곳"을 결함으로 봤는데, Flutter의 그 옵션은
`SafeArea(bottom: false)`라 **하단을 의도적으로 제외**한다(`bottom_sheet.dart:1167`, dartdoc도
"including any system intrusions" 명시). B팀이 임시 위젯 테스트로 실측해 뒤집었다 —
`useSafeArea: true`로 켜도 침범량 28dp가 그대로였다.
- 진짜 원인: targetSdk 36에서 edge-to-edge는 **강제**(Android 16은 opt-out 플래그마저 무시)라
  시스템 바가 콘텐츠 위에 겹치는데, 시트들은 하단 여백을 `viewInsets`(=키보드)로만 잡았다.
- 그래서 **키보드가 없는 시트에서만** 터졌다 — Android는 IME가 뜨면 `viewInsets`에 내비바를
  함께 담기 때문에 입력 시트에서는 정확했고, 그래서 지금까지 안 드러났다.
- 침범량 실측: 3버튼 28dp / 제스처 4dp / iOS 14dp. `RiseButton` 실높이 42dp이므로
  **3버튼에서 CTA의 눌리는 영역이 14dp만 남았다**(예약 확정·동의 저장·계약 서명).
- 시트는 13곳이 아니라 **실제 호출 12곳**(하나는 주석)이고, **3곳은 이미 정답 패턴을 쓰고
  있었다** — 답이 저장소 안에 있는데 나머지 9곳이 안 따라간 상태였다.
- 해법은 `showRiseSheet` 래퍼가 시트 안쪽의 `viewInsets.bottom`을
  `max(viewInsets, viewPadding)`으로 바꿔 주입하는 것. 그러면 **호출부의
  `viewInsets.bottom + 20` 코드를 한 줄도 안 고치고** 정답이 된다(위젯 트리 무변경 = 낮은 회귀 위험).
- **더하지 않고 `max`인 이유**: 더하면 키보드 위로 내비바 높이만큼 CTA가 뜬다(실측: 여백 20 vs 68).

### 3. 카메라 FAB 히트 영역 — 셸 재구성
실기기 이분 탐색으로 확인: 원의 **위쪽 약 11dp가 안 눌렸다**. `Transform.translate(0,-18)`가
그리기만 옮기고, 조상 항목 박스가 막대 높이(62)뿐이라 그 18이 박스 **밖**이었기 때문
(`RenderBox.hitTest`의 `size.contains`). 더 나쁜 건 그 자리의 탭이 **뒤 본문 콘텐츠로
내려갔다**는 것 — 큰 버튼을 눌렀는데 뒤 목록이 반응한다.
- 해법: 각 항목이 위에 `_kFabRaise`만큼 **투명 헤드룸**을 두고, 배경·상단 보더는
  `Positioned(top: 18, bottom: 0)`으로 아래 막대에만 칠한다. 그리는 위치는 종전과 같고
  **히트 영역만** 위로 넓어진다.
- **구현 중 두 번 부풀렸다(실측으로 잡음)**: ① Stack의 자식이 **전부 Positioned**면
  Stack이 `constraints.biggest`(= 화면 전체 높이)를 먹는다. ② 행에 `CrossAxisAlignment.stretch`를
  주면 Flex가 교차축을 `constraints.maxHeight`로 **타이트하게** 준다 — 역시 화면 전체.
  둘 다 배경이 하단에만 칠해져 **스크린샷으로는 멀쩡해 보인다** — 눈으로는 못 잡는다.
  그래서 회귀 테스트에 높이 **상한**을 함께 넣었다.

### 4. 어드민 팔레트 — 같은 충돌이 더 심했다
`--color-brand: #f43f5e` vs `--color-danger: #fb7185`가 **색상각 1.6°·대비 1.36:1**로
회원앱(9.5°)보다 나빴다. 어드민은 회원권 상태·결제·삭제 경고가 한 화면에 모이는 곳이다.
- **다크 UI라 회원앱 원색을 그대로 못 쓴다** — `#3B4C60`은 패널 위 2.05:1이다. 같은 색상
  (hue 212°)에서 명도만 올린 `#7fa0c4`(패널 6.64:1)를 액센트로 쓴다.
- `text-brand`(18곳)와 `bg-brand text-white`가 **서로 반대 방향을 요구**해 토큰을 갈랐다:
  `--color-brand`는 텍스트·보더·틴트용 밝은 네이비, `--color-brand-2`는 **회원앱 원색**으로
  채워진 면 전용(흰 글자 8.79:1).
- 기본 버튼은 다크 UI 관용대로 **밝은 면 + 어두운 글자**(`bg-brand text-bg`)로 뒤집었다 —
  원색을 면으로 쓰면 패널에 묻힌다.
- `--color-blue: #60a5fa`(hue 213°)가 새 브랜드와 **2° 차이**라 회원권 "예정" 배지가
  브랜드와 구분되지 않게 됐다 → 바이올렛 `#a78bfa`(44° 이격)로 이동. 이 토큰의 용도는
  그 배지 하나뿐이라 파급이 없다.
- 트레이너 기본 색·매출 차트 스트로크의 하드코딩 `#f43f5e` 10곳도 함께 교체.

### 5. 검은 내비게이션 바 — 스토어 캡처를 다시 찍다가 발견
`AppBarTheme.systemOverlayStyle`을 넣고 끝난 줄 알았는데, 그건 **AppBar가 있는 화면에만**
걸린다. 홈·로그인엔 AppBar가 없어서 `MaterialApp`이 밝은 테마 기본값으로 보내는
`SystemUiOverlayStyle.dark`가 그대로 나갔고, 그 값의 실제 내용이 **"내비바 배경 검정 +
아이콘 흰색"**이라 크림색 앱 아래에 검은 띠가 깔렸다(이름과 정반대로 읽히는 자리다).
- 람 폰에서 찍은 화면에도, 스토어 캡처에도 그대로 박혀 있었다. **재캡처를 하지 않았으면
  못 봤을 결함**이다 — 개발자는 대개 제스처 내비(얇은 핸들)를 써서 눈에 덜 띈다.
- 루트 `AnnotatedRegion`으로 앱 전체에 걸었다. 검은 전체화면(카메라·사진 뷰어)은 자기
  `AnnotatedRegion`으로 이걸 덮는다 — 그 우선순위도 테스트로 고정했다.
- 실기기 재확인: 내비바가 앱 배경과 같은 크림색, 아이콘 어둡게.

### 6. 접근성 — C팀이 오탐을 스스로 걷어낸 것이 핵심
초기 48쌍 계산에서 22쌍이 "미달"로 나왔지만 **진짜 위반은 9쌍**이었다. 걷어낸 근거:
- 비활성 컴포넌트는 WCAG 1.4.3이 **명시적으로 면제**한다
- 배지 **배경**은 의미를 나르지 않는다(안의 글자가 나른다) → 1.4.11 대상 아님.
  단 **입력 필드 보더는 다르다** — 보더가 없으면 입력 칸인지 알 수 없어 해당된다
- `RiseButton(small)`은 Flutter가 `materialTapTargetSize = padded`로 **자동 48dp**를 준다
  (`theme_data.dart:400-404` 직접 확인) → 46곳을 헛되이 고칠 뻔했다

이 판단을 테스트의 "면제" 그룹에 **기록으로 남겼다** — 다음 사람이 전수 계산을 돌려
"미달"을 발견했을 때 잘못 고치는 걸 막는다.

## 진행 단계
- [x] 실태 조사 + P 클레임
- [x] 디자이너 3팀 병렬 투입(색채/시스템UI/접근성)
- [x] 교차검증 + 자문자답
- [x] 구현 — 브랜드 색 · 시트 래퍼 · 시스템 오버레이 · 접근성 12건
- [x] 검증 — analyze 0 · 테스트 1207 · 실기기(3버튼 내비) 실주행
- [x] 카메라 FAB 히트테스트 — 셸 재구성 + 실기기(갤럭시 S21U, 3버튼) 재검증
- [x] 어드민 팔레트 정렬

## 변경 파일
**색**
- `lib/core/theme/app_colors.dart` — `red/redLight/redBorder` → `brand/brandLight/brandBorder`
  + `brandDark`·`brandStrong`·`inputBorder` 신설. `tabInactive` `#9CA3AF`→`#767676`,
  `badgeMutFg` `#6B7280`→`#5B6472`
- `lib/core/theme/app_theme.dart` — seed 교체, 스위치 트랙 `brandStrong`,
  `enabledBorder` `inputBorder`, **`dialogTheme` 신설**, `systemOverlayStyle` 신설
- `lib/core/widgets/rise_badge.dart` + 호출부 — `RiseBadgeVariant.red` → `.brand`
- 색 참조 61곳 / 29파일 기계 치환(테스트 참조 0건이라 순수 교체였다)

**시스템 UI**
- `lib/core/widgets/rise_sheet.dart` **신설** — `showRiseSheet`
- 시트 12곳 전환(10파일)
- `camera_screen.dart`·`body_photo_viewer.dart` — `AnnotatedRegion(SystemUiOverlayStyle.light)`

**접근성**
- `rise_chip.dart` — `Semantics(selected:)` (칩 전역: 회원권 스위처·날짜 스트립·코치 필터)
- `signature_pad.dart` — 서명란 `Semantics` + `liveRegion` / `camera_screen.dart` — 셔터 라벨
- `capture_review_layer.dart` — 대표 자유 입력 포즈명 오버플로(`Expanded` + `maxLines`)
- 터치 타깃 6곳 투명 패딩(시각 무변화): 사진 "다시 시도" · 포즈 칩 · 약관 전문 보기 ·
  "다시 쓰기" · 계약 본문 펼치기 · 재등록 요청

**셸 · 어드민**
- `lib/features/shell/app_shell.dart` — 항목마다 `_kFabRaise` 투명 헤드룸, 배경은
  `Positioned(top:18,bottom:0)`으로 아래 막대에만. `_NavItemShell` 신설
- `admin/src/index.css` — `--color-brand` `#7fa0c4` · `--color-brand-2` `#3b4c60` ·
  `--color-blue` → `#a78bfa`
- `admin/src/components/ui.tsx` — 기본 버튼 `bg-brand text-bg`(다크 UI 관용)
- `admin/src/App.tsx` — `bg-brand text-white` → `bg-brand-2`(2곳)
- `admin/src/features/{Settings,Schedule,Sales}.tsx` — 하드코딩 `#f43f5e` 10곳

**스토어 자산 재생성**
- `store/screenshots/{android,ios}/{raw,final}` 각 7장 — **색만 덧칠하지 않고 다시 찍었다**.
  탭 바가 FAB 헤드룸만큼 높아져 레이아웃이 이동했고, 바뀐 게 브랜드만이 아니라 비활성 탭
  회색·배지 회색·입력 보더·다이얼로그 모서리까지였다. FAB 글로우는 브랜드 알파 40%라
  안티에일리어싱 가장자리를 색 치환하면 지저분해진다.
- `store/screenshots/capture.sh` — **제스처 내비 강제**. AVD 설정은 재부팅해도 남아서,
  3버튼으로 바꿔 테스트한 뒤 그대로 찍으면 하단에 **검은 띠 + 버튼 잔상**이 박힌다
  (실제로 한 번 그렇게 찍혔다). 데모 모드는 상태바만 정리하고 내비바는 손대지 않는다.
- `store/README.md` — "UI가 바뀌면 다시 찍는다, 색만 덧칠하지 말 것"을 근거와 함께 기록.
  실기기 동시 연결 시 `ANDROID_SERIAL` 필요도 함께(안 붙이면 adb가 대상을 못 골라 죽는다).
- `store/screenshots/frame.py` — iOS 원본은 `integration_test`가 **Flutter 표면만** 찍어
  상태바가 비므로(Android는 `adb screencap`이라 실제 9:41이 들어온다) 그 빈 띠를 덜어낸다.
  없는 상태바를 그려 넣지는 않는다. **캔버스 크기는 원본 그대로 고정** — 처음엔 크롭이
  캔버스까지 줄여 1320×2723이 나왔는데, 6.9" 슬롯은 1320×2868 고정이라 **그대로면 업로드가
  거부됐을 자리다**(전 파일 크기 단언으로 잡았다).

**테스트 +28**
- `test/core/widgets/rise_sheet_test.dart` (7) — 3버튼/제스처/iOS × 키보드 유무 격자.
  **첫 그룹이 "`useSafeArea`는 하단을 안 막는다"는 사실 자체를 고정**한다(래퍼를 걷어내면 터진다)
- `test/tool/sheet_guard_test.dart` (2) — `showModalBottomSheet` 직접 호출 0건 정적 가드
- `test/core/theme/color_contrast_test.dart` (14) — 대비비 + **색상각** + 면제 기록
- `test/core/system_overlay_style_test.dart` (2) — 밝은 화면의 내비바 색·아이콘,
  검은 전체화면이 루트를 덮는 우선순위
- `test/features/shell/camera_fab_hit_test.dart` (3) — 원 전체가 눌리는지 + 뒤 본문으로
  새지 않는지 + **탭 바 높이 하한·상한**. 뮤테이션(헤드룸 제거)으로 실제 격추 확인

## 검증
- `flutter analyze` 0 issues · `flutter test` **1210 pass**(착수 시 1184, +26 신규, 회귀 0)
- 어드민 `tsc --noEmit` 통과 · `npm run build` 성공 ·
  **번들 실측**: 새 색 `7fa0c4` 17건·`3b4c60` 2건·`a78bfa` 2건 / 옛 색 `f43f5e`·`e11d48`·`60a5fa` **각 0건**
- **갤럭시 S21 Ultra(3버튼 내비) 실기기**: 릴리스 APK 설치 → 로그인 → 홈이 브랜드 네이비로
  정렬(로그인 워드마크·CTA·잔여 링·탭 활성색) → **FAB 히트 이분 탐색 y=2010~2120 전 구간 반응**
  (수정 전 에뮬레이터에서는 위쪽 11dp 무반응이었다)
- **실기기 실주행**(에뮬레이터를 **3버튼 내비로 전환** — 인셋이 가장 큰 최악 조건):
  릴리스 APK 설치 → 심사 계정 로그인 → 홈·예약·마이 · 코치 소개 시트가 시스템 바 위에서 끝남
- 탭 바 히트테스트 해시 이분 탐색: 2285~2330 전 구간 반응(=정상). 초기에 "안 눌린다"고 본 것은
  **시트 닫힘 애니메이션 중 탭한 내 측정 오류**였다

### 구현 중 테스트가 잡은 실버그 1건
래퍼 첫 구현이 `builder(sheetContext)`를 호출했는데, 그러면 자식이 받는 context가 주입한
MediaQuery **위쪽**이라 값을 못 읽는다 — 호출부는 `MediaQuery.of`를 쓰므로 **조용히 종전
동작으로 되돌아간다**(analyze·기존 테스트 전부 초록인 채로). 새로 쓴 3버튼 케이스가 잡았고
`Builder(builder: builder)`로 고쳤다. 테스트를 먼저 안 썼으면 "고쳤다"고 보고할 뻔했다.

### 내가 틀린 것 2건 (기록)
1. 착수 진단 "useSafeArea 지정 0곳이 결함" — B팀이 SDK 소스와 실측으로 뒤집었다.
2. 대비비로 "브랜드와 위험이 구분되는가"를 단언하려 했다 — **대비비는 명도만 재므로**
   네이비 vs 빨강(1.82:1)을 실패로 잡았다. 구분 가능성의 축은 **색상각**이라 `hueDistance`로 교체.

## 후속 작업
1. **[HIGH] 실기기 시트 CTA 재확인** — FAB·브랜드 색은 갤럭시에서 확인했으나, **바텀시트
   하단 CTA 실기기 확인만 남았다**(확인 도중 USB 연결이 끊겼다). 위젯 테스트 7건이
   3버튼/제스처/iOS 인셋을 격자로 덮고 있으나 엔진이 주는 실제 `viewPadding`은 테스트가
   증명하지 못한다 — 3버튼 갤럭시에서 예약 확정·동의 저장 시트를 한 번 눌러 볼 것.
2. **[MEDIUM] 글자 확대 상한 1.35 → 2.0 (WCAG 1.4.4)** — 본문 최빈 크기가 11.5px라 최대
   15.5px로, **보통 앱의 기본값(17px)보다 작다**. `app.dart:31-32`가 지목한 고정 높이 3곳 중
   **2곳은 이미 수리됐고**(탭바는 minHeight, 체형 사진은 AspectRatio) 남은 건 인바디 차트
   하나뿐이라 생각보다 싸다. `app.dart:27`이 참조하는 테스트 파일명도 실재하지 않는다
   (`text_scale_overflow_test.dart` → 실제는 `long_label_overflow_test.dart`).
4. **[LOW] 트레이너 기본 아바타 색** — 어드민 색상 피커 기본값이 로즈라 실데이터 아바타가
   네이비 UI 위에서 튄다. 데이터라 앱 수정 대상은 아니고 어드민에서 바꾸면 된다.
5. **[LOW] `AppTypography` 토큰 공백** — 실사용 최다 크기 11.5px(57회)·11px(43회)가 토큰에
   없어 인라인 `TextStyle`이 228개다. 이걸 메우면 다크모드·타이포 정리가 싸진다.
6. **[정보] 다크모드는 지금 넣지 말 것** — `AppColors` 참조 362회가 전부 `static const`
   (컴파일 타임 상수라 테마 인지 불가)이고 `Theme.of` 사용이 2회뿐이다. 도입하려면 420곳
   호출부 수정이며, 위 3·5번이 선행되어야 싸다. PT 회원앱의 사용 시간대(운동 전후 주간)를
   감안하면 지금의 이득이 크지 않다.
7. **[정보] 브랜드 표기 `RIZE` vs `RISE`** — 브랜드 보드의 워드마크는 **RIZE**이고 RISE는
   세 기둥의 셋째 단어다. 그런데 앱 로그인 화면·피처 그래픽은 "RISE CONDITIONING"이고
   패키지도 `com.han.rise`로 확정됐다(Play 불변). 어느 쪽이 공식인지 확인 필요.

## 참조
- P46(스토어 배포 준비) — 색이 바뀌었으므로 **스토어 스크린샷 14장 재캡처 필요**
- P09(시트를 루트 Navigator에) · P50(한 곳을 고쳐 뿌리째 해소하는 방식의 선례)
