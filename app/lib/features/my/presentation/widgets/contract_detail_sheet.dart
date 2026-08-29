import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/features/my/domain/ledger_summary.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

/// 계약 상세 열람.
///
/// 종전에는 **서명한 순간 계약을 다시 볼 길이 사라졌다** — `sent` 행만 서명 시트로
/// 열리고 `signed`/`draft`/`voided`는 배지만 있는 죽은 행이었다. 회원이 얼마를 내고
/// 무엇에 동의했는지 나중에 확인할 수 없는 건, 돈이 오간 계약에서는 그냥 결함이다.
///
/// **없는 걸 있는 척하지 않는다.** 서버 Contract는 지금 상태·메타데이터만 들고 있고
/// 계약 본문 PDF(`pdf_path`)는 연동 전이라 늘 비어 있다(domain/contract.go 주석).
/// 그래서 가진 값(상품·금액·위약금율·발송일·서명일)은 다 보여주되, 본문이 없다는
/// 사실도 숨기지 않고 적는다 — "PDF 보기" 같은 눌러도 안 되는 버튼을 만드느니 낫다.
Future<void> showContractDetailSheet(
  BuildContext context, {
  required ContractItem contract,
  double? penaltyRate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // 서명 시트와 같은 이유로 루트 Navigator에 띄운다 — 셸 Navigator에 올리면
    // 하단 탭바가 스크림 위에 남는다(contract_sign_sheet 주석, P09).
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _ContractDetailSheet(contract: contract, penaltyRate: penaltyRate),
  );
}

class _ContractDetailSheet extends StatelessWidget {
  const _ContractDetailSheet({required this.contract, this.penaltyRate});

  final ContractItem contract;

  /// 계약 생성 시점에 스냅샷된 위약금율(0~1). 서버가 안 내려주면 null —
  /// 그때는 **행을 아예 빼서** 0%로 오해하게 만들지 않는다.
  final double? penaltyRate;

  @override
  Widget build(BuildContext context) {
    final c = contract;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${c.product} 계약',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _headline(c),
              style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line, width: 1.5),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                children: [
                  _Row('상품', c.product),
                  // 분할로 내는 중이면 지금까지 낸 돈과 다르다 — 회차 단가·위약금의 기준값이다.
                  _Row('계약가', MoneyFormat.won(c.paidAmount)),
                  _Row('상태', c.statusLabel),
                  if (penaltyRate != null)
                    _Row('위약금율(계약가 기준)', '${(penaltyRate! * 100).toStringAsFixed(penaltyRate! * 100 % 1 == 0 ? 0 : 1)}%'),
                  if (c.sentAt != null) _Row('발송일', DateFmt.isoDate(c.sentAt!)),
                  if (c.signedAt != null) _Row('서명일', DateFmt.isoDate(c.signedAt!)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.line.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Text(
                c.pdfPath == null
                    ? '계약서 원본 파일은 아직 앱에 올라와 있지 않아요 — 센터에 요청하면 보내드려요.'
                    : '계약서 원본이 센터에 보관돼 있어요 — 사본이 필요하면 센터에 요청해주세요.',
                style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
            RiseButton(
              label: '닫기',
              style: RiseButtonStyleKind.outline,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  String _headline(ContractItem c) => switch (c.status) {
        'signed' => c.signedAt == null
            ? '서명이 완료된 계약이에요'
            : '${DateFmt.isoDate(c.signedAt!)}에 서명한 계약이에요',
        'draft' => '센터가 작성 중이에요 — 발송되면 서명할 수 있어요',
        'voided' => '환불로 무효 처리된 계약이에요',
        _ => '계약 내용이에요',
      };
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
