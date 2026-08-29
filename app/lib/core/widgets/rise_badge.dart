import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/theme/app_typography.dart';

enum RiseBadgeVariant { ok, warn, danger, red, muted, blue }

/// 목업 `.badge` — 완료/대기/만석 등 짧은 상태 표시.
class RiseBadge extends StatelessWidget {
  const RiseBadge(this.label, {super.key, this.variant = RiseBadgeVariant.muted});

  final String label;
  final RiseBadgeVariant variant;

  (Color, Color) get _colors => switch (variant) {
        RiseBadgeVariant.ok => (AppColors.badgeOkBg, AppColors.badgeOkFg),
        RiseBadgeVariant.warn => (AppColors.badgeWarnBg, AppColors.badgeWarnFg),
        RiseBadgeVariant.danger => (AppColors.badgeDanBg, AppColors.badgeDanFg),
        RiseBadgeVariant.red => (AppColors.redLight, AppColors.red),
        RiseBadgeVariant.muted => (AppColors.badgeMutBg, AppColors.badgeMutFg),
        RiseBadgeVariant.blue => (AppColors.badgeBlueBg, AppColors.badgeBlueFg),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      // 알약은 한 줄이 정상 — 두 줄로 늘어난 배지는 고장으로 보인다. 폭이 좁으면
      // 줄바꿈 대신 말줄임한다. 폭이 넉넉할 땐(= 지금 모든 화면) 아무 영향 없다.
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.badge.copyWith(color: fg),
      ),
    );
  }
}
