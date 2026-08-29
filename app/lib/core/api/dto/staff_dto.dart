import 'package:freezed_annotation/freezed_annotation.dart';

part 'staff_dto.freezed.dart';
part 'staff_dto.g.dart';

/// API계약_v1.md — Staff 엔티티 중 회원 앱이 쓰는 필드만 파싱
/// (payout은 회원 응답에서 서버가 비우므로 생략 — json_serializable은 기본적으로
/// 미지정 키를 무시하므로 안전).
///
/// **offdays는 생략하지 않는다.** 예전 주석은 "payout/offdays는 원장·트레이너
/// 전용"이라고 적었지만 계약이 그렇지 않다: `ListStaff`는 role=member 응답에서
/// payout만 비우고(그리고 퇴사자 profile만 마스킹하고) offdays는 그대로 내려준다.
/// 파싱하지 않은 탓에 앱은 담당 코치의 휴무일을 전혀 몰랐고, 휴무일 슬롯이 정상
/// "예약 가능"으로 보인 뒤 확정 시트까지 가서야 400("담당 코치의 휴무일이에요")을
/// 받았다 — 화면 어디에도 휴무 표시가 없어 회원은 원인을 알 수 없었다.
@freezed
abstract class StaffDto with _$StaffDto {
  const StaffDto._();

  const factory StaffDto({
    required String uid,
    @Default('trainer') String role, // owner|trainer
    required String name,
    String? color,
    /// v2.0 직원 생애주기 — "active|inactive". 계약: **필드 부재/""는 active로 승격**
    /// (기존 Firestore 문서 마이그레이션 불필요). @Default는 키 누락·null만 메우므로
    /// ""·미지값의 승격은 [isInactive]가 "inactive일 때만 퇴사"로 판정해 처리한다.
    @Default('active') String status,

    /// v2.0 — RFC3339, inactive일 때만 존재(서버 기록). 프로필 시트 퇴사 시점 표기용.
    @JsonKey(name: 'left_at') String? leftAt,

    /// 휴무일 목록("YYYY-MM-DD"). 계약상 항상 배열(null 금지 — 서버 Normalize가
    /// nil을 []로 승격)이지만, 구버전 서버/키 누락에도 빈 목록으로 안전하게 떨어진다.
    /// 예약 사전 판정(BookingRules → TrainerOffday)이 이 값을 쓴다.
    @Default([]) List<String> offdays,

    // v1.6 — 계약상 항상 객체(null 금지)지만, 구버전 서버/키 누락에도 빈 프로필로 안전.
    // v2.0 — role=member 응답에선 inactive 스태프의 profile이 빈 객체로 마스킹된다
    // (이름은 남는다). 즉 "inactive + isEmpty"는 오류가 아니라 정상 응답이다.
    @Default(StaffProfileDto()) StaffProfileDto profile,
  }) = _StaffDto;

  factory StaffDto.fromJson(Map<String, dynamic> json) => _$StaffDtoFromJson(json);

  /// 퇴사한 스태프인가. "inactive"에만 true — 부재/""/미지값은 전부 현직으로 승격한다
  /// (계약 v2.0 승격 규약 + 구버전 서버 하위호환: 모르는 값 때문에 현직 코치를
  /// 퇴사자로 오표기하는 쪽이 훨씬 나쁘다).
  bool get isInactive => status == 'inactive';

  /// 퇴사일(파싱 실패/미표기면 null) — 프로필 시트 "2026년 8월에 퇴사했어요" 표기용.
  DateTime? get leftOn {
    final raw = leftAt;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

/// Staff.profile(계약 v1.6, P05) — 트레이너 소개. 배열은 항상 []·빈 문자열=미등록.
/// photo_url이 비었거나 로드에 실패하면 클라이언트는 Staff.color 배경 +
/// 이름 첫 글자 이니셜 아바타로 폴백한다(TrainerAvatar).
@freezed
abstract class StaffProfileDto with _$StaffProfileDto {
  const StaffProfileDto._();

  const factory StaffProfileDto({
    @JsonKey(name: 'photo_url') @Default('') String photoUrl,
    @Default('') String title, // 직함(예: "퍼포먼스 트레이너")
    @JsonKey(name: 'career_years') @Default(0) int careerYears, // 0=미표기
    @Default([]) List<String> specialties,
    @Default([]) List<String> certifications,
    @Default([]) List<String> awards, // 수상·선수 경력
    @Default('') String bio,
  }) = _StaffProfileDto;

  factory StaffProfileDto.fromJson(Map<String, dynamic> json) =>
      _$StaffProfileDtoFromJson(json);

  /// 등록된 소개가 하나도 없는 상태 — 프로필 시트가 "아직 소개가 등록되지 않았어요"로 표시.
  bool get isEmpty =>
      photoUrl.isEmpty &&
      title.isEmpty &&
      careerYears == 0 &&
      specialties.isEmpty &&
      certifications.isEmpty &&
      awards.isEmpty &&
      bio.isEmpty;
}
