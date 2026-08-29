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

// 홈의 **대표 패스 선택** — 종료된 회원권이 기본 선택되던 결함.
//
// 예전 `_defaultPass`는 active가 하나도 없으면 `passes.first`를 그냥 골랐다.
// 환불된 패스 하나만 남은 회원의 홈은 그 패스를 골라 잔여 링("잔여 8회 — 연장 상담
// 가능")·담당 코치·다음 예약까지 **정상처럼** 그렸다. 회원이 화면에서 읽는 결론은
// "내 회원권 아직 살아 있다"인데, 서버는 그 패스로 예약도 홀딩도 받지 않는다
// (`CreateBooking`/`HoldPass`는 PassStatusActive만 통과).
//
// 여기서 고정하는 것:
//  ① 기본 선택은 active → scheduled 순. 종료 상태는 **기본으로는** 고르지 않는다.
//  ② 쓸 수 있는 패스가 하나도 없으면 `hasUsablePass=false`로 사실을 위로 올린다.
//  ③ 그래도 `selectedPassId`는 **실재하는 id**로 남긴다 — 예약 탭이 이 값을
//     `primaryPassId`로 받아 대표 패스를 찾고 거기서 만료·환불을 `PassNotUsable`로
//     직접 안내한다. 비우거나 throw하면 그 안내까지 함께 사라진다.
//  ④ 칩을 직접 누른 경우(preferredPassId)는 회원의 명시적 선택이라 존중한다.
void main() {
  late _PassApiAdapter adapter;
  late HomeRepositoryImpl repo;

  setUp(() {
    adapter = _PassApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    repo = HomeRepositoryImpl(
      PassesApi(dio),
      BookingsApi(dio),
      HomeRemoteDataSource(dio),
      () async => const <String, StaffDto>{},
    );
  });

  Future<HomeSummary> load({String? preferred}) async {
    final result =
        await repo.loadHome(memberId: 'm1', preferredPassId: preferred);
    expect(result, isA<Ok<HomeSummary>>(), reason: '홈 로드가 실패했다: $result');
    return (result as Ok<HomeSummary>).value;
  }

  group('기본 선택 — active → scheduled', () {
    test('환불 패스가 목록 앞에 있어도 active를 고른다', () async {
      adapter.passes = [_pass('refunded1', 'refunded'), _pass('active1', 'active')];

      final summary = await load();

      expect(summary.selectedPassId, 'active1');
      expect(summary.hasUsablePass, isTrue);
    });

    test('만료 패스가 목록 앞에 있어도 active를 고른다', () async {
      adapter.passes = [_pass('expired1', 'expired'), _pass('active1', 'active')];

      expect((await load()).selectedPassId, 'active1');
    });

    test('active가 없고 scheduled만 있으면 scheduled — "회원권 없음"으로 떨어뜨리지 않는다', () async {
      adapter.passes = [_pass('refunded1', 'refunded'), _pass('scheduled1', 'scheduled')];

      final summary = await load();

      expect(summary.selectedPassId, 'scheduled1');
      expect(summary.hasUsablePass, isTrue);
    });

    test('active와 scheduled가 함께 있으면 active가 이긴다', () async {
      adapter.passes = [_pass('scheduled1', 'scheduled'), _pass('active1', 'active')];

      expect((await load()).selectedPassId, 'active1');
    });
  });

  group('쓸 수 있는 패스가 하나도 없을 때', () {
    test('환불 패스 하나뿐 — hasUsablePass=false', () async {
      adapter.passes = [_pass('refunded1', 'refunded')];

      final summary = await load();

      expect(summary.hasUsablePass, isFalse,
          reason: '홈이 환불된 회원권을 잔여 링·다음 예약까지 갖춘 정상 회원권으로 그린다');
    });

    test('만료 패스만 여러 개 — hasUsablePass=false', () async {
      adapter.passes = [_pass('expired1', 'expired'), _pass('expired2', 'expired')];

      expect((await load()).hasUsablePass, isFalse);
    });

    test('그래도 selectedPassId는 실재하는 id다 — 예약 탭의 PassNotUsable 안내가 살아 있어야 한다', () async {
      adapter.passes = [_pass('refunded1', 'refunded'), _pass('expired1', 'expired')];

      final summary = await load();

      expect(summary.passes.map((p) => p.id), containsAll(['refunded1', 'expired1']));
      expect(summary.passes.any((p) => p.id == summary.selectedPassId), isTrue);
      // selectedPass 접근이 orElse 폴백으로 도망가지 않고 진짜로 찾아진다.
      expect(summary.selectedPass.id, summary.selectedPassId);
    });

    test('회원권이 0개인 것과는 다른 사건 — 여전히 EmptyPassesFailure만 던진다', () async {
      adapter.passes = const [];

      final result = await repo.loadHome(memberId: 'm1');

      expect(result, isA<Err<HomeSummary>>());
      expect((result as Err<HomeSummary>).failure, isA<EmptyPassesFailure>());
    });
  });

  group('칩을 직접 누른 선택은 존중한다', () {
    test('환불 칩을 누르면 그 패스가 선택된다 — 스스로 누른 칩이 화면을 지우면 안 된다', () async {
      adapter.passes = [_pass('active1', 'active'), _pass('refunded1', 'refunded')];

      final summary = await load(preferred: 'refunded1');

      expect(summary.selectedPassId, 'refunded1');
      // 목록에 쓸 수 있는 패스가 남아 있으므로 홈은 계속 정상 본문을 그린다.
      expect(summary.hasUsablePass, isTrue);
    });

    test('없는 id를 주면 기본 선택으로 떨어진다(환불 패스가 아니라 active)', () async {
      adapter.passes = [_pass('refunded1', 'refunded'), _pass('active1', 'active')];

      expect((await load(preferred: 'gone')).selectedPassId, 'active1');
    });
  });
}

String _pass(String id, String status) =>
    '{"id":"$id","member_id":"m1","trainer_id":"t1","product":"PT 20회","paid_amount":1200000,'
    '"total_sessions":20,"remaining":8,"valid_from":"2026-01-01","valid_until":"2030-12-31",'
    '"status":"$status"}';

class _PassApiAdapter implements HttpClientAdapter {
  List<String> passes = [_pass('active1', 'active')];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.startsWith('/v1/passes')) return _res('[${passes.join(',')}]');
    if (path.startsWith('/v1/bookings')) return _res('[]');
    if (path.startsWith('/v1/homeworks')) return _res('[]');
    if (path.startsWith('/v1/hw-checks')) return _res('[]');
    fail('홈이 예상 밖의 엔드포인트를 호출했다: $path');
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
