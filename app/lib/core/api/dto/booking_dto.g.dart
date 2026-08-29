// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BookingDto _$BookingDtoFromJson(Map<String, dynamic> json) => _BookingDto(
  id: json['id'] as String,
  slotKey: json['slot_key'] as String,
  memberId: json['member_id'] as String,
  trainerId: json['trainer_id'] as String,
  passId: json['pass_id'] as String,
  kind: json['kind'] as String,
  status: json['status'] as String? ?? 'confirmed',
  recurringId: json['recurring_id'] as String?,
  createdAt: json['created_at'] as String?,
);

Map<String, dynamic> _$BookingDtoToJson(_BookingDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'slot_key': instance.slotKey,
      'member_id': instance.memberId,
      'trainer_id': instance.trainerId,
      'pass_id': instance.passId,
      'kind': instance.kind,
      'status': instance.status,
      'recurring_id': instance.recurringId,
      'created_at': instance.createdAt,
    };
