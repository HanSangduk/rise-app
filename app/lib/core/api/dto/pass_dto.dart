import 'package:freezed_annotation/freezed_annotation.dart';

part 'pass_dto.freezed.dart';
part 'pass_dto.g.dart';

/// API계약_v1.md — Pass 엔티티.
@freezed
abstract class PassDto with _$PassDto {
  const factory PassDto({
    required String id,
    @JsonKey(name: 'member_id') required String memberId,
    @JsonKey(name: 'trainer_id') required String trainerId,
    required String product,
    @JsonKey(name: 'paid_amount') required int paidAmount,
    @JsonKey(name: 'total_sessions') required int totalSessions,
    required int remaining,
    @JsonKey(name: 'valid_from') required String validFrom,
    @JsonKey(name: 'valid_until') required String validUntil,
    @Default('active') String status, // active|scheduled|expired|refunded
    @Default(<PassHoldDto>[]) List<PassHoldDto> holds,
  }) = _PassDto;

  factory PassDto.fromJson(Map<String, dynamic> json) => _$PassDtoFromJson(json);
}

@freezed
abstract class PassHoldDto with _$PassHoldDto {
  const factory PassHoldDto({
    required String from,
    required String to,
    String? reason,
  }) = _PassHoldDto;

  factory PassHoldDto.fromJson(Map<String, dynamic> json) => _$PassHoldDtoFromJson(json);
}
