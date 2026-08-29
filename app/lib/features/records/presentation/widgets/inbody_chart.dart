import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

/// 인바디 추이 — 골격근량(SMM, 빨강 실선) · 체지방률(PBF, 주황 파선) 두 시리즈를
/// 각각 자체 범위로 정규화해 추세만 보여준다.
///
/// 선은 **monotone cubic(Fritsch–Carlson) 보간** 곡선이다. Catmull-Rom을 쓰지 않는
/// 이유는 미감이 아니라 정합성이다: min-max 정규화라 극값이 정확히 패딩 경계에
/// 붙는데 Catmull-Rom은 극값 근처에서 경계를 뚫고(overshoot), 무엇보다 두 점 사이에
/// **데이터에 없는 가짜 오르내림**을 만든다 — 아래 캡션이 "오르내림만 봐주세요"라고
/// 말하는 차트에서 그건 유일하게 읽으라고 한 정보를 오염시킨다. monotone은 보간값이
/// 데이터 범위를 벗어나지 않는다.
///
/// PBF를 파선으로 긋는 건 색각이상 대응이다 — 빨강·주황은 적록색각에서 같은
/// 색 밴드라 범례가 둘을 구분해 주지 못한다. 형태(실선/파선)는 색과 무관하게 갈린다.
class InbodyChart extends StatelessWidget {
  const InbodyChart({super.key, required this.records});
  final List<InbodyRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.length < 2) {
      return const SizedBox(
        height: 80,
        child: Center(
          // 카드 안 빈 상태 한 줄은 앱 전체가 11.5 — 여기만 11이었다(J2).
          child: Text(
            '추이를 보려면 인바디 기록이 2회 이상 필요해요',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CustomPaint는 스크린리더에 존재하지 않는다 — 그림이 숨긴 실제 수치를
        // 요약으로 준다(처음→마지막, 시각 사용자가 곡선에서 읽는 것과 같은 정보).
        Semantics(
          label:
              '인바디 추이, 최근 ${records.length}회 — '
              '골격근량 ${_fmt(records.first.smm)}에서 ${_fmt(records.last.smm)}kg, '
              '체지방률 ${_fmt(records.first.pbf)}에서 ${_fmt(records.last.pbf)}%',
          child: SizedBox(
            height: 80,
            width: double.infinity,
            child: CustomPaint(painter: _InbodyChartPainter(records: records)),
          ),
        ),
        const SizedBox(height: 6),
        // **범례가 없으면 이 그림은 읽을 수 없다.** 종전엔 색만 다른 두 선이 교차할 뿐
        // 어느 쪽이 근육이고 어느 쪽이 체지방인지 화면 어디에도 없었다(실기기 확인).
        const Row(
          children: [
            _Legend(color: AppColors.red, label: '골격근량(SMM)'),
            SizedBox(width: 12),
            _Legend(color: AppColors.warn, label: '체지방률(PBF)', dashed: true),
          ],
        ),
        const SizedBox(height: 4),
        // 두 시리즈는 **각자 범위로 정규화**된다(단위가 kg과 %라 같은 축에 못 올린다).
        // 그러면 선이 만나는 지점·높이 차이에 아무 의미가 없는데, 한 그림에 겹쳐 놓으면
        // 회원은 반드시 비교해서 읽는다 — 그래서 무엇을 읽으면 되는지 적는다.
        const Text(
          '두 값은 단위가 달라 각각의 범위로 그렸어요 — 선의 높이가 아니라 오르내림만 봐주세요',
          style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.4),
        ),
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    this.dashed = false,
  });
  final Color color;
  final String label;

  /// 차트의 선 형태(실선/파선)를 범례 스와치에도 그대로 — 색각이상 사용자는
  /// 색이 아니라 이 형태로 두 시리즈를 잇는다.
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dashed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _seg(color, 4),
              const SizedBox(width: 2),
              _seg(color, 4),
            ],
          )
        else
          _seg(color, 10),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
        ),
      ],
    );
  }

  Widget _seg(Color color, double width) => Container(
    width: width,
    height: 3,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _InbodyChartPainter extends CustomPainter {
  _InbodyChartPainter({required this.records});
  final List<InbodyRecord> records;

  /// 이보다 기록이 많으면 중간 점을 숨긴다 — 화면폭 ~300px에서 점 간격이 10px대로
  /// 떨어지면 곡선이 구슬 목걸이가 된다. 처음·마지막 점만 남긴다.
  static const _maxDots = 12;

  @override
  void paint(Canvas canvas, Size size) {
    _drawSeries(canvas, size, [for (final r in records) r.smm], AppColors.red);
    _drawSeries(
      canvas,
      size,
      [for (final r in records) r.pbf],
      AppColors.warn,
      dashed: true,
    );
  }

  void _drawSeries(
    Canvas canvas,
    Size size,
    List<double> values,
    Color color, {
    bool dashed = false,
  }) {
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final n = values.length;

    final points = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(
          n == 1 ? size.width / 2 : size.width * i / (n - 1),
          size.height - 6 - ((values[i] - minV) / range * (size.height - 12)),
        ),
    ];

    final path = _monotonePath(points);
    canvas.drawPath(
      dashed ? _dashPath(path) : path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    _drawDots(canvas, points, color);
  }

  /// Fritsch–Carlson monotone cubic — 구간 기울기(secant)와 부호가 다른 접선을
  /// 0으로 눌러, 곡선이 데이터 점 사이에서 새 극값을 만들지 못하게 한다.
  Path _monotonePath(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    final n = p.length;
    if (n == 2) return path..lineTo(p[1].dx, p[1].dy);

    final h = [for (var i = 0; i < n - 1; i++) p[i + 1].dx - p[i].dx];
    final delta = [
      for (var i = 0; i < n - 1; i++) (p[i + 1].dy - p[i].dy) / h[i],
    ];
    final m = List<double>.filled(n, 0);
    m[0] = delta[0];
    m[n - 1] = delta[n - 2];
    for (var i = 1; i < n - 1; i++) {
      if (delta[i - 1] == 0 ||
          delta[i] == 0 ||
          delta[i - 1].sign != delta[i].sign) {
        m[i] = 0; // 극값(방향 전환) — 접선을 눕혀 overshoot를 막는다.
      } else {
        // 가중 조화 평균 — 간격이 다른(등간격 아님) 표본에도 단조성이 유지되는 형태.
        final w1 = 2 * h[i] + h[i - 1];
        final w2 = h[i] + 2 * h[i - 1];
        m[i] = (w1 + w2) / (w1 / delta[i - 1] + w2 / delta[i]);
      }
    }
    for (var i = 0; i < n - 1; i++) {
      // Hermite → cubic Bézier 제어점 변환(1/3 규칙).
      path.cubicTo(
        p[i].dx + h[i] / 3,
        p[i].dy + m[i] * h[i] / 3,
        p[i + 1].dx - h[i] / 3,
        p[i + 1].dy - m[i + 1] * h[i] / 3,
        p[i + 1].dx,
        p[i + 1].dy,
      );
    }
    return path;
  }

  Path _dashPath(Path source, {double dash = 4, double gap = 3}) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        out.addPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          Offset.zero,
        );
        d += dash + gap;
      }
    }
    return out;
  }

  /// 측정은 이산 이벤트다 — 곡선만 남기면 그 사실이 숨는다. 점은 흰 링 위에 얹어
  /// 선(굵기 2.5)에서 분리하고, 두 시리즈가 교차하는 자리에서도 어느 시리즈의
  /// 측정점인지 링이 구분해 준다. 마지막 점만 반 치수 키운다 — 회원이 이 차트에서
  /// 실제로 묻는 질문("지금 어디쯤인가")의 답이라서. 수치 라벨·별색은 얹지 않는다.
  void _drawDots(Canvas canvas, List<Offset> points, Color color) {
    final ring = Paint()..color = AppColors.surface;
    final fill = Paint()..color = color;
    final showAll = points.length <= _maxDots;
    for (var i = 0; i < points.length; i++) {
      final isLast = i == points.length - 1;
      if (!showAll && !isLast && i != 0) continue;
      final r = isLast ? 3.5 : 2.5;
      canvas.drawCircle(points[i], r + 1.5, ring);
      canvas.drawCircle(points[i], r, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _InbodyChartPainter oldDelegate) =>
      oldDelegate.records != records;
}
