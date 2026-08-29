// 회원의 결제 내역(P26).
//
// 서버는 `GET /v1/payments?member=`로 본인 분할 내역을 그대로 내려주는데 앱에 그리는
// 화면이 하나도 없었다 — 분할로 결제한 회원이 "2차가 언제 얼마인지"를 확인하려면
// 센터에 물어보는 수밖에 없었다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/widgets/payments_card.dart';

void main() {
  InstallmentItem inst(int amount, String due, {DateTime? paid, DateTime? waived}) =>
      InstallmentItem(due: due, amount: amount, paidAt: paid, waivedAt: waived);

  PaymentItem split({List<InstallmentItem>? items}) => PaymentItem(
        id: 'pay1',
        passId: 'p1',
        method: 'card',
        total: 1200000,
        installments: items ??
            [
              inst(600000, '2026-08-01', paid: DateTime(2026, 8, 1)),
              inst(600000, '2026-09-01'),
            ],
      );

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
      );

  group('미납 합계', () {
    test('서버 Outstanding()과 같은 규칙 — 미납이고 종결되지 않은 회차만', () {
      expect(split().outstanding, 600000);
    });

    test('청구 종결(환불)은 미납이 아니다 — 이미 환불받은 회원에게 낼 돈이 있다고 하면 안 된다', () {
      final p = split(items: [
        inst(600000, '2026-08-01', paid: DateTime(2026, 8, 1)),
        inst(600000, '2026-09-01', waived: DateTime(2026, 8, 20)),
      ]);
      expect(p.outstanding, 0);
    });

    testWidgets('미납이 있으면 카드 상단에 금액을 말한다', (tester) async {
      await pump(tester, PaymentsCard(payments: [split()]));
      expect(find.textContaining('아직 낼 금액'), findsOneWidget);
      expect(find.textContaining('600,000원'), findsWidgets);
    });

    testWidgets('완납이면 미납 줄을 띄우지 않는다', (tester) async {
      final p = split(items: [
        inst(600000, '2026-08-01', paid: DateTime(2026, 8, 1)),
        inst(600000, '2026-09-01', paid: DateTime(2026, 9, 1)),
      ]);
      await pump(tester, PaymentsCard(payments: [p]));
      expect(find.textContaining('아직 낼 금액'), findsNothing);
    });
  });

  group('회차 표시', () {
    testWidgets('분할이면 회차별 금액·예정일·상태가 보인다', (tester) async {
      await pump(tester, PaymentsCard(payments: [split()]));

      expect(find.textContaining('1차'), findsOneWidget);
      expect(find.textContaining('2차'), findsOneWidget);
      expect(find.text('납부 완료'), findsOneWidget);
      expect(find.text('납부 예정'), findsOneWidget);
      expect(find.textContaining('납부 예정일 2026-09-01'), findsOneWidget);
    });

    testWidgets('한 번에 낸 결제는 회차를 펼치지 않는다', (tester) async {
      final lump = PaymentItem(
        id: 'pay2',
        passId: 'p1',
        method: 'cash',
        total: 700000,
        installments: [inst(700000, '2026-08-01', paid: DateTime(2026, 8, 1))],
      );
      await pump(tester, PaymentsCard(payments: [lump]));

      expect(find.text('현금 결제'), findsOneWidget);
      expect(find.textContaining('1차'), findsNothing);
    });
  });

  group('빈 상태와 실패는 다르다', () {
    testWidgets('결제가 없으면 카드를 아예 띄우지 않는다', (tester) async {
      await pump(tester, const PaymentsCard(payments: []));
      expect(find.text('결제 내역'), findsNothing);
    });

    testWidgets('조회 실패는 "결제 없음"으로 위장하지 않는다', (tester) async {
      // 미납이 있는 회원에게 없다고 말하는 건 그냥 거짓말이다.
      await pump(tester, const PaymentsCard(payments: [], failed: true));
      expect(find.text('결제 내역'), findsOneWidget);
      expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    });
  });

  group('모르는 결제수단', () {
    test('wire 값 그대로 폴백 — 새 수단이 생겨도 행이 깨지지 않는다', () {
      const p = PaymentItem(
        id: 'x', passId: 'p', method: 'kakaopay', total: 1000, installments: [],
      );
      expect(p.methodLabel, 'kakaopay');
    });
  });

  group('좁은 폭', () {
    testWidgets('360dp에서 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pump(tester, PaymentsCard(payments: [split()]));
      expect(tester.takeException(), isNull);
    });
  });
}
