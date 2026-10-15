import 'dart:async';

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

// Home Work 토글 — 같은 hwId의 제출은 **직렬**이다(P73).
//
// POST /v1/hw-checks는 형제 done 배열 전체를 보내고 서버가 문서를 통째로 교체한다. 항목을
// 훑듯 연달아 체크하면 종전엔 두 POST가 서로 다른 배열([T,F,F]·[T,T,F])로 **동시에** 나갔고,
// 나중에 도착한 쪽이 이겼다 — 네트워크에서 순서가 뒤집히면 방금 체크한 칸이 서버에서
// 사라진다(둘 다 Ok라 롤백도 토스트도 없다). 이제 앞 요청이 끝난 뒤에 보내고, 보내는 시점의
// 최신 상태로 배열을 다시 만든다.
void main() {
  late _GatedHomeRepository home;

  setUp(() => home = _GatedHomeRepository());

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(home),
        recordsRepositoryProvider.overrideWithValue(_IdleRecordsRepository()),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
      ],
    );
    container.read(sessionProvider.notifier).set(
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람'),
        );
    // 홈 탭은 indexedStack에 상주해 provider가 살아 있다 — 구독 없이 이벤트 루프를 한 번 돌리면
    // autoDispose가 provider를 지워 "폐기된 Ref" 예외·null 상태가 되어 시험이 현실과 달라진다.
    container.listen(homeViewModelProvider, (_, __) {});
    return container;
  }

  Future<void> flushMicrotasks() => Future<void>.delayed(Duration.zero);

  test('연달아 두 칸을 체크해도 요청은 한 번에 하나 — 두 번째는 첫 응답 뒤에, 최신 배열로 나간다', () async {
    final container = makeContainer();
    final summary = await container.read(homeViewModelProvider.future);
    final vm = container.read(homeViewModelProvider.notifier);

    home.holdNext(); // 첫 POST를 서버에서 붙잡아 둔다
    final first = vm.toggleHomework(summary.homeworkItems[0]);
    final second = vm.toggleHomework(summary.homeworkItems[1]);
    await flushMicrotasks();

    // 화면은 즉시 둘 다 체크(낙관적) — 서버 왕복을 기다리지 않는다.
    expect(container.read(homeViewModelProvider).value!.homeworkItems.map((i) => i.done), [true, true, false]);
    // 서버로는 **하나만** 나가 있다. 종전엔 여기서 [T,F,F]와 [T,T,F] 두 건이 동시에 떠 있었다.
    expect(home.submitted, hasLength(1), reason: '같은 hwId의 두 번째 POST가 첫 응답 전에 나갔다');
    expect(home.submitted.single, [true, true, false], reason: '보내는 시점의 최신 상태여야 한다(뒤 토글 흡수)');
    expect(home.maxInFlight, 1);

    home.release(); // 첫 응답 도착
    await Future.wait([first, second]);

    // 두 번째 제출도 최신 배열 — 마지막으로 도착하는 배열이 화면과 같다.
    expect(home.submitted.last, [true, true, false]);
    expect(home.maxInFlight, 1, reason: '어느 순간에도 같은 hwId의 POST가 둘 이상 떠 있으면 안 된다');
  });

  test('앞 요청이 실패해도 그 칸만 되돌리고, 뒤 요청은 되돌린 상태로 이어서 나간다', () async {
    final container = makeContainer();
    final summary = await container.read(homeViewModelProvider.future);
    final vm = container.read(homeViewModelProvider.notifier);

    home.holdNext(failWith: const NetworkFailure());
    final first = vm.toggleHomework(summary.homeworkItems[0]);
    final second = vm.toggleHomework(summary.homeworkItems[1]);
    await flushMicrotasks();
    home.release();
    await Future.wait([first, second]);

    final items = container.read(homeViewModelProvider).value!.homeworkItems;
    expect(items.map((i) => i.done), [false, true, false], reason: '실패한 0번만 원복, 1번은 유지');
    expect(home.submitted, [
      [true, true, false], // 실패한 첫 요청(둘 다 실린 채)
      [false, true, false], // 되돌린 뒤의 최신 상태로 다시
    ]);
    expect(container.read(homeworkToggleErrorProvider), isNotNull, reason: '실패는 여전히 알린다');
  });

  test('다른 hwId끼리는 서로 기다리지 않는다', () async {
    home.twoAssignments = true;
    final container = makeContainer();
    final summary = await container.read(homeViewModelProvider.future);
    final vm = container.read(homeViewModelProvider.notifier);
    final h1 = summary.homeworkItems.firstWhere((i) => i.hwId == 'h1');
    final h2 = summary.homeworkItems.firstWhere((i) => i.hwId == 'h2');

    home.holdNext();
    final a = vm.toggleHomework(h1);
    final b = vm.toggleHomework(h2);
    await flushMicrotasks();

    expect(home.submitted, hasLength(2), reason: '배정이 다르면 문서도 달라 직렬화할 이유가 없다');
    home.release();
    await Future.wait([a, b]);
  });
}

/// 첫 `submitHomeworkChecks` 응답을 붙잡아 둘 수 있는 가짜 — "요청이 겹치는 순간"을 만든다.
class _GatedHomeRepository implements HomeRepository {
  bool twoAssignments = false;
  final List<List<bool>> submitted = [];
  int inFlight = 0;
  int maxInFlight = 0;

  /// 다음 제출을 붙잡을 게이트(장전) — 호출이 들어오면 [_held]로 옮긴다.
  Completer<void>? _gate;
  Failure? _gateFailure;

  /// 지금 붙잡혀 있는 호출의 게이트 — [release]가 푸는 대상(장전 필드는 호출이 이미 비웠다).
  Completer<void>? _held;

  void holdNext({Failure? failWith}) {
    _gate = Completer<void>();
    _gateFailure = failWith;
  }

  void release() {
    _held?.complete();
    _held = null;
  }

  @override
  Future<Result<HomeSummary>> loadHome({required String memberId, String? preferredPassId}) async {
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
        for (var i = 0; i < 3; i++) HomeworkItem(hwId: 'h1', index: i, name: '운동$i', done: false),
        if (twoAssignments) const HomeworkItem(hwId: 'h2', index: 0, name: '스트레칭', done: false),
      ],
      homeworkDate: DateFmt.todayKst(),
    ));
  }

  @override
  Future<Result<void>> submitHomeworkChecks({
    required String memberId,
    required String hwId,
    required DateTime date,
    required List<bool> done,
  }) async {
    submitted.add(List.of(done));
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final gate = _gate;
    final failure = _gateFailure;
    _gate = null;
    _gateFailure = null;
    if (gate != null) {
      _held = gate;
      await gate.future;
    }
    inFlight--;
    return failure == null ? const Ok(null) : Err(failure);
  }

  @override
  Future<Result<void>> selfCheckIn({String? scannedToken}) async => const Ok(null);
}

class _IdleRecordsRepository implements RecordsRepository {
  @override
  Future<Result<RecordsData>> load(String memberId) async => const Ok(RecordsData(
        workoutLogs: [],
        homeworkWeeks: [],
        inbodyRecords: [],
        bodyPhotos: BodyPhotoAlbum.empty,
      ));

  @override
  Future<Result<void>> createInbody({required String memberId, required InbodyDraft draft}) =>
      throw UnsupportedError('Home Work 토글이 인바디를 저장하지 않는다');

  @override
  Future<Result<void>> deleteInbody(String id) => throw UnsupportedError('Home Work 토글이 인바디를 삭제하지 않는다');
}
