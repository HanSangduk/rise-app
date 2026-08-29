// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'body_photo_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BodyPhotoDto _$BodyPhotoDtoFromJson(Map<String, dynamic> json) =>
    _BodyPhotoDto(
      id: json['id'] as String,
      memberId: json['member_id'] as String,
      pose: json['pose'] as String,
      direction: json['direction'] as String? ?? 'front',
      date: json['date'] as String,
      storagePath: json['storage_path'] as String?,
      blurred: json['blurred'] as bool? ?? false,
    );

Map<String, dynamic> _$BodyPhotoDtoToJson(_BodyPhotoDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'member_id': instance.memberId,
      'pose': instance.pose,
      'direction': instance.direction,
      'date': instance.date,
      'storage_path': instance.storagePath,
      'blurred': instance.blurred,
    };
