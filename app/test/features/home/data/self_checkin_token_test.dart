import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/network/api_config.dart';
import 'package:rise_member/core/network/api_result_guard.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/home/data/home_remote_data_source.dart';

// 셀프 체크인 QR 실연동 회귀.
//
// 종전엔 빌드 시 심은 상수(ApiConfig.checkinQrToken)를 **무조건** 보냈다 — 화면의
// "체크인" 다이얼로그는 확인만 받고 스캔은 하지 않았다. 이제 스캔 값이 1순위이고,
// 상수는 카메라 없는 개발 환경을 위한 폴백으로만 남는다. 이 순서가 뒤집히면
// 데스크 QR을 바꿔도 앱이 옛 토큰을 계속 보내고, 그걸 화면에서는 알 수 없다.
void main() {
  late _CheckinAdapter adapter;
  late HomeRemoteDataSource remote;

  setUp(() {
    adapter = _CheckinAdapter();
    remote = HomeRemoteDataSource(
      Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter,
    );
  });

  group('qr_token 우선순위', () {
    test('스캔한 값이 1순위 — 빌드 상수를 덮는다', () async {
      await remote.selfCheckIn(scannedToken: 'rise-desk-2026-08');

      expect(adapter.lastBody?['source'], 'self_qr');
      expect(adapter.lastBody?['qr_token'], 'rise-desk-2026-08');
      expect(adapter.lastBody?['qr_token'], isNot(ApiConfig.checkinQrToken));
    });

    test('스캔 값이 없으면(개발 폴백) 빌드 상수를 보낸다', () async {
      await remote.selfCheckIn();

      expect(adapter.lastBody?['qr_token'], ApiConfig.checkinQrToken);
    });

    test('빈 문자열·공백만 있는 스캔 값도 폴백으로 취급한다', () async {
      await remote.selfCheckIn(scannedToken: '   ');

      expect(adapter.lastBody?['qr_token'], ApiConfig.checkinQrToken);
    });

    test('앞뒤 공백은 다듬어 보낸다 — QR 인코딩에 개행이 섞여도 서버 대조가 깨지지 않게', () async {
      await remote.selfCheckIn(scannedToken: '  rise-desk-checkin\n');

      expect(adapter.lastBody?['qr_token'], 'rise-desk-checkin');
    });

    test('booking_id는 보내지 않는다 — 서버가 ±30분 시간창으로 스스로 찾는다(P44)', () async {
      await remote.selfCheckIn(scannedToken: 'x');

      expect(adapter.lastBody?.containsKey('booking_id'), isFalse);
    });
  });

  // repository가 하는 일과 같은 경로(guardApi)로 통과시켜, 서버 문구가 가공되지
  // 않고 화면까지 그대로 오는지 본다.
  group('잘못된 QR — 서버 400 문구를 그대로 노출', () {
    test('{"error":...} 본문이 RejectedFailure 메시지가 된다', () async {
      adapter.status = 400;
      adapter.body = '{"error":"qr_token이 유효하지 않음"}';

      final result = await guardApi(() => remote.selfCheckIn(scannedToken: 'wrong'));

      expect(result, isA<Err<void>>());
      final failure = (result as Err<void>).failure;
      expect(failure, isA<RejectedFailure>());
      expect(failure.message, 'qr_token이 유효하지 않음');
    });

    test('시간창 밖 문구도 가공하지 않는다', () async {
      adapter.status = 400;
      adapter.body = '{"error":"시간창 안의 예약을 찾을 수 없음"}';

      final result = await guardApi(() => remote.selfCheckIn(scannedToken: 'ok'));

      expect((result as Err<void>).failure.message, '시간창 안의 예약을 찾을 수 없음');
    });
  });
}

class _CheckinAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastBody;
  int status = 200;
  String body = '{}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/v1/checkin') {
      lastBody = Map<String, dynamic>.from(options.data as Map);
    }
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
