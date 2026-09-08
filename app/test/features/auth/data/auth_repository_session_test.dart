import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/me_api.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/features/auth/data/auth_remote_data_source.dart';
import 'package:rise_member/features/auth/data/auth_repository_impl.dart';

// P10 — 세션 복원 경로가 이름을 잃던 회귀.
//
// 앱을 껐다 켜면 세션은 GET /v1/me **하나**로 세워진다(매칭 응답이 없다). 그
// 응답에 이름이 없던 시절엔 memberName이 항상 ''이라, 같은 홈 헤더가 최초
// 로그인 땐 "김민지 님", 재실행 뒤엔 센터명(AppConfig.centerFullName 폴백)으로
// 갈렸다 — 같은 화면이 실행 시점에 따라 다르게 보였다(실기기 점검에서 발견).
//
// 계약 v2.2가 name을 추가했지만 **best-effort**다(서버가 이름 조회에 실패해도
// /v1/me는 성공한다). 그래서 두 방향을 함께 고정한다:
//   · name 있음 → 세션에 그대로 실린다(헤더가 "김민지 님"을 쓴다)
//   · name 없음 → ''로 남는다(헤더가 기존 센터명 폴백으로 떨어진다)
void main() {
  late _MeAdapter adapter;
  late AuthRepositoryImpl repo;

  setUp(() {
    adapter = _MeAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    repo = AuthRepositoryImpl(AuthRemoteDataSource(dio), MeApi(dio));
  });

  Future<AppSession> loadOk() async {
    final result = await repo.loadSession();
    expect(result, isA<Ok<AppSession>>(), reason: '세션 복원이 실패했다: $result');
    return (result as Ok<AppSession>).value;
  }

  group('loadSession — /v1/me의 name을 세션에 싣는다 (계약 v2.2)', () {
    test('name이 오면 memberName에 담긴다', () async {
      adapter.body =
          '{"uid":"u1","role":"member","center_id":"c1","member_id":"m1","name":"김민지"}';

      final session = await loadOk();

      expect(session.memberName, '김민지');
      // 나머지 필드는 종전 그대로.
      expect(session.uid, 'u1');
      expect(session.role, 'member');
      expect(session.centerId, 'c1');
      expect(session.memberId, 'm1');
    });

    test('name 키가 없으면 ""— 헤더의 센터명 폴백이 살아 있어야 한다', () async {
      // 구버전 서버이거나 서버가 이름 조회에 실패한 경우. 계약상 정상 응답이다.
      adapter.body =
          '{"uid":"u1","role":"member","center_id":"c1","member_id":"m1"}';

      expect((await loadOk()).memberName, isEmpty);
    });

    test('name: null도 ""로 (계약은 omitempty지만 방어)', () async {
      adapter.body =
          '{"uid":"u1","role":"member","center_id":"c1","member_id":"m1","name":null}';

      expect((await loadOk()).memberName, isEmpty);
    });

    test('공백뿐인 name은 ""로 정규화 — "  님"이 렌더되면 안 된다', () async {
      // 헤더도 CoachLabel로 한 번 더 거르지만, 세션에 공백을 실어 두면 이 값을
      // 읽는 다른 화면이 같은 실수를 되풀이한다. 경계에서 끝낸다.
      adapter.body =
          '{"uid":"u1","role":"member","center_id":"c1","member_id":"m1","name":"   "}';

      expect((await loadOk()).memberName, isEmpty);
    });

    test('앞뒤 공백이 낀 이름은 trim해서 담는다', () async {
      adapter.body =
          '{"uid":"u1","role":"member","center_id":"c1","member_id":"m1","name":" 김민지 "}';

      expect((await loadOk()).memberName, '김민지');
    });

    test('member_id가 없으면 이름이 와도 미연결 — 기존 분기를 흔들지 않는다', () async {
      // "아직 연결 전"은 네트워크 실패와 다른 결론(온보딩 vs 재시도)으로 이어진다.
      // 이름이 생겼다고 이 판정이 바뀌면 미연결 계정이 홈으로 새어 들어간다.
      adapter.body = '{"uid":"u1","role":"member","center_id":"c1","name":"김민지"}';

      final result = await repo.loadSession();

      expect(result, isA<Err<AppSession>>());
      expect((result as Err<AppSession>).failure, isA<MemberNotLinkedFailure>());
    });

    test('서버 오류는 종전대로 실패 — 이름 파싱이 성공 판정을 바꾸지 않는다', () async {
      adapter
        ..status = 500
        ..body = '{"error":"me down"}';

      final result = await repo.loadSession();

      expect(result, isA<Err<AppSession>>());
      expect((result as Err<AppSession>).failure, isA<NetworkFailure>());
    });
  });
}

/// GET /v1/me 응답 본문만 갈아 끼우는 최소 어댑터 — 이 파일의 관심사는
/// "서버가 준 JSON이 세션의 어떤 값이 되는가" 하나다.
class _MeAdapter implements HttpClientAdapter {
  String body = '{"uid":"u1","role":"member","center_id":"c1","member_id":"m1"}';
  int status = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, '/v1/me');
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
