// 팔레트 대비비 규약(P54).
//
// 색은 "보기 좋으냐"로 바뀌기 쉬운데, 바꾼 값이 읽히는지는 눈으로 판정할 수 없다.
// 그래서 실제로 짝을 이루는 조합만 골라 WCAG 대비비로 못 박는다. 여기 없는 조합은
// 의도적으로 뺐다 — 아래 "면제" 그룹 주석 참조. 전수 계산을 그대로 단언하면 위반이
// 아닌 것까지 잡아 다음 사람이 잘못된 수정을 하게 된다(감사에서 22쌍 중 13쌍이 오탐이었다).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_colors.dart';

double _lin(int c) {
  final s = c / 255.0;
  return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _lum(Color c) =>
    0.2126 * _lin((c.r * 255).round()) +
    0.7152 * _lin((c.g * 255).round()) +
    0.0722 * _lin((c.b * 255).round());

/// WCAG 2.x 대비비.
double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 두 색의 색상환 최단 거리(0~180°). 색이 "서로 달라 보이는가"를 재는 축이다.
double hueDistance(Color a, Color b) {
  final d = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs() % 360;
  return d > 180 ? 360 - d : d;
}

void _expectAA(Color fg, Color bg, String what, {double min = 4.5}) {
  final r = contrast(fg, bg);
  expect(
    r,
    greaterThanOrEqualTo(min),
    reason: '$what — 실측 ${r.toStringAsFixed(2)}:1, 기준 $min:1',
  );
}

void main() {
  group('본문 텍스트 4.5:1', () {
    test('brand — 흰 면·페이지 배경·틴트 면 어디에 얹혀도 읽힌다', () {
      // 종전 #E11D48은 페이지 배경 4.39 / 배지 글자 4.28로 두 자리가 미달이었다.
      _expectAA(AppColors.brand, AppColors.surface, 'brand on 흰 면');
      _expectAA(AppColors.brand, AppColors.page, 'brand on 페이지 배경');
      _expectAA(AppColors.brand, AppColors.brandLight, 'brand on 틴트 면(배지 글자)');
    });

    test('brand 면 위의 흰 글자 — CTA 라벨', () {
      _expectAA(Colors.white, AppColors.brand, 'CTA 라벨');
      _expectAA(Colors.white, AppColors.brandDark, 'pressed CTA 라벨');
    });

    test('탭 라벨 — 활성·비활성 둘 다', () {
      // 비활성이 앱 최대 대비 실패였다(#9CA3AF = 2.54:1). 4개 탭 중 3개가 항상 이 상태다.
      _expectAA(AppColors.tabInactive, AppColors.surface, '비활성 탭 라벨');
      _expectAA(AppColors.brand, AppColors.surface, '활성 탭 라벨');
    });

    test('배지 5종 — 배경/글자 쌍', () {
      _expectAA(AppColors.badgeOkFg, AppColors.badgeOkBg, 'ok 배지');
      _expectAA(AppColors.badgeWarnFg, AppColors.badgeWarnBg, 'warn 배지');
      _expectAA(AppColors.badgeDanFg, AppColors.badgeDanBg, 'danger 배지');
      _expectAA(AppColors.badgeBlueFg, AppColors.badgeBlueBg, 'blue 배지');
      // muted는 가장 많이 쓰이는 변형인데 유일하게 미달이었다(4.39).
      _expectAA(AppColors.badgeMutFg, AppColors.badgeMutBg, 'muted 배지');
    });

    test('본문 회색 — 흰 면과 페이지 배경', () {
      _expectAA(AppColors.muted, AppColors.surface, 'muted 본문 on 흰 면');
      _expectAA(AppColors.muted, AppColors.page, 'muted 본문 on 페이지 배경');
      _expectAA(AppColors.chipFg, AppColors.chipBg, '칩 글자');
    });
  });

  group('비텍스트 UI 3:1', () {
    test('잔여 링 — 진행 호가 트랙과 구분된다', () {
      _expectAA(AppColors.brand, AppColors.trackBg, '잔여 링', min: 3.0);
    });

    test('입력 필드 경계 — 보더가 사라지면 입력 칸인지 알 수 없다', () {
      // 카드 보더(line)는 장식이라 면제지만 텍스트 필드는 다르다(WCAG 1.4.11).
      _expectAA(AppColors.inputBorder, AppColors.surface, '입력 필드 경계', min: 3.0);
      _expectAA(AppColors.brand, AppColors.surface, '포커스 경계', min: 3.0);
    });

    test('비활성 탭 아이콘', () {
      _expectAA(AppColors.tabInactive, AppColors.surface, '비활성 탭 아이콘', min: 3.0);
    });
  });

  group('브랜드와 위험이 구분된다 — 이 팔레트 교체의 핵심 이유', () {
    // **대비비로 재지 않는다.** 대비비는 명도만 보므로 "같은 빨강 두 개"를
    // 통과시키고(종전 brand vs danger = 1.03:1이었지만 문제는 명도가 아니었다),
    // 반대로 네이비와 빨강처럼 명백히 다른 색을 명도가 비슷하다는 이유로
    // 잡아낸다. 구분 가능성을 재는 축은 **색상각**이다.
    test('brand와 danger의 색상각이 충분히 떨어져 있다', () {
      // 종전 #E11D48(hue 15) vs #DC2626(hue 25)은 9.5° 차이로 사람 눈에 같은
      // 색이었다. 그래서 "오늘" 배지와 경고 배지가, 골격근량 증가와 악화가,
      // 탈퇴 동의 체크박스와 탈퇴 버튼이 한 화면에서 구분되지 않았다.
      final d = hueDistance(AppColors.brand, AppColors.danger);
      expect(
        d,
        greaterThanOrEqualTo(60),
        reason: '브랜드와 위험이 다시 붙었다 — 실측 ${d.toStringAsFixed(1)}°',
      );
    });

    test('brand가 카메라 크로스헤어와도 구분된다', () {
      // 어두운 프리뷰 한 화면에 브랜드·경고·크로스헤어가 함께 뜬다.
      expect(hueDistance(AppColors.brand, AppColors.camCrosshair), greaterThanOrEqualTo(60));
    });

    test('brand가 성공/경고 상태색과도 구분된다', () {
      expect(hueDistance(AppColors.brand, AppColors.ok), greaterThanOrEqualTo(60));
      expect(hueDistance(AppColors.brand, AppColors.warn), greaterThanOrEqualTo(60));
    });

    test('상태색 3종은 서로도 구분된다 — 기존 규약이 깨지지 않았다', () {
      expect(hueDistance(AppColors.ok, AppColors.danger), greaterThanOrEqualTo(60));
      expect(hueDistance(AppColors.warn, AppColors.danger), greaterThanOrEqualTo(20));
    });
  });

  group('면제 — 여기 있는 조합은 대비 기준 대상이 아니다', () {
    // 이 그룹은 단언이 아니라 **기록**이다. 다음 사람이 전수 계산을 돌려
    // "미달"을 발견했을 때 잘못 고치는 걸 막는다.
    test('장식 경계와 배지 면은 WCAG 1.4.11 대상이 아니다', () {
      // brandBorder(1.80) · line(1.24) · 배지 배경들(1.1x)은 전부 기준 미달이지만,
      // "컴포넌트 식별에 필요한" 그래픽이 아니다 — 배지는 안의 글자가 의미를
      // 나르고, 카드는 보더가 없어도 카드다. 입력 필드만 예외라 위에서 따로 잰다.
      expect(contrast(AppColors.brandBorder, AppColors.surface), lessThan(3.0));
      expect(contrast(AppColors.line, AppColors.surface), lessThan(3.0));
    });

    test('비활성 버튼 라벨은 WCAG 1.4.3이 명시적으로 면제한다', () {
      expect(contrast(AppColors.muted, AppColors.line), lessThan(4.5));
    });
  });
}
