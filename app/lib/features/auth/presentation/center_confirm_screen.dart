import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/config/app_config.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/theme/app_typography.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/core/widgets/trainer_avatar.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
import 'package:rise_member/features/booking/presentation/widgets/trainer_profile_sheet.dart';

/// 로그인 3단계 — 센터 자동 매칭 + 이름확인 1탭 (목업 step-center, P48).
/// "네, OO 본인이에요"가 핵심 CTA: 오타 번호로 남의 계정에 잘못 연결되는 걸
/// 막는 유일한 확인 장치이므로 이름을 크게 강조해서 보여준다.
///
/// CTA는 `member != null`이 아니라 [CenterConfirmStage]로 분기한다. 예전엔 CTA
/// 블록 전체가 member 게이트 안에 있어서, "본인이 아니에요"를 누르거나 가입 요청을
/// 보내는 순간 버튼과 링크가 통째로 사라졌다 — 이 화면은 AppBar도 뒤로가기도 없고
/// 라우터 스택이 1장이라(전부 context.go) 시스템 백은 앱을 종료한다. 즉 안내 문구만
/// 남은 막다른 길이었다. 그래서 **모든 상태에서 "다른 번호로 다시 시도"가 상시 노출**된다.
class CenterConfirmScreen extends ConsumerWidget {
  const CenterConfirmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authViewModelProvider);
    final member = state.match?.member;
    final stage = state.centerConfirmStage;
    // 담당 코치 아바타·직함(P05) — 인증 단계에서 이미 로드된 스태프 캐시를 재사용
    // (best-effort: 미로드/실패면 기존처럼 이름만 표시).
    final trainerId = member?.trainerId;
    final trainer =
        trainerId == null ? null : ref.watch(staffMapProvider).value?[trainerId];

    // 이 화면도 라우터 스택 1장 — 막지 않으면 시스템 백이 앱을 끈다. 백은 화면 내
    // 탈출구("다른 번호로 다시 시도")와 같은 목적지로 보내되, 인증을 통째로
    // 되돌리는 동작이라 오탭 한 번에 실행되지 않게 한 번 되묻는다.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmRestart(context, ref);
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 34, 20, 34),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '센터 선택',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  // 매칭에 실패했는데 "찾았어요"라고 말하지 않도록 상태별 안내.
                  switch (stage) {
                    CenterConfirmStage.matched => '전화번호로 등록된 센터를 찾았어요',
                    CenterConfirmStage.pendingApproval => '센터 승인을 기다리는 중이에요',
                    CenterConfirmStage.declined => '연결을 취소했어요. 아래에서 다시 선택해주세요',
                    CenterConfirmStage.connectionUnknown => '연결 상태를 확인하지 못했어요',
                    CenterConfirmStage.notFound => '이 번호로 등록된 센터를 찾지 못했어요',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                if (member != null)
                  _MatchedCenterCard(
                    memberName: member.name,
                    trainerName: state.trainerName,
                    trainer: trainer,
                  )
                else if (state.matchDeclined) const _DeclinedCard()
                else if (stage == CenterConfirmStage.connectionUnknown)
                  const _ConnectionUnknownCard()
                else const _NotFoundCard(),
                const SizedBox(height: 10),
                // 가입 요청을 이미 보냈으면 "승인 대기 중" 카드로 고정 — 중복 제출 방지,
                // "다시 요청"은 30초 카운트다운 후에만 활성.
                if (state.joinRequestedAt case final requestedAt?)
                  _PendingApprovalCard(
                    // 재요청 시각이 바뀌면 카운트다운을 새로 시작하도록 상태를 재생성.
                    key: ValueKey(requestedAt),
                    requestedAt: requestedAt,
                    busy: state.busy,
                    checking: state.checkingConnection,
                    onRetry: () => _showJoinRequestSheet(context),
                    onCheck: () => _check(context, ref),
                  )
                // 연결 여부를 모르는 상태에서는 가입 요청을 권하지 않는다 — 이미
                // 연결된 회원일 수 있고, 그 요청은 대표 화면에 중복 줄을 만든다.
                else if (stage != CenterConfirmStage.connectionUnknown)
                  _JoinOtherCenterCard(
                    onTap: state.busy ? null : () => _showJoinRequestSheet(context),
                  ),
                const Spacer(),
                if (state.error != null) ...[
                  Text(
                    state.error!.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
                  ),
                  const SizedBox(height: 8),
                ],
                _CtaBlock(
                  stage: stage,
                  memberName: member?.name,
                  busy: state.busy,
                  checking: state.checkingConnection,
                  onConfirm: (confirm) => _confirm(context, ref, confirm),
                  onRestart: () => _restart(context, ref),
                  onCheck: () => _check(context, ref),
                ),
                const SizedBox(height: 10),
                const Text(
                  '본인 확인은 잘못 연결 방지용이에요(오타 번호 보호). 한 계정으로 여러 센터 이용 가능 — 홈 상단에서 전환.',
                  textAlign: TextAlign.center,
                  style: AppTypography.note,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, bool confirm) async {
    final ok = await ref.read(authViewModelProvider.notifier).confirmMatch(confirm);
    if (ok && context.mounted) context.go('/home');
  }

  /// "연결됐는지 확인" — 대표 승인 여부를 읽기만 한다(가입 요청과 달리 대표 화면에
  /// 아무 줄도 더 쌓지 않는다). 실패해도 대기 상태는 그대로 유지된다.
  Future<void> _check(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(authViewModelProvider.notifier).checkConnection();
    if (!context.mounted) return;
    switch (result) {
      case ConnectionCheck.connected:
        context.go('/home');
      case ConnectionCheck.notYet:
        // 실패가 아니다 — 조회는 성공했고 답이 "아직"일 뿐이라 중립색.
        messenger.showSnackBar(riseSnackBar('아직 승인 전이에요. 승인되면 바로 연결돼요'));
      case ConnectionCheck.failed:
        break; // 사유는 화면 인라인 문구(state.error)로 이미 보인다.
    }
  }

  /// 상시 탈출구 — Firebase 로그아웃 + 플로우 상태 초기화 후 전화번호 입력으로.
  /// (라우터 redirect는 앱 시작 1회만 도는 래치라 이 이동과 충돌하지 않는다.)
  Future<void> _restart(BuildContext context, WidgetRef ref) async {
    await ref.read(authViewModelProvider.notifier).restartWithNewPhone();
    if (context.mounted) context.go('/login');
  }

  /// 시스템 백 전용 — 같은 탈출구를 쓰되, 되돌릴 수 없는 동작이라 확인을 받는다.
  Future<void> _confirmRestart(BuildContext context, WidgetRef ref) async {
    final leave = await showDialog<bool>(
      context: context,
    // 루트 Navigator에 띄운다 — 기본값(false)이면 셸 내부 Navigator에 올라가
    // **하단 탭바가 시트와 스크림 위에 남는다**(실기기 점검에서 발견, P09).
    // 모달이 뜬 채로 다른 탭을 누를 수 있어 확정 전 화면을 벗어나게 된다.
    useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('번호 입력으로 돌아갈까요?'),
        content: const Text(
          '지금 인증한 번호는 로그아웃돼요. 승인을 기다리는 중이라면 같은 번호로 '
          '다시 인증했을 때 대기 상태로 돌아와요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('머무르기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('돌아가기'),
          ),
        ],
      ),
    );
    if ((leave ?? false) && context.mounted) await _restart(context, ref);
  }

  void _showJoinRequestSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _JoinRequestSheet(),
    );
  }
}

