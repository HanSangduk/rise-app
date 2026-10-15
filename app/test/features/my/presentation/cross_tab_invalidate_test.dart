// 뮤테이션 뒤 **다른 탭의 출처**가 함께 새로고침되는지(P73).
//
// 두 결함 모두 "자기 provider만 refresh"였다:
//   ① 예약 취소/생성 → 마이 탭(잔여·이용내역)이 옛 값 — 취소 확인 다이얼로그가 "차감 여부는
//      마이 탭 이용내역에서 확인할 수 있어요"라고 약속하는데 그 탭이 갱신되지 않았다.
//   ② 마이 탭 동의 ON → 체형 촬영 셔터의 동의 게이트(myProfileProvider)가 옛 값 — 기록 탭이
//      그 provider를 붙들고 있으면(indexedStack) "마이 탭에서 동의해주세요"가 앱을 껐다 켜기
//      전까지 풀리지 않았다. 안내대로 했는데 열리지 않는 문.
//
// 함수 시험이 아니라 **배선** 시험이다(함정 ⑩): 뷰모델 메서드가 성공한 뒤 다른 provider의
// 로드 횟수가 실제로 늘어야 한다.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/member_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/session/session_store.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_repository.dart';
import 'package:rise_member/features/booking/presentation/booking_view_model.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/domain/my_repository.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';

void main() {
  const me = AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람');

  late _CountingMyRepository myRepo;
  late _CountingMemberApi memberApi;
  late ProviderContainer container;

  setUp(() {
    memberApi = _CountingMemberApi();
    // 실서버에서는 두 엔드포인트가 같은 회원 문서를 읽고 쓴다 — 가짜도 그 계약을 지켜야
    // "저장 뒤 다시 읽으면 새 값이 보인다"를 검증할 수 있다.
    myRepo = _CountingMyRepository(memberApi);
    container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(_FakeHomeRepository()),
        bookingRepositoryProvider.overrideWithValue(const _FakeBookingRepository()),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        myRepositoryProvider.overrideWithValue(myRepo),
        memberApiProvider.overrideWithValue(memberApi),
        sessionStoreProvider.overrideWithValue(_NoopSessionStore()),
      ],
    );
    container.read(sessionProvider.notifier).set(me);
  });

  group('예약 뮤테이션 → 마이 탭 동반 갱신', () {
    test('취소가 성공하면 마이 탭 요약을 다시 읽는다', () async {
      // 마이 탭이 indexedStack에 살아 있는 상태를 흉내 낸다.
      container.listen(myViewModelProvider, (_, __) {});
      await container.read(myViewModelProvider.future);
      expect(myRepo.loads, 1);

      final result = await container.read(bookingViewModelProvider.notifier).cancel('b1');
      expect(result, isA<Ok<void>>());
      await container.read(myViewModelProvider.future);
      expect(myRepo.loads, 2, reason: '"마이 탭 이용내역에서 확인할 수 있어요"가 거짓이 된다');
    });

    test('예약이 성공해도 마이 탭 요약을 다시 읽는다', () async {
      container.listen(myViewModelProvider, (_, __) {});
      await container.read(myViewModelProvider.future);
      expect(myRepo.loads, 1);

      final result = await container
          .read(bookingViewModelProvider.notifier)
          .book(slotKey: DateFmt.toSlotKey(DateFmt.todayKst(), 10), passId: 'p1');
      expect(result, isA<Ok<void>>());
      await container.read(myViewModelProvider.future);
      expect(myRepo.loads, 2);
    });
  });

  group('동의 저장 → 촬영 게이트 동반 갱신', () {
    test('updateConsent가 성공하면 myProfileProvider를 다시 읽는다', () async {
      // 기록 탭(포즈 칩)·카메라 뷰모델처럼 프로필을 붙들고 있는 구독자.
      container.listen(myProfileProvider, (_, __) {});
      await container.read(myProfileProvider.future);
      expect(memberApi.fetches, 1);

      final result = await container
          .read(myViewModelProvider.notifier)
          .updateConsent(general: true, sensitive: true);
      expect(result, isA<Ok<void>>());
      final profile = await container.read(myProfileProvider.future);
      expect(memberApi.fetches, 2, reason: '셔터의 동의 게이트가 옛 동의 상태를 본다');
      expect(profile.consent?.sensitive, isTrue);
    });

    test('updateConsent가 실패하면 프로필을 건드리지 않는다', () async {
      myRepo.failConsent = true;
      container.listen(myProfileProvider, (_, __) {});
      await container.read(myProfileProvider.future);

      final result = await container
          .read(myViewModelProvider.notifier)
          .updateConsent(general: true, sensitive: true);
      expect(result, isA<Err<void>>());
      await container.read(myProfileProvider.future);
      expect(memberApi.fetches, 1);
    });
  });
}

class _CountingMyRepository implements MyRepository {
  _CountingMyRepository(this._memberApi);

  final _CountingMemberApi _memberApi;
  int loads = 0;
  bool failConsent = false;

  @override
  Future<Result<MySummary>> load(String memberId) async {
    loads++;
    return const Ok(MySummary(
      passes: [],
      ledgerByPass: {},
      contracts: [],
      consent: ConsentState(general: true, sensitive: false),
    ));
  }

  @override
  Future<Result<void>> updateConsent({
    required String memberId,
    required bool general,
    required bool sensitive,
  }) async {
    if (failConsent) return const Err(UnknownFailure());
    await _memberApi.updateConsent(memberId: memberId, general: general, sensitive: sensitive);
    return const Ok(null);
  }

  @override
  Future<Result<void>> requestHold({
    required String passId,
    required DateTime from,
    required DateTime to,
    String? reason,
  }) async =>
      const Ok(null);

  @override
  Future<Result<void>> resumeHold(String passId) async => const Ok(null);

  @override
  Future<Result<void>> signContract(String contractId, {String? signaturePng}) async => const Ok(null);

  @override
  Future<Result<AccountDeletionSummary>> deleteAccount() => throw UnimplementedError();
}

/// 프로필 조회 횟수를 센다 — 동의 저장 뒤 두 번째 읽기가 실제로 나가는지가 핵심이다.
class _CountingMemberApi extends MemberApi {
  _CountingMemberApi() : super(Dio());

  int fetches = 0;
  bool sensitive = false;

  @override
  Future<MemberDto> fetchMyProfile() async {
    fetches++;
    return MemberDto(
      id: 'm1',
      name: '람',
      phone: '010-1234-5678',
      consent: ConsentDto(general: true, sensitive: sensitive),
    );
  }

  @override
  Future<void> updateConsent({
    required String memberId,
    required bool general,
    required bool sensitive,
  }) async {
    this.sensitive = sensitive;
  }
}

class _FakeHomeRepository implements HomeRepository {
  @override
  Future<Result<HomeSummary>> loadHome({required String memberId, String? preferredPassId}) async =>
      Ok(HomeSummary(
        passes: [
          PassOption(
            id: 'p1',
            product: 'PT 20회',
            trainerId: 't1',
            trainerName: '정혜린',
            status: 'active',
            remaining: 5,
            totalSessions: 20,
            validFrom: DateTime(2026, 1, 1),
            validUntil: DateTime(2030, 12, 31),
          ),
        ],
        selectedPassId: 'p1',
        homeworkItems: const [],
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
  const _FakeBookingRepository();

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

class _NoopSessionStore implements SessionStore {
  @override
  Future<AppSession?> read(String uid) async => null;

  @override
  Future<void> write(AppSession session) async {}

  @override
  Future<void> clear() async {}
}
