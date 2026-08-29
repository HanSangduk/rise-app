import 'package:dio/dio.dart';
import 'package:rise_member/core/api/dto/homework_dto.dart';
import 'package:rise_member/core/api/dto/inbody_dto.dart';
import 'package:rise_member/core/api/dto/workout_log_dto.dart';

class RecordsRemoteDataSource {
  const RecordsRemoteDataSource(this._dio);
  final Dio _dio;

  /// GET /v1/inbody?member=.
  Future<List<InbodyDto>> fetchInbody(String memberId) async {
    final res = await _dio.get<List<dynamic>>('/v1/inbody', queryParameters: {'member': memberId});
    return (res.data ?? [])
        .map((e) => InbodyDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/inbody — 회원 본인 수기 입력(민감정보 동의 필수 · date는 YYYY-MM-DD).
  ///
  /// 바디는 계약의 **8필드 그대로**다. `source`를 넣으면 안 된다 — 서버
  /// `decodeJSON`이 `DisallowUnknownFields`라 미지 필드 하나로 전량 400이 되고,
  /// 출처는 서버가 Principal로 판정하는 값이다.
  Future<InbodyDto> createInbody({
    required String memberId,
    required String date,
    required double weight,
    required double smm,
    required double bfm,
    required double pbf,
    required double vfl,
    required double bmr,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>('/v1/inbody', data: {
      'member_id': memberId,
      'date': date,
      'weight': weight,
      'smm': smm,
      'bfm': bfm,
      'pbf': pbf,
      'vfl': vfl,
      'bmr': bmr,
    });
    return InbodyDto.fromJson(res.data ?? const <String, dynamic>{});
  }

  /// DELETE /v1/inbody/{id} — 오입력 정정 경로(수정 대신 삭제 후 재입력).
  Future<void> deleteInbody(String id) async {
    await _dio.delete<void>('/v1/inbody/$id');
  }

  /// GET /v1/workout-logs?member= (API계약 v1.4 — 수업 기록, member=본인 강제).
  Future<List<WorkoutLogDto>> fetchWorkoutLogs(String memberId) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/workout-logs',
      queryParameters: {'member': memberId},
    );
    return (res.data ?? [])
        .map((e) => WorkoutLogDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /v1/hw-checks?member= (v1.1) — Home Work 주간 집계용 전체 체크.
  /// 최근 4주 범위는 클라이언트(HomeworkWeekRules)에서 자른다.
  Future<List<HwCheckDto>> fetchHwChecks(String memberId) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/hw-checks',
      queryParameters: {'member': memberId},
    );
    return (res.data ?? [])
        .map((e) => HwCheckDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
