import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/bodycheck/domain/body_check_repository.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/data/records_remote_data_source.dart';
import 'package:rise_member/features/records/data/records_repository_impl.dart';
import 'package:rise_member/features/records/domain/homework_week_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

// 기록 탭 — 불량 데이터 1건 / 부분 조회 실패가 탭 전체를 삼키던 결함.
//
// ① 인바디 날짜: 운동 기록(:24)·hw-checks(:53)는 tryParse + 그 건만 스킵인데
//    인바디만 DateTime.parse(throw)였다. 서버 CreateInbody는 date를 형식 검증
//    **없이** 저장하므로("2026-8-2" 같은 값이 실제로 들어온다) 불량 1건이
//    guardApi까지 올라가 운동·인바디·체형 세 탭 전부를 "알 수 없는 오류"로 만들었고
//    pull-to-refresh로도 복구되지 않았다(같은 값이 계속 온다).
// ② 체형사진: `photosResult.valueOrNull ?? []`가 실패와 "0장"을 같은 값으로 뭉개
//    "아직 촬영한 사진이 없어요"라고 말했다. 같은 파일 hw-checks는 이미 플래그를
//    쓰고 있었다 — 비대칭을 없앤다.
void main() {
  late _RecordsApiAdapter adapter;
  late _FakeBodyCheckRepository bodyCheck;
  late RecordsRepositoryImpl repo;

  setUp(() {
    adapter = _RecordsApiAdapter();
    bodyCheck = _FakeBodyCheckRepository();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    repo = RecordsRepositoryImpl(RecordsRemoteDataSource(dio), bodyCheck);
  });

  Future<RecordsData> loadOk() async {
    final result = await repo.load('m1');
    expect(result, isA<Ok<RecordsData>>(), reason: '기록 탭이 통째로 실패했다: $result');
    return (result as Ok<RecordsData>).value;
  }

  group('인바디 날짜 — 불량 1건이 기록 탭 전체를 죽이지 않는다', () {
    test('파싱 불가 날짜 1건은 그 건만 버리고 나머지는 살린다', () async {
      adapter.inbodyBody = '''
[
  ${_inbody('i1', '2026-07-01', 70.0)},
  ${_inbody('i2', '2026-8-2', 71.0)},
  ${_inbody('i3', '2026-08-03', 72.0)}
]''';

      final data = await loadOk();

      expect(data.inbodyRecords, hasLength(2), reason: '불량 1건만 스킵해야 한다');
      expect(data.inbodyRecords.map((r) => r.weight), [70.0, 72.0]);
      // 같은 로드에 실린 다른 탭 데이터도 무사해야 한다 — 이게 이 버그의 실제 피해였다.
      expect(data.workoutLogs, hasLength(1));
      expect(data.bodyPhotos.totalCount, 1);
    });

    test('빈 문자열·완전 쓰레기 날짜도 throw하지 않는다', () async {
      adapter.inbodyBody = '''
[
  ${_inbody('i1', '', 70.0)},
  ${_inbody('i2', 'not-a-date', 71.0)},
  ${_inbody('i3', '2026-08-03', 72.0)}
]''';

      expect((await loadOk()).inbodyRecords, hasLength(1));
    });

    test('전부 불량이면 인바디만 비고 나머지 탭은 그대로 — 여전히 Ok', () async {
      adapter.inbodyBody = '[${_inbody('i1', '2026-8-2', 70.0)}]';

      final data = await loadOk();

      expect(data.inbodyRecords, isEmpty);
      expect(data.workoutLogs, hasLength(1));
    });

    test('정상 날짜는 그대로 파싱되고 오래된 순으로 정렬 — 가드가 데이터를 먹지 않는다', () async {
      adapter.inbodyBody = '''
[
  ${_inbody('i1', '2026-08-03', 72.0)},
  ${_inbody('i2', '2026-07-01', 70.0)}
]''';

      final data = await loadOk();

      expect(data.inbodyRecords.map((r) => r.date), [DateTime(2026, 7, 1), DateTime(2026, 8, 3)]);
    });

    test('인바디 엔드포인트 자체의 5xx는 여전히 탭 실패다 — 조용히 삼키지 않는다', () async {
      // 불량 날짜(데이터 문제, 그 건만 스킵)와 엔드포인트 장애(전체 조회 실패)는
      // 다른 사건이다. 후자까지 빈 목록으로 흡수하면 "인바디 기록 없음"이라는
      // 새로운 거짓말이 생긴다 — 기록 탭 에러 뷰가 재시도를 안내해야 한다.
      adapter.inbodyStatus = 500;

      expect(await repo.load('m1'), isA<Err<RecordsData>>());
    });
  });

  group('체형사진 조회 실패 — "아직 촬영한 사진이 없어요"로 위장하지 않는다', () {
    test('fetchPhotos가 Err면 bodyPhotosFailed=true', () async {
      bodyCheck.result = const Err(NetworkFailure());

      final data = await loadOk();

      expect(data.bodyPhotosFailed, isTrue);
      expect(data.bodyPhotos.isEmpty, isTrue);
      // 사진 실패가 운동·인바디를 가리지 않는다(best-effort 전제).
      expect(data.workoutLogs, hasLength(1));
      expect(data.inbodyRecords, hasLength(1));
    });

    test('진짜 0장은 실패가 아니다 — 첫 촬영 안내가 붉은 실패 문구로 바뀌면 안 된다', () async {
      bodyCheck.result = const Ok(<BodyPhotoEntry>[]);

      final data = await loadOk();

      expect(data.bodyPhotosFailed, isFalse);
      expect(data.bodyPhotos.isEmpty, isTrue);
    });

    test('성공하면 flag=false + 포즈별로 나뉘어 오래된 순', () async {
      bodyCheck.result = Ok([
        _photo('b2', 'ohsquat', DateTime(2026, 8, 1)),
        _photo('b3', 'stand', DateTime(2026, 8, 2)),
        _photo('b1', 'ohsquat', DateTime(2026, 7, 1)),
      ]);

      final data = await loadOk();

      expect(data.bodyPhotosFailed, isFalse);
      expect(data.bodyPhotos.entriesFor('ohsquat').map((e) => e.id), ['b1', 'b2']);
    });
  });

  // 촬영 탭은 4종(PoseSpec.fallbackSequence)을 전부 찍게 하는데 데이터 계층이 ohsquat만
  // 남겨 나머지 3종은 저장만 되고 앱 어디에도 나타나지 않았다 — 회원은 4장 찍고
  // 1장만 다시 볼 수 있었다. 필터가 다시 생기면 여기서 잡힌다.
  group('체형사진 포즈 — 데이터 계층은 한 포즈만 남기지 않는다', () {
    test('4종을 다 찍었으면 4종이 다 온다', () async {
      bodyCheck.result = Ok([
        for (final pose in PoseSpec.fallbackSequence) _photo(pose.key, pose.key, DateTime(2026, 8, 1)),
      ]);

      final album = (await loadOk()).bodyPhotos;

      expect(album.totalCount, PoseSpec.fallbackSequence.length);
      for (final pose in PoseSpec.fallbackSequence) {
        expect(album.countFor(pose.key), 1, reason: '${pose.key} 사진이 사라졌다');
      }
    });

    test('ohsquat이 0장이어도 다른 포즈는 그대로 살아 있다', () async {
      // 종전 구현이면 이 회원의 기록 탭은 "아직 촬영한 사진이 없어요"였다.
      bodyCheck.result = Ok([
        _photo('s1', 'stand', DateTime(2026, 7, 1)),
        _photo('s2', 'stand', DateTime(2026, 8, 1)),
      ]);

      final album = (await loadOk()).bodyPhotos;

      expect(album.isEmpty, isFalse);
      expect(album.countFor('ohsquat'), 0);
      expect(album.entriesFor('stand').map((e) => e.id), ['s1', 's2']);
    });

    test('같은 포즈 안에서는 오래된 순 — 서버 정렬을 믿지 않는다', () async {
      bodyCheck.result = Ok([
        _photo('t3', 'tpose', DateTime(2026, 9, 1)),
        _photo('t1', 'tpose', DateTime(2026, 7, 1)),
        _photo('t2', 'tpose', DateTime(2026, 8, 1)),
      ]);

      final album = (await loadOk()).bodyPhotos;

      expect(album.entriesFor('tpose').map((e) => e.id), ['t1', 't2', 't3']);
    });
  });

  group('Home Work 주간 기록 — 이미 있던 규약의 회귀 고정', () {
    test('GET /v1/hw-checks 5xx → homeworkWeeksFailed=true, 나머지는 그대로', () async {
      adapter.hwChecksStatus = 500;

      final data = await loadOk();

      expect(data.homeworkWeeksFailed, isTrue);
      expect(data.homeworkWeeks, isEmpty);
      expect(data.bodyPhotosFailed, isFalse);
      expect(data.inbodyRecords, hasLength(1));
    });

    test('성공이면 homeworkWeeksFailed=false', () async {
      expect((await loadOk()).homeworkWeeksFailed, isFalse);
    });
  });

  // 주 경계(월~일)의 기준일이 센터(KST)인지. hw-check의 date는 서버가 KST로 찍은
  // 날짜라(`api/service.go`의 today()), 기준일을 기기 로컬 시각으로 잡으면 해외에서
  // 주가 하루 밀려 "이번 주"에 지난주 체크가 섞이거나 오늘 체크가 빠진다.
  //
  // ⚠️ 이 그룹은 홈의 시각 판정들과 달리 **뮤테이션을 항상 잡지는 못한다**.
  //    summarize는 시각이 아니라 날짜만 쓰므로, `nowKst()` → `DateTime.now()`로
  //    되돌려도 두 날짜가 **같은 주 안에 있으면** 답이 같다. 오프셋 최대치(±14h)로도
  //    날짜는 하루밖에 못 움직이니, 실제로 갈리는 건 두 날짜가 월요일 경계를 사이에
  //    두는 날뿐이다(대략 주 1회). 검증 시점(KST 일 8/23)에는 어떤 TZ로도 같은 주라
  //    `TZ=UTC` 뮤테이션이 살아남았다 — 대신 주를 한 칸 미는 뮤테이션
  //    (`nowKst().subtract(7일)`, 축이 갈리는 날 실제로 나타나는 증상)은 아래 두
  //    테스트가 모두 잡는다. 그래서 값 자체를 KST 레퍼런스와 통째로 대조해 둔다.
  group('Home Work 주간 집계 — 기준일은 센터(KST)', () {
    /// KST 이번 주의 월요일/일요일 — 주 경계 양 끝.
    (DateTime, DateTime) kstWeekEdges() {
      final today = DateFmt.todayKst();
      final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
      return (monday, monday.add(const Duration(days: 6)));
    }

    test('KST 이번 주의 월요일·일요일 체크는 둘 다 "이번 주"에 들어간다', () async {
      final (monday, sunday) = kstWeekEdges();
      adapter.hwChecksBody = '['
          '${_hwCheck(DateFmt.isoDate(monday), '[true,false]')},'
          '${_hwCheck(DateFmt.isoDate(sunday), '[true,true]')}'
          ']';

      final data = await loadOk();

      expect(data.homeworkWeeks, isNotEmpty);
      final current = data.homeworkWeeks.firstWhere((w) => w.isCurrent);
      expect(current.total, 4, reason: '주 경계가 밀려 월/일요일 체크가 다른 주로 흩어졌다');
      expect(current.done, 3);
    });

    test('집계 결과가 KST 기준 레퍼런스와 정확히 같다', () async {
      final (monday, sunday) = kstWeekEdges();
      final lastWeek = monday.subtract(const Duration(days: 3));
      adapter.hwChecksBody = '['
          '${_hwCheck(DateFmt.isoDate(lastWeek), '[true]')},'
          '${_hwCheck(DateFmt.isoDate(monday), '[true,false]')},'
          '${_hwCheck(DateFmt.isoDate(sunday), '[true,true]')}'
          ']';

      final data = await loadOk();

      final expected = HomeworkWeekRules.summarize(
        now: DateFmt.nowKst(),
        checks: [
          HomeworkCheckDay(date: lastWeek, done: const [true]),
          HomeworkCheckDay(date: monday, done: const [true, false]),
          HomeworkCheckDay(date: sunday, done: const [true, true]),
        ],
      );

      expect(
        data.homeworkWeeks.map((w) => '${w.label}:${w.done}/${w.total}:${w.isCurrent}'),
        expected.map((w) => '${w.label}:${w.done}/${w.total}:${w.isCurrent}'),
      );
    });
  });
}

