// 순수 도메인 — 가속도계 원값 → 수평계 각도. Flutter/센서 패키지 의존 0(테스트 대상).

import 'dart:math' as math;

/// 가속도계 raw (x, y) → 화면 수평 막대에 그대로 먹일 각도(도).
///
/// 좌표계(Android 규약, sensors_plus는 iOS도 여기에 맞춰준다):
/// x = 화면 오른쪽, y = 화면 위쪽, z = 화면 바깥. 폰을 세로로 곧게 세우면
/// 중력 반작용이 y축에 실려 `(0, +9.81, 0)`이 나온다.
///
/// 폰을 시계방향(윗변이 오른쪽으로)으로 θ만큼 기울이면 `x = -g·sinθ, y = g·cosθ`다
/// (θ=90°에서 `x = -g, y = 0`으로 검산됨). 따라서 **기기의** 시계방향 기울기는
/// `atan2(-x, y)`인데, [fromAccelerometer]는 그 부호를 뒤집은 `atan2(x, y)`를
/// 돌려준다 — `LevelIndicator`가 이 값을 `Transform.rotate`(양수 = 시계방향)에
/// 그대로 넣기 때문이다. 기기가 시계방향으로 기울 때 막대를 반시계로 같은 각만큼
/// 돌려야 막대가 **실제 수평**을 가리킨다. 목업 위젯을 한 줄도 안 고치고 물리적으로
/// 옳게 만드는 유일한 부호다.
///
/// 상태 판정([LevelEvaluator])과 각도 표기는 둘 다 `abs()`라 부호에 무관하다.
///
/// z축(폰을 눕히는 방향)은 쓰지 않는다 — 체형 촬영은 폰을 세워 두고 좌우 롤만
/// 보정하는 자리고, 완전히 눕히면 x·y가 둘 다 0에 수렴해 atan2가 노이즈로 튄다.
/// 그 구간은 [isReliable]로 걸러 직전 값을 유지한다.
abstract final class LevelAngle {
  /// x·y 합성 크기가 이보다 작으면(≈ 폰을 바닥에 눕힘) 각도를 신뢰하지 않는다.
  /// 중력 9.81 m/s²의 약 1/4.
  static const minPlanarMagnitude = 2.5;

  static bool isReliable(double x, double y) =>
      math.sqrt(x * x + y * y) >= minPlanarMagnitude;

  /// [isReliable]이 false면 0을 준다 — 호출부가 이 값을 쓰지 않고 직전 값을
  /// 유지하는 게 정상 경로다(0을 "수평"으로 오인해 쓰지 말 것).
  static double fromAccelerometer(double x, double y) {
    if (!isReliable(x, y)) return 0;
    return math.atan2(x, y) * 180 / math.pi;
  }

  /// 저역통과 계수 — 손떨림 때문에 각도가 1° 경계를 초당 수십 번 넘나들며
  /// 초록/주황이 깜빡이는 걸 막는다. 0.18은 60Hz에서 약 0.1초 시상수.
  static const smoothing = 0.18;

  static double smooth(double previous, double next) =>
      previous + (next - previous) * smoothing;

  /// 이만큼 안 움직이면 state를 갱신하지 않는다 — 60Hz를 그대로 흘리면
  /// 카메라 화면 전체가 초당 60번 리빌드된다.
  static const updateEpsilonDeg = 0.05;
}
