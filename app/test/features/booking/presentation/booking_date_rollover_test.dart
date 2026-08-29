import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_repository.dart';
import 'package:rise_member/features/booking/presentation/booking_screen.dart';
import 'package:rise_member/features/booking/presentation/booking_view_model.dart';
import 'package:rise_member/features/booking/presentation/widgets/date_strip.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';

// HIGH(기능 전면 마비) — 자정을 넘기면 예약 탭이 **앱을 껐다 켜기 전까지** 죽는다.
//
// `SelectedBookingDate`의 초기 state는 `todayKst()`인데, 예약 탭은
// `StatefulShellRoute.indexedStack`에 상주해 구독이 끊기지 않는다 → build가
// 앱 프로세스 수명 내내 다시 돌지 않는다. 자정을 넘긴 회원이 보는 것:
//  · 날짜 스트립은 새 "오늘"부터 14일을 그리는데 선택 날짜는 어제 → **선택된 칩 0개**
//  · 뷰모델은 어제 슬롯을 로드 → **13칸 전부 "지남"**
// 돈이 걸린 결함은 아니지만 예약 자체가 불가능해진다.
//
// 처방은 "과거가 됐으면 오늘로 **당긴다**"(되돌리지 않는다 — 과거 날짜를 고를 경로가
// 없으므로 "선택 날짜 < 오늘"은 자정을 넘겼다는 뜻 하나뿐이다).
// 시각은 UTC로 주입하고 기대값은 KST로 읽는다(TZ 독립).
void main() {
  late _FakeHomeRepository homeRepo;
  late _RecordingBookingRepository bookingRepo;

  setUp(() {
    homeRepo = _FakeHomeRepository();
    bookingRepo = _RecordingBookingRepository();
  });

  /// KST 벽시계 2026-08-[day] [h]:[m]:[s]에 해당하는 절대 시각.
  DateTime kst(int day, int h, int m, [int s = 0]) => DateTime.utc(2026, 8, day, h - 9, m, s);

  Future<ProviderContainer> pumpBooking(WidgetTester tester, {DateTime? selectDate}) async {
    final container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(homeRepo),
        bookingRepositoryProvider.overrideWithValue(bookingRepo),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        staffMapProvider.overrideWithValue(const AsyncValue<Map<String, StaffDto>>.data({})),
      ],
    );
    container.read(sessionProvider.notifier).set(
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람'),
        );
    if (selectDate != null) {
      container.read(selectedBookingDateProvider.notifier).select(selectDate);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const BookingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// 23:50 → 00:00:01. 경계 타이머는 +1초 여유를 두고 예약된다.
  Future<void> crossMidnight(WidgetTester tester, void Function(DateTime) setNow) async {
    setNow(kst(24, 0, 0, 1));
    await tester.pump(const Duration(minutes: 10, seconds: 2));
    await tester.pumpAndSettle();
  }

  /// 날짜 스트립에서 선택된 칩들의 라벨(상단 "내 코치"·"내 회원권 전체" 칩과 구분).
  List<String> selectedDateChips(WidgetTester tester) => tester
      .widgetList<RiseChip>(
        find.descendant(of: find.byType(DateStrip), matching: find.byType(RiseChip)),
      )
      .where((c) => c.selected)
      .map((c) => c.label)
      .toList();

  testWidgets('23:50에 열어 둔 예약 탭이 자정에 스스로 오늘로 넘어간다', (tester) async {
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      final container = await pumpBooking(tester);

      // 8/23(일) 23:50 — 운영시간 09~21시는 전부 지났다.
      expect(container.read(selectedBookingDateProvider), DateTime(2026, 8, 23));
      expect(selectedDateChips(tester), ['일 23']);
      expect(find.widgetWithText(RiseButton, '예약'), findsNothing);

      await crossMidnight(tester, (t) => now = t);

      expect(container.read(selectedBookingDateProvider), DateTime(2026, 8, 24),
          reason: '앱을 껐다 켜기 전엔 어제로 남는다 — 예약 탭이 통째로 못 쓰는 화면이 된다');
      expect(bookingRepo.loadedDates.last, DateTime(2026, 8, 24));
    });
  });

  testWidgets('선택된 날짜 칩이 사라지지 않는다 — 스트립엔 어제가 없다', (tester) async {
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      await pumpBooking(tester);
      await crossMidnight(tester, (t) => now = t);

      expect(selectedDateChips(tester), ['월 24'],
          reason: '스트립은 오늘부터 14일이라, 선택 날짜가 어제면 칩이 하나도 선택되지 않는다');
    });
  });

  testWidgets('슬롯 13칸이 전부 "지남"으로 굳지 않는다 — 예약이 실제로 가능해야 한다', (tester) async {
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      await pumpBooking(tester);
      expect(find.text('지남'), findsWidgets);

      await crossMidnight(tester, (t) => now = t);

      expect(find.text('지남'), findsNothing);
      expect(find.widgetWithText(RiseButton, '예약'), findsWidgets,
          reason: '회원이 자정 이후에 할 수 있는 일이 "앱 강제 종료"밖에 없으면 안 된다');
    });
  });

  testWidgets('회원이 고른 미래 날짜는 자정에도 그대로 — 되돌리지 않고 앞으로만 민다', (tester) async {
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      final container = await pumpBooking(tester, selectDate: DateTime(2026, 8, 26));
      final loadsBefore = bookingRepo.loadedDates.length;

      await crossMidnight(tester, (t) => now = t);

      expect(container.read(selectedBookingDateProvider), DateTime(2026, 8, 26));
      expect(bookingRepo.loadedDates.length, loadsBefore,
          reason: '날짜가 안 바뀌면 슬롯을 다시 부를 이유가 없다(왕복 0)');
    });
  });

  testWidgets('다른 탭에 있는 동안엔 슬롯을 다시 부르지 않는다', (tester) async {
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      final container = ProviderContainer.test(
        overrides: [
          homeRepositoryProvider.overrideWithValue(homeRepo),
          bookingRepositoryProvider.overrideWithValue(bookingRepo),
          centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
          staffMapProvider.overrideWithValue(const AsyncValue<Map<String, StaffDto>>.data({})),
        ],
      );
      container.read(sessionProvider.notifier).set(
            const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1'),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          // go_router가 indexedStack의 비활성 브랜치를 감싸는 것과 같은 모양.
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const TickerMode(enabled: false, child: BookingScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final loadsBefore = bookingRepo.loadedDates.length;

      await crossMidnight(tester, (t) => now = t);

      expect(bookingRepo.loadedDates.length, loadsBefore);
      // 탭으로 돌아오면 그때 맞춰진다 — TickerMode는 InheritedWidget이라 리빌드가 따라온다.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const TickerMode(enabled: true, child: BookingScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(selectedBookingDateProvider), DateTime(2026, 8, 24));
    });
  });

  group('SelectedBookingDate.rolloverToToday', () {
    test('과거면 오늘로 당기고, 오늘·미래면 건드리지 않는다(멱등)', () {
      withClock(Clock.fixed(kst(24, 0, 5)), () {
        final container = ProviderContainer.test();
        final notifier = container.read(selectedBookingDateProvider.notifier);

        notifier.select(DateTime(2026, 8, 23));
        notifier.rolloverToToday();
        expect(container.read(selectedBookingDateProvider), DateTime(2026, 8, 24));

        notifier.rolloverToToday();
        expect(container.read(selectedBookingDateProvider), DateTime(2026, 8, 24));

        notifier.select(DateTime(2026, 8, 30));
        notifier.rolloverToToday();
        expect(container.read(selectedBookingDateProvider), DateTime(2026, 8, 30));
      });
    });
  });
}

