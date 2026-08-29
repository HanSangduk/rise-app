// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(homeRepository)
const homeRepositoryProvider = HomeRepositoryProvider._();

final class HomeRepositoryProvider
    extends $FunctionalProvider<HomeRepository, HomeRepository, HomeRepository>
    with $Provider<HomeRepository> {
  const HomeRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeRepositoryHash();

  @$internal
  @override
  $ProviderElement<HomeRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HomeRepository create(Ref ref) {
    return homeRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HomeRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HomeRepository>(value),
    );
  }
}

String _$homeRepositoryHash() => r'eef74aae2dad6138f50733cff2e9c6de68595af1';

@ProviderFor(HomeViewModel)
const homeViewModelProvider = HomeViewModelProvider._();

final class HomeViewModelProvider
    extends $AsyncNotifierProvider<HomeViewModel, HomeSummary> {
  const HomeViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeViewModelHash();

  @$internal
  @override
  HomeViewModel create() => HomeViewModel();
}

String _$homeViewModelHash() => r'0fc9e4e146644823b2d63c9d06ca5ac22eb1ef19';

abstract class _$HomeViewModel extends $AsyncNotifier<HomeSummary> {
  FutureOr<HomeSummary> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<HomeSummary>, HomeSummary>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<HomeSummary>, HomeSummary>,
              AsyncValue<HomeSummary>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Home Work 토글 실패 1회성 알림 — 홈 화면이 listen해 스낵바로 보여준 뒤 clear.

@ProviderFor(HomeworkToggleError)
const homeworkToggleErrorProvider = HomeworkToggleErrorProvider._();

/// Home Work 토글 실패 1회성 알림 — 홈 화면이 listen해 스낵바로 보여준 뒤 clear.
final class HomeworkToggleErrorProvider
    extends $NotifierProvider<HomeworkToggleError, Failure?> {
  /// Home Work 토글 실패 1회성 알림 — 홈 화면이 listen해 스낵바로 보여준 뒤 clear.
  const HomeworkToggleErrorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeworkToggleErrorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeworkToggleErrorHash();

  @$internal
  @override
  HomeworkToggleError create() => HomeworkToggleError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Failure? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Failure?>(value),
    );
  }
}

String _$homeworkToggleErrorHash() =>
    r'1c186eb9127e00424c6084d85cc3e4dd5a6b50a9';

/// Home Work 토글 실패 1회성 알림 — 홈 화면이 listen해 스낵바로 보여준 뒤 clear.

abstract class _$HomeworkToggleError extends $Notifier<Failure?> {
  Failure? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<Failure?, Failure?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Failure?, Failure?>,
              Failure?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// 셀프 체크인에 성공한 예약 id — 다음 예약 카드 버튼을 "체크인 완료"로 비활성.

@ProviderFor(CheckedInBookingId)
const checkedInBookingIdProvider = CheckedInBookingIdProvider._();

/// 셀프 체크인에 성공한 예약 id — 다음 예약 카드 버튼을 "체크인 완료"로 비활성.
final class CheckedInBookingIdProvider
    extends $NotifierProvider<CheckedInBookingId, String?> {
  /// 셀프 체크인에 성공한 예약 id — 다음 예약 카드 버튼을 "체크인 완료"로 비활성.
  const CheckedInBookingIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'checkedInBookingIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$checkedInBookingIdHash();

  @$internal
  @override
  CheckedInBookingId create() => CheckedInBookingId();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$checkedInBookingIdHash() =>
    r'5a2eebf4ae5471fa5bae8d8c39e3a5b59198d23a';

/// 셀프 체크인에 성공한 예약 id — 다음 예약 카드 버튼을 "체크인 완료"로 비활성.

abstract class _$CheckedInBookingId extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
