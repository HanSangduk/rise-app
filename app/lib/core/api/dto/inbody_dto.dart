import 'package:freezed_annotation/freezed_annotation.dart';

part 'inbody_dto.freezed.dart';
part 'inbody_dto.g.dart';

/// API계약_v1.md — Inbody 엔티티.
@freezed
abstract class InbodyDto with _$InbodyDto {
  const factory InbodyDto({
    required String id,
    @JsonKey(name: 'member_id') required String memberId,
    required String date,
    required double weight,
    required double smm, // 골격근량
    required double bfm, // 체지방량
    required double pbf, // 체지방률
    required double vfl, // 내장지방레벨
    required double bmr, // 기초대사량

    /// 출처(`member_self` = 회원 본인 입력 / 그 외 = 코치·어드민).
    ///
    /// **반드시 nullable.** 서버가 이 필드를 채우기 전에 저장된 레코드에는 키가
    /// 아예 없어서, required로 두면 그 전부가 fromJson에서 던진다 — 인바디 파싱
    /// 실패 1건이 기록 탭 셋(운동·인바디·체형)을 통째로 죽인 전례가 이미 있다
    /// (`records_repository_impl.dart`의 날짜 가드 주석).
    ///
    /// 응답 파싱 전용이다. 생성 요청 바디에는 넣지 않는다 — 서버 `decodeJSON`이
    /// `DisallowUnknownFields`라 미지 필드는 400이고, 출처는 서버가 Principal로
    /// 판정하는 값이라 클라이언트가 주장할 성질이 아니다.
    String? source,
  }) = _InbodyDto;

  factory InbodyDto.fromJson(Map<String, dynamic> json) => _$InbodyDtoFromJson(json);
}
