import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/bookings_api.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/home/data/home_remote_data_source.dart';
import 'package:rise_member/features/home/data/home_repository_impl.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';

// 홈의 "지금"·"오늘" 배선이 **센터(KST) 축** 위에 있는지.
//
// 서버는 전 계층이 고정 KST(+09:00)로 판정하고(`backend/internal/domain/booking.go`의
// `KST = time.FixedZone("KST", 9*60*60)`, `api/service.go`의 `today()`), slotKey
// "20260814-20"도 KST 벽시계다. 홈은 그 벽시계를 `DateTime.now()`(기기 로컬)와
// 비교하고 있었다 — 국내에선 우연히 맞고, 해외 체류·기기 시계 오설정에선
// **오프셋 차만큼 통째로** 틀린다.
//
// ⚠️ 실행 TZ에 대하여(date_format_test.dart와 같은 주의): `nowKst()`가 진짜 시계를
// 읽는 탓에 호스트가 KST면 `nowKst() == DateTime.now()`라 회귀가 **원리상 보이지
// 않는다**. 이 파일은 `TZ=UTC` / `TZ=America/New_York` / `TZ=Pacific/Auckland` /
// `TZ=Asia/Seoul` 네 가지로 실제로 돌려 확인했고, 뮤테이션(`DateFmt.nowKst()` →
// `DateTime.now()`)은 KST 아닌 TZ에서만 죽는다. **KST 아닌 TZ로도 한 번 돌리는
// 것까지가 검증이다.**
//
// 그래서 판정을 두 종류로 나눠 담았다:
//  ① 시각 판정(체크인 ±30분 · 지난 예약 · 취소 컷오프) — 오프셋 9시간이 창(30분~24시간)
//     보다 커서 **하루 중 언제 돌려도** 로컬 축이면 답이 뒤집힌다.
//  ② 날짜 판정(hw-check의 date) — KST 날짜와 로컬 날짜가 갈리는 시간대에만 답이
//     갈린다. 그래도 값 자체는 언제나 KST여야 하므로 고정해 둔다.
void main() {
  /// 지금(KST)에서 30분 이내인 정시 — slotKey는 시간 단위라 "가장 가까운 정시"는
  /// 언제 돌려도 ±30분 안에 있다(체크인 시간창의 경계를 실행 시각에 맡기지 않는다).
  DateTime nearestHourKst() {
    final now = DateFmt.nowKst();
    final floor = DateTime(now.year, now.month, now.day, now.hour);
    return now.difference(floor) < const Duration(minutes: 30)
        ? floor
        : floor.add(const Duration(hours: 1));
  }

  String slotKeyAt(DateTime kst) => DateFmt.toSlotKey(kst, kst.hour);

  late _KstApiAdapter adapter;
  late HomeRepositoryImpl repo;
  late Dio dio;

  setUp(() {
    adapter = _KstApiAdapter();
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    repo = HomeRepositoryImpl(
      PassesApi(dio),
      BookingsApi(dio),
      HomeRemoteDataSource(dio),
      () async => const <String, StaffDto>{},
    );
  });

  Future<HomeSummary> loadOk() async {
    final result = await repo.loadHome(memberId: 'm1');
    expect(result, isA<Ok<HomeSummary>>(), reason: '홈 로드가 실패했다: $result');
    return (result as Ok<HomeSummary>).value;
  }

  group('시각 판정 — slotKey(KST 벽시계)와 같은 축에서 뺀다', () {
    test('지난 예약은 "다음 예약"이 되지 않는다 (로컬 축이면 3시간 전 수업이 미래로 보인다)', () async {
      // TZ=UTC에서 로컬 축을 쓰면 "지금"이 9시간 뒤처져, 3시간 전에 끝난 수업이
      // 아직 6시간 남은 것으로 읽힌다 — 정렬상 더 이르므로 그게 다음 예약이 된다.
      final past = nearestHourKst().subtract(const Duration(hours: 3));
      final future = nearestHourKst().add(const Duration(hours: 5));
      adapter.bookings = [
        _booking('past', slotKeyAt(past)),
        _booking('future', slotKeyAt(future)),
      ];

      final summary = await loadOk();

      expect(summary.nextBooking, isNotNull);
      expect(summary.nextBooking!.id, 'future',
          reason: '이미 지난 수업이 "다음 예약" 카드에 남았다 — 회원이 안 오거나 헛걸음한다');
    });

    // 체크인 시간창(±30분)과 무료 취소 컷오프의 KST 축 검증은 여기 있었지만,
    // 판정이 repository를 떠나면서 함께 옮겨갔다(P51):
    //   → test/features/home/presentation/widgets/next_booking_card_test.dart
    //     의 '시간축 — "지금"은 기기 로컬이 아니라 센터(KST)다' 그룹.
    //
    // 옮긴 이유: 두 값은 이제 로드 시점에 bool로 굳지 않는다. `NextBooking`은
    // startAt만 들고 가고, `DateFmt.nowKst()`를 실제로 부르는 프로덕션 코드는
    // 카드(TimeBoundaryBuilder)다 — 축이 틀어지는 회귀도 거기서만 잡힌다.
    // 같은 픽스처 기법("가장 가까운 정시")과 같은 TZ 규약을 그대로 이어받았다.
  });

  group('날짜 판정 — Home Work의 "오늘"은 읽기·쓰기가 같은 KST 날짜다', () {
    test('체크 조회(GET ?date=)가 KST 오늘을 묻는다', () async {
      await loadOk();

      expect(adapter.hwChecksQueryDates, isNotEmpty);
      expect(adapter.hwChecksQueryDates.last, DateFmt.isoDate(DateFmt.todayKst()));
    });

    test('서버 today()와 같은 문자열 — 서버: time.Now().In(KST).Format("2006-01-02")', () async {
      await loadOk();

      final serverToday = DateTime.now().toUtc().add(const Duration(hours: 9));
      String pad(int v) => v.toString().padLeft(2, '0');

      expect(
        adapter.hwChecksQueryDates.last,
        '${serverToday.year}-${pad(serverToday.month)}-${pad(serverToday.day)}',
      );
    });

    test('토글이 보내는 date가 조회한 date와 **같다** — 한쪽만 KST면 체크가 되돌아가 보인다', () async {
      // 이게 이 그룹의 핵심이다. 읽기(GET ?date=)와 쓰기(POST body date)가 갈리면
      // 회원이 체크한 값이 다른 날짜 문서에 저장되고, 다음 로드는 그걸 못 읽어
      // 체크가 저절로 풀린 것처럼 보인다. 종전엔 둘 다 로컬이라 **틀린 채로
      // 일관**됐다 — 한쪽만 고치는 순간 이 테스트가 깨진다.
      final container = _container(repo);
      addTearDown(container.dispose);
      // 홈 탭이 화면에 떠 있는 상태 — 구독을 걸지 않으면 autoDispose가 로드 직후
      // 상태를 버려, 토글이 `state.value == null`로 조용히 빠져나간다.
      container.listen(homeViewModelProvider, (_, __) {});
      final summary = await container.read(homeViewModelProvider.future);
      expect(summary.homeworkChecksFailed, isFalse, reason: '체크 조회가 실패하면 토글이 잠긴다');

      await container
          .read(homeViewModelProvider.notifier)
          .toggleHomework(summary.homeworkItems.first);

      expect(adapter.hwCheckPostDates, hasLength(1));
      expect(adapter.hwCheckPostDates.single, adapter.hwChecksQueryDates.first);
      expect(adapter.hwCheckPostDates.single, DateFmt.isoDate(DateFmt.todayKst()));
    });
  });
}