String _hwCheck(String date, String done) =>
    '{"member_id":"m1","hw_id":"h1","date":"$date","done":$done}';

String _inbody(String id, String date, double weight) =>
    '{"id":"$id","member_id":"m1","date":"$date","weight":$weight,'
    '"smm":30.0,"bfm":15.0,"pbf":20.0,"vfl":5.0,"bmr":1400.0}';

BodyPhotoEntry _photo(String id, String pose, DateTime date) => BodyPhotoEntry(
      id: id,
      memberId: 'm1',
      pose: pose,
      direction: BodyDirection.front,
      date: date,
      blurred: false,
    );

class _RecordsApiAdapter implements HttpClientAdapter {
  String workoutLogsBody = '''
[{"id":"w1","member_id":"m1","trainer_id":"t1","date":"2026-08-01","title":"1:1 PT",
  "exercises":[{"name":"스쿼트","sets":3,"reps":"12","weight_kg":60}],"coach_note":""}]''';

  String hwChecksBody = '[{"member_id":"m1","hw_id":"h1","date":"2026-08-01","done":[true,false]}]';

  String inbodyBody = '[{"id":"i1","member_id":"m1","date":"2026-08-01","weight":70.0,'
      '"smm":30.0,"bfm":15.0,"pbf":20.0,"vfl":5.0,"bmr":1400.0}]';

