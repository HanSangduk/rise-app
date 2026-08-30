import 'package:dio/dio.dart';
import 'package:rise_member/core/api/dto/consult_request_dto.dart';

/// 재등록/상담 요청 API(계약 v2.20, P42) — 회원 경로 두 개뿐이다.
/// done 처리는 어드민 몫이라 앱에는 없다.
class ConsultApi {
  const ConsultApi(this._dio);
  final Dio _dio;

  /// GET /v1/consult-requests — 회원은 자기 요청만 온다(서버 스코프).
  Future<List<ConsultRequestDto>> fetchMine() async {
    final res = await _dio.get<List<dynamic>>('/v1/consult-requests');
    return (res.data ?? [])
        .map((e) => ConsultRequestDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/consult-requests {kind, note} — pending 중복이면 서버가 409를 준다
  /// (문구는 서버 것을 그대로 띄운다 — hold 시트와 같은 규약).
  Future<ConsultRequestDto> create({
    required String kind,
    String note = '',
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/consult-requests',
      data: {'kind': kind, 'note': note},
    );
    return ConsultRequestDto.fromJson(res.data!);
  }
}
