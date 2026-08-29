// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'passes_api.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(passesApi)
const passesApiProvider = PassesApiProvider._();

final class PassesApiProvider
    extends $FunctionalProvider<PassesApi, PassesApi, PassesApi>
    with $Provider<PassesApi> {
  const PassesApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'passesApiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$passesApiHash();

  @$internal
  @override
  $ProviderElement<PassesApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PassesApi create(Ref ref) {
    return passesApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PassesApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PassesApi>(value),
    );
  }
}

String _$passesApiHash() => r'd9534bf251757ffa61eccc8db8bb01aa3363104f';
