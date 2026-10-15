import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/bookings_api.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/network/dio_client.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/session/session_store.dart';
import 'package:rise_member/features/booking/data/booking_remote_data_source.dart';
import 'package:rise_member/features/booking/data/booking_repository_impl.dart';
import 'package:rise_member/features/home/data/home_remote_data_source.dart';
import 'package:rise_member/features/home/data/home_repository_impl.dart';
import 'package:rise_member/features/my/data/my_repository_impl.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/features/my/data/my_remote_data_source.dart';

// 스태프 목록 출처 단일화 회귀.
//
// 예전엔 홈·예약·마이의 repository가 staffMapProvider를 거치지 않고
// StaffDirectory.fetchAll()을 **직접** 호출했다. 그래서
//   ① 탭마다 GET /v1/staff가 새로 나갔고(홈+예약 진입에만 2회 이상),
//   ② "퇴사 여부"의 출처가 캐시와 직접조회 둘로 갈려 한 화면 안에서 모순됐고,
//   ③ ref.invalidate(staffMapProvider)가 그 세 화면의 라벨엔 아무 영향이 없었다.
//   ④ fetchAll()을 가드 없이 맨 먼저 await해서, /v1/staff 한 번의 실패가
//      3개 탭을 통째로 에러 화면으로 만들었다.
void main() {
  late _RecordingAdapter adapter;
  late ProviderContainer container;

  setUp(() {
    adapter = _RecordingAdapter();
    container = ProviderContainer.test(
      overrides: [dioProvider.overrideWithValue(_dio(adapter))],
    );
  });

  HomeRepositoryImpl homeRepo() {
    final dio = container.read(dioProvider);
    return HomeRepositoryImpl(
      PassesApi(dio),
      BookingsApi(dio),
      HomeRemoteDataSource(dio),
      container.read(staffMapReaderProvider),
    );
  }

  BookingRepositoryImpl bookingRepo() {
    final dio = container.read(dioProvider);
    return BookingRepositoryImpl(
      BookingRemoteDataSource(dio),
      BookingsApi(dio),
      container.read(staffMapReaderProvider),
    );
  }

  MyRepositoryImpl myRepo() {
    final dio = container.read(dioProvider);
    return MyRepositoryImpl(
      PassesApi(dio),
      container.read(staffMapReaderProvider),
      MyRemoteDataSource(dio),
      MemberApi(dio),
    );
  }

  Future<void> loadAllThreeTabs() async {
    await homeRepo().loadHome(memberId: 'm1');
    await bookingRepo().loadMyBookings('m1');
    await myRepo().load('m1');
  }

  group('출처 단일화 — 세 탭이 캐시 하나를 공유한다', () {
    test('홈·예약·마이를 전부 로드해도 GET /v1/staff는 한 번만 나간다', () async {
      await loadAllThreeTabs();

      expect(adapter.countOf('/v1/staff'), 1);
      // 나머지 조회는 탭별로 그대로 나간다(캐시 대상이 아님) — 스태프만 공유됐는지 확인.
      expect(adapter.countOf('/v1/passes'), 2); // 홈 + 마이
    });

    test('세 탭이 같은 맵을 보므로 "퇴사 여부"가 갈릴 수 없다', () async {
      final home = await homeRepo().loadHome(memberId: 'm1');
      final booking = await bookingRepo().loadMyBookings('m1');
      final my = await myRepo().load('m1');

      final homePass = (home as Ok).value.passes.single;
      final myPass = (my as Ok).value.passes.single;
      expect(homePass.trainerInactive, isTrue);
      expect(myPass.trainerInactive, isTrue);
      expect(homePass.trainerName, '정혜린');
      // 화면에서 읽는 캐시(staffMapProvider)도 같은 객체다.
      expect(container.read(staffMapProvider).value?['t1']?.isInactive, isTrue);
      expect((booking as Ok).value, isEmpty);
    });

    test('invalidate(staffMapProvider)가 실제로 다음 로드에 반영된다', () async {
      await homeRepo().loadHome(memberId: 'm1');
      expect(adapter.countOf('/v1/staff'), 1);

      // 예전엔 repository가 캐시를 거치지 않아, 무효화는 화면이 watch하는 캐시만
      // 건드리고 라벨(도메인 플래그)에는 아무 영향이 없었다.
      adapter.staffBody = '[{"uid":"t1","name":"박서준","status":"active"}]';
      container.invalidate(staffMapProvider);

      final home = await homeRepo().loadHome(memberId: 'm1');
      expect(adapter.countOf('/v1/staff'), 2);
      final pass = (home as Ok).value.passes.single;
      expect(pass.trainerName, '박서준');
      expect(pass.trainerInactive, isFalse);
    });
  });

  group('best-effort — 스태프 조회 실패가 탭을 죽이지 않는다', () {
    setUp(() => adapter.staffStatus = 500);

    test('홈·예약·마이 모두 정상 로드된다(이름만 미해석)', () async {
      final home = await homeRepo().loadHome(memberId: 'm1');
      final booking = await bookingRepo().loadMyBookings('m1');
      final my = await myRepo().load('m1');

      expect(home, isA<Ok<Object?>>());
      expect(booking, isA<Ok<Object?>>());
      expect(my, isA<Ok<Object?>>());

      final pass = (home as Ok).value.passes.single;
      // 이름과 퇴사 여부는 **함께** 사라진다 — 이름이 없으면 화면은 코치 문구를
      // 통째로 생략하므로, "(퇴사)"를 빼먹어 현직이라 우기는 자리가 생기지 않는다.
      expect(pass.trainerName, isNull);
      expect(pass.trainerInactive, isFalse);
    });

    test('실패는 캐시에 눌러앉지 않는다 — 서버가 돌아오면 다음 로드에서 해석된다', () async {
      await homeRepo().loadHome(memberId: 'm1');

      adapter.staffStatus = 200;
      final home = await homeRepo().loadHome(memberId: 'm1');

      expect((home as Ok).value.passes.single.trainerName, '정혜린');
    });
  });

  group('TTL — 활성 구독이 있어도 만료가 계속 동작한다', () {
    test('구독 중 15분이 지나면 재조회하고, 그 뒤로도 다시 만료된다', () {
      fakeAsync((async) {
        final local = ProviderContainer.test(
          overrides: [dioProvider.overrideWithValue(_dio(adapter))],
        );
        // 예약 탭은 IndexedStack으로 계속 mount된 채 staffMapProvider를 watch한다
        // — 즉 "활성 구독이 있는 상태로 TTL이 만료되는" 경로가 실제로 도달한다.
        local.listen(staffMapProvider, (_, __) {});
        async.elapse(const Duration(seconds: 1));
        expect(adapter.countOf('/v1/staff'), 1);

        async.elapse(const Duration(minutes: 16));
        // 예전 구현(Timer(ttl, link.close))은 구독이 남아 있어 폐기도 재빌드도
        // 일어나지 않았고, 타이머는 이미 소진돼 TTL이 영구히 죽었다.
        expect(adapter.countOf('/v1/staff'), 2);

        // 만료가 1회성이 아니라는 것 — 새 타이머가 다시 걸렸는지.
        async.elapse(const Duration(minutes: 16));
        expect(adapter.countOf('/v1/staff'), 3);
      });
    });

    test('구독이 없으면 만료 시점에 요청을 새로 내지 않고, 다음 읽기에서 갱신한다', () {
      fakeAsync((async) {
        final local = ProviderContainer.test(
          overrides: [dioProvider.overrideWithValue(_dio(adapter))],
        );
        local.read(staffMapProvider.future);
        async.elapse(const Duration(seconds: 1));
        expect(adapter.countOf('/v1/staff'), 1);

        async.elapse(const Duration(minutes: 16));
        expect(adapter.countOf('/v1/staff'), 1); // 폴링이 아니라 캐시 만료

        local.read(staffMapProvider.future);
        async.elapse(const Duration(seconds: 1));
        expect(adapter.countOf('/v1/staff'), 2);
      });
    });

    test('TTL 안에서는 재조회하지 않는다', () {
      fakeAsync((async) {
        final local = ProviderContainer.test(
          overrides: [dioProvider.overrideWithValue(_dio(adapter))],
        );
        local.listen(staffMapProvider, (_, __) {});
        async.elapse(const Duration(minutes: 14));
        expect(adapter.countOf('/v1/staff'), 1);
      });
    });
  });

  group('세션 경계 — 캐시가 계정을 넘어 살아남지 않는다(P73)', () {
    const first = AppSession(uid: 'u1', role: 'member', centerId: 'rise', memberId: 'm1');
    const second = AppSession(uid: 'u2', role: 'member', centerId: 'branch2', memberId: 'm2');

    ProviderContainer sessionAware() => ProviderContainer.test(
          overrides: [
            dioProvider.overrideWithValue(_dio(adapter)),
            sessionStoreProvider.overrideWithValue(_NoopSessionStore()),
          ],
        );

    test('로그아웃 → 다른 계정 로그인이면 이전 센터의 명단을 재사용하지 않는다', () async {
      final local = sessionAware();
      local.read(sessionProvider.notifier).set(first);
      // 예약 탭처럼 살아 있는 구독자 + 로그인 사용자의 조회.
      final sub = local.listen(staffMapProvider, (_, __) {});
      expect((await local.read(staffMapProvider.future)).keys.toList(), ['t1']);

      // 같은 기기에서 로그아웃 → 셸이 내려가며 구독도 끊긴다 — keepAlive는 정확히 이 순간
      // 캐시를 지키도록 만들어진 장치라, 종전엔 't1'(1호점 코치)이 그대로 살아남았다.
      local.read(sessionProvider.notifier).clear(reason: SessionEndReason.signedOut);
      sub.close();
      await pumpEventQueue();

      // 다른 센터 회원이 로그인한다(센터 태블릿·가족 공용폰).
      adapter.staffBody = '[{"uid":"t9","name":"2호점코치","status":"active"}]';
      local.read(sessionProvider.notifier).set(second);
      final map = await local.read(staffMapProvider.future);
      expect(map.keys.toList(), ['t9']);
      expect(map.containsKey('t1'), isFalse, reason: '1호점 코치가 2호점 회원에게 보인다');
    });

    test('구독이 살아 있는 채로 계정이 바뀌어도 새 계정 기준으로 다시 받는다', () async {
      final local = sessionAware();
      local.read(sessionProvider.notifier).set(first);
      local.listen(staffMapProvider, (_, __) {});
      expect((await local.read(staffMapProvider.future)).keys.toList(), ['t1']);

      adapter.staffBody = '[{"uid":"t9","name":"2호점코치","status":"active"}]';
      local.read(sessionProvider.notifier).clear(reason: SessionEndReason.unauthorized);
      local.read(sessionProvider.notifier).set(second);
      await pumpEventQueue();

      final map = await local.read(staffMapProvider.future);
      expect(map.containsKey('t1'), isFalse);
      expect(map.containsKey('t9'), isTrue);
    });

    test('같은 신원 안에서는 세션 객체가 갈아 끼워져도 재조회하지 않는다(select memberId)', () async {
      final local = sessionAware();
      local.read(sessionProvider.notifier).set(first);
      local.listen(staffMapProvider, (_, __) {});
      await local.read(staffMapProvider.future);
      expect(adapter.countOf('/v1/staff'), 1);

      // 표시 이름만 바뀐 같은 사람(로그인 경로가 /v1/me의 빈 이름을 매칭 응답으로 메우는 자리).
      local.read(sessionProvider.notifier).set(first.withMemberName('김민지'));
      await pumpEventQueue();
      await local.read(staffMapProvider.future);
      expect(adapter.countOf('/v1/staff'), 1, reason: '신원이 같은데 캐시를 버렸다');
    });
  });

  group('staffMapReader — 예외를 밖으로 내보내지 않는다', () {
    test('서버 오류든 무엇이든 빈 맵으로 떨어진다', () async {
      adapter.staffStatus = 503;
      final map = await container.read(staffMapReaderProvider)();
      expect(map, isEmpty);
    });

    test('성공하면 그대로 돌려준다', () async {
      final map = await container.read(staffMapReaderProvider)();
      expect(map['t1'], isA<StaffDto>());
      expect(map['t1']!.name, '정혜린');
    });
  });
}

