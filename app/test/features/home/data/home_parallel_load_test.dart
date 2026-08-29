// 홈 로드가 왕복을 **동시에** 보낸다(P32) + 부분 실패 규약(P33).
//
// 종전엔 `loadHome` 안에 `await`가 다섯 번 줄줄이 있어 왕복이 직렬이었다. 그런데
// 이들은 서로의 응답을 필요로 하지 않는다 — 의존은 전부 응답을 *가공할 때* 생긴다
// (홈워크 필터가 `selected.trainerId`를 쓰는 식).
//
// 병렬로 바꾸면서 생기는 위험이 둘이다. 이 스위트가 그 둘을 잠근다:
//  ① 중간에 빠져나가는 경로(`EmptyPassesFailure`)에서 남은 요청이 나중에 실패하면
//     **아무도 받지 않는 비동기 예외**가 되어 앱이 죽는다.
//  ② 어느 하나가 실패했을 때 **원래 나가던 에러가 그대로** 나가야 한다.

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/bookings_api.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/home/data/home_remote_data_source.dart';
import 'package:rise_member/features/home/data/home_repository_impl.dart';
import 'package:rise_member/features/home/domain/home_models.dart';

void main() {
  late _Adapter adapter;
  late HomeRepositoryImpl repo;

  setUp(() {
    adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    repo = HomeRepositoryImpl(
      PassesApi(dio),
      BookingsApi(dio),
      HomeRemoteDataSource(dio),
      () async => const <String, StaffDto>{},
    );
  });

  group('동시에 나간다', () {
    test('패스 응답을 붙잡아 둬도 나머지 요청이 이미 나가 있다', () async {
      // 직렬이면 패스 응답이 오기 전엔 다음 요청이 **시작조차** 못 한다.
      // 이 테스트가 그 구조 변화를 직접 본다.
      adapter.holdPasses = true;

      final future = repo.loadHome(memberId: 'm1');
      await pumpEventQueue();

      expect(adapter.seen, contains('/v1/bookings'),
          reason: '패스를 기다리는 동안 예약 요청이 나가지 않았다 — 아직 직렬이다');
      expect(adapter.seen, contains('/v1/homeworks'));
      expect(adapter.seen, contains('/v1/hw-checks'));

      adapter.releasePasses();
      expect(await future, isA<Ok<HomeSummary>>());
    });
  });

  group('부분 실패가 앱을 죽이지 않는다', () {
    test('회원권 0개로 빠져나갈 때 남은 요청이 실패해도 조용하다', () async {
      // 여기가 가장 위험한 자리다: `EmptyPassesFailure`로 일찍 나가는데 남은
      // future가 뒤늦게 실패하면 **아무도 받지 않는 비동기 예외**가 된다.
      adapter.passesBody = '[]';
      adapter.failLate = true;

      final result = await repo.loadHome(memberId: 'm1');
      expect(result, isA<Err<HomeSummary>>());
      expect((result as Err<HomeSummary>).failure, isA<EmptyPassesFailure>(),
          reason: '늦게 도착한 실패가 원래 에러를 덮었다');

      // 뒤늦은 실패가 도착할 시간을 준다 — 여기서 죽으면 테스트가 깨진다.
      await pumpEventQueue(times: 20);
    });

    test('예약 조회가 실패하면 종전처럼 그 실패가 나간다', () async {
      adapter.failPath = '/v1/bookings';
      final result = await repo.loadHome(memberId: 'm1');
      expect(result, isA<Err<HomeSummary>>());
    });

    test('체크 조회 실패는 홈을 죽이지 않는다 — best-effort 규약 유지', () async {
      // 항목은 보여주되 "안 함"으로 위장하지 않는다(플래그로 올린다).
      adapter.failPath = '/v1/hw-checks';
      final result = await repo.loadHome(memberId: 'm1');
      expect(result, isA<Ok<HomeSummary>>());
      expect((result as Ok<HomeSummary>).value.homeworkChecksFailed, isTrue);
    });
  });
}

String _pass(String id, String status) =>
    '{"id":"$id","member_id":"m1","trainer_id":"t1","product":"PT 20회","paid_amount":1200000,'
    '"total_sessions":20,"remaining":8,"valid_from":"2026-01-01","valid_until":"2030-12-31",'
    '"status":"$status"}';

class _Adapter implements HttpClientAdapter {
  final seen = <String>[];
  String passesBody = '[${_pass('active1', 'active')}]';
  bool holdPasses = false;
  bool failLate = false;
  String? failPath;

  final _gate = Completer<void>();
  void releasePasses() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async {
    final path = o.path;
    seen.add(path.split('?').first);

    if (failPath != null && path.startsWith(failPath!)) {
      throw DioException(requestOptions: o, message: '실패');
    }
    if (path.startsWith('/v1/passes')) {
      if (holdPasses) await _gate.future;
      return _res(passesBody);
    }
    // 패스가 비어 일찍 빠져나간 뒤 **늦게** 실패하는 경로.
    if (failLate) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      throw DioException(requestOptions: o, message: '늦은 실패');
    }
    return _res('[]');
  }

  ResponseBody _res(String body) => ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}
