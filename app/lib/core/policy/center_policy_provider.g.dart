// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'center_policy_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 센터 운영 정책 — 세션 로드 후 조회해 성공 시에만 캐시([ref.keepAlive]).
/// 실패해도 절대 throw하지 않고 [CenterPolicy.fallback](24h/2회/30일)으로 폴백한다
/// — 정책 표시가 홈/예약/마이 탭 로드를 막으면 안 되기 때문(최종 검증은 서버).
///
/// keepAlive를 무조건 걸지 않는 이유(P03 보완):
/// 1) 실패 폴백이 앱 세션 내내 keepAlive 캐시에 눌러앉으면 이후 모든 화면이
///    기본값(24h)만 보게 된다 — 성공 시에만 keepAlive, 실패하면 autoDispose로
///    남겨 다음 구독/새로고침 때 재시도한다.
/// 2) 정책은 대표가 언제든 바꾼다. 예: 대표가 취소 컷오프를 축소(24h→6h)한 뒤에도
///    앱이 로그인 시점 정책을 붙들고 있으면, 회원은 취소 가능한 예약에서 취소 버튼을
///    못 보거나(버튼 미노출) 서버가 거부하는 버튼을 계속 누르는 사일런트 데드엔드에
///    빠진다 — 그래서 각 탭 새로고침 경로가 이 provider를 invalidate해 재로그인
///    없이도 최신 정책이 반영되게 한다.

@ProviderFor(centerPolicy)
const centerPolicyProvider = CenterPolicyProvider._();

/// 센터 운영 정책 — 세션 로드 후 조회해 성공 시에만 캐시([ref.keepAlive]).
/// 실패해도 절대 throw하지 않고 [CenterPolicy.fallback](24h/2회/30일)으로 폴백한다
/// — 정책 표시가 홈/예약/마이 탭 로드를 막으면 안 되기 때문(최종 검증은 서버).
///
/// keepAlive를 무조건 걸지 않는 이유(P03 보완):
/// 1) 실패 폴백이 앱 세션 내내 keepAlive 캐시에 눌러앉으면 이후 모든 화면이
///    기본값(24h)만 보게 된다 — 성공 시에만 keepAlive, 실패하면 autoDispose로
///    남겨 다음 구독/새로고침 때 재시도한다.
/// 2) 정책은 대표가 언제든 바꾼다. 예: 대표가 취소 컷오프를 축소(24h→6h)한 뒤에도
///    앱이 로그인 시점 정책을 붙들고 있으면, 회원은 취소 가능한 예약에서 취소 버튼을
///    못 보거나(버튼 미노출) 서버가 거부하는 버튼을 계속 누르는 사일런트 데드엔드에
///    빠진다 — 그래서 각 탭 새로고침 경로가 이 provider를 invalidate해 재로그인
///    없이도 최신 정책이 반영되게 한다.

final class CenterPolicyProvider
    extends
        $FunctionalProvider<
          AsyncValue<CenterPolicy>,
          CenterPolicy,
          FutureOr<CenterPolicy>
        >
    with $FutureModifier<CenterPolicy>, $FutureProvider<CenterPolicy> {
  /// 센터 운영 정책 — 세션 로드 후 조회해 성공 시에만 캐시([ref.keepAlive]).
  /// 실패해도 절대 throw하지 않고 [CenterPolicy.fallback](24h/2회/30일)으로 폴백한다
  /// — 정책 표시가 홈/예약/마이 탭 로드를 막으면 안 되기 때문(최종 검증은 서버).
  ///
  /// keepAlive를 무조건 걸지 않는 이유(P03 보완):
  /// 1) 실패 폴백이 앱 세션 내내 keepAlive 캐시에 눌러앉으면 이후 모든 화면이
  ///    기본값(24h)만 보게 된다 — 성공 시에만 keepAlive, 실패하면 autoDispose로
  ///    남겨 다음 구독/새로고침 때 재시도한다.
  /// 2) 정책은 대표가 언제든 바꾼다. 예: 대표가 취소 컷오프를 축소(24h→6h)한 뒤에도
  ///    앱이 로그인 시점 정책을 붙들고 있으면, 회원은 취소 가능한 예약에서 취소 버튼을
  ///    못 보거나(버튼 미노출) 서버가 거부하는 버튼을 계속 누르는 사일런트 데드엔드에
  ///    빠진다 — 그래서 각 탭 새로고침 경로가 이 provider를 invalidate해 재로그인
  ///    없이도 최신 정책이 반영되게 한다.
  const CenterPolicyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'centerPolicyProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$centerPolicyHash();

  @$internal
  @override
  $FutureProviderElement<CenterPolicy> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CenterPolicy> create(Ref ref) {
    return centerPolicy(ref);
  }
}

String _$centerPolicyHash() => r'f2285b28dc5a9999beeffbd8309f8011f425428a';
