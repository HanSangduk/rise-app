import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking_dto.freezed.dart';
part 'booking_dto.g.dart';

/// API계약_v1.md — Booking 엔티티.
@freezed
abstract class BookingDto with _$BookingDto {
  const factory BookingDto({
    required String id,
    @JsonKey(name: 'slot_key') required String slotKey,
    @JsonKey(name: 'member_id') required String memberId,
    @JsonKey(name: 'trainer_id') required String trainerId,
    @JsonKey(name: 'pass_id') required String passId,
    required String kind, // pt|group|ot
    @Default('confirmed') String status, // confirmed|waitlist|cancelled|noshow|completed
    @JsonKey(name: 'recurring_id') String? recurringId,
    @JsonKey(name: 'created_at') String? createdAt,
  }) = _BookingDto;

  factory BookingDto.fromJson(Map<String, dynamic> json) => _$BookingDtoFromJson(json);
}
