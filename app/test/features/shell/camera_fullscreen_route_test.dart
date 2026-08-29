// 촬영이 **탭이 아니라 전체화면 모드**인가(P21 C).
//
// 라우팅을 바꿨는데 기존 794건이 전부 통과했다 — 탭 인덱스와 촬영 진입을 확인하는 테스트가
// 하나도 없었다는 뜻이다. 다음에 브랜치를 건드리면 조용히 깨진다:
//   · 탭 4개의 인덱스가 밀리면 "기록"을 눌렀는데 "마이"가 열린다
//   · 촬영이 다시 브랜치가 되면 탭바가 프리뷰를 가리고 카메라 수명주기가 이중 판정으로 돌아간다
//
// 카메라 화면 자체는 실기기 하드웨어를 잡으므로 위젯 테스트로 띄우지 않는다. 여기서 지키는
// 것은 **셸의 계약**이다: 탭 4개는 브랜치를 바꾸고, 촬영 버튼은 브랜치를 바꾸지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/features/shell/app_shell.dart';

/// 실제 셸을 최소 브랜치 4개 위에 띄운다(카메라 라우트는 더미로 대체 — 하드웨어 회피).
Widget _harness({required List<String> pushed}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/camera',
        pageBuilder: (_, __) {
          pushed.add('/camera');
          return const MaterialPage(
            fullscreenDialog: true,
            child: Scaffold(body: Text('CAMERA')),
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, __) => const Text('HOME'))],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/booking', builder: (_, __) => const Text('BOOKING'))],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/records', builder: (_, __) => const Text('RECORDS'))],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/my', builder: (_, __) => const Text('MY'))],
          ),
        ],
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  testWidgets('탭 4개가 각자의 화면을 연다 — 인덱스가 밀리지 않는다', (tester) async {
    await tester.pumpWidget(_harness(pushed: []));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);

    for (final (label, screen) in [('예약', 'BOOKING'), ('기록', 'RECORDS'), ('마이', 'MY')]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text(screen), findsOneWidget, reason: '"$label" 탭이 $screen을 열지 않았다');
    }
  });

  testWidgets('촬영 버튼은 전체화면 라우트를 push한다(브랜치 전환이 아니다)', (tester) async {
    final pushed = <String>[];
    await tester.pumpWidget(_harness(pushed: pushed));
    await tester.pumpAndSettle();

    await tester.tap(find.text('촬영'));
    await tester.pumpAndSettle();

    expect(pushed, ['/camera'], reason: '촬영이 라우트로 열리지 않았다');
    expect(find.text('CAMERA'), findsOneWidget);
    // 전체화면이므로 탭바가 덮여야 한다 — 남아 있으면 프리뷰를 가린다.
    expect(find.text('홈'), findsNothing, reason: '촬영 화면 위에 탭바가 남아 있다');
  });

  testWidgets('촬영에서 나오면 있던 탭으로 돌아온다', (tester) async {
    await tester.pumpWidget(_harness(pushed: []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('촬영'));
    await tester.pumpAndSettle();

    // 시스템 백(= AppBar close와 같은 pop).
    final router = GoRouter.of(tester.element(find.text('CAMERA')));
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('RECORDS'), findsOneWidget, reason: '촬영 전 탭으로 복귀하지 않았다');
  });

  testWidgets('촬영 버튼은 선택 상태를 갖지 않는다', (tester) async {
    await tester.pumpWidget(_harness(pushed: []));
    await tester.pumpAndSettle();

    // 탭이 아니므로 어떤 탭에 있든 "촬영" 라벨의 굵기가 변하지 않는다.
    TextStyle styleOf(String label) =>
        tester.widget<Text>(find.text(label)).style ?? const TextStyle();
    final before = styleOf('촬영').fontWeight;

    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();

    expect(styleOf('촬영').fontWeight, before);
    expect(styleOf('마이').fontWeight, FontWeight.w800, reason: '탭은 선택 상태를 가져야 한다');
  });
}
