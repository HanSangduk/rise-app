import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/network/dio_client.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';

// 공개 경로(/v1/public/*)의 401은 로그아웃 사유가 아니다(P56 L10 후속, 피어 세션 P60 지적).
//
// 401 인터셉터는 "신원이 사라졌다"는 뜻으로 세션을 비운다. 그런데 무인증 공개 경로는 신원을
// 보지 않으므로 거기서 오는 401은 신원 상실이 아니다 — 경로가 아직 없는 **구서버**가 auth
// 미들웨어에서 먼저 401(missing_token)을 돌려주는 경우(v2.29 배포 전), 또는 Bearer 첨부가
// 실패한 경우다. 홈 헤더·마이 탭이 상호 한 줄을 읽으러 `/v1/public/center`를 부르는데, 그
// 요청의 401이 회원을 로그아웃시키면 안 된다.
void main() {
  group('isPublicApiPath', () {
    test('/v1/public/* 와 Hosting 미러 /api/v1/public/* 만 공개다', () {
      expect(isPublicApiPath('/v1/public/center'), isTrue);
      expect(isPublicApiPath('/v1/public/business'), isTrue);
      expect(isPublicApiPath('/api/v1/public/center'), isTrue);
      expect(isPublicApiPath('https://api.example.com/v1/public/center'), isTrue);
    });

    test('인증 경로는 공개가 아니다 — 접두가 비슷해도', () {
      for (final p in ['/v1/me', '/v1/center', '/v1/publication', '/v1/publicity/x', '/v1/members']) {
        expect(isPublicApiPath(p), isFalse, reason: p);
      }
    });
  });

  group('401 인터셉터', () {
    late ProviderContainer container;
    late _StatusAdapter adapter;
    late ProviderSubscription<Dio> dioSub;

    setUp(() {
      adapter = _StatusAdapter();
      container = ProviderContainer.test();
      container.read(sessionProvider.notifier).set(
            const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람'),
          );
      // dioProvider는 autoDispose다 — 앱에서는 API provider들이 붙들고 있지만 여기선 아무도
      // 구독하지 않아 read 직후 폐기되고, 인터셉터의 `ref.read`가 "disposed Ref"로 터진다.
      // 구독을 하나 걸어 앱과 같은 수명을 만든다.
      dioSub = container.listen(dioProvider, (_, __) {});
      dioSub.read().httpClientAdapter = adapter;
    });

    tearDown(() => dioSub.close());

    Future<void> fire(String path) async {
      try {
        await dioSub.read().get<Map<String, dynamic>>(path);
        fail('401이어야 한다');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 401, reason: 'type=${e.type} error=${e.error} msg=${e.message}');
      }
    }

    test('공개 경로의 401은 세션을 지우지 않는다', () async {
      await fire('/v1/public/center');
      expect(container.read(sessionProvider), isNotNull, reason: '상호 읽기 401이 회원을 로그아웃시켰다');
    });

    test('인증 경로의 401은 종전대로 세션을 지운다 — 방어선이 신원 상실 처리를 무디게 하지 않는다', () async {
      await fire('/v1/me');
      expect(container.read(sessionProvider), isNull);
    });
  });
}

/// 어느 경로든 401 {"error":"missing_token"}을 돌려주는 어댑터.
class _StatusAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      jsonEncode({'error': 'missing_token'}),
      401,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}
