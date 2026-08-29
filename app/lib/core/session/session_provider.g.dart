// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 로그인 세션 — 로그인 플로우(join/confirm) 완료 시 채워지고,
/// 셸(홈/예약/촬영/기록/마이) 이하 모든 화면이 memberId를 여기서 읽는다.
/// keepAlive: 화면 전환 사이 구독이 잠시 끊겨도 세션이 유실되지 않아야 한다
/// (autoDispose면 로그인 직후 라우팅 레이스로 세션이 사라질 수 있음).

@ProviderFor(Session)
const sessionProvider = SessionProvider._();

/// 로그인 세션 — 로그인 플로우(join/confirm) 완료 시 채워지고,
/// 셸(홈/예약/촬영/기록/마이) 이하 모든 화면이 memberId를 여기서 읽는다.
/// keepAlive: 화면 전환 사이 구독이 잠시 끊겨도 세션이 유실되지 않아야 한다
/// (autoDispose면 로그인 직후 라우팅 레이스로 세션이 사라질 수 있음).
final class SessionProvider extends $NotifierProvider<Session, AppSession?> {
  /// 로그인 세션 — 로그인 플로우(join/confirm) 완료 시 채워지고,
  /// 셸(홈/예약/촬영/기록/마이) 이하 모든 화면이 memberId를 여기서 읽는다.
  /// keepAlive: 화면 전환 사이 구독이 잠시 끊겨도 세션이 유실되지 않아야 한다
  /// (autoDispose면 로그인 직후 라우팅 레이스로 세션이 사라질 수 있음).
  const SessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionHash();

  @$internal
  @override
  Session create() => Session();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppSession? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppSession?>(value),
    );
  }
}

String _$sessionHash() => r'6193bfc2dde97ded0235116f1b8d0de25e4580d3';

/// 로그인 세션 — 로그인 플로우(join/confirm) 완료 시 채워지고,
/// 셸(홈/예약/촬영/기록/마이) 이하 모든 화면이 memberId를 여기서 읽는다.
/// keepAlive: 화면 전환 사이 구독이 잠시 끊겨도 세션이 유실되지 않아야 한다
/// (autoDispose면 로그인 직후 라우팅 레이스로 세션이 사라질 수 있음).

abstract class _$Session extends $Notifier<AppSession?> {
  AppSession? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AppSession?, AppSession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppSession?, AppSession?>,
              AppSession?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
