// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PaymentDto _$PaymentDtoFromJson(Map<String, dynamic> json) => _PaymentDto(
  id: json['id'] as String,
  memberId: json['member_id'] as String,
  passId: json['pass_id'] as String,
  method: json['method'] as String? ?? 'card',
  total: (json['total'] as num?)?.toInt() ?? 0,
  installments:
      (json['installments'] as List<dynamic>?)
          ?.map((e) => InstallmentDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <InstallmentDto>[],
  channel: json['channel'] as String? ?? '',
);

Map<String, dynamic> _$PaymentDtoToJson(_PaymentDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'member_id': instance.memberId,
      'pass_id': instance.passId,
      'method': instance.method,
      'total': instance.total,
      'installments': instance.installments,
      'channel': instance.channel,
    };

_InstallmentDto _$InstallmentDtoFromJson(Map<String, dynamic> json) =>
    _InstallmentDto(
      due: json['due'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      paidAt: json['paid_at'] as String?,
      waivedAt: json['waived_at'] as String?,
    );

Map<String, dynamic> _$InstallmentDtoToJson(_InstallmentDto instance) =>
    <String, dynamic>{
      'due': instance.due,
      'amount': instance.amount,
      'paid_at': instance.paidAt,
      'waived_at': instance.waivedAt,
    };
