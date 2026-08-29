import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/domain/records_repository.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';

// Home Work 토글 — 조용한 데이터 손실 두 건.
//
// ① 조회 실패 상태에서의 토글: POST /v1/hw-checks는 형제 항목의 done 배열 전체를
//    보내고 서버가 문서를 통째로 교체한다(store.SaveHwCheck의 `.Set()`). 오늘 체크
//    상태를 못 읽어 전부 false인 화면에서 한 칸을 누르면 서버의 완료 기록이 지워진다.
//    → 플래그가 서 있으면 **아무 요청도 나가면 안 된다**.
// ② 기록 탭 stale: 5개 탭이 StatefulShellRoute.indexedStack으로 동시에 mount된 채
//    유지되므로 탭 전환으로는 AsyncData가 폐기되지 않는다. 홈에서 체크해도 기록 탭의
//    "Home Work 주간 기록"이 예전 값 그대로 남았다 — 쓰기 성공이 무효화를 불러야 한다.
void main() {
  late _RecordingHomeRepository home;
  late _CountingRecordsRepository records;

  setUp(() {
    home = _RecordingHomeRepository();
    records = _CountingRecordsRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(home),
        recordsRepositoryProvider.overrideWithValue(records),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
      ],
    );
    container.read(sessionProvider.notifier).set(
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람'),
        );
    return container;
  }

  group('체크 상태를 모를 때는 토글이 서버로 나가지 않는다', () {
    test('homeworkChecksFailed=true면 POST 0회 — 서버의 완료 기록을 덮지 않는다', () async {
      home.checksFailed = true;
      final container = makeContainer();
      final summary = await container.read(homeViewModelProvider.future);

      await container.read(homeViewModelProvider.notifier).toggleHomework(summary.homeworkItems[2]);

      expect(home.submitted, isEmpty,
          reason: '한 칸만 아는 상태로 done 배열 전체를 보내면 서버의 완료 기록이 사라진다');
    });

    test('막았다는 사실을 회원에게 알린다 — 조용히 무시하면 "안 눌린 버튼"이 된다', () async {
      home.checksFailed = true;
      final container = makeContainer();
      final summary = await container.read(homeViewModelProvider.future);

      await container.read(homeViewModelProvider.notifier).toggleHomework(summary.homeworkItems[0]);

      final failure = container.read(homeworkToggleErrorProvider);
      expect(failure, isNotNull);
      expect(failure!.message, contains('불러오지 못했'));
    });

    test('낙관적 체크도 남기지 않는다 — 저장 안 된 체크가 체크된 채로 보이면 안 된다', () async {
      home.checksFailed = true;
      final container = makeContainer();
      final summary = await container.read(homeViewModelProvider.future);

      await container.read(homeViewModelProvider.notifier).toggleHomework(summary.homeworkItems[0]);

      final after = container.read(homeViewModelProvider).value!;
      expect(after.homeworkItems.map((i) => i.done), everyElement(isFalse));
    });

    test('조회 성공 상태에서는 종전대로 저장된다 — 잠금이 상시화되면 기능이 죽는다', () async {
      // 이 케이스가 없으면 "항상 return"으로도 위 3개가 통과한다.
      final container = makeContainer();
      final summary = await container.read(homeViewModelProvider.future);

      await container.read(homeViewModelProvider.notifier).toggleHomework(summary.homeworkItems[2]);

      expect(home.submitted, hasLength(1));
      // 형제 전체 배열이 나가되, 서버에서 읽은 값(true,true)이 보존된 채 3번만 뒤집힌다.
      expect(home.submitted.single, [true, true, true]);
    });
  });

  // ③ 자정 경계 — 23:50에 홈을 열고 00:05에 체크하면, 어제 목록으로 만든 done 배열이
  //    **오늘 문서**를 통째로 덮었다. 읽기는 repository가 로드 시점의 `todayKst()`로
  //    굳히고, 쓰기는 토글 순간의 시계를 **다시** 읽었기 때문이다. 같은 `.Set()`
  //    덮어쓰기지만 이쪽이 더 조용하다 — 회원은 어제 목록을 보고 있었을 뿐이고,
  //    지워지는 건 오늘 아침에 이미 체크해 둔 기록이다.
  //
  //    시계는 `withClock`으로 고정한다(UTC로 주입하고 기대값은 KST로 읽는다 — TZ 독립).
  group('자정을 넘긴 목록으로 오늘 문서를 덮지 않는다 (23:50 로드 → 00:05 체크)', () {
    /// KST 벽시계 2026-08-[day] [h]:[m]에 해당하는 절대 시각.
    DateTime kst(int day, int h, int m) => DateTime.utc(2026, 8, day, h - 9, m);

    /// 23:50에 홈을 로드한 컨테이너 — 반환 후 [clock]을 00:05로 옮기면 그대로
    /// "켜 둔 채 자정을 넘긴 화면"이 된다.
    Future<ProviderContainer> loadAt2350() async {
      final container = makeContainer();
      // 자정 재조회는 provider가 살아 있어야 일어난다(홈 탭은 indexedStack 상주).
      container.listen(homeViewModelProvider, (_, __) {});
      await container.read(homeViewModelProvider.future);
      return container;
    }

    test('POST가 나가지 않는다 — 어제 done 배열이 오늘 문서를 덮던 자리', () async {
      var now = kst(23, 23, 50);
      await withClock(Clock(() => now), () async {
        final container = await loadAt2350();
        final summary = container.read(homeViewModelProvider).value!;
        expect(summary.homeworkDate, DateTime(2026, 8, 23));

        // 회원은 아무것도 하지 않았다 — 시계만 흘렀다.
        now = kst(24, 0, 5);
        await container.read(homeViewModelProvider.notifier).toggleHomework(summary.homeworkItems[2]);

        expect(home.submitted, isEmpty,
            reason: '어제 목록의 done 배열이 오늘 문서를 통째로 교체한다 — 오늘 체크해 둔 기록이 사라진다');
      });
    });

    test('막았다는 사실을 회원에게 알린다', () async {
      var now = kst(23, 23, 50);
      await withClock(Clock(() => now), () async {
        final container = await loadAt2350();
        final summary = container.read(homeViewModelProvider).value!;

        now = kst(24, 0, 5);
        await container.read(homeViewModelProvider.notifier).toggleHomework(summary.homeworkItems[0]);

        final failure = container.read(homeworkToggleErrorProvider);
        expect(failure, isNotNull);
        expect(failure!.message, contains('날짜가 바뀌었어요'));
      });
    });

    test('낙관적 체크도 남기지 않는다 — 저장 안 된 체크가 체크된 채로 보이면 안 된다', () async {
      var now = kst(23, 23, 50);
      await withClock(Clock(() => now), () async {
        final container = await loadAt2350();
        final summary = container.read(homeViewModelProvider).value!;
        // 서버 값은 [true,true,false] — 3번만 뒤집히면 안 된다.
        now = kst(24, 0, 5);
        await container.read(homeViewModelProvider.notifier).toggleHomework(summary.homeworkItems[2]);

        expect(container.read(homeViewModelProvider).value!.homeworkItems.map((i) => i.done),
            [true, true, false]);
      });
    });

    test('막는 데서 끝내지 않고 오늘 목록을 다시 읽어 온다 — 그 뒤론 정상 저장된다', () async {
      var now = kst(23, 23, 50);
      await withClock(Clock(() => now), () async {
        final container = await loadAt2350();
        expect(home.loadCount, 1);
        final stale = container.read(homeViewModelProvider).value!;

        now = kst(24, 0, 5);
        await container.read(homeViewModelProvider.notifier).toggleHomework(stale.homeworkItems[2]);

        final fresh = await container.read(homeViewModelProvider.future);
        expect(home.loadCount, 2, reason: '막기만 하고 두면 회원은 이유 모를 잠긴 화면에 갇힌다');
        expect(fresh.homeworkDate, DateTime(2026, 8, 24));

        // 오늘 목록으로 갈린 뒤엔 종전대로 저장된다(가드가 상시화되면 기능이 죽는다).
        await container.read(homeViewModelProvider.notifier).toggleHomework(fresh.homeworkItems[2]);
        expect(home.submitted.single, [true, true, true]);
        expect(home.submittedDates.single, DateTime(2026, 8, 24));
      });
    });

    test('재조회해도 날짜가 안 맞으면 무한 재시도하지 않는다 — 그날치 한 번', () async {
      var now = kst(23, 23, 50);
      await withClock(Clock(() => now), () async {
        // 서버(혹은 기기 시계)가 계속 어제를 준다 — 재조회가 상황을 못 고치는 경우.
        home.loadedDate = DateTime(2026, 8, 23);
        final container = await loadAt2350();

        now = kst(24, 0, 5);
        final notifier = container.read(homeViewModelProvider.notifier);
        await notifier.toggleHomework(container.read(homeViewModelProvider).value!.homeworkItems[0]);
        await container.read(homeViewModelProvider.future);
        expect(home.loadCount, 2);

        notifier.refreshIfDateRolled();
        notifier.refreshIfDateRolled();
        await container.read(homeViewModelProvider.future);
        expect(home.loadCount, 2, reason: '날짜가 안 맞는 동안 계속 다시 부르면 홈 로드 5~6 왕복이 무한 반복된다');
      });
    });

    test('낙관적 토글의 copyWith가 날짜를 잃지 않는다 — 잃으면 가드가 열린다', () {
      // 이 값이 "지금"으로 되살아나면 어제 목록이 스스로 오늘이라고 주장하게 된다
      // (homeworkChecksFailed를 copyWith에서 이어받는 것과 같은 이유).
      final stale = HomeSummary(
        passes: const [],
        selectedPassId: 'p1',
        homeworkItems: const [],
        homeworkDate: DateTime(2026, 8, 23),
      );
      withClock(Clock.fixed(kst(24, 0, 5)), () {
        expect(stale.copyWith(homeworkItems: const []).homeworkDate, DateTime(2026, 8, 23));
      });
    });

    test('날짜가 그대로면 재조회하지 않는다 — 왕복 0', () async {
      await withClock(Clock.fixed(kst(23, 23, 50)), () async {
        final container = await loadAt2350();
        container.read(homeViewModelProvider.notifier).refreshIfDateRolled();
        await container.read(homeViewModelProvider.future);

        expect(home.loadCount, 1);
      });
    });
  });

  group('토글 성공은 기록 탭을 무효화한다 (indexedStack stale)', () {
    test('성공 후 기록 탭이 다시 로드된다', () async {
      final container = makeContainer();
      // 기록 탭이 mount되어 있는 상황 — indexedStack이라 홈과 동시에 살아 있다.
      container.listen(recordsViewModelProvider, (_, __) {});
      await container.read(recordsViewModelProvider.future);
      expect(records.loadCount, 1);

      final summary = await container.read(homeViewModelProvider.future);
      await container.read(homeViewModelProvider.notifier).toggleHomework(summary.homeworkItems[2]);
      await container.read(recordsViewModelProvider.future);

      expect(records.loadCount, 2, reason: '홈에서 체크했는데 기록 탭이 "0/3"으로 남는다');
    });

    test('저장 실패면 무효화하지 않는다 — 롤백된 값으로 기록 탭을 흔들 이유가 없다', () async {
      home.submitFails = true;
      final container = makeContainer();
      container.listen(recordsViewModelProvider, (_, __) {});
      await container.read(recordsViewModelProvider.future);

      final summary = await container.read(homeViewModelProvider.future);
      await container.read(homeViewModelProvider.notifier).toggleHomework(summary.homeworkItems[2]);

      expect(records.loadCount, 1);
    });
  });
}

