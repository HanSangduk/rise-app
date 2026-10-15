import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/presentation/widgets/workout_log_list.dart';

// 수업 기록은 최근 10건만 먼저 그리고 "더 보기"로 20건씩 편다(P74).
//
// 서버는 회원의 수업 기록 **전체**를 한 번에 준다(계약에 페이지네이션이 없다). 종전엔 그 전부를
// 탭을 열 때마다 즉시 빌드했다 — 주 2~3회 회원이 1년이면 100건+, 카드마다 운동 행이 또 반복된다.
// 원장(LedgerList)의 "최근 3건 + 전체" 규약을 같은 탭에 맞게 옮긴 것이다.
void main() {
  WorkoutLog log(int i) => WorkoutLog(
        id: 'w$i',
        date: DateTime(2026, 1, 1).add(Duration(days: i)),
        title: '세션 $i',
        exercises: const [ExerciseEntry(name: '스쿼트', sets: 3, reps: '12', weightKg: 60)],
      );

  Future<void> pump(WidgetTester tester, List<WorkoutLog> logs) => tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: WorkoutLogList(logs: logs, homeworkWeeks: const [])),
          ),
        ),
      );

  testWidgets('25건이면 처음엔 10건 + "이전 수업 15건" 행, 더 보기로 전부 펴진다', (tester) async {
    final logs = [for (var i = 25; i >= 1; i--) log(i)]; // 최신 먼저(레포지토리 정렬과 같음)
    await pump(tester, logs);

    expect(find.textContaining('세션 25'), findsOneWidget, reason: '최신 세션이 먼저 보인다');
    expect(find.textContaining('세션 16'), findsOneWidget, reason: '10번째까지 보인다');
    expect(find.textContaining('세션 15'), findsNothing, reason: '11번째부터는 접혀 있다');
    expect(find.text('… 이전 수업 15건'), findsOneWidget);

    await tester.ensureVisible(find.text('더 보기')); // 10장 아래 접힘 밖에 있다
    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp(r'· 세션 1$')), findsOneWidget, reason: '25건 전부 펴졌다(10 + 20 ≥ 25)');
    expect(find.text('더 보기'), findsNothing, reason: '남은 게 없으면 행이 사라진다');
  });

  // 위 시험은 한 번에 전부 펴지는 25건이라 "한 번에 몇 건"을 고정하지 못한다(pageSize가 15 이상이면 무엇이든 통과).
  testWidgets('35건이면 10 → 30 → 35 — 더 보기 한 번에 정확히 20건씩 편다', (tester) async {
    await pump(tester, [for (var i = 35; i >= 1; i--) log(i)]);
    expect(find.text('… 이전 수업 25건'), findsOneWidget);

    await tester.ensureVisible(find.text('더 보기'));
    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'· 세션 6$')), findsOneWidget, reason: '30번째까지 펴졌다');
    expect(find.textContaining(RegExp(r'· 세션 5$')), findsNothing, reason: '31번째는 아직 접혀 있다 — 한 번에 20건');
    expect(find.text('… 이전 수업 5건'), findsOneWidget);

    await tester.ensureVisible(find.text('더 보기'));
    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'· 세션 1$')), findsOneWidget);
    expect(find.text('더 보기'), findsNothing);
  });

  testWidgets('10건 이하면 더 보기 행이 없다 — 상시 노출되면 없는 기록을 약속한다', (tester) async {
    await pump(tester, [for (var i = 10; i >= 1; i--) log(i)]);
    expect(find.text('더 보기'), findsNothing);
    expect(find.textContaining(RegExp(r'· 세션 1$')), findsOneWidget);
  });

  testWidgets('더 보기 행은 스크린리더에 남은 건수와 함께 "버튼"으로 읽힌다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, [for (var i = 12; i >= 1; i--) log(i)]);
    final node = tester.getSemantics(find.text('더 보기'));
    expect(node, isSemantics(isButton: true, hasTapAction: true));
    expect(node.label, contains('이전 수업 2건'), reason: '"더 보기"만 읽으면 몇 건이 숨어 있는지 모른다');
    semantics.dispose();
  });

  testWidgets('더 보기 행은 44dp 이상이다(원장 행과 같은 터치 기준)', (tester) async {
    await pump(tester, [for (var i = 12; i >= 1; i--) log(i)]);
    final row = find.ancestor(of: find.text('더 보기'), matching: find.byType(InkWell)).first;
    expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
  });
}
