// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'center_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CenterResponseDto _$CenterResponseDtoFromJson(Map<String, dynamic> json) =>
    _CenterResponseDto(
      centerId: json['center_id'] as String,
      policy: CenterPolicyDto.fromJson(json['policy'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CenterResponseDtoToJson(_CenterResponseDto instance) =>
    <String, dynamic>{
      'center_id': instance.centerId,
      'policy': instance.policy,
    };

_CenterPolicyDto _$CenterPolicyDtoFromJson(Map<String, dynamic> json) =>
    _CenterPolicyDto(
      slotCapacity: (json['slot_capacity'] as num?)?.toInt() ?? 3,
      cancelCutoffHours: (json['cancel_cutoff_hours'] as num?)?.toInt() ?? 24,
      graceOnce: json['grace_once'] as bool? ?? true,
      penaltyRate: (json['penalty_rate'] as num?)?.toDouble() ?? 0.10,
      expiringDays: (json['expiring_days'] as num?)?.toInt() ?? 7,
      maxHoldsPerPass: (json['max_holds_per_pass'] as num?)?.toInt() ?? 2,
      maxHoldTotalDays: (json['max_hold_total_days'] as num?)?.toInt() ?? 30,
      openHour: _hourOrNull(json['open_hour']),
      closeHour: _hourOrNull(json['close_hour']),
    );

Map<String, dynamic> _$CenterPolicyDtoToJson(_CenterPolicyDto instance) =>
    <String, dynamic>{
      'slot_capacity': instance.slotCapacity,
      'cancel_cutoff_hours': instance.cancelCutoffHours,
      'grace_once': instance.graceOnce,
      'penalty_rate': instance.penaltyRate,
      'expiring_days': instance.expiringDays,
      'max_holds_per_pass': instance.maxHoldsPerPass,
      'max_hold_total_days': instance.maxHoldTotalDays,
      'open_hour': instance.openHour,
      'close_hour': instance.closeHour,
    };
