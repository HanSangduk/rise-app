import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_typography.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/time_boundary_builder.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';

/// 목업 "내 회원권 (N개)" 카드 — 패스별 담당 코치/상태 + 일시정지 신청·재개 진입점.
/// 홀딩 중인 패스는 "일시정지 중 ~종료일" 배지 + 재개 버튼을 함께 보여준다.
class PassList extends ConsumerStatefulWidget {
  const PassList({super.key, required this.passes, required this.onHoldTap});

  final List<PassDetail> passes;
  final VoidCallback onHoldTap;

  @override
  ConsumerState<PassList> createState() => _PassListState();
}

class _PassListState extends ConsumerState<PassList> {
  String? _resumingPassId;

  @override
  Widget build(BuildContext context) {
    // 홀딩 상한은 센터 정책 실값(GET /v1/center) — 미로드/실패 시 폴백(2회/30일)이
    // 오지만 그 숫자는 **화면에 내지 않는다**(`isFallback` 분기, P56 H1).
    final policy = ref.watch(centerPolicyProvider).value ?? CenterPolicy.fallback;
    // 이용 중(active) 패스가 없으면 일시정지 신청은 데드엔드(서버 거부) —
    // 진입점 자체를 비활성으로 두고 이유를 안내한다.
    final hasActivePass = widget.passes.any((p) => p.isActive);

    // "일시정지 중" 배지와 그 옆 **재개 버튼**은 날짜가 바뀌면 뜻이 달라진다
    // ([_resumableHold] → [PassDetail.activeHold]가 `todayKst()`를 다시 읽는 getter).
    // 마이 탭도 indexedStack에 상주해서(core/router/app_router.dart) 아무도
    // 리빌드해 주지 않으므로, 홀딩 마지막 날 자정을 넘겨도 버튼이 살아 있었다 —
    // 누르면 서버 `ResumePass`가 거부하고(400), 그 전에 **되돌릴 수 없는 소진**을
    // 알리는 확인 다이얼로그가 이미 굳은 판정 위에 뜬다(_confirmResume).
    // 홈 회원권 카드와 같은 처방이다(home_screen.dart의 atMidnight — 서버 왕복 0).
    return TimeBoundaryBuilder(
      atMidnight: true,
      builder: (context, _) => _card(hasActivePass, policy),
    );
  }