class _RecordingHomeRepository implements HomeRepository {
  bool checksFailed = false;
  bool submitFails = false;

  /// 로드 시점 날짜를 강제로 고정한다(null이면 실제 `todayKst()`) — "23:50에 로드"를
  /// 시계 조작 없이도 재현하기 위한 손잡이.
  DateTime? loadedDate;

  /// loadHome 호출 횟수 — 자정 재조회가 실제로 일어났는지의 증거.
  int loadCount = 0;

  /// 실제로 서버에 나간 done 배열들 — "덮어쓰기가 일어났는가"의 유일한 증거.
  final List<List<bool>> submitted = [];

  /// 서버로 나간 (날짜, done) 쌍 — **어느 문서를 덮었는가**까지 본다.
  final List<DateTime> submittedDates = [];

  @override
  Future<Result<HomeSummary>> loadHome({
    required String memberId,
    String? preferredPassId,
  }) async {
    loadCount++;
    // 서버에는 [true,true,false]가 있다. 조회에 실패하면 폴백(전부 false)이 실린다
    // — 그 상태로 3번을 누르면 [false,false,true]가 저장되던 것이 이 버그다.
    final done = checksFailed ? [false, false, false] : [true, true, false];
    return Ok(HomeSummary(
      passes: [
        PassOption(
          id: 'p1',
          product: 'PT 20회',
          trainerId: 't1',
          status: 'active',
          remaining: 8,
          totalSessions: 20,
          validFrom: DateTime(2026, 1, 1),
          validUntil: DateTime(2030, 12, 31),
        ),
      ],
      selectedPassId: 'p1',
      homeworkItems: [
        for (var i = 0; i < 3; i++) HomeworkItem(hwId: 'h1', index: i, name: '운동$i', done: done[i]),
      ],
      // 실제 repository가 하는 것과 같게 **로드 시점의 센터(KST) 오늘**을 싣는다
      // — 쓰기 가드(HomeSummary.homeworkDate)가 이 값을 기준으로 판정한다.
      homeworkDate: loadedDate ?? DateFmt.todayKst(),
      homeworkChecksFailed: checksFailed,
    ));
  }

  @override
  Future<Result<void>> submitHomeworkChecks({
    required String memberId,
    required String hwId,
    required DateTime date,
    required List<bool> done,
  }) async {
    submitted.add(done);
    submittedDates.add(date);
    return submitFails ? const Err(NetworkFailure()) : const Ok(null);
  }

  @override
  Future<Result<void>> selfCheckIn({String? scannedToken}) async => const Ok(null);
}

class _CountingRecordsRepository implements RecordsRepository {
  int loadCount = 0;

  @override
  Future<Result<RecordsData>> load(String memberId) async {
    loadCount++;
    return const Ok(RecordsData(
      workoutLogs: [],
      homeworkWeeks: [],
      inbodyRecords: [],
      bodyPhotos: BodyPhotoAlbum.empty,
    ));
  }

  // 이 테스트는 Home Work 토글만 본다 — 인바디 쓰기가 불리면 결함이므로 즉시 실패.
  @override
  Future<Result<void>> createInbody({required String memberId, required InbodyDraft draft}) =>
      throw UnsupportedError('Home Work 토글이 인바디를 저장하지 않는다');

  @override
  Future<Result<void>> deleteInbody(String id) =>
      throw UnsupportedError('Home Work 토글이 인바디를 삭제하지 않는다');
}
