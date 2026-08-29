// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'body_photo_loader.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(bodyPhotoLoader)
const bodyPhotoLoaderProvider = BodyPhotoLoaderProvider._();

final class BodyPhotoLoaderProvider
    extends
        $FunctionalProvider<BodyPhotoLoader, BodyPhotoLoader, BodyPhotoLoader>
    with $Provider<BodyPhotoLoader> {
  const BodyPhotoLoaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bodyPhotoLoaderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bodyPhotoLoaderHash();

  @$internal
  @override
  $ProviderElement<BodyPhotoLoader> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BodyPhotoLoader create(Ref ref) {
    return bodyPhotoLoader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BodyPhotoLoader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BodyPhotoLoader>(value),
    );
  }
}

String _$bodyPhotoLoaderHash() => r'4a5e10338df47ffea067ff8a45145643f39e7ea4';
