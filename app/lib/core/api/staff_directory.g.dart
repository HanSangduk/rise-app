// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'staff_directory.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(staffDirectory)
const staffDirectoryProvider = StaffDirectoryProvider._();

final class StaffDirectoryProvider
    extends $FunctionalProvider<StaffDirectory, StaffDirectory, StaffDirectory>
    with $Provider<StaffDirectory> {
  const StaffDirectoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'staffDirectoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$staffDirectoryHash();

  @$internal
  @override
  $ProviderElement<StaffDirectory> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StaffDirectory create(Ref ref) {
    return staffDirectory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StaffDirectory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StaffDirectory>(value),
    );
  }
}

String _$staffDirectoryHash() => r'd06216ed6ae72f3719de06a18a7f10ea89aa3ff9';

/// 센터 전체 스태프를 로드해 uid→StaffDto 맵으로 캐싱(FutureProvider).
///
/// **앱 전체에서 스태프 목록의 유일한 출처다.** 홈·예약·마이의 repository도
/// [staffMapReaderProvider]를 통해 여기로 들어온다 — 예전엔 그 셋이 각자
/// `StaffDirectory.fetchAll()`을 직접 불러서 (a) 탭 진입마다 GET /v1/staff가
/// 중복으로 나가고 (b) "퇴사 여부"의 출처가 캐시와 직접조회 둘로 갈려 한 화면
/// 안에서 답이 모순되고 (c) `ref.invalidate(staffMapProvider)`가 정작 그 세
/// 화면의 라벨엔 아무 영향도 주지 못했다.
///
/// **성공만** 캐시한다 — center_policy_provider와 동일 원칙: 실패(AsyncError)가
/// 캐시에 눌러앉으면 화면이 살아있는 동안 재시도 없이 "캐시 미적중 폴백"(이름만/빈 프로필)
/// 만 계속 보게 된다. 실패는 링크를 풀어 다음 구독 때 재시도한다.
///
/// 단 [Ref.keepAlive]는 **로드를 시작하기 전에** 건다. repository는 화면처럼
/// watch하지 않고 [staffMapReaderProvider]를 통해 read로 들어오는데, 그러면 구독자가
/// 0이라 요청이 나간 채로 element가 폐기되고 `.future`가 "disposed during loading"으로
/// 깨진다(그리고 탭마다 다시 요청이 나가 단일화가 무의미해진다). 실측으로 확인한
/// 경로라 링크를 먼저 걸고, 실패했을 때만 되돌린다.
///
/// 성공 캐시를 **무기한** 붙들어도 안 된다(계약 v2.0 보완): 코치가 퇴사해도 앱을
/// 껐다 켜기 전까지 아바타·프로필 시트·온보딩 매칭 카드가 현직 정보를 계속 보여준다.
/// 그래서 세션 중 갱신 경로가 둘이다:
///   ① TTL([_staffCacheTtl]) — 만료 시 [Ref.invalidateSelf]로 캐시를 버린다.
///   ② 홈·마이·예약 탭의 pull-to-refresh와 에러 onRetry가 invalidate로 즉시 재조회
///      (사용자가 직접 당길 때만 — 자동 반복 호출 없음). 세 화면 모두 뷰모델을
///      함께 새로고침하므로, 이제 라벨(도메인 플래그)까지 같은 새 데이터로 바뀐다.

@ProviderFor(staffMap)
const staffMapProvider = StaffMapProvider._();

