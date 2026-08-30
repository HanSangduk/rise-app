// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'consult_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(consultApi)
const consultApiProvider = ConsultApiProvider._();

final class ConsultApiProvider
    extends $FunctionalProvider<ConsultApi, ConsultApi, ConsultApi>
    with $Provider<ConsultApi> {
  const ConsultApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'consultApiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$consultApiHash();

  @$internal
  @override
  $ProviderElement<ConsultApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ConsultApi create(Ref ref) {
    return consultApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConsultApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConsultApi>(value),
    );
  }
}

String _$consultApiHash() => r'97529dea77ba33f428f7d1592321c0aaa32103d9';

/// 내 재등록/상담 요청 목록 — CTA가 "요청 보냈어요" 상태를 세션·재실행을 넘어 복원하는
/// 유일한 출처다(로컬 플래그로 들면 앱 재설치·기기 변경에서 거짓말이 된다).
///
/// keepAlive를 걸지 않는다 — 이 값을 보는 화면은 CTA가 뜬 홈/예약뿐이고, 요청 전송
/// 직후 invalidate로 즉시 갱신되므로 짧은 생명주기가 맞다(staffMap처럼 앱 전역에서
/// 이름 해석에 쓰이는 캐시가 아니다).

@ProviderFor(myConsultRequests)
const myConsultRequestsProvider = MyConsultRequestsProvider._();

/// 내 재등록/상담 요청 목록 — CTA가 "요청 보냈어요" 상태를 세션·재실행을 넘어 복원하는
/// 유일한 출처다(로컬 플래그로 들면 앱 재설치·기기 변경에서 거짓말이 된다).
///
/// keepAlive를 걸지 않는다 — 이 값을 보는 화면은 CTA가 뜬 홈/예약뿐이고, 요청 전송
/// 직후 invalidate로 즉시 갱신되므로 짧은 생명주기가 맞다(staffMap처럼 앱 전역에서
/// 이름 해석에 쓰이는 캐시가 아니다).

final class MyConsultRequestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ConsultRequestDto>>,
          List<ConsultRequestDto>,
          FutureOr<List<ConsultRequestDto>>
        >
    with
        $FutureModifier<List<ConsultRequestDto>>,
        $FutureProvider<List<ConsultRequestDto>> {
  /// 내 재등록/상담 요청 목록 — CTA가 "요청 보냈어요" 상태를 세션·재실행을 넘어 복원하는
  /// 유일한 출처다(로컬 플래그로 들면 앱 재설치·기기 변경에서 거짓말이 된다).
  ///
  /// keepAlive를 걸지 않는다 — 이 값을 보는 화면은 CTA가 뜬 홈/예약뿐이고, 요청 전송
  /// 직후 invalidate로 즉시 갱신되므로 짧은 생명주기가 맞다(staffMap처럼 앱 전역에서
  /// 이름 해석에 쓰이는 캐시가 아니다).
  const MyConsultRequestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noRetry,
        name: r'myConsultRequestsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myConsultRequestsHash();

  @$internal
  @override
  $FutureProviderElement<List<ConsultRequestDto>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ConsultRequestDto>> create(Ref ref) {
    return myConsultRequests(ref);
  }
}

String _$myConsultRequestsHash() => r'd2aacedc738037e1824bb54b1530f5182d8bd964';
