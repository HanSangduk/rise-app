import 'package:dio/dio.dart';
import 'package:rise_member/core/api/dto/body_photo_dto.dart';

class BodyCheckRemoteDataSource {
  const BodyCheckRemoteDataSource(this._dio);
  final Dio _dio;

  /// GET /v1/body-photos?member=.
  Future<List<BodyPhotoDto>> fetchPhotos(String memberId) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/body-photos',
      queryParameters: {'member': memberId},
    );
    return (res.data ?? [])
        .map((e) => BodyPhotoDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/body-photos (동의 검증 P8은 서버 최종 확인) — JSON 바디만 수신
  /// (백엔드 BodyPhotoCreateRequest: member_id/pose/direction/date/storage_path/blurred).
  ///
  /// 이미지 바이너리는 이 엔드포인트로 보내지 않는다 — 원본은 **Firebase Storage에
  /// 먼저 올리고**([BodyPhotoUploader]) 그 버킷 내부 경로만 [storagePath]로 싣는다.
  /// 서버는 경로만 들고 있다가 열람 시점에 서명 URL을 발급하면 되고, 백엔드가
  /// 수십 MB짜리 멀티파트를 중계할 필요가 없다.
  Future<BodyPhotoDto> uploadPhoto({
    required String memberId,
    required String pose,
    required String direction,
    required String date,
    required String storagePath,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>('/v1/body-photos', data: {
      'member_id': memberId,
      'pose': pose,
      'direction': direction,
      'date': date,
      'storage_path': storagePath,
      // 배경 인물 블러는 아직 온디바이스 감지가 없다 — 서버/코치 도구가 판정한다.
      'blurred': false,
    });
    return BodyPhotoDto.fromJson(res.data!);
  }

  /// DELETE /v1/body-photos/{id}.
  ///
  /// **회원이 부르면 즉시 완전 파기다** — 유예도 복원도 없다. 배포된
  /// 개인정보처리방침이 정보주체의 삭제 요청에 "지체 없이 파기"를 약속하고 있어서,
  /// 30일 유예는 그 약속과 정면으로 어긋난다(스태프가 지울 때만 유예가 붙는다 —
  /// 그쪽은 운영 오조작이라 되돌릴 시간이 필요하다).
  Future<void> deletePhoto(String id) async {
    await _dio.delete<void>('/v1/body-photos/$id');
  }
}
