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

// 홈 — 코치가 처방한 세트·횟수가 도메인 경계에서 사라지던 결함(P21 감사 ②).
//
// 서버는 계약대로 `items[].sets`(int) · `items[].reps`(string, "10-12"·"40초"·"각 15회")를
// 내려주고 DTO(HomeworkItemDto)도 그 둘을 받는다. 그런데 리포지토리가 DTO→도메인으로
// 옮길 때 name·note만 실어서, **회원 앱에는 운동 이름만 남았다** — "플랭크"를 몇 세트
// 몇 초 하라는 건지 회원이 알 방법이 앱 안에 없다(배정의 알맹이가 처방인데).
//
// 손실 지점이 매핑 한 곳이라 여기(리포지토리)에서 고정한다. 화면 렌더는
// widgets/homework_checklist_prescription_test.dart가 짝으로 고정한다.
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

  Future<List<HomeworkItem>> loadItems() async {
    final result = await repo.loadHome(memberId: 'm1');
    expect(result, isA<Ok<HomeSummary>>(), reason: '홈 로드가 실패했다: $result');
    return (result as Ok<HomeSummary>).value.homeworkItems;
  }

  test('서버 items[].sets·reps가 도메인 HomeworkItem까지 살아서 온다', () async {
    final items = await loadItems();

    expect(items, hasLength(3));
    expect(items[0].sets, 3, reason: 'DTO는 받았는데 도메인 매핑이 sets를 버렸다');
    expect(items[0].reps, '40초', reason: 'reps는 문자열 표기 그대로여야 한다(계약 v1.3)');
    expect(items[1].sets, 3);
    expect(items[1].reps, '15');
    expect(items[1].note, '무릎 방향 주의', reason: '기존에 살아 있던 note까지 잃으면 안 된다');
  });

  test('reps만 있는 처방(sets 생략)도 그대로 온다 — "걷기 30분"', () async {
    // 어드민 폼은 sets를 비울 수 있고(null), Go는 zero value 0으로 직렬화한다.
    // 둘 다 "세트 개념이 없는 과제"라 표기에서 빠져야 하지만, **reps는 남아야 한다**.
    final items = await loadItems();

    expect(items[2].sets, anyOf(isNull, 0));
    expect(items[2].reps, '30분');
  });

  test('처방 표기 — 있는 것만 조합한다("0×" · "3×" 같은 빈 세그먼트 금지)', () async {
    final items = await loadItems();

    expect(items[0].prescription, '3×40초');
    expect(items[2].prescription, '30분', reason: 'sets가 없으면 "n×"를 붙이지 않는다');
    // 세트만 온 처방은 "3세트"(수업기록 카드와 같은 규약), 아무것도 없으면 null.
    const setsOnly = HomeworkItem(hwId: 'h1', index: 0, name: '버피', sets: 3, done: false);
    const bare = HomeworkItem(hwId: 'h1', index: 0, name: '스트레칭', done: false);
    expect(setsOnly.prescription, '3세트');
    expect(bare.prescription, isNull);
    // 서버가 reps:"" 로 내려주는 경우(Go zero value)도 빈 표기가 새면 안 된다.
    const blankReps = HomeworkItem(hwId: 'h1', index: 0, name: '스트레칭', reps: '  ', done: false);
    expect(blankReps.prescription, isNull);
  });

  test('토글 낙관적 업데이트(copyWith)가 처방을 떨어뜨리지 않는다', () async {
    // done만 바꾸는 copyWith가 sets·reps를 흘리면 체크 한 번에 처방이 사라진다
    // — 첫 렌더에만 보이고 누르면 없어지는, 리포지토리 테스트로는 안 잡히는 경로.
    final items = await loadItems();

    final toggled = items[0].copyWith(done: true);

    expect(toggled.sets, 3);
    expect(toggled.reps, '40초');
    expect(toggled.note, items[0].note);
    expect(toggled.done, isTrue);
  });
}

class _HomeApiAdapter implements HttpClientAdapter {
  String passesBody = '''
[{"id":"p1","member_id":"m1","trainer_id":"t1","product":"PT 20회","paid_amount":1200000,
  "total_sessions":20,"remaining":8,"valid_from":"2026-01-01","valid_until":"2030-12-31","status":"active"}]''';

  /// schedule 생략 = 매일 노출 — 실행 날짜에 따라 흔들리지 않게(hw_checks 테스트와 동일).
  /// sets는 int, reps는 string — 계약 v1.3 그대로.
  String homeworksBody = '''
[{"id":"h1","trainer_id":"t1","scope":"individual","target_member_ids":["m1"],
  "items":[{"name":"플랭크","sets":3,"reps":"40초","note":""},
           {"name":"스쿼트","sets":3,"reps":"15","note":"무릎 방향 주의"},
           {"name":"걷기","sets":0,"reps":"30분","note":""}]}]''';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.startsWith('/v1/passes')) return _res(passesBody);
    if (path.startsWith('/v1/bookings')) return _res('[]');
    if (path.startsWith('/v1/homeworks')) return _res(homeworksBody);
    if (path.startsWith('/v1/hw-checks')) {
      final date = options.queryParameters['date']?.toString() ?? '';
      return _res('[{"member_id":"m1","hw_id":"h1","date":"$date","done":[false,false,false]}]');
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
