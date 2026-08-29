// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'body_check_repository_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 체형 사진 리포지토리 — **두 feature가 함께 쓴다**(촬영 탭이 쓰고, 기록 탭이 읽는다).
///
/// 원래 `presentation/camera_view_model.dart` 안에 있었다. 그래서
/// `records_view_model.dart`가 이 provider 하나 때문에 **촬영 탭의 뷰모델 파일을
/// import**했고, 반대 방향(업로드 성공 → 기록 탭 무효화)이 순환이 되어 막혔다.
/// 소비자가 둘인 provider는 어느 한쪽 화면의 뷰모델 파일이 아니라 data 레이어에 둔다.

@ProviderFor(bodyCheckRepository)
const bodyCheckRepositoryProvider = BodyCheckRepositoryProvider._();

/// 체형 사진 리포지토리 — **두 feature가 함께 쓴다**(촬영 탭이 쓰고, 기록 탭이 읽는다).
///
/// 원래 `presentation/camera_view_model.dart` 안에 있었다. 그래서
/// `records_view_model.dart`가 이 provider 하나 때문에 **촬영 탭의 뷰모델 파일을
/// import**했고, 반대 방향(업로드 성공 → 기록 탭 무효화)이 순환이 되어 막혔다.
/// 소비자가 둘인 provider는 어느 한쪽 화면의 뷰모델 파일이 아니라 data 레이어에 둔다.

final class BodyCheckRepositoryProvider
    extends
        $FunctionalProvider<
          BodyCheckRepository,
          BodyCheckRepository,
          BodyCheckRepository
        >
    with $Provider<BodyCheckRepository> {
  /// 체형 사진 리포지토리 — **두 feature가 함께 쓴다**(촬영 탭이 쓰고, 기록 탭이 읽는다).
  ///
  /// 원래 `presentation/camera_view_model.dart` 안에 있었다. 그래서
  /// `records_view_model.dart`가 이 provider 하나 때문에 **촬영 탭의 뷰모델 파일을
  /// import**했고, 반대 방향(업로드 성공 → 기록 탭 무효화)이 순환이 되어 막혔다.
  /// 소비자가 둘인 provider는 어느 한쪽 화면의 뷰모델 파일이 아니라 data 레이어에 둔다.
  const BodyCheckRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bodyCheckRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bodyCheckRepositoryHash();

  @$internal
  @override
  $ProviderElement<BodyCheckRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BodyCheckRepository create(Ref ref) {
    return bodyCheckRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BodyCheckRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BodyCheckRepository>(value),
    );
  }
}

String _$bodyCheckRepositoryHash() =>
    r'a18f504fd405439350b174fa14e6bced3b88f2dc';
