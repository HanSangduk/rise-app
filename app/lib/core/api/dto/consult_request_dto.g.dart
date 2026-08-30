// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'consult_request_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ConsultRequestDto _$ConsultRequestDtoFromJson(Map<String, dynamic> json) =>
    _ConsultRequestDto(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'renewal',
      note: json['note'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] as String?,
    );

Map<String, dynamic> _$ConsultRequestDtoToJson(_ConsultRequestDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'kind': instance.kind,
      'note': instance.note,
      'status': instance.status,
      'created_at': instance.createdAt,
    };
