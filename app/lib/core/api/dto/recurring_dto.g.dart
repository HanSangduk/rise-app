// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recurring_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RecurringDto _$RecurringDtoFromJson(Map<String, dynamic> json) =>
    _RecurringDto(
      id: json['id'] as String,
      memberId: json['member_id'] as String,
      trainerId: json['trainer_id'] as String,
      passId: json['pass_id'] as String,
      days:
          (json['days'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const <String>[],
      hour: (json['hour'] as num).toInt(),
      until: json['until'] as String?,
    );

Map<String, dynamic> _$RecurringDtoToJson(_RecurringDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'member_id': instance.memberId,
      'trainer_id': instance.trainerId,
      'pass_id': instance.passId,
      'days': instance.days,
      'hour': instance.hour,
      'until': instance.until,
    };
