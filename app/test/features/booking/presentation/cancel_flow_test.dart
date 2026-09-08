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
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_repository.dart';
import 'package:rise_member/features/booking/presentation/booking_screen.dart';
import 'package:rise_member/features/booking/presentation/booking_view_model.dart';
import 'package:rise_member/features/booking/presentation/widgets/my_bookings_list.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';

// HIGH — 컷오프가 지나면 앱이 취소 버튼을 없앴다. 서버는 취소를 막은 적이 없다:
// `CancelBooking` 주석이 명시적이다 — "취소 자체는 항상 허용한다(막으면 노쇼로
// 위장할 유인만 커짐)". `CancelAtomic`은 무조건 실행되고, 컷오프 경과는 원장
// 페널티(정책상 최초 1회 유예)만 붙인다.
//
// 앱이 그 문을 닫으면 회원에게 남는 선택지는 **노쇼뿐**이다 — 차감은 똑같이 일어나고
// 코치는 통보조차 못 받는다. 그래서 취소는 항상 열어 두되, 컷오프가 지났으면 결과를
// 정확히 말하고 확인을 받는다.
//
// "유예가 남았는지"는 원장 이력에 달려 있는데 예약 탭은 원장을 로드하지 않는다 —
// 단정하지 않고 두 경우를 다 말한다(그리고 정책이 유예를 끄면 그 문장을 뺀다).
void main() {
  late _FakeHomeRepository homeRepo;
  late _FakeBookingRepository bookingRepo;

  setUp(() {
    homeRepo = _FakeHomeRepository();
    bookingRepo = _FakeBookingRepository();
  });

  /// 지금부터 [hours] 뒤 정시의 slotKey. 컷오프(24h) 안/밖을 만드는 데 쓴다.
  String slotKeyIn(int hours) {
    final at = DateFmt.nowKst().add(Duration(hours: hours));
    return DateFmt.toSlotKey(at, at.hour);
  }

  MyBooking booking(String slotKey) => MyBooking(
        id: 'b1',
        slotKey: slotKey,
        passId: 'p1',
        trainerId: 't1',
        trainerName: '정혜린',
        kind: 'pt',
        status: 'confirmed',
      );

  /// 서버가 준 정책 — 숫자는 폴백(24h/유예)과 같지만 `isFallback`이 false다.
  ///
  /// 무료/차감 판정 문구는 정책을 **아는** 상태에서만 나온다(P56 H2 — 폴백이면 다이얼로그가
  /// "확인할 수 없어요"라고 말한다). 그래서 판정 문구를 재는 기본값은 서버 값이고, 폴백은
  /// 아래 '정책을 못 받았으면' 테스트가 따로 잰다.
  const serverPolicy = CenterPolicy(
    slotCapacity: 3,
    cancelCutoffHours: 24,
    graceOnce: true,
    penaltyRate: 0.10,
    expiringDays: 7,
    maxHoldsPerPass: 2,
    maxHoldTotalDays: 30,
  );

  Future<void> pump(
    WidgetTester tester, {
    required MyBooking myBooking,
    CenterPolicy policy = serverPolicy,
  }) async {
    bookingRepo.bookings = [myBooking];
    final container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(homeRepo),
        bookingRepositoryProvider.overrideWithValue(bookingRepo),
        centerPolicyProvider.overrideWithValue(AsyncValue.data(policy)),
        staffMapProvider.overrideWithValue(const AsyncValue.data(<String, StaffDto>{})),
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
    // 슬롯 목록이 전부 "지남"이 되지 않게 내일 기준(booking_screen_test와 같은 이유).
    container
        .read(selectedBookingDateProvider.notifier)
        .select(DateFmt.todayKst().add(const Duration(days: 1)));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const BookingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // "내 예약" 카드는 운영시간 13칸 슬롯 아래에 있어 첫 화면 밖이다(ListView는
    // 보이는 만큼만 만든다) — 스크롤해 실제로 붙여 놓고 검증한다.
    await tester.scrollUntilVisible(
      find.byType(MyBookingsList),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// "내 예약" 행의 취소 버튼(슬롯 목록의 "예약" 버튼과 라벨이 겹치지 않는다).
  Finder cancelButton() => find.widgetWithText(RiseButton, '취소');

  /// 확인 다이얼로그 안의 문구만 본다 — 카드 하단 안내에도 "차감"·"무료" 같은 단어가
  /// 있어서, 화면 전체로 찾으면 다이얼로그가 말하지 않은 것도 말한 것처럼 통과한다.
  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.textContaining(text));

  Future<void> tapCancel(WidgetTester tester) async {
    await tester.ensureVisible(cancelButton());
    await tester.pumpAndSettle();
    await tester.tap(cancelButton());
    await tester.pumpAndSettle();
  }

  group('컷오프가 지난 예약', () {
    testWidgets('취소 버튼이 그대로 살아 있다 — 예전엔 탭 타깃 없는 "확정" 배지만 남았다', (tester) async {
      await pump(tester, myBooking: booking(slotKeyIn(2))); // 2시간 뒤 = 컷오프(24h) 안

      expect(cancelButton(), findsOneWidget);
      expect(tester.widget<RiseButton>(cancelButton()).onPressed, isNotNull);
      expect(find.text('확정'), findsNothing);
    });

    testWidgets('확인 문구가 결과(세션 1회 차감)를 정확히 말한다', (tester) async {
      await pump(tester, myBooking: booking(slotKeyIn(2)));

      await tapCancel(tester);

      expect(inDialog('세션 1회가 차감돼요'), findsOneWidget);
      expect(inDialog('취소 마감(24시간 전)이 지나'), findsOneWidget);
      // 유예 잔여는 앱이 모른다 — 두 경우를 다 말하고 확인처를 안내한다.
      expect(inDialog('최초 1회는 유예되지만, 이미 유예를 받았다면'), findsOneWidget);
      expect(inDialog('마이 탭 이용내역'), findsOneWidget);
    });

    testWidgets('확인하면 실제로 취소 요청이 나간다 — 서버는 거부하지 않는다', (tester) async {
      await pump(tester, myBooking: booking(slotKeyIn(2)));

      await tapCancel(tester);
      await tester.tap(find.text('취소하기'));
      await tester.pumpAndSettle();

      expect(bookingRepo.cancelled, ['b1']);
      expect(find.text('예약을 취소했어요'), findsOneWidget);
    });

    testWidgets('"아니요"면 아무 요청도 나가지 않는다', (tester) async {
      await pump(tester, myBooking: booking(slotKeyIn(2)));

      await tapCancel(tester);
      await tester.tap(find.text('아니요'));
      await tester.pumpAndSettle();

      expect(bookingRepo.cancelled, isEmpty);
    });

    testWidgets('센터가 유예를 끄면 없는 유예를 약속하지 않는다', (tester) async {
      await pump(
        tester,
        myBooking: booking(slotKeyIn(2)),
        policy: const CenterPolicy(
          slotCapacity: 3,
          cancelCutoffHours: 24,
          graceOnce: false,
          penaltyRate: 0.10,
          expiringDays: 7,
          maxHoldsPerPass: 2,
          maxHoldTotalDays: 30,
        ),
      );

      await tapCancel(tester);

      expect(inDialog('세션 1회가 차감돼요'), findsOneWidget);
      expect(inDialog('유예'), findsNothing);
    });
  });

  group('정책을 못 받았으면 무료라고 단정하지 않는다 (P56 H2 — 이 자리가 `isFallback` dartdoc의 사고다)', () {
    testWidgets('폴백이면 다이얼로그가 "확인할 수 없어요"라고 말하고 마감 시간도 찍지 않는다', (tester) async {
      // 폴백 24h로 계산하면 48시간 뒤 예약은 `free=true` → 경고가 아예 안 뜬 채 회원은
      // "취소할까요?"만 읽고 확정한다. 센터 실제 마감이 72시간이면 그 취소는 차감이다.
      await pump(tester, myBooking: booking(slotKeyIn(48)), policy: CenterPolicy.fallback);

      await tapCancel(tester);

      expect(inDialog('취소 정책을 불러오지 못해서'), findsOneWidget);
      expect(inDialog('차감되는지 확인할 수 없어요'), findsOneWidget);
      expect(inDialog('24시간'), findsNothing, reason: '폴백 마감을 사실처럼 말했다');
      expect(inDialog('마이 탭 이용내역'), findsOneWidget); // 확인처는 여전히 안내한다
    });
  });

  group('컷오프 이전 예약', () {
    testWidgets('취소 버튼은 그대로이고 확인 문구엔 차감 안내가 없다', (tester) async {
      await pump(tester, myBooking: booking(slotKeyIn(48))); // 48시간 뒤 = 무차감

      expect(cancelButton(), findsOneWidget);

      await tapCancel(tester);

      expect(inDialog('예약을 취소할까요?'), findsOneWidget);
      expect(inDialog('차감'), findsNothing);
      expect(inDialog('취소 마감'), findsNothing);
    });
  });

  // 이 화면에서 굳는 판정 중 **유일하게 돈이 걸린 자리**(P17). 다이얼로그를 열어 둔
  // 채 컷오프를 넘기면 회원은 "그냥 취소할까요?"만 읽고 확인하는데, 서버는 그 시각
  // 기준으로 세션 1회를 차감한다(노쇼와 같은 원장 처리). 창이 좁아도 결과가
  // 비가역이라 열어 둔 문구가 스스로 바뀌어야 한다 — 경계는 컷오프 시각 하나뿐이다.
  group('다이얼로그를 열어 둔 채 컷오프를 넘긴다', () {
    /// KST 벽시계 2026-08-23 [h]:[m]:[s]에 해당하는 절대 시각.
    DateTime kst(int h, int m, [int s = 0]) => DateTime.utc(2026, 8, 23, h - 9, m, s);

    testWidgets('무차감 문구가 차감 안내로 바뀐다 — 아무도 새로고침하지 않았는데', (tester) async {
      // 8/24 19:00 예약 · 컷오프 24시간 → 경계는 8/23 19:00. 18:50에 다이얼로그를 연다.
      var now = kst(18, 50);
      await withClock(Clock(() => now), () async {
        await pump(tester, myBooking: booking('20260824-19'));
        await tapCancel(tester);
        expect(inDialog('차감'), findsNothing);

        now = kst(19, 0, 1);
        await tester.pump(const Duration(minutes: 10, seconds: 2));
        await tester.pumpAndSettle();

        expect(inDialog('세션 1회가 차감돼요'), findsOneWidget,
            reason: '무차감인 줄 알고 누른 확인이 세션 1회를 태운다 — 되돌릴 수 없다');
        expect(inDialog('취소 마감(24시간 전)이 지나'), findsOneWidget);
      });
    });

    testWidgets('컷오프를 안 넘기면 문구는 그대로 — 없는 차감을 겁주지 않는다', (tester) async {
      var now = kst(18, 50);
      await withClock(Clock(() => now), () async {
        await pump(tester, myBooking: booking('20260824-19'));
        await tapCancel(tester);

        now = kst(18, 59);
        await tester.pump(const Duration(minutes: 9));
        await tester.pumpAndSettle();

        expect(inDialog('차감'), findsNothing);
      });
    });
  });

  group('안내 문구', () {
    testWidgets('컷오프 이후에도 취소가 가능하다는 사실을 카드 하단이 말한다', (tester) async {
      await pump(tester, myBooking: booking(slotKeyIn(48))); // 기본 = 서버 정책

      // 예전 문구는 "N시간 전까지 무료예요."에서 끊겨, 이후엔 취소가 아예 안 되는
      // 것처럼 읽혔다(그리고 버튼이 실제로 사라져 그 오독을 확증해줬다).
      expect(find.textContaining('24시간 전까지 무료 · 이후엔 세션 1회가 차감돼요'), findsOneWidget);
    });

    testWidgets('정책을 못 받았으면 시간·팀 수를 말하지 않는다 — 차감된다는 사실만 (P56 H1)', (tester) async {
      // 폴백 24시간을 사실처럼 찍으면 센터 실제 마감이 48시간일 때 그 문구를 믿고
      // 30시간 전에 취소한 회원이 차감된다(`isFallback` dartdoc의 사고).
      await pump(tester, myBooking: booking(slotKeyIn(48)), policy: CenterPolicy.fallback);

      expect(find.textContaining('24시간 전까지'), findsNothing, reason: '모르는 값을 사실처럼 말했다');
      expect(find.textContaining('시간당 최대'), findsNothing);
      expect(find.textContaining('취소 정책을 불러오지 못해'), findsOneWidget);
      expect(find.textContaining('세션 1회가 차감돼요'), findsOneWidget, reason: '대가는 폴백이어도 말한다');
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
      // 실제 repository가 하는 것과 같게 **로드 시점의 센터(KST) 오늘**을 싣는다
      // — 쓰기 가드(HomeSummary.homeworkDate)가 이 값을 기준으로 판정한다.
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

class _FakeBookingRepository implements BookingRepository {
  List<MyBooking> bookings = const [];
  final cancelled = <String>[];

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
  Future<Result<void>> cancel(String bookingId) async {
    cancelled.add(bookingId);
    bookings = bookings.where((b) => b.id != bookingId).toList();
    return const Ok(null);
  }

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
