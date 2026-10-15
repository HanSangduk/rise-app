// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'center_contact_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// [centerId]가 있으면 `?center=`로 **그 센터**를 묻는다(계약 v2.33·v2.34) — 2호점에 요청을
/// 보낸 사람의 대기실이 1호점 전화번호를 찍으면 남의 센터다. `null`(홈 헤더·마이 탭·요청 전
/// 대기실)은 파라미터 없이 종전대로 기본 센터다. family로 두는 이유: 같은 화면이 두 센터를
/// 동시에 볼 일은 없지만, 홈 헤더의 기본 인스턴스가 대기실의 선택에 따라 흔들리면 안 된다.

@ProviderFor(centerContact)
const centerContactProvider = CenterContactFamily._();

/// [centerId]가 있으면 `?center=`로 **그 센터**를 묻는다(계약 v2.33·v2.34) — 2호점에 요청을
/// 보낸 사람의 대기실이 1호점 전화번호를 찍으면 남의 센터다. `null`(홈 헤더·마이 탭·요청 전
/// 대기실)은 파라미터 없이 종전대로 기본 센터다. family로 두는 이유: 같은 화면이 두 센터를
/// 동시에 볼 일은 없지만, 홈 헤더의 기본 인스턴스가 대기실의 선택에 따라 흔들리면 안 된다.

