// 홈의 막다른 길(P30).
//
// 예약이 없을 때 카드가 "예약 탭에서 잡아보세요"라고 **말만 하고 버튼이 없었다**.
// 프로덕션 회원 상태를 재보니 예약 0건 · 결제 0건 · 수업기록 0건 — 대표가 "홈이
// 허전하다"고 본 화면이 바로 이 상태다. 회원이 가장 자주 만나는 상태가 막다른 길이었다.
//
// 경쟁 제품 4종(Trainerize · TrueCoach · Everfit · PT Distinction) 조사에서도 홈에
// 예약 진입점을 둔 곳이 없었다 — Trainerize는 로깅과 섞인 "+" FAB, Everfit은
// Coaching → Sessions → View all 두 단계 아래, 나머지 둘은 회원 예약 자체가 없다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/widgets/next_booking_card.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    NextBooking? booking, {
    double width = 360,
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              child: NextBookingCard(
                booking: booking,
                cutoffHours: 24,
                onCheckIn: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('예약이 없을 때', () {
    testWidgets('데려다주는 버튼이 있다 — 말만 하고 끝내지 않는다', (tester) async {
      await pump(tester, null);

      expect(find.text('예약하러 가기'), findsOneWidget);
      final btn = tester.widget<RiseButton>(find.byType(RiseButton));
      expect(btn.onPressed, isNotNull, reason: '눌러도 아무 일 없는 버튼은 막다른 길과 같다');
    });

    testWidgets('범위를 여전히 밝힌다 — "없어요"만 말하면 전부 없다고 읽힌다', (tester) async {
      // 이 카드는 선택된 회원권의 담당 코치 예약만 본다. 회원권이 둘 이상이면
      // 다른 코치 수업이 더 빨라도 여기엔 안 뜬다.
      await pump(tester, null);
      expect(find.textContaining('이 회원권 담당 코치로'), findsOneWidget);
    });

    testWidgets('좁은 폭 · 큰 글씨에서 넘치지 않는다', (tester) async {
      await pump(tester, null, width: 320, scale: 1.35);
      expect(tester.takeException(), isNull);
      expect(find.text('예약하러 가기'), findsOneWidget);
    });
  });

  group('예약이 있을 때', () {
    testWidgets('예약하러 가기 버튼을 띄우지 않는다 — 이미 잡혀 있다', (tester) async {
      await pump(
        tester,
        NextBooking(
          id: 'b1',
          startAt: DateTime.now().add(const Duration(days: 1)),
          kind: 'pt',
          trainerName: '정혜린',
        ),
      );
      expect(find.text('예약하러 가기'), findsNothing);
    });
  });
}
