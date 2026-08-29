import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/bookings_api.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/home/data/home_remote_data_source.dart';
import 'package:rise_member/features/home/data/home_repository_impl.dart';
import 'package:rise_member/features/home/domain/home_models.dart';

// 홈 — 오늘 체크 상태 조회 실패가 "미완료"로 위장하던 결함.
//
// GET /v1/hw-checks 실패를 빈 catch로 삼키면 모든 항목이 미체크로 렌더된다. 표시가
// 틀린 것으로 끝나지 않는 이유는 **쓰기 경로** 때문이다: POST /v1/hw-checks는 형제
// 항목의 done 배열 **전체**를 보내고, 서버 store.SaveHwCheck는 (member,hw,date) 키로
// `.Set()` — 문서를 통째로 교체한다. 서버가 [true,true,false]인데 조회가 실패해
// 전부 꺼진 화면에서 3번만 누르면 [false,false,true]가 저장되어 1·2번 완료가
// 조용히 사라진다. 회원 본인도 인지하지 못한다.
//
// 이 파일은 리포지토리가 그 사실을 **플래그로 위로 올리는지**만 본다(토글 차단
// 자체는 home_view_model 테스트가 고정한다).
void main() {
  late _HomeApiAdapter adapter;
  late HomeRepositoryImpl repo;

  setUp(() {
    adapter = _HomeApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    repo = HomeRepositoryImpl(
      PassesApi(dio),
      BookingsApi(dio),
      HomeRemoteDataSource(dio),
      () async => const <String, StaffDto>{},
    );
  });

  Future<HomeSummary> loadOk() async {
    final result = await repo.loadHome(memberId: 'm1');
    expect(result, isA<Ok<HomeSummary>>(), reason: '체크 조회 실패가 홈 전체를 죽였다: $result');
    return (result as Ok<HomeSummary>).value;
  }

  test('GET /v1/hw-checks 5xx → homeworkChecksFailed=true (항목은 그대로 렌더)', () async {
    adapter.hwChecksStatus = 500;

    final summary = await loadOk();

    expect(summary.homeworkChecksFailed, isTrue,
        reason: '플래그가 없으면 화면·뷰모델이 "전부 미완료"를 사실로 믿고 덮어쓴다');
    // best-effort 전제는 그대로 — 배정 목록 자체는 보여준다.
    expect(summary.homeworkItems, hasLength(3));
    expect(summary.homeworkItems.map((i) => i.done), everyElement(isFalse));
  });

  test('조회 성공이면 homeworkChecksFailed=false + 서버 done 반영', () async {
    // 늘 true를 세우는 구현으로 도망가면 아무도 체크를 못 하게 된다 — 반대 방향 고정.
    final summary = await loadOk();

    expect(summary.homeworkChecksFailed, isFalse);
    expect(summary.homeworkItems.map((i) => i.done), [true, true, false]);
    expect(summary.homeworkDone, 2);
  });

  test('오늘 체크 레코드가 아예 없는 것은 실패가 아니다 — "아직 안 함"이 맞다', () async {
    adapter.hwChecksBody = '[]';

    final summary = await loadOk();

    expect(summary.homeworkChecksFailed, isFalse);
    expect(summary.homeworkItems.map((i) => i.done), everyElement(isFalse));
  });

  test('copyWith가 플래그를 떨어뜨리지 않는다 — 낙관적 토글 한 번에 잠금이 풀리면 안 된다', () async {
    adapter.hwChecksStatus = 500;
    final summary = await loadOk();

    final afterToggle = summary.copyWith(homeworkItems: summary.homeworkItems);

    expect(afterToggle.homeworkChecksFailed, isTrue);
  });
}

class _HomeApiAdapter implements HttpClientAdapter {
  String passesBody = '''
[{"id":"p1","member_id":"m1","trainer_id":"t1","product":"PT 20회","paid_amount":1200000,
  "total_sessions":20,"remaining":8,"valid_from":"2026-01-01","valid_until":"2030-12-31","status":"active"}]''';

  String bookingsBody = '[]';

  /// schedule 생략 = 매일 노출(HomeworkScheduleRules.isActiveOn) — 실행 날짜에
  /// 따라 테스트가 흔들리지 않게 한다.
  String homeworksBody = '''
[{"id":"h1","trainer_id":"t1","scope":"individual","target_member_ids":["m1"],
  "items":[{"name":"플랭크"},{"name":"스쿼트"},{"name":"런지"}]}]''';

  int hwChecksStatus = 200;

  /// date는 서버 필터지만 어댑터는 무시하고 "오늘"로 응답한다 — 리포지토리가
  /// 클라이언트에서도 date 일치를 방어하므로 요청에 실린 값을 그대로 되돌려 준다.
  String? hwChecksBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.startsWith('/v1/passes')) return _res(passesBody, 200);
    if (path.startsWith('/v1/bookings')) return _res(bookingsBody, 200);
    if (path.startsWith('/v1/homeworks')) return _res(homeworksBody, 200);
    if (path.startsWith('/v1/hw-checks')) {
      final date = options.queryParameters['date']?.toString() ?? '';
      final body = hwChecksBody ??
          '[{"member_id":"m1","hw_id":"h1","date":"$date","done":[true,true,false]}]';
      return _res(body, hwChecksStatus);
    }
    fail('홈이 예상 밖의 엔드포인트를 호출했다: $path');
  }

  ResponseBody _res(String body, int status) => ResponseBody.fromString(
        status == 200 ? body : '{"error":"boom"}',
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}
