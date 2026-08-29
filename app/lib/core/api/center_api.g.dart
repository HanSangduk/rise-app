// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'center_api.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(centerApi)
const centerApiProvider = CenterApiProvider._();

final class CenterApiProvider
    extends $FunctionalProvider<CenterApi, CenterApi, CenterApi>
    with $Provider<CenterApi> {
  const CenterApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'centerApiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$centerApiHash();

  @$internal
  @override
  $ProviderElement<CenterApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CenterApi create(Ref ref) {
    return centerApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CenterApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CenterApi>(value),
    );
  }
}

String _$centerApiHash() => r'eac7cc87059561fd4ed2fffc339c20e7d8c55d37';
