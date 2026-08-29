import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/bookings_api.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/booking/data/booking_remote_data_source.dart';
import 'package:rise_member/features/booking/data/booking_repository_impl.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_rules.dart';

// 예약 예산 판정(P13 H1)이 서 있는 **바닥**을 고정한다.
//
// 서버 예산은 `pass.Remaining − 이 패스의 confirmed 예약 수`인데, 오른쪽 항은
// "이 패스의"라서 예약이 어느 회원권에 붙었는지 모르면 재현할 수 없다.
// `GET /v1/bookings`는 회원 응답에서도 pass_id를 마스킹하지 않고 그대로 준다
// (슬롯과 달리 ListBookings엔 최소노출 처리가 없다). DTO는 예전부터 파싱하고
// 있었는데 도메인 매핑에서만 버려지고 있었고, 그 한 줄이 빠지면 모든 패스의
// openBookings가 0이 되어 판정이 조용히 옛 규칙(잔여만 보기)으로 되돌아간다.
void main() {
  late _BookingsAdapter adapter;
  late BookingRepositoryImpl repo;

  setUp(() {
    adapter = _BookingsAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    repo = BookingRepositoryImpl(
      BookingRemoteDataSource(dio),
      BookingsApi(dio),
      // 스태프 해석은 이 파일의 관심사가 아니다(이름 없이도 예산은 계산된다).
      () async => {},
    );
  });

  Future<List<MyBooking>> load() async {
    final result = await repo.loadMyBookings('m1');
    return (result as Ok<List<MyBooking>>).value;
  }

  test('pass_id가 도메인까지 살아서 온다 — 없으면 예산 판정이 통째로 무력화된다', () async {
    final bookings = await load();

    expect(bookings.map((b) => b.passId).toList(), ['p1', 'p1', 'p2', 'p1']);
  });

  test('로드한 목록으로 패스별 confirmed를 세면 서버 예산과 같은 값이 나온다', () async {
    final bookings = await load();

    // p1: confirmed 2건(b1·b2) + completed 1건(b4 — 이미 차감된 회차라 세지 않는다).
    expect(BookingRules.countOpenBookings(bookings, 'p1'), 2);
    expect(BookingRules.countOpenBookings(bookings, 'p2'), 1);
  });

  test('취소 건은 애초에 목록에 들어오지 않는다(cancelled 필터 유지)', () async {
    final bookings = await load();

    expect(bookings.map((b) => b.id), isNot(contains('b5')));
    expect(bookings, hasLength(4));
  });

  test('GET /v1/bookings는 from 없이 회원 전체를 받는다 — 서버와 같은 모집단', () async {
    await load();

    // 서버 countOpenPassBookings는 ListBookingsByMember 전체(지난 회차 포함)를
    // 센다. 앱이 "다가오는 예약만" 받아 오면 예산을 넉넉히 보고 서버가 거부한다.
    expect(adapter.lastQuery, {'member': 'm1'});
  });
}

class _BookingsAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastQuery;

  /// b4(completed)는 이미 원장에서 차감된 회차, b5(cancelled)는 되돌려준 건.
  /// b1은 **지난 날짜**의 confirmed — 곧 완료·노쇼로 차감될 청구권이라 센다.
  static const _bookings = '''
[{"id":"b1","slot_key":"20260101-10","member_id":"m1","trainer_id":"t1","pass_id":"p1",
  "kind":"pt","status":"confirmed"},
 {"id":"b2","slot_key":"20260830-10","member_id":"m1","trainer_id":"t1","pass_id":"p1",
  "kind":"pt","status":"confirmed"},
 {"id":"b3","slot_key":"20260831-10","member_id":"m1","trainer_id":"t2","pass_id":"p2",
  "kind":"pt","status":"confirmed"},
 {"id":"b4","slot_key":"20260102-10","member_id":"m1","trainer_id":"t1","pass_id":"p1",
  "kind":"pt","status":"completed"},
 {"id":"b5","slot_key":"20260901-10","member_id":"m1","trainer_id":"t1","pass_id":"p1",
  "kind":"pt","status":"cancelled"}]''';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/v1/bookings') lastQuery = Map.of(options.queryParameters);
    final body = options.path == '/v1/bookings' ? _bookings : '[]';
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