/// 상태별 CTA — 어떤 분기로 들어와도 최소 하나의 진행 경로와
/// "다른 번호로 다시 시도"가 함께 남는다(빈 CTA 블록이 나올 수 없는 구조).
class _CtaBlock extends StatelessWidget {
  const _CtaBlock({
    required this.stage,
    required this.memberName,
    required this.busy,
    required this.checking,
    required this.onConfirm,
    required this.onRestart,
    required this.onCheck,
  });

  final CenterConfirmStage stage;
  final String? memberName;

  /// 이 플로우의 어떤 요청이든 진행 중 — 모든 CTA를 함께 잠근다.
  final bool busy;

  /// 그중 "연결 확인"이 진행 중일 때만 — 라벨을 "확인 중…"으로 바꾼다.
  final bool checking;

  final void Function(bool confirm) onConfirm;
  final VoidCallback onRestart;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    if (stage == CenterConfirmStage.matched && memberName != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiseButton(
            label: busy ? '확인 중…' : '네, $memberName 본인이에요 — 시작하기',
            expand: true,
            onPressed: busy ? null : () => onConfirm(true),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _UnderlineLink(
                label: '본인이 아니에요',
                onTap: busy ? null : () => onConfirm(false),
              ),
              const Text(' · ', style: TextStyle(fontSize: 11, color: AppColors.muted)),
              _UnderlineLink(label: _restartLabel, onTap: busy ? null : onRestart),
            ],
          ),
        ],
      );
    }

    // 연결 여부를 모르는 상태(앱 시작 복원 실패) — 번호를 다시 넣게 하는 건
    // 이미 연결됐을지 모르는 사용자에게 인증을 처음부터 시키는 일이다.
    // 재확인을 주 버튼으로 올리고, 번호 재시도는 링크로 남긴다.
    if (stage == CenterConfirmStage.connectionUnknown) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiseButton(
            label: checking ? '확인 중…' : '연결됐는지 다시 확인',
            expand: true,
            onPressed: busy ? null : onCheck,
          ),
          const SizedBox(height: 10),
          Center(
            child: _UnderlineLink(label: _restartLabel, onTap: busy ? null : onRestart),
          ),
        ],
      );
    }

    // 매칭이 없는 세 상태(본인 아님 / 승인 대기 / 매칭 실패)에서는 번호를 다시 넣는
    // 것이 사실상 유일한 자력 복구 경로 — 주 버튼으로 올린다. 다만 승인 대기 중엔
    // "기다리기"가 정상 경로이므로 outline으로 낮춘다.
    final waiting = stage == CenterConfirmStage.pendingApproval;
    return RiseButton(
      label: busy ? '처리 중…' : _restartLabel,
      expand: true,
      style: waiting ? RiseButtonStyleKind.outline : RiseButtonStyleKind.primary,
      onPressed: busy ? null : onRestart,
    );
  }

  static const _restartLabel = '다른 번호로 다시 시도';
}

