import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/theme/app_typography.dart';

/// Light 테마 + 브랜드 네이비 액센트(#3B4C60). 회색·상태색은 목업 CSS 1:1 매핑.
///
/// seed를 [AppColors.brand]로 주는 것이 중요하다(P54) — Material 3는 error 팔레트를
/// hue 25로 하드코딩하므로, seed가 빨강이면 M3가 생성하는 primary/secondary/tertiary
/// 전체가 error와 10° 안에서 겹친다. 네이비 seed는 231° 떨어진다.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.brand,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: AppColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.page,
    fontFamily: AppTypography.fontFamily,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: AppTypography.headerTitle,
      // 시스템 바 아이콘 색을 명시한다(P54). 종전엔 지정이 없어 MaterialApp이
      // 밝은 테마 기본값 `SystemUiOverlayStyle.dark`를 보냈는데, 그 값은
      // **네비게이션 바를 검게 칠하고 그 위에 흰 아이콘**을 얹는 조합이다.
      // targetSdk 36의 edge-to-edge에서 `systemNavigationBarColor`는 no-op이라
      // 칠은 사라지고 **흰 아이콘만 크림 배경 위에 남았다**(실측: 전송값
      // `systemNavigationBarIconBrightness: light`). 3버튼 내비는 시스템이 깔아
      // 주는 스크림 덕에 읽혔지만 제스처 내비는 스크림이 없어 거의 안 보였다.
      // 색은 지정하지 않는다 — no-op인 값을 넣으면 Play Console이 deprecated
      // API 사용으로 경고한다.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light, // iOS
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.line,
        disabledForegroundColor: AppColors.muted,
        elevation: 0,
        textStyle: AppTypography.button,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line, width: 1.5),
        textStyle: AppTypography.button,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.all(13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        borderSide: const BorderSide(color: AppColors.line, width: 1.5),
      ),
      // 입력 필드만 [AppColors.line]보다 진한 경계를 쓴다(P54). WCAG 1.4.11은
      // "컴포넌트 식별에 필요한" 경계에 3:1을 요구하는데, 텍스트 필드는 보더가
      // 사라지면 입력 칸인지 알 방법이 없어 해당된다(카드 보더는 장식이라 면제).
      // `line` #E5E7EB은 흰 배경 위 1.24:1이었다.
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        borderSide: const BorderSide(color: AppColors.inputBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
      ),
    ),
    // 스낵바는 앱에서 유일하게 팔레트 밖이었다(M3 기본 inverseSurface = 보라 계열
    // 회색). 중립 알림의 기본값만 여기서 정하고, 성공/실패 색 분기는 호출부가
    // [riseSnackBar]로 넘긴다 — 테마 하나로는 "저장됨"과 "저장 실패"를 구분할
    // 방법이 없기 때문(camera_screen의 두 스낵바가 실제로 똑같이 보였다).
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: AppTypography.body.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
    ),
    // 다이얼로그 테마가 없어서 `AlertDialog` 9개 중 8개가 M3 기본값으로 떠 있었다
    // (P54): 모서리 28dp(앱 전체는 14), 제목 24pt(앱 최대 본문 15pt), surfaceTint가
    // 섞인 보라끼 흰색. 한 화면 안에서 카드와 다이얼로그가 다른 앱처럼 보였다.
    // 여기 한 블록이 8곳을 동시에 정렬한다 — 개별 화면에서 다시 지정하지 말 것.
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: AppTypography.cardTitle,
      contentTextStyle: AppTypography.body,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.brand : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? AppColors.brandBorder : AppColors.line,
      ),
    ),
  );
}
