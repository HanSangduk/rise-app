import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/features/records/domain/inbody_metrics.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

/// 인바디 카드의 수치 행 — 6지표 전부 + **직전 측정 대비 증감**.
///
/// 종전엔 SMM/PBF 2행만 하드코딩돼 있었고 weight/bfm/vfl/bmr은 서버 → DTO →
/// 도메인까지 다 와서 화면 직전에 버려졌다. 목업
/// (목업_회원앱_라이즈_2026-08-14.html:226-232)의 `24.1kg ▲0.4` / `26.8% ▼0.9`도
/// 구현되지 않은 상태였다 — 델타는 신규 발명이 아니라 미구현분 이행이다.
///
/// 라벨·방향·생략 문턱은 전부 [InbodyMetric]이 정한다(순수 도메인). 여기서 하는
/// 일은 [InbodyTrend]를 팔레트 색으로 옮기는 것뿐이라, 색과 해석이 어긋날 자리가
/// 한 군데로 줄어든다.
///
/// 차트는 건드리지 않는다 — [InbodyChart]는 SMM/PBF 2시리즈로 남는다. 6지표를
/// 한 캔버스에 넣으면 시리즈별 정규화라도 축 라벨이 없어 BMR(≈1400)과 PBF(≈26)가
/// 같은 높이에 겹쳐 그려져 어느 선이 무엇인지 읽을 수 없다.
class InbodyMetricRows extends StatelessWidget {
  const InbodyMetricRows({super.key, required this.latest, this.previous});

  /// 가장 최근 측정.
  final InbodyRecord latest;

  /// 그 직전 측정 — 없으면(첫 측정) 델타를 그리지 않는다.
  final InbodyRecord? previous;

  /// 차트에 선이 있는 두 지표만 라벨을 칠한다 — 색이 곧 범례다(목업 `■` 표기).
  /// 나머지 4개는 선이 없으므로 칠하면 없는 범례를 가리킨다.
  static const _labelColor = {
    InbodyMetric.smm: AppColors.red,
    InbodyMetric.pbf: AppColors.warn,
  };

  static Color _trendColor(InbodyTrend trend) => switch (trend) {
        InbodyTrend.good => AppColors.ok,
        InbodyTrend.bad => AppColors.danger,
        InbodyTrend.neutral => AppColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    final metrics = InbodyMetric.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, metric) in metrics.indexed)
          RiseRow(
            showDivider: i < metrics.length - 1,
            child: Text(
              metric.label,
              style: TextStyle(color: _labelColor[metric] ?? AppColors.ink),
            ),
            trailing: _ValueWithDelta(
              value: metric.display(latest),
              delta: metric.deltaOf(latest, previous),
            ),
          ),
      ],
    );
  }
}

class _ValueWithDelta extends StatelessWidget {
  const _ValueWithDelta({required this.value, required this.delta});

  final String value;
  final InbodyDelta? delta;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (d != null) ...[
          const SizedBox(width: 5),
          Text(
            d.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: InbodyMetricRows._trendColor(d.trend),
            ),
          ),
        ],
      ],
    );
  }
}
