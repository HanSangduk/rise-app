import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/features/my/domain/ledger_summary.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

/// 결제 내역 카드(P26).
///
/// 서버는 `GET /v1/payments?member=`로 본인 분할 내역을 그대로 내려주는데 **앱에 그리는
/// 화면이 하나도 없었다**. 분할로 결제한 회원이 "2차가 언제 얼마인지", "아직 얼마가
/// 남았는지"를 확인하려면 센터에 물어보는 수밖에 없었다.
///
/// 미납 합계는 서버 `Payment.Outstanding()`과 **같은 규칙**으로 센다(미납이고 종결되지
/// 않은 회차). 두 값이 갈리면 앱은 "미납 30만원"이라 하고 데스크는 "완납"이라 한다.
class PaymentsCard extends StatelessWidget {
  const PaymentsCard({
    super.key,
    required this.payments,
    this.failed = false,
  });

  final List<PaymentItem> payments;

  /// 조회 실패 — 빈 목록("결제 없음")과 구분한다. 미납이 있는 회원에게 없다고
  /// 말하는 건 그냥 거짓말이다.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    // 실패도 아니고 결제도 없으면 카드 자체를 띄우지 않는다 — 아직 아무것도 안 산
    // 회원에게 빈 "결제 내역" 상자를 보여줄 이유가 없다.
    if (!failed && payments.isEmpty) return const SizedBox.shrink();

    final outstanding = payments.fold<int>(0, (sum, p) => sum + p.outstanding);

    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseCardHeader(title: '결제 내역'),
          if (failed)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '결제 내역을 불러오지 못했어요 — 아래로 당겨 새로고침해주세요',
                style: TextStyle(fontSize: 11, color: AppColors.danger, height: 1.4),
              ),
            ),
          if (outstanding > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '아직 낼 금액 ${MoneyFormat.won(outstanding)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.warn,
                ),
              ),
            ),
          for (final p in payments) _PaymentBlock(payment: p),
        ],
      ),
    );
  }
}

class _PaymentBlock extends StatelessWidget {
  const _PaymentBlock({required this.payment});
  final PaymentItem payment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RiseRow(
          showDivider: !payment.isLumpSum,
          child: Text('${payment.methodLabel} 결제'),
          trailing: Text(
            MoneyFormat.won(payment.total),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
        // 한 번에 낸 결제는 회차를 펼치지 않는다 — 총액과 같은 줄이 하나 더 생길 뿐이다.
        if (!payment.isLumpSum)
          for (var i = 0; i < payment.installments.length; i++)
            _InstallmentRow(
              index: i + 1,
              item: payment.installments[i],
              last: i == payment.installments.length - 1,
            ),
      ],
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  const _InstallmentRow({
    required this.index,
    required this.item,
    required this.last,
  });

  final int index;
  final InstallmentItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return RiseRow(
      showDivider: !last,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$index차 ${MoneyFormat.won(item.amount)}',
            style: const TextStyle(fontSize: 12),
          ),
          if (_dateLine(item) case final line?)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                line,
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
            ),
        ],
      ),
      trailing: RiseBadge(item.statusLabel, variant: _variant(item)),
    );
  }

  /// 회차 아래 한 줄.
  ///
  /// **납부가 끝났으면 `due`(예정일)가 아니라 `paidAt`(실제 낸 날)을 쓴다.** 종전엔
  /// 완납 회차에도 예정일을 "납부일"이라 찍어서, 늦게 낸 회원에게 **본 적 없는 날짜를
  /// 자기가 낸 날이라고** 말했다(예정 9/1 · 실제 9/14면 화면은 9/1).
  ///
  /// 청구 종결(환불)은 낸 것도 낼 것도 아니므로 예정일을 그대로 두되 **"예정일"이라고
  /// 부른다** — 배지가 이미 "청구 종결"을 말하고 있어 날짜의 뜻만 흐리지 않으면 된다.
  String? _dateLine(InstallmentItem i) {
    if (i.paidAt != null) return '납부일 ${DateFmt.isoDate(i.paidAt!)}';
    if (i.due.isEmpty) return null;
    if (i.waivedAt != null) return '예정일 ${i.due}';
    return '납부 예정일 ${i.due}';
  }

  /// 청구 종결(환불로 수납 중단)은 **미납이 아니다** — warn으로 칠하면 이미 환불받은
  /// 회원에게 낼 돈이 남은 것처럼 보인다.
  RiseBadgeVariant _variant(InstallmentItem i) {
    if (i.waivedAt != null) return RiseBadgeVariant.muted;
    if (i.paidAt != null) return RiseBadgeVariant.ok;
    return RiseBadgeVariant.warn;
  }
}
