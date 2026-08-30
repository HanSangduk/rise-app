import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_repository.dart';
import 'package:rise_member/features/booking/presentation/booking_view_model.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';

// 예약 예산(P13 H1)의 **조립 지점**을 고정한다.
//
// 서버는 `pass.Remaining − 이 패스의 confirmed 예약 수`로 예약을 거부한다. 왼쪽
// 항은 홈 요약에서, 오른쪽 항은 예약 목록에서 온다 — 둘을 잇는 곳이 이 뷰모델이고,
// 여기서 0으로 두면 판정 함수가 아무리 정확해도 규칙이 통째로 꺼진다(잔여만 보던
// 옛 동작으로 조용히 되돌아간다).
void main() {
  MyBooking booking(String id, {required String passId, String status = 'confirmed'}) => MyBooking(
        id: id,
        slotKey: '20260830-10',
        passId: passId,
        trainerId: 't1',
        kind: 'pt',
        status: status,
      );

  PassOption passOption(String id, {required String trainerId, required int remaining}) =>
      PassOption(
        id: id,
        product: 'PT 20회',
        trainerId: trainerId,
        trainerName: '정혜린',
        status: 'active',
        remaining: remaining,
        totalSessions: 20,
        validFrom: DateTime(2026, 1, 1),
        validUntil: DateTime(2030, 12, 31),
      );

  Future<BookingScreenData> load({
    required List<PassOption> passes,
    required List<MyBooking> bookings,
    CenterPolicy policy = CenterPolicy.fallback,
  }) async {
    final container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(_FakeHomeRepository(passes)),
        bookingRepositoryProvider.overrideWithValue(_FakeBookingRepository(bookings)),
        centerPolicyProvider.overrideWithValue(AsyncValue.data(policy)),
      ],
    );
    container.read(sessionProvider.notifier).set(
          const AppSession(
            uid: 'u1',
            role: 'member',
            centerId: 'c1',
            memberId: 'm1',
            memberName: '람',
          ),
        );
    return container.read(bookingViewModelProvider.future);
  }

  test('내 예약 목록의 confirmed 건수가 패스별 openBookings로 실린다', () async {
    final data = await load(
      passes: [
        passOption('p1', trainerId: 't1', remaining: 2),
        passOption('p2', trainerId: 't2', remaining: 5),
      ],
      bookings: [
        booking('b1', passId: 'p1'),
        booking('b2', passId: 'p1'),
        booking('b3', passId: 'p2'),
        // 이미 차감된 회차 — 다시 세면 이중 차감이다.
        booking('b4', passId: 'p2', status: 'completed'),
      ],
    );

    final p1 = data.myPasses.firstWhere((p) => p.passId == 'p1');
    final p2 = data.myPasses.firstWhere((p) => p.passId == 'p2');

    expect(p1.openBookings, 2);
    expect(p2.openBookings, 1);
    // 서버 판정과 같은 결론: p1은 잔여 2를 이미 다 물었고, p2는 4건 더 잡을 수 있다.
    expect(p1.hasBookingBudget, isFalse);
    expect(p2.bookingBudget, 4);
  });

  test('예약이 없으면 예산은 잔여 그대로', () async {
    final data = await load(
      passes: [passOption('p1', trainerId: 't1', remaining: 2)],
      bookings: const [],
    );

    expect(data.myPasses.single.openBookings, 0);
    expect(data.myPasses.single.bookingBudget, 2);
  });

  // 운영시간 배선 — 규칙 함수가 아니라 **뷰모델이 정책값을 실제로 넘기는지**를 본다.
  // 규칙 쪽 단언(booking_rules_test)이 다 통과해도 여기서 상수를 넘기면 회원 화면은
  // 그대로 09~21시에 갇힌다.
  group('센터 운영시간이 슬롯 목록에 반영된다', () {
    CenterPolicy hours(int open, int close) => CenterPolicy(
          slotCapacity: 3,
          cancelCutoffHours: 24,
          graceOnce: true,
          penaltyRate: 0.10,
          expiringDays: 7,
          maxHoldsPerPass: 2,
          maxHoldTotalDays: 30,
          openHour: open,
          closeHour: close,
        );

    Future<List<String>> slotKeys(CenterPolicy policy) async {
      final data = await load(
        passes: [passOption('p1', trainerId: 't1', remaining: 5)],
        bookings: const [],
        policy: policy,
      );
      return data.slots.map((s) => s.slotKey).toList();
    }

    test('06시 개장·23시 마지막 수업 → 18칸(첫 06시 · 마지막 23시)', () async {
      final today = DateFmt.todayKst();
      final keys = await slotKeys(hours(6, 23));

      expect(keys, hasLength(18));
      expect(keys.first, DateFmt.toSlotKey(today, 6));
      expect(keys.last, DateFmt.toSlotKey(today, 23));
    });

    test('폴백 정책(구버전 서버·조회 실패) → 09~21시 13칸 그대로', () async {
      final today = DateFmt.todayKst();
      final keys = await slotKeys(CenterPolicy.fallback);

      expect(keys, hasLength(13));
      expect(keys.first, DateFmt.toSlotKey(today, 9));
      expect(keys.last, DateFmt.toSlotKey(today, 21));
    });
  });
}

class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository(this.passes);

  final List<PassOption> passes;

  @override
  Future<Result<HomeSummary>> loadHome({
    required String memberId,
    String? preferredPassId,
  }) async =>
      Ok(HomeSummary(
        passes: passes,
        selectedPassId: passes.first.id,
        homeworkItems: const [],
        // 실제 repository가 하는 것과 같게 **로드 시점의 센터(KST) 오늘**을 싣는다
        // — 쓰기 가드(HomeSummary.homeworkDate)가 이 값을 기준으로 판정한다.
        homeworkDate: DateFmt.todayKst(),
      ));

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

class _FakeBookingRepository implements BookingRepository {
  _FakeBookingRepository(this.bookings);

  final List<MyBooking> bookings;

  @override
  Future<Result<List<Slot>>> loadSlots(DateTime date) async => const Ok([]);

  @override
  Future<Result<List<MyBooking>>> loadMyBookings(String memberId) async => Ok(bookings);

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
