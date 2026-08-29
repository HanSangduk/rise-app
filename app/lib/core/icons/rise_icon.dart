import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// [RiseIcons]의 SVG 문자열을 렌더링하는 공용 아이콘 위젯.
/// SVG는 `stroke="currentColor"`로 정의되어 있고, [SvgTheme.currentColor]로
/// 실제 색을 주입한다(= flutter_svg의 currentColor 지원).
///
/// 일관된 24x24 viewBox, lucide 스타일 stroke(round cap/join).
class RiseIcon extends StatelessWidget {
  const RiseIcon(
    this.svg, {
    super.key,
    this.size = 24,
    this.color,
  });

  /// [RiseIcons]의 정적 필드 중 하나 (SVG 원문 문자열).
  final String svg;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? const Color(0xFF111827);
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: resolved),
    );
  }
}
