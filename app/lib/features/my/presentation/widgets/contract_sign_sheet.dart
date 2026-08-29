import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/config/legal_links.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/my/domain/ledger_summary.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// 계약 서명 시트 — status=sent 계약의 요약(상품·금액·발송일)을 보여주고
/// 동의 체크 후 자체서명한다(POST /v1/contracts/{id}/sign, v1.4 P27).
/// 예약 확정·일시정지 시트와 같은 패턴: 제출 중 표시·이중 탭 방지·에러 인라인.
Future<void> showContractSignSheet(BuildContext context, {required ContractItem contract}) {
  return showModalBottomSheet<void>(
    context: context,
    // 루트 Navigator에 띄운다 — 기본값(false)이면 셸 내부 Navigator에 올라가
    // **하단 탭바가 시트와 스크림 위에 남는다**(실기기 점검에서 발견, P09).
    // 모달이 뜬 채로 다른 탭을 누를 수 있어 확정 전 화면을 벗어나게 된다.
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _ContractSignSheet(contract: contract),
  );
}

class _ContractSignSheet extends ConsumerStatefulWidget {
  const _ContractSignSheet({required this.contract});
  final ContractItem contract;

  @override
  ConsumerState<_ContractSignSheet> createState() => _ContractSignSheetState();
}

class _ContractSignSheetState extends ConsumerState<_ContractSignSheet> {
  bool _agreed = false;
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final c = widget.contract;
    // 조회 실패해도 fallback(24h/10%)으로 떨어질 뿐 화면이 죽지 않는다.
    final policy = ref.watch(centerPolicyProvider).value ?? CenterPolicy.fallback;
    final rate = c.penaltyRate ?? policy.penaltyRate;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('계약 서명', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            '내용을 확인하고 서명하면 계약이 체결돼요 (서명 시각은 서버에 기록)',
            style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line, width: 1.5),
              // 원래 12 — 목업 근거 없는 일회성이라 card(14)로 흡수했다(H3, 2px 변화).
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              children: [
                _SummaryRow('상품', c.product),
                // "결제 금액"이 아니라 **계약가**다 — 분할로 내는 중이면 지금까지 낸 돈과
                // 다르고, 회차 단가·위약금은 이 값에서 나온다(어드민 v1.5 어휘와 통일).
                _SummaryRow('계약가', MoneyFormat.won(c.paidAmount)),
                // 위약금율은 **동의를 받기 전에 반드시 보여야 한다**. 종전엔 상품·금액·
                // 발송일 세 줄만 띄우고 "위 계약 내용을 확인했으며 동의합니다"를 받았다 —
                // 회원이 본 적 없는 조건에 동의시킨 셈이고, 방문판매법 제30조②(계약서
                // 교부)의 필수 기재사항이 빠진 상태다.
                //
                // 계약에 스냅샷이 있으면 그 값, 없으면(v1.5 이전 레거시) 현재 센터 정책 —
                // 서버 refundBasis가 정확히 그 순서로 고른다. 여기서 다른 값을 그리면
                // "계약서 30% / 실제 공제 10%"로 갈렸던 사고(policy.go Validate 주석)의
                // 재현이 된다.
                _SummaryRow('중도 해지 위약금', _penaltyLabel(rate)),
                _SummaryRow('발송일', c.sentAt == null ? '-' : DateFmt.isoDate(c.sentAt!)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.line.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '해지하면 이렇게 정산돼요',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                // 서버 RefundQuote와 같은 순서·같은 말. 문구가 계산과 갈리면
                // 회원은 환불액을 받고 나서야 조건을 알게 된다.
                Text(
                  // 기준액을 반드시 밝힌다. "위약금 10%"만 쓰면 회원은 **자기가 낸 돈의 10%**로
                  // 읽는데, 실제 기준은 계약가다(공정위 고시 제2019-9호 제2조2호 "총계약대금 =
                  // 지급하기로 한 금액" + 별표 "헬스·피트니스업 총계약대금의 10%"). 분할로 내는
                  // 중이면 두 값이 갈리고, 그때 회원이 처음 알게 되는 건 정산서에서다.
                  //
                  // 반대로 빼기 시작하는 돈은 **실제 낸 금액**이다(같은 고시 제5조① "사업자에게
                  // 지급한 계약대금에서"). 같은 고시가 두 자리에 다른 단어를 쓴다.
                  '환불액 = 지금까지 낸 금액 − 사용한 회차 금액 − 위약금\n'
                  '· 회차 단가 = 계약가 ${MoneyFormat.won(c.paidAmount)} ÷ 총 회차\n'
                  '· 위약금 = 계약가의 ${_penaltyLabel(rate)} (낸 금액이 아니라 계약가 기준이에요)\n'
                  '· 예약은 수업 ${policy.cancelCutoffHours}시간 전까지 무료로 취소할 수 있어요',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: _agreed,
            activeColor: AppColors.red,
            title: const Text(
              '위 계약 내용과 이용약관을 확인했으며 동의합니다',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            onChanged: _submitting ? null : (v) => setState(() => _agreed = v ?? false),
          ),
          // 전문은 웹으로 — 앱에 박으면 개정할 때마다 스토어 심사를 다시 통과해야 한다
          // (P26 LegalLinksCard와 같은 이유).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openTerms,
            child: const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '이용약관 전문 보기',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.red,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
            ),
          RiseButton(
            label: _submitting ? '서명 중…' : '서명하기',
            expand: true,
            onPressed: (_agreed && !_submitting) ? _submit : null,
          ),
        ],
      ),
    );
  }

  /// 소수 자리를 억지로 붙이지 않는다 — "10%"를 "10.0%"로 쓰면 정밀해 보일 뿐이다.
  String _penaltyLabel(double rate) {
    final pct = rate * 100;
    return '${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}%';
  }

  Future<void> _openTerms() async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(LegalLinks.terms), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        riseSnackBar('브라우저를 열지 못했어요 — 주소: ${LegalLinks.terms}', kind: RiseSnackKind.danger),
      );
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref.read(myViewModelProvider.notifier).signContract(widget.contract.id);
    if (!mounted) return;
    switch (result) {
      case Ok():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(riseSnackBar('서명 완료', kind: RiseSnackKind.ok));
      case Err(:final failure):
        // 4xx 거부(RejectedFailure)는 이미 서명됨/무효화 등 서버와 목록이 어긋난
        // 경우가 대부분 — 목록을 재동기화해 낡은 '서명 대기' 행이 반복 에러를
        // 만들지 않게 한다(네트워크 실패는 목록이 낡은 게 아니므로 제외).
        if (failure is RejectedFailure) {
          ref.read(myViewModelProvider.notifier).refresh();
        }
        setState(() {
          _submitting = false;
          _error = failure.message;
        });
    }
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
