import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/my/data/my_remote_data_source.dart';
import 'package:rise_member/features/my/data/my_repository_impl.dart';

// 회원탈퇴 데이터 계층(DELETE /v1/me, 계약 v2.11).
//
// 위젯 테스트가 못 잡는 것 셋을 여기서 고정한다:
//
//   ① **메서드와 경로.** 서버는 `DELETE /v1/me` 하나만 이 동작으로 인정한다. POST로
//      보내면 405가 아니라 **다른 핸들러(GET /me와 짝인 라우트가 없어 404)** 로 조용히
//      새고, 회원은 "탈퇴가 안 된다"만 본다.
//   ② **바디를 싣지 않는다.** 서버 decodeJSON이 DisallowUnknownFields라 어떤 바디든
//      400이 될 수 있고, 애초에 실을 값이 없다.
//   ③ **응답 파싱은 절대 던지지 않는다.** 200을 받았다는 것은 계정이 **이미** 지워졌다는
//      뜻이다. 요약 숫자 하나 때문에 예외가 올라가면 성공한 탈퇴가 실패 화면이 되고,
//      다시 눌러도 이제 404만 돌아온다(재시도 경로가 없다).
void main() {
  late _DeleteMeAdapter adapter;
  late MyRepositoryImpl repo;

  setUp(() {
    adapter = _DeleteMeAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    repo = MyRepositoryImpl(
      PassesApi(dio),
      () async => const <String, StaffDto>{},
      MyRemoteDataSource(dio),
      MemberApi(dio),
    );
  });

  test('DELETE /v1/me 를 바디 없이 부른다', () async {
    final result = await repo.deleteAccount();

    expect(result.isOk, isTrue);
    expect(adapter.method, 'DELETE');
    expect(adapter.path, '/v1/me');
    expect(adapter.hadBody, isFalse, reason: '바디를 실으면 DisallowUnknownFields에 걸릴 수 있다');
  });

  test('응답의 파기·보존 건수를 그대로 옮긴다', () async {
    final result = await repo.deleteAccount();

    final summary = result.valueOrNull!;
    expect(summary.bodyPhotos, 4);
    expect(summary.inbody, 2);
    expect(summary.workoutLogs, 9);
    expect(summary.retainedPasses, 2);
    expect(summary.retainedPayments, 3);
    expect(summary.cancelledBookings, 1);
    expect(summary.remainingSessions, 7);
  });

  test('응답이 비어 있어도 성공으로 처리한다(이미 지워진 계정을 실패로 보고하지 않는다)', () async {
    adapter.body = '{}';
    expect((await repo.deleteAccount()).isOk, isTrue);

    // 바디 자체가 없는 200(구서버·프록시)도 마찬가지다.
    adapter.body = '';
    expect((await repo.deleteAccount()).isOk, isTrue);
  });

  test('403은 서버 문구를 그대로 실어 거부로 매핑한다', () async {
    adapter.status = 403;
    adapter.body = '{"error":"권한이 없습니다"}';

    final result = await repo.deleteAccount();

    expect(result.isOk, isFalse);
    final failure = (result as Err).failure;
    expect(failure, isA<RejectedFailure>());
    expect(failure.message, '권한이 없습니다');
  });
}

class _DeleteMeAdapter implements HttpClientAdapter {
  String? method;
  String? path;
  bool hadBody = false;
  int status = 200;
  String body = '''
{"deleted":true,"member_id":"m1","withdrawn_at":"2026-08-25T05:00:00Z",
 "purged":{"body_photos":4,"inbody":2,"workout_logs":9,"hw_checks":12,"checkins":5,"recurrings":1},
 "retained":{"passes":2,"payments":3,"contracts":2,"ledger":31,"bookings":18},
 "cancelled_bookings":1,"remaining_sessions":7}''';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    method = options.method;
    path = options.path;
    hadBody = options.data != null;
    if (body.isEmpty) {
      return ResponseBody.fromString('', status);
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
