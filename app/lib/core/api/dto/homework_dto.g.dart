// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'homework_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_HomeworkDto _$HomeworkDtoFromJson(Map<String, dynamic> json) => _HomeworkDto(
  id: json['id'] as String,
  trainerId: json['trainer_id'] as String,
  scope: json['scope'] as String? ?? 'individual',
  targetMemberIds:
      (json['target_member_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  excluded:
      (json['excluded'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  items:
      (json['items'] as List<dynamic>?)
          ?.map((e) => HomeworkItemDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <HomeworkItemDto>[],
  schedule: json['schedule'] == null
      ? null
      : HomeworkScheduleDto.fromJson(json['schedule'] as Map<String, dynamic>),
);

Map<String, dynamic> _$HomeworkDtoToJson(_HomeworkDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainer_id': instance.trainerId,
      'scope': instance.scope,
      'target_member_ids': instance.targetMemberIds,
      'excluded': instance.excluded,
      'items': instance.items,
      'schedule': instance.schedule,
    };

_HomeworkItemDto _$HomeworkItemDtoFromJson(Map<String, dynamic> json) =>
    _HomeworkItemDto(
      name: json['name'] as String,
      sets: (json['sets'] as num?)?.toInt(),
      reps: _repsToString(json['reps']),
      note: json['note'] as String?,
    );

Map<String, dynamic> _$HomeworkItemDtoToJson(_HomeworkItemDto instance) =>
    <String, dynamic>{
      'name': instance.name,
      'sets': instance.sets,
      'reps': instance.reps,
      'note': instance.note,
    };

_HomeworkScheduleDto _$HomeworkScheduleDtoFromJson(Map<String, dynamic> json) =>
    _HomeworkScheduleDto(
      type: json['type'] as String? ?? 'weekly',
      days:
          (json['days'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const <String>[],
      from: json['from'] as String?,
      to: json['to'] as String?,
    );

Map<String, dynamic> _$HomeworkScheduleDtoToJson(
  _HomeworkScheduleDto instance,
) => <String, dynamic>{
  'type': instance.type,
  'days': instance.days,
  'from': instance.from,
  'to': instance.to,
};

_HwCheckDto _$HwCheckDtoFromJson(Map<String, dynamic> json) => _HwCheckDto(
  memberId: json['member_id'] as String,
  hwId: json['hw_id'] as String,
  date: json['date'] as String,
  done:
      (json['done'] as List<dynamic>?)?.map((e) => e as bool).toList() ??
      const <bool>[],
);

Map<String, dynamic> _$HwCheckDtoToJson(_HwCheckDto instance) =>
    <String, dynamic>{
      'member_id': instance.memberId,
      'hw_id': instance.hwId,
      'date': instance.date,
      'done': instance.done,
    };
