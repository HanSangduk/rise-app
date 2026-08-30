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

/// 운영시간 필드의 관대한 파싱 — 정수가 아니면 **null(= 서버가 안 준 것과 동일)**.
///
/// 이웃 필드처럼 `@Default`를 쓰지 않는 이유는 [CenterPolicyDto.openHour] 주석 참조.
/// `as num` 캐스트를 그대로 두면 `open_hour: "9"` 하나에 파싱 전체가 던져지고,
/// 정책 provider의 catch가 **취소 컷오프·홀딩 상한까지 통째로** 폴백시킨다 —
/// 운영시간 한 필드의 오타가 다른 정책들의 실값을 지우게 된다.
int? _hourOrNull(Object? value) => value is num ? value.toInt() : null;

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

    /// 센터 운영시간 — **슬롯 시작 시각, 양끝 포함**(9·21 → 09시 시작 ~ 21시 시작 13칸).
    ///
    /// **이웃 필드와 달리 nullable이고 `@Default`가 없다.** 여기에 `@Default(9)`를
    /// 박으면 같은 숫자가 DTO와 `CenterPolicy.fallback` 두 군데에 살면서 따로 움직일
    /// 수 있는데, 이 두 자리는 반드시 같아야 한다 — "서버가 필드를 안 준 구버전"과
    /// "정책 조회 자체가 실패"는 회원에게 **똑같이 오늘의 09~21시**로 보여야 한다.
    /// 그래서 "서버가 안 줬다"를 null 그대로 넘기고, 기본값과 유효성(open ≤ close,
    /// 0..23)은 정책을 읽는 경계 한 곳(`CenterPolicy.resolveHours`)이 전담한다.
    @JsonKey(name: 'open_hour', fromJson: _hourOrNull) int? openHour,
    @JsonKey(name: 'close_hour', fromJson: _hourOrNull) int? closeHour,
  }) = _CenterPolicyDto;

  factory CenterPolicyDto.fromJson(Map<String, dynamic> json) =>
      _$CenterPolicyDtoFromJson(json);
}
