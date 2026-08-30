// POST /v1/contracts/{id}/sign — P44 wire 계약 고정.
//
// · 서명 이미지가 있으면 {"signature_png": <base64>} 바디 동봉.
// · 없으면(null) **바디 자체가 없다** — 바디 없는 sign은 종전 그대로 유효한
//   wire(결정 6)고, 서버 decodeJSON(DisallowUnknownFields) 앞에서 빈 오브젝트를
//   지어 보낼 이유가 없다. 여기서 {}라도 실리면 구서버(바디 예상 없음)와의
//   호환 서사가 어긋난다.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/my/data/my_remote_data_source.dart';

void main() {
  late _CapturingAdapter adapter;
  late MyRemoteDataSource source;

  setUp(() {
    adapter = _CapturingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    source = MyRemoteDataSource(dio);
  });

  test('signaturePng 동봉 — 경로·메서드·바디 필드가 wire 계약 그대로다', () async {
    await source.signContract('c-1', signaturePng: 'aVZCT1J3MEtHZ28=');

    final req = adapter.requests.single;
    expect(req.method, 'POST');
    expect(req.path, '/v1/contracts/c-1/sign');
    expect(req.data, {'signature_png': 'aVZCT1J3MEtHZ28='});
  });

  test('signaturePng 없음(null) — 바디를 싣지 않는다(종전 wire 그대로, 결정 6)', () async {
    await source.signContract('c-1');

    final req = adapter.requests.single;
    expect(req.path, '/v1/contracts/c-1/sign');
    expect(req.data, isNull, reason: '빈 오브젝트({})도 아니고 바디 부재여야 한다');
  });
}

class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {}
}
