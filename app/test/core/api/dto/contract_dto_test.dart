import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/contract_dto.dart';

// P39/v2.18 — Contract.template_version/vars 파싱 규약.
//
// 순수 additive 필드라 **부재가 기본값**이고(래치 OFF 동안의 계약·레거시 전부),
// 부재·기형은 전부 "스냅샷 없음"(요약 고지 경로)으로 떨어져야 한다. 여기서 파싱이
// 죽으면 계약 하나 때문에 목록 전체가 contractsFailed로 넘어간다 — 방어 규약은
// homework reps(_repsToString)와 같은 자리다.
void main() {
  Map<String, dynamic> base() => {
        'id': 'c1',
        'member_id': 'm1',
        'pass_id': 'p1',
        'product': 'PT 20회',
        'paid_amount': 1200000,
        'status': 'sent',
      };

  group('ContractDto.fromJson — template_version/vars (v2.18)', () {
    test('둘 다 있으면 그대로 파싱 — 래치 ON 스탬프 형태', () {
      final dto = ContractDto.fromJson({
        ...base(),
        'first_sent_at': '2026-08-20T09:00:00Z',
        'template_version': 'pt-v1',
        'vars': {'회원명': '홍길동', '총 회차': '20'},
      });

      expect(dto.templateVersion, 'pt-v1');
      expect(dto.vars, {'회원명': '홍길동', '총 회차': '20'});
      expect(dto.firstSentAt, '2026-08-20T09:00:00Z');
    });

    test('부재 → 빈 값 — 스탬프 전(래치 OFF)·레거시 서버 응답 전부', () {
      final dto = ContractDto.fromJson(base());

      expect(dto.templateVersion, '');
      expect(dto.vars, isEmpty);
    });

    test('서버 규약 그대로의 빈 값(omitempty 없음)도 빈 값', () {
      // v2.18: 두 필드 모두 omitempty 없이 내려온다 — 스탬프 전엔 ""와 {}.
      final dto = ContractDto.fromJson({...base(), 'template_version': '', 'vars': {}});

      expect(dto.templateVersion, '');
      expect(dto.vars, isEmpty);
    });

    test('vars 값에 숫자가 와도 문자열화 — homework reps와 같은 방어', () {
      final dto = ContractDto.fromJson({
        ...base(),
        'template_version': 'pt-v1',
        'vars': {'총 회차': 20, '위약금율': 10.5, '회원명': '홍길동'},
      });

      expect(dto.vars, {'총 회차': '20', '위약금율': '10.5', '회원명': '홍길동'});
    });

    test('vars가 map이 아니면 통째로 빈 값 — 부재와 같은 경로, 목록은 살아남는다', () {
      expect(ContractDto.fromJson({...base(), 'vars': '이상한 문자열'}).vars, isEmpty);
      expect(ContractDto.fromJson({...base(), 'vars': ['배열']}).vars, isEmpty);
      expect(ContractDto.fromJson({...base(), 'vars': null}).vars, isEmpty);
    });

    test('vars의 null 값 키는 버린다 — "null"을 계약서에 인쇄하지 않는다', () {
      // 값이 null인 키를 "null" 문자열로 살리면 그대로 본문에 인쇄된다. 키를 버리면
      // 렌더러가 MissingVars로 정직하게 거부하고 요약 경로로 폴백한다(부재 우선).
      final dto = ContractDto.fromJson({
        ...base(),
        'template_version': 'pt-v1',
        'vars': {'회원명': null, '상품명': 'PT 20회'},
      });

      expect(dto.vars, {'상품명': 'PT 20회'});
      expect(dto.vars.containsKey('회원명'), isFalse);
    });
  });

  group('ContractDto.fromJson — signature_png/signature_sha256 (P44)', () {
    test('둘 다 있으면 그대로 파싱 — 자필 서명 계약', () {
      final dto = ContractDto.fromJson({
        ...base(),
        'status': 'signed',
        'signed_at': '2026-08-29T05:03:00Z',
        'signer_ip': '211.36.132.7',
        'sha256': 'a1b2',
        'signature_png': 'aVZCT1J3MEtHZ28=',
        'signature_sha256': 'f6e5',
      });

      expect(dto.signaturePng, 'aVZCT1J3MEtHZ28=');
      expect(dto.signatureSha256, 'f6e5');
      expect(dto.signerIp, '211.36.132.7');
      expect(dto.sha256, 'a1b2');
    });

    test('부재 → 빈 값 — 구서버 응답(additive 규약, template_version과 동형)', () {
      final dto = ContractDto.fromJson(base());

      expect(dto.signaturePng, '');
      expect(dto.signatureSha256, '');
    });

    test('서버 규약 그대로의 빈 값(omitempty 금지, 결정 2)도 빈 값', () {
      final dto = ContractDto.fromJson(
          {...base(), 'signature_png': '', 'signature_sha256': ''});

      expect(dto.signaturePng, '');
      expect(dto.signatureSha256, '');
    });
  });
}
