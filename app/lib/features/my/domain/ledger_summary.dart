import 'package:rise_member/features/my/domain/my_models.dart';

/// 순수 함수 — 원장 합계 · 금액 표시 포맷팅. Flutter/외부 의존 0(유닛 테스트 대상).
///
/// 환불 견적(RefundQuote/RefundCalculator)은 P39에서 제거 — 회원 앱은 환불
/// 예상액을 보여주지 않는다(어드민 RefundQuoteModal + 서버
/// `POST /v1/passes/{id}/refund-quote`가 담당, my_screen.dart 주석 참조).

/// 원장 delta 합 = 잔여 회차. (발급 +N, 완료 -1, 노쇼유예 0 등)
int ledgerRemaining(List<LedgerEntry> entries) =>
    entries.fold(0, (sum, e) => sum + e.delta);

abstract final class MoneyFormat {
  /// 1000000 → "1,000,000원".
  static String won(int amount) {
    final digits = amount.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${amount < 0 ? '-' : ''}$buffer원';
  }
}
