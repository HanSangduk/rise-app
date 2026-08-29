import 'package:dio/dio.dart';
import 'package:rise_member/core/api/dto/homework_dto.dart';
import 'package:rise_member/core/network/api_config.dart';

class HomeRemoteDataSource {
  const HomeRemoteDataSource(this._dio);
  final Dio _dio;

  /// GET /v1/homeworks?member= (API계약_v1.md — 부상 자동 제외는 서버 책임 P39).
  Future<List<HomeworkDto>> fetchHomeworks(String memberId) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/homeworks',
      queryParameters: {'member': memberId},
    );
    return (res.data ?? [])
        .map((e) => HomeworkDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// API계약 v1.1로 확정됨: `GET /v1/hw-checks?hw_id=&member=` (어드민·앱 가정 승인).
  /// 오늘 체크 상태를 미리 보여주기 위한 조회(date=는 클라이언트에서도 방어).
  Future<List<HwCheckDto>> fetchHwChecks({required String memberId, required String date}) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/hw-checks',
      queryParameters: {'member': memberId, 'date': date},
    );
    return (res.data ?? [])
        .map((e) => HwCheckDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/hw-checks {hw_id, date, done:[...]} — 계약 그대로(member_id는 인증 토큰에서 서버가 채움).
  Future<void> submitHwCheck({
    required String hwId,
    required String date,
    required List<bool> done,
  }) {
    return _dio.post<void>('/v1/hw-checks', data: {
      'hw_id': hwId,
      'date': date,
      'done': done,
    });
  }

  /// POST /v1/checkin {source:"self_qr", qr_token} — qr_token 필수(booking_id는
  /// 서버가 무시하고 ±30분 시간창 내 내 예약을 스스로 찾는다, P44).
  ///
  /// [scannedToken]은 데스크 QR에서 실제로 읽은 원문이며 **1순위**다.
  /// 비어 있을 때만 [ApiConfig.checkinQrToken](빌드 시 심은 상수)으로 떨어진다 —
  /// 카메라가 없는 에뮬레이터·로컬 백엔드 개발이 스캐너 때문에 막히지 않게 남긴
  /// dev 폴백이며, 운영에서는 이 경로를 타지 않는다(스캔 실패면 화면이 먼저 멈춘다).
  Future<void> selfCheckIn({String? scannedToken}) {
    final token = (scannedToken != null && scannedToken.trim().isNotEmpty)
        ? scannedToken.trim()
        : ApiConfig.checkinQrToken;
    return _dio.post<void>('/v1/checkin', data: {
      'source': 'self_qr',
      'qr_token': token,
    });
  }
}
