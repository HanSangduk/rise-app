// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_log_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WorkoutLogDto _$WorkoutLogDtoFromJson(Map<String, dynamic> json) =>
    _WorkoutLogDto(
      id: json['id'] as String,
      memberId: json['member_id'] as String,
      trainerId: json['trainer_id'] as String,
      bookingId: json['booking_id'] as String?,
      date: json['date'] as String,
      title: json['title'] as String? ?? '',
      exercises:
          (json['exercises'] as List<dynamic>?)
              ?.map(
                (e) => WorkoutExerciseDto.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const <WorkoutExerciseDto>[],
      coachNote: json['coach_note'] as String? ?? '',
    );

Map<String, dynamic> _$WorkoutLogDtoToJson(_WorkoutLogDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'member_id': instance.memberId,
      'trainer_id': instance.trainerId,
      'booking_id': instance.bookingId,
      'date': instance.date,
      'title': instance.title,
      'exercises': instance.exercises,
      'coach_note': instance.coachNote,
    };

_WorkoutExerciseDto _$WorkoutExerciseDtoFromJson(Map<String, dynamic> json) =>
    _WorkoutExerciseDto(
      name: json['name'] as String,
      sets: (json['sets'] as num?)?.toInt() ?? 0,
      reps: _repsToString(json['reps']),
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0,
      note: json['note'] as String?,
    );

Map<String, dynamic> _$WorkoutExerciseDtoToJson(_WorkoutExerciseDto instance) =>
    <String, dynamic>{
      'name': instance.name,
      'sets': instance.sets,
      'reps': instance.reps,
      'weight_kg': instance.weightKg,
      'note': instance.note,
    };
