import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';

abstract interface class BodyCheckRepository {
  /// GET /v1/body-photos?member=.
  Future<Result<List<BodyPhotoEntry>>> fetchPhotos(String memberId);

  /// POST /v1/body-photos — 동의 검증(P8)은 서버가 최종 확인하지만,
  /// 클라이언트도 촬영 전 동의 상태를 먼저 확인해 UX를 막지 않는다.
  ///
  /// [storagePath]는 **이미 Firebase Storage에 올라간** 원본의 버킷 내부 경로다
  /// (BodyPhotoStoragePath 규칙). 순서가 바뀌면 서버에 죽은 경로가 남는다.
  Future<Result<BodyPhotoEntry>> uploadPhoto({
    required String memberId,
    required String pose,
    required BodyDirection direction,
    required DateTime date,
    required String storagePath,
  });

  /// DELETE /v1/body-photos/{id} — **회원 본인이 부르면 즉시 완전 파기**(복원 없음).
  ///
  /// 성공하면 로컬 바이트 캐시도 함께 비워야 한다. 안 그러면 "완전히 지워졌다"고
  /// 들은 사진이 목록 갱신 실패 시 화면에 그대로 뜬다 — 회원 입장에선 삭제가
  /// 거짓말이 된다.
  Future<Result<void>> deletePhoto({required String id, String? storagePath});
}
