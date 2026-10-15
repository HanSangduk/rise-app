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
  ///
  /// **같은 기록의 삭제가 진행 중이면 그 결과를 함께 받는다**(P73). 서버 왕복 동안 행이 화면에
  /// 남아 있어 "삭제 → 삭제하기"를 한 번 더 하면 두 번째 DELETE가 이미 없는 문서를 만나
  /// 400대로 돌아왔고, 방금 성공한 삭제에 "삭제 실패" 토스트가 떴다("되돌릴 수 없어요"라고
  /// 강조한 화면에서 성공과 모순되는 안내). 성공 즉시 행을 목록에서 빼기도 한다 — 재조회가
  /// 끝나기 전에 두 번째 탭이 들어갈 자리를 없앤다.
  Future<Result<void>> deleteInbody(String id) =>
      // 블록 본문이어야 한다: `=> _deletingInbody.remove(id)`는 지도에 든 **이 Future 자신**을
      // 돌려주고, whenComplete는 콜백이 돌려준 Future를 기다리므로 자기 자신을 기다리다 영원히
      // 끝나지 않는다(자문자답 라운드에서 잡음).
      _deletingInbody[id] ??= _deleteInbody(id).whenComplete(() {
        _deletingInbody.remove(id);
      });

  final _deletingInbody = <String, Future<Result<void>>>{};

  Future<Result<void>> _deleteInbody(String id) async {
    final result = await ref.read(recordsRepositoryProvider).deleteInbody(id);
    // 왕복 중 provider가 폐기됐으면(로그아웃) 갱신할 상태가 없다 — 결과만 돌려준다.
    if (!ref.mounted) return result;
    if (result case Ok()) {
      final current = state.value;
      if (current != null) {
        state = AsyncData(RecordsData(
          workoutLogs: current.workoutLogs,
          homeworkWeeks: current.homeworkWeeks,
          inbodyRecords: current.inbodyRecords.where((r) => r.id != id).toList(growable: false),
          bodyPhotos: current.bodyPhotos,
          homeworkWeeksFailed: current.homeworkWeeksFailed,
          bodyPhotosFailed: current.bodyPhotosFailed,
        ));
      }
      refresh();
    }
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
