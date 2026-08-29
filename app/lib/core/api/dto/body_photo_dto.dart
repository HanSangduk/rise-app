import 'package:freezed_annotation/freezed_annotation.dart';

part 'body_photo_dto.freezed.dart';
part 'body_photo_dto.g.dart';

/// API계약_v1.md — BodyPhoto 엔티티(체형 분석 사진).
@freezed
abstract class BodyPhotoDto with _$BodyPhotoDto {
  const factory BodyPhotoDto({
    required String id,
    @JsonKey(name: 'member_id') required String memberId,
    required String pose, // stand|tpose|fold|ohsquat
    @Default('front') String direction, // front|side|back
    required String date,
    @JsonKey(name: 'storage_path') String? storagePath,
    @Default(false) bool blurred,
  }) = _BodyPhotoDto;

  factory BodyPhotoDto.fromJson(Map<String, dynamic> json) => _$BodyPhotoDtoFromJson(json);
}
