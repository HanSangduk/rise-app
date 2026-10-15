// 색 대비의 **자**(P72). 종전엔 "읽기 힘들다"는 명제가 아니라 인상이었고, 고친 뒤에도
// 나아졌는지 알 방법이 없었다. WCAG 2.1 상대휘도 공식을 그대로 구현해 토큰 × 배경 조합을
// 숫자로 고정한다 — 색을 되돌리면 이 파일이 빨갛게 뜬다.
//
// 기준: 1.4.3 일반 텍스트 4.5:1 / 큰 글자(24px, 또는 bold 18.66px) 3:1 · 1.4.11 비텍스트 UI 3:1.
// **이 앱의 로그인 흐름에는 24px 텍스트가 없다** — 전부 4.5:1 기준이다.
//
// 시트 배경은 **상수가 아니라 ThemeData에서 읽는다**. Flutter/M3 기본값(surfaceContainerLow =
// neutral tone 96)은 패키지 업그레이드로 움직이므로, 상수로 박으면 이 시험이 진짜를 안 잰다.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_theme.dart';

/// 채널 선형화 — WCAG 2.1의 그 식 그대로.
double _lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // 자가 맞는지 먼저 잰다 — 자를 안 재고 쓰면 틀린 눈금으로 통과시킨다.
  test('자 검증 — 알려진 값과 일치한다', () {
    expect(contrast(Colors.black, Colors.white), closeTo(21.0, 0.01));
    expect(contrast(Colors.white, Colors.white), closeTo(1.0, 0.001));
  });

  group('본문 텍스트 4.5:1 (WCAG 1.4.3)', () {
    final sheetBg = () {
      final t = buildAppTheme();
      return t.bottomSheetTheme.backgroundColor ?? t.colorScheme.surfaceContainerLow;
    }();

    // 뮤테이션: app_theme.dart의 bottomSheetTheme 블록을 지우면 아래 두 건이 죽는다
    // (M3 기본 tone 96에서 muted·danger가 4.37:1로 떨어진다).
    test('가입 요청 시트 — muted 설명문과 danger 에러가 AA를 넘는다', () {
      expect(contrast(AppColors.muted, sheetBg), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.danger, sheetBg), greaterThanOrEqualTo(4.5));
    });

    test('흰 면(Scaffold)·회색 카드 면 위의 본문', () {
      for (final bg in [AppColors.surface, AppColors.surfaceMuted]) {
        expect(contrast(AppColors.muted, bg), greaterThanOrEqualTo(4.5), reason: '$bg');
        expect(contrast(AppColors.danger, bg), greaterThanOrEqualTo(4.5), reason: '$bg');
        expect(contrast(AppColors.ink, bg), greaterThanOrEqualTo(4.5), reason: '$bg');
      }
    });

    // brandLight(#EDF1F5) 위에서 muted는 **4.26:1**로 미달이다. `app_colors.dart`가 이미
    // "면이 회색일 때 한 단계 내린다"는 규약과 그 토큰(badgeMutFg)을 갖고 있었는데
    // 매칭 카드·센터 선택 행에만 적용되지 않았다(P72).
    test('brandLight 카드 면 위에서는 muted를 쓸 수 없다 — badgeMutFg가 그 자리다', () {
      expect(contrast(AppColors.muted, AppColors.brandLight), lessThan(4.5),
          reason: '이 사실이 바뀌면 아래 규약의 근거가 사라진다');
      expect(contrast(AppColors.badgeMutFg, AppColors.brandLight), greaterThanOrEqualTo(4.5));
    });

    test('주 버튼 — 네이비 면 위 흰 글씨', () {
      expect(contrast(Colors.white, AppColors.brand), greaterThanOrEqualTo(4.5));
    });
  });

  group('비텍스트 UI 3:1 (WCAG 1.4.11)', () {
    test('입력 경계', () {
      expect(contrast(AppColors.inputBorder, AppColors.surface), greaterThanOrEqualTo(3.0));
    });

    // `line`(#E5E7EB)은 흰 배경 대비 1.24:1이라 **유일한 식별 단서로는 미달**이다
    // (app_colors.dart가 스스로 적어 둔 사실). 스텝퍼의 남은 단계 표시는 색 말고
    // 모양(빈 링 vs 채운 원 vs 링+점)과 라벨 문구로도 구분되므로 장식으로 남긴다 —
    // 이 시험은 그 사실을 못 박아, 색만으로 정보를 나르는 자리에 `line`을 쓰면
    // 근거 없이 지나가지 않게 한다.
    test('line은 정보 전달용이 아니다 — 그 전제를 고정한다', () {
      expect(contrast(AppColors.line, AppColors.surface), lessThan(3.0));
    });
  });
}
