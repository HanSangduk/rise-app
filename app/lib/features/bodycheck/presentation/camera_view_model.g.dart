// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'camera_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 셔터 → 실촬영 → Firebase Storage 업로드 → `POST /v1/body-photos`.

@ProviderFor(CameraViewModel)
const cameraViewModelProvider = CameraViewModelProvider._();

/// 셔터 → 실촬영 → Firebase Storage 업로드 → `POST /v1/body-photos`.
final class CameraViewModelProvider
    extends $NotifierProvider<CameraViewModel, CameraState> {
  /// 셔터 → 실촬영 → Firebase Storage 업로드 → `POST /v1/body-photos`.
  const CameraViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cameraViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cameraViewModelHash();

  @$internal
  @override
  CameraViewModel create() => CameraViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CameraState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CameraState>(value),
    );
  }
}

String _$cameraViewModelHash() => r'd81e53fb0c96c5a0668e36826d1f5e18a8c9b4cc';

/// 셔터 → 실촬영 → Firebase Storage 업로드 → `POST /v1/body-photos`.

abstract class _$CameraViewModel extends $Notifier<CameraState> {
  CameraState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<CameraState, CameraState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CameraState, CameraState>,
              CameraState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
