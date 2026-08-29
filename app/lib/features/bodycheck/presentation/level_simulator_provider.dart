import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/features/bodycheck/domain/level_angle.dart';
import 'package:sensors_plus/sensors_plus.dart';

part 'level_simulator_provider.g.dart';

/// 가속도계 이벤트 스트림을 여는 함수.
typedef AccelerometerSource = Stream<AccelerometerEvent> Function();

/// 센서 소스를 provider로 한 겹 빼는 이유는 두 가지다.
///
/// ① **테스트에서 합성 이벤트를 흘려 넣기 위해** — 각도 파이프라인(원값 → 평활 →
///    임계값)을 실기기 없이 검증할 수 있다.
/// ② **테스트가 진짜 플러그인을 건드리면 터지기 때문** — sensors_plus는
///    `accelerometerEventStream()` 안에서 `invokeMethod('setAccelerationSamplingPeriod')`를
///    **await 없이** 호출한다(sensors_plus_platform_interface 2.0.2,
///    method_channel_sensors.dart:55). 플러그인이 없는 환경에서 그 Future가 거부되면
///    아무도 잡지 않는 비동기 예외가 되고, 호출부의 try/catch로는 막을 수 없다
///    (동기 구간을 이미 벗어난 뒤에 터진다).
///
/// 샘플링 주기는 uiInterval(≈16.7ms) — 수평계는 눈으로 따라가는 지표라 UI 주기면
/// 충분하고, gameInterval(≈10ms)까지 올리면 배터리만 더 먹는다.
@riverpod
AccelerometerSource accelerometerSource(Ref ref) =>
    () => accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval);

/// 수평계 각도 소스 — 가속도계 실측(1순위) + 수동 시뮬 토글(폴백).
///
/// 각도 계산은 [LevelAngle](순수 도메인)이 하고, 이 provider는 **입력 소스**와
/// 스트림 수명주기만 담당한다. 판정(각도 → 초록/주황)은 종전대로 LevelEvaluator가
/// 그대로 하므로 기존 도메인 테스트는 한 줄도 손대지 않았다.
///
/// 이름은 [LevelSimulator] 그대로 둔다. 공개 API(`build` / `toggleTiltDemo`)와
/// provider 이름이 화면에 이미 박혀 있고, 시뮬 토글은 **없어지지 않았다** —
/// 가속도계가 없는 에뮬레이터·시뮬레이터에서 수평계 UI를 확인하는 유일한 길이다.
///
/// 수명주기: `@riverpod`(autoDispose)라 카메라 화면이 구독을 놓으면 provider가
/// 버려지고 `ref.onDispose`가 스트림을 끊는다. 촬영 탭을 벗어난 뒤에도 가속도계가
/// 돌아 배터리를 먹는 일이 없도록, 화면 쪽에서도 보이지 않는 동안에는 watch하지
/// 않는다(camera_screen.dart의 TickerMode 주석).
@riverpod
class LevelSimulator extends _$LevelSimulator {
  StreamSubscription<AccelerometerEvent>? _sub;

  /// 수동 시뮬을 켜 둔 동안에는 센서 값을 무시한다 — 안 그러면 버튼을 눌러도
  /// 다음 센서 프레임(16ms 뒤)이 곧바로 덮어써 아무 일도 안 일어난 것처럼 보인다.
  bool _manual = false;

  /// 센서가 아예 없거나 스트림이 에러로 끝난 환경(테스트·에뮬레이터·데스크톱).
  bool _sensorUnavailable = false;

  @override
  double build() {
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    _listen();
    return 0.0;
  }

  void _listen() {
    try {
      _sub = ref.read(accelerometerSourceProvider)().listen(
        _onEvent,
        onError: (Object _) {
          // 센서 미탑재/채널 오류 — 조용히 수동 모드로 떨어진다(화면은 계속 돈다).
          _sensorUnavailable = true;
          _sub?.cancel();
          _sub = null;
        },
        cancelOnError: true,
      );
    } catch (_) {
      // 스트림 생성 자체가 실패(플러그인 없음) — 수동 모드.
      _sensorUnavailable = true;
    }
  }

  void _onEvent(AccelerometerEvent event) {
    if (_manual) return;
    if (!LevelAngle.isReliable(event.x, event.y)) return; // 눕힌 구간은 직전 값 유지.
    final target = LevelAngle.fromAccelerometer(event.x, event.y);
    final next = LevelAngle.smooth(state, target);
    if ((next - state).abs() < LevelAngle.updateEpsilonDeg) return;
    state = next;
  }

  /// 목업 "기울기 시뮬" 버튼.
  ///
  /// 실기기에서는 **센서 값을 잠그는 토글**로 동작한다: 켜면 3.4°(목업 데모 값)로
  /// 고정해 주황 상태를 확인할 수 있고, 다시 누르면 센서로 복귀한다.
  /// 센서가 없는 환경에서는 종전과 똑같이 0° ↔ 3.4° 토글이다.
  void toggleTiltDemo() {
    if (_sensorUnavailable) {
      state = state == 0.0 ? 3.4 : 0.0;
      return;
    }
    _manual = !_manual;
    // 해제 시 0으로 두면 다음 센서 프레임(16ms)이 곧바로 실측값으로 덮는다.
    state = _manual ? 3.4 : 0.0;
  }
}
