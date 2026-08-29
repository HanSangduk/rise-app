// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dev_session.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(devSession)
const devSessionProvider = DevSessionProvider._();

final class DevSessionProvider
    extends $FunctionalProvider<DevSession, DevSession, DevSession>
    with $Provider<DevSession> {
  const DevSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'devSessionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$devSessionHash();

  @$internal
  @override
  $ProviderElement<DevSession> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DevSession create(Ref ref) {
    return devSession(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DevSession value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DevSession>(value),
    );
  }
}

String _$devSessionHash() => r'b9dbcba5da9198cae134fc1e96a3d46d9a3f197b';
