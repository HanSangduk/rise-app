import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/bodycheck/domain/body_check_repository.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/data/records_remote_data_source.dart';
import 'package:rise_member/features/records/data/records_repository_impl.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

// 인바디 쓰기 경로(POST /v1/inbody · DELETE /v1/inbody/{id}).
//
// 못 박는 것 셋:
// ① 요청 바디에 `source`가 **없어야 한다**. 서버 decodeJSON이
//    DisallowUnknownFields라 미지 필드 하나로 전량 400이고, 출처는 서버가
//    Principal로 판정하는 값이다.
// ② 응답의 `source`는 **없어도 파싱된다**(nullable). required로 두면 이 필드가
//    생기기 전에 저장된 레코드 전부가 fromJson에서 던져 기록 탭 세 개
//    (운동·인바디·체형)를 통째로 죽인다 — 같은 사고의 전례가 이미 있다.
// ③ 409(같은 날 중복)는 **ConflictFailure 타입**으로 온다 — ViewModel이 이 타입을
//    보고 재조회한다(충돌을 일으킨 기존 기록이 화면에 보여야 지울 수 있다).
//    문구는 서버 우선, 서버가 본문을 안 줬을 때만 다음 행동을 말하는 폴백.
//    409가 아닌 4xx는 ConflictFailure가 **아니어야** 한다 — 400까지 재조회하면
//    실패마다 멀쩡한 화면을 흔드는 것으로 규약이 무너진다.
void main() {
  late _InbodyWriteAdapter adapter;
  late RecordsRemoteDataSource remote;
  late RecordsRepositoryImpl repo;

  setUp(() {
    adapter = _InbodyWriteAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    remote = RecordsRemoteDataSource(dio);
    repo = RecordsRepositoryImpl(remote, _FakeBodyCheckRepository());
  });

  final draft = InbodyDraft(
    date: DateTime(2026, 8, 17),
    weight: 70.2,
    smm: 30.1,
    bfm: 18.8,
    pbf: 26.8,
    vfl: 8,
    bmr: 1420,
  );

  group('POST /v1/inbody', () {
    test('바디는 계약 8필드 그대로 — source를 보내지 않는다(보내면 서버가 400)', () async {
      final result = await repo.createInbody(memberId: 'm1', draft: draft);

      expect(result, isA<Ok<void>>());
      expect(adapter.lastPath, '/v1/inbody');
      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastBody!.keys, isNot(contains('source')));
      expect(adapter.lastBody!.keys.toSet(), {
        'member_id', 'date', 'weight', 'smm', 'bfm', 'pbf', 'vfl', 'bmr',
      });
    });

    test('date는 YYYY-MM-DD — 서버 v2.5 검증을 통과하는 형식이어야 한다', () async {
      await repo.createInbody(memberId: 'm1', draft: draft);

      expect(adapter.lastBody!['date'], '2026-08-17');
    });

    test('숫자 6개가 그대로 실린다', () async {
      await repo.createInbody(memberId: 'm1', draft: draft);

      expect(adapter.lastBody!['weight'], 70.2);
      expect(adapter.lastBody!['smm'], 30.1);
      expect(adapter.lastBody!['bfm'], 18.8);
      expect(adapter.lastBody!['pbf'], 26.8);
      expect(adapter.lastBody!['vfl'], 8);
      expect(adapter.lastBody!['bmr'], 1420);
    });

    test('409에서 서버 문구가 있으면 그대로 쓴다 — 서버는 날짜까지 말해 준다', () async {
      adapter.createStatus = 409;
      adapter.createBody =
          '{"error":"2026-08-17 인바디 기록이 이미 있어요 — 기존 기록을 지우고 다시 저장해주세요"}';

      final result = await repo.createInbody(memberId: 'm1', draft: draft);

      final failure = (result as Err<void>).failure;
      expect(failure, isA<ConflictFailure>(), reason: 'ViewModel이 이 타입을 보고 재조회한다');
      expect(failure.message, contains('2026-08-17'), reason: '앱이 지어낸 문장이 더 구체적인 서버 문구를 덮으면 안 된다');
    });

    test('409인데 서버가 본문을 안 주면 앱이 다음 행동을 말한다 — 타입도 Conflict', () async {
      adapter.createStatus = 409;
      adapter.createBody = '{}';

      final result = await repo.createInbody(memberId: 'm1', draft: draft);

      final failure = (result as Err<void>).failure;
      // 서버 문구 유무와 무관하게 타입은 같아야 한다 — 문구가 없는 409에서만
      // 재조회가 빠지면 같은 충돌이 두 갈래로 행동한다.
      expect(failure, isA<ConflictFailure>());
      // guardApi 기본 폴백('요청을 처리할 수 없어요')은 다음 행동을 말하지 않는다.
      expect(failure.message, contains('지우고 다시'));
    });

    test('409가 아닌 4xx는 서버 문구를 그대로 전달한다 — 문구를 지어내지 않는다', () async {
      adapter.createStatus = 400;
      adapter.createBody = '{"error":"동의(sensitive)가 없거나 철회되어 저장할 수 없음(P8)"}';

      final result = await repo.createInbody(memberId: 'm1', draft: draft);

      final failure = (result as Err<void>).failure;
      expect(failure.message, contains('동의(sensitive)'));
      // 400은 "화면이 낡았다"는 신호가 아니다 — Conflict로 분류되면 ViewModel이
      // 400에도 재조회해 멀쩡한 화면을 흔든다.
      expect(failure, isNot(isA<ConflictFailure>()));
    });

    test('5xx는 NetworkFailure — 재시도 안내로 이어진다', () async {
      adapter.createStatus = 500;

      final result = await repo.createInbody(memberId: 'm1', draft: draft);

      expect((result as Err<void>).failure, isA<NetworkFailure>());
    });
  });

  group('DELETE /v1/inbody/{id}', () {
    test('id를 경로에 담아 부른다', () async {
      final result = await repo.deleteInbody('i9');

      expect(result, isA<Ok<void>>());
      expect(adapter.lastMethod, 'DELETE');
      expect(adapter.lastPath, '/v1/inbody/i9');
    });

    test('실패는 삼키지 않는다 — 안 지워졌는데 지웠다고 말하면 안 된다', () async {
      adapter.deleteStatus = 403;
      adapter.deleteBody = '{"error":"권한이 없습니다"}';

      final result = await repo.deleteInbody('i9');

      expect(result, isA<Err<void>>());
      expect((result as Err<void>).failure.message, contains('권한'));
    });
  });

  group('GET 파싱 — id/source가 도메인까지 온다', () {
    test('source가 있으면 실어 오고, 본인 기록으로 판정된다', () async {
      adapter.inbodyBody = '''
[{"id":"i1","member_id":"m1","date":"2026-08-17","weight":70.2,"smm":30.1,
  "bfm":18.8,"pbf":26.8,"vfl":8,"bmr":1420,"source":"member_self"}]''';

      final data = (await repo.load('m1') as Ok<RecordsData>).value;

      expect(data.inbodyRecords.single.id, 'i1');
      expect(data.inbodyRecords.single.source, 'member_self');
      expect(data.inbodyRecords.single.isMemberSelf, isTrue);
    });

    test('source 키가 아예 없어도 파싱된다 — 이 필드가 생기기 전 레코드', () async {
      adapter.inbodyBody = '''
[{"id":"i1","member_id":"m1","date":"2026-08-17","weight":70.2,"smm":30.1,
  "bfm":18.8,"pbf":26.8,"vfl":8,"bmr":1420}]''';

      final data = (await repo.load('m1') as Ok<RecordsData>).value;

      expect(data.inbodyRecords.single.source, isNull);
      // null은 "출처 미상"이지 "회원 본인"이 아니다 — 삭제 액션이 붙으면 안 된다.
      expect(data.inbodyRecords.single.isMemberSelf, isFalse);
    });

    test('빈 문자열 source는 null과 같게 정규화된다 — 서버가 v2.9 이전 레코드에 실제로 그렇게 보낸다', () async {
      // `Inbody.Source`는 omitempty가 아니라 `"source": ""`로 내려온다. ""와 키 부재는
      // 둘 다 "본인이 넣었다는 근거가 없다"는 같은 뜻이라, 화면이 두 갈래로 말하면 안 된다.
      adapter.inbodyBody = '''
[{"id":"i1","member_id":"m1","date":"2026-08-17","weight":70.2,"smm":30.1,
  "bfm":18.8,"pbf":26.8,"vfl":8,"bmr":1420,"source":""}]''';

      final data = (await repo.load('m1') as Ok<RecordsData>).value;

      expect(data.inbodyRecords.single.source, isNull);
      expect(data.inbodyRecords.single.isMemberSelf, isFalse);
    });

    test('코치가 넣은 기록은 본인 기록이 아니다', () async {
      adapter.inbodyBody = '''
[{"id":"i1","member_id":"m1","date":"2026-08-17","weight":70.2,"smm":30.1,
  "bfm":18.8,"pbf":26.8,"vfl":8,"bmr":1420,"source":"staff"}]''';

      final data = (await repo.load('m1') as Ok<RecordsData>).value;

      expect(data.inbodyRecords.single.isMemberSelf, isFalse);
    });

    test('같은 날짜 동률은 id 오름차순으로 확정된다 — 도착 순서와 무관하게 같은 결과', () async {
      // Dart List.sort는 불안정 정렬이라 date만 비교하면 동률의 상대 순서가
      // 입력 순서(여기선 일부러 id 역순)에 끌려간다. 동률은 회원+코치가 같은 날
      // 동시에 넣으면 실제로 생기고(서버는 쓰기 직전 읽기 1회 검사라 경합은
      // 통과), 순서가 흔들리면 "직전 기록" 델타가 조회마다 달라진다.
      String rec(String id, String date, double weight) =>
          '{"id":"$id","member_id":"m1","date":"$date","weight":$weight,'
          '"smm":30.1,"bfm":18.8,"pbf":26.8,"vfl":8,"bmr":1420,"source":"staff"}';
      adapter.inbodyBody = '['
          '${rec('i9', '2026-08-17', 70.9)},'
          '${rec('i2', '2026-08-17', 70.2)},'
          '${rec('i5', '2026-08-01', 71.0)}'
          ']';

      final data = (await repo.load('m1') as Ok<RecordsData>).value;

      expect(
        [for (final r in data.inbodyRecords) r.id],
        ['i5', 'i2', 'i9'],
        reason: 'date 오름차순, 동률은 id 오름차순(서버 문서 ID 순서와 같은 축)',
      );
    });
  });
}

