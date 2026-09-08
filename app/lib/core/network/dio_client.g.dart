// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dio_client.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 공용 Dio 클라이언트 — 인증 헤더 인터셉터 포함.
/// dev 모드: `X-Dev-Role` / `X-Dev-Uid`. 운영: `Authorization: Bearer <Firebase ID token>`.

@ProviderFor(dio)
const dioProvider = DioProvider._();

/// 공용 Dio 클라이언트 — 인증 헤더 인터셉터 포함.
/// dev 모드: `X-Dev-Role` / `X-Dev-Uid`. 운영: `Authorization: Bearer <Firebase ID token>`.

final class DioProvider extends $FunctionalProvider<Dio, Dio, Dio>
    with $Provider<Dio> {
  /// 공용 Dio 클라이언트 — 인증 헤더 인터셉터 포함.
  /// dev 모드: `X-Dev-Role` / `X-Dev-Uid`. 운영: `Authorization: Bearer <Firebase ID token>`.
  const DioProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dioProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dioHash();

  @$internal
  @override
  $ProviderElement<Dio> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Dio create(Ref ref) {
    return dio(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Dio value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Dio>(value),
    );
  }
}

String _$dioHash() => r'10aeafb189cd89f4d3fe46cf19b5779abac87e9d';
