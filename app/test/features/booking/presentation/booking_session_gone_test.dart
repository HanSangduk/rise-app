// 예약 탭 — 셸이 그려진 채 세션이 비면 **문구도 재시도 버튼도** 그리지 않는다(P64).
// 규약은 `home_session_gone_test`와 같다 — 그 파일 머리말 참조.
//
// 예약 뷰모델은 홈 뷰모델의 future를 watch하므로 두 뷰모델이 같은 프레임에 같은
// 타입을 내야 한다. 예약이 먼저 세션을 검사해 홈 쪽 실패를 기다리지 않는다.

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
import 'package:rise_member/features/booking/presentation/booking_screen.dart';
import 'package:rise_member/features/booking/presentation/booking_view_model.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';

void main() {
  testWidgets('세션 null → SessionGoneFailure · 전환 뷰 · 재시도 없음 · 옛 문구 없음', (tester) async {
    final container = ProviderContainer.test(
      retry: (_, __) => null,
      overrides: [
        homeRepositoryProvider.overrideWith((ref) => throw StateError('세션 없이 저장소를 만졌다')),
        bookingRepositoryProvider.overrideWith((ref) => throw StateError('세션 없이 저장소를 만졌다')),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        staffMapProvider.overrideWithValue(const AsyncValue<Map<String, StaffDto>>.data({})),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const BookingScreen()),
      ),
    );
    // `pumpAndSettle`은 못 쓴다 — 전환 뷰의 스피너가 영원히 돈다. 뷰모델의 실패는
    // 마이크로태스크 하나 뒤에 도착하므로 두 프레임이면 충분하다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final vm = container.read(bookingViewModelProvider);
    expect(vm, isA<AsyncError<Object?>>());
    expect(vm.error, isA<SessionGoneFailure>(), reason: '뷰모델이 원인을 모르면서 문구를 말했다');

    expect(find.byType(SessionGoneView), findsOneWidget);
    expect(find.byType(RiseErrorView), findsNothing);
    expect(find.text('다시 시도'), findsNothing, reason: '세션을 만들지 못하는 버튼을 그렸다');
    expect(find.text('로그인이 필요해요'), findsNothing, reason: '연결 해제 경로에선 거짓 문장이다');
  });
}
