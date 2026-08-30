// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(bookingRepository)
const bookingRepositoryProvider = BookingRepositoryProvider._();

final class BookingRepositoryProvider
    extends
        $FunctionalProvider<
          BookingRepository,
          BookingRepository,
          BookingRepository
        >
    with $Provider<BookingRepository> {
  const BookingRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookingRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookingRepositoryHash();

  @$internal
  @override
  $ProviderElement<BookingRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BookingRepository create(Ref ref) {
    return bookingRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BookingRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BookingRepository>(value),
    );
  }
}

String _$bookingRepositoryHash() => r'c9cdf9f3c34fe680591ac37c90d32383adb047b5';

/// 날짜 스트립에서 선택된 날짜(기본 오늘).
///
/// ## 이 초기값은 **앱 프로세스 수명 내내 다시 계산되지 않는다** (P17)
///
/// 예약 탭은 `StatefulShellRoute.indexedStack`에 상주해서(`core/router/app_router.dart`)
/// 탭을 떠나도 구독이 끊기지 않는다 — autoDispose provider지만 실제로는 폐기되지
/// 않으므로 [build]는 첫 진입 때 딱 한 번 돈다. 자정을 넘겨도 여기 담긴 "오늘"은
/// 어제인 채로 남고, 회원이 보는 건 이렇다:
///
///  · `DateStrip`은 매 build마다 `todayKst()`부터 14일을 새로 그린다 — 목록에 어제가
///    없으니 **선택된 칩이 하나도 없다.**
///  · 뷰모델은 어제 날짜로 슬롯을 로드하고, `SlotList`는 지난 시각을 "지남"으로
///    그린다 — **13칸이 전부 "지남"**.
///
/// 회원 입장에서 예약 탭이 통째로 죽은 화면이 된다. 앱을 껐다 켜기 전엔 안 풀린다.
///
/// ## 처방 — 자정에 [rolloverToToday]로 **당긴다**
///
/// 되돌리지 않고 **앞으로만** 민다. 과거 날짜를 고를 경로가 없으므로(스트립은 오늘부터
/// 14일) "선택 날짜가 오늘보다 과거"라는 상태는 자정을 넘겼다는 뜻 하나뿐이고,
/// 회원이 고른 미래 날짜는 그대로 둔다.
///
/// 트리거는 화면이 쥔다(`BookingScreen`의 `TimeBoundaryBuilder(atMidnight: true)`) —
/// provider 안에 타이머를 두면 다른 탭에 있을 때도, 앱이 백그라운드일 때도 돈다.
/// 그 판단(비활성 탭 게이팅 · 앱 재개 재평가)은 이미 그 위젯에 들어 있다.

@ProviderFor(SelectedBookingDate)
const selectedBookingDateProvider = SelectedBookingDateProvider._();