Dio _dio(_RecordingAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;

/// 경로별 호출 횟수를 세는 Dio 어댑터 — "몇 번 나갔는가"가 이 파일의 핵심 관심사다.
class _RecordingAdapter implements HttpClientAdapter {
  final _counts = <String, int>{};

  int staffStatus = 200;
  String staffBody = '[{"uid":"t1","name":"정혜린","status":"inactive"}]';

  static const _passes = '''
[{"id":"p1","member_id":"m1","trainer_id":"t1","product":"PT 20회","paid_amount":1000000,
  "total_sessions":20,"remaining":8,"valid_from":"2026-01-01","valid_until":"2030-12-31"}]''';

  int countOf(String path) => _counts[path] ?? 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    _counts[path] = countOf(path) + 1;

    final (body, status) = switch (path) {
      '/v1/staff' => (staffStatus == 200 ? staffBody : '{"error":"staff down"}', staffStatus),
      '/v1/passes' => (_passes, 200),
      // 나머지는 전부 빈 배열 — 이 파일이 검증하는 건 스태프 조회 횟수와 그 실패의
      // 파급 범위이지, 각 탭의 본문이 아니다(빈 응답도 정상 경로다).
      _ => ('[]', 200),
    };

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

/// 세션 경계 테스트용 — 캐시 저장소(SharedPreferences)를 건드리지 않는다.
class _NoopSessionStore implements SessionStore {
  @override
  Future<AppSession?> read(String uid) async => null;

  @override
  Future<void> write(AppSession session) async {}

  @override
  Future<void> clear() async {}
}
