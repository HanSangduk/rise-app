import 'package:freezed_annotation/freezed_annotation.dart';

part 'slot_dto.freezed.dart';
part 'slot_dto.g.dart';

/// API계약_v1.md — Slot 엔티티. slotKey 예: "20260814-20" (YYYYMMDD-HH).
@freezed
abstract class SlotDto with _$SlotDto {
  const factory SlotDto({
    @JsonKey(name: 'slot_key') required String slotKey,
    @Default(3) int capacity,
    @Default(<SlotTeamDto>[]) List<SlotTeamDto> teams,
  }) = _SlotDto;

  factory SlotDto.fromJson(Map<String, dynamic> json) => _$SlotDtoFromJson(json);
}

@freezed
abstract class SlotTeamDto with _$SlotTeamDto {
  const factory SlotTeamDto({
    @JsonKey(name: 'booking_id') required String bookingId,
    @JsonKey(name: 'trainer_id') required String trainerId,
    @JsonKey(name: 'member_id') required String memberId,
    required String kind, // pt|group|ot
  }) = _SlotTeamDto;

  factory SlotTeamDto.fromJson(Map<String, dynamic> json) => _$SlotTeamDtoFromJson(json);
}
