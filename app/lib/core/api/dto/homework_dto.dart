import 'package:freezed_annotation/freezed_annotation.dart';

part 'homework_dto.freezed.dart';
part 'homework_dto.g.dart';

/// API계약_v1.md — Homework 엔티티(Home Work 배정). 부상 플래그 자동 제외(P39)는 서버 책임.
@freezed
abstract class HomeworkDto with _$HomeworkDto {
  const factory HomeworkDto({
    required String id,
    @JsonKey(name: 'trainer_id') required String trainerId,
    @Default('individual') String scope, // individual|my_members|center_notice
    @JsonKey(name: 'target_member_ids') @Default(<String>[]) List<String> targetMemberIds,
    @Default(<String>[]) List<String> excluded,
    @Default(<HomeworkItemDto>[]) List<HomeworkItemDto> items,
    HomeworkScheduleDto? schedule,
  }) = _HomeworkDto;

  factory HomeworkDto.fromJson(Map<String, dynamic> json) => _$HomeworkDtoFromJson(json);
}

/// reps는 백엔드가 숫자(12)로 주든 문자열("12" / "10-12")로 주든 안전하게 문자열화.
String? _repsToString(Object? value) => value?.toString();

@freezed
abstract class HomeworkItemDto with _$HomeworkItemDto {
  const factory HomeworkItemDto({
    required String name,
    int? sets,
    @JsonKey(fromJson: _repsToString) String? reps,
    String? note,
  }) = _HomeworkItemDto;

  factory HomeworkItemDto.fromJson(Map<String, dynamic> json) => _$HomeworkItemDtoFromJson(json);
}

@freezed
abstract class HomeworkScheduleDto with _$HomeworkScheduleDto {
  const factory HomeworkScheduleDto({
    @Default('weekly') String type, // once|weekly
    @Default(<String>[]) List<String> days,
    String? from,
    String? to,
  }) = _HomeworkScheduleDto;

  factory HomeworkScheduleDto.fromJson(Map<String, dynamic> json) =>
      _$HomeworkScheduleDtoFromJson(json);
}

/// API계약_v1.md — HwCheck 엔티티(회원 체크 상태).
@freezed
abstract class HwCheckDto with _$HwCheckDto {
  const factory HwCheckDto({
    @JsonKey(name: 'member_id') required String memberId,
    @JsonKey(name: 'hw_id') required String hwId,
    required String date,
    @Default(<bool>[]) List<bool> done,
  }) = _HwCheckDto;

  factory HwCheckDto.fromJson(Map<String, dynamic> json) => _$HwCheckDtoFromJson(json);
}