  Widget _card(bool hasActivePass, CenterPolicy policy) {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseCardHeader(title: '내 회원권 (${widget.passes.length}개)'),
          for (final p in widget.passes)
            RiseRow(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상품명·코치 이름은 서버 문자열이라 길이 상한이 없다 — 셋 다
                  // 비유연이면 "3개월 집중 관리 프로그램" + 긴 코치 이름에서 행이
                  // 통째로 넘친다. 앞의 두 텍스트만 Flexible(loose)로 두면: 다
                  // 들어갈 땐 지금과 똑같이 왼쪽으로 붙어 렌더되고(loose는 자연
                  // 크기를 그대로 준다), 넘칠 때만 줄여서 말줄임한다.
                  // 배지는 비유연으로 남긴다 — 상태('이용 중'·'만료')는 잘리면
                  // 뜻이 사라지고, 길이가 짧아 넘침의 원인이 아니다
                  // (my_bookings_list의 Flexible+trailing 조합과 같은 규약).
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.product,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyStrong,
                        ),
                      ),
                      // 담당 코치 미배정/미해석이면 " · " 꼬리를 아예 생략(빈 세그먼트 방지).
                      //
                      // 마이 탭의 **퇴사 표기 앵커** — 패스마다 담당 코치가 다르고,
                      // 여기가 마이 탭에서 코치 이름이 나오는 가장 큰 자리다.
                      // 원장 대상 칩·일시정지 시트 드롭다운은 "어떤 패스인지" 고르는
                      // 자리라 이름만 두고 표기는 생략한다(같은 사실 반복 방지).
                      // 만료·환불된 과거 패스는 퇴사 선행 조건(active/scheduled만 검사)에
                      // 걸리지 않으므로 실제로 여기서 퇴사자를 보게 된다.
                      // 이름은 정규화된 값만 보간한다 — 판정만 유틸에 맡기고 원본을
                      // 쓰면 " 정혜린 "이 "·  정혜린 "으로 새어 나온다.
                      if (CoachLabel.nameOrNull(p.trainerName) case final coach?) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            CoachLabel.tag('· $coach', inactive: p.trainerInactive),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      RiseBadge(_statusLabel(p), variant: p.isActive ? RiseBadgeVariant.ok : RiseBadgeVariant.muted),
                    ],
                  ),
                  if (_resumableHold(p) case final hold?)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(
                        children: [
                          RiseBadge(
                            '일시정지 중 ~${hold.to.month}/${hold.to.day}',
                            variant: RiseBadgeVariant.warn,
                          ),
                          const SizedBox(width: 6),
                          RiseButton(
                            label: _resumingPassId == p.id ? '재개 중…' : '재개',
                            style: RiseButtonStyleKind.outline,
                            small: true,
                            onPressed: _resumingPassId == null ? () => _resume(p, hold) : null,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              trailing: Text(
                p.isScheduled ? '${p.totalSessions}회' : '잔여 ${p.remaining}회',
                style: AppTypography.bodyStrong,
              ),
            ),
          InkWell(
            onTap: hasActivePass ? widget.onHoldTap : null,
            child: Opacity(
              opacity: hasActivePass ? 1 : 0.55,
              child: RiseRow(
                showDivider: false,
                minHeight: 44,
                child: Row(
                  children: [
                    const RiseIcon(RiseIcons.pause, size: 13, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        // 폴백이면 상한을 말하지 않는다 — "최대 2회/30일"은 이 센터의
                        // 기준이 아니라 앱 기본값이다. 실값은 시트 안 잔여 요약이 다시 말한다.
                        !hasActivePass
                            ? '일시정지 신청 — 이용 중인 회원권이 없어요'
                            : policy.isFallback
                                ? '일시정지 신청 (여행·부상 시)'
                                : '일시정지 신청 (여행·부상 시 · ${policy.holdLimitLabel})',
                      ),
                    ),
                  ],
                ),
                trailing: hasActivePass
                    ? const RiseIcon(RiseIcons.chevronRight, size: 14, color: AppColors.muted)
                    : null,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '회원권마다 담당 코치가 달라요 — 홈 상단 칩으로 전환하면 예약·Home Work가 그 코치 기준으로 '
              '바뀝니다. 일시정지하면 실제로 쉰 날짜만큼 유효기간이 늘어나고, 중간에 재개해도 그 1회는 '
              '쓴 것으로 남아요.',
              style: AppTypography.note,
            ),
          ),
        ],
      ),
    );
  }

  /// 지금 재개할 수 있는 홀딩(없으면 null) — "일시정지 중" 배지 + 재개 버튼의 조건.
  ///
  /// [PassDetail.activeHold]만으로는 부족하다: 서버 `ResumePass`는 **active 패스만**
  /// 재개한다(400 "이용 가능한 상태의 패스만 재개할 수 있어요"). 환불·만료된 패스도
  /// `holds`를 그대로 들고 있어서(`RefundPass`는 status만 바꾼다) 오늘이 구간 안이면
  /// 배지와 버튼이 떴고, 누르면 서버가 거부했다. 상태가 아닌 패스에선 "일시정지 중"
  /// 자체가 사실이 아니므로 배지까지 함께 감춘다 — '환불' 배지 옆의 '일시정지 중'은
  /// 회원에게 "아직 살아 있는 회원권"으로 읽힌다.
  PassHold? _resumableHold(PassDetail p) => p.isActive ? p.activeHold : null;

  /// 조기 재개는 되돌릴 수 없는 소진이다 — 확인을 받고, **무엇이 사라지는지** 말한다.
  ///
  /// 서버 규칙 두 가지를 그대로 옮긴다:
  ///  · `domain.ResumeHold` — 진행 중 홀딩의 `to`를 오늘로 줄이고, 안 쓴 날짜만큼
  ///    `valid_until`을 **다시 당긴다**. 즉 실제로 쉰 날짜만 유효기간 연장으로 남는다.
  ///  · `domain.ValidateNewHold` — 줄어든 홀딩도 `holds`에 그대로 남아
  ///    `len(existing)+1 > maxCount` 검사에 계속 잡힌다("조기 종료(Resume)된 홀딩도
  ///    횟수 상한에 포함된다 — 사용한 홀딩은 소진" — pass.go 주석).
  /// 10일 예정 중 2일 만에 재개한 회원이 나중에 "상한 초과"로 거부당하고서야
  /// 알게 되는 걸 막는 게 이 다이얼로그의 목적이다.
  Future<bool> _confirmResume(PassDetail p, PassHold hold) async {
    final policy = ref.read(centerPolicyProvider).value ?? CenterPolicy.fallback;
    final used = p.holds.length;
    final lines = <String>[
      // hold.to는 **정지 예정 종료일**이지 유효기간 만료일이 아니다 — 둘을 섞어
      // 쓰면 "8/31까지 쓸 수 있었는데"로 잘못 읽힌다. 늘어났던 만큼 되돌아간다는
      // 사실만 말하고 날짜는 정지 예정일로 못 박는다.
      '· 유효기간은 정지 예정일(${hold.to.month}/${hold.to.day})까지를 기준으로 늘어나 있어요. '
          '지금 끝내면 실제로 쉰 날짜만 남기고 다시 당겨져요.',
      // 상한을 모르면(정책 조회 실패) "최대 N회"를 지어내지 않는다 — 쓴 횟수는 이 회원권의
      // 사실이라 그대로 말하고, 상한은 모른다고 밝힌다(P56 H1).
      if (policy.isFallback)
        '· 일찍 끝내도 이번 일시정지 1회는 쓴 것으로 남아요 — 이 회원권은 지금까지 $used회를 '
            '썼어요. (최대 횟수는 센터 정책을 확인하지 못했어요)'
      else if (policy.maxHoldsPerPass > 0)
        '· 일찍 끝내도 이번 일시정지 1회는 쓴 것으로 남아요 — 이 회원권은 최대 '
            '${policy.maxHoldsPerPass}회 중 $used회를 썼어요.'
      else
        '· 일찍 끝내도 이번 일시정지 1회는 쓴 것으로 남아요.',
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      // 마이 탭 시트들과 같은 이유로 루트 Navigator(하단 탭바가 스크림 위에 남지 않게).
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('일시정지를 지금 끝낼까요?'),
        content: Text(lines.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('더 쉬기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('지금 재개'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _resume(PassDetail p, PassHold hold) async {
    if (!await _confirmResume(p, hold)) return;
    if (!mounted) return;
    setState(() => _resumingPassId = p.id);
    final result = await ref.read(myViewModelProvider.notifier).resumeHold(p.id);
    if (!mounted) return;
    setState(() => _resumingPassId = null);
    if (result case Err(:final failure)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(riseSnackBar(failure.message, kind: RiseSnackKind.danger));
    }
  }

  /// 상태 wire 값을 그대로 노출하지 않고 한국어 라벨로 매핑.
  String _statusLabel(PassDetail p) {
    if (p.isActive) return '이용 중';
    if (p.isScheduled) return '${p.validFrom.month}/${p.validFrom.day} 시작';
    return switch (p.status) {
      'expired' => '만료',
      'refunded' => '환불',
      _ => p.status,
    };
  }
}
