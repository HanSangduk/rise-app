import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';

/// 회원탈퇴 확인 화면(API계약 v2.11 · App Store Guideline 5.1.1(v)).
///
/// **다이얼로그가 아니라 전체 화면인 이유**: 이 결정은 되돌릴 수 없고, 회원이 읽어야 할 것이
/// 두 문단이 아니라 두 목록이다(무엇이 지워지는지 / 무엇이 왜 남는지). 다이얼로그에 넣으면
/// 스크롤되는 경고문이 되고, 스크롤되는 경고문은 읽히지 않는다.
///
/// 확인은 **두 겹**이다: 화면의 체크박스로 "읽었다"를, 마지막 다이얼로그로 "실행한다"를
/// 따로 받는다. 이 저장소의 파괴적 동작 규약(consent_toggles·inbody 삭제)이 "화면이 먼저
/// 결과를 예고하고 다이얼로그는 재확인"이라, 탈퇴는 그중 가장 무거운 쪽에 맞춘다.
///
/// 라우트가 아니라 `Navigator.push`인 이유는 QrScanScreen과 같다 — 탭 셸 밖의 일회성 화면이라
/// 딥링크로 들어올 자리가 없고, 오히려 링크가 생기면 안 되는 화면이다.
class AccountDeletionScreen extends ConsumerStatefulWidget {
  const AccountDeletionScreen({super.key});

