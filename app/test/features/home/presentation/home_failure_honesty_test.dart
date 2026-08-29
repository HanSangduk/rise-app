// 홈이 모르는 걸 사실처럼 말하지 않는다(P33).
//
// 셋 다 같은 종류의 결함이다 — **앱이 모르는 것을 아는 척하거나, 실패를 숨긴다.**
// 화면이 멀쩡해 보여서 감사에서도 늦게 잡혔다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/widgets/next_booking_card.dart';

void main() {
  NextBooking bookingAt(DateTime start) => NextBooking(
        id: 'b1',
        startAt: start,
        kind: 'pt',
        trainerName: '정혜린',
      );

  /// 카드는 내부에서 KST 현재 시각을 읽는다 — 컷오프 여유/경과는 **예약 시각을
  /// 옮겨서** 만든다.
  Future<void> pumpCard(
    WidgetTester tester, {
    required bool cutoffUnknown,
    required Duration fromNow,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: NextBookingCard(
            booking: bookingAt(DateTime.now().add(fromNow)),
            cutoffHours: 24,
            cutoffUnknown: cutoffUnknown,
            onCheckIn: () {},
          ),
        ),
      ),
    );
  }

  group('① 정책을 못 받았으면 시간을 말하지 않는다', () {
    testWidgets('폴백일 때 "24시간 전까지"라고 찍지 않는다', (tester) async {
      // 센터 실제 기준이 48시간인데 폴백 24시간을 사실처럼 찍으면, 그 문구를 믿고
      // 30시간 전에 취소한 회원이 **차감된다.** 앱이 한 약속 때문에 회원이 손해를 본다.
      await pumpCard(tester,
          cutoffUnknown: true, fromNow: const Duration(days: 3)); // 컷오프 여유

      expect(find.textContaining('24시간'), findsNothing,
          reason: '모르는 값을 사실처럼 말했다');
      expect(find.textContaining('예약 탭에서 확인'), findsOneWidget);
    });

    testWidgets('서버 값이면 종전대로 시간을 말한다 — 과잉 차단이 아니다', (tester) async {
      await pumpCard(tester,
          cutoffUnknown: false, fromNow: const Duration(days: 3));

      expect(find.textContaining('24시간 전까지 취소 가능'), findsOneWidget);
    });

    testWidgets('컷오프가 지난 뒤 문구는 폴백이어도 그대로 — 서버가 최종 판정한다', (tester) async {
      // "지금 취소하면 차감"은 시각 판정이 아니라 사실 진술이고, 실제 차감 여부는
      // 서버가 정한다. 여기까지 숨기면 회원이 대가를 모른 채 취소한다.
      await pumpCard(tester,
          cutoffUnknown: true, fromNow: const Duration(minutes: 30)); // 컷오프 경과

      expect(find.textContaining('세션 1회가 차감'), findsOneWidget);
    });
  });

  group('폴백 표시가 값에 딸려 온다', () {
    test('CenterPolicy.fallback은 스스로 폴백이라고 말한다', () {
      // 받는 쪽이 출처를 구별할 수 없던 게 ①의 원인이었다.
      expect(CenterPolicy.fallback.isFallback, isTrue);
    });

    test('직접 만든 정책은 폴백이 아니다 — 기본값이 반대로 서면 안 된다', () {
      const fromServer = CenterPolicy(
        slotCapacity: 3,
        cancelCutoffHours: 48,
        graceOnce: true,
        penaltyRate: 10,
        expiringDays: 7,
        maxHoldsPerPass: 2,
        maxHoldTotalDays: 30,
      );
      expect(fromServer.isFallback, isFalse);
    });
  });
}
