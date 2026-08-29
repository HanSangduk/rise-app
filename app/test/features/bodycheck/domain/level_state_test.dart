import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/bodycheck/domain/level_state.dart';

// 순수 도메인 — 체형 분석 카메라 수평계. 규칙: |각도| < 1°면 초록(OK), 아니면 주황(Tilted).
void main() {
  group('LevelEvaluator.evaluate', () {
    test('각도 0° → LevelOk', () {
      expect(LevelEvaluator.evaluate(0), isA<LevelOk>());
    });

    test('경계 바로 아래(0.99°) → LevelOk', () {
      expect(LevelEvaluator.evaluate(0.99), isA<LevelOk>());
      expect(LevelEvaluator.evaluate(-0.99), isA<LevelOk>());
    });

    test('경계값(1.0°) → LevelTilted (임계값은 미만만 OK)', () {
      expect(LevelEvaluator.evaluate(1.0), isA<LevelTilted>());
    });

    test('기울음 3.4°(목업 시뮬 값) → LevelTilted', () {
      final state = LevelEvaluator.evaluate(3.4);
      expect(state, isA<LevelTilted>());
      expect(state.angleDeg, 3.4);
    });

    test('음수 기울음(-2.0°)도 절대값 기준으로 LevelTilted', () {
      expect(LevelEvaluator.evaluate(-2.0), isA<LevelTilted>());
    });
  });
}
