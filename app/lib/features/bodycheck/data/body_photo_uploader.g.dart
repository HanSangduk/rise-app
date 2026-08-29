// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'body_photo_uploader.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(bodyPhotoUploader)
const bodyPhotoUploaderProvider = BodyPhotoUploaderProvider._();

final class BodyPhotoUploaderProvider
    extends
        $FunctionalProvider<
          BodyPhotoUploader,
          BodyPhotoUploader,
          BodyPhotoUploader
        >
    with $Provider<BodyPhotoUploader> {
  const BodyPhotoUploaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bodyPhotoUploaderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bodyPhotoUploaderHash();

  @$internal
  @override
  $ProviderElement<BodyPhotoUploader> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BodyPhotoUploader create(Ref ref) {
    return bodyPhotoUploader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BodyPhotoUploader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BodyPhotoUploader>(value),
    );
  }
}

String _$bodyPhotoUploaderHash() => r'cc8da51a554baf1fe978b8ae3e21e97c2d7ff1b5';
