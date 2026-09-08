// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lobby_auto_check.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 대기실 자동 확인의 기본 간격(P69 H1). **`null`이면 자동 확인 전체가 꺼진다** — 마운트 즉시
/// 1회도 없다.
///
/// provider로 둔 이유는 위젯 테스트다(plan C 3-e): `pumpAndSettle`은 살아 있는 타이머가 있는
/// 한 절대 settle되지 않아, 주기 타이머 하나가 대기실 테스트 31건을 전부 타임아웃시킨다. 테스트
/// 하네스가 `overrideWithValue(null)` 한 줄로 끄고, 자동 확인 전용 테스트만 `tester.pump(30s)`로
/// 틱을 진행한다. `centerContactProvider`의 `retry: _noRetry`와 같은 교훈이다.

@ProviderFor(lobbyAutoCheckInterval)
const lobbyAutoCheckIntervalProvider = LobbyAutoCheckIntervalProvider._();

/// 대기실 자동 확인의 기본 간격(P69 H1). **`null`이면 자동 확인 전체가 꺼진다** — 마운트 즉시
/// 1회도 없다.
///
/// provider로 둔 이유는 위젯 테스트다(plan C 3-e): `pumpAndSettle`은 살아 있는 타이머가 있는
/// 한 절대 settle되지 않아, 주기 타이머 하나가 대기실 테스트 31건을 전부 타임아웃시킨다. 테스트
/// 하네스가 `overrideWithValue(null)` 한 줄로 끄고, 자동 확인 전용 테스트만 `tester.pump(30s)`로
/// 틱을 진행한다. `centerContactProvider`의 `retry: _noRetry`와 같은 교훈이다.

final class LobbyAutoCheckIntervalProvider
    extends $FunctionalProvider<Duration?, Duration?, Duration?>
    with $Provider<Duration?> {
  /// 대기실 자동 확인의 기본 간격(P69 H1). **`null`이면 자동 확인 전체가 꺼진다** — 마운트 즉시
  /// 1회도 없다.
  ///
  /// provider로 둔 이유는 위젯 테스트다(plan C 3-e): `pumpAndSettle`은 살아 있는 타이머가 있는
  /// 한 절대 settle되지 않아, 주기 타이머 하나가 대기실 테스트 31건을 전부 타임아웃시킨다. 테스트
  /// 하네스가 `overrideWithValue(null)` 한 줄로 끄고, 자동 확인 전용 테스트만 `tester.pump(30s)`로
  /// 틱을 진행한다. `centerContactProvider`의 `retry: _noRetry`와 같은 교훈이다.
  const LobbyAutoCheckIntervalProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lobbyAutoCheckIntervalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lobbyAutoCheckIntervalHash();

  @$internal
  @override
  $ProviderElement<Duration?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration? create(Ref ref) {
    return lobbyAutoCheckInterval(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration?>(value),
    );
  }
}

String _$lobbyAutoCheckIntervalHash() =>
    r'e125b2229ee081fd6fc6e426f12107c7edd7870f';
