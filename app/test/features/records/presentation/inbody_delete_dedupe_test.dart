import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/domain/records_repository.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';

// 인바디 삭제 — 같은 기록의 삭제는 **한 번만 서버에 간다**(P73).
//
// 왕복 동안 행이 화면에 남아 "삭제 → 삭제하기"를 한 번 더 하면 종전엔 두 번째 DELETE가 이미
// 없는 문서를 만나 400대로 돌아왔고, 방금 성공한 삭제에 "삭제 실패" 토스트가 떴다. 이제
// ① 진행 중인 삭제는 결과를 함께 받고 ② 성공 즉시 행이 목록에서 빠진다.
void main() {
  InbodyRecord rec(String id, int day) => InbodyRecord(
        id: id,
        date: DateTime(2026, 8, day),
        weight: 70.2,
        smm: 30.1,
        bfm: 18.8,
        pbf: 26.8,
        vfl: 8,
        bmr: 1420,
        source: 'member_self',
      );

  late _GatedRecordsRepository repo;

  ProviderContainer makeContainer() {
    repo = _GatedRecordsRepository([rec('i1', 1), rec('i2', 2)]);
    final container = ProviderContainer.test(
      overrides: [recordsRepositoryProvider.overrideWithValue(repo)],
    );
    container.read(sessionProvider.notifier).set(
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1'),
        );
    // 재조회(invalidateSelf)는 구독자가 있어야 일어난다 — 기록 탭은 indexedStack 상주.
    container.listen(recordsViewModelProvider, (_, __) {});
    return container;
  }

  test('왕복 중 같은 id를 다시 지워도 DELETE는 1회, 두 호출 모두 Ok', () async {
    final container = makeContainer();
    await container.read(recordsViewModelProvider.future);
    final vm = container.read(recordsViewModelProvider.notifier);

    repo.hold();
    final first = vm.deleteInbody('i1');
    final second = vm.deleteInbody('i1');
    await Future<void>.delayed(Duration.zero);
    expect(repo.deleteCalls, ['i1'], reason: '두 번째 확인이 서버에 또 나갔다 — 404 허위 실패의 재료');

    repo.release();
    final results = await Future.wait([first, second]);
    expect(results, everyElement(isA<Ok<void>>()), reason: '두 번째 확인도 첫 삭제의 결과(성공)를 받아야 한다');
    expect(repo.deleteCalls, ['i1']);
  });

  test('성공 즉시 행이 목록에서 빠진다 — 재조회가 끝나기 전에도', () async {
    final container = makeContainer();
    await container.read(recordsViewModelProvider.future);
    final vm = container.read(recordsViewModelProvider.notifier);

    repo.holdReloads = true; // 삭제 뒤 재조회를 붙잡아 "재조회 전" 상태를 관찰한다
    await vm.deleteInbody('i1');

    final ids = container.read(recordsViewModelProvider).value!.inbodyRecords.map((r) => r.id);
    expect(ids, ['i2'], reason: '재조회 응답이 오기 전엔 지운 행이 그대로 남아 두 번째 탭이 들어갔다');
    repo.releaseReloads();
    await Future<void>.delayed(Duration.zero);
  });

  test('삭제가 끝난 뒤의 새 삭제 요청은 다시 서버로 간다(중복 제거가 상시화되면 삭제가 죽는다)', () async {
    final container = makeContainer();
    await container.read(recordsViewModelProvider.future);
    final vm = container.read(recordsViewModelProvider.notifier);

    await vm.deleteInbody('i1');
    await vm.deleteInbody('i2');
    expect(repo.deleteCalls, ['i1', 'i2']);
  });

  test('실패한 삭제는 행을 남기고 실패를 그대로 돌려준다', () async {
    final container = makeContainer();
    await container.read(recordsViewModelProvider.future);
    final vm = container.read(recordsViewModelProvider.notifier);

    repo.failNextDelete = const RejectedFailure('요청을 처리할 수 없어요');
    final result = await vm.deleteInbody('i1');
    expect(result, isA<Err<void>>());
    final ids = container.read(recordsViewModelProvider).value!.inbodyRecords.map((r) => r.id);
    expect(ids, ['i1', 'i2']);
  });
}

class _GatedRecordsRepository implements RecordsRepository {
  _GatedRecordsRepository(this._records);
  final List<InbodyRecord> _records;
  final deleteCalls = <String>[];
  final deletedIds = <String>[];
  Failure? failNextDelete;
  bool holdReloads = false;

  /// 다음 삭제 호출을 붙잡을 게이트(장전) — 호출이 들어오면 [_held]로 옮긴다.
  Completer<void>? _gate;

  /// 지금 붙잡혀 있는 호출의 게이트 — [release]가 푸는 대상. 장전 필드를 그대로 완료하면
  /// 호출이 이미 비운 뒤라 아무것도 풀리지 않는다(첫 실행에서 30초 타임아웃으로 드러난 실수).
  Completer<void>? _held;
  final _reloadGates = <Completer<void>>[];
  int _loads = 0;

  void hold() => _gate = Completer<void>();
  void release() {
    _held?.complete();
    _held = null;
  }
  void releaseReloads() {
    for (final g in _reloadGates) {
      if (!g.isCompleted) g.complete();
    }
  }

  @override
  Future<Result<RecordsData>> load(String memberId) async {
    _loads++;
    if (holdReloads && _loads > 1) {
      final g = Completer<void>();
      _reloadGates.add(g);
      await g.future;
    }
    return Ok(RecordsData(
      workoutLogs: const [],
      homeworkWeeks: const [],
      inbodyRecords: _records.where((r) => !deletedIds.contains(r.id)).toList(),
      bodyPhotos: BodyPhotoAlbum.empty,
    ));
  }

  @override
  Future<Result<void>> createInbody({required String memberId, required InbodyDraft draft}) =>
      throw UnsupportedError('이 테스트는 삭제만 본다');

  @override
  Future<Result<void>> deleteInbody(String id) async {
    deleteCalls.add(id);
    final gate = _gate;
    _gate = null;
    if (gate != null) {
      _held = gate;
      await gate.future;
    }
    final failure = failNextDelete;
    failNextDelete = null;
    if (failure != null) return Err(failure);
    deletedIds.add(id);
    return const Ok(null);
  }
}
