// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_api.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(memberApi)
const memberApiProvider = MemberApiProvider._();

final class MemberApiProvider
    extends $FunctionalProvider<MemberApi, MemberApi, MemberApi>
    with $Provider<MemberApi> {
  const MemberApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'memberApiProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$memberApiHash();

  @$internal
  @override
  $ProviderElement<MemberApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MemberApi create(Ref ref) {
    return memberApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MemberApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MemberApi>(value),
    );
  }
}

String _$memberApiHash() => r'9f2c37d4166a394e9c4ce838c27a3f59cbb6ffef';

/// 내 프로필(동의 상태 등) — 체형 분석 촬영 전 동의 확인, 마이 탭 동의 토글에서 공용.

@ProviderFor(myProfile)
const myProfileProvider = MyProfileProvider._();

/// 내 프로필(동의 상태 등) — 체형 분석 촬영 전 동의 확인, 마이 탭 동의 토글에서 공용.

final class MyProfileProvider
    extends
        $FunctionalProvider<
          AsyncValue<MemberDto>,
          MemberDto,
          FutureOr<MemberDto>
        >
    with $FutureModifier<MemberDto>, $FutureProvider<MemberDto> {
  /// 내 프로필(동의 상태 등) — 체형 분석 촬영 전 동의 확인, 마이 탭 동의 토글에서 공용.
  const MyProfileProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myProfileProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myProfileHash();

  @$internal
  @override
  $FutureProviderElement<MemberDto> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<MemberDto> create(Ref ref) {
    return myProfile(ref);
  }
}

String _$myProfileHash() => r'08c7ac32eb2cf5d645b85b5e5177361652f8ae84';
