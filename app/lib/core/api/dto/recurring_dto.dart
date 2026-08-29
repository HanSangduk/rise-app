import 'package:freezed_annotation/freezed_annotation.dart';

part 'recurring_dto.freezed.dart';
part 'recurring_dto.g.dart';

/// API계약_v1.md — Recurring 엔티티(고정 스케줄, P47).
@freezed
abstract class RecurringDto with _$RecurringDto {
  const factory RecurringDto({
    required String id,
    @JsonKey(name: 'member_id') required String memberId,
    @JsonKey(name: 'trainer_id') required String trainerId,
    @JsonKey(name: 'pass_id') required String passId,
    @Default(<String>[]) List<String> days, // ["tue","fri"]
    required int hour,
    String? until,
  }) = _RecurringDto;

  factory RecurringDto.fromJson(Map<String, dynamic> json) => _$RecurringDtoFromJson(json);
}
