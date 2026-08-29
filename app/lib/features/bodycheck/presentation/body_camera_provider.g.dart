// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'body_camera_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 체형 촬영용 [CameraController] 수명주기 소유자.
///
/// **autoDispose인 게 핵심이다.** 촬영 탭은 `StatefulShellRoute.indexedStack`
/// 안에 있어 다른 탭으로 가도 위젯이 트리에 남는다(IndexedStack + maintainState).
/// 화면이 안 보일 때 이 provider를 watch하지 않으면 구독이 0이 되어 provider가
/// 버려지고, `ref.onDispose`가 카메라를 닫는다 — 홈 탭에서 카메라가 계속 켜져
/// 배터리를 먹고 기기가 뜨거워지는 걸 이 한 줄이 막는다(camera_screen.dart의
/// TickerMode 판정과 짝).

@ProviderFor(BodyCamera)
const bodyCameraProvider = BodyCameraProvider._();

/// 체형 촬영용 [CameraController] 수명주기 소유자.
///
/// **autoDispose인 게 핵심이다.** 촬영 탭은 `StatefulShellRoute.indexedStack`
/// 안에 있어 다른 탭으로 가도 위젯이 트리에 남는다(IndexedStack + maintainState).
/// 화면이 안 보일 때 이 provider를 watch하지 않으면 구독이 0이 되어 provider가
/// 버려지고, `ref.onDispose`가 카메라를 닫는다 — 홈 탭에서 카메라가 계속 켜져
/// 배터리를 먹고 기기가 뜨거워지는 걸 이 한 줄이 막는다(camera_screen.dart의
/// TickerMode 판정과 짝).
final class BodyCameraProvider
    extends $AsyncNotifierProvider<BodyCamera, BodyCameraState> {
  /// 체형 촬영용 [CameraController] 수명주기 소유자.
  ///
  /// **autoDispose인 게 핵심이다.** 촬영 탭은 `StatefulShellRoute.indexedStack`
  /// 안에 있어 다른 탭으로 가도 위젯이 트리에 남는다(IndexedStack + maintainState).
  /// 화면이 안 보일 때 이 provider를 watch하지 않으면 구독이 0이 되어 provider가
  /// 버려지고, `ref.onDispose`가 카메라를 닫는다 — 홈 탭에서 카메라가 계속 켜져
  /// 배터리를 먹고 기기가 뜨거워지는 걸 이 한 줄이 막는다(camera_screen.dart의
  /// TickerMode 판정과 짝).
  const BodyCameraProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bodyCameraProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bodyCameraHash();

  @$internal
  @override
  BodyCamera create() => BodyCamera();
}

String _$bodyCameraHash() => r'2e1b02c0c7aee7e88e371f16e736df5ee48aa1e3';

/// 체형 촬영용 [CameraController] 수명주기 소유자.
///
/// **autoDispose인 게 핵심이다.** 촬영 탭은 `StatefulShellRoute.indexedStack`
/// 안에 있어 다른 탭으로 가도 위젯이 트리에 남는다(IndexedStack + maintainState).
/// 화면이 안 보일 때 이 provider를 watch하지 않으면 구독이 0이 되어 provider가
/// 버려지고, `ref.onDispose`가 카메라를 닫는다 — 홈 탭에서 카메라가 계속 켜져
/// 배터리를 먹고 기기가 뜨거워지는 걸 이 한 줄이 막는다(camera_screen.dart의
/// TickerMode 판정과 짝).

abstract class _$BodyCamera extends $AsyncNotifier<BodyCameraState> {
  FutureOr<BodyCameraState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<BodyCameraState>, BodyCameraState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<BodyCameraState>, BodyCameraState>,
              AsyncValue<BodyCameraState>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
