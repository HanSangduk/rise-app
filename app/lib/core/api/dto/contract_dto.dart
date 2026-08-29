import 'package:freezed_annotation/freezed_annotation.dart';

part 'contract_dto.freezed.dart';
part 'contract_dto.g.dart';

/// API계약 v1.1 — Contract 엔티티(전자계약).
/// {id, member_id, pass_id, product, paid_amount, penalty_rate,
///  status:"draft|sent|signed|voided", sent_at, first_sent_at, signed_at,
///  signer_ip, sha256, pdf_path}
/// v1.5: penalty_rate(생성 시점 위약금율 스냅샷)·first_sent_at(최초 발송 증적)·
/// voided(환불 시 미서명 계약 자동 무효 — 종단 상태, 서명·발송 400) 추가.
@freezed
abstract class ContractDto with _$ContractDto {
  const factory ContractDto({
    required String id,
    @JsonKey(name: 'member_id') required String memberId,
    @JsonKey(name: 'pass_id') required String passId,
    required String product,
    @JsonKey(name: 'paid_amount') required int paidAmount,
    // v1.5 이전 서버 응답엔 없을 수 있어 nullable — 회원 앱은 표시에 안 쓰고 파싱 안전만 보장.
    @JsonKey(name: 'penalty_rate') double? penaltyRate,
    @Default('draft') String status, // draft|sent|signed|voided
    @JsonKey(name: 'sent_at') String? sentAt,
    @JsonKey(name: 'first_sent_at') String? firstSentAt,
    @JsonKey(name: 'signed_at') String? signedAt,
    @JsonKey(name: 'signer_ip') String? signerIp,
    String? sha256,
    @JsonKey(name: 'pdf_path') String? pdfPath,
  }) = _ContractDto;

  factory ContractDto.fromJson(Map<String, dynamic> json) => _$ContractDtoFromJson(json);
}
