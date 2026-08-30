// 순수 도메인 — 이 앱 빌드가 렌더할 줄 아는 계약서 템플릿 버전 → 번들 자산 경로.
//
// 서버가 스탬프한 template_version(v2.18)이 이 표 밖이면 **렌더하지 않는다** —
// 모르는 버전을 손에 있는 최신 템플릿으로 렌더하면 조용히 틀린 문서를 보여주게 된다
// (계약서doc §D ④ :916-917). 그때 시트는 "앱을 업데이트하면 전문을 열람할 수 있어요"
// 안내로 폴백하고, 요약 고지 경로(P28이 적법화한 기준선)는 그대로 산다 — 전문 열람
// 불가가 서명 자체를 막지는 않는다.
abstract final class ContractTemplates {
  /// 버전 → 자산 경로. 새 버전은 자산 번들 + pubspec 등록과 **같은 변경**에서만
  /// 늘린다 — 표에는 있는데 자산이 없는 버전은 빌드 결손이다.
  ///
  /// 변형 2종(P42) — 서식 취향이 아니라 **시설 신고 상태 선언**이 버전을 고른다:
  /// reported(신고번호 행 유지) / exempt(신고번호 행·체육시설법 인용 제거, §D-5).
  /// 상태 unknown이면 서버가 스탬프를 스킵하므로 여기 올 버전 자체가 없다.
  /// 초기 pt-v1은 폐기 — 폐기 시점까지 발행 래치가 한 번도 안 켜져 스탬프 이력 0이라, "지난
  /// 버전은 지우지 않는다"는 재현 원칙(전자문서법 §5①2)이 걸릴 문서가 없다.
  static const assetByVersion = <String, String>{
    'pt-v1-reported': 'assets/legal/contract_pt_v1_reported.md',
    'pt-v1-exempt': 'assets/legal/contract_pt_v1_exempt.md',
  };

  /// 모르는 버전이면 null — 호출자는 §D ④의 업데이트 안내로 폴백한다.
  static String? assetPathFor(String templateVersion) => assetByVersion[templateVersion];
}