/// 날짜 스트립에서 선택된 날짜(기본 오늘).
///
/// ## 이 초기값은 **앱 프로세스 수명 내내 다시 계산되지 않는다** (P17)
///
/// 예약 탭은 `StatefulShellRoute.indexedStack`에 상주해서(`core/router/app_router.dart`)
/// 탭을 떠나도 구독이 끊기지 않는다 — autoDispose provider지만 실제로는 폐기되지
/// 않으므로 [build]는 첫 진입 때 딱 한 번 돈다. 자정을 넘겨도 여기 담긴 "오늘"은
/// 어제인 채로 남고, 회원이 보는 건 이렇다:
///
///  · `DateStrip`은 매 build마다 `todayKst()`부터 14일을 새로 그린다 — 목록에 어제가
///    없으니 **선택된 칩이 하나도 없다.**
///  · 뷰모델은 어제 날짜로 슬롯을 로드하고, `SlotList`는 지난 시각을 "지남"으로
///    그린다 — **13칸이 전부 "지남"**.
///
/// 회원 입장에서 예약 탭이 통째로 죽은 화면이 된다. 앱을 껐다 켜기 전엔 안 풀린다.
///
/// ## 처방 — 자정에 [rolloverToToday]로 **당긴다**
///
/// 되돌리지 않고 **앞으로만** 민다. 과거 날짜를 고를 경로가 없으므로(스트립은 오늘부터
/// 14일) "선택 날짜가 오늘보다 과거"라는 상태는 자정을 넘겼다는 뜻 하나뿐이고,
/// 회원이 고른 미래 날짜는 그대로 둔다.
///
/// 트리거는 화면이 쥔다(`BookingScreen`의 `TimeBoundaryBuilder(atMidnight: true)`) —
/// provider 안에 타이머를 두면 다른 탭에 있을 때도, 앱이 백그라운드일 때도 돈다.
/// 그 판단(비활성 탭 게이팅 · 앱 재개 재평가)은 이미 그 위젯에 들어 있다.
final class SelectedBookingDateProvider
    extends $NotifierProvider<SelectedBookingDate, DateTime> {
  /// 날짜 스트립에서 선택된 날짜(기본 오늘).
  ///
  /// ## 이 초기값은 **앱 프로세스 수명 내내 다시 계산되지 않는다** (P17)
  ///
  /// 예약 탭은 `StatefulShellRoute.indexedStack`에 상주해서(`core/router/app_router.dart`)
  /// 탭을 떠나도 구독이 끊기지 않는다 — autoDispose provider지만 실제로는 폐기되지
  /// 않으므로 [build]는 첫 진입 때 딱 한 번 돈다. 자정을 넘겨도 여기 담긴 "오늘"은
  /// 어제인 채로 남고, 회원이 보는 건 이렇다:
  ///
  ///  · `DateStrip`은 매 build마다 `todayKst()`부터 14일을 새로 그린다 — 목록에 어제가
  ///    없으니 **선택된 칩이 하나도 없다.**
  ///  · 뷰모델은 어제 날짜로 슬롯을 로드하고, `SlotList`는 지난 시각을 "지남"으로
  ///    그린다 — **13칸이 전부 "지남"**.
  ///
  /// 회원 입장에서 예약 탭이 통째로 죽은 화면이 된다. 앱을 껐다 켜기 전엔 안 풀린다.
  ///
  /// ## 처방 — 자정에 [rolloverToToday]로 **당긴다**
  ///
  /// 되돌리지 않고 **앞으로만** 민다. 과거 날짜를 고를 경로가 없으므로(스트립은 오늘부터
  /// 14일) "선택 날짜가 오늘보다 과거"라는 상태는 자정을 넘겼다는 뜻 하나뿐이고,
  /// 회원이 고른 미래 날짜는 그대로 둔다.
  ///
  /// 트리거는 화면이 쥔다(`BookingScreen`의 `TimeBoundaryBuilder(atMidnight: true)`) —
  /// provider 안에 타이머를 두면 다른 탭에 있을 때도, 앱이 백그라운드일 때도 돈다.
  /// 그 판단(비활성 탭 게이팅 · 앱 재개 재평가)은 이미 그 위젯에 들어 있다.
  const SelectedBookingDateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedBookingDateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedBookingDateHash();

  @$internal
  @override
  SelectedBookingDate create() => SelectedBookingDate();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime>(value),
    );
  }
}

String _$selectedBookingDateHash() =>
    r'154e3b2b5fa97a881cf29aaccc547f621c4ac887';

