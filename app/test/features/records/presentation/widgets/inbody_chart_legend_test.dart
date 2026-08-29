// 인바디 추이 차트의 읽을 수 있음(P29).
//
// 종전엔 색만 다른 두 선이 교차할 뿐, 어느 쪽이 근육이고 어느 쪽이 체지방인지
// 화면 어디에도 없었다(실기기 확인). 게다가 두 시리즈는 단위가 kg과 %라 **각자
// 범위로 정규화**돼 있어 선의 높이·교차점에 아무 의미가 없는데, 한 그림에 겹쳐
// 놓으면 회원은 반드시 비교해서 읽는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/presentation/widgets/inbody_chart.dart';

void main() {
  InbodyRecord rec(String date, double smm, double pbf) => InbodyRecord(
        id: 'i-$date',
        date: DateTime.parse(date),
        weight: 70,
        smm: smm,
        bfm: 12,
        pbf: pbf,
        vfl: 6,
        bmr: 1500,
      );

  Future<void> pump(WidgetTester tester, List<InbodyRecord> records) =>
      tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: InbodyChart(records: records)),
      ));

  testWidgets('어느 선이 무엇인지 범례로 말한다', (tester) async {
    await pump(tester, [rec('2026-05-26', 35.6, 13.7), rec('2026-08-23', 32.1, 18.4)]);

    expect(find.text('골격근량(SMM)'), findsOneWidget);
    expect(find.text('체지방률(PBF)'), findsOneWidget);
  });

  testWidgets('높이 비교가 의미 없다는 사실을 밝힌다', (tester) async {
    // 각자 범위로 정규화한 두 선을 겹쳐 놓고 아무 말도 안 하면, 교차점을
    // "근육이 체지방을 넘어섰다"로 읽게 된다.
    await pump(tester, [rec('2026-05-26', 35.6, 13.7), rec('2026-08-23', 32.1, 18.4)]);
    expect(find.textContaining('오르내림만'), findsOneWidget);
  });

  testWidgets('기록이 1개면 차트 대신 이유를 말한다 — 범례도 띄우지 않는다', (tester) async {
    await pump(tester, [rec('2026-08-23', 32.1, 18.4)]);

    expect(find.textContaining('2회 이상 필요해요'), findsOneWidget);
    expect(find.text('골격근량(SMM)'), findsNothing);
  });

  testWidgets('360dp에서 범례가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester, [rec('2026-05-26', 35.6, 13.7), rec('2026-08-23', 32.1, 18.4)]);
    expect(tester.takeException(), isNull);
  });
}
