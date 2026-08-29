// 브랜드 마크 지오메트리(P32).
//
// 마크는 자산이 아니라 **그림**이다(`pubspec.yaml`에 `assets:` 키가 없어 브랜드
// PNG가 번들되지 않는다). 좌표는 `design/brand/rise-mark.svg`에서 한 줄씩 옮겼고,
// 그 SVG 자체가 브랜드 보드의 R을 픽셀 스캔해 재현한 값이라 **숫자가 곧 근거**다.
//
// 이 스위트가 잠그는 것: 그 숫자들이 조용히 바뀌지 않는 것, 그리고 네이티브
// 스플래시와 **같은 값**을 쓰는 것. 갈리면 기동 순간 마크가 점프하거나 배경색이 튄다.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/brand/rise_mark.dart';

void main() {
  group('SVG 원본과 같은 값', () {
    test('viewBox — "112 106 196 202"', () {
      expect(RiseMarkGeometry.viewBoxLeft, 112);
      expect(RiseMarkGeometry.viewBoxTop, 106);
      expect(RiseMarkGeometry.viewBoxWidth, 196);
      expect(RiseMarkGeometry.viewBoxHeight, 202);
    });

    test('획 굵기·색', () {
      expect(RiseMarkGeometry.strokeWidth, 21.5);
      expect(RiseMarkGeometry.navy, const Color(0xFF3B4C60));
      expect(RiseMarkGeometry.beige, const Color(0xFFCEBBAA));
    });

    test('크림은 SVG 밖 값 — 네이티브 launch_background와 같아야 한다', () {
      // `android/app/src/main/res/values/colors.xml`의 brand_cream,
      // `pubspec.yaml`의 adaptive_icon_background와 같은 #F6F4EF.
      expect(RiseMarkGeometry.cream, const Color(0xFFF6F4EF));
    });

    test('베이지 점 — 마크에서 유일하게 움직이는 요소', () {
      expect(RiseMarkGeometry.dotCenter, const Offset(287, 284.5));
      expect(RiseMarkGeometry.dotRadius, 17);
    });
  });

  group('획이 실제로 그려진다', () {
    test('세 갈래가 모두 들어 있다', () {
      // 획 하나를 빠뜨리면 R이 아니게 되는데, 색·굵기만 검사하면 안 잡힌다.
      final metrics = RiseMarkGeometry.strokePaths().computeMetrics().toList();
      expect(metrics, hasLength(3), reason: '큰 아치 · 다리 · 안쪽 r형 세 갈래다');
      for (final m in metrics) {
        expect(m.length, greaterThan(20), reason: '길이 0인 빈 획이 있다');
      }
    });

    test('획이 viewBox 안에 들어간다 — 굵기의 절반까지 포함해서', () {
      // 캡이 둥글어 획은 경로 바깥으로 굵기/2만큼 더 나간다. 이게 viewBox를
      // 넘으면 네이티브 스플래시(같은 viewport)에서 잘린다.
      final b = RiseMarkGeometry.strokePaths().getBounds();
      const half = RiseMarkGeometry.strokeWidth / 2;
      expect(b.left - half, greaterThanOrEqualTo(RiseMarkGeometry.viewBoxLeft));
      expect(b.top - half, greaterThanOrEqualTo(RiseMarkGeometry.viewBoxTop));
      expect(b.right + half,
          lessThanOrEqualTo(RiseMarkGeometry.viewBoxLeft + RiseMarkGeometry.viewBoxWidth));
      expect(b.bottom + half,
          lessThanOrEqualTo(RiseMarkGeometry.viewBoxTop + RiseMarkGeometry.viewBoxHeight));
    });

    test('점도 viewBox 안이다', () {
      const c = RiseMarkGeometry.dotCenter;
      const r = RiseMarkGeometry.dotRadius;
      expect(c.dx + r,
          lessThanOrEqualTo(RiseMarkGeometry.viewBoxLeft + RiseMarkGeometry.viewBoxWidth));
      expect(c.dy + r,
          lessThanOrEqualTo(RiseMarkGeometry.viewBoxTop + RiseMarkGeometry.viewBoxHeight));
    });
  });

  group('다시 그릴 때만 다시 그린다', () {
    test('값이 같으면 repaint하지 않는다 — 기동 중엔 래스터 스레드가 가장 바쁘다', () {
      const a = RiseMarkPainter(opacity: 0.5);
      const b = RiseMarkPainter(opacity: 0.5);
      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(const RiseMarkPainter(opacity: 0.6)), isTrue);
    });
  });
}
