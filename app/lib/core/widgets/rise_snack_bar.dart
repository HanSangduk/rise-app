import 'package:flutter/material.dart';
import 'package:rise_member/core/result/failure.dart';
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
SnackBar riseSnackBar(
  String message, {
  RiseSnackKind kind = RiseSnackKind.neutral,
  SnackBarAction? action,
}) {
  final (bg, fg) = switch (kind) {
    RiseSnackKind.neutral => (null, null), // 테마 기본(ink/흰 글씨)에 맡긴다.
    RiseSnackKind.ok => (AppColors.badgeOkBg, AppColors.badgeOkFg),
    RiseSnackKind.danger => (AppColors.badgeDanBg, AppColors.badgeDanFg),
  };
  return SnackBar(
    backgroundColor: bg,
    content: Text(message, style: fg == null ? null : TextStyle(color: fg)),
    action: action,
  );
}

/// 액션 실패를 danger 스낵바로 알린다 — **[SessionGoneFailure]는 건너뛴다**(P64 검증 반영).
///
/// 4탭의 액션(체크인·예약 취소·인바디 삭제·사진 삭제·홈워크 토글)은 세션이 빈 채 눌리면
/// `Err(SessionGoneFailure())`를 돌려주는데, 그 순간 `app.dart` 리스너가 화면을 내리는 중이다.
/// 여기서 빨간 스낵바를 띄우면 "요청이 실패했으니 다시 시도하라"는 색을 내보내는 셈이고,
/// 그 재시도는 세션을 만들지 못한다. 한 곳에서 거르는 이유: 호출부마다 `is` 검사를 붙이면
/// 다음 액션이 빠뜨린다.
///
/// 그 밖의 실패는 서버 문구를 그대로 낸다 — 회원에게 필요한 건 "무엇이 안 됐나"이고 그건
/// 메시지가 이미 말한다.
void showFailureSnackBar(BuildContext context, Failure failure) {
  if (failure is SessionGoneFailure) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(riseSnackBar(failure.message, kind: RiseSnackKind.danger));
}