ProviderContainer _container(HomeRepositoryImpl repo) {
  final container = ProviderContainer.test(
    overrides: [
      homeRepositoryProvider.overrideWithValue(repo),
      centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
    ],
  );
  container.read(sessionProvider.notifier).set(
        const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람'),
      );
  return container;
}

String _booking(String id, String slotKey) =>
    '{"id":"$id","slot_key":"$slotKey","member_id":"m1","trainer_id":"t1",'
    '"pass_id":"p1","kind":"pt","status":"confirmed"}';

class _KstApiAdapter implements HttpClientAdapter {
  List<String> bookings = const [];

  /// GET /v1/hw-checks에 실려 나간 date= 값들(호출 순서대로).
  final hwChecksQueryDates = <String>[];

  /// POST /v1/hw-checks 바디의 date 값들.
  final hwCheckPostDates = <String>[];

  static const _passes = '''
[{"id":"p1","member_id":"m1","trainer_id":"t1","product":"PT 20회","paid_amount":1200000,
  "total_sessions":20,"remaining":8,"valid_from":"2026-01-01","valid_until":"2030-12-31","status":"active"}]''';

  /// schedule 생략 = 매일 노출 — 실행 요일에 따라 테스트가 흔들리지 않게.
  static const _homeworks = '''
[{"id":"h1","trainer_id":"t1","scope":"individual","target_member_ids":["m1"],
  "items":[{"name":"플랭크"},{"name":"스쿼트"}]}]''';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.startsWith('/v1/passes')) return _res(_passes);
    if (path.startsWith('/v1/bookings')) return _res('[${bookings.join(',')}]');
    if (path.startsWith('/v1/homeworks')) return _res(_homeworks);
    if (path.startsWith('/v1/hw-checks')) {
      if (options.method == 'POST') {
        final body = options.data as Map<String, dynamic>;
        hwCheckPostDates.add(body['date'] as String);
        return _res('{}');
      }
      final date = options.queryParameters['date']?.toString() ?? '';
      hwChecksQueryDates.add(date);
      // 조회는 성공시킨다(실패하면 토글이 잠겨 쓰기 경로를 볼 수 없다).
      return _res(
        jsonEncode([
          {'member_id': 'm1', 'hw_id': 'h1', 'date': date, 'done': [false, false]},
        ]),
      );
    }
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
