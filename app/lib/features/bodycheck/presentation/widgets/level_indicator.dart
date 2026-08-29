import 'dart:math';
import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/features/bodycheck/domain/level_state.dart';

/// 수평계 — 맞으면 초록, 기울면 주황 + 각도.
///
/// 자동 촬영은 제거했다(P31). 수평계는 **자세를 맞추는 눈금**으로 남는다 — 폰이
/// 기울면 어깨선 기울기를 재는 격자 자체가 거짓말을 하기 때문이다.
class LevelIndicator extends StatelessWidget {
  const LevelIndicator({super.key, required this.state});
  final LevelState state;

  @override
  Widget build(BuildContext context) {
    final ok = state is LevelOk;
    final color = ok ? AppColors.camLevelOk : AppColors.camLevelTilt;
    final clampedDeg = state.angleDeg.clamp(-15.0, 15.0);

    return Positioned(
      left: 0,
      right: 0,
      top: 0.36 * 472, // 목업 top:36% (카메라 프레임 높이 472 기준 근사)
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Transform.rotate(
              angle: clampedDeg * pi / 180,
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 10)],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  ok
                      ? '수평 OK'
                      : '기울음 ${state.angleDeg.abs().toStringAsFixed(1)}° — 폰을 세워주세요',
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
