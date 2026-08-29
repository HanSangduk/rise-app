import 'package:freezed_annotation/freezed_annotation.dart';

part 'payment_dto.freezed.dart';
part 'payment_dto.g.dart';

/// API계약 — Payment 엔티티(결제·분할납부).
///
/// 서버 `GET /v1/payments?member=`는 **회원 스코프로도 열려 있다**(`memberScopeID`) —
/// 본인 분할 내역이 그대로 내려온다. 종전엔 서버가 주는데 앱에 그리는 화면이 0이라,
/// 분할로 결제한 회원이 "2차가 언제 얼마인지"를 앱에서 확인할 방법이 없었다.
@freezed
abstract class PaymentDto with _$PaymentDto {
  const factory PaymentDto({
    required String id,
    @JsonKey(name: 'member_id') required String memberId,
    @JsonKey(name: 'pass_id') required String passId,
    @Default('card') String method, // card|cash|transfer
    @Default(0) int total,
    @Default(<InstallmentDto>[]) List<InstallmentDto> installments,
    @Default('') String channel,
  }) = _PaymentDto;

  factory PaymentDto.fromJson(Map<String, dynamic> json) => _$PaymentDtoFromJson(json);
}

/// 분할납부 회차.
///
/// `waived_at`은 v1.5 — 패스 환불로 **더 이상 수납하지 않는** 회차다. 삭제가 아니라
/// 표식이라(원장주의 P3와 같은 철학) 목록에는 남되 미납 합계에서는 빠져야 한다.
/// 이걸 미납으로 세면 이미 환불받은 회원에게 "아직 낼 돈이 있다"고 말하게 된다.
@freezed
abstract class InstallmentDto with _$InstallmentDto {
  const factory InstallmentDto({
    @Default('') String due, // "YYYY-MM-DD"
    @Default(0) int amount,
    @JsonKey(name: 'paid_at') String? paidAt,
    @JsonKey(name: 'waived_at') String? waivedAt,
  }) = _InstallmentDto;

  factory InstallmentDto.fromJson(Map<String, dynamic> json) => _$InstallmentDtoFromJson(json);
}
