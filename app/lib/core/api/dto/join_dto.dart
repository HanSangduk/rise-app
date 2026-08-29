import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:rise_member/core/api/dto/member_dto.dart';

part 'join_dto.freezed.dart';
part 'join_dto.g.dart';

/// API계약_v1.md — POST /v1/join/match 응답: {member?, needs_confirm:true}.
@freezed
abstract class JoinMatchResponseDto with _$JoinMatchResponseDto {
  const factory JoinMatchResponseDto({
    MemberDto? member,
    @JsonKey(name: 'needs_confirm') @Default(false) bool needsConfirm,
  }) = _JoinMatchResponseDto;

  factory JoinMatchResponseDto.fromJson(Map<String, dynamic> json) =>
      _$JoinMatchResponseDtoFromJson(json);
}

/// API계약_v1.md — GET /v1/me 응답: {uid, role, center_id, member_id?, name?}.
@freezed
abstract class MeResponseDto with _$MeResponseDto {
  const factory MeResponseDto({
    required String uid,
    required String role,
    @JsonKey(name: 'center_id') required String centerId,
    @JsonKey(name: 'member_id') String? memberId,

    /// 화면 표시용 본인 이름(계약 v2.2). **없을 수 있다** — 서버는 이름을
    /// best-effort로만 채우고(조회 실패해도 /v1/me는 성공한다), 미연결 계정이면
    /// omitempty로 아예 빠지며, 구버전 서버는 이 키 자체를 모른다.
    /// 그래서 non-null 기본값(`@Default('')`)이 아니라 nullable이다 — "서버가
    /// 안 줬다"와 "서버가 빈 이름을 줬다"를 굳이 가르지 않되, 호출부가 폴백을
    /// **반드시** 거치게 강제한다.
    String? name,
  }) = _MeResponseDto;

  factory MeResponseDto.fromJson(Map<String, dynamic> json) => _$MeResponseDtoFromJson(json);
}
