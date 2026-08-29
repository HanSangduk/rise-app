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

// 5개 탭이 StatefulShellRoute.indexedStack으로 **동시에 mount된 채 유지**되므로
// 탭을 오가는 것만으로는 AsyncData가 폐기되지 않는다. 저장/삭제 후 무효화하지
// 않으면 방금 넣은 기록이 같은 화면에 안 나타나고 회원은 한 번 더 넣는다.
//
// 반대로 **실패했을 때 무효화하면** 멀쩡한 화면을 로딩으로 되돌린다 —
// camera_view_model·my_view_model이 이미 "성공 시에만"으로 굳혀 둔 규약이다.
//
// 예외는 정확히 하나, 409(ConflictFailure)다. 409는 "그날 기록이 서버에 이미
// 있다"는 뜻 — 앱이 들고 있는 목록이 낡았다는 신호라서, 재조회해야 충돌을
// 일으킨 기존 기록이 리스트에 보이고 안내("지우고 다시")를 따라갈 수 있다.
// 이 예외가 400·네트워크 실패로 번지면 규약이 통째로 무너지므로, 번지지
// 않는 것까지 함께 못 박는다.
void main() {
  final draft = InbodyDraft(
    date: DateTime(2026, 8, 17),
    weight: 70.2,
    smm: 30.1,
    bfm: 18.8,
    pbf: 26.8,
    vfl: 8,
    bmr: 1420,
  );

  late _CountingRecordsRepository repo;

  ProviderContainer make({bool withSession = true}) {
    repo = _CountingRecordsRepository();
    final container = ProviderContainer.test(
      overrides: [recordsRepositoryProvider.overrideWithValue(repo)],
    );
    if (withSession) {
      container.read(sessionProvider.notifier).set(const AppSession(
            uid: 'firebase-uid-1',
            role: 'member',
            centerId: 'rise-gangnam',
            memberId: 'm1',
            memberName: '람',
          ));
    }
    return container;
  }

  Future<ProviderContainer> mounted({bool withSession = true}) async {
    final container = make(withSession: withSession);
    container.listen(recordsViewModelProvider, (_, __) {});
    if (withSession) await container.read(recordsViewModelProvider.future);
    return container;
  }

  group('createInbody', () {
    test('성공하면 기록 탭이 다시 로드된다', () async {
      final container = await mounted();
      expect(repo.loadCount, 1);

      final result = await container.read(recordsViewModelProvider.notifier).createInbody(draft);
      await container.read(recordsViewModelProvider.future);

      expect(result, isA<Ok<void>>());
      expect(repo.loadCount, 2, reason: '저장했는데 같은 화면에 안 보이면 회원이 한 번 더 넣는다');
    });

    test('세션의 memberId를 그대로 보낸다 — 회원 본인 기록만 만들 수 있다', () async {
      final container = await mounted();

      await container.read(recordsViewModelProvider.notifier).createInbody(draft);

      expect(repo.lastCreateMemberId, 'm1');
      expect(repo.lastDraft, same(draft));
    });

    test('실패하면 무효화하지 않는다 — 저장 안 된 것으로 화면을 흔들 이유가 없다', () async {
      final container = await mounted();
      repo.createFailure = const NetworkFailure('연결이 불안정해요');

      final result = await container.read(recordsViewModelProvider.notifier).createInbody(draft);
      // 무효화는 즉시 재빌드하지 않는다 — 다시 읽어서 **실제로** 재로드가
      // 일어났는지까지 확인해야 한다(이 await 없이는 무조건 무효화로 바꿔도
      // 테스트가 통과했다).
      await container.read(recordsViewModelProvider.future);

      expect(result, isA<Err<void>>());
      expect(repo.loadCount, 1);
    });

    test('세션이 없으면 요청을 보내지 않고 로그인 안내로 끝낸다', () async {
      final container = make(withSession: false);

      final result = await container.read(recordsViewModelProvider.notifier).createInbody(draft);

      expect((result as Err<void>).failure, isA<AuthFailure>());
      expect(repo.createCount, 0);
    });

    test('409(Conflict)는 실패인데도 재조회한다 — 충돌을 일으킨 기존 기록이 보여야 한다', () async {
      final container = await mounted();
      repo.createFailure =
          const ConflictFailure('2026-08-17 인바디 기록이 이미 있어요 — 기존 기록을 지우고 다시 저장해주세요');

      final result = await container.read(recordsViewModelProvider.notifier).createInbody(draft);
      // 성공 케이스와 같은 이유로 실제 재로드까지 확인한다(무효화는 즉시
      // 재빌드하지 않는다).
      await container.read(recordsViewModelProvider.future);

      expect(result, isA<Err<void>>(), reason: '재조회는 하되 실패는 실패로 돌려준다 — 시트가 서버 문구를 띄워야 한다');
      expect(repo.loadCount, 2,
          reason: '409가 지목한 기존 기록이 리스트에 없으면 "지우고 다시" 안내를 따라갈 수 없다');
    });

    test('409가 아닌 거부(400류)는 재조회하지 않는다 — 화면이 낡았다는 근거가 없다', () async {
      final container = await mounted();
      repo.createFailure = const RejectedFailure('동의(sensitive)가 없거나 철회되어 저장할 수 없음(P8)');

      final result = await container.read(recordsViewModelProvider.notifier).createInbody(draft);
      await container.read(recordsViewModelProvider.future);

      expect(result, isA<Err<void>>());
      expect(repo.loadCount, 1);
    });
  });

  group('deleteInbody', () {
    test('성공하면 기록 탭이 다시 로드된다 — 지운 기록이 차트에 남아 있으면 안 된다', () async {
      final container = await mounted();

      final result = await container.read(recordsViewModelProvider.notifier).deleteInbody('i1');
      await container.read(recordsViewModelProvider.future);

      expect(result, isA<Ok<void>>());
      expect(repo.lastDeletedId, 'i1');
      expect(repo.loadCount, 2);
    });

    test('실패하면 무효화하지 않는다', () async {
      final container = await mounted();
      repo.deleteFailure = const RejectedFailure('권한이 없어요');

      final result = await container.read(recordsViewModelProvider.notifier).deleteInbody('i1');
      await container.read(recordsViewModelProvider.future);

      expect(result, isA<Err<void>>());
      expect(repo.loadCount, 1);
    });
  });
}

class _CountingRecordsRepository implements RecordsRepository {
  int loadCount = 0;
  int createCount = 0;
  String? lastCreateMemberId;
  InbodyDraft? lastDraft;
  String? lastDeletedId;
  Failure? createFailure;
  Failure? deleteFailure;

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

  @override
  Future<Result<void>> createInbody({
    required String memberId,
    required InbodyDraft draft,
  }) async {
    createCount++;
    lastCreateMemberId = memberId;
    lastDraft = draft;
    return createFailure == null ? const Ok(null) : Err(createFailure!);
  }

  @override
  Future<Result<void>> deleteInbody(String id) async {
    lastDeletedId = id;
    return deleteFailure == null ? const Ok(null) : Err(deleteFailure!);
  }
}