class _InbodyWriteAdapter implements HttpClientAdapter {
  String? lastPath;
  String? lastMethod;
  Map<String, dynamic>? lastBody;

  int createStatus = 200;
  String createBody = '{"id":"i1","member_id":"m1","date":"2026-08-17","weight":70.2,'
      '"smm":30.1,"bfm":18.8,"pbf":26.8,"vfl":8,"bmr":1420,"source":"member_self"}';

  int deleteStatus = 204;
  String deleteBody = '';

  String inbodyBody = '[]';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = options.path;
    lastMethod = options.method;

    if (options.method == 'POST' && options.path == '/v1/inbody') {
      lastBody = (options.data as Map).cast<String, dynamic>();
      return _json(createBody, createStatus);
    }
    if (options.method == 'DELETE') {
      return _json(deleteBody, deleteStatus);
    }
    return switch (options.path) {
      '/v1/inbody' => _json(inbodyBody, 200),
      '/v1/workout-logs' => _json('[]', 200),
      '/v1/hw-checks' => _json('[]', 200),
      _ => _json('[]', 200),
    };
  }

  ResponseBody _json(String body, int status) => ResponseBody.fromString(
        body,
        status,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );

  @override
  void close({bool force = false}) {}
}

class _FakeBodyCheckRepository implements BodyCheckRepository {
  // 이 스위트는 삭제 경로를 쓰지 않는다 — 부르면 조용히 통과하는 대신 터뜨려서
  // "안 부른다"는 전제가 깨졌을 때 바로 드러나게 한다.
  @override
  Future<Result<void>> deletePhoto({required String id, String? storagePath}) =>
      throw UnimplementedError();

  @override
  Future<Result<List<BodyPhotoEntry>>> fetchPhotos(String memberId) async =>
      const Ok(<BodyPhotoEntry>[]);

  @override
  Future<Result<BodyPhotoEntry>> uploadPhoto({
    required String memberId,
    required String pose,
    required BodyDirection direction,
    required DateTime date,
    required String storagePath,
  }) =>
      throw UnsupportedError('이 테스트는 인바디 쓰기만 본다');
}
