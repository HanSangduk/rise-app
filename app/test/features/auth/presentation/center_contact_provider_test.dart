import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/config/app_config.dart';
import 'package:rise_member/core/network/dio_client.dart';
import 'package:rise_member/features/auth/presentation/center_contact_provider.dart';

// 센터 상호의 출처 단일화(P56 L10).
//
// 어드민 "센터 신원" 폼은 "회원 앱에 이 이름으로 뜬다"고 약속했는데, 앱은 그 값을 어디서도
// 읽지 않았다 — 상호는 로컬 상수 '(강남)'까지 박혀 있었고, 대기실의 전화·주소는 사업자 정보
// (GET /v1/public/business)에서 읽어 어드민이 저장한 센터 전화는 어디에도 나오지 않았다.
// 이 테스트는 ① 경로가 GET /v1/public/center 하나라는 것 ② 서버 상호가 있으면 그것, 없으면
// 임시 상수라는 폴백 규칙 ③ 실패가 화면을 막지 않는다는 것 ④ 동기 표시명 provider가 로딩
// 중에도 임시 상수를 바로 내고 서버 값이 오면 갈아탄다는 것을 못 박는다.
void main() {
  late _CannedAdapter adapter;
  late ProviderContainer container;

  setUp(() {
    adapter = _CannedAdapter();
    container = ProviderContainer.test(
      overrides: [dioProvider.overrideWithValue(_dio(adapter))],
    );
  });

  group('centerContactProvider', () {
    test('GET /v1/public/center 3칸을 그대로 읽는다 — 사업자 정보 경로가 아니다', () async {
      adapter.body = {'name': '라이즈 컨디셔닝 센터', 'phone': '02-555-0001', 'address': '서울 강남구 1'};

      final contact = await container.read(centerContactProvider(null).future);

      expect(adapter.paths, ['/v1/public/center']);
      expect(contact.name, '라이즈 컨디셔닝 센터');
      expect(contact.phone, '02-555-0001');
      expect(contact.address, '서울 강남구 1');
      expect(contact.displayName, '라이즈 컨디셔닝 센터');
      expect(contact.isEmpty, isFalse);
    });

    test('미등록(빈 3칸)이면 표시명은 임시 상수 — 빈 문자열을 화면에 찍지 않는다', () async {
      adapter.body = {'name': '', 'phone': '', 'address': ''};

      final contact = await container.read(centerContactProvider(null).future);

      expect(contact.isEmpty, isTrue);
      expect(contact.hasPhone, isFalse);
      expect(contact.displayName, AppConfig.centerFullName);
    });

    test('공백뿐인 상호도 미등록과 같다 — " "를 상호로 믿지 않는다', () async {
      adapter.body = {'name': '   ', 'phone': '', 'address': ''};

      final contact = await container.read(centerContactProvider(null).future);

      expect(contact.hasName, isFalse);
      expect(contact.displayName, AppConfig.centerFullName);
    });

    // P69 H3 — family: 요청한 센터가 있으면 `?center=`로 그 센터를 묻는다(v2.33·v2.34).
    test('centerId를 주면 ?center=로 그 센터를 묻는다', () async {
      adapter.body = {'name': '라이즈 강남 2호점', 'phone': '', 'address': ''};

      final contact = await container.read(centerContactProvider('gangnam-2').future);

      expect(adapter.paths, ['/v1/public/center']);
      expect(adapter.queries, [{'center': 'gangnam-2'}]);
      expect(contact.name, '라이즈 강남 2호점');
    });

    test('null·빈 문자열은 파라미터 없이 기본 센터 — 홈 헤더의 인스턴스와 같다', () async {
      adapter.body = {'name': '', 'phone': '', 'address': ''};
      await container.read(centerContactProvider(null).future);
      await container.read(centerContactProvider('').future);
      expect(adapter.queries, [<String, dynamic>{}, <String, dynamic>{}]);
    });

    // P69 M2 — 계약 v2.34 open_hour·close_hour. "마지막 슬롯 시작"이라 끝 표기는 +1.
    test('open_hour·close_hour를 읽고 close+1로 표기한다', () async {
      adapter.body = {'name': '라이즈', 'phone': '', 'address': '', 'open_hour': 9, 'close_hour': 21};

      final contact = await container.read(centerContactProvider(null).future);

      expect(contact.openHour, 9);
      expect(contact.closeHour, 21);
      expect(contact.hasHours, isTrue);
      expect(contact.hoursLabel, '09:00–22:00');
    });

    test('hours 키가 없으면(구서버·미설정) null — 9·21 기본값을 지어내지 않는다', () async {
      adapter.body = {'name': '라이즈', 'phone': '', 'address': ''};

      final contact = await container.read(centerContactProvider(null).future);

      expect(contact.openHour, isNull);
      expect(contact.hasHours, isFalse);
      expect(contact.hoursLabel, '');
    });

    test('말이 안 되는 값(한쪽만·역순·범위 밖·문자열)은 hasHours=false', () {
      expect(const CenterContact(openHour: 9).hasHours, isFalse);
      expect(const CenterContact(openHour: 22, closeHour: 9).hasHours, isFalse);
      expect(const CenterContact(openHour: -1, closeHour: 9).hasHours, isFalse);
      expect(const CenterContact(openHour: 9, closeHour: 24).hasHours, isFalse);
      expect(const CenterContact(openHour: 0, closeHour: 23).hoursLabel, '00:00–24:00');
    });

    test('문자열로 온 시각은 무시한다 — 억지로 해석하지 않는다', () async {
      adapter.body = {'name': '라이즈', 'phone': '', 'address': '', 'open_hour': '9', 'close_hour': '21'};
      final contact = await container.read(centerContactProvider(null).future);
      expect(contact.hasHours, isFalse);
    });

    test('서버 5xx는 빈 값으로 접힌다 — 상호 한 줄이 대기실·홈을 막지 않는다', () async {
      adapter.status = 503;

      final contact = await container.read(centerContactProvider(null).future);

      expect(contact.isEmpty, isTrue);
      expect(contact.displayName, AppConfig.centerFullName);
      // 재시도 없음 — 백오프 타이머가 테스트에 남지 않는다(P46 규약).
      expect(adapter.paths.length, 1);
    });
  });

  group('centerDisplayNameProvider', () {
    test('로딩 중엔 임시 상수, 서버 값이 오면 그 자리에서 바뀐다', () async {
      adapter.body = {'name': '라이즈 컨디셔닝 센터', 'phone': '', 'address': ''};
      // autoDispose provider가 읽기 직후 폐기되지 않게 붙들어 둔다.
      final sub = container.listen(centerDisplayNameProvider, (_, __) {});

      expect(sub.read(), AppConfig.centerFullName);

      await container.read(centerContactProvider(null).future);

      expect(sub.read(), '라이즈 컨디셔닝 센터');
      sub.close();
    });

    test('실패해도 임시 상수 — 예외가 화면으로 새지 않는다', () async {
      adapter.status = 500;
      final sub = container.listen(centerDisplayNameProvider, (_, __) {});

      await container.read(centerContactProvider(null).future);

      expect(sub.read(), AppConfig.centerFullName);
      sub.close();
    });
  });

  test('임시 상수에 지점명이 없다 — 검증 못 한 사실("강남")을 회원에게 찍지 않는다', () {
    expect(AppConfig.centerFullName, isNot(contains('(')));
    expect(AppConfig.centerFullName, '라이즈 컨디셔닝 센터');
  });
}

Dio _dio(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = adapter;
  return dio;
}

/// 경로를 기록하고 정해진 JSON 한 벌(또는 정해진 상태 코드)로 응답하는 어댑터.
class _CannedAdapter implements HttpClientAdapter {
  final paths = <String>[];
  final queries = <Map<String, dynamic>>[];
  Map<String, dynamic> body = const {};
  int status = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    queries.add(options.uri.queryParameters);
    return ResponseBody.fromString(
      jsonEncode(status == 200 ? body : {'error': 'x'}),
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}
