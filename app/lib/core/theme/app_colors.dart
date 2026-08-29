import 'package:flutter/material.dart';

/// 디자인 토큰 — 목업(목업_회원앱_라이즈_2026-08-14.html) CSS 변수 1:1 매핑.
/// Light 테마 + 레드 액센트(#e11d48).
abstract final class AppColors {
  static const red = Color(0xFFE11D48);
  static const redLight = Color(0xFFFFF1F2); // --red-l
  static const redBorder = Color(0xFFFECDD3); // --red-b

  static const ink = Color(0xFF111827);
  static const line = Color(0xFFE5E7EB);
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
  static const tabInactive = Color(0xFF9CA3AF); // 목업 `.tab{color:#9ca3af}`

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
  static const badgeMutFg = Color(0xFF6B7280);

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
