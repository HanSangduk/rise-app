// 세션 소멸 전환 뷰의 계약(P64).
//
// 이 뷰가 그려지는 순간 세션 리스너가 착지 화면으로 보내는 중이라 보통 한 프레임
// 안에 사라진다. 그래서 ① [다시 시도]가 없고(세션을 만들지 못하는 버튼) ② 리스너가
// 어떤 이유로 이동하지 못했을 때를 위해 **세션을 요구하지 않는 탈출구**를 3초 뒤에
// 낸다 — 즉시 내면 정상 전환의 한 프레임에 버튼이 번쩍인다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_gone_view.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/session/session_store.dart';
import 'package:rise_member/core/theme/app_theme.dart';

void main() {
  const me = AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1');

  ProviderContainer makeContainer() {
    final c = ProviderContainer.test(
      overrides: [sessionStoreProvider.overrideWithValue(_NoopStore())],
    );
    return c;
  }

  testWidgets('처음엔 스피너만 — 재시도 버튼도, 탈출 버튼도 없다', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: makeContainer(),
        child: MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: SessionGoneView())),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing, reason: '세션을 만들지 못하는 버튼을 그렸다');
    expect(find.text('로그인 화면으로'), findsNothing, reason: '정상 전환의 한 프레임에 버튼이 번쩍인다');
  });

  testWidgets('3초 뒤 "로그인 화면으로"가 나타난다 — 스피너에 갇히지 않게', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: makeContainer(),
        child: MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: SessionGoneView())),
      ),
    );
    await tester.pump(const Duration(seconds: 2, milliseconds: 900));
    expect(find.text('로그인 화면으로'), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('로그인 화면으로'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('탈출 버튼은 리스너와 같은 규칙으로 착지한다 — notLinked면 대기실', (tester) async {
    final container = makeContainer();
    container.read(sessionProvider.notifier).set(me);
    container.read(sessionProvider.notifier).clear(reason: SessionEndReason.notLinked);

    final router = GoRouter(
      initialLocation: '/shell',
      routes: [
        GoRoute(
          path: '/shell',
          builder: (_, __) => const Scaffold(
            body: SessionGoneView(escapeAfter: Duration(milliseconds: 10)),
          ),
        ),
        GoRoute(path: '/login', builder: (_, __) => const Text('전화번호 화면')),
        GoRoute(path: '/login/center-confirm', builder: (_, __) => const Text('대기실')),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    // 가짜 시계라 `pump()`만으로는 타이머가 안 돈다 — 시간을 흘려 탈출 버튼을 띄운다.
    await tester.pump(const Duration(milliseconds: 20));

    // P64 검증 반영 — 버튼이 가는 곳을 말해야 한다. 대기실로 가는데 '로그인 화면으로'라
    // 적혀 있으면 회원은 SMS 재인증을 각오하고 누른다.
    expect(find.text('로그인 화면으로'), findsNothing, reason: '연결 해제 착지는 로그인 화면이 아니다');
    await tester.tap(find.text('연결 상태 확인하러 가기'));
    await tester.pumpAndSettle();

    expect(find.text('대기실'), findsOneWidget,
        reason: '연결 해제로 비워진 세션을 여기서만 전화번호 화면으로 보내면 안 된다');
    expect(find.text('전화번호 화면'), findsNothing);
  });

  test('sessionGoneEscapeLabel — 라벨은 착지(sessionEndRoute)와 같은 축으로 갈린다', () {
    expect(sessionGoneEscapeLabel(SessionEndReason.notLinked), '연결 상태 확인하러 가기');
    for (final r in [
      SessionEndReason.signedOut,
      SessionEndReason.unauthorized,
      SessionEndReason.deleted,
    ]) {
      expect(sessionGoneEscapeLabel(r), '로그인 화면으로', reason: '$r — 착지가 /login이다');
    }
  });

  testWidgets('라우터 없이 띄워도(위젯 테스트) 탈출 버튼 탭이 던지지 않는다', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: makeContainer(),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: SessionGoneView(escapeAfter: Duration(milliseconds: 10))),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.text('로그인 화면으로'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _NoopStore implements SessionStore {
  @override
  Future<AppSession?> read(String uid) async => null;
  @override
  Future<void> write(AppSession session) async {}
  @override
  Future<void> clear() async {}
}
