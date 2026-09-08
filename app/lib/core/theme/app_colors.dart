import 'package:flutter/material.dart';

/// 디자인 토큰 — 목업(목업_회원앱_라이즈_2026-08-14.html) CSS 변수 1:1 매핑.
/// 회색·상태색은 목업 그대로이고, **액센트만 브랜드 보드 색으로 교체**했다(P54).
abstract final class AppColors {
  /// 브랜드 액센트 — `design/brand/` 보드의 네이비 그대로다.
  ///
  /// **왜 레드가 아닌가**(P54): 종전 값 `#E11D48`은 브랜드가 아니라 목업 CSS 변수
  /// `--red` 하나가 출처였다(형제 목업은 오렌지·바이올렛도 시험했다 — 확정된 선택이
  /// 아니었다). 정작 브랜드 보드·런처 아이콘·스플래시·안드로이드 창 배경·어드민
  /// 마크는 전부 네이비/크림이라, 앱만 첫 프레임에서 브랜드를 갈아치우고 있었다.
  /// `design/brand/README.md`가 이 분열을 이미 "다른 팔레트"로 적어 두고 마크를
  /// 앱 색으로 칠하지 말라고 경고했는데, 옳은 방향은 그 반대였다 — 앱이 마크를 따른다.
  ///
  /// **왜 빨강이면 안 되는가**: `#E11D48`(HCT hue 15.1)과 [danger] `#DC2626`(hue 24.6)은
  /// 색상각 9.5°·대비 **1.03:1**로 사람 눈에 같은 색이다. 그래서 "오늘" 배지와 경고
  /// 배지가, 골격근량 증가와 악화가, 탈퇴 동의 체크박스와 탈퇴 버튼이 한 화면에서
  /// 구분되지 않았다. 게다가 Material 3는 error 팔레트를 `TonalPalette.of(25.0, 84.0)`으로
  /// **하드코딩**한다(material_color_utilities `dynamic_scheme.dart`) — seed를 빨강으로
  /// 주는 한 primary와 error는 구조적으로 겹치고, 채도는 error가 2배라 화면에서 가장
  /// 선명한 빨강이 브랜드가 아니라 에러가 된다. 네이비 seed는 error와 231° 떨어진다.
  ///
  /// 접근성도 함께 나아졌다 — 종전 `#E11D48`은 페이지 배경 위 4.39:1, 배지 글자
  /// 4.28:1로 **AA 미달**이었다. 아래 값들은 8:1 이상이다.
  static const brand = Color(0xFF3B4C60);

  /// 틴트 면(홈 "다음 예약" 카드, 브랜드 배지 배경). 종전 `--red-l` 자리.
  static const brandLight = Color(0xFFEDF1F5);

  /// 장식 테두리. **상태를 이 색 하나로 지지 말 것** — 흰 배경 대비 1.80:1이라
  /// 경계 자체가 정보를 나르는 자리에는 [brandStrong]을 쓴다(종전 `--red-b`도
  /// 1.41:1로 같은 결함이 있었다).
  static const brandBorder = Color(0xFFB1C3DA);

  /// pressed·강조. [brand]와 같은 HCT 색상(252.5°)의 t24.
  static const brandDark = Color(0xFF293A4E);

  /// 테두리만으로 상태를 표시해야 하는 자리(스위치 트랙 등). 2.70:1.
  static const brandStrong = Color(0xFF8E9FB6);

  static const ink = Color(0xFF111827);
  static const line = Color(0xFFE5E7EB);

  /// 입력 필드 경계 전용(P54). [line]은 흰 배경 위 1.24:1이라 텍스트 필드의
  /// 유일한 식별 단서로는 미달이다(WCAG 1.4.11 = 3:1). 카드·구분선은 장식이라
  /// 면제되므로 [line]을 그대로 쓴다 — 이 값을 그쪽에 퍼뜨리지 말 것.
  static const inputBorder = Color(0xFF949494);
  static const muted = Color(0xFF6B7280);

