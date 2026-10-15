// 기록 탭 로드가 네 조회(수업 기록·hw-checks·인바디·체형사진)를 **동시에** 보낸다(P74).
//
// 종전엔 네 왕복이 직렬이라 탭 전환마다 3회분을 그냥 기다렸다. 결과 값은 직렬이든 병렬이든 같아서
// 실패 스위트(records_repository_failure_test)로는 잴 수 없다 — 다시 직렬로 만들면 이 파일만 죽는다.

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/bodycheck/domain/body_check_repository.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/data/records_remote_data_source.dart';
import 'package:rise_member/features/records/data/records_repository_impl.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

void main() {
  test('수업 기록 응답을 붙잡아 둬도 hw-checks·인바디·체형사진 조회는 이미 나가 있다', () async {
    final adapter = _Adapter()..holdLogs = true;
    final photos = _PhotosSpy();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    final repo = RecordsRepositoryImpl(RecordsRemoteDataSource(dio), photos);

    final future = repo.load('m1');
    await pumpEventQueue();

    expect(adapter.seen, containsAll(<String>['/v1/hw-checks', '/v1/inbody']),
        reason: '수업 기록을 기다리는 동안 다른 조회가 나가지 않았다 — 아직 직렬이다');
    expect(photos.calls, 1, reason: '체형사진 조회가 수업 기록 응답을 기다렸다 — 아직 직렬이다');

    adapter.releaseLogs();
    final result = await future;
    expect(result, isA<Ok<RecordsData>>(), reason: '$result');
    expect((result as Ok<RecordsData>).value.workoutLogs, hasLength(1));
  });

  test('수업 기록 실패로 일찍 빠져나가도 뒤늦게 실패한 조회가 앱을 죽이지 않는다', () async {
    // 마이 탭(my_parallel_load_test)과 같은 위험: 필수 조회(수업 기록)가 실패해 guardApi로 빠져나간 뒤
    // 남은 future(hw-checks·인바디·체형사진)가 늦게 실패하면 **아무도 받지 않는 비동기 예외**가 된다.
    final adapter = _Adapter()
      ..logsStatus = 500
      ..failLate = true;
    final photos = _PhotosSpy()..throwLate = true;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    final repo = RecordsRepositoryImpl(RecordsRemoteDataSource(dio), photos);

    final result = await repo.load('m1');
    expect(result, isA<Err<RecordsData>>());

    // 늦은 실패(5ms 뒤)가 **시험 안에서** 도착하게 기다린다 — 받는 쪽이 없으면 여기서 죽는다.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(adapter.seen, containsAll(<String>['/v1/hw-checks', '/v1/inbody']), reason: '늦게 실패할 조회가 실제로 나갔다');
    expect(photos.calls, 1);
  });
}

class _Adapter implements HttpClientAdapter {
  final seen = <String>[];
  bool holdLogs = false;
  int logsStatus = 200;
  bool failLate = false;

  final _gate = Completer<void>();
  void releaseLogs() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async {
    final path = o.path.split('?').first;
    seen.add(path);
    if (path.startsWith('/v1/workout-logs')) {
      if (holdLogs) await _gate.future;
      if (logsStatus != 200) return _res('{"error":"boom"}', logsStatus);
      return _res('''
[{"id":"w1","member_id":"m1","trainer_id":"t1","date":"2026-08-01","title":"1:1 PT",
  "exercises":[{"name":"스쿼트","sets":3,"reps":"12","weight_kg":60}],"coach_note":""}]''');
    }
    if (path.startsWith('/v1/hw-checks') || path.startsWith('/v1/inbody')) {
      if (failLate) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return _res('{"error":"late"}', 500);
      }
      return _res('[]');
    }
    fail('기록 탭이 예상 밖의 엔드포인트를 호출했다: $path');
  }

  ResponseBody _res(String body, [int status = 200]) => ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

/// 체형사진은 Result를 돌려주는 도메인 인터페이스라 어댑터 없이 호출 횟수만 센다.
class _PhotosSpy implements BodyCheckRepository {
  int calls = 0;
  bool throwLate = false;

  @override
  Future<Result<List<BodyPhotoEntry>>> fetchPhotos(String memberId) async {
    calls++;
    if (throwLate) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      throw StateError('늦게 던지는 체형사진 조회');
    }
    return const Ok(<BodyPhotoEntry>[]);
  }

  @override
  Future<Result<void>> deletePhoto({required String id, String? storagePath}) =>
      throw UnimplementedError('이 파일은 조회 경로만 본다');

  @override
  Future<Result<BodyPhotoEntry>> uploadPhoto({
    required String memberId,
    required String pose,
    required BodyDirection direction,
    required DateTime date,
    required String storagePath,
  }) =>
      throw UnimplementedError('이 파일은 조회 경로만 본다');
}
