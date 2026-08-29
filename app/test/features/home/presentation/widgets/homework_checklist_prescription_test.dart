import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/widgets/homework_checklist_card.dart';

// Home Work 카드 — 코치가 처방한 세트·횟수가 **화면에 실제로 보이는가**.
//
// 리포지토리까지 값이 올라와도(homework_sets_reps_test) 카드가 안 그리면 회원에겐
// 여전히 없는 기능이다. 배정의 알맹이는 이름이 아니라 처방("몇 세트 몇 회")이라
// 렌더까지가 이 결함의 끝이다.
void main() {
  Widget host(List<HomeworkItem> items) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeworkChecklistCard(
              items: items,
              done: 0,
              total: items.length,
              onToggle: (_) {},
            ),
          ),
        ),
      );

  testWidgets('세트·횟수가 항목마다 보인다', (tester) async {
    await tester.pumpWidget(host(const [
      HomeworkItem(hwId: 'h1', index: 0, name: '플랭크', sets: 3, reps: '40초', done: false),
      HomeworkItem(hwId: 'h1', index: 1, name: '스쿼트', sets: 3, reps: '15', done: false),
    ]));

    expect(find.text('3×40초'), findsOneWidget);
    expect(find.text('3×15'), findsOneWidget);
    // 운동 이름은 처방과 **다른 위젯**으로 남는다 — 한 줄로 이어붙이면 긴 이름에서
    // 처방이 말줄임에 먹힌다(맨 오른쪽 고정이라 항상 읽힌다).
    expect(find.text('플랭크'), findsOneWidget);
  });

  testWidgets('note가 있어도 처방과 함께 보인다 — 둘 중 하나만 살아남지 않는다', (tester) async {
    await tester.pumpWidget(host(const [
      HomeworkItem(
          hwId: 'h1', index: 0, name: '스쿼트', sets: 3, reps: '15', note: '무릎 방향 주의', done: false),
    ]));

    expect(find.text('스쿼트 — 무릎 방향 주의'), findsOneWidget);
    expect(find.text('3×15'), findsOneWidget);
  });

  testWidgets('처방이 없는 항목은 빈 자리를 만들지 않는다 — "0×"·"×" 같은 잔해 금지', (tester) async {
    await tester.pumpWidget(host(const [
      HomeworkItem(hwId: 'h1', index: 0, name: '스트레칭', done: false),
      HomeworkItem(hwId: 'h1', index: 1, name: '걷기', reps: '30분', done: false),
      HomeworkItem(hwId: 'h1', index: 2, name: '버피', sets: 3, done: false),
    ]));

    expect(find.textContaining('×'), findsNothing);
    expect(find.text('30분'), findsOneWidget, reason: 'sets가 없어도 reps는 처방이다');
    expect(find.text('3세트'), findsOneWidget, reason: 'reps가 없어도 sets는 처방이다');
    expect(find.text('스트레칭'), findsOneWidget);
  });

  testWidgets('긴 reps + 긴 이름이 실기기 폭(360dp)에서 행을 넘치지 않는다', (tester) async {
    // reps는 코치 자유 입력이라 계약상 길이 상한이 없다. 기본 테스트 화면(800dp)에선
    // 안 터지고 실기기에서만 오버플로 줄무늬가 뜨던 자리 — 폭을 실기기로 맞춰 고정한다.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const [
      HomeworkItem(
        hwId: 'h1',
        index: 0,
        name: '루마니안 데드리프트 바벨 힙힌지 드릴 아주 긴 이름',
        sets: 3,
        reps: '각 15회 좌우 번갈아 천천히 통증 없는 범위에서',
        note: '무릎 방향 주의하고 허리 중립 유지',
        done: false,
      ),
    ]));
    await tester.pumpAndSettle();

    // 오버플로가 나면 pumpAndSettle 단계에서 예외로 잡힌다 — 여기까지 왔다는 게 통과다.
    expect(tester.takeException(), isNull);
  });

  group('빈 메모 — 구분자만 남지 않는다', () {
    // 서버는 메모 없음을 `""`로 준다(Go `HwItem.Note`는 string, 포인터가 아니다).
    // 그대로 넘기면 화면에 `'스쿼트 — '`처럼 em dash만 남는다 — 실기기 플로우
    // 점검에서 실제로 그렇게 떴다.
    test('빈 문자열 메모는 없는 것으로 정규화된다', () {
      String? normalize(String? note) =>
          (note?.trim().isEmpty ?? true) ? null : note!.trim();

      expect(normalize(''), isNull);
      expect(normalize('   '), isNull);
      expect(normalize(null), isNull);
      expect(normalize('허리 중립'), '허리 중립');
      expect(normalize('  허리 중립  '), '허리 중립');
    });

    testWidgets('메모가 비면 이름만 그린다', (tester) async {
      await tester.pumpWidget(host(const [
        HomeworkItem(hwId: 'h1', index: 0, name: '스쿼트', done: false, sets: 4, reps: '12회'),
      ]));

      expect(find.text('스쿼트'), findsOneWidget);
      expect(find.textContaining('—'), findsNothing);
    });

    testWidgets('메모가 있으면 종전대로 이어 붙인다', (tester) async {
      await tester.pumpWidget(host(const [
        HomeworkItem(
          hwId: 'h1', index: 0, name: '플랭크', done: false,
          sets: 3, reps: '40초', note: '허리 중립',
        ),
      ]));

      expect(find.text('플랭크 — 허리 중립'), findsOneWidget);
    });
  });
}
