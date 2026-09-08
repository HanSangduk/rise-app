import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/router/app_router.dart';
import 'package:rise_member/core/theme/app_theme.dart';

// P2R — 로그인 3화면 어디에도 PopScope가 없고 라우터 스택이 1장이라
// (전부 context.go) 안드로이드 하드웨어 백이 **앱을 종료**하던 문제.
// 각 화면이 백을 가로채 제 목적지로 보내는지 확인한다.
void main() {
  /// 엔진이 하드웨어 백에서 보내는 것과 같은 플랫폼 메시지.
  /// PopScope가 없으면 프레임워크가 처리하지 않고 앱이 닫힌다(테스트에선 무반응).
  Future<void> pressSystemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Future<GoRouter> pumpLogin(WidgetTester tester, {String? at}) async {
    final router = createRouter();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    if (at != null) {
      router.go(at);
      await tester.pumpAndSettle();
    }
    return router;
  }

  testWidgets('코드 화면 — 백은 번호 입력으로 되돌린다(화면 내 뒤로가기와 같은 목적지)',
      (tester) async {
    await pumpLogin(tester, at: '/login/code');
    expect(find.text('인증번호 입력'), findsOneWidget);

    await pressSystemBack(tester);

    expect(find.text('인증번호 입력'), findsNothing);
    expect(find.text('인증번호 받기'), findsOneWidget); // PhoneScreen
  });

  testWidgets('첫 화면 — 백이 곧바로 앱을 끄지 않고 확인을 받는다', (tester) async {
    await pumpLogin(tester);
    expect(find.text('인증번호 받기'), findsOneWidget);

    await pressSystemBack(tester);

    expect(find.text('앱을 종료할까요?'), findsOneWidget);

    await tester.tap(find.text('계속하기'));
    await tester.pumpAndSettle();

    expect(find.text('앱을 종료할까요?'), findsNothing);
    expect(find.text('인증번호 받기'), findsOneWidget);
  });

  testWidgets('첫 화면 — 백을 연타해도 확인 창이 겹쳐 쌓이지 않는다', (tester) async {
    await pumpLogin(tester);

    await pressSystemBack(tester);
    expect(find.text('앱을 종료할까요?'), findsOneWidget);

    // 두 번째 백은 다이얼로그 라우트가 받는다 — 창이 하나 더 열리는 게 아니라 닫힌다.
    await pressSystemBack(tester);
    expect(find.text('앱을 종료할까요?'), findsNothing);
    expect(find.text('인증번호 받기'), findsOneWidget);

    // 그리고 다시 물을 수 있어야 한다(재진입 가드가 잠긴 채 남으면 안 된다).
    await pressSystemBack(tester);
    expect(find.text('앱을 종료할까요?'), findsOneWidget);
  });

  testWidgets('센터 확인 화면 — 백은 화면 내 탈출구와 같은 목적지를 확인받는다',
      (tester) async {
    await pumpLogin(tester, at: '/login/center-confirm');
    // 화면 내 상시 탈출구.
    expect(find.text('번호 다시 인증하기'), findsOneWidget);

    await pressSystemBack(tester);

    // 인증을 통째로 되돌리는 동작이라 오탭 한 번에 실행되지 않는다.
    expect(find.text('번호 입력으로 돌아갈까요?'), findsOneWidget);

    await tester.tap(find.text('머무르기'));
    await tester.pumpAndSettle();

    expect(find.text('번호 입력으로 돌아갈까요?'), findsNothing);
    expect(find.text('번호 다시 인증하기'), findsOneWidget);
  });
}
