import 'package:freezed_annotation/freezed_annotation.dart';

part 'member_dto.freezed.dart';
part 'member_dto.g.dart';

/// API계약_v1.md — Member 엔티티. json 키는 계약 그대로(snake_case).
@freezed
abstract class MemberDto with _$MemberDto {
  const factory MemberDto({
    required String id,
    required String name,
    required String phone,
    String? channel,
    @JsonKey(name: 'trainer_id') String? trainerId,
    @Default(<MemberFlagDto>[]) List<MemberFlagDto> flags,
    ConsentDto? consent,
    @JsonKey(name: 'app_linked') @Default(false) bool appLinked,
    @Default('active') String status, // active|dormant
    @JsonKey(name: 'last_visit_at') String? lastVisitAt,

    /// 체형 촬영 포즈 시퀀스(계약 v2.10). **nullable로 둔다** — 구버전 서버는 이 키를
    /// 안 보내고, required로 파싱하면 회원 목록 전체가 던져 앱이 통째로 죽는다
    /// (인바디 `source`에서 같은 이유로 nullable을 택한 전례).
    /// 서버는 응답에서 항상 구체화해 주므로 정상 경로에선 비어 있지 않다.
    @JsonKey(name: 'body_poses') List<BodyPoseDto>? bodyPoses,
  }) = _MemberDto;

  factory MemberDto.fromJson(Map<String, dynamic> json) => _$MemberDtoFromJson(json);
}

/// 계약 v2.10 — `{key, label}`. key는 Storage 파일명 조각이라 서버가 슬러그를 강제한다.
@freezed
abstract class BodyPoseDto with _$BodyPoseDto {
  const factory BodyPoseDto({
    required String key,
    required String label,
  }) = _BodyPoseDto;

  factory BodyPoseDto.fromJson(Map<String, dynamic> json) => _$BodyPoseDtoFromJson(json);
}

@freezed
abstract class MemberFlagDto with _$MemberFlagDto {
  const factory MemberFlagDto({
    required String type, // 예: "injury"
    String? note,
  }) = _MemberFlagDto;

  factory MemberFlagDto.fromJson(Map<String, dynamic> json) => _$MemberFlagDtoFromJson(json);
}

@freezed
abstract class ConsentDto with _$ConsentDto {
  const factory ConsentDto({
    @Default(false) bool general,
    @Default(false) bool sensitive,
    @JsonKey(name: 'signed_at') String? signedAt,
    @JsonKey(name: 'revoked_at') String? revokedAt,
  }) = _ConsentDto;

  factory ConsentDto.fromJson(Map<String, dynamic> json) => _$ConsentDtoFromJson(json);
}
