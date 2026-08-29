import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/presentation/widgets/inbody_metric_rows.dart';

// 기록 탭 인바디 카드는 6지표 중 **2개(SMM/PBF)만** 그리고 있었다.
// weight/bfm/vfl/bmr은 서버 → DTO → 도메인까지 다 와서 화면 직전에 버려졌다.
// 목업(:226-232)에 이미 있던 델타(`▲0.4`/`▼0.9`)도 구현되지 않았다.
//
// 색이 곧 해석이라 방향이 틀리면 나쁜 변화가 초록으로 칠해진다 — 여기서 못 박는다.
void main() {
  InbodyRecord rec({
    String id = 'i1',
    DateTime? date,
    double weight = 70,
    double smm = 30,
    double bfm = 18,
    double pbf = 26,
    double vfl = 8,
    double bmr = 1400,
  }) =>
      InbodyRecord(
        id: id,
        date: date ?? DateTime(2026, 8, 1),
        weight: weight,
        smm: smm,
        bfm: bfm,
        pbf: pbf,
        vfl: vfl,
        bmr: bmr,
      );

  Future<void> pump(WidgetTester tester, {required InbodyRecord latest, InbodyRecord? previous}) {
    return tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: InbodyMetricRows(latest: latest, previous: previous),
        ),
      ),
    ));
  }

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  testWidgets('6지표를 전부 그린다 — 버려지던 4개(체중·BFM·VFL·BMR)가 화면에 온다', (tester) async {
    await pump(tester, latest: rec(weight: 70.2, smm: 24.1, bfm: 18.8, pbf: 26.8, vfl: 8, bmr: 1420));

    expect(find.text('체중'), findsOneWidget);
    expect(find.text('골격근량(SMM)'), findsOneWidget);
    expect(find.text('체지방량(BFM)'), findsOneWidget);
    expect(find.text('체지방률(PBF)'), findsOneWidget);
    expect(find.text('내장지방(VFL)'), findsOneWidget);
    expect(find.text('기초대사량(BMR)'), findsOneWidget);

    expect(find.text('70.2kg'), findsOneWidget);
    expect(find.text('24.1kg'), findsOneWidget);
    expect(find.text('18.8kg'), findsOneWidget);
    expect(find.text('26.8%'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('1420kcal'), findsOneWidget);
  });

  testWidgets('직전 기록이 없으면 델타를 아예 그리지 않는다', (tester) async {
    await pump(tester, latest: rec());

    expect(find.textContaining('▲'), findsNothing);
    expect(find.textContaining('▼'), findsNothing);
  });

  testWidgets('|Δ| < 0.05는 생략 — 측정 노이즈를 변화로 말하지 않는다', (tester) async {
    await pump(tester, latest: rec(smm: 30.04), previous: rec(smm: 30));

    expect(find.textContaining('▲'), findsNothing);
  });

  testWidgets('SMM 상승은 ok색 ▲', (tester) async {
    await pump(tester, latest: rec(smm: 30.4), previous: rec(smm: 30));

    expect(colorOf(tester, '▲0.4'), AppColors.ok);
  });

  testWidgets('PBF 상승은 danger색 ▲ — 같은 화살표가 반대 뜻이다', (tester) async {
    await pump(tester, latest: rec(pbf: 27.0), previous: rec(pbf: 26));

    expect(colorOf(tester, '▲1.0'), AppColors.danger);
  });

  testWidgets('PBF 하락은 ok색 ▼', (tester) async {
    await pump(tester, latest: rec(pbf: 25.1), previous: rec(pbf: 26));

    expect(colorOf(tester, '▼0.9'), AppColors.ok);
  });

  testWidgets('체중·BMR은 중립색 — 증량/감량 목표가 사람마다 반대라 칠하지 않는다', (tester) async {
    await pump(
      tester,
      latest: rec(weight: 72, bmr: 1450),
      previous: rec(weight: 70, bmr: 1400),
    );

    expect(colorOf(tester, '▲2.0'), AppColors.muted);
    expect(colorOf(tester, '▲50.0'), AppColors.muted);
  });

  testWidgets('BFM·VFL 상승도 danger — 어드민이 안 그리던 방향까지 확장한다', (tester) async {
    await pump(tester, latest: rec(bfm: 19.5, vfl: 9), previous: rec(bfm: 18, vfl: 8));

    expect(colorOf(tester, '▲1.5'), AppColors.danger);
    expect(colorOf(tester, '▲1.0'), AppColors.danger);
  });
}
