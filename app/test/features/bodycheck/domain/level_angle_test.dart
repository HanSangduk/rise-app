import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/bodycheck/domain/level_angle.dart';
import 'package:rise_member/features/bodycheck/domain/level_state.dart';

// 가속도계 → 각도 변환. 여기가 틀리면 수평계가 "물리적으로 반대"를 가리키는데도
// 화면은 멀쩡해 보인다(초록/주황은 abs 판정이라 부호를 안 본다) — 그래서 부호까지
// 못 박아 둔다.
//
// g = 9.81, 폰을 세로로 곧게 세우면 (x, y) = (0, +9.81).
const g = 9.81;

/// 폰을 시계방향(윗변이 오른쪽)으로 [deg]만큼 기울였을 때의 가속도계 원값.
/// x = -g·sinθ, y = g·cosθ (level_angle.dart 유도 참조).
(double, double) tilt(double deg) {
  final r = deg * math.pi / 180;
  return (-g * math.sin(r), g * math.cos(r));
}

void main() {
  group('LevelAngle.fromAccelerometer — 부호와 크기', () {
    test('곧게 세우면 0°', () {
      final (x, y) = tilt(0);
      expect(LevelAngle.fromAccelerometer(x, y), closeTo(0, 0.001));
    });

    test('시계방향 3.4° 기울이면 크기 3.4°', () {
      final (x, y) = tilt(3.4);
      expect(LevelAngle.fromAccelerometer(x, y).abs(), closeTo(3.4, 0.001));
    });

    test('기기가 시계방향으로 기울면 화면 각도는 **반시계**(음수) — 막대가 실제 수평을 가리키게', () {
      final (x, y) = tilt(10);
      expect(LevelAngle.fromAccelerometer(x, y), lessThan(0));
    });

    test('반시계로 기울이면 부호가 뒤집힌다', () {
      final (x, y) = tilt(-10);
      expect(LevelAngle.fromAccelerometer(x, y), greaterThan(0));
    });

    test('90° 기울임(가로) — x = -g, y = 0 검산', () {
      final (x, y) = tilt(90);
      expect(x, closeTo(-g, 0.001));
      expect(y, closeTo(0, 0.001));
      expect(LevelAngle.fromAccelerometer(x, y).abs(), closeTo(90, 0.001));
    });
  });

  group('LevelAngle.isReliable — 폰을 눕힌 구간', () {
    test('세운 상태는 신뢰', () {
      final (x, y) = tilt(5);
      expect(LevelAngle.isReliable(x, y), isTrue);
    });

    test('완전히 눕히면(중력이 z축으로) 신뢰하지 않는다 — atan2가 노이즈로 튄다', () {
      // 바닥에 놓으면 (x, y) ≈ (0, 0)이고 z에 g가 실린다.
      expect(LevelAngle.isReliable(0.1, -0.2), isFalse);
      expect(LevelAngle.fromAccelerometer(0.1, -0.2), 0);
    });

    test('경계 바로 위/아래', () {
      expect(LevelAngle.isReliable(LevelAngle.minPlanarMagnitude, 0), isTrue);
      expect(LevelAngle.isReliable(LevelAngle.minPlanarMagnitude - 0.01, 0), isFalse);
    });
  });

  group('LevelAngle.smooth — 경계 깜빡임 억제', () {
    test('한 프레임에 목표값으로 튀지 않는다', () {
      final next = LevelAngle.smooth(0, 10);
      expect(next, closeTo(10 * LevelAngle.smoothing, 0.0001));
      expect(next, lessThan(10));
    });

    test('반복하면 목표값으로 수렴한다', () {
      var v = 0.0;
      for (var i = 0; i < 200; i++) {
        v = LevelAngle.smooth(v, 10);
      }
      expect(v, closeTo(10, 0.01));
    });
  });

  group('LevelEvaluator와의 접합 — 실측 각도가 기존 임계값 로직에 그대로 들어간다', () {
    test('0.5° 기울임 → 여전히 초록(OK)', () {
      final (x, y) = tilt(0.5);
      final angle = LevelAngle.fromAccelerometer(x, y);
      expect(LevelEvaluator.evaluate(angle), isA<LevelOk>());
    });

    test('2° 기울임 → 주황(Tilted), 표시 각도는 절대값', () {
      final (x, y) = tilt(2);
      final angle = LevelAngle.fromAccelerometer(x, y);
      final state = LevelEvaluator.evaluate(angle);
      expect(state, isA<LevelTilted>());
      expect(state.angleDeg.abs(), closeTo(2, 0.001));
    });
  });
}