/// 센터 전체 스태프를 로드해 uid→StaffDto 맵으로 캐싱(FutureProvider).
///
/// **앱 전체에서 스태프 목록의 유일한 출처다.** 홈·예약·마이의 repository도
/// [staffMapReaderProvider]를 통해 여기로 들어온다 — 예전엔 그 셋이 각자
/// `StaffDirectory.fetchAll()`을 직접 불러서 (a) 탭 진입마다 GET /v1/staff가
/// 중복으로 나가고 (b) "퇴사 여부"의 출처가 캐시와 직접조회 둘로 갈려 한 화면
/// 안에서 답이 모순되고 (c) `ref.invalidate(staffMapProvider)`가 정작 그 세
/// 화면의 라벨엔 아무 영향도 주지 못했다.
///
/// **성공만** 캐시한다 — center_policy_provider와 동일 원칙: 실패(AsyncError)가
/// 캐시에 눌러앉으면 화면이 살아있는 동안 재시도 없이 "캐시 미적중 폴백"(이름만/빈 프로필)
/// 만 계속 보게 된다. 실패는 링크를 풀어 다음 구독 때 재시도한다.
///
/// 단 [Ref.keepAlive]는 **로드를 시작하기 전에** 건다. repository는 화면처럼
/// watch하지 않고 [staffMapReaderProvider]를 통해 read로 들어오는데, 그러면 구독자가
/// 0이라 요청이 나간 채로 element가 폐기되고 `.future`가 "disposed during loading"으로
/// 깨진다(그리고 탭마다 다시 요청이 나가 단일화가 무의미해진다). 실측으로 확인한
/// 경로라 링크를 먼저 걸고, 실패했을 때만 되돌린다.
///
/// 성공 캐시를 **무기한** 붙들어도 안 된다(계약 v2.0 보완): 코치가 퇴사해도 앱을
/// 껐다 켜기 전까지 아바타·프로필 시트·온보딩 매칭 카드가 현직 정보를 계속 보여준다.
/// 그래서 세션 중 갱신 경로가 둘이다:
///   ① TTL([_staffCacheTtl]) — 만료 시 [Ref.invalidateSelf]로 캐시를 버린다.
///   ② 홈·마이·예약 탭의 pull-to-refresh와 에러 onRetry가 invalidate로 즉시 재조회
///      (사용자가 직접 당길 때만 — 자동 반복 호출 없음). 세 화면 모두 뷰모델을
///      함께 새로고침하므로, 이제 라벨(도메인 플래그)까지 같은 새 데이터로 바뀐다.

final class StaffMapProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, StaffDto>>,
          Map<String, StaffDto>,
          FutureOr<Map<String, StaffDto>>
        >
    with
        $FutureModifier<Map<String, StaffDto>>,
        $FutureProvider<Map<String, StaffDto>> {
  /// 센터 전체 스태프를 로드해 uid→StaffDto 맵으로 캐싱(FutureProvider).
  ///
  /// **앱 전체에서 스태프 목록의 유일한 출처다.** 홈·예약·마이의 repository도
  /// [staffMapReaderProvider]를 통해 여기로 들어온다 — 예전엔 그 셋이 각자
  /// `StaffDirectory.fetchAll()`을 직접 불러서 (a) 탭 진입마다 GET /v1/staff가
  /// 중복으로 나가고 (b) "퇴사 여부"의 출처가 캐시와 직접조회 둘로 갈려 한 화면
  /// 안에서 답이 모순되고 (c) `ref.invalidate(staffMapProvider)`가 정작 그 세
  /// 화면의 라벨엔 아무 영향도 주지 못했다.
  ///
  /// **성공만** 캐시한다 — center_policy_provider와 동일 원칙: 실패(AsyncError)가
  /// 캐시에 눌러앉으면 화면이 살아있는 동안 재시도 없이 "캐시 미적중 폴백"(이름만/빈 프로필)
  /// 만 계속 보게 된다. 실패는 링크를 풀어 다음 구독 때 재시도한다.
  ///
  /// 단 [Ref.keepAlive]는 **로드를 시작하기 전에** 건다. repository는 화면처럼
  /// watch하지 않고 [staffMapReaderProvider]를 통해 read로 들어오는데, 그러면 구독자가
  /// 0이라 요청이 나간 채로 element가 폐기되고 `.future`가 "disposed during loading"으로
  /// 깨진다(그리고 탭마다 다시 요청이 나가 단일화가 무의미해진다). 실측으로 확인한
  /// 경로라 링크를 먼저 걸고, 실패했을 때만 되돌린다.
  ///
  /// 성공 캐시를 **무기한** 붙들어도 안 된다(계약 v2.0 보완): 코치가 퇴사해도 앱을
  /// 껐다 켜기 전까지 아바타·프로필 시트·온보딩 매칭 카드가 현직 정보를 계속 보여준다.
  /// 그래서 세션 중 갱신 경로가 둘이다:
  ///   ① TTL([_staffCacheTtl]) — 만료 시 [Ref.invalidateSelf]로 캐시를 버린다.
  ///   ② 홈·마이·예약 탭의 pull-to-refresh와 에러 onRetry가 invalidate로 즉시 재조회
  ///      (사용자가 직접 당길 때만 — 자동 반복 호출 없음). 세 화면 모두 뷰모델을
  ///      함께 새로고침하므로, 이제 라벨(도메인 플래그)까지 같은 새 데이터로 바뀐다.
  const StaffMapProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'staffMapProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$staffMapHash();

  @$internal
  @override
  $FutureProviderElement<Map<String, StaffDto>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, StaffDto>> create(Ref ref) {
    return staffMap(ref);
  }
}

