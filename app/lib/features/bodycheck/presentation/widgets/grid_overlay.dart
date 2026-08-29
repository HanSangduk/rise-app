import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';

/// 체형 촬영 프레이밍 가이드 — 촘촘한 격자 + 이동 가능한 빨간 기준선 + 발위치 마커.
///
/// **격자가 촘촘해야 하는 이유**: 이 격자는 예쁘라고 있는 게 아니라 **나중에 두 장을
/// 비교할 때의 눈금자**다. 칸이 크면 어깨가 반 칸 내려온 건지 한 칸 내려온 건지 구분이
/// 안 되고, 그게 곧 "얼마나 변했는지"를 못 읽는다는 뜻이다.
///
/// 굵기를 두 단계로 나눈다(주선/보조선). 균일한 촘촘한 격자는 눈이 칸을 셀 수 없어
/// 오히려 판독이 어렵다 — 5칸마다 진한 선을 둬서 "세 번째 굵은 선 아래 두 칸"처럼
/// 위치를 말로 옮길 수 있게 한다(제도용 모눈지가 쓰는 방식).
///
/// [hLine]은 어깨·골반 높이를 맞추는 수평 기준선이고 **손으로 끌어 옮길 수 있다**
/// (0~1 비율). 사람마다 키가 다르므로 고정 높이는 아무 데도 안 맞는다.
class GridOverlay extends StatelessWidget {
  const GridOverlay({
    super.key,
    this.density = GridDensity.fine,
    this.hLine = 0.60,
  });

  final GridDensity density;

  /// 수평 기준선의 세로 위치(0=위, 1=아래).
  final double hLine;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _GridPainter(density: density, hLine: hLine)),
      ),
    );
  }
}

/// 격자 밀도 — 촬영 조건에 따라 고르게 한다.
///
/// 전신을 멀리서 찍으면 촘촘한 편이 좋고, 상체만 가까이 찍으면 성긴 편이 덜 어지럽다.
enum GridDensity {
  /// 성김 — 예전 기본값(9×12). 프레이밍만 볼 때.
  coarse(9, 12, 3),

  /// 촘촘 — 기본값. 변화량 판독용.
  fine(18, 24, 6),

  /// 매우 촘촘 — 미세한 좌우 차이를 볼 때.
  ultra(28, 36, 7);

  const GridDensity(this.cols, this.rows, this.majorEvery);

  final int cols;
  final int rows;

  /// 몇 칸마다 진한 주선을 그을지(칸을 셀 수 있게).
  final int majorEvery;

  String get label => switch (this) {
        GridDensity.coarse => '성김',
        GridDensity.fine => '촘촘',
        GridDensity.ultra => '아주 촘촘',
      };

  GridDensity get next => switch (this) {
        GridDensity.coarse => GridDensity.fine,
        GridDensity.fine => GridDensity.ultra,
        GridDensity.ultra => GridDensity.coarse,
      };
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.density, required this.hLine});

  final GridDensity density;
  final double hLine;

  @override
  void paint(Canvas canvas, Size size) {
    // 보조선은 아주 옅게 — 촘촘해질수록 선이 화면을 덮어 피사체가 안 보인다.
    final minor = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 0.5;
    final major = Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..strokeWidth = 1;

    for (var i = 1; i < density.cols; i++) {
      final x = size.width * i / density.cols;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        i % density.majorEvery == 0 ? major : minor,
      );
    }
    for (var i = 1; i < density.rows; i++) {
      final y = size.height * i / density.rows;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        i % density.majorEvery == 0 ? major : minor,
      );
    }

    // **얇게 긋는다.** 굵은 선은 그 자체가 몇 픽셀을 덮어 어깨선·골반선을 맞출 때
    // 오차가 된다 — 선이 가리는 만큼 어디에 맞췄는지 알 수 없다.
    final crossPaint = Paint()
      ..color = AppColors.camCrosshair
      ..strokeWidth = 1;

    // 중심 수직선(전신 좌우 대칭 기준) — 이건 항상 가운데다.
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      crossPaint,
    );

    // 수평 기준선 — 어깨·골반 높이에 맞춰 회원이 끌어 옮긴다.
    final hy = size.height * hLine.clamp(0.05, 0.95);
    canvas.drawLine(
      Offset(size.width * 0.07, hy),
      Offset(size.width * 0.93, hy),
      crossPaint,
    );
    // 끌 수 있다는 표시 — 오른쪽 끝 손잡이(예시 앱과 같은 어포던스).
    canvas.drawCircle(
      Offset(size.width * 0.93, hy),
      6,
      Paint()..color = AppColors.camCrosshair,
    );

    // 발위치 마커 — 매번 같은 거리에서 서도록.
    final dotCenter = Offset(size.width / 2, size.height * 0.92);
    canvas.drawCircle(
      dotCenter,
      9,
      Paint()
        ..color = AppColors.camCrosshair
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(dotCenter, 4, Paint()..color = AppColors.camCrosshair);
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.density != density || old.hLine != hLine;
}
