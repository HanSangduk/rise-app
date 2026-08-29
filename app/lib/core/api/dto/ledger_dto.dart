import 'package:freezed_annotation/freezed_annotation.dart';

part 'ledger_dto.freezed.dart';
part 'ledger_dto.g.dart';

/// API계약_v1.md — Ledger 엔티티(원장). reason은 계약에 명시된 9종 그대로 문자열 보관.
@freezed
abstract class LedgerDto with _$LedgerDto {
  const factory LedgerDto({
    required String id,
    @JsonKey(name: 'pass_id') required String passId,
    @JsonKey(name: 'member_id') required String memberId,
    required int delta,
    required String reason, // issue|complete|noshow|noshow_waived|revert|refund|hold|resume|transfer
    @JsonKey(name: 'ref_booking_id') String? refBookingId,
    String? by,
    required String at,
  }) = _LedgerDto;

  factory LedgerDto.fromJson(Map<String, dynamic> json) => _$LedgerDtoFromJson(json);
}