String _$staffMapHash() => r'6c1d3ccf91046193a389486f91d95718288c9f99';

/// [StaffMapReader]의 실제 구현 — 실패를 **삼킨다**(best-effort).
///
/// **왜 best-effort인가.** 예전엔 세 repository가 `fetchAll()`을 가드 없이 맨 먼저
/// await해서, GET /v1/staff 한 번이 실패하면 홈·예약·마이 **3개 탭이 통째로 에러
/// 화면**이 됐다. 이름 해석은 회원권 잔여·예약·원장을 보는 데 필수가 아닌 부가
/// 정보다. 부가 정보 하나 때문에 본문을 전부 가리는 건 과하다.
///
/// **그러면 "퇴사 여부"를 모르게 되는데 현직으로 보이는 게 맞나.** 맞다. 실패 시
/// 빈 맵이 되면 이름(`staffMap[id]?.name`)과 상태(`?.isInactive`)가 **함께** 사라진다:
///   · 이름이 null이면 화면들은 코치 문구 자체를 통째로 생략한다(CoachLabel 규약).
///     "정혜린 코치"라고 말하지 않으니 "(퇴사)"를 빼먹었다고 거짓을 말할 자리도 없다
///     — 즉 `?? false` 폴백이 화면에서 관측 가능한 거짓말이 되지 않는다.
///   · 반대로 "모르면 퇴사"로 기울이면 없는 퇴사를 지어내게 된다. 계약 v2.0의
///     승격 규약(모르는 status는 active)과도 정면으로 어긋난다.
///   · 예약 가능 여부([BookablePass.isSelectable])도 열어 두는 쪽이 맞다. 디렉토리
///     조회 실패로 회원의 예약을 막는 건 무관한 장애로 본업을 세우는 것이고,
///     실제 퇴사라면 서버가 거절한다(계약상 active/scheduled 패스가 남아 있으면
///     퇴사 처리 자체가 막히므로 정상 흐름에선 발생하지 않는다).
/// 프로필 시트는 이 경우 `staffMap == null`을 보고 "불러오지 못했어요"로 안내하므로,
/// **모른다는 사실 자체는 감춰지지 않는다**.
///
/// 예외를 전부 삼키는 데는 두 번째 이유도 있다: repository provider가 이미 폐기된
/// 뒤(뷰모델 재빌드와 로드가 겹칠 때) 호출되면 `ref.read`가 UnmountedRefException을
/// 던지는데, 그 결과는 어차피 버려질 로드라 조용히 빈 맵으로 끝내는 게 맞다.

@ProviderFor(staffMapReader)
const staffMapReaderProvider = StaffMapReaderProvider._();

/// [StaffMapReader]의 실제 구현 — 실패를 **삼킨다**(best-effort).
///
/// **왜 best-effort인가.** 예전엔 세 repository가 `fetchAll()`을 가드 없이 맨 먼저
/// await해서, GET /v1/staff 한 번이 실패하면 홈·예약·마이 **3개 탭이 통째로 에러
/// 화면**이 됐다. 이름 해석은 회원권 잔여·예약·원장을 보는 데 필수가 아닌 부가
/// 정보다. 부가 정보 하나 때문에 본문을 전부 가리는 건 과하다.
///
/// **그러면 "퇴사 여부"를 모르게 되는데 현직으로 보이는 게 맞나.** 맞다. 실패 시
/// 빈 맵이 되면 이름(`staffMap[id]?.name`)과 상태(`?.isInactive`)가 **함께** 사라진다:
///   · 이름이 null이면 화면들은 코치 문구 자체를 통째로 생략한다(CoachLabel 규약).
///     "정혜린 코치"라고 말하지 않으니 "(퇴사)"를 빼먹었다고 거짓을 말할 자리도 없다
///     — 즉 `?? false` 폴백이 화면에서 관측 가능한 거짓말이 되지 않는다.
///   · 반대로 "모르면 퇴사"로 기울이면 없는 퇴사를 지어내게 된다. 계약 v2.0의
///     승격 규약(모르는 status는 active)과도 정면으로 어긋난다.
///   · 예약 가능 여부([BookablePass.isSelectable])도 열어 두는 쪽이 맞다. 디렉토리
///     조회 실패로 회원의 예약을 막는 건 무관한 장애로 본업을 세우는 것이고,
///     실제 퇴사라면 서버가 거절한다(계약상 active/scheduled 패스가 남아 있으면
///     퇴사 처리 자체가 막히므로 정상 흐름에선 발생하지 않는다).
/// 프로필 시트는 이 경우 `staffMap == null`을 보고 "불러오지 못했어요"로 안내하므로,
/// **모른다는 사실 자체는 감춰지지 않는다**.
///
/// 예외를 전부 삼키는 데는 두 번째 이유도 있다: repository provider가 이미 폐기된
/// 뒤(뷰모델 재빌드와 로드가 겹칠 때) 호출되면 `ref.read`가 UnmountedRefException을
/// 던지는데, 그 결과는 어차피 버려질 로드라 조용히 빈 맵으로 끝내는 게 맞다.

