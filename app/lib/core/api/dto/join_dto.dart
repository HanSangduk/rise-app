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

    /// 진행 중인 가입 요청(계약 v2.27). **`member_id`가 없을 때만** 실린다 —
    /// 연결된 회원·스태프에겐 서버가 키 자체를 빼므로 nullable이다.
    ///
    /// 이 필드가 생기기 전엔 "요청을 보냈다"는 사실이 **기기의 SharedPreferences에만**
    /// 있었다. 그래서 기기를 바꾸거나 앱을 지웠다 깔면 근거가 사라져 화면이
    /// "요청한 적 없음"으로 떨어졌고, 사용자는 같은 요청을 또 보냈다 — 그 중복이
    /// 대표 어드민을 죽이던 재료였다(P55). 이제 서버가 주인이다.
    @JsonKey(name: 'join_request') JoinRequestStatusDto? joinRequest,
  }) = _MeResponseDto;

  factory MeResponseDto.fromJson(Map<String, dynamic> json) => _$MeResponseDtoFromJson(json);
}

/// `GET /v1/me`의 `join_request`(계약 v2.27·v2.34) — **`{status, center_id, created_at}` 셋뿐**이다.
/// 이름·번호는 신청자가 방금 입력한 값이라 되돌려줄 이유가 없고, 응답 표면은 좁을수록 좋다.
@freezed
abstract class JoinRequestStatusDto with _$JoinRequestStatusDto {
  const factory JoinRequestStatusDto({
    /// `pending` | `rejected` | `approved`.
    ///
    /// `approved`는 정상 경로에서 보이지 않는다 — 승인되면 `member_id`가 생겨
    /// 이 필드 자체가 빠지기 때문이다. 승인 도중 인덱스 쓰기만 실패한 부분 잔여에서만
    /// 관측되므로 "승인됐는데 아직 연결 중"으로 다루고 재조회한다.
    required String status,

    /// 요청이 귀속된 센터(계약 v2.34). **구서버는 이 키를 모른다** → `''`. v2.33이 요청 시
    /// 센터 선택을 열었으므로 대기실이 "어느 센터에 보냈는지"를 알아야 그 센터의 연락처를
    /// 보여줄 수 있다(없으면 기본 센터 — 종전 동작).
    @JsonKey(name: 'center_id') @Default('') String centerId,
    @JsonKey(name: 'created_at') required String createdAt,
  }) = _JoinRequestStatusDto;

  factory JoinRequestStatusDto.fromJson(Map<String, dynamic> json) =>
      _$JoinRequestStatusDtoFromJson(json);
}

/// GET /v1/join/centers 응답 한 건(계약 v2.33).
///
/// **freezed를 쓰지 않는다.** 이 파일의 다른 DTO들은 copyWith·값 동등성이 필요해 코드젠을
/// 쓰지만, 이 타입은 한 번 파싱해 도메인으로 넘기고 버려지는 4칸짜리 읽기 전용 값이라
/// 생성 파일 두 개를 늘릴 이유가 없다. 파싱 규약은 같다 — **모르는 키는 무시하고, 없는 키는
/// 빈 문자열**이다(서버가 필드를 늘려도 앱이 깨지지 않는다).
class CenterDirectoryDto {
  const CenterDirectoryDto({
    required this.id,
    required this.name,
    this.address = '',
    this.phone = '',
  });

  final String id;
  final String name;
  final String address;
  final String phone;

  factory CenterDirectoryDto.fromJson(Map<String, dynamic> json) => CenterDirectoryDto(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        address: (json['address'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
      );
}
