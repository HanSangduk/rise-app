// 촬영 포즈 칩의 완료·진행 상태가 스크린리더에 전달된다(P73).
//
// `_PoseChip`은 RiseChip을 본떠 만들었지만 RiseChip이 P54에서 붙인 `Semantics(selected:)`를
// 가져오지 않았다 — 시각으로는 체크·점으로 구분되는 상태가 보조기기에는 "1 차렷"뿐이었다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/pose_sequence_chips.dart';

void main() {
  const poses = [PoseSpec('stand', '차렷'), PoseSpec('tpose', 'T자'), PoseSpec('fold', '전굴')];

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PoseSequenceChips(
            poses: poses,
            completed: const {'stand'},
            currentIndex: 1,
            onSelect: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('완료 포즈는 "촬영 완료", 진행 포즈는 선택 상태 + "지금 찍을 포즈"로 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(find.bySemanticsLabel(RegExp('촬영 완료')), findsOneWidget, reason: '완료 상태가 말로 전달되지 않는다');
    expect(find.bySemanticsLabel(RegExp('지금 찍을 포즈')), findsOneWidget, reason: '진행 상태가 말로 전달되지 않는다');

    // 선택(selected)은 진행 중인 칩 하나에만 붙는다 — RiseChip과 같은 규약. 노드 플래그 API는
    // 프레임워크 버전마다 이름이 바뀌어 왔으므로 위젯 속성(Semantics.properties.selected)으로 본다.
    expect(_selectedOf(tester, '2 T자'), isTrue);
    expect(_selectedOf(tester, '1 차렷'), isFalse);
    expect(_selectedOf(tester, '3 전굴'), isFalse);

    handle.dispose();
  });
}

/// 글자에서 가장 가까운, `selected`를 명시한 Semantics 조상의 값.
bool? _selectedOf(WidgetTester tester, String text) {
  for (final w in tester.widgetList<Semantics>(
    find.ancestor(of: find.text(text), matching: find.byType(Semantics)),
  )) {
    if (w.properties.selected != null) return w.properties.selected;
  }
  return null;
}