class _UnderlineLink extends StatelessWidget {
  const _UnderlineLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 로그인 플로우의 최종 탈출구("다른 번호로", "본인이 아니에요") — 글자 상자만
    // 누르면 ≈15dp였다. 투명 패딩을 GestureDetector 안쪽에 두고 opaque로 받는다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: onTap == null ? AppColors.line : AppColors.muted,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

/// 가입 요청 시트 — 예약 확정 시트와 같은 Stateful 패턴:
/// 제출 중 표시·이중 탭 방지·에러는 시트 뒤가 아니라 시트 안에 인라인 표시.
class _JoinRequestSheet extends ConsumerStatefulWidget {
  const _JoinRequestSheet();

  @override
  ConsumerState<_JoinRequestSheet> createState() => _JoinRequestSheetState();
}

class _JoinRequestSheetState extends ConsumerState<_JoinRequestSheet> {
  final _nameController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 이름 입력 시 키보드가 올라오면 작은 화면에서 overflow — 스크롤로 흡수.
    return SingleChildScrollView(
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
          const Text('가입 요청', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            '이름·연락처로 가입 요청 → 센터에서 승인하면 연결돼요 (코드 입력 없음)',
            style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: '이름 입력 (연락처는 인증한 번호로 전송돼요)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
          ],
          const SizedBox(height: 12),
          RiseButton(
            label: _submitting ? '요청 중…' : '가입 요청 보내기',
            expand: true,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '이름을 입력해주세요');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final notifier = ref.read(authViewModelProvider.notifier);
    final ok = await notifier.requestJoin(name);
    if (!mounted) return;
    if (ok) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        riseSnackBar('가입 요청 완료 — 센터 승인 후 자동으로 연결돼요', kind: RiseSnackKind.ok),
      );
    } else {
      // 에러는 시트 안에서 보여주고, 시트 뒤 화면(state.error 표시부)에는 남기지 않는다.
      final message = ref.read(authViewModelProvider).error?.message ?? '요청에 실패했어요';
      notifier.clearError();
      setState(() {
        _submitting = false;
        _error = message;
      });
    }
  }
}

