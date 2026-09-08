// 세션 소멸 처리(P29).
//
// 종전 결함: `guardApi`가 400대를 전부 `RejectedFailure`로 뭉갰다. 그래서 토큰이
// 폐기되면(다른 기기에서 탈퇴·계정 삭제·리프레시 토큰 무효화) 회원은 **모든 화면에서
// "요청을 처리할 수 없어요"만** 보고, 그게 규칙에 걸린 건지 로그인이 끊긴 건지 알 수도
// 없고 로그인으로 돌아갈 길도 안내받지 못했다.
//
// Firebase SDK가 만료 임박 토큰은 알아서 갱신하므로(`getIdToken()`), 여기까지 401이
// 왔다는 건 **갱신으로 살릴 수 없는 상태**다.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/network/api_result_guard.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';

DioException _http(int status, {Object? body}) => DioException(
      requestOptions: RequestOptions(path: '/v1/me'),
      response: Response<Object?>(
        requestOptions: RequestOptions(path: '/v1/me'),
        statusCode: status,
        data: body,
      ),
    );

Future<Failure> _failureOf(int status, {Object? body}) async {
  final r = await guardApi<int>(() async => throw _http(status, body: body));
  return (r as Err<int>).failure;
}

void main() {
  group('401 — 신원이 사라진 것', () {
    test('AuthFailure로 분류한다 — 규칙 위반과 다른 종류의 실패다', () async {
      expect(await _failureOf(401), isA<AuthFailure>());
    });

    test('무엇을 해야 하는지 말한다', () async {
      final f = await _failureOf(401);
      expect(f.message, contains('로그인'));
    });

    test('서버가 이유를 말했으면 그 말을 쓴다', () async {
      final f = await _failureOf(401, body: {'error': '토큰이 만료됐어요'});
      expect(f, isA<AuthFailure>());
      expect(f.message, '토큰이 만료됐어요');
    });
  });

  // P69 C2 — 계약 v2.34: POST /v1/join/request 409 `{code: join_pending, center_id}`.
  group('409 join_pending — pending 확답', () {
    test('code가 join_pending이면 JoinPendingFailure(centerId) — AuthFailure 하위', () async {
      final f = await _failureOf(409, body: {
        'error': '이미 보낸 가입 요청이 있어요 — 센터에서 확인하면 연결돼요',
        'code': 'join_pending',
        'center_id': 'gangnam-2',
      });
      expect(f, isA<JoinPendingFailure>());
      expect((f as JoinPendingFailure).centerId, 'gangnam-2');
      expect(f, isA<AuthFailure>());
      expect(f.message, contains('이미 보낸'));
    });

    test('center_id가 없으면 \'\'', () async {
      final f = await _failureOf(409, body: {'error': 'x', 'code': 'join_pending'});
      expect((f as JoinPendingFailure).centerId, '');
    });

    test('code 없는 409(구서버)·다른 code는 종전대로 RejectedFailure — 문구로 판정하지 않는다', () async {
      expect(await _failureOf(409, body: {'error': '이미 보낸 가입 요청이 있어요'}), isA<RejectedFailure>());
      expect(await _failureOf(409, body: {'error': 'x', 'code': 'other'}), isA<RejectedFailure>());
      expect(await _failureOf(409, body: 'not a map'), isA<RejectedFailure>());
    });
  });

  group('403은 로그아웃 사유가 아니다', () {
    test('RejectedFailure로 남는다 — 신원은 멀쩡한데 권한이 없다는 뜻이다', () async {
      // 담당 아닌 코치의 조회, 탈퇴 회원의 잔여 호출이 여기 해당한다.
      // AuthFailure로 올리면 정상 거절이 세션 종료로 번진다.
      expect(await _failureOf(403), isA<RejectedFailure>());
      expect(await _failureOf(403), isNot(isA<AuthFailure>()));
    });

    test('400·404·409도 종전대로', () async {
      for (final s in [400, 404, 409]) {
        expect(await _failureOf(s), isA<RejectedFailure>(), reason: '$s');
        expect(await _failureOf(s), isNot(isA<AuthFailure>()), reason: '$s');
      }
    });

    test('5xx는 네트워크 실패 — 재시도가 의미 있는 자리다', () async {
      expect(await _failureOf(500), isA<NetworkFailure>());
      expect(await _failureOf(503), isA<NetworkFailure>());
    });
  });
}
