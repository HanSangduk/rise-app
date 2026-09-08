// 세션 없이는 셸(홈/예약/기록/마이)에 못 들어간다 — 그 규약이 **코드의 성질**인가(P64).
//
// `session_provider.dart`와 `app_router.dart`는 "셸 이하는 세션이 있다"를 규약으로
// 적어 두었지만 그걸 고정하는 테스트가 없었다. 실제로 구멍이 있었다: go_router는
// 플랫폼 기본 라우트(`platformDispatcher.defaultRouteName`)가 '/'가 아니면
// `initialLocation`을 덮어쓴다(`_effectiveInitialLocation`). 초기 라우트가 `/home`이고
// `restoreLanding`이 null(미로그인)이면 redirect가 null을 돌려 **세션 없이 셸에 착지**했고,
// 4탭 뷰모델이 "로그인이 필요해요"를 그렸다. 지금까지 그 길을 막은 건 코드가 아니라
// AndroidManifest에 VIEW intent-filter가 없다는 **부재**였다.
//
// 뮤테이션: `overridePlatformDefaultLocation: true`를 지우면 첫 테스트가 죽는다(실측 —
// 이 플래그가 없던 코드에서 먼저 실패시켜 D4를 증명한 뒤 통과시켰다). 둘째는 복원이
// 라우트를 돌려주는 한 redirect가 살아 있어 플래그 없이도 통과한다 — 그쪽이 지키는 건
// "대기실 착지가 셸로 새지 않는다"는 별개의 규칙이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/router/app_router.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/auth/presentation/center_confirm_screen.dart';
import 'package:rise_member/features/auth/presentation/center_contact_provider.dart';
import 'package:rise_member/features/auth/presentation/phone_screen.dart';
import 'package:rise_member/features/shell/app_shell.dart';

void main() {
  /// OS가 앱을 `/home`으로 띄웠다고 가정한다(명시적 인텐트에 data를 실은 경우).
  Future<void> pumpWithPlatformRoute(
    WidgetTester tester, {
    required Future<String?> Function() restoreLanding,
  }) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/home';
    addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);

    final container = ProviderContainer.test(
      // 실패한 provider의 자동 재시도 타이머가 테스트 종료 뒤까지 남지 않게.
      retry: (_, __) => null,
      overrides: [
        // 셸이 새어 열리는 경우에도 네트워크로 나가지 않게 정적 값으로 막는다 —
        // 이 테스트가 보는 건 "어디에 섰나"뿐이다.
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        staffMapProvider.overrideWithValue(const AsyncValue<Map<String, StaffDto>>.data({})),
        centerContactProvider.overrideWith((ref, _) async => const CenterContact()),
      ],
    );
    final router = createRouter(restoreLanding: restoreLanding);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('플랫폼 초기 라우트가 /home이고 복원할 세션이 없으면 셸이 아니라 전화번호 화면에 선다',
      (tester) async {
    await pumpWithPlatformRoute(tester, restoreLanding: () async => null);

    expect(find.byType(AppShell), findsNothing,
        reason: '세션 없이 셸에 들어갔다 — 4탭이 세션을 요구하는 에러를 그린다');
    expect(find.byType(PhoneScreen), findsOneWidget, reason: '온보딩 첫 화면이어야 한다');
  });

  testWidgets('같은 조건에서 복원이 대기실을 가리키면 대기실에 선다 — 셸로 새지 않는다',
      (tester) async {
    await pumpWithPlatformRoute(
      tester,
      restoreLanding: () async => '/login/center-confirm',
    );

    expect(find.byType(AppShell), findsNothing, reason: '미연결 회원이 셸에 들어갔다');
    expect(find.byType(CenterConfirmScreen), findsOneWidget);
  });
}
