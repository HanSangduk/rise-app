import 'package:rise_member/core/network/api_result_guard.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/bodycheck/data/body_check_remote_data_source.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';
import 'package:rise_member/features/bodycheck/domain/body_check_repository.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';

class BodyCheckRepositoryImpl implements BodyCheckRepository {
  const BodyCheckRepositoryImpl(this._remote, this._loader);
  final BodyCheckRemoteDataSource _remote;

  /// 삭제가 성공하면 이 사진의 바이트도 함께 비운다 — 캐시에 남으면 "완전히
  /// 지워졌다"고 들은 사진이 다시 그려진다.
  final BodyPhotoLoader _loader;

  @override
  Future<Result<List<BodyPhotoEntry>>> fetchPhotos(String memberId) {
    return guardApi(() async {
      final dtos = await _remote.fetchPhotos(memberId);
      // 날짜는 tryParse + 그 건만 스킵 — 인바디·수업 기록·hw-check와 **같은 규칙**
      // (records_repository_impl). 여기만 DateTime.parse(throw)였다: 형식이 깨진 레코드
      // 하나가 guardApi에서 Err로 접혀 회원의 체형사진 타임라인 **전체**(수개월 치)를
      // "불러오지 못했어요"로 숨겼다(P73). 서버 CreateBodyPhoto는 v2.37부터 date 형식을
      // 검증하지만, 그 전에 들어간 레코드·수기 편집·마이그레이션은 여기서 막는 수밖에 없다.
      final out = <BodyPhotoEntry>[];
      for (final d in dtos) {
        final date = DateTime.tryParse(d.date);
        if (date == null) continue;
        out.add(BodyPhotoEntry(
          id: d.id,
          memberId: d.memberId,
          pose: d.pose, // key 원문 보존(미지 포즈도 사라지면 안 된다)
          direction: BodyDirection.values.firstWhere(
            (e) => e.wireValue == d.direction,
            orElse: () => BodyDirection.front,
          ),
          date: date,
          storagePath: d.storagePath,
          blurred: d.blurred,
        ));
      }
      return out;
    });
  }

  @override
  Future<Result<BodyPhotoEntry>> uploadPhoto({
    required String memberId,
    required String pose,
    required BodyDirection direction,
    required DateTime date,
    required String storagePath,
  }) {
    return guardApi(() async {
      final dto = await _remote.uploadPhoto(
        memberId: memberId,
        pose: pose,
        direction: direction.wireValue,
        date: DateFmt.isoDate(date),
        storagePath: storagePath,
      );
      return BodyPhotoEntry(
        id: dto.id,
        memberId: dto.memberId,
        pose: pose,
        direction: direction,
        date: date,
        storagePath: dto.storagePath,
        blurred: dto.blurred,
      );
    });
  }

  @override
  Future<Result<void>> deletePhoto({required String id, String? storagePath}) {
    return guardApi(() async {
      await _remote.deletePhoto(id);
      // **서버가 지운 뒤에 비운다.** 먼저 비우면 요청이 실패했을 때 멀쩡한 사진의
      // 캐시만 날려 다음 조회가 네트워크를 다시 타고, 최악에는 파기되지 않은 사진을
      // "지워진 것처럼" 보이게 만든다.
      if (storagePath != null && storagePath.isNotEmpty) {
        _loader.evict(storagePath);
      }
    });
  }
}
