import 'package:dio/dio.dart';
import 'package:rise_member/core/api/dto/join_dto.dart';

/// dio 호출만 담당(파싱까지). 인증 자체(SMS 발송/검증)는 repository에서 스텁 처리.
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._dio);
  final Dio _dio;

  /// POST /v1/join/match {phone} — 번호 인증 후 자동 매칭 조회.
  /// 백엔드가 phone으로 회원 명단을 조회하므로 바디 필수(빈 바디는 400).
  Future<JoinMatchResponseDto> matchJoin(String phone) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/join/match',
      data: {'phone': phone},
    );
    return JoinMatchResponseDto.fromJson(res.data!);
  }

  /// POST /v1/join/confirm {member_id, confirm, phone} — 이름확인 1탭(P48).
  /// phone은 서버측 재대조용(계약 v1.3): 유출·추측된 member_id만으로는 연결되지 않게
  /// 인증한 번호를 함께 보낸다(Firebase 실연동 시 토큰의 phone_number로 대체 예정).
  Future<void> confirmJoin({required String memberId, required bool confirm, required String phone}) {
    return _dio.post<void>(
      '/v1/join/confirm',
      data: {'member_id': memberId, 'confirm': confirm, 'phone': phone},
    );
  }

  /// POST /v1/join/request {center_id, name, phone} — "우리 센터가 안 보여요" 경로.
  /// center_id를 비우면 서버가 기본 센터로 폴백(백엔드 JoinRequestBody).
  Future<void> requestJoin({required String name, required String phone}) {
    return _dio.post<void>('/v1/join/request', data: {
      'center_id': '',
      'name': name,
      'phone': phone,
    });
  }
}
