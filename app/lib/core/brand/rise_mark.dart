import 'package:flutter/material.dart';

/// 라이즈 컨디셔닝 R 마크 — `design/brand/rise-mark.svg`를 좌표 그대로 옮긴 것.
///
/// **자산이 아니라 그림이다.** `pubspec.yaml`에 `assets:` 키가 없어서
/// `assets/brand/*.png`는 런타임에 존재하지 않는다. 마크는 획 3개 + 원 1개라
/// 그리는 편이 자산을 번들하는 것보다 싸고, 해상도에 독립적이며(스플래시는 폰마다
/// 크기가 다르다), 네이티브 스플래시와 픽셀을 맞추기도 쉽다.
///
/// 좌표계는 SVG의 `viewBox="112 106 196 202"`를 그대로 쓴다 — 원본이 브랜드 보드의
/// R을 픽셀 스캔해 재현한 값이라 그 숫자 자체가 근거다(`rise-mark.svg` 헤더 주석).
/// 여기서 좌표를 "정리"하면 원본과의 대조가 불가능해진다.
abstract final class RiseMarkGeometry {
  /// SVG viewBox — `112 106 196 202`.
  static const viewBoxLeft = 112.0;
  static const viewBoxTop = 106.0;
  static const viewBoxWidth = 196.0;
  static const viewBoxHeight = 202.0;

  /// 획 굵기·색·캡 — 전부 SVG 속성 그대로.
  static const strokeWidth = 21.5;
  static const navy = Color(0xFF3B4C60);
  static const beige = Color(0xFFCEBBAA);

  /// 크림 배경은 **SVG 파일에 없다**(주석: "배경은 쓰는 쪽이 깐다").
  /// 네이티브 스플래시와 이 값이 갈리면 첫 프레임에서 배경색이 튄다.
  static const cream = Color(0xFFF6F4EF);

  /// 베이지 점 — 마크에서 **유일하게 움직이는 요소**(P32의 아웃트로).
  static const dotCenter = Offset(287, 284.5);
  static const dotRadius = 17.0;

  /// 네이비 획 3개. SVG `d` 속성을 명령 단위로 옮긴다.
  ///
  /// 원본이 절대 좌표(`C`·`Q`·`L` 대문자)만 쓰므로 `cubicTo`/`quadraticBezierTo`가
  /// 1:1로 대응한다 — 상대 좌표였다면 누적 계산이 필요했을 자리다.
  static Path strokePaths() {
    final p = Path();

    // 큰 열린 아치.
    p.moveTo(127, 164);
    p.cubicTo(137, 143, 158, 124, 182, 121);
    p.cubicTo(190, 120, 202, 120, 210, 122);
    p.cubicTo(232, 127, 249, 138, 257, 155);
    p.cubicTo(263, 167, 265, 180, 262, 196);
    p.cubicTo(259, 214, 251, 228, 240, 238);
    p.cubicTo(231, 245, 221, 249, 206, 249);

    // R의 다리.
    p.moveTo(208, 252);
    p.cubicTo(217, 263, 224, 272, 232, 280);
    p.cubicTo(240, 288, 245, 291, 250, 293);

    // 안쪽 r형 획.
    p.moveTo(159.5, 290);
    p.lineTo(159.5, 214);
    p.quadraticBezierTo(159.5, 195.5, 178, 195.5);
    p.lineTo(190, 195.5);
    p.quadraticBezierTo(197, 196, 201, 198.5);

    return p;
  }

  /// viewBox 좌표계를 [size] 안에 **비율을 지켜** 앉히는 변환.
  ///
  /// 늘리지 않는다 — 마크가 조금이라도 찌그러지면 브랜드가 아니게 된다.
  static void applyTransform(Canvas canvas, Size size) {
    final scale = (size.width / viewBoxWidth) < (size.height / viewBoxHeight)
        ? size.width / viewBoxWidth
        : size.height / viewBoxHeight;
    canvas.translate(
      (size.width - viewBoxWidth * scale) / 2,
      (size.height - viewBoxHeight * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-viewBoxLeft, -viewBoxTop);
  }
}

/// R 마크를 그린다.
///
/// [dotProgress] 0 = 점이 아직 없다(네이티브 스플래시가 보여주는 그림) ·
/// 1 = 점이 제자리에 있다. 이 한 값이 P32 아웃트로의 전부다.
class RiseMarkPainter extends CustomPainter {
  const RiseMarkPainter({this.dotProgress = 1, this.opacity = 1});

  final double dotProgress;

  /// 마크 전체의 불투명도. **`Opacity` 위젯 대신 여기로 받는다** — 전체화면
  /// `Opacity`는 오프스크린 레이어를 떠서 기동 중 래스터 스레드에 화면 크기만 한
  /// 합성을 매 프레임 얹는다. 획과 점이 겹치지 않아 색에 직접 넣어도 결과가 같다.
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    RiseMarkGeometry.applyTransform(canvas, size);

    canvas.drawPath(
      RiseMarkGeometry.strokePaths(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = RiseMarkGeometry.strokeWidth
        ..strokeCap = StrokeCap.round
        // 획은 이어진 곡선이라 join도 둥글어야 캡과 실루엣이 맞는다.
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..color = RiseMarkGeometry.navy.withValues(alpha: opacity),
    );

    if (dotProgress > 0) {
      canvas.drawCircle(
        RiseMarkGeometry.dotCenter,
        // 반지름으로 자란다 — 위치가 고정이라 "날아오는" 게 아니라 "도착해 있는"
        // 느낌이 된다. 마크의 정체성은 셋의 **상대 위치**라 점을 옮기면 안 된다
        // (`rise-mark.svg` 주석: "개별 요소를 따로 옮기지 말 것").
        RiseMarkGeometry.dotRadius * dotProgress,
        Paint()
          ..isAntiAlias = true
          ..color = RiseMarkGeometry.beige.withValues(alpha: opacity),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RiseMarkPainter old) =>
      old.dotProgress != dotProgress || old.opacity != opacity;
}

/// 마크 한 개를 그리는 위젯. 크기는 부모가 정한다.
class RiseMark extends StatelessWidget {
  const RiseMark({
    super.key,
    this.size = 120,
    this.dotProgress = 1,
    this.opacity = 1,
  });

  final double size;
  final double dotProgress;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * RiseMarkGeometry.viewBoxHeight / RiseMarkGeometry.viewBoxWidth,
      child: CustomPaint(
        painter: RiseMarkPainter(dotProgress: dotProgress, opacity: opacity),
      ),
    );
  }
}
