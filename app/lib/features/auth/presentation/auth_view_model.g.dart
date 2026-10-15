// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(authRepository)
const authRepositoryProvider = AuthRepositoryProvider._();

final class AuthRepositoryProvider
    extends $FunctionalProvider<AuthRepository, AuthRepository, AuthRepository>
    with $Provider<AuthRepository> {
  const AuthRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authRepositoryHash();

  @$internal
  @override
  $ProviderElement<AuthRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AuthRepository create(Ref ref) {
    return authRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthRepository>(value),
    );
  }
}

String _$authRepositoryHash() => r'7657082ba639a78d100aa589265d857878f9bb63';

/// 코드 화면이 "로그인이 방금 끝났다"를 알아채는 유일한 통로 —
/// 안드로이드 SMS 자동 회수가 `codeSent` **이후** 도착하는 정상 흐름을 잡는다.
/// (구독 시점의 기존 세션은 흘러오지 않는다 — [AuthRepository.signedInPhoneChanges].)
///
/// autoDispose인 채로 둔다: 구독자는 코드 화면 하나뿐이고, 그 화면이 사라지면
/// Firebase 스트림 구독까지 함께 정리돼야 한다(수명주기는 화면이 소유).

@ProviderFor(signedInPhone)
const signedInPhoneProvider = SignedInPhoneProvider._();

/// 코드 화면이 "로그인이 방금 끝났다"를 알아채는 유일한 통로 —
/// 안드로이드 SMS 자동 회수가 `codeSent` **이후** 도착하는 정상 흐름을 잡는다.
/// (구독 시점의 기존 세션은 흘러오지 않는다 — [AuthRepository.signedInPhoneChanges].)
///
/// autoDispose인 채로 둔다: 구독자는 코드 화면 하나뿐이고, 그 화면이 사라지면
/// Firebase 스트림 구독까지 함께 정리돼야 한다(수명주기는 화면이 소유).

final class SignedInPhoneProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, Stream<String?>>
    with $FutureModifier<String?>, $StreamProvider<String?> {
  /// 코드 화면이 "로그인이 방금 끝났다"를 알아채는 유일한 통로 —
  /// 안드로이드 SMS 자동 회수가 `codeSent` **이후** 도착하는 정상 흐름을 잡는다.
  /// (구독 시점의 기존 세션은 흘러오지 않는다 — [AuthRepository.signedInPhoneChanges].)
  ///
  /// autoDispose인 채로 둔다: 구독자는 코드 화면 하나뿐이고, 그 화면이 사라지면
  /// Firebase 스트림 구독까지 함께 정리돼야 한다(수명주기는 화면이 소유).
  const SignedInPhoneProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'signedInPhoneProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$signedInPhoneHash();

  @$internal
  @override
  $StreamProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<String?> create(Ref ref) {
    return signedInPhone(ref);
  }
}

String _$signedInPhoneHash() => r'6cb8e510f5d1a44a9a5418861a943889fecb1fa0';

/// 가입 요청을 보낼 수 있는 센터 목록(계약 v2.33).
///
/// **고를 것이 2곳 이상일 때만 화면이 선택을 묻는다**(`hasChoice`). 센터가 하나뿐인데 선택
/// 화면을 띄우면 회원에게 "고를 수 있다"는 거짓 인상을 주고 탭만 하나 늘린다.
///
/// 실패는 **빈 목록으로 접는다** — 이 조회가 실패했다고 가입 요청 자체를 막으면 안 된다.
/// 센터 없이 보낸 요청은 서버가 기본 센터로 폴백하므로(v2.33) 종전 동작이 그대로 남는다.
/// autoDispose: 대기실을 떠나면 필요 없다.

@ProviderFor(joinCenters)
const joinCentersProvider = JoinCentersProvider._();

/// 가입 요청을 보낼 수 있는 센터 목록(계약 v2.33).
///
/// **고를 것이 2곳 이상일 때만 화면이 선택을 묻는다**(`hasChoice`). 센터가 하나뿐인데 선택
/// 화면을 띄우면 회원에게 "고를 수 있다"는 거짓 인상을 주고 탭만 하나 늘린다.
///
/// 실패는 **빈 목록으로 접는다** — 이 조회가 실패했다고 가입 요청 자체를 막으면 안 된다.
/// 센터 없이 보낸 요청은 서버가 기본 센터로 폴백하므로(v2.33) 종전 동작이 그대로 남는다.
/// autoDispose: 대기실을 떠나면 필요 없다.

final class JoinCentersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CenterDirectory>>,
          List<CenterDirectory>,
          FutureOr<List<CenterDirectory>>
        >
    with
        $FutureModifier<List<CenterDirectory>>,
        $FutureProvider<List<CenterDirectory>> {
  /// 가입 요청을 보낼 수 있는 센터 목록(계약 v2.33).
  ///
  /// **고를 것이 2곳 이상일 때만 화면이 선택을 묻는다**(`hasChoice`). 센터가 하나뿐인데 선택
  /// 화면을 띄우면 회원에게 "고를 수 있다"는 거짓 인상을 주고 탭만 하나 늘린다.
  ///
  /// 실패는 **빈 목록으로 접는다** — 이 조회가 실패했다고 가입 요청 자체를 막으면 안 된다.
  /// 센터 없이 보낸 요청은 서버가 기본 센터로 폴백하므로(v2.33) 종전 동작이 그대로 남는다.
  /// autoDispose: 대기실을 떠나면 필요 없다.
  const JoinCentersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'joinCentersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$joinCentersHash();

  @$internal
  @override
  $FutureProviderElement<List<CenterDirectory>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CenterDirectory>> create(Ref ref) {
    return joinCenters(ref);
  }
}

