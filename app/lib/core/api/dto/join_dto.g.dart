// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'join_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_JoinMatchResponseDto _$JoinMatchResponseDtoFromJson(
  Map<String, dynamic> json,
) => _JoinMatchResponseDto(
  member: json['member'] == null
      ? null
      : MemberDto.fromJson(json['member'] as Map<String, dynamic>),
  needsConfirm: json['needs_confirm'] as bool? ?? false,
);

Map<String, dynamic> _$JoinMatchResponseDtoToJson(
  _JoinMatchResponseDto instance,
) => <String, dynamic>{
  'member': instance.member,
  'needs_confirm': instance.needsConfirm,
};

_MeResponseDto _$MeResponseDtoFromJson(Map<String, dynamic> json) =>
    _MeResponseDto(
      uid: json['uid'] as String,
      role: json['role'] as String,
      centerId: json['center_id'] as String,
      memberId: json['member_id'] as String?,
      name: json['name'] as String?,
    );

Map<String, dynamic> _$MeResponseDtoToJson(_MeResponseDto instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'role': instance.role,
      'center_id': instance.centerId,
      'member_id': instance.memberId,
      'name': instance.name,
    };
