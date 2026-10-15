// `POST /v1/join/match` 응답의 `center`(계약 v2.32)를 앱이 읽는다(P65 후속 3 · P73).
//
// 서버는 v2.32부터 매칭된 **그 회원의 센터** 신원을 응답에 실어 왔는데 앱 DTO엔 그 칸이 없어
// 버려졌고, 대기실 매칭 카드는 무인증 공개 경로(기본 센터 고정)의 상호를 찍었다. DTO(freezed
// 생성물)를 건드리지 않고 데이터 소스가 응답 맵에서 상호 한 칸만 읽는다 — 그 배선을 고정한다.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/auth/data/auth_remote_data_source.dart';

void main() {
  AuthRemoteDataSource source(String body) => AuthRemoteDataSource(_StubDio(body));

  test('center.name이 오면 그대로 읽는다', () async {
    final payload = await source('''
{"member":{"id":"m2","name":"람","phone":"010-****-5678","status":"active","trainer_id":"t1"},
 "needs_confirm":true,
 "center":{"name":"라이즈 2호점","phone":"02-000-0002","address":"서울"}}
''').matchJoin('01012345678');

    expect(payload.dto.member?.id, 'm2');
    expect(payload.dto.needsConfirm, isTrue);
    expect(payload.centerName, '라이즈 2호점');
  });

  test('center가 없으면(미매칭·미등록·구서버) 빈 문자열 — 예외를 내지 않는다', () async {
    final noCenter = await source('{"needs_confirm":false}').matchJoin('01012345678');
    expect(noCenter.dto.member, isNull);
    expect(noCenter.centerName, '');

    // 형이 이상해도(널·문자열·이름 누락·이름이 숫자·공백뿐) 매칭 자체는 살아남는다 — 상호 한 칸
    // 때문에 로그인이 막히면 안 된다. `as String?` 캐스트였다면 숫자 이름에서 던졌다.
    for (final raw in [
      '{"needs_confirm":true,"center":null}',
      '{"needs_confirm":true,"center":"rise"}',
      '{"needs_confirm":true,"center":{"phone":"02"}}',
      '{"needs_confirm":true,"center":{"name":123}}',
      '{"needs_confirm":true,"center":{"name":"   "}}',
    ]) {
      final p = await source(raw).matchJoin('01012345678');
      expect(p.centerName, '', reason: raw);
      expect(p.dto.needsConfirm, isTrue, reason: raw);
    }
  });
}

class _StubDio with DioMixin implements Dio {
  _StubDio(String body) {
    options = BaseOptions();
    httpClientAdapter = _Adapter(body);
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