final class CenterContactProvider
    extends
        $FunctionalProvider<
          AsyncValue<CenterContact>,
          CenterContact,
          FutureOr<CenterContact>
        >
    with $FutureModifier<CenterContact>, $FutureProvider<CenterContact> {
  /// [centerId]가 있으면 `?center=`로 **그 센터**를 묻는다(계약 v2.33·v2.34) — 2호점에 요청을
  /// 보낸 사람의 대기실이 1호점 전화번호를 찍으면 남의 센터다. `null`(홈 헤더·마이 탭·요청 전
  /// 대기실)은 파라미터 없이 종전대로 기본 센터다. family로 두는 이유: 같은 화면이 두 센터를
  /// 동시에 볼 일은 없지만, 홈 헤더의 기본 인스턴스가 대기실의 선택에 따라 흔들리면 안 된다.
  const CenterContactProvider._({
    required CenterContactFamily super.from,
    required String? super.argument,
  }) : super(
         retry: _noRetry,
         name: r'centerContactProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$centerContactHash();

  @override
  String toString() {
    return r'centerContactProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<CenterContact> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CenterContact> create(Ref ref) {
    final argument = this.argument as String?;
    return centerContact(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CenterContactProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$centerContactHash() => r'775a7b780941b88c54ebd4938c515f2031bfb52d';

/// [centerId]가 있으면 `?center=`로 **그 센터**를 묻는다(계약 v2.33·v2.34) — 2호점에 요청을
/// 보낸 사람의 대기실이 1호점 전화번호를 찍으면 남의 센터다. `null`(홈 헤더·마이 탭·요청 전
/// 대기실)은 파라미터 없이 종전대로 기본 센터다. family로 두는 이유: 같은 화면이 두 센터를
/// 동시에 볼 일은 없지만, 홈 헤더의 기본 인스턴스가 대기실의 선택에 따라 흔들리면 안 된다.

final class CenterContactFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<CenterContact>, String?> {
  const CenterContactFamily._()
    : super(
        retry: _noRetry,
        name: r'centerContactProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// [centerId]가 있으면 `?center=`로 **그 센터**를 묻는다(계약 v2.33·v2.34) — 2호점에 요청을
  /// 보낸 사람의 대기실이 1호점 전화번호를 찍으면 남의 센터다. `null`(홈 헤더·마이 탭·요청 전
  /// 대기실)은 파라미터 없이 종전대로 기본 센터다. family로 두는 이유: 같은 화면이 두 센터를
  /// 동시에 볼 일은 없지만, 홈 헤더의 기본 인스턴스가 대기실의 선택에 따라 흔들리면 안 된다.

  CenterContactProvider call(String? centerId) =>
      CenterContactProvider._(argument: centerId, from: this);

  @override
  String toString() => r'centerContactProvider';
}

/// 화면이 찍는 센터 상호 — 로딩 중·실패·미등록이면 [AppConfig.centerFullName].
///
/// 동기 `String`으로 내려서 헤더·카드가 `AsyncValue` 분기 없이 `ref.watch` 한 줄로 쓴다.
/// 로딩 중에도 임시 상수를 바로 보여주는 것이 의도다 — 상호 한 줄 때문에 홈 헤더가
/// 스피너를 돌릴 이유가 없고, 서버 값이 오면 그 자리에서 바뀐다.
///
/// **로그인 뒤에는 세션의 센터를 묻는다**(P65 후속 3 · P73). 종전엔 항상 `?center=` 없는 기본
/// 센터라, 2호점 회원의 홈 헤더·마이 탭·다음 예약 카드가 **1호점 상호**를 찍었다. 세션의
/// `center_id`(`GET /v1/me`)는 연결된 회원의 실제 센터다. 세션이 없는 대기실은 종전대로 기본
/// 센터(매칭 카드는 매칭 응답의 상호를 따로 받는다 — `_MatchedCenterCard`).

@ProviderFor(centerDisplayName)
const centerDisplayNameProvider = CenterDisplayNameProvider._();

/// 화면이 찍는 센터 상호 — 로딩 중·실패·미등록이면 [AppConfig.centerFullName].
///
/// 동기 `String`으로 내려서 헤더·카드가 `AsyncValue` 분기 없이 `ref.watch` 한 줄로 쓴다.
/// 로딩 중에도 임시 상수를 바로 보여주는 것이 의도다 — 상호 한 줄 때문에 홈 헤더가
/// 스피너를 돌릴 이유가 없고, 서버 값이 오면 그 자리에서 바뀐다.
///
/// **로그인 뒤에는 세션의 센터를 묻는다**(P65 후속 3 · P73). 종전엔 항상 `?center=` 없는 기본
/// 센터라, 2호점 회원의 홈 헤더·마이 탭·다음 예약 카드가 **1호점 상호**를 찍었다. 세션의
/// `center_id`(`GET /v1/me`)는 연결된 회원의 실제 센터다. 세션이 없는 대기실은 종전대로 기본
/// 센터(매칭 카드는 매칭 응답의 상호를 따로 받는다 — `_MatchedCenterCard`).

final class CenterDisplayNameProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// 화면이 찍는 센터 상호 — 로딩 중·실패·미등록이면 [AppConfig.centerFullName].
  ///
  /// 동기 `String`으로 내려서 헤더·카드가 `AsyncValue` 분기 없이 `ref.watch` 한 줄로 쓴다.
  /// 로딩 중에도 임시 상수를 바로 보여주는 것이 의도다 — 상호 한 줄 때문에 홈 헤더가
  /// 스피너를 돌릴 이유가 없고, 서버 값이 오면 그 자리에서 바뀐다.
  ///
  /// **로그인 뒤에는 세션의 센터를 묻는다**(P65 후속 3 · P73). 종전엔 항상 `?center=` 없는 기본
  /// 센터라, 2호점 회원의 홈 헤더·마이 탭·다음 예약 카드가 **1호점 상호**를 찍었다. 세션의
  /// `center_id`(`GET /v1/me`)는 연결된 회원의 실제 센터다. 세션이 없는 대기실은 종전대로 기본
  /// 센터(매칭 카드는 매칭 응답의 상호를 따로 받는다 — `_MatchedCenterCard`).
  const CenterDisplayNameProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'centerDisplayNameProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$centerDisplayNameHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return centerDisplayName(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$centerDisplayNameHash() => r'762129276790285d2cec03cddd6ac0e0486cebae';
