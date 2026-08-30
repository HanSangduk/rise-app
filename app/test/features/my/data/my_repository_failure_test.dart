import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/api/passes_api.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/my/data/my_remote_data_source.dart';
import 'package:rise_member/features/my/data/my_repository_impl.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

// 마이 탭 — "조회 실패를 빈 데이터로 위장"하는 계열 결함.
//
// 마이 탭 로드는 4개 요청의 합성이고, 부가 요청(원장·계약·동의)은 하나가 실패해도
// 탭 전체를 죽이지 않는 best-effort다. 그 자체는 옳다 — 문제는 **실패했다는 사실이
// 어디에도 남지 않아** 화면이 확정적인 거짓을 말했다는 것이다:
//
//   · 동의 조회 실패 → 하드코딩 기본값(false/false)이 "미동의"로 렌더되고, 회원이
//     시트를 열어 토글을 **건드리지 않은 채** 저장하면 PUT이 그 false를 그대로
//     보낸다. 서버는 sensitive true→false를 철회로 보고 revoked_at을 남기며
//     (normalizeConsentTransition), 그 순간 인바디·체형사진 저장이 잠긴다
//     (Consent.SensitiveConsentValid). 앱에서 법적 기록을 남기는 유일한 경로다.
//   · 원장 조회 실패 → 빈 목록이 "아직 내역이 없어요"가 되어, 수십 회 이력이 있는
//     회원에게 이력 0이라고 말한다.
//
// 계약 목록은 이미 contractsFailed로 정확히 이 문제를 피하고 있었다 — 이 파일은
// 같은 규약이 동의·원장에도 적용되는지, 그리고 **성공했을 때는 서지 않는지**(플래그를
// 늘 세우는 구현으로 도망가지 못하게) 양방향으로 고정한다.
void main() {
  late _MyApiAdapter adapter;
  late MyRepositoryImpl repo;

  setUp(() {
    adapter = _MyApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = adapter;
    repo = MyRepositoryImpl(
      PassesApi(dio),
      () async => const <String, StaffDto>{}, // 스태프 맵은 이 파일의 관심사가 아니다
      MyRemoteDataSource(dio),
      MemberApi(dio),
    );
  });

  Future<MySummary> loadOk() async {
    final result = await repo.load('m1');
    // 부분 실패는 탭을 죽이지 않는다 — 그 전제가 깨지면 아래 플래그 검증은 무의미하다.
    expect(result, isA<Ok<MySummary>>(), reason: '부분 실패가 마이 탭 전체를 무너뜨렸다: $result');
    return (result as Ok<MySummary>).value;
  }

  group('동의 조회 실패 — "미동의"로 위장하지 않는다', () {
    test('GET /v1/members 5xx → consentFailed=true (기본값 false/false는 "모름"이다)', () async {
      adapter.profileStatus = 500;

      final summary = await loadOk();

      expect(summary.consentFailed, isTrue,
          reason: '실패가 플래그로 남지 않으면 화면이 "동의 필요"라고 확정적으로 거짓말한다');
      // 나머지 마이 탭 정보는 그대로 — best-effort 전제가 살아 있어야 한다.
      expect(summary.passes, hasLength(2));
      expect(summary.contractsFailed, isFalse);
    });

    test('GET /v1/members 4xx도 같다 — 상태코드로 갈리지 않는다', () async {
      adapter.profileStatus = 403;

      expect((await loadOk()).consentFailed, isTrue);
    });

    test('빈 배열 응답(회원 레코드 없음)도 "모름" — StateError를 성공으로 세지 않는다', () async {
      // MemberApi.fetchMyProfile은 빈 목록에 StateError를 던진다. 이것도 동의 상태를
      // 모르는 상태이므로 저장을 열어 주면 안 된다.
      adapter.profileBody = '[]';

      expect((await loadOk()).consentFailed, isTrue);
    });

    test('조회 성공이면 consentFailed=false + 서버 값 그대로 — 늘 막는 구현은 오답', () async {
      // 이 케이스가 없으면 "consentFailed = true"를 무조건 세워도 테스트가 통과한다.
      // 그러면 아무도 동의를 켜거나 철회할 수 없게 된다(반대 방향의 고장).
      adapter.profileBody = '[{"id":"m1","name":"람","phone":"01000000000",'
          '"consent":{"general":true,"sensitive":true,"signed_at":"2026-01-02T03:04:05Z"}}]';

      final summary = await loadOk();

      expect(summary.consentFailed, isFalse);
      expect(summary.consent.general, isTrue);
      expect(summary.consent.sensitive, isTrue);
      expect(summary.consent.signedAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('실제 미동의(consent false/false)와 조회 실패는 서로 다른 상태다', () async {
      adapter.profileBody = '[{"id":"m1","name":"람","phone":"01000000000",'
          '"consent":{"general":false,"sensitive":false}}]';

      final summary = await loadOk();

      expect(summary.consent.sensitive, isFalse);
      // 값은 같아도 플래그로 갈린다 — 이쪽은 저장이 열려야 하는 정상 상태.
      expect(summary.consentFailed, isFalse);
    });

    test('consent 키 자체가 없으면 실패가 아니다 — 저장이 영원히 막히면 안 된다', () async {
      // 서버 Member.Consent는 값 타입(omitempty 없음)이라 정상 응답엔 항상 실려 온다.
      // 그래도 "키 없음 = 모름"으로 기울이면, 그런 서버를 만난 회원은 다시 불러와도
      // 플래그가 안 풀려 **영원히 동의할 수 없다**. 미동의 기본값으로 둔다.
      adapter.profileBody = '[{"id":"m1","name":"람","phone":"01000000000"}]';

      final summary = await loadOk();

      expect(summary.consentFailed, isFalse);
      expect(summary.consent.sensitive, isFalse);
    });
  });

  group('원장 조회 실패 — "아직 내역이 없어요"로 위장하지 않는다', () {
    test('패스 하나만 실패하면 그 패스만 표시된다', () async {
      adapter.failingLedgerPassIds.add('p2');

      final summary = await loadOk();

      expect(summary.ledgerFailedFor('p2'), isTrue);
      expect(summary.ledgerByPass['p2'], isEmpty);
      // 나머지 패스의 원장은 멀쩡하다 — 실패는 패스 단위로만 번진다.
      expect(summary.ledgerFailedFor('p1'), isFalse);
      expect(summary.ledgerByPass['p1'], hasLength(2));
    });

    test('두 패스 모두 실패하면 둘 다 표시', () async {
      adapter.failingLedgerPassIds.addAll(['p1', 'p2']);

      final summary = await loadOk();

      expect(summary.ledgerFailedPassIds, {'p1', 'p2'});
    });

    test('진짜 0건은 실패가 아니다 — "없음"과 "확인 실패"를 구분한다', () async {
      // 이 케이스가 없으면 "빈 목록이면 실패"로 뭉개도 통과한다. 신규 발급 직후
      // 원장이 정말 비어 있는 회원에게 붉은 실패 문구를 띄우게 된다.
      adapter.ledgerBody = '[]';

      final summary = await loadOk();

      expect(summary.ledgerFailedPassIds, isEmpty);
      expect(summary.ledgerByPass['p1'], isEmpty);
    });

    test('원장 실패가 동의·계약 플래그로 번지지 않는다', () async {
      adapter.failingLedgerPassIds.add('p1');

      final summary = await loadOk();

      expect(summary.consentFailed, isFalse);
      expect(summary.contractsFailed, isFalse);
    });
  });

  group('계약 조회 실패 — 이미 있던 규약의 회귀 고정', () {
    test('GET /v1/contracts 5xx → contractsFailed=true, 나머지는 그대로', () async {
      adapter.contractsStatus = 500;

      final summary = await loadOk();

      expect(summary.contractsFailed, isTrue);
      expect(summary.contracts, isEmpty);
      expect(summary.consentFailed, isFalse);
      expect(summary.ledgerFailedPassIds, isEmpty);
    });
  });

  group('계약 문서 스냅샷(v2.18, P39) — DTO→도메인 스레딩에서 유실되지 않는다', () {
    test('template_version·vars·first_sent_at이 ContractItem까지 온다', () async {
      // 종전 매핑은 first_sent_at을 DTO까지 받고 버렸다 — {{계약 체결일}}의 미서명
      // 폴백(:781)이 여기서 끊기면 시트는 스냅샷이 있어도 본문을 못 그린다.
      adapter.contractsBody =
          '[{"id":"c1","member_id":"m1","pass_id":"p1","product":"PT 20회",'
          '"paid_amount":1200000,"status":"sent","first_sent_at":"2026-08-20T00:30:00Z",'
          '"template_version":"pt-v1","vars":{"회원명":"람"}}]';

      final summary = await loadOk();
      final c = summary.contracts.single;

      expect(c.templateVersion, 'pt-v1');
      expect(c.vars, {'회원명': '람'});
      expect(c.firstSentAt, DateTime.utc(2026, 8, 20, 0, 30));
      expect(c.hasDocumentSnapshot, isTrue);
    });

    test('스탬프 전(필드 부재) → 스냅샷 없음 판정 — 요약 고지 경로', () async {
      adapter.contractsBody =
          '[{"id":"c1","member_id":"m1","pass_id":"p1","product":"PT 20회",'
          '"paid_amount":1200000,"status":"sent"}]';

      final summary = await loadOk();

      expect(summary.contracts.single.hasDocumentSnapshot, isFalse);
      expect(summary.contractsFailed, isFalse);
    });
  });

  group('체결 증적(P44) — 서명 이미지·해시·IP가 ContractItem까지 온다', () {
    test('signature_png/signature_sha256/signer_ip/sha256 스레딩', () async {
      adapter.contractsBody =
          '[{"id":"c1","member_id":"m1","pass_id":"p1","product":"PT 20회",'
          '"paid_amount":1200000,"status":"signed","signed_at":"2026-08-29T05:03:00Z",'
          '"signer_ip":"211.36.132.7","sha256":"a1b2c3",'
          '"signature_png":"aGk=","signature_sha256":"f6e5d4"}]';

      final summary = await loadOk();
      final c = summary.contracts.single;

      expect(c.signaturePng, 'aGk=');
      expect(c.signatureSha256, 'f6e5d4');
      expect(c.hasSignatureImage, isTrue);
      expect(c.signerIp, '211.36.132.7');
      expect(c.sha256, 'a1b2c3');
    });

    test('빈 문자열 IP·해시는 null로 접힌다 — 빈 값 행을 화면에 만들지 않는다(pdfPath 규약)', () async {
      adapter.contractsBody =
          '[{"id":"c1","member_id":"m1","pass_id":"p1","product":"PT 20회",'
          '"paid_amount":1200000,"status":"signed","signer_ip":"","sha256":"",'
          '"signature_png":"","signature_sha256":""}]';

      final summary = await loadOk();
      final c = summary.contracts.single;

      expect(c.signerIp, isNull);
      expect(c.sha256, isNull);
      expect(c.signaturePng, '');
      expect(c.hasSignatureImage, isFalse);
    });
  });
}

/// 마이 탭 로드가 때리는 4개 엔드포인트를 경로로 갈라 응답하는 최소 어댑터.
/// 관심사는 하나다: **어떤 요청이 실패했을 때 MySummary의 어떤 플래그가 서는가.**
class _MyApiAdapter implements HttpClientAdapter {
  String passesBody = '''
[
  {"id":"p1","member_id":"m1","trainer_id":"t1","product":"PT 20회","paid_amount":1200000,
   "total_sessions":20,"remaining":8,"valid_from":"2026-01-01","valid_until":"2030-12-31","status":"active"},
  {"id":"p2","member_id":"m1","trainer_id":"t1","product":"PT 10회","paid_amount":700000,
   "total_sessions":10,"remaining":0,"valid_from":"2025-01-01","valid_until":"2025-12-31","status":"expired"}
]''';

  String ledgerBody = '''
[
  {"id":"l1","pass_id":"p1","member_id":"m1","delta":-1,"reason":"complete","at":"2026-08-01T10:00:00Z"},
  {"id":"l2","pass_id":"p1","member_id":"m1","delta":20,"reason":"issue","at":"2026-01-01T10:00:00Z"}
]''';

  String contractsBody = '[]';

  String profileBody = '[{"id":"m1","name":"람","phone":"01000000000",'
      '"consent":{"general":true,"sensitive":true}}]';

  int passesStatus = 200;
  int contractsStatus = 200;
  int profileStatus = 200;

  /// 원장은 패스별로 따로 조회한다 — 어느 패스의 조회가 죽었는지까지 재현한다.
  final Set<String> failingLedgerPassIds = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    // 순서 주의: "/v1/members/{id}/ledger"가 "/v1/members" 접두사에도 걸린다.
    if (path.contains('/ledger')) {
      final passId = options.queryParameters['pass']?.toString() ?? '';
      if (failingLedgerPassIds.contains(passId)) return _res('{"error":"ledger down"}', 500);
      return _res(ledgerBody, 200);
    }
    if (path.startsWith('/v1/passes')) return _res(passesBody, passesStatus);
    if (path.startsWith('/v1/contracts')) return _res(contractsBody, contractsStatus);
    if (path.startsWith('/v1/members')) return _res(profileBody, profileStatus);
    fail('마이 탭이 예상 밖의 엔드포인트를 호출했다: $path');
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
