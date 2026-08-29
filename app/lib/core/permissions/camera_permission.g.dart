// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'camera_permission.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(cameraPermissionGate)
const cameraPermissionGateProvider = CameraPermissionGateProvider._();

final class CameraPermissionGateProvider
    extends
        $FunctionalProvider<
          CameraPermissionGate,
          CameraPermissionGate,
          CameraPermissionGate
        >
    with $Provider<CameraPermissionGate> {
  const CameraPermissionGateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cameraPermissionGateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cameraPermissionGateHash();

  @$internal
  @override
  $ProviderElement<CameraPermissionGate> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CameraPermissionGate create(Ref ref) {
    return cameraPermissionGate(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CameraPermissionGate value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CameraPermissionGate>(value),
    );
  }
}

String _$cameraPermissionGateHash() =>
    r'241aa89422f8d9afcdc380c4ac7d5779f99ee384';
