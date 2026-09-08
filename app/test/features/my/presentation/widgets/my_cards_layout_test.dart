// 마이 탭 신규 카드의 레이아웃 회귀(P29).
//
// 두 축에서만 터진다: **좁은 폭(360dp 실기기)** 과 **글꼴 배율 상한(1.35 —
// app.dart가 클램프하는 최대치)**. 기본 테스트 화면은 800dp·배율 1.0이라 둘 다 못 잡는다.
//
// 탭 타깃 44dp는 별개 축이다 — 넘치지 않는다고 누를 수 있는 건 아니다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/theme/app_theme.dart';

import '../../../../support/font_loader.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/widgets/legal_links_card.dart';
import 'package:rise_member/features/my/presentation/widgets/payments_card.dart';

void main() {
  // **번들 폰트를 실제로 로드한다.** 폴백 폰트는 줄높이가 달라 실기기에서만 나는
  // 1px 오버플로를 재현하지 못한다(app_shell_overflow_test가 같은 이유로 그렇게 한다).
  setUpAll(loadPretendard);

  final payments = [
    PaymentItem(
      id: 'pay1',
      passId: 'p1',
      method: 'card',
      total: 1200000,
      installments: [
        InstallmentItem(due: '2026-08-01', amount: 600000, paidAt: DateTime(2026, 8, 1)),
        const InstallmentItem(due: '2026-09-01', amount: 600000),
      ],
    ),
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 360,
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // ProviderScope — 약관 카드가 세션에서 센터를 읽어 법정 문서 URL에 싣는다(v2.33).
    // 이 스위트는 레이아웃만 보므로 오버라이드 없이 기본 세션(null)이면 충분하다.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );
  }

  group('좁은 폭 · 큰 글씨에서 넘치지 않는다', () {
    for (final scale in [1.0, 1.35]) {
      testWidgets('약관 카드 — 360dp · 배율 $scale', (tester) async {
        await pump(tester, const LegalLinksCard(), scale: scale);
        expect(tester.takeException(), isNull);
      });

      testWidgets('결제 카드 — 360dp · 배율 $scale', (tester) async {
        await pump(tester, PaymentsCard(payments: payments), scale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('탭 타깃', () {
    testWidgets('약관 5행 모두 44dp — 넘치지 않는 것과 누를 수 있는 것은 다른 문제다', (tester) async {
      await pump(tester, const LegalLinksCard());

      for (final label in const [
        '앱 개인정보처리방침 (운영자)',
        '이용약관',
        '개인정보처리방침 (센터)',
        '민감정보(인바디·체형사진) 처리 안내',
        '계정·데이터 삭제 안내',
      ]) {
        final row = find.ancestor(
          of: find.text(label),
          matching: find.byType(GestureDetector),
        );
        expect(row, findsWidgets, reason: '$label 행이 탭 대상이 아니다');
        expect(
          tester.getSize(row.first).height,
          greaterThanOrEqualTo(44),
          reason: '$label 행이 44dp 미만',
        );
      }
    });
  });

  group('카드 사이 리듬', () {
    testWidgets('두 카드 모두 RiseCard 기본 margin을 쓴다 — 한 장만 달라지면 리듬이 깨진다', (tester) async {
      // **인접한 위젯 rect 사이 간격을 재면 안 된다**: RiseCard의 margin은 그 위젯
      // 자신의 rect 안에 들어가므로 margin을 얼마로 바꾸든 두 rect는 항상 맞붙는다
      // (실제로 뮤테이션에서 그 테스트가 살아남았다 — 아무것도 검증하지 못했다).
      // 불변식 자체를 직접 단언한다.
      await pump(
        tester,
        Column(children: [PaymentsCard(payments: payments), const LegalLinksCard()]),
      );
      expect(tester.takeException(), isNull);

      final cards = tester.widgetList<RiseCard>(find.byType(RiseCard)).toList();
      expect(cards.length, greaterThanOrEqualTo(2));
      for (final c in cards) {
        expect(c.margin, const EdgeInsets.only(bottom: 10),
            reason: '카드마다 margin이 다르면 세로 리듬이 어긋난다');
      }
    });
  });
}
