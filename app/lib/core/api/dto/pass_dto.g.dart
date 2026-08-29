// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pass_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PassDto _$PassDtoFromJson(Map<String, dynamic> json) => _PassDto(
  id: json['id'] as String,
  memberId: json['member_id'] as String,
  trainerId: json['trainer_id'] as String,
  product: json['product'] as String,
  paidAmount: (json['paid_amount'] as num).toInt(),
  totalSessions: (json['total_sessions'] as num).toInt(),
  remaining: (json['remaining'] as num).toInt(),
  validFrom: json['valid_from'] as String,
  validUntil: json['valid_until'] as String,
  status: json['status'] as String? ?? 'active',
  holds:
      (json['holds'] as List<dynamic>?)
          ?.map((e) => PassHoldDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <PassHoldDto>[],
);

Map<String, dynamic> _$PassDtoToJson(_PassDto instance) => <String, dynamic>{
  'id': instance.id,
  'member_id': instance.memberId,
  'trainer_id': instance.trainerId,
  'product': instance.product,
  'paid_amount': instance.paidAmount,
  'total_sessions': instance.totalSessions,
  'remaining': instance.remaining,
  'valid_from': instance.validFrom,
  'valid_until': instance.validUntil,
  'status': instance.status,
  'holds': instance.holds,
};

_PassHoldDto _$PassHoldDtoFromJson(Map<String, dynamic> json) => _PassHoldDto(
  from: json['from'] as String,
  to: json['to'] as String,
  reason: json['reason'] as String?,
);

Map<String, dynamic> _$PassHoldDtoToJson(_PassHoldDto instance) =>
    <String, dynamic>{
      'from': instance.from,
      'to': instance.to,
      'reason': instance.reason,
    };
