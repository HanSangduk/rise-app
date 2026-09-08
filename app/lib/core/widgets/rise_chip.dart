import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/theme/app_typography.dart';

/// 목업 `.chip` — 패스 스위처, 날짜 스트립, 코치 필터, 포즈 시퀀스에 공용.
class RiseChip extends StatelessWidget {
  const RiseChip({super.key, required this.label, this.selected = false, this.onTap, this.leading});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// 라벨 앞 소형 위젯(예: 코치 아바타 16) — 없으면 기존 텍스트 전용 칩 그대로.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    // 배지와 같은 이유로 한 줄 고정 — 칩 라벨은 코치 이름·상품명이 들어와 길이
    // 상한이 없고("정혜린 코치 (퇴사) · PT 20회권 (활성)"), 두 줄로 접힌 알약은
    // 고장으로 보인다. Wrap 안에서는 폭이 이미 유계라 그대로 말줄임된다.
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: selected ? AppTypography.chipOn : AppTypography.chip,
    );
    // 선택 상태가 색·굵기로만 전달되고 있었다(P54) — 스크린리더 사용자는 어느
    // 날짜·어느 회원권이 골라졌는지 알 방법이 없었다. 이 위젯을 회원권 스위처·
    // 날짜 스트립·코치 필터가 모두 상속하므로 여기 한 줄이 앱 전역을 고친다.
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        // 히트 영역만 상하로 넓힌다(44dp 근접) — 투명 패딩이라 알약의 시각 크기
        // (배경·보더는 아래 Container가 칠한다)는 그대로다.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            margin: const EdgeInsets.only(right: 6, bottom: 4),
            decoration: BoxDecoration(
              color: selected ? AppColors.brandLight : AppColors.chipBg,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: selected ? AppColors.brandBorder : Colors.transparent),
            ),
            child: leading == null
                ? text
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    // MainAxisSize.min은 자식에게 무제한 폭을 주므로 Text 혼자서는
                    // 말줄임되지 못하고 Row가 넘친다 — Flexible로 유계를 만들어 준다.
                    children: [
                      leading!,
                      const SizedBox(width: 5),
                      Flexible(child: text),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
