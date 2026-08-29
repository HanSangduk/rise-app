// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'slot_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SlotDto _$SlotDtoFromJson(Map<String, dynamic> json) => _SlotDto(
  slotKey: json['slot_key'] as String,
  capacity: (json['capacity'] as num?)?.toInt() ?? 3,
  teams:
      (json['teams'] as List<dynamic>?)
          ?.map((e) => SlotTeamDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <SlotTeamDto>[],
);

Map<String, dynamic> _$SlotDtoToJson(_SlotDto instance) => <String, dynamic>{
  'slot_key': instance.slotKey,
  'capacity': instance.capacity,
  'teams': instance.teams,
};

_SlotTeamDto _$SlotTeamDtoFromJson(Map<String, dynamic> json) => _SlotTeamDto(
  bookingId: json['booking_id'] as String,
  trainerId: json['trainer_id'] as String,
  memberId: json['member_id'] as String,
  kind: json['kind'] as String,
);

Map<String, dynamic> _$SlotTeamDtoToJson(_SlotTeamDto instance) =>
    <String, dynamic>{
      'booking_id': instance.bookingId,
      'trainer_id': instance.trainerId,
      'member_id': instance.memberId,
      'kind': instance.kind,
    };
