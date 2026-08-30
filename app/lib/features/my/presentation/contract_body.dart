// 계약서 본문 표시 판정(P39 시트 슬라이스) — 서명 시트와 상세 시트가 **같은 게이트**를
// 탄다: 스냅샷 유무 → 버전 인지 → 자산 로드 → 결정적 렌더. 판정이 두 시트에서 갈리면
// "서명 화면에서 본 문서"와 "나중에 상세에서 재현되는 문서"가 다른 경로로 만들어져
// D-4(서명 당시 문서의 재현)가 흔들린다.
//
// 자산 IO(AssetBundle)가 있어 도메인이 아니라 presentation에 둔다 — 렌더러·모델은
// Flutter 의존 0을 유지한다(랜딩된 렌더러 슬라이스의 경계를 그대로 존중).

import 'package:flutter/services.dart' show AssetBundle;
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/my/domain/contract_render_model.dart';
import 'package:rise_member/features/my/domain/contract_template_renderer.dart';
import 'package:rise_member/features/my/domain/contract_templates.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

/// 본문 표시 판정 결과 — sealed라 새 갈래가 생기면 두 시트의 switch가 컴파일로 막힌다.
sealed class ContractBodyState {
  const ContractBodyState();
}

/// 문서 스냅샷 없음(시설 미선언·사업자 정보 미등록으로 서버가 스탬프를 스킵한 계약,
/// 그리고 레거시 전부. 발행 래치 자체는 P48/v2.22부터 켜져 있다) — 요약 고지 화면 그대로,
/// 아무 표시도 더하지 않는다(§D ⑥ "없는 걸 있는 척하지 않는다").
final class ContractBodyNone extends ContractBodyState {
  const ContractBodyNone();
}

/// 자산 로드 중 — 한 프레임 남짓. 이 동안 서명 시트의 동의 게이트는 닫아 둔다:
/// 열어 뒀다가 문서가 도착하며 닫으면, 회원이 이미 체크한 동의가 풀리는 역행이 생긴다.
final class ContractBodyLoading extends ContractBodyState {
  const ContractBodyLoading();
}

/// 전문 렌더 가능 — [document]가 화면에 그릴 전부다.
final class ContractBodyReady extends ContractBodyState {
  const ContractBodyReady(this.document);

  final ContractDocument document;
}

/// 서버가 이 앱이 모르는 버전을 스탬프했다 — 렌더 금지(§D ④ :916-917), 업데이트 안내.
/// 요약 고지 경로는 그대로 산다(전문 열람 불가가 서명을 막지 않는다).
final class ContractBodyNeedsAppUpdate extends ContractBodyState {
  const ContractBodyNeedsAppUpdate();
}

/// 스냅샷은 있는데 전문을 그릴 수 없다(렌더 거부·자산 결손) — 사실대로 한 줄 알리고
/// 요약 경로로 진행한다. 가짜 문서도, 조용한 숨김도 아니다(P33 정직 규약).
final class ContractBodyUnavailable extends ContractBodyState {
  const ContractBodyUnavailable();
}

/// [contract]의 문서 스냅샷으로 본문 표시를 판정한다.
///
/// [bundle]은 호출 위젯의 DefaultAssetBundle — 운영은 rootBundle 폴백이고,
/// 테스트는 가짜 번들로 짧은/깨진 템플릿을 주입한다.
Future<ContractBodyState> resolveContractBody({
  required AssetBundle bundle,
  required ContractItem contract,
}) async {
  if (!contract.hasDocumentSnapshot) return const ContractBodyNone();

  final assetPath = ContractTemplates.assetPathFor(contract.templateVersion);
  if (assetPath == null) return const ContractBodyNeedsAppUpdate();

  final String template;
  try {
    template = await bundle.loadString(assetPath);
  } catch (_) {
    // 표에 등록된 버전인데 자산이 안 열리는 건 빌드 결손 — 정직 고지로 폴백.
    return const ContractBodyUnavailable();
  }

  // {{계약 체결일}}은 Vars 밖(P39 결정 3) — sha256이 봉인하는 스냅샷이 아니라 sha256과
  // 같은 트랜잭션에 기록되는 엔티티 증적에서 렌더 시점에 온다: SignedAt, 미서명이면
  // FirstSentAt(계약서doc :781 표시 규칙). 둘 다 없으면(규약상 sent 이후엔 없을 수 없지만)
  // 키를 아예 넣지 않는다 — 렌더러가 MissingVars로 정직하게 거부하고 요약 경로로
  // 떨어진다. 지어낸 날짜로 채우지 않는다.
  //
  // 날짜는 **KST 벽시계**로 접는다(P44 마감 리뷰 H): 서버 증적은 UTC 순간이고, KST
  // 00~09시 서명은 UTC 날짜가 전날이다 — toKst 없이 isoDate를 찍으면 법적 문서의
  // 체결일과 바로 아래 체결 정보(서명 일시, toKst 적용)가 하루 어긋난다.
  final concludedAt = contract.signedAt ?? contract.firstSentAt;
  final outcome = ContractTemplateRenderer.render(
    template: template,
    vars: contract.vars,
    entityVars: {
      if (concludedAt != null) '계약 체결일': DateFmt.isoDate(DateFmt.toKst(concludedAt)),
    },
  );
  return switch (outcome) {
    ContractRenderReady(:final document) => ContractBodyReady(document),
    // 어떤 거부든(미지 문법·값 누락·원천 충돌) 회원에게는 같은 사실이다 —
    // "전문을 표시할 수 없다". 종류 구분은 refusal.reason으로 테스트·로그가 한다.
    ContractRenderRefused() => const ContractBodyUnavailable(),
  };
}
