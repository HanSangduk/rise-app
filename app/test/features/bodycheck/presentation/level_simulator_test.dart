import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/bodycheck/domain/level_state.dart';
import 'package:rise_member/features/bodycheck/presentation/level_simulator_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

// 수평계 입력 소스 교체(버튼 → 가속도계) 회귀.
//
// 검증 관심사는 셋이다:
//   ① 센서 없는 환경(테스트·에뮬레이터)에서 **앱이 죽지 않는다**.
//   ② 실제 이벤트가 들어오면 기존 임계값 로직(LevelEvaluator, ±1°)에 그대로 먹는다.
//   ③ 구독 수명주기 — 화면이 놓으면 스트림이 확실히 끊긴다(배터리·발열).
void main() {
  AccelerometerEvent event(double x, double y) =>
      AccelerometerEvent(x, y, 0, DateTime(2026, 8, 23));

  group('센서가 없는 환경', () {
    ProviderContainer noSensor() => ProviderContainer.test(
          overrides: [
            // 스트림 생성 자체가 실패하는 상황(플러그인 미등록)을 그대로 재현.
            accelerometerSourceProvider.overrideWithValue(
              () => throw StateError('no sensor plugin'),
            ),
          ],
        );

    test('provider 생성이 예외를 던지지 않고 0°로 시작한다', () {
      final container = noSensor();
      expect(() => container.read(levelSimulatorProvider), returnsNormally);
      expect(container.read(levelSimulatorProvider), 0.0);
    });

    test('시뮬 토글이 종전 목업 동작(0° ↔ 3.4°)으로 남는다', () {
      final container = noSensor();
      final notifier = container.read(levelSimulatorProvider.notifier);

      notifier.toggleTiltDemo();
      expect(container.read(levelSimulatorProvider), 3.4);
      notifier.toggleTiltDemo();
      expect(container.read(levelSimulatorProvider), 0.0);
    });

    test('스트림이 에러로 끝나도(런타임 센서 오류) 죽지 않고 수동 모드로 떨어진다', () async {
      final controller = StreamController<AccelerometerEvent>();
      final container = ProviderContainer.test(
        overrides: [
          accelerometerSourceProvider.overrideWithValue(() => controller.stream),
        ],
      );
      final sub = container.listen(levelSimulatorProvider, (_, __) {});
      addTearDown(sub.close);

      controller.addError(StateError('sensor died'));
      await Future<void>.delayed(Duration.zero);

      final notifier = container.read(levelSimulatorProvider.notifier);
      notifier.toggleTiltDemo();
      expect(container.read(levelSimulatorProvider), 3.4);
      await controller.close();
    });
  });

  group('실 가속도계 이벤트 → 기존 임계값 로직', () {
    late StreamController<AccelerometerEvent> sensor;
    late ProviderContainer container;
    late ProviderSubscription<double> sub;

    setUp(() {
      sensor = StreamController<AccelerometerEvent>.broadcast();
      container = ProviderContainer.test(
        overrides: [
          accelerometerSourceProvider.overrideWithValue(() => sensor.stream),
        ],
      );
      sub = container.listen(levelSimulatorProvider, (_, __) {});
    });

    tearDown(() async {
      sub.close();
      await sensor.close();
    });

    /// 평활(저역통과) 때문에 한 프레임으로는 목표에 못 닿는다 — 실제 60Hz 스트림처럼
    /// 같은 자세를 여러 프레임 흘려 수렴시킨다.
    Future<void> hold(double x, double y, {int frames = 120}) async {
      for (var i = 0; i < frames; i++) {
        sensor.add(event(x, y));
      }
      await Future<void>.delayed(Duration.zero);
    }

    test('곧게 세운 자세(0, 9.81)는 초록(LevelOk)', () async {
      await hold(0, 9.81);
      final state = LevelEvaluator.evaluate(container.read(levelSimulatorProvider));
      expect(state, isA<LevelOk>());
    });

    test('좌우로 기울이면 주황(LevelTilted)이 되고 각도가 실측을 따라간다', () async {
      // 시계방향 약 10° — x = -g·sin10°, y = g·cos10°.
      await hold(-1.7036, 9.6608);
      final angle = container.read(levelSimulatorProvider);

      expect(angle.abs(), closeTo(10, 0.5));
      expect(LevelEvaluator.evaluate(angle), isA<LevelTilted>());
    });

    test('폰을 눕히면(x·y ≈ 0) 각도가 튀지 않고 직전 값을 유지한다', () async {
      await hold(-1.7036, 9.6608);
      final tilted = container.read(levelSimulatorProvider);

      await hold(0.05, -0.02); // 바닥에 눕힘 — 중력이 z축으로.
      expect(container.read(levelSimulatorProvider), tilted);
    });

    test('시뮬을 켜 두면 센서 값이 덮어쓰지 않는다', () async {
      container.read(levelSimulatorProvider.notifier).toggleTiltDemo();
      expect(container.read(levelSimulatorProvider), 3.4);

      await hold(0, 9.81);
      expect(container.read(levelSimulatorProvider), 3.4);

      // 다시 누르면 센서로 복귀.
      container.read(levelSimulatorProvider.notifier).toggleTiltDemo();
      await hold(-1.7036, 9.6608);
      expect(container.read(levelSimulatorProvider).abs(), closeTo(10, 0.5));
    });
  });

  test('구독을 놓으면 스트림이 끊긴다 — 탭을 벗어난 뒤 가속도계가 계속 돌지 않게', () async {
    final sensor = StreamController<AccelerometerEvent>.broadcast();
    final container = ProviderContainer.test(
      overrides: [
        accelerometerSourceProvider.overrideWithValue(() => sensor.stream),
      ],
    );

    final sub = container.listen(levelSimulatorProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    expect(sensor.hasListener, isTrue);

    sub.close();
    await Future<void>.delayed(Duration.zero);

    expect(sensor.hasListener, isFalse, reason: 'onDispose가 구독을 취소해야 한다');
    await sensor.close();
  });
}
