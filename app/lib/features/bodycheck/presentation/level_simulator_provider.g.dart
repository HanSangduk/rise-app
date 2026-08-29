// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'level_simulator_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(accelerometerSource)
const accelerometerSourceProvider = AccelerometerSourceProvider._();

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

final class AccelerometerSourceProvider
    extends
        $FunctionalProvider<
          AccelerometerSource,
          AccelerometerSource,
          AccelerometerSource
        >
    with $Provider<AccelerometerSource> {
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
  const AccelerometerSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accelerometerSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accelerometerSourceHash();

  @$internal
  @override
  $ProviderElement<AccelerometerSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AccelerometerSource create(Ref ref) {
    return accelerometerSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccelerometerSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccelerometerSource>(value),
    );
  }
}

String _$accelerometerSourceHash() =>
    r'b1fdf1382af96805b316c842dc02b67c1da2fe11';

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

@ProviderFor(LevelSimulator)
const levelSimulatorProvider = LevelSimulatorProvider._();

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
final class LevelSimulatorProvider
    extends $NotifierProvider<LevelSimulator, double> {
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
  const LevelSimulatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'levelSimulatorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$levelSimulatorHash();

  @$internal
  @override
  LevelSimulator create() => LevelSimulator();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$levelSimulatorHash() => r'1e40d88956cb42f2289986e706fcb8d926f154d1';

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

abstract class _$LevelSimulator extends $Notifier<double> {
  double build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<double, double>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<double, double>,
              double,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
