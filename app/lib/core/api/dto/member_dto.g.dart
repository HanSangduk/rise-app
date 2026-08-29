// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MemberDto _$MemberDtoFromJson(Map<String, dynamic> json) => _MemberDto(
  id: json['id'] as String,
  name: json['name'] as String,
  phone: json['phone'] as String,
  channel: json['channel'] as String?,
  trainerId: json['trainer_id'] as String?,
  flags:
      (json['flags'] as List<dynamic>?)
          ?.map((e) => MemberFlagDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MemberFlagDto>[],
  consent: json['consent'] == null
      ? null
      : ConsentDto.fromJson(json['consent'] as Map<String, dynamic>),
  appLinked: json['app_linked'] as bool? ?? false,
  status: json['status'] as String? ?? 'active',
  lastVisitAt: json['last_visit_at'] as String?,
  bodyPoses: (json['body_poses'] as List<dynamic>?)
      ?.map((e) => BodyPoseDto.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$MemberDtoToJson(_MemberDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'phone': instance.phone,
      'channel': instance.channel,
      'trainer_id': instance.trainerId,
      'flags': instance.flags,
      'consent': instance.consent,
      'app_linked': instance.appLinked,
      'status': instance.status,
      'last_visit_at': instance.lastVisitAt,
      'body_poses': instance.bodyPoses,
    };

_BodyPoseDto _$BodyPoseDtoFromJson(Map<String, dynamic> json) =>
    _BodyPoseDto(key: json['key'] as String, label: json['label'] as String);

Map<String, dynamic> _$BodyPoseDtoToJson(_BodyPoseDto instance) =>
    <String, dynamic>{'key': instance.key, 'label': instance.label};

_MemberFlagDto _$MemberFlagDtoFromJson(Map<String, dynamic> json) =>
    _MemberFlagDto(type: json['type'] as String, note: json['note'] as String?);

Map<String, dynamic> _$MemberFlagDtoToJson(_MemberFlagDto instance) =>
    <String, dynamic>{'type': instance.type, 'note': instance.note};

_ConsentDto _$ConsentDtoFromJson(Map<String, dynamic> json) => _ConsentDto(
  general: json['general'] as bool? ?? false,
  sensitive: json['sensitive'] as bool? ?? false,
  signedAt: json['signed_at'] as String?,
  revokedAt: json['revoked_at'] as String?,
);

Map<String, dynamic> _$ConsentDtoToJson(_ConsentDto instance) =>
    <String, dynamic>{
      'general': instance.general,
      'sensitive': instance.sensitive,
      'signed_at': instance.signedAt,
      'revoked_at': instance.revokedAt,
    };
