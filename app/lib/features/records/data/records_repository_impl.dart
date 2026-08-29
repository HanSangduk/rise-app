import 'package:dio/dio.dart';
import 'package:rise_member/core/network/api_result_guard.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/bodycheck/domain/body_check_repository.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/data/records_remote_data_source.dart';
import 'package:rise_member/features/records/domain/homework_week_rules.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/domain/records_repository.dart';

class RecordsRepositoryImpl implements RecordsRepository {
  const RecordsRepositoryImpl(this._remote, this._bodyCheckRepository);

  final RecordsRemoteDataSource _remote;
  final BodyCheckRepository _bodyCheckRepository;

  @override
  Future<Result<RecordsData>> load(String memberId) {
    return guardApi(() async {
      // 수업 기록(GET /v1/workout-logs?member=, v1.4) — 최신 세션 먼저.
      // 날짜는 tryParse — 불량 날짜 1건이 기록 탭 전체를 죽이지 않도록 그 건만 스킵.
      final logDtos = await _remote.fetchWorkoutLogs(memberId);
      final workoutLogs = <WorkoutLog>[];
      for (final d in logDtos) {
        final date = DateTime.tryParse(d.date);
        if (date == null) continue;
        workoutLogs.add(WorkoutLog(
          id: d.id,
          date: date,
          title: d.title.isEmpty ? '1:1 PT' : d.title,
          exercises: [
            for (final e in d.exercises)
              ExerciseEntry(
                name: e.name,
                sets: e.sets,
                reps: e.reps ?? '',
                weightKg: e.weightKg,
              ),
          ],
          coachComment: d.coachNote.isEmpty ? null : d.coachNote,
        ));
      }
      workoutLogs.sort((a, b) => b.date.compareTo(a.date));

      // Home Work 주간 집계(GET /v1/hw-checks?member=) — best-effort:
      // 체크 조회 실패가 운동 기록·인바디까지 죽이지 않도록 빈 목록 폴백.
      // 단, 실패를 "기록 없음"으로 위장하지 않게 플래그로 구분해 UI에 전달.
      var homeworkWeeks = const <HomeworkWeekSummary>[];
      var homeworkWeeksFailed = false;
      try {
        final checkDtos = await _remote.fetchHwChecks(memberId);
        final checks = <HomeworkCheckDay>[];
        for (final c in checkDtos) {
          final parsed = DateTime.tryParse(c.date);
          if (parsed != null) checks.add(HomeworkCheckDay(date: parsed, done: c.done));
        }
        // 주 경계(월~일)는 센터(KST) 기준 — hw-check의 date는 서버가 KST로 찍은
        // 날짜라 기준일도 같은 축이어야 한다. 로컬 시각으로 재면 해외에서 주가
        // 하루 밀려 "이번 주"에 지난주 체크가 섞이거나 오늘 체크가 빠진다
        // (DateFmt 클래스 주석의 시간축 규약).
        homeworkWeeks = HomeworkWeekRules.summarize(now: DateFmt.nowKst(), checks: checks);
      } catch (_) {
        // 주간 요약만 비우고 실패 표시.
        homeworkWeeksFailed = true;
      }

      // 인바디도 운동 기록·hw-checks와 **같은 규칙**: tryParse + 해당 건만 스킵.
      // 여기만 DateTime.parse(throw)였다 — 서버 CreateInbody가 date를 형식 검증
      // 없이 저장하므로("2026-8-2" 같은 값이 실제로 들어올 수 있다) 불량 1건이
      // guardApi까지 올라가 운동·인바디·체형 **세 탭 전부**를 "알 수 없는 오류"로
      // 만들고 pull-to-refresh로도 복구되지 않았다.
      final inbodyDtos = await _remote.fetchInbody(memberId);
      final inbody = <InbodyRecord>[];
      for (final d in inbodyDtos) {
        final date = DateTime.tryParse(d.date);
        if (date == null) continue;
        inbody.add(InbodyRecord(
          // id·source를 여기서 버리면 화면이 삭제 대상을 특정할 수 없고
          // (회원 오입력이 영구 확정), 코치 기록과 본인 기록도 구분되지 않는다.
          id: d.id,
          // 빈 문자열과 키 부재를 **같은 것으로** 정규화한다. 서버 `Inbody.Source`는
          // `omitempty`가 아니라 v2.9 이전 레코드가 `"source": ""`로 내려오는데,
          // ""와 null은 둘 다 "회원 본인이 넣었다는 근거가 없다"는 같은 뜻이다.
          // 여기서 합치지 않으면 화면이 "출처 미상"과 "센터 기록"을 갈라 말한다.
          source: (d.source ?? '').isEmpty ? null : d.source,
          date: date,
          weight: d.weight,
          smm: d.smm,
          bfm: d.bfm,
          pbf: d.pbf,
          vfl: d.vfl,
          bmr: d.bmr,
        ));
      }
      // date 동률은 id로 — Dart `List.sort`는 불안정 정렬이라 date만 비교하면
      // 서버가 확정한 같은 날짜 동률의 문서 ID 순서가 버려진다(같은 목록을 두 번
      // 받아도 델타의 "직전 기록"이 달라질 수 있다). 동률은 회원+코치 동시 입력이
      // 실제로 만든다(백엔드 P18 §한계 — 쓰기 직전 읽기 1회 검사라 경합은 통과).
      inbody.sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });

      // 체형사진도 best-effort지만 실패를 "아직 촬영한 사진이 없어요"로 위장하지
      // 않는다 — 같은 파일 hw-checks와 같은 규약으로 플래그를 세워 UI에 넘긴다.
      // (valueOrNull ?? []는 실패와 0장을 구분할 수 없어 쓰지 않는다.)
      final photosResult = await _bodyCheckRepository.fetchPhotos(memberId);
      final List<BodyPhotoEntry> allPhotos;
      final bool bodyPhotosFailed;
      switch (photosResult) {
        case Ok(:final value):
          allPhotos = value;
          bodyPhotosFailed = false;
        case Err():
          allPhotos = const <BodyPhotoEntry>[];
          bodyPhotosFailed = true;
      }
      // 포즈 필터를 여기서 걸지 않는다 — 촬영 탭은 4종을 다 찍게 하는데 여기서
      // ohsquat만 남기면 나머지 3종은 저장만 되고 앱 어디에도 나타나지 않는다
      // (회원은 4장 찍고 1장만 다시 볼 수 있었다). 어느 포즈를 볼지는 화면의
      // 포즈 칩이 정한다(BodyPhotoAlbum).
      return RecordsData(
        workoutLogs: workoutLogs,
        homeworkWeeks: homeworkWeeks,
        homeworkWeeksFailed: homeworkWeeksFailed,
        inbodyRecords: inbody,
        bodyPhotos: BodyPhotoAlbum.from(allPhotos),
        bodyPhotosFailed: bodyPhotosFailed,
      );
    });
  }

  @override
  Future<Result<void>> createInbody({
    required String memberId,
    required InbodyDraft draft,
  }) {
    return guardApi(() async {
      try {
        await _remote.createInbody(
          memberId: memberId,
          // 서버는 YYYY-MM-DD만 받는다(v2.5) — 표시용 포맷을 섞지 않는다.
          date: DateFmt.isoDate(draft.date),
          weight: draft.weight,
          smm: draft.smm,
          bfm: draft.bfm,
          pbf: draft.pbf,
          vfl: draft.vfl,
          bmr: draft.bmr,
        );
      } on DioException catch (e) {
        // 같은 날 중복(409)은 [ConflictFailure] **타입**으로 던진다 — ViewModel이
        // 이 타입을 보고 기록을 재조회한다. 409는 실패 중 유일하게 "앱이 들고
        // 있는 목록이 서버와 다르다"는 신호라서, 충돌을 일으킨 기존 기록이
        // 리스트에 보여야 회원이 안내("기존 기록을 지우고 다시")를 따라갈 수 있다.
        //
        // 문구는 **서버 문구를 우선**한다 — 서버는 날짜와 출처까지 넣어 말하고
        // (센터 입력분이면 "담당 코치에게 요청", 셀프면 "지우고 다시"), 그게 앱이
        // 지어낼 수 있는 어떤 문장보다 구체적이다. 여기서 문구를 만드는 건 서버가
        // 본문을 안 준 경우뿐이다. guardApi의 기본 폴백('요청을 처리할 수 없어요')은
        // 409에서 **다음 행동을 말하지 않는다**.
        if (e.response?.statusCode == 409) {
          throw ConflictFailure(
            _serverMessageOf(e) ?? '그날 기록이 이미 있어요 — 기존 기록을 지우고 다시 넣어주세요',
          );
        }
        rethrow;
      }
    });
  }

  @override
  Future<Result<void>> deleteInbody(String id) {
    return guardApi(() => _remote.deleteInbody(id));
  }

  /// 백엔드 공통 에러 포맷 `{"error":"메시지"}`의 본문 — 없거나 비면 null.
  /// [guardApi]가 같은 필드를 읽어 [Failure.message]로 쓴다.
  static String? _serverMessageOf(DioException e) {
    final data = e.response?.data;
    if (data is! Map) return null;
    final message = data['error']?.toString();
    return (message == null || message.isEmpty) ? null : message;
  }
}