/// 날짜 스트립에서 선택된 날짜(기본 오늘).
///
/// ## 이 초기값은 **앱 프로세스 수명 내내 다시 계산되지 않는다** (P17)
///
/// 예약 탭은 `StatefulShellRoute.indexedStack`에 상주해서(`core/router/app_router.dart`)
/// 탭을 떠나도 구독이 끊기지 않는다 — autoDispose provider지만 실제로는 폐기되지
/// 않으므로 [build]는 첫 진입 때 딱 한 번 돈다. 자정을 넘겨도 여기 담긴 "오늘"은
/// 어제인 채로 남고, 회원이 보는 건 이렇다:
///
///  · `DateStrip`은 매 build마다 `todayKst()`부터 14일을 새로 그린다 — 목록에 어제가
///    없으니 **선택된 칩이 하나도 없다.**
///  · 뷰모델은 어제 날짜로 슬롯을 로드하고, `SlotList`는 지난 시각을 "지남"으로
///    그린다 — **13칸이 전부 "지남"**.
///
/// 회원 입장에서 예약 탭이 통째로 죽은 화면이 된다. 앱을 껐다 켜기 전엔 안 풀린다.
///
/// ## 처방 — 자정에 [rolloverToToday]로 **당긴다**
///
/// 되돌리지 않고 **앞으로만** 민다. 과거 날짜를 고를 경로가 없으므로(스트립은 오늘부터
/// 14일) "선택 날짜가 오늘보다 과거"라는 상태는 자정을 넘겼다는 뜻 하나뿐이고,
/// 회원이 고른 미래 날짜는 그대로 둔다.
///
/// 트리거는 화면이 쥔다(`BookingScreen`의 `TimeBoundaryBuilder(atMidnight: true)`) —
/// provider 안에 타이머를 두면 다른 탭에 있을 때도, 앱이 백그라운드일 때도 돈다.
/// 그 판단(비활성 탭 게이팅 · 앱 재개 재평가)은 이미 그 위젯에 들어 있다.

abstract class _$SelectedBookingDate extends $Notifier<DateTime> {
  DateTime build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<DateTime, DateTime>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DateTime, DateTime>,
              DateTime,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// "내 코치 / 전체 코치" 토글 — 목업 fMy/fAll. 슬롯은 그대로 두고 클라이언트에서 필터.

@ProviderFor(ShowMyCoachOnly)
const showMyCoachOnlyProvider = ShowMyCoachOnlyProvider._();

/// "내 코치 / 전체 코치" 토글 — 목업 fMy/fAll. 슬롯은 그대로 두고 클라이언트에서 필터.
final class ShowMyCoachOnlyProvider
    extends $NotifierProvider<ShowMyCoachOnly, bool> {
  /// "내 코치 / 전체 코치" 토글 — 목업 fMy/fAll. 슬롯은 그대로 두고 클라이언트에서 필터.
  const ShowMyCoachOnlyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'showMyCoachOnlyProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$showMyCoachOnlyHash();

  @$internal
  @override
  ShowMyCoachOnly create() => ShowMyCoachOnly();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$showMyCoachOnlyHash() => r'12e2ea266dbc276f5d2b7ed884d7adb9ae21d0e1';

/// "내 코치 / 전체 코치" 토글 — 목업 fMy/fAll. 슬롯은 그대로 두고 클라이언트에서 필터.

abstract class _$ShowMyCoachOnly extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// 예약 탭 — 홈의 패스 스위처에서 선택된 패스를 "내 코치" 기준으로 재사용.

@ProviderFor(BookingViewModel)
const bookingViewModelProvider = BookingViewModelProvider._();

/// 예약 탭 — 홈의 패스 스위처에서 선택된 패스를 "내 코치" 기준으로 재사용.
final class BookingViewModelProvider
    extends $AsyncNotifierProvider<BookingViewModel, BookingScreenData> {
  /// 예약 탭 — 홈의 패스 스위처에서 선택된 패스를 "내 코치" 기준으로 재사용.
  const BookingViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookingViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookingViewModelHash();

  @$internal
  @override
  BookingViewModel create() => BookingViewModel();
}

String _$bookingViewModelHash() => r'96acf271de57266818074afed0f341e8d14018d6';

/// 예약 탭 — 홈의 패스 스위처에서 선택된 패스를 "내 코치" 기준으로 재사용.

abstract class _$BookingViewModel extends $AsyncNotifier<BookingScreenData> {
  FutureOr<BookingScreenData> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<AsyncValue<BookingScreenData>, BookingScreenData>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<BookingScreenData>, BookingScreenData>,
              AsyncValue<BookingScreenData>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
