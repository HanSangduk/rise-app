import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/my/domain/ledger_summary.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

// 순수 도메인 — 원장 합계 골든(과제 지시): 화면에 보이는 -2 + 이전 11건(-11) +
// 최초 발급 +20 = 잔여 7/20. (환불 견적 계산은 P39에서 회원 앱과 함께 제거 —
// 어드민 + 서버 refund-quote가 담당한다.)
void main() {
  group('ledgerRemaining — 원장 합계 = 잔여 회차', () {
    test('발급 +20, 이전 11회 사용, 화면에 보이는 2회 사용 → 잔여 7', () {
      final entries = <LedgerEntry>[
        LedgerEntry(id: 'l0', passId: 'p1', delta: 20, reason: LedgerReason.issue, at: DateTime(2026, 6, 2)),
        for (var i = 0; i < 11; i++)
          LedgerEntry(
            id: 'prior-$i',
            passId: 'p1',
            delta: -1,
            reason: LedgerReason.complete,
            at: DateTime(2026, 6, 3 + i),
          ),
        LedgerEntry(id: 'l1', passId: 'p1', delta: -1, reason: LedgerReason.complete, at: DateTime(2026, 8, 8)),
        LedgerEntry(id: 'l2', passId: 'p1', delta: -1, reason: LedgerReason.complete, at: DateTime(2026, 8, 12)),
      ];

      expect(entries.length, 14); // 1(발급) + 11(이전) + 2(화면 표시)
      expect(ledgerRemaining(entries), 7);
    });

    test('노쇼 유예(delta 0)는 잔여에 영향 없음', () {
      final entries = [
        LedgerEntry(id: 'l0', passId: 'p1', delta: 20, reason: LedgerReason.issue, at: DateTime(2026, 6, 2)),
        LedgerEntry(id: 'l1', passId: 'p1', delta: 0, reason: LedgerReason.noshowWaived, at: DateTime(2026, 8, 1)),
      ];
      expect(ledgerRemaining(entries), 20);
    });

    test('빈 원장이면 잔여 0', () {
      expect(ledgerRemaining(const []), 0);
    });
  });

  group('MoneyFormat.won', () {
    test('550000 → "550,000원"', () {
      expect(MoneyFormat.won(550000), '550,000원');
    });

    test('1000000 → "1,000,000원"', () {
      expect(MoneyFormat.won(1000000), '1,000,000원');
    });

    test('0 → "0원"', () {
      expect(MoneyFormat.won(0), '0원');
    });

    test('세 자리 이하는 콤마 없이', () {
      expect(MoneyFormat.won(500), '500원');
    });
  });
}
