import 'package:freezed_annotation/freezed_annotation.dart';

part 'workout_log_dto.freezed.dart';
part 'workout_log_dto.g.dart';

/// API계약 v1.4 — WorkoutLog 엔티티(수업 기록).
/// {id, member_id, trainer_id, booking_id?, date, title, exercises:[], coach_note}
/// reps는 문자열(HwItem과 동일 규약) · weight_kg는 숫자(0=자중) · exercises는 항상 [].
@freezed
abstract class WorkoutLogDto with _$WorkoutLogDto {
  const factory WorkoutLogDto({
    required String id,
    @JsonKey(name: 'member_id') required String memberId,
    @JsonKey(name: 'trainer_id') required String trainerId,
    @JsonKey(name: 'booking_id') String? bookingId,
    required String date, // "2026-08-22"
    @Default('') String title, // 서버 기본 "1:1 PT" — 빈 값은 repository에서 폴백
    @Default(<WorkoutExerciseDto>[]) List<WorkoutExerciseDto> exercises,
    @JsonKey(name: 'coach_note') @Default('') String coachNote,
  }) = _WorkoutLogDto;

  factory WorkoutLogDto.fromJson(Map<String, dynamic> json) => _$WorkoutLogDtoFromJson(json);
}

/// reps는 백엔드가 숫자(12)로 주든 문자열("10-12"·"30초")로 주든 안전하게 문자열화
/// (HomeworkItemDto와 동일 방어).
String? _repsToString(Object? value) => value?.toString();

@freezed
abstract class WorkoutExerciseDto with _$WorkoutExerciseDto {
  const factory WorkoutExerciseDto({
    required String name,
    @Default(0) int sets,
    @JsonKey(fromJson: _repsToString) String? reps,
    // 계약: 숫자(int/float 혼용 가능) → double. 0 = 자중/해당 없음.
    @JsonKey(name: 'weight_kg') @Default(0) double weightKg,
    String? note,
  }) = _WorkoutExerciseDto;

  factory WorkoutExerciseDto.fromJson(Map<String, dynamic> json) =>
      _$WorkoutExerciseDtoFromJson(json);
}
