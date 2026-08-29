import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/dto/center_dto.dart';
import 'package:rise_member/core/network/dio_client.dart';

part 'center_api.g.dart';

/// GET /v1/center → {center_id, policy} (API계약 v1.4 — member에게도 공개).
/// 취소 컷오프·홀딩 상한 등을 하드코딩 문구가 아닌 실정책 값으로 표시하기 위해
/// 세션 로드 후 1회 조회한다(core/policy/center_policy_provider.dart).
class CenterApi {
  const CenterApi(this._dio);
  final Dio _dio;

  Future<CenterResponseDto> fetchCenter() async {
    final res = await _dio.get<Map<String, dynamic>>('/v1/center');
    return CenterResponseDto.fromJson(res.data!);
  }
}

@riverpod
CenterApi centerApi(Ref ref) => CenterApi(ref.watch(dioProvider));
