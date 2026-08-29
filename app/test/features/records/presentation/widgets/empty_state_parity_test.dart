// 빈 상태 골격 일치(P29).
//
// 기록 탭 "운동"에서 수업 기록이 없을 때만 **카드 밖 맨 텍스트**로 말하고 있었다.
// 같은 화면의 Home Work 주간 기록도, 다른 탭의 원장·예약·슬롯도 전부 카드 안에서
// 말한다 — 기록이 없는 회원에게는 카드 위에 문장 한 줄이 떠 있는 화면이 됐다(실기기 확인).
//
// `state_view_parity_test`가 빈 상태 ↔ 에러 상태의 골격을 잠그는 것과 같은 이유다:
// 같은 자리에 교대로 나타나는 표현이 다른 골격을 쓰면 같은 앱처럼 보이지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/features/records/presentation/widgets/workout_log_list.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  testWidgets('수업 기록이 없어도 카드 안에서 말한다', (tester) async {
    await pump(tester, const WorkoutLogList(logs: [], homeworkWeeks: []));

    final text = find.textContaining('아직 수업 기록이 없어요');
    expect(text, findsOneWidget);
    expect(
      find.ancestor(of: text, matching: find.byType(RiseCard)),
      findsOneWidget,
      reason: '빈 상태만 카드 밖에 있으면 카드 위에 문장이 떠 있는 화면이 된다',
    );
  });

  testWidgets('같은 화면의 두 빈 상태가 같은 골격을 쓴다', (tester) async {
    await pump(tester, const WorkoutLogList(logs: [], homeworkWeeks: []));

    // 수업 기록 · Home Work 주간 기록 — 둘 다 카드, 둘 다 헤더가 있다.
    expect(find.byType(RiseCard), findsNWidgets(2));
    expect(find.byType(RiseCardHeader), findsNWidgets(2));
  });

  testWidgets('조회 실패는 빈 상태와 다른 말을 한다', (tester) async {
    await pump(
      tester,
      const WorkoutLogList(logs: [], homeworkWeeks: [], homeworkWeeksFailed: true),
    );
    expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    expect(find.textContaining('아직 체크한 Home Work가 없어요'), findsNothing);
  });
}
