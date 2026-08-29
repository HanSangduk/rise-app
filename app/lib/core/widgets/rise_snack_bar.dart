import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';

/// 스낵바가 말하는 결과의 종류.
enum RiseSnackKind {
  /// 성공도 실패도 아닌 알림("아직 승인 전이에요") — 테마 기본(잉크 배경).
  neutral,

  /// 요청이 끝났다("저장했어요", "서명 완료").
  ok,

  /// 요청이 실패했다 — 회원이 다시 시도해야 한다.
  danger,
}

/// 팔레트에 맞는 스낵바.
///
/// 기본 스타일(모양·글꼴·중립 배경)은 [buildAppTheme]의 `snackBarTheme`이 정하고,
/// 여기서는 **결과 색만** 덮는다. 색을 나누는 이유: 체형 사진 저장 성공(:30)과
/// 실패(:33)가 시각적으로 완전히 동일해서, 사진이 저장됐는지를 문구를 읽어야만
/// 알 수 있었다.
///
/// 색은 새로 만들지 않고 **배지의 ok/danger 쌍을 그대로 쓴다**(b-ok / b-dan).
/// 앱이 이미 "성공은 연한 초록 + 진한 초록 글씨, 실패는 연한 빨강 + 진한 빨강
/// 글씨"로 말하고 있어서 배우지 않아도 읽히고, 대비도 검증돼 있다
/// (badgeOkFg on badgeOkBg ≈ 4.6:1, badgeDanFg on badgeDanBg ≈ 5.3:1 — 둘 다 AA).
/// `AppColors.ok`/`danger`를 그대로 배경에 깔고 흰 글씨를 얹는 쪽이 눈에는 더
/// 세지만 초록 위 흰 글씨가 3.3:1로 AA에 못 미쳐 택하지 않았다.
SnackBar riseSnackBar(String message, {RiseSnackKind kind = RiseSnackKind.neutral}) {
  final (bg, fg) = switch (kind) {
    RiseSnackKind.neutral => (null, null), // 테마 기본(ink/흰 글씨)에 맡긴다.
    RiseSnackKind.ok => (AppColors.badgeOkBg, AppColors.badgeOkFg),
    RiseSnackKind.danger => (AppColors.badgeDanBg, AppColors.badgeDanFg),
  };
  return SnackBar(
    backgroundColor: bg,
    content: Text(message, style: fg == null ? null : TextStyle(color: fg)),
  );
}
