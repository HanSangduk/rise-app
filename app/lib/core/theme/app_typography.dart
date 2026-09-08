import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';

/// 타이포 토큰 — 목업의 px 크기를 그대로 이식(.hd .t 16.5/900, .card h4 12.5/700 등).
abstract final class AppTypography {
  static const fontFamily = 'Pretendard';

  static const headerTitle = TextStyle(
    fontSize: 16.5,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
  );

  static const headerSubtitle = TextStyle(
    fontSize: 10,
    color: AppColors.muted,
  );

  static const cardTitle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontSize: 12,
    color: AppColors.ink,
  );

  static const bodyStrong = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
  );

  static const note = TextStyle(
    fontSize: 10,
    color: AppColors.muted,
    height: 1.6,
  );

  static const badge = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
  );

  static const chip = TextStyle(
    fontSize: 10.5,
    color: AppColors.chipFg,
  );

  static const chipOn = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    color: AppColors.brand,
  );

  static const button = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
  );

  static const bigNumber = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
  );

  static const logo = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
  );
}
