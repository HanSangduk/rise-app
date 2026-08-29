import 'package:freezed_annotation/freezed_annotation.dart';

part 'center_dto.freezed.dart';
part 'center_dto.g.dart';

/// API계약 v1.1/v1.4 — GET /v1/center 응답 {center_id, policy}.
/// v1.4에서 member에게도 공개(취소 컷오프·홀딩 상한을 실정책 값으로 표시).
/// revenue_target 등 owner 전용 금액 지표는 회원 응답에서 0이므로 파싱하지 않는다.
@freezed
abstract class CenterResponseDto with _$CenterResponseDto {
  const factory CenterResponseDto({
    @JsonKey(name: 'center_id') required String centerId,
    required CenterPolicyDto policy,
  }) = _CenterResponseDto;

  factory CenterResponseDto.fromJson(Map<String, dynamic> json) =>
      _$CenterResponseDtoFromJson(json);
}

/// Policy 중 회원 앱이 소비하는 필드(백엔드 domain.Policy json 태그 그대로).
/// 홀딩 상한 -1 = 무제한(계약 v1.3: 무제한은 -1로만 표현).
@freezed
abstract class CenterPolicyDto with _$CenterPolicyDto {
  const factory CenterPolicyDto({
    @JsonKey(name: 'slot_capacity') @Default(3) int slotCapacity,
    @JsonKey(name: 'cancel_cutoff_hours') @Default(24) int cancelCutoffHours,
    @JsonKey(name: 'grace_once') @Default(true) bool graceOnce,
    @JsonKey(name: 'penalty_rate') @Default(0.10) double penaltyRate,
    /// 만료임박 기준일(대표가 설정 화면에서 정한다). 서버는 v1부터 이 값을 내려주는데
    /// 앱이 파싱하지 않아, 홈의 "연장 상담 가능" 배지가 **조건 없이 항상** 켜져 있었다.
    @JsonKey(name: 'expiring_days') @Default(7) int expiringDays,
    @JsonKey(name: 'max_holds_per_pass') @Default(2) int maxHoldsPerPass,
    @JsonKey(name: 'max_hold_total_days') @Default(30) int maxHoldTotalDays,
  }) = _CenterPolicyDto;

  factory CenterPolicyDto.fromJson(Map<String, dynamic> json) =>
      _$CenterPolicyDtoFromJson(json);
}
