import 'package:dio/dio.dart';
import 'package:rise_member/core/api/dto/contract_dto.dart';
import 'package:rise_member/core/api/dto/ledger_dto.dart';
import 'package:rise_member/core/api/dto/payment_dto.dart';

class MyRemoteDataSource {
  const MyRemoteDataSource(this._dio);
  final Dio _dio;

  /// GET /v1/contracts?member= (API계약 v1.1 — 전자계약 목록).
  Future<List<ContractDto>> fetchContracts(String memberId) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/contracts',
      queryParameters: {'member': memberId},
    );
    return (res.data ?? [])
        .map((e) => ContractDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/contracts/{id}/sign (API계약 v1.4 — 회원 자체서명 P27).
  /// sent→signed 전이 · signed_at·signer_ip는 서버가 기록.
  ///
  /// P44: [signaturePng](자필 서명 PNG base64)가 있으면 {"signature_png": …} 바디로
  /// 동봉한다 — 서버는 base64·PNG 매직·크기 상한만 검증한다(결정 6). null이면
  /// **바디 자체를 싣지 않는다**: 바디 없는 sign이 종전 그대로 유효한 wire고,
  /// 서버 decodeJSON(DisallowUnknownFields) 앞에서 빈 오브젝트를 지어 보낼 이유가 없다.
  Future<void> signContract(String contractId, {String? signaturePng}) =>
      _dio.post<void>(
        '/v1/contracts/$contractId/sign',
        data: signaturePng == null ? null : {'signature_png': signaturePng},
      );

  /// GET /v1/payments?member= — 본인 결제·분할 내역.
  ///
  /// 회원 스코프로 열려 있다(서버 `memberScopeID`) — 트레이너와 달리 담당 필터가
  /// 걸리지 않고 본인 것만 그대로 내려온다.
  Future<List<PaymentDto>> fetchPayments(String memberId) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/payments',
      queryParameters: {'member': memberId},
    );
    return (res.data ?? [])
        .map((e) => PaymentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /v1/members/{id}/ledger?pass=.
  Future<List<LedgerDto>> fetchLedger({required String memberId, required String passId}) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/members/$memberId/ledger',
      queryParameters: {'pass': passId},
    );
    return (res.data ?? [])
        .map((e) => LedgerDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/passes/{id}/hold {from,to,reason}.
  Future<void> requestHold({
    required String passId,
    required String from,
    required String to,
    String? reason,
  }) {
    return _dio.post<void>('/v1/passes/$passId/hold', data: {
      'from': from,
      'to': to,
      if (reason != null) 'reason': reason,
    });
  }

  /// POST /v1/passes/{id}/resume.
  Future<void> resumeHold(String passId) => _dio.post<void>('/v1/passes/$passId/resume');

  /// DELETE /v1/me (API계약 v2.11 — 회원탈퇴). 바디 없음.
  ///
  /// 서버가 `decodeJSON`(DisallowUnknownFields)이라 바디를 실으면 그 자체로 400이 되고,
  /// 애초에 실을 것도 없다 — confirm 플래그는 클라이언트가 스스로 세우는 값이라 아무것도
  /// 막지 못한다(확인 절차는 확인 화면의 책임이다).
  ///
  /// 응답은 파싱하되 **던지지 않는다**: 이 호출이 200을 받았다는 것은 계정이 이미 지워졌다는
  /// 뜻이라, 요약 파싱 실패로 예외를 올리면 성공한 탈퇴가 화면에서 실패로 보인다.
  Future<Map<String, dynamic>> deleteAccount() async {
    final res = await _dio.delete<Map<String, dynamic>>('/v1/me');
    return res.data ?? const <String, dynamic>{};
  }

}
