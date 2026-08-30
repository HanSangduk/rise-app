// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'my_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(myRepository)
const myRepositoryProvider = MyRepositoryProvider._();

final class MyRepositoryProvider
    extends $FunctionalProvider<MyRepository, MyRepository, MyRepository>
    with $Provider<MyRepository> {
  const MyRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myRepositoryHash();

  @$internal
  @override
  $ProviderElement<MyRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MyRepository create(Ref ref) {
    return myRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MyRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MyRepository>(value),
    );
  }
}

String _$myRepositoryHash() => r'53b8e1e460d26c5cd754a78266727048caabec2e';

@ProviderFor(MyViewModel)
const myViewModelProvider = MyViewModelProvider._();

final class MyViewModelProvider
    extends $AsyncNotifierProvider<MyViewModel, MySummary> {
  const MyViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myViewModelHash();

  @$internal
  @override
  MyViewModel create() => MyViewModel();
}

String _$myViewModelHash() => r'75e0d019b0f0e7cf06d762d7a58735817a0a4ab3';

abstract class _$MyViewModel extends $AsyncNotifier<MySummary> {
  FutureOr<MySummary> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<MySummary>, MySummary>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<MySummary>, MySummary>,
              AsyncValue<MySummary>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// 마이 탭 원장 카드에서 선택된 패스 id(null = 대표 패스) —
/// 패스가 2개 이상일 때 칩으로 원장을 전환한다.

@ProviderFor(SelectedLedgerPassId)
const selectedLedgerPassIdProvider = SelectedLedgerPassIdProvider._();

/// 마이 탭 원장 카드에서 선택된 패스 id(null = 대표 패스) —
/// 패스가 2개 이상일 때 칩으로 원장을 전환한다.
final class SelectedLedgerPassIdProvider
    extends $NotifierProvider<SelectedLedgerPassId, String?> {
  /// 마이 탭 원장 카드에서 선택된 패스 id(null = 대표 패스) —
  /// 패스가 2개 이상일 때 칩으로 원장을 전환한다.
  const SelectedLedgerPassIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedLedgerPassIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedLedgerPassIdHash();

  @$internal
  @override
  SelectedLedgerPassId create() => SelectedLedgerPassId();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$selectedLedgerPassIdHash() =>
    r'7fb0ae835f14403498772fb56daf5c40807bd59e';

/// 마이 탭 원장 카드에서 선택된 패스 id(null = 대표 패스) —
/// 패스가 2개 이상일 때 칩으로 원장을 전환한다.

abstract class _$SelectedLedgerPassId extends $Notifier<String?> {
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
