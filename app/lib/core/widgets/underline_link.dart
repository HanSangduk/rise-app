import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';

/// 본문과 경쟁하지 않는 작은 밑줄 링크 — 로그인 흐름의 보조 경로(약관·처리방침·계정 삭제·
/// "번호 다시 인증하기"·"본인이 아니에요")가 전부 이것이다.
///
/// 대기실(`center_confirm_screen.dart`)의 사제 위젯이었는데, 같은 줄을 전화번호 화면에도
/// 두면서 공용으로 끌어올렸다(P72 C2) — 두 벌이면 한쪽만 44dp를 잃는 종류의 비일관이 생긴다.
///
/// **터치 영역은 44dp를 명시한다.** 글자 상자만 누르면 ≈15dp였다. 투명 히트 영역을
/// `GestureDetector` 안쪽에 두고 `opaque`로 받되, 높이는 `ConstrainedBox`로 하한을 박는다 —
/// 종전 세로 패딩 14×2 + 11px 글자는 43dp 남짓이라 글꼴·배율에 따라 44에 못 미쳤다
/// (`touch_target_test`의 기준).
class RiseUnderlineLink extends StatelessWidget {
  const RiseUnderlineLink({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
    this.fontSize = 11.5,
  });

  final String label;

  /// null이면 비활성 — 색이 한 단계 옅어진다. **`line`까지 내리지 않는다**(P72 C10):
  /// 이 링크들은 로그인 흐름의 유일한 탈출구라, 요청이 날아가는 몇 초 동안 화면에서
  /// 증발하면 "얼었다"로 읽힌다. 흐려지되 남는다.
  final VoidCallback? onTap;

  /// 활성 색(기본 muted). 되돌릴 수 없는 동작(계정 삭제)은 danger로 구분한다.
  final Color? color;

  /// 기본 11.5 — 로그인 3화면의 보조 문구가 쓰는 최소 크기(P72 C3에서 11 → 11.5로 올렸다).
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final base = color ?? AppColors.muted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                color: onTap == null ? base.withValues(alpha: 0.45) : base,
                decoration: TextDecoration.underline,
                decorationColor: onTap == null ? base.withValues(alpha: 0.45) : base,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
