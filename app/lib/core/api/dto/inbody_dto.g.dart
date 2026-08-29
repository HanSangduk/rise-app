// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbody_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_InbodyDto _$InbodyDtoFromJson(Map<String, dynamic> json) => _InbodyDto(
  id: json['id'] as String,
  memberId: json['member_id'] as String,
  date: json['date'] as String,
  weight: (json['weight'] as num).toDouble(),
  smm: (json['smm'] as num).toDouble(),
  bfm: (json['bfm'] as num).toDouble(),
  pbf: (json['pbf'] as num).toDouble(),
  vfl: (json['vfl'] as num).toDouble(),
  bmr: (json['bmr'] as num).toDouble(),
  source: json['source'] as String?,
);

Map<String, dynamic> _$InbodyDtoToJson(_InbodyDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'member_id': instance.memberId,
      'date': instance.date,
      'weight': instance.weight,
      'smm': instance.smm,
      'bfm': instance.bfm,
      'pbf': instance.pbf,
      'vfl': instance.vfl,
      'bmr': instance.bmr,
      'source': instance.source,
    };
