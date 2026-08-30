// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contract_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ContractDto _$ContractDtoFromJson(Map<String, dynamic> json) => _ContractDto(
  id: json['id'] as String,
  memberId: json['member_id'] as String,
  passId: json['pass_id'] as String,
  product: json['product'] as String,
  paidAmount: (json['paid_amount'] as num).toInt(),
  penaltyRate: (json['penalty_rate'] as num?)?.toDouble(),
  status: json['status'] as String? ?? 'draft',
  sentAt: json['sent_at'] as String?,
  firstSentAt: json['first_sent_at'] as String?,
  signedAt: json['signed_at'] as String?,
  signerIp: json['signer_ip'] as String?,
  sha256: json['sha256'] as String?,
  pdfPath: json['pdf_path'] as String?,
  templateVersion: json['template_version'] as String? ?? '',
  vars: json['vars'] == null
      ? const <String, String>{}
      : _contractVarsFromJson(json['vars']),
  signaturePng: json['signature_png'] as String? ?? '',
  signatureSha256: json['signature_sha256'] as String? ?? '',
);

Map<String, dynamic> _$ContractDtoToJson(_ContractDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'member_id': instance.memberId,
      'pass_id': instance.passId,
      'product': instance.product,
      'paid_amount': instance.paidAmount,
      'penalty_rate': instance.penaltyRate,
      'status': instance.status,
      'sent_at': instance.sentAt,
      'first_sent_at': instance.firstSentAt,
      'signed_at': instance.signedAt,
      'signer_ip': instance.signerIp,
      'sha256': instance.sha256,
      'pdf_path': instance.pdfPath,
      'template_version': instance.templateVersion,
      'vars': instance.vars,
      'signature_png': instance.signaturePng,
      'signature_sha256': instance.signatureSha256,
    };
