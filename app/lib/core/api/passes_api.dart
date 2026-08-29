import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/dto/pass_dto.dart';
import 'package:rise_member/core/network/dio_client.dart';

part 'passes_api.g.dart';

/// API계약 v1.1로 확정됨: `GET /v1/passes?member=` (앱 가정 승인 — 내/특정
/// 회원 회원권 목록). 백엔드에는 이 라우트만 존재한다.
/// 홈(패스 스위처)과 마이(회원권 목록)가 이 API를 공유한다.
class PassesApi {
  const PassesApi(this._dio);
  final Dio _dio;

  Future<List<PassDto>> fetchMyPasses(String memberId) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/passes',
      queryParameters: {'member': memberId},
    );
    return (res.data ?? [])
        .map((e) => PassDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

@riverpod
PassesApi passesApi(Ref ref) => PassesApi(ref.watch(dioProvider));
