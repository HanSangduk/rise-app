// 마이 탭 로드가 독립 조회를 **동시에** 보낸다(P74) — 홈(home_parallel_load_test)과 같은 자.
//
// 종전엔 staffMap → passes → 원장×K → contracts → payments → profile이 전부 직렬이었다. 결과 값은
// 직렬이든 병렬이든 같아서 실패 스위트(my_repository_failure_test)로는 이 변화를 잴 수 없다 —
// 누가 `await`를 앞으로 당겨 다시 직렬로 만들면 이 파일만 죽는다.

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/my/data/my_remote_data_source.dart';
import 'package:rise_member/features/my/data/my_repository_impl.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

void main() {
  late _Adapter adapter;
  late MyRepositoryImpl repo;

  setUp(() {
    adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    repo = MyRepositoryImpl(
      PassesApi(dio),
      () async => const <String, StaffDto>{},
      MyRemoteDataSource(dio),
      MemberApi(dio),
    );
  });

  test('패스 응답을 붙잡아 둬도 계약·결제·동의 조회는 이미 나가 있다', () async {
    adapter.holdPasses = true;

    final future = repo.load('m1');
    await pumpEventQueue();

    expect(adapter.seen, containsAll(<String>['/v1/contracts', '/v1/payments', '/v1/members']),
        reason: '패스를 기다리는 동안 다른 조회가 나가지 않았다 — 아직 직렬이다');
    expect(adapter.seen.where((p) => p.endsWith('/ledger')), isEmpty,
        reason: '원장은 패스 목록이 있어야 패스별로 조회한다 — 패스보다 먼저 나갈 수 없다');

    adapter.releasePasses();
    final result = await future;
    expect(result, isA<Ok<MySummary>>(), reason: '$result');
    expect(adapter.seen.where((p) => p.endsWith('/ledger')), hasLength(2), reason: '패스 2개 → 원장 2번');
  });

  test('패스 조회 실패로 일찍 빠져나가도 뒤늦게 실패한 조회가 앱을 죽이지 않는다', () async {
    // 병렬화의 위험: 필수 조회(패스)가 실패해 guardApi로 빠져나간 뒤 남은 future가 늦게 실패하면
    // **아무도 받지 않는 비동기 예외**가 된다. settle로 감싸 두었는지 여기서 본다.
    adapter.passesStatus = 500;
    adapter.failLate = true;

    final result = await repo.load('m1');
    expect(result, isA<Err<MySummary>>());

    // 늦은 실패(5ms 뒤)가 **시험 안에서** 도착하게 기다린다 — 받는 쪽이 없으면 여기서 죽는다.
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  test('패스가 많아도 원장은 동시에, 단 ledgerConcurrency개씩만 나간다', () async {
    // 재등록마다 패스가 하나씩 쌓인다 — 상한이 없으면 오래 다닌 회원일수록 연결이 한꺼번에 열린다.
    adapter.passCount = 10;
    adapter.ledgerDelay = const Duration(milliseconds: 2);

    final result = await repo.load('m1');
    expect(result, isA<Ok<MySummary>>(), reason: '$result');
    expect(adapter.seen.where((p) => p.endsWith('/ledger')), hasLength(10), reason: '패스 10개 → 원장 10번');
    expect(adapter.peakLedger, MyRepositoryImpl.ledgerConcurrency,
        reason: '상한이 빠지면 10, 다시 직렬이면 1');
    expect((result as Ok<MySummary>).value.ledgerFailedPassIds, isEmpty);
  });
}

class _Adapter implements HttpClientAdapter {
  final seen = <String>[];
  bool holdPasses = false;
  bool failLate = false;
  int passesStatus = 200;

  /// 2가 아니면 p1..pN 활성 패스를 만들어 준다(원장 동시성 시험).
  int passCount = 2;
  Duration ledgerDelay = Duration.zero;
  int _ledgerInFlight = 0;
  int peakLedger = 0;

  String get _passesBody => passCount == 2
      ? _passes
      : '[${[
          for (var i = 1; i <= passCount; i++)
            '{"id":"p$i","member_id":"m1","trainer_id":"t1","product":"PT 10회","paid_amount":700000,'
                '"total_sessions":10,"remaining":5,"valid_from":"2026-01-01","valid_until":"2030-12-31","status":"active"}'
        ].join(',')}]';

  final _gate = Completer<void>();
  void releasePasses() {
    if (!_gate.isCompleted) _gate.complete();
  }

  static const _passes = '''
[
  {"id":"p1","member_id":"m1","trainer_id":"t1","product":"PT 20회","paid_amount":1200000,
   "total_sessions":20,"remaining":8,"valid_from":"2026-01-01","valid_until":"2030-12-31","status":"active"},
  {"id":"p2","member_id":"m1","trainer_id":"t1","product":"PT 10회","paid_amount":700000,
   "total_sessions":10,"remaining":0,"valid_from":"2025-01-01","valid_until":"2025-12-31","status":"expired"}
]''';

  static const _profile = '[{"id":"m1","name":"람","phone":"01000000000",'
      '"consent":{"general":true,"sensitive":true}}]';

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async {
    final path = o.path.split('?').first;
    seen.add(path);

    if (path.startsWith('/v1/passes')) {
      if (holdPasses) await _gate.future;
      return passesStatus == 200 ? _res(_passesBody) : _res('{"error":"boom"}', passesStatus);
    }
    // 패스 실패로 일찍 빠져나간 뒤 **늦게** 실패하는 경로.
    if (failLate) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      throw DioException(requestOptions: o, message: '늦은 실패');
    }
    // 순서 주의: "/v1/members/{id}/ledger"도 "/v1/members" 접두사에 걸린다.
    if (path.endsWith('/ledger')) {
      _ledgerInFlight++;
      if (_ledgerInFlight > peakLedger) peakLedger = _ledgerInFlight;
      await Future<void>.delayed(ledgerDelay);
      _ledgerInFlight--;
      return _res('[]');
    }
    if (path.startsWith('/v1/members')) return _res(_profile);
    if (path.startsWith('/v1/contracts') || path.startsWith('/v1/payments')) return _res('[]');
    fail('마이 탭이 예상 밖의 엔드포인트를 호출했다: $path');
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
