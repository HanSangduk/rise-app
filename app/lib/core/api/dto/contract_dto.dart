import 'package:freezed_annotation/freezed_annotation.dart';

part 'contract_dto.freezed.dart';
part 'contract_dto.g.dart';

/// API계약 v1.1 — Contract 엔티티(전자계약).
/// {id, member_id, pass_id, product, paid_amount, penalty_rate,
///  status:"draft|sent|signed|voided", sent_at, first_sent_at, signed_at,
///  signer_ip, sha256, pdf_path, template_version, vars}
/// v1.5: penalty_rate(생성 시점 위약금율 스냅샷)·first_sent_at(최초 발송 증적)·
/// voided(환불 시 미서명 계약 자동 무효 — 종단 상태, 서명·발송 400) 추가.
/// v2.18(P39): template_version(send가 확정한 계약서 템플릿 버전)·vars(슬롯→값 스냅샷).
/// 순수 additive — 스탬프 전(시설 미선언·사업자 정보 미등록)·레거시는 둘 다 빈 값이고,
/// 그때 앱은 요약 고지 경로를 그대로 탄다(§D ⑥ 레거시 분기와 동일).
/// P44: signature_png(자필 서명 PNG base64)·signature_sha256(서명 이미지 해시 —
/// 문서 sha256과 **별개**의 해시, 결정 3). omitempty 금지(결정 2) — 빈 문자열 =
/// 서명 이미지 없음(레거시·구버전 앱의 체크 동의 서명 전부).
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
    // v2.18 — 빈 문자열 = 스탬프 전(래치 OFF 동안의 계약·레거시 전부). 부재 허용.
    @JsonKey(name: 'template_version') @Default('') String templateVersion,
    // v2.18 — sha256이 봉인하는 Vars 스냅샷. 파싱 규약은 [_contractVarsFromJson] 참조.
    @JsonKey(fromJson: _contractVarsFromJson)
    @Default(<String, String>{})
    Map<String, String> vars,
    // P44 — 자필 서명 증적 2필드. 부재 허용(구서버 응답)이며 그때도 빈 값과 같은
    // "이미지 없음" 경로다(template_version과 같은 additive 규약).
    @JsonKey(name: 'signature_png') @Default('') String signaturePng,
    @JsonKey(name: 'signature_sha256') @Default('') String signatureSha256,
  }) = _ContractDto;

  factory ContractDto.fromJson(Map<String, dynamic> json) => _$ContractDtoFromJson(json);
}

/// vars 파싱 안전 — 계약(v2.18)상 값은 전부 string이지만, 숫자가 와도 안전하게
/// 문자열화한다(homework reps의 `_repsToString`과 같은 방어 규약).
/// · map이 아니면 통째로 빈 맵 — 부재와 같은 "스냅샷 없음"(요약 고지) 경로로 떨어진다.
/// · 값이 null인 키는 버린다 — "null"이 계약서 본문에 인쇄되느니, 렌더러가
///   MissingVars로 정직하게 거부하고 요약 경로로 폴백하는 편이 낫다(부재 우선).
Map<String, String> _contractVarsFromJson(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final e in value.entries)
      if (e.value != null) e.key.toString(): e.value.toString(),
  };
}
