import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/network/dio_client.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/features/bodycheck/data/body_check_repository_provider.dart';
import 'package:rise_member/features/records/data/records_remote_data_source.dart';
import 'package:rise_member/features/records/data/records_repository_impl.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/domain/records_repository.dart';

part 'records_view_model.g.dart';

@riverpod
RecordsRepository recordsRepository(Ref ref) {
  final dio = ref.watch(dioProvider);
  return RecordsRepositoryImpl(
    RecordsRemoteDataSource(dio),
    ref.watch(bodyCheckRepositoryProvider),
  );
}

@riverpod
class RecordsViewModel extends _$RecordsViewModel {
  @override
  Future<RecordsData> build() async {
    final memberId = ref.watch(sessionProvider)?.memberId;
    if (memberId == null) {
      // 셸이 떠 있는 채 세션이 비었다 — 리스너가 이동 중이라 문구가 아닌 타입만 낸다(P64).
      throw const SessionGoneFailure();
    }
    final repo = ref.watch(recordsRepositoryProvider);
    return _unwrap(await repo.load(memberId));
  }

  T _unwrap<T>(Result<T> r) => switch (r) {
        Ok<T>(:final value) => value,
        Err<T>(:final failure) => throw failure,
      };

  void refresh() => ref.invalidateSelf();

  /// 인바디 수기 입력 저장. **성공 시에만** 스스로를 무효화한다 — 예외는 409 하나.
  ///
  /// 5개 탭이 `StatefulShellRoute.indexedStack`으로 동시에 mount된 채 유지되므로
  /// (core/router/app_router.dart) 탭을 오가는 것만으로는 AsyncData가 폐기되지
  /// 않는다 — 무효화하지 않으면 방금 저장한 기록이 같은 화면에 나타나지 않고,
  /// 회원은 저장이 안 된 줄 알고 한 번 더 넣는다(중복 저장). 실패했을 때 갱신하면
  /// 반대로 멀쩡한 화면을 로딩으로 되돌린다(camera_view_model·my_view_model 규약).
  ///
  /// **409([ConflictFailure])만은 실패인데도 재조회한다.** 409는 "그날 기록이
  /// 서버에 이미 있다"는 뜻 — 앱이 들고 있는 목록에 그 기록이 없어서 생긴
  /// 충돌이므로, 실패 중 유일하게 화면이 낡았다는 신호다. 재조회해야 충돌을
  /// 일으킨 기존 기록이 리스트에 보이고, 시트의 안내("기존 기록을 지우고 다시")를
  /// 회원이 실제로 따라갈 수 있다. 다른 실패(400·네트워크)는 종전대로 갱신하지
  /// 않는다 — 화면이 낡았다는 근거가 없다.
  Future<Result<void>> createInbody(InbodyDraft draft) async {
    final memberId = ref.read(sessionProvider)?.memberId;
    if (memberId == null) return const Err(SessionGoneFailure());
    final result = await ref.read(recordsRepositoryProvider).createInbody(
          memberId: memberId,
          draft: draft,
        );
    switch (result) {
      case Ok():
        refresh();
      case Err(failure: ConflictFailure()):
        refresh();
      case Err():
        break;
    }
    return result;
  }

  /// 인바디 기록 삭제 — 같은 규약(성공 시에만 무효화).
  Future<Result<void>> deleteInbody(String id) async {
    final result = await ref.read(recordsRepositoryProvider).deleteInbody(id);
    if (result case Ok()) refresh();
    return result;
  }
}

enum RecordsTab { workout, inbody, bodycheck }

/// 세그먼트 탭(운동/인바디/체형 분석) — 목업 seg-lw/li/lb.
@riverpod
class SelectedRecordsTab extends _$SelectedRecordsTab {
  @override
  RecordsTab build() => RecordsTab.workout;

  void select(RecordsTab tab) => state = tab;
}
