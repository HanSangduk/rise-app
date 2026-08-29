import 'package:flutter/material.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

/// 목업 "계약 · 동의" 카드.
/// v1.4: status=sent 계약 행은 탭 → 서명 시트(회원 자체서명 P27),
/// signed 행은 서명일 표시, draft 행은 비활성(관리자 발송 대기 안내).
class ContractsRow extends StatelessWidget {
  const ContractsRow({
    super.key,
    required this.contracts,
    required this.consent,
    required this.onConsentTap,
    required this.onSignTap,
    required this.onDetailTap,
    this.contractsFailed = false,
    this.consentFailed = false,
    this.refundedPassIds = const {},
  });

  final List<ContractItem> contracts;
  final ConsentState consent;
  final VoidCallback onConsentTap;

  /// status=sent 계약 행 탭 → 서명 시트 열기.
  final ValueChanged<ContractItem> onSignTap;

  /// 그 외 모든 행 탭 → 읽기 전용 상세. 서명한 계약을 다시 못 보는 게 종전 결함이었다.
  final ValueChanged<ContractItem> onDetailTap;

  /// 환불된(status=refunded) 패스 id들 — 그 패스의 계약은 서명이 서버에서 400이다
  /// (`api/service.go` SignContract: "환불 처리된 거래의 계약은 서명할 수 없어요").
  ///
  /// 보통 `RefundPass`가 미서명 계약을 voided로 함께 넘기지만, 그 단계는 환불 처리의
  /// **뒤쪽**에 있어 중간 실패 시 "패스는 refunded인데 계약은 sent"가 남는다. 그때
  /// 목록만 보면 멀쩡한 '서명 대기' 행이라 탭 → 시트 → 서명 → 400까지 간다.
  final Set<String> refundedPassIds;

  /// 계약 목록 조회 실패 — 빈 목록(계약 없음)과 구분해 상단에 1줄 안내.
  final bool contractsFailed;

  /// 동의 상태 조회 실패 — [consent]가 기본값(미동의)이라는 뜻이다. 배지를
  /// "동의 필요"로 두면 **실제로 동의한 회원에게 미동의라고 거짓말**을 하고,
  /// 그 상태로 시트를 열어 저장하면 서버 동의가 철회된다(consent_toggles 주석).
  final bool consentFailed;

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseCardHeader(title: '계약 · 동의'),
          // 부분 실패를 "계약 없음"으로 위장하지 않는다 — 실패는 실패라고 말한다.
          if (contractsFailed)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '계약 목록을 불러오지 못했어요 — 아래로 당겨 새로고침해주세요',
                style: TextStyle(fontSize: 11, color: AppColors.danger, height: 1.4),
              ),
            ),
          for (final c in contracts) _contractRow(c),
          InkWell(
            onTap: onConsentTap,
            child: RiseRow(
              showDivider: false,
              minHeight: 44,
              child: const Text('민감정보(인바디·체형사진) 동의'),
              // "모름"은 세 번째 상태다 — 동의함/동의 필요 어느 쪽으로도 기울이지
              // 않는다. 행은 그대로 열리되 시트가 읽기 전용으로 뜬다.
              trailing: consentFailed
                  ? const RiseBadge('확인 실패', variant: RiseBadgeVariant.danger)
                  : RiseBadge(
                      consent.sensitive ? '동의함 · 철회 가능' : '동의 필요',
                      variant: consent.sensitive ? RiseBadgeVariant.ok : RiseBadgeVariant.warn,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 이 계약을 지금 서명할 수 있는가 — 서버 `SignContract`가 통과시킬 조건 그대로.
  /// ① sent만 signed로 전이한다(`domain.CanTransitionContract`) ② 패스가 환불됐으면 거부.
  bool _signable(ContractItem c) => c.status == 'sent' && !refundedPassIds.contains(c.passId);

  Widget _contractRow(ContractItem c) {
    // 모든 행이 탭 가능하다 — 서명 가능하면 서명 시트, 아니면 읽기 전용 상세.
    // 종전엔 sent만 열려서 **서명하는 순간 계약을 다시 볼 길이 사라졌다**.
    final signable = _signable(c);
    final row = RiseRow(
      minHeight: 44,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${c.product} 계약'),
          if (_subtitle(c) case final sub?)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusBadge(c),
          const SizedBox(width: 4),
          const RiseIcon(RiseIcons.chevronRight, size: 14, color: AppColors.muted),
        ],
      ),
    );

    // 서명 가능한 행만 **서명 시트**로 간다 — draft는 발송 대기, voided(v1.5)는 종단
    // 상태(서명·발송 서버 400), 환불된 패스의 sent 계약도 서명이 400이다
    // ([refundedPassIds] 주석). 그 행들도 열리긴 하되 서명 버튼 없는 상세로 간다.
    return InkWell(
      onTap: () => signable ? onSignTap(c) : onDetailTap(c),
      child: row,
    );
  }

  String? _subtitle(ContractItem c) {
    // 상태는 'sent'인데 거래가 환불됐다면 "탭해서 서명"은 거짓말이다 —
    // 서버가 그 서명을 400으로 막는다. 상태 배지는 서버가 준 값 그대로 두고
    // (없는 상태를 지어내지 않는다) 왜 못 누르는지만 한 줄로 말한다.
    if (c.status == 'sent' && refundedPassIds.contains(c.passId)) {
      return '환불 처리된 거래예요 — 서명할 수 없어요';
    }
    return switch (c.status) {
      'sent' => '탭해서 내용 확인 후 서명할 수 있어요',
      'signed' => c.signedAt == null
          ? '탭해서 계약 내용을 볼 수 있어요'
          : '서명일 ${DateFmt.isoDate(c.signedAt!)} · 탭해서 내용 보기',
      'draft' => '센터에서 발송하면 서명할 수 있어요',
      'voided' => '환불로 무효 처리된 계약이에요',
      _ => null,
    };
  }

  /// Contract.status(draft|sent|signed|voided) → 상태 배지. 미지 status는 기존 폴백 유지.
  Widget _statusBadge(ContractItem c) => switch (c.status) {
        'signed' => RiseBadge(
            c.pdfPath == null ? '서명 완료' : '서명 완료 · PDF',
            variant: RiseBadgeVariant.ok,
          ),
        'sent' => const RiseBadge('서명 대기', variant: RiseBadgeVariant.warn),
        'draft' => const RiseBadge('작성 중', variant: RiseBadgeVariant.muted),
        'voided' => const RiseBadge('무효(환불)', variant: RiseBadgeVariant.muted),
        _ => RiseBadge(c.statusLabel, variant: RiseBadgeVariant.muted),
      };
}
