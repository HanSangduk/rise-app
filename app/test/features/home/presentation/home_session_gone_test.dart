// 홈 탭 — 셸이 그려진 채 세션이 비면 **문구도 재시도 버튼도** 그리지 않는다(P64).
//
// 종전엔 뷰모델이 `AuthFailure('로그인이 필요해요')`를 던지고 화면이 '문제가 생겼어요'
// + 그 문장 + [다시 시도]를 그렸다. 뷰모델은 세션이 왜 비었는지 모르므로 그 문장은
// 연결 해제 경로에서 거짓이고(신원은 살아 있다), 그 버튼은 세션을 만들지 못한다.
// 지금은 타입(`SessionGoneFailure`)만 내고 화면은 전환 뷰를 그린다 — 리스너가 이동 중.
//
// 뮤테이션: 뷰모델의 throw를 `AuthFailure('로그인이 필요해요')`로 되돌리면 죽는다.
// 화면의 `e is SessionGoneFailure` 분기를 지워도 죽는다(재시도 버튼이 그려진다).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/session/session_gone_view.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/rise_error_view.dart';
import 'package:rise_member/features/home/presentation/home_screen.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';

void main() {
  testWidgets('세션 null → SessionGoneFailure · 전환 뷰 · 재시도 없음 · 옛 문구 없음', (tester) async {
    final container = ProviderContainer.test(
      // 실패한 provider의 자동 재시도 타이머가 테스트 종료 뒤까지 남지 않게.
      retry: (_, __) => null,
      overrides: [
        // 뷰모델은 세션 검사에서 멈춰야 한다 — 저장소까지 오면 이 스텁이 던져 타입이 갈린다.
        homeRepositoryProvider.overrideWith((ref) => throw StateError('세션 없이 저장소를 만졌다')),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        staffMapProvider.overrideWithValue(const AsyncValue<Map<String, StaffDto>>.data({})),
      ],
    );
    addTearDown(container.dispose);
    // 세션을 채우지 않는다 — 셸이 떠 있는 채 비워진 그 프레임을 그대로 그린다.

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
      ),
    );
    // `pumpAndSettle`은 못 쓴다 — 전환 뷰의 스피너가 영원히 돈다. 뷰모델의 실패는
    // 마이크로태스크 하나 뒤에 도착하므로 두 프레임이면 충분하다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final vm = container.read(homeViewModelProvider);
    expect(vm, isA<AsyncError<Object?>>(), reason: '세션 없이 데이터가 나왔다');
    expect(vm.error, isA<SessionGoneFailure>(), reason: '뷰모델이 원인을 모르면서 문구를 말했다');

    expect(find.byType(SessionGoneView), findsOneWidget);
    expect(find.byType(RiseErrorView), findsNothing, reason: '에러 뷰가 그려졌다');
    expect(find.text('다시 시도'), findsNothing, reason: '세션을 만들지 못하는 버튼을 그렸다');
    expect(find.text('로그인이 필요해요'), findsNothing, reason: '연결 해제 경로에선 거짓 문장이다');
    expect(find.text('문제가 생겼어요'), findsNothing);
  });
}
