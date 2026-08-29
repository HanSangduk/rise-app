import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/theme/app_typography.dart';

/// 목업 `.card` — 흰 배경 + 라운드 + 옅은 보더. 화면 대부분의 기본 컨테이너.
class RiseCard extends StatelessWidget {
  const RiseCard({
    super.key,
    required this.child,
    this.tinted = false,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  /// `.card`에 `background:var(--red-l)`가 적용된 강조 카드(예: 다음 예약).
  final bool tinted;
  final Widget child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: tinted ? AppColors.redLight : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: tinted ? AppColors.redBorder : AppColors.line),
      ),
      child: child,
    );
  }
}

/// 카드 상단 `<h4>` 행 — 제목 + (선택) 우측 배지/액션.
class RiseCardHeader extends StatelessWidget {
  const RiseCardHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppTypography.cardTitle),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 목업 `.row` — 카드 내부 리스트 행(라벨 좌, 값/배지 우, 하단 구분선).
class RiseRow extends StatelessWidget {
  const RiseRow({
    super.key,
    required this.child,
    this.trailing,
    this.showDivider = true,
    this.minHeight = 0,
  });

  final Widget child;
  final Widget? trailing;
  final bool showDivider;

  /// 탭 가능한 행의 최소 전체 높이(44dp 타깃). 기본 0 = 목업 그대로의 정적 행.
  ///
  /// 바깥에 Padding을 두는 대신 행 자체를 키운다 — 구분선은 [Container]의
  /// 하단 보더라서, 바깥 패딩이면 선이 행 경계에서 떨어져 뜬다.
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.divider))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: DefaultTextStyle(style: AppTypography.body, child: child)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