String _$joinCentersHash() => r'ed13296670202bd055f85ee6b1f58a0520f4a183';

/// 가입 요청("승인 대기 중")의 로컬 영속 — 앱 재실행 복원(session_restore)과
/// 뷰모델이 공유한다.

@ProviderFor(joinRequestStore)
const joinRequestStoreProvider = JoinRequestStoreProvider._();

/// 가입 요청("승인 대기 중")의 로컬 영속 — 앱 재실행 복원(session_restore)과
/// 뷰모델이 공유한다.

final class JoinRequestStoreProvider
    extends
        $FunctionalProvider<
          JoinRequestStore,
          JoinRequestStore,
          JoinRequestStore
        >
    with $Provider<JoinRequestStore> {
  /// 가입 요청("승인 대기 중")의 로컬 영속 — 앱 재실행 복원(session_restore)과
  /// 뷰모델이 공유한다.
  const JoinRequestStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'joinRequestStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$joinRequestStoreHash();

  @$internal
  @override
  $ProviderElement<JoinRequestStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  JoinRequestStore create(Ref ref) {
    return joinRequestStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(JoinRequestStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<JoinRequestStore>(value),
    );
  }
}

String _$joinRequestStoreHash() => r'8dffa317e98426ce9011a518440efb57c5327fa7';

/// 전화번호 → 인증번호 → 센터 자동매칭 → 이름확인(P48) 전체 흐름을 관리.
/// 화면 3개(phone/code/center_confirm)가 이 하나의 Notifier를 공유한다.
///
/// keepAlive: sessionProvider와 같은 이유 — 라우팅 레이스로 상태가 사라지면 안 된다.
/// autoDispose면 앱 시작 복원 경로(session_restore가 화면 mount 전에 승인 대기
/// 상태를 심어 두는 구간)에서 구독자가 0이라 상태가 그대로 폐기된다(실측 확인).
/// 상태 초기화는 수명주기가 아니라 restartWithNewPhone()로 명시 처리한다.

@ProviderFor(AuthViewModel)
const authViewModelProvider = AuthViewModelProvider._();

/// 전화번호 → 인증번호 → 센터 자동매칭 → 이름확인(P48) 전체 흐름을 관리.
/// 화면 3개(phone/code/center_confirm)가 이 하나의 Notifier를 공유한다.
///
/// keepAlive: sessionProvider와 같은 이유 — 라우팅 레이스로 상태가 사라지면 안 된다.
/// autoDispose면 앱 시작 복원 경로(session_restore가 화면 mount 전에 승인 대기
/// 상태를 심어 두는 구간)에서 구독자가 0이라 상태가 그대로 폐기된다(실측 확인).
/// 상태 초기화는 수명주기가 아니라 restartWithNewPhone()로 명시 처리한다.
final class AuthViewModelProvider
    extends $NotifierProvider<AuthViewModel, AuthState> {
  /// 전화번호 → 인증번호 → 센터 자동매칭 → 이름확인(P48) 전체 흐름을 관리.
  /// 화면 3개(phone/code/center_confirm)가 이 하나의 Notifier를 공유한다.
  ///
  /// keepAlive: sessionProvider와 같은 이유 — 라우팅 레이스로 상태가 사라지면 안 된다.
  /// autoDispose면 앱 시작 복원 경로(session_restore가 화면 mount 전에 승인 대기
  /// 상태를 심어 두는 구간)에서 구독자가 0이라 상태가 그대로 폐기된다(실측 확인).
  /// 상태 초기화는 수명주기가 아니라 restartWithNewPhone()로 명시 처리한다.
  const AuthViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authViewModelHash();

  @$internal
  @override
  AuthViewModel create() => AuthViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthState>(value),
    );
  }
}

String _$authViewModelHash() => r'140391f385e696cf8e5dcf4c924a4a805d6207db';

/// 전화번호 → 인증번호 → 센터 자동매칭 → 이름확인(P48) 전체 흐름을 관리.
/// 화면 3개(phone/code/center_confirm)가 이 하나의 Notifier를 공유한다.
///
/// keepAlive: sessionProvider와 같은 이유 — 라우팅 레이스로 상태가 사라지면 안 된다.
/// autoDispose면 앱 시작 복원 경로(session_restore가 화면 mount 전에 승인 대기
/// 상태를 심어 두는 구간)에서 구독자가 0이라 상태가 그대로 폐기된다(실측 확인).
/// 상태 초기화는 수명주기가 아니라 restartWithNewPhone()로 명시 처리한다.

abstract class _$AuthViewModel extends $Notifier<AuthState> {
  AuthState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AuthState, AuthState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AuthState, AuthState>,
              AuthState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
