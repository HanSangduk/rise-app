// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ledger_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LedgerDto _$LedgerDtoFromJson(Map<String, dynamic> json) => _LedgerDto(
  id: json['id'] as String,
  passId: json['pass_id'] as String,
  memberId: json['member_id'] as String,
  delta: (json['delta'] as num).toInt(),
  reason: json['reason'] as String,
  refBookingId: json['ref_booking_id'] as String?,
  by: json['by'] as String?,
  at: json['at'] as String,
);

Map<String, dynamic> _$LedgerDtoToJson(_LedgerDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'pass_id': instance.passId,
      'member_id': instance.memberId,
      'delta': instance.delta,
      'reason': instance.reason,
      'ref_booking_id': instance.refBookingId,
      'by': instance.by,
      'at': instance.at,
    };
