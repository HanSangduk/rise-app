// 버전 표(P39·P42) — 표 자체를 못박는다: 변형 2종이 각자 자산으로 가고, 폐기·미지
// 버전은 null이다(호출자는 §D ④ 업데이트 안내로 폴백). 자산이 진짜 번들에 있는지는
// 렌더러 골든의 rootBundle 로드가, 시트가 표를 따라가는지는 시트 테스트가 덮는다.

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/my/domain/contract_templates.dart';

void main() {
  test('변형 2종(P42)이 각자 자산 경로로 간다 — 신고 상태 선언이 버전을 고른다', () {
    expect(
      ContractTemplates.assetPathFor('pt-v1-reported'),
      'assets/legal/contract_pt_v1_reported.md',
    );
    expect(
      ContractTemplates.assetPathFor('pt-v1-exempt'),
      'assets/legal/contract_pt_v1_exempt.md',
    );
    expect(ContractTemplates.assetByVersion, hasLength(2));
  });

  test('폐기된 pt-v1은 더 이상 렌더하지 않는다 — 스탬프 이력 0이라 지울 수 있었다(P42)', () {
    // "지난 버전은 지우지 않는다"(전자문서법 §5①2 재현 의무)의 예외가 아니라
    // 적용 대상 부재다: 래치가 한 번도 안 켜져 pt-v1로 서명된 문서가 없다.
    expect(ContractTemplates.assetPathFor('pt-v1'), isNull);
  });

  test('미지 버전은 null — 업데이트 안내 폴백(§D ④ :916-917)', () {
    expect(ContractTemplates.assetPathFor('pt-v99'), isNull);
  });
}