  static const ok = Color(0xFF16A34A);
  static const warn = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const blue = Color(0xFF2563EB);

  static const surface = Color(0xFFFFFFFF);
  static const page = Color(0xFFF7F7F8); // .bd 배경
  static const chipBg = Color(0xFFF3F4F6);

  // 아래 셋은 값이 위 둘과 같은 **역할 별칭**이다. 목업이 같은 회색을 서로 다른
  // 뜻으로 쓰기 때문에(면 / 선 / 트랙) 이름을 나눠 둔다 — 나중에 한 역할만
  // 조정할 때 `page`를 바꿔 온 화면 배경까지 흔드는 일을 막는다.
  static const surfaceMuted = page; // 카드 안의 "가라앉힌 면"(#f7f7f8)
  static const divider = chipBg; // 목업 `.row{border-bottom:1px solid #f3f4f6}`
  static const trackBg = chipBg; // 잔여 링 트랙(목업 circle stroke="#f3f4f6")

  static const chipFg = Color(0xFF4B5563); // 목업 `.chip{color:#4b5563}`

  /// 비활성 탭. **목업 값 `#9ca3af`에서 내렸다**(P54) — 그 값은 흰 배경 위
  /// **2.54:1**로 앱 전체에서 대비가 가장 나빴다. 4개 탭 중 3개는 항상 이 상태이고
  /// 하단 탭은 이 앱의 유일한 주 내비게이션이라, 가장 자주 읽히는 글자가 가장 안
  /// 보이는 상태였다. 라벨 9.5px·아이콘 21dp 둘 다 미달이었다(텍스트 4.5 / UI 3.0).
  /// `#767676`은 흰 배경에서 4.54:1로 통과하는 가장 밝은 회색이다.
  static const tabInactive = Color(0xFF767676);

  // 배지 배경/전경 쌍 (b-ok, b-warn, b-dan, b-red, b-mut, b-blue)
  static const badgeOkBg = Color(0xFFDCFCE7);
  static const badgeOkFg = Color(0xFF15803D);
  static const badgeWarnBg = Color(0xFFFEF3C7);
  static const badgeWarnFg = Color(0xFFB45309);
  static const badgeDanBg = Color(0xFFFEE2E2);
  static const badgeDanFg = Color(0xFFB91C1C);
  static const badgeBlueBg = Color(0xFFDBEAFE);
  static const badgeBlueFg = Color(0xFF1D4ED8);
  static const badgeMutBg = Color(0xFFF3F4F6);

  /// 중립 배지 글자. [muted]와 값을 갈랐다(P54) — `#6B7280`은 흰 배경에서는
  /// 4.83:1로 통과하지만 배지 배경 `#F3F4F6` 위에서는 **4.39:1로 미달**이었고,
  /// 하필 `muted`가 가장 많이 쓰이는 배지 변형이다(34곳). 면이 회색일 때만
  /// 한 단계 내린다 — 본문 [muted]는 목업 값 그대로 둔다.
  static const badgeMutFg = Color(0xFF5B6472);

  // 체형 분석 카메라 오버레이
  static const camBgTop = Color(0xFF43464F);
  static const camBgBottom = Color(0xFF26282F);
  static const camCrosshair = Color(0xFFFF2D2D);
  static const camLevelOk = Color(0xFF22C55E);
  static const camLevelTilt = Color(0xFFF59E0B);

  /// 배경 인물 경고 배너(목업 `.camwrap .warnbg`) — 어두운 프리뷰 위에 얹히는
  /// 전용 쌍이라 배지의 b-dan(밝은 배경 + 진한 글자)과 반대 방향이다.
  /// 배경은 [danger]를 알파 .28로 깐다(목업 `rgba(220,38,38,.28)`).
  static const camWarnBorder = Color(0xFFFCA5A5); // rgba(252,165,165,.6)
  static const camWarnFg = Color(0xFFFECACA);
}
