import 'package:freezed_annotation/freezed_annotation.dart';

part 'consult_request_dto.freezed.dart';
part 'consult_request_dto.g.dart';

/// 재등록/상담 요청(계약 v2.20) — 회원 응답에는 member_name이 없다(자기 것만 보므로).
@freezed
abstract class ConsultRequestDto with _$ConsultRequestDto {
  const ConsultRequestDto._();

  const factory ConsultRequestDto({
    required String id,
    @Default('renewal') String kind, // renewal|consult
    @Default('') String note,
    @Default('pending') String status, // pending|done
    @JsonKey(name: 'created_at') String? createdAt,
  }) = _ConsultRequestDto;

  factory ConsultRequestDto.fromJson(Map<String, dynamic> json) =>
      _$ConsultRequestDtoFromJson(json);

  /// pending일 때만 true — 미지값은 "진행 중 아님"으로 승격(StaffDto.isInactive와
  /// 같은 방향: 모르는 값으로 살아 있는 요청을 지어내지 않는다).
  bool get isPending => status == 'pending';
}