  @override
  ConsumerState<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends ConsumerState<AccountDeletionScreen> {
  bool _acknowledged = false;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    // 잔여 회차는 **서버가 준 값**만 쓴다(마이 탭이 이미 받아 둔 요약). 못 읽었으면 숫자를
    // 지어내지 않고 그 사실을 말한다 — 이 저장소의 "모르는 것을 아는 것처럼 말하지 않는다"
    // 규약(v2.1 3상태 규약과 같은 근거).
    final summary = ref.watch(myViewModelProvider).asData?.value;

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(title: const Text('회원탈퇴')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          children: [
            const _WarningBox(),
            // 조회에 실패했으면 **모른다고 말한다.** 상자를 그냥 빼면 "남은 회차 없음"과
            // 구별되지 않고, 회원은 정산할 게 있다는 사실을 되돌릴 수 없게 된 뒤에야 안다
            // (계약 v2.1의 3상태 규약 — 값 있음 / 없음 / 미상을 뭉개지 않는다).
            if (summary != null) _RemainingBox(summary: summary) else const _RemainingUnknownBox(),
            const _PurgedCard(),
            const _RetainedCard(),
            const SizedBox(height: 4),
            _AcknowledgeRow(
              value: _acknowledged,
              onChanged: _submitting ? null : (v) => setState(() => _acknowledged = v),
            ),
            const SizedBox(height: 10),
            RiseButton(
              label: _submitting ? '처리 중…' : '탈퇴하기',
              expand: true,
              // 이중 잠금: 체크 전에는 버튼이 잠기고, 눌린 뒤에도 _submit이 다시 확인한다
              // (이 저장소의 파괴적 동작 규약 — 비활성 버튼만 믿지 않는다).
              onPressed: (_acknowledged && !_submitting) ? _submit : null,
            ),
            const SizedBox(height: 8),
            RiseButton(
              label: '돌아가기',
              expand: true,
              style: RiseButtonStyleKind.outline,
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_acknowledged || _submitting) return; // 이중 잠금
    if (!await _confirm()) return;
    if (!mounted) return;

    setState(() => _submitting = true);
    final result = await ref.read(myViewModelProvider.notifier).deleteAccount();
    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        // 성공 뒤에는 이 계정으로 아무것도 부를 수 없다 — 세션을 정리하고 즉시 로그인으로.
        // 스낵바 메신저는 화면이 사라지기 **전에** 잡아 둔다(hold_request_sheet와 같은 순서).
        final messenger = ScaffoldMessenger.of(context);
        await _signOut();
        if (!mounted) return;
        context.go('/login');
        messenger.showSnackBar(riseSnackBar(value.completionMessage));
      case Err(:final failure):
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(riseSnackBar(failure.message, kind: RiseSnackKind.danger));
    }
  }

  /// 마지막 재확인. 여기서 처음 알리는 사실은 하나도 없다 — 화면이 이미 전부 말했고,
  /// 이 다이얼로그는 "지금 실행한다"만 묻는다.
  Future<bool> _confirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('정말 탈퇴할까요?'),
        content: const Text(
          '탈퇴하면 되돌릴 수 없어요.\n\n'
          '체형사진·인바디·수업 기록이 모두 삭제되고, 같은 번호로 다시 가입해도 복구되지 않아요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('그대로 두기'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('탈퇴하기'),
          ),
        ],
      ),
    );
    return confirmed ?? false; // 배리어 탭 = 취소
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // dev 헤더 모드·Firebase 미초기화여도 로컬 세션은 반드시 정리한다(_logout과 같은 관용).
    }
    ref.read(sessionProvider.notifier).clear();
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.badgeDanBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: const Text(
        '탈퇴하면 되돌릴 수 없어요.\n같은 번호로 다시 가입해도 이전 기록은 복구되지 않아요.',
        style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.badgeDanFg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 남은 회차 고지. 서버는 잔여가 있어도 탈퇴를 막지 않으므로(Guideline 5.1.1(v)),
/// **막는 대신 알린다** — 회원이 탈퇴 전에 정산할 기회를 갖는 유일한 지점이다.
class _RemainingBox extends StatelessWidget {
  const _RemainingBox({required this.summary});
  final MySummary summary;

  @override
  Widget build(BuildContext context) {
    final remaining = summary.passes
        .where((p) => p.isActive || p.isScheduled)
        .fold<int>(0, (sum, p) => sum + p.remaining);
    if (remaining <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.badgeWarnBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warn.withValues(alpha: 0.35)),
      ),
      child: Text(
        '아직 $remaining회가 남아 있어요.\n'
        '탈퇴해도 자동으로 환불되지 않아요 — 정산은 센터와 따로 진행해야 해요.',
        style: const TextStyle(
          fontSize: 12,
          height: 1.6,
          color: AppColors.badgeWarnFg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 회원권 조회에 실패했을 때. **원인을 지목하지 않는다** — "남은 회차가 없어요"라고 말하면
/// 모르는 것을 아는 것처럼 말하게 되고, 그게 이 화면에서 가장 비싼 거짓말이다.
class _RemainingUnknownBox extends StatelessWidget {
  const _RemainingUnknownBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.badgeMutBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: const Text(
        '남은 회차를 확인하지 못했어요.\n'
        '남은 회차가 있다면 탈퇴해도 자동으로 환불되지 않아요 — 먼저 센터에 확인해주세요.',
        style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.badgeMutFg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PurgedCard extends StatelessWidget {
  const _PurgedCard();

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseCardHeader(title: '삭제되는 정보'),
          for (var i = 0; i < withdrawalPurgedItems.length; i++)
            RiseRow(
              showDivider: i != withdrawalPurgedItems.length - 1,
              child: Text(withdrawalPurgedItems[i], style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _RetainedCard extends StatelessWidget {
  const _RetainedCard();

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseCardHeader(title: '법에 따라 보관되는 정보'),
          for (var i = 0; i < withdrawalRetainedItems.length; i++)
            RiseRow(
              showDivider: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(withdrawalRetainedItems[i].item, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                    withdrawalRetainedItems[i].reason,
                    style: const TextStyle(fontSize: 10, height: 1.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 9),
            child: Text(
              withdrawalRetentionNote,
              style: TextStyle(fontSize: 10, height: 1.6, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _AcknowledgeRow extends StatelessWidget {
  const _AcknowledgeRow({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: value,
                activeColor: AppColors.red,
                onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
              ),
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '위 내용을 모두 확인했고, 탈퇴에 동의해요',
                style: TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
