// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'records_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(recordsRepository)
const recordsRepositoryProvider = RecordsRepositoryProvider._();

final class RecordsRepositoryProvider
    extends
        $FunctionalProvider<
          RecordsRepository,
          RecordsRepository,
          RecordsRepository
        >
    with $Provider<RecordsRepository> {
  const RecordsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recordsRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recordsRepositoryHash();

  @$internal
  @override
  $ProviderElement<RecordsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RecordsRepository create(Ref ref) {
    return recordsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecordsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecordsRepository>(value),
    );
  }
}

String _$recordsRepositoryHash() => r'e2e631d11d4ef974408e62be0060cb7675b9062d';

@ProviderFor(RecordsViewModel)
const recordsViewModelProvider = RecordsViewModelProvider._();

final class RecordsViewModelProvider
    extends $AsyncNotifierProvider<RecordsViewModel, RecordsData> {
  const RecordsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recordsViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recordsViewModelHash();

  @$internal
  @override
  RecordsViewModel create() => RecordsViewModel();
}

String _$recordsViewModelHash() => r'69b937f0039ff83cf16912f9e8dd93c352b66128';

abstract class _$RecordsViewModel extends $AsyncNotifier<RecordsData> {
  FutureOr<RecordsData> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<RecordsData>, RecordsData>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<RecordsData>, RecordsData>,
              AsyncValue<RecordsData>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// 세그먼트 탭(운동/인바디/체형 분석) — 목업 seg-lw/li/lb.

@ProviderFor(SelectedRecordsTab)
const selectedRecordsTabProvider = SelectedRecordsTabProvider._();

/// 세그먼트 탭(운동/인바디/체형 분석) — 목업 seg-lw/li/lb.
final class SelectedRecordsTabProvider
    extends $NotifierProvider<SelectedRecordsTab, RecordsTab> {
  /// 세그먼트 탭(운동/인바디/체형 분석) — 목업 seg-lw/li/lb.
  const SelectedRecordsTabProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedRecordsTabProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedRecordsTabHash();

  @$internal
  @override
  SelectedRecordsTab create() => SelectedRecordsTab();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecordsTab value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecordsTab>(value),
    );
  }
}

String _$selectedRecordsTabHash() =>
    r'4aa4b1f19b7d8b96f40c03965dfdc674526441fd';

/// 세그먼트 탭(운동/인바디/체형 분석) — 목업 seg-lw/li/lb.

abstract class _$SelectedRecordsTab extends $Notifier<RecordsTab> {
  RecordsTab build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<RecordsTab, RecordsTab>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RecordsTab, RecordsTab>,
              RecordsTab,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
