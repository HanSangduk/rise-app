import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/widgets/homework_checklist_card.dart';

// 체크 상태를 모를 때 카드가 하는 일 — 뷰모델 가드(homework_toggle_guard_test)의
// 눈에 보이는 절반. 뷰모델이 요청을 막아도 카드가 평소처럼 눌리고 체크가 켜지면
// 회원은 "저장됐다"고 믿는다. 잠금은 눌러보기 **전에** 보여야 한다.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  const items = [
    HomeworkItem(hwId: 'h1', index: 0, name: '플랭크', done: false),
    HomeworkItem(hwId: 'h1', index: 1, name: '스쿼트', done: false),
  ];

  testWidgets('조회 실패면 탭해도 onToggle이 불리지 않는다', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(host(HomeworkChecklistCard(
      items: items,
      done: 0,
      total: 2,
      checksFailed: true,
      onToggle: (_) => toggles++,
    )));

    await tester.tap(find.text('플랭크'), warnIfMissed: false);
    await tester.tap(find.byType(Checkbox).first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(toggles, 0);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).onChanged, isNull);
  });

  testWidgets('실패 문구를 보여주고 "오늘 0/2" 배지는 숨긴다 — 모르는 값을 확정으로 말하지 않는다', (tester) async {
    await tester.pumpWidget(host(HomeworkChecklistCard(
      items: items,
      done: 0,
      total: 2,
      checksFailed: true,
      onToggle: (_) {},
    )));

    expect(find.textContaining('오늘 체크 상태를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('오늘 0/2'), findsNothing);
  });

  testWidgets('정상 상태에서는 종전대로 토글되고 배지도 뜬다', (tester) async {
    // 잠금이 상시화되면 Home Work 기능 자체가 죽는다 — 반대 방향 고정.
    var toggles = 0;
    await tester.pumpWidget(host(HomeworkChecklistCard(
      items: items,
      done: 1,
      total: 2,
      onToggle: (_) => toggles++,
    )));

    await tester.tap(find.text('플랭크'));
    await tester.pumpAndSettle();

    expect(toggles, 1);
    expect(find.text('오늘 1/2'), findsOneWidget);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
  });

  testWidgets('배정이 0개면 실패 문구를 띄우지 않는다 — 잠글 것도 없다', (tester) async {
    await tester.pumpWidget(host(HomeworkChecklistCard(
      items: const [],
      done: 0,
      total: 0,
      checksFailed: true,
      onToggle: (_) {},
    )));

    expect(find.textContaining('오늘 배정된 Home Work가 없어요'), findsOneWidget);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
    // 빈 상태에서 "코치가 배정했어요"가 함께 뜨면 한 카드 안에서 두 문장이
    // 서로를 부정한다 — footer는 배정이 있을 때만 붙는다(P30).
    expect(find.textContaining('완료율이 보여요'), findsNothing);
  });
}