  int workoutLogsStatus = 200;
  int hwChecksStatus = 200;
  int inbodyStatus = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.startsWith('/v1/workout-logs')) return _res(workoutLogsBody, workoutLogsStatus);
    if (path.startsWith('/v1/hw-checks')) return _res(hwChecksBody, hwChecksStatus);
    if (path.startsWith('/v1/inbody')) return _res(inbodyBody, inbodyStatus);
    fail('기록 탭이 예상 밖의 엔드포인트를 호출했다: $path');
  }

  ResponseBody _res(String body, int status) => ResponseBody.fromString(
        status == 200 ? body : '{"error":"boom"}',
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

/// 체형사진은 Result를 돌려주는 도메인 인터페이스라 어댑터 없이 바로 갈아끼운다.
class _FakeBodyCheckRepository implements BodyCheckRepository {
  // 이 스위트는 삭제 경로를 쓰지 않는다 — 부르면 조용히 통과하는 대신 터뜨려서
  // "안 부른다"는 전제가 깨졌을 때 바로 드러나게 한다.
  @override
  Future<Result<void>> deletePhoto({required String id, String? storagePath}) =>
      throw UnimplementedError();

  Result<List<BodyPhotoEntry>> result = Ok([
    BodyPhotoEntry(
      id: 'b1',
      memberId: 'm1',
      pose: 'ohsquat',
      direction: BodyDirection.front,
      date: DateTime(2026, 7, 1),
      blurred: false,
    ),
  ]);

  @override
  Future<Result<List<BodyPhotoEntry>>> fetchPhotos(String memberId) async => result;

  @override
  Future<Result<BodyPhotoEntry>> uploadPhoto({
    required String memberId,
    required String pose,
    required BodyDirection direction,
    required DateTime date,
    required String storagePath,
  }) async =>
      throw UnimplementedError('이 파일은 조회 경로만 본다');
}
