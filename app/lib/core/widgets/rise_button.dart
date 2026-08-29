import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_typography.dart';

enum RiseButtonStyleKind { primary, outline }

/// 목업 `.btn-p` / `.btn-o` — 작은 버튼(카드 내 인라인 액션)까지 커버.
class RiseButton extends StatelessWidget {
  const RiseButton({
    super.key,
    required this.label,
    this.onPressed,
    this.style = RiseButtonStyleKind.primary,
    this.small = false,
    this.expand = false,
    this.onDark = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final RiseButtonStyleKind style;
  final bool small;
  final bool expand;

  /// 어두운 배경 위에 놓이는가(체형 촬영 전체화면). 이 위젯은 라벨 색을 **자식 Text에
  /// 직접** 박기 때문에 상위 `Theme`로는 덮을 수 없다 — 실기기에서 검은 배경 위
  /// outline 버튼의 글자가 통째로 묻혀서 알았다. 옵션으로 명시하는 편이 호출부에서
  /// 의도가 보이고, 테마 우회처럼 조용히 깨지지도 않는다.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final padding = small
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 12);
    final textStyle = small
        ? AppTypography.button.copyWith(fontSize: 10.5)
        : AppTypography.button;

    // 라벨에 회원 이름이 들어가는 전폭 CTA가 있다("네, $memberName 본인이에요 —
    // 시작하기"). 긴 이름·큰 글꼴 배율에서 버튼이 3~4줄로 늘어나지 않게 2줄에서
    // 끊고, 두 줄이 될 때 아랫줄이 왼쪽으로 붙지 않게 가운데 정렬한다.
    // (한 줄에 들어가는 지금의 모든 라벨에는 둘 다 무영향 — 버튼이 텍스트 폭에
    //  맞춰 줄어들므로 정렬할 여백 자체가 없다.)
    final Widget child = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: textStyle.copyWith(
        color: style == RiseButtonStyleKind.primary
            ? Colors.white
            : (onPressed == null
                  ? (onDark ? Colors.white38 : AppColors.muted)
                  : (onDark ? Colors.white : AppColors.ink)),
      ),
    );

    final button = switch (style) {
      RiseButtonStyleKind.primary => ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(padding: padding),
        child: child,
      ),
      RiseButtonStyleKind.outline => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: padding,
          side: onDark ? const BorderSide(color: Colors.white54) : null,
        ),
        child: child,
      ),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
