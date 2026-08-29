// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'staff_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_StaffDto _$StaffDtoFromJson(Map<String, dynamic> json) => _StaffDto(
  uid: json['uid'] as String,
  role: json['role'] as String? ?? 'trainer',
  name: json['name'] as String,
  color: json['color'] as String?,
  status: json['status'] as String? ?? 'active',
  leftAt: json['left_at'] as String?,
  offdays:
      (json['offdays'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  profile: json['profile'] == null
      ? const StaffProfileDto()
      : StaffProfileDto.fromJson(json['profile'] as Map<String, dynamic>),
);

Map<String, dynamic> _$StaffDtoToJson(_StaffDto instance) => <String, dynamic>{
  'uid': instance.uid,
  'role': instance.role,
  'name': instance.name,
  'color': instance.color,
  'status': instance.status,
  'left_at': instance.leftAt,
  'offdays': instance.offdays,
  'profile': instance.profile,
};

_StaffProfileDto _$StaffProfileDtoFromJson(Map<String, dynamic> json) =>
    _StaffProfileDto(
      photoUrl: json['photo_url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      careerYears: (json['career_years'] as num?)?.toInt() ?? 0,
      specialties:
          (json['specialties'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      certifications:
          (json['certifications'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      awards:
          (json['awards'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      bio: json['bio'] as String? ?? '',
    );

Map<String, dynamic> _$StaffProfileDtoToJson(_StaffProfileDto instance) =>
    <String, dynamic>{
      'photo_url': instance.photoUrl,
      'title': instance.title,
      'career_years': instance.careerYears,
      'specialties': instance.specialties,
      'certifications': instance.certifications,
      'awards': instance.awards,
      'bio': instance.bio,
    };
