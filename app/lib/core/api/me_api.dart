import 'package:dio/dio.dart';
import 'package:rise_member/core/api/dto/join_dto.dart';

/// GET /v1/me → {uid, role, center_id, member_id?, name?} (API계약_v1.md).
/// name은 계약 v2.2 — 서버가 best-effort로만 채우므로 없을 수 있다.
class MeApi {
  const MeApi(this._dio);
  final Dio _dio;

  Future<MeResponseDto> fetchMe() async {
    final res = await _dio.get<Map<String, dynamic>>('/v1/me');
    return MeResponseDto.fromJson(res.data!);
  }
}