final class StaffMapReaderProvider
    extends $FunctionalProvider<StaffMapReader, StaffMapReader, StaffMapReader>
    with $Provider<StaffMapReader> {
  /// [StaffMapReader]의 실제 구현 — 실패를 **삼킨다**(best-effort).
  ///
  /// **왜 best-effort인가.** 예전엔 세 repository가 `fetchAll()`을 가드 없이 맨 먼저
  /// await해서, GET /v1/staff 한 번이 실패하면 홈·예약·마이 **3개 탭이 통째로 에러
  /// 화면**이 됐다. 이름 해석은 회원권 잔여·예약·원장을 보는 데 필수가 아닌 부가
  /// 정보다. 부가 정보 하나 때문에 본문을 전부 가리는 건 과하다.
  ///
  /// **그러면 "퇴사 여부"를 모르게 되는데 현직으로 보이는 게 맞나.** 맞다. 실패 시
  /// 빈 맵이 되면 이름(`staffMap[id]?.name`)과 상태(`?.isInactive`)가 **함께** 사라진다:
  ///   · 이름이 null이면 화면들은 코치 문구 자체를 통째로 생략한다(CoachLabel 규약).
  ///     "정혜린 코치"라고 말하지 않으니 "(퇴사)"를 빼먹었다고 거짓을 말할 자리도 없다
  ///     — 즉 `?? false` 폴백이 화면에서 관측 가능한 거짓말이 되지 않는다.
  ///   · 반대로 "모르면 퇴사"로 기울이면 없는 퇴사를 지어내게 된다. 계약 v2.0의
  ///     승격 규약(모르는 status는 active)과도 정면으로 어긋난다.
  ///   · 예약 가능 여부([BookablePass.isSelectable])도 열어 두는 쪽이 맞다. 디렉토리
  ///     조회 실패로 회원의 예약을 막는 건 무관한 장애로 본업을 세우는 것이고,
  ///     실제 퇴사라면 서버가 거절한다(계약상 active/scheduled 패스가 남아 있으면
  ///     퇴사 처리 자체가 막히므로 정상 흐름에선 발생하지 않는다).
  /// 프로필 시트는 이 경우 `staffMap == null`을 보고 "불러오지 못했어요"로 안내하므로,
  /// **모른다는 사실 자체는 감춰지지 않는다**.
  ///
  /// 예외를 전부 삼키는 데는 두 번째 이유도 있다: repository provider가 이미 폐기된
  /// 뒤(뷰모델 재빌드와 로드가 겹칠 때) 호출되면 `ref.read`가 UnmountedRefException을
  /// 던지는데, 그 결과는 어차피 버려질 로드라 조용히 빈 맵으로 끝내는 게 맞다.
  const StaffMapReaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'staffMapReaderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$staffMapReaderHash();

  @$internal
  @override
  $ProviderElement<StaffMapReader> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StaffMapReader create(Ref ref) {
    return staffMapReader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StaffMapReader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StaffMapReader>(value),
    );
  }
}

String _$staffMapReaderHash() => r'857f0ea6994cc65d55469a9de2e19b98f7ddbf55';
