import 'dart:async';

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
import 'package:rise_member/core/widgets/trainer_avatar.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_repository.dart';
import 'package:rise_member/features/booking/presentation/booking_screen.dart';
import 'package:rise_member/features/booking/presentation/booking_view_model.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';

// 계약 v2.0 — "퇴사 여부"의 출처가 두 개라 한 화면 안에서 서로 모순되던 문제.
//
// 같은 사실을 두 곳에서 읽었다: repository가 화면 로드마다 새로 만드는 도메인
// 플래그(Pass.trainerInactive)와, 15분 TTL 캐시인 staffMapProvider의 StaffDto.status.
//   · 확정 시트 — 라벨은 신선한 플래그로 "정혜린 코치 (퇴사)"인데 그 옆 아바타는
//     캐시 DTO를 그대로 받아 총천연색이었다.
//   · 프로필 시트 — 칩은 "(퇴사)"라고 말하는데, 그 칩이 여는 시트는 캐시로
//     isInactive를 판정해 퇴사 배지도 안내도 없이 "아직 소개가 등록되지 않았어요"로
//     떨어졌다. 퇴사를 설명하는 **유일한 자리**가 설명을 못 한 것이다.
//
// 통일 방향: 도메인 플래그가 진실, 캐시는 사진·색·소개 같은 표시용 부가 정보만.
// (근거는 booking_screen의 _withDomainStatus 주석 — 신선도가 곧 일관성인 경우다.)
void main() {
  late _FakeHomeRepository homeRepo;
  late _FakeBookingRepository bookingRepo;

  setUp(() {
    homeRepo = _FakeHomeRepository();
    bookingRepo = _FakeBookingRepository();
  });

  /// 캐시(staffMap)와 도메인 플래그(trainerInactive)를 따로 세팅해 어긋난 상황을 만든다.
  /// [staffMap]이 null이면 캐시 미로드(로딩) 상태.
  Future<ProviderContainer> pumpBooking(
    WidgetTester tester, {
    required bool passTrainerInactive,
    Map<String, StaffDto>? staffMap,
    String? trainerName = '정혜린',
  }) async {
    homeRepo
      ..trainerInactive = passTrainerInactive
      ..trainerName = trainerName;
    final container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(homeRepo),
        bookingRepositoryProvider.overrideWithValue(bookingRepo),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        if (staffMap == null)
          // 로딩 고정 — 최초 진입(캐시가 아직 안 찬 상태)을 그대로 재현한다.
          staffMapProvider.overrideWith((ref) => Completer<Map<String, StaffDto>>().future)
        else
          staffMapProvider.overrideWithValue(AsyncValue.data(staffMap)),
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
    // 슬롯은 운영시간(09~21시)으로 합성된다 — 오늘로 두면 실행 시각에 따라 전부
    // "지남"이 될 수 있어(21시 이후) 예약 버튼 유무가 흔들린다. 항상 내일 기준.
    //
    // 기준축은 **KST**다(selectedBookingDateProvider의 기본값·SlotList의 "지남"
    // 판정과 같은 축). 기기 로컬로 만들면 KST보다 뒤에 있는 지역에서 로컬의
    // "내일"이 KST의 "오늘"과 겹쳐 오전 슬롯이 전부 "지남"이 된다.
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
    return container;
  }

  /// 스태프 캐시가 아직 "현직"이라고 알고 있는 상태(TTL 15분 안에 코치가 퇴사).
  const staleActiveCache = {
    't1': StaffDto(
      uid: 't1',
      name: '정혜린',
      color: '#f43f5e',
      profile: StaffProfileDto(title: '퍼포먼스 트레이너', careerYears: 7),
    ),
  };

  group('퇴사(신선) + 캐시는 아직 현직', () {
    testWidgets('칩 라벨과 아바타가 같은 답을 쓴다', (tester) async {
      await pumpBooking(tester, passTrainerInactive: true, staffMap: staleActiveCache);

      expect(find.text('내 코치 (정혜린 · 퇴사)'), findsOneWidget);
      // 예전엔 "(퇴사)" 라벨 옆에 총천연색 아바타가 붙었다.
      final avatar = tester.widget<TrainerAvatar>(find.byType(TrainerAvatar).first);
      expect(avatar.inactive, isTrue);
    });

    testWidgets('칩 라벨은 정규화된 이름만 쓴다 — 공백이 괄호 안으로 새지 않는다', (tester) async {
      // 예전엔 isUnresolved()로 trim 판정만 하고 보간은 원본(trainerName!)이라
      // " 정혜린 "이 "내 코치 ( 정혜린  · 퇴사)"로 그대로 렌더됐다.
      await pumpBooking(
        tester,
        passTrainerInactive: true,
        staffMap: staleActiveCache,
        trainerName: ' 정혜린 ',
      );

      expect(find.text('내 코치 (정혜린 · 퇴사)'), findsOneWidget);
    });

    testWidgets('프로필 시트가 퇴사를 설명한다 — 이 화면에서 그걸 말하는 유일한 자리', (tester) async {
      await pumpBooking(tester, passTrainerInactive: true, staffMap: staleActiveCache);

      await tester.tap(find.text('코치 소개'));
      await tester.pumpAndSettle();

      expect(find.textContaining('활동하지 않는 코치'), findsOneWidget);
      // 시트 안의 퇴사 배지(뒤에 깔린 슬롯 목록 안내 배지와 구분).
      expect(
        find.descendant(of: find.byType(BottomSheet), matching: find.text('퇴사')),
        findsOneWidget,
      );
      expect(find.textContaining('아직 소개가 등록되지 않았어요'), findsNothing);
    });
  });

  group('현직(신선) + 캐시는 퇴사로 낡음', () {
    const staleRetiredCache = {
      't1': StaffDto(uid: 't1', name: '정혜린', status: 'inactive', color: '#f43f5e'),
    };

    testWidgets('반대 방향에서도 화면은 한 답만 말한다(칩·아바타·시트)', (tester) async {
      await pumpBooking(tester, passTrainerInactive: false, staffMap: staleRetiredCache);

      expect(find.text('내 코치 (정혜린)'), findsOneWidget);
      final avatar = tester.widget<TrainerAvatar>(find.byType(TrainerAvatar).first);
      expect(avatar.inactive, isFalse);

      await tester.tap(find.text('코치 소개'));
      await tester.pumpAndSettle();

      expect(find.text('퇴사'), findsNothing);
      expect(find.textContaining('활동하지 않는 코치'), findsNothing);
    });

    testWidgets('예약 확정 시트의 아바타도 라벨과 어긋나지 않는다', (tester) async {
      // 확정 시트는 라벨(도메인 플래그)과 아바타(캐시 DTO)를 따로 받던 자리다.
      // 예전엔 라벨엔 "(퇴사)"가 없는데 아바타만 흑백/무채색으로 떨어졌다.
      await pumpBooking(tester, passTrainerInactive: false, staffMap: staleRetiredCache);

      await tester.tap(find.widgetWithText(RiseButton, '예약').first);
      await tester.pumpAndSettle();

      final avatar = tester.widget<TrainerAvatar>(
        find.descendant(of: find.byType(BottomSheet), matching: find.byType(TrainerAvatar)),
      );
      expect(avatar.inactive, isFalse);
      expect(find.text('정혜린 코치 · PT 20회'), findsOneWidget);
    });
  });

  group('퇴사 코치는 확정 시트까지 가지도 못한다', () {
    testWidgets('"내 코치" 모드의 슬롯에 살아 있는 예약 버튼이 없다', (tester) async {
      // A 결함의 화면 단위 회귀 — 기본 모드(ShowMyCoachOnly=true)에서 확인한다.
      await pumpBooking(tester, passTrainerInactive: true, staffMap: staleActiveCache);

      expect(find.widgetWithText(RiseButton, '예약'), findsNothing);
      expect(find.widgetWithText(RiseButton, '예약 불가'), findsWidgets);
    });
  });

  // 스태프 조회(GET /v1/staff)가 통째로 실패한 상태. 예전엔 repository가
  // fetchAll()을 가드 없이 맨 먼저 await해서 이 탭이 통째로 에러 화면이 됐다.
  // 지금은 best-effort라 본문은 그대로 살고, 이름·퇴사 여부만 **함께** 사라진다
  // (판단 근거는 staff_directory의 staffMapReaderProvider 주석).
  group('스태프 조회 실패 — 부가 정보만 잃는다', () {
    testWidgets('예약 탭은 살아 있고, 없는 이름으로 현직/퇴사를 말하지 않는다', (tester) async {
      await pumpBooking(
        tester,
        // 맵이 비면 repository도 이름과 상태를 함께 잃는다 — 그 모양 그대로 재현.
        passTrainerInactive: false,
        trainerName: null,
        staffMap: null,
      );

      // 본문(슬롯·예약 버튼)은 그대로 — 디렉토리 장애로 예약을 막지 않는다.
      expect(find.widgetWithText(RiseButton, '예약'), findsWidgets);
      // 이름이 없으니 코치 문구는 통째로 생략된다 — "(퇴사)"도, 그 반대 주장도 없다.
      expect(find.text('내 코치'), findsOneWidget);
      expect(find.textContaining('퇴사'), findsNothing);
      // 프로필 링크도 뜨지 않으므로 "모른다"를 현직으로 위장하는 자리가 없다.
      expect(find.text('코치 소개'), findsNothing);
    });
  });

  group('캐시 미로드(최초 진입)', () {
    testWidgets('현직이면 퇴사로 단정하지 않고 재시도를 안내한다', (tester) async {
      await pumpBooking(tester, passTrainerInactive: false, staffMap: null);

      expect(find.text('내 코치 (정혜린)'), findsOneWidget);

      await tester.tap(find.text('코치 소개'));
      await tester.pumpAndSettle();

      // "모르는 걸 퇴사로 단정하지 않는다"(계약 v2.0 승격 규약)가 유지되는지.
      expect(find.text('퇴사'), findsNothing);
      expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    });

    testWidgets('퇴사면 캐시가 없어도 시트가 퇴사를 안내한다', (tester) async {
      await pumpBooking(tester, passTrainerInactive: true, staffMap: null);

      await tester.tap(find.text('코치 소개'));
      await tester.pumpAndSettle();

      // 퇴사 > 캐시 미로드 우선순위(trainer_profile_sheet) — 확정 사실을 먼저 말한다.
      expect(find.textContaining('활동하지 않는 코치'), findsOneWidget);
      expect(find.textContaining('불러오지 못했어요'), findsNothing);
    });
  });
}

class _FakeHomeRepository implements HomeRepository {
  bool trainerInactive = false;
  String? trainerName = '정혜린';

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
          trainerName: trainerName,
          // 도메인 플래그 — repository가 조회할 때마다 새로 만드는 신선한 값.
          trainerInactive: trainerInactive,
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
  @override
  Future<Result<List<Slot>>> loadSlots(DateTime date) async => const Ok([]);

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