class _MatchedCenterCard extends StatelessWidget {
  const _MatchedCenterCard({required this.memberName, this.trainerName, this.trainer});
  final String memberName;
  final String? trainerName;

  /// 스태프 캐시에서 보강한 담당 코치(P05) — 아바타·직함 표시용(best-effort).
  final StaffDto? trainer;

  @override
  Widget build(BuildContext context) {
    // 캐시의 이름이 ""면 state의 이름으로 넘어가야 한다(??는 ""를 통과시킨다).
    // 둘 다 미해석(null·""·공백)이면 null — 예전엔 공백뿐인 이름이 non-null로
    // 살아남아 "담당    코치" + 빈 이니셜 아바타(TrainerAvatar는 isEmpty만 본다)가 됐다.
    final coachName =
        CoachLabel.nameOrNull(trainer?.name) ?? CoachLabel.nameOrNull(trainerName);
    // 스태프 캐시를 못 받았으면 퇴사 여부를 알 수 없다 → 현직으로 본다
    // (계약 v2.0 승격 규약과 같은 방향 — 모르는 걸 퇴사로 단정하지 않는다).
    final coachInactive = trainer?.isInactive ?? false;
    // 직함 · 연차 한 줄 — 매칭 카드의 신뢰도 보강(빈 프로필이면 줄 생략).
    final coachSubtitle = trainer == null
        ? ''
        : [
            if (trainer!.profile.title.isNotEmpty) trainer!.profile.title,
            if (trainer!.profile.careerYears > 0) '${trainer!.profile.careerYears}년차',
          ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.redLight,
        border: Border.all(color: AppColors.red, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  AppConfig.centerFullName,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              RiseBadge('자동 매칭', variant: RiseBadgeVariant.ok),
            ],
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
              children: [
                TextSpan(
                  text: memberName,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                const TextSpan(text: ' 님으로 등록되어 있어요'),
              ],
            ),
          ),
          if (coachName != null) ...[
            const SizedBox(height: 8),
            // 담당 코치 아바타(소) + 직함(P05) — 탭하면 프로필 시트.
            InkWell(
              onTap: () => showTrainerProfileSheet(
                context,
                staff: trainer ?? StaffDto(uid: '', name: coachName),
                // 스태프 캐시를 못 받아 이름만 채운 폴백이면 "미등록"이 아니라
                // "미로드"다 — 예약 탭과 같은 규약으로 시트가 재시도 안내를 한다
                // (예전엔 플래그를 안 넘겨 온보딩에서만 문구가 갈렸다).
                profileUnavailable: trainer == null,
              ),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Row(
                children: [
                  TrainerAvatar(
                    name: coachName,
                    photoUrl: trainer?.profile.photoUrl ?? '',
                    colorHex: trainer?.color,
                    size: 26,
                    inactive: coachInactive,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // 온보딩 화면의 **퇴사 표기 앵커**(코치 언급이 여기 한 줄뿐).
                          // 계약상 퇴사 전 Member.trainer_id 이관이 강제되므로 정상
                          // 흐름에선 나오지 않지만, 첫 화면부터 사실과 다른 담당을
                          // 소개하는 건 되돌리기 가장 어려운 오해라 방어한다.
                          CoachLabel.tag('담당 $coachName 코치', inactive: coachInactive),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        if (coachSubtitle.isNotEmpty)
                          Text(
                            coachSubtitle,
                            style: const TextStyle(fontSize: 10, color: AppColors.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "본인이 아니에요" 거부 직후 안내 — 매칭 카드는 사라지고, 아래 가입 요청 경로가 남는다.
class _DeclinedCard extends StatelessWidget {
  const _DeclinedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.line, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseIcon(RiseIcons.check, size: 18, color: AppColors.muted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '확인했어요. 번호가 잘못 등록됐다면 센터에 문의해주세요. '
              '다른 센터 회원이라면 아래에서 가입 요청할 수 있어요.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotFoundCard extends StatelessWidget {
  const _NotFoundCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.line, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseIcon(RiseIcons.alertTriangle, size: 18, color: AppColors.warn),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '이 번호로 등록된 회원 정보를 찾지 못했어요. 아래에서 센터를 찾아 가입 요청해보세요.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 연결 여부를 확인하지 못한 상태(앱 시작 복원이 GET /v1/me에 실패) —
/// "찾지 못했어요"와 다른 카드를 쓴다. 저쪽은 서버가 낸 결론이지만 이쪽은
/// 아직 아무것도 모르는 상태라, 가입 요청이 아니라 재확인으로 유도해야 한다.
class _ConnectionUnknownCard extends StatelessWidget {
  const _ConnectionUnknownCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.line, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseIcon(RiseIcons.alertTriangle, size: 18, color: AppColors.warn),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '연결 상태를 불러오지 못했어요. 네트워크가 돌아오면 아래에서 다시 확인해주세요. '
              '이미 연결된 회원이라면 그대로 홈으로 들어가요.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 가입 요청 성공 후 고정되는 "승인 대기 중" 카드 — 재제출 중복을 막고,
/// "다시 요청" 버튼은 30초 카운트다운이 끝나야 활성화된다(로컬 상태).
///
/// "연결됐는지 확인"이 주 액션이다: 대표가 승인해도 앱은 알 방법이 없어서,
/// 예전엔 앱을 껐다 켜거나 **다시 요청**하는 것뿐이었다 — 그런데 재요청은
/// 대표 화면에 같은 사람을 한 줄 더 쌓는다. 확인은 읽기만 하므로 안전하다.
class _PendingApprovalCard extends StatefulWidget {
  const _PendingApprovalCard({
    super.key,
    required this.requestedAt,
    required this.onRetry,
    required this.onCheck,
    this.busy = false,
    this.checking = false,
  });

  final DateTime requestedAt;
  final VoidCallback onRetry;
  final VoidCallback onCheck;

  /// 이 플로우의 어떤 요청이든 진행 중이면 두 버튼을 함께 잠근다(연타 방지).
  final bool busy;

  /// 그중 연결 확인이 진행 중 — 라벨만 바꾼다.
  final bool checking;

  @override
  State<_PendingApprovalCard> createState() => _PendingApprovalCardState();
}

class _PendingApprovalCardState extends State<_PendingApprovalCard> {
  static const _cooldown = Duration(seconds: 30);

  Timer? _timer;
  late int _remainingSeconds = _computeRemaining();

  int _computeRemaining() {
    final elapsed = DateTime.now().difference(widget.requestedAt);
    final left = _cooldown - elapsed;
    return left.isNegative ? 0 : left.inSeconds + (left.inMilliseconds % 1000 > 0 ? 1 : 0);
  }

  @override
  void initState() {
    super.initState();
    if (_remainingSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _remainingSeconds = _computeRemaining());
        if (_remainingSeconds <= 0) t.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final retryLocked = _remainingSeconds > 0 || widget.busy;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.line, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('가입 요청을 보냈어요', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              RiseBadge('승인 대기 중', variant: RiseBadgeVariant.warn),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '센터에서 승인하면 자동으로 연결돼요. 승인됐는지 아래에서 확인할 수 있어요.',
            style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 10),
          // Wrap: 좁은 화면·긴 카운트다운 라벨("다시 요청 (30초 후)")에서 두 버튼이
          // 가로로 넘치는 대신 줄바꿈되게 한다.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 승인 여부를 아는 유일한 안전한 방법 — 읽기만 하므로 쿨다운이 없다.
              RiseButton(
                label: widget.checking ? '확인 중…' : '연결됐는지 확인',
                small: true,
                onPressed: widget.busy ? null : widget.onCheck,
              ),
              // 재요청은 대표 화면에 줄을 하나 더 만든다 — 30초 쿨다운 유지.
              RiseButton(
                label: _remainingSeconds > 0 ? '다시 요청 ($_remainingSeconds초 후)' : '다시 요청',
                style: RiseButtonStyleKind.outline,
                small: true,
                onPressed: retryLocked ? null : widget.onRetry,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JoinOtherCenterCard extends StatelessWidget {
  const _JoinOtherCenterCard({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('우리 센터가 안 보여요', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  SizedBox(height: 3),
                  Text(
                    '이름·연락처로 가입 요청 → 승인되면 연결돼요',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            RiseIcon(RiseIcons.chevronRight, size: 14, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