class _FakeHomeRepository implements HomeRepository {
  @override
  Future<Result<HomeSummary>> loadHome({
    required String memberId,
    String? preferredPassId,
  }) async {
    return Ok(HomeSummary(
      passes: [
        PassOption(
          id: 'p1',
          product: 'PT 20회',
          trainerId: 't1',
          trainerName: '정혜린',
          status: 'active',
          remaining: 8,
          totalSessions: 20,
          validFrom: DateTime(2026, 1, 1),
          validUntil: DateTime(2030, 12, 31),
        ),
      ],
      selectedPassId: 'p1',
      homeworkItems: const [],
      homeworkDate: DateFmt.todayKst(),
    ));
  }

  @override
  Future<Result<void>> submitHomeworkChecks({
    required String memberId,
    required String hwId,
    required DateTime date,
    required List<bool> done,
  }) async =>
      const Ok(null);

  @override
  Future<Result<void>> selfCheckIn({String? scannedToken}) async => const Ok(null);
}

class _RecordingBookingRepository implements BookingRepository {
  /// 슬롯을 실제로 조회한 날짜들 — "어느 날 화면을 보고 있는가"의 증거.
  final List<DateTime> loadedDates = [];

  @override
  Future<Result<List<Slot>>> loadSlots(DateTime date) async {
    loadedDates.add(date);
    // 서버는 예약이 있던 슬롯만 준다 — 빈 시간대는 BookingRules가 09~21시로 합성한다.
    return const Ok([]);
  }

  @override
  Future<Result<List<MyBooking>>> loadMyBookings(String memberId) async => const Ok([]);

  @override
  Future<Result<void>> book({
    required String slotKey,
    required String memberId,
    required String passId,
  }) async =>
      const Ok(null);

  @override
  Future<Result<void>> cancel(String bookingId) async => const Ok(null);

  @override
  Future<Result<void>> createRecurring({
    required String memberId,
    required String trainerId,
    required String passId,
    required List<String> days,
    required int hour,
    DateTime? until,
  }) async =>
      const Ok(null);

  @override
  Future<Result<void>> deleteRecurring(String recurringId) async => const Ok(null);
}
