import 'package:flutter/material.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';

/// 포즈 시퀀스 칩 — "1 차렷 ✓  2 T자 ✓  3 전굴 ●".
///
/// 목록·라벨은 **회원마다 다르다**(계약 v2.10 — 대표가 어드민에서 정한다). 번호는 이
/// 시퀀스 안의 순서일 뿐이라 회원마다 같은 번호가 다른 포즈를 가리킬 수 있다.
/// 체크는 RiseIcon, 진행 중 표시는 텍스트 문자 대신 점 컨테이너(이모지 금지).
class PoseSequenceChips extends StatelessWidget {
  const PoseSequenceChips({
    super.key,
    required this.poses,
    required this.completed,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<PoseSpec> poses;

  /// 저장을 마친 포즈 **key** 집합.
  final Set<String> completed;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 5,
      runSpacing: 5,
      children: [
        for (var i = 0; i < poses.length; i++)
          _PoseChip(
            index: i,
            pose: poses[i],
            done: completed.contains(poses[i].key),
            current: i == currentIndex,
            onTap: () => onSelect(i),
          ),
      ],
    );
  }
}

class _PoseChip extends StatelessWidget {
  const _PoseChip({
    required this.index,
    required this.pose,
    required this.done,
    required this.current,
    required this.onTap,
  });

  final int index;
  final PoseSpec pose;
  final bool done;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = done || current;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? AppColors.redLight : AppColors.chipBg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: on ? AppColors.redBorder : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1} ${pose.label}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                color: on ? AppColors.red : AppColors.chipFg,
              ),
            ),
            const SizedBox(width: 4),
            if (done)
              const RiseIcon(RiseIcons.check, size: 11, color: AppColors.red)
            else if (current)
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}
