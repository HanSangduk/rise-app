import 'package:flutter/material.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:url_launcher/url_launcher.dart';

/// 법정 고지 문서(약관·처리방침 등, [LegalLinks])를 **외부 브라우저**로 연다.
///
/// 마이 탭의 약관 카드(`legal_links_card.dart`)와 로그인 전 화면(대기실 하단 링크,
/// P56 B5)이 같은 함수를 쓴다 — 여는 방식과 실패 처리가 화면마다 갈리면, 한쪽에서만
/// 브라우저 실패가 조용히 삼켜지는 종류의 비일관이 생긴다.
///
/// 외부 브라우저인 이유(웹뷰 아님): 회원이 주소창으로 출처를 확인하고 저장·공유할 수
/// 있어야 하고, 문서 안의 외부 링크(분쟁조정위·KISA)까지 앱이 떠안지 않기 위해서다.
///
/// 브라우저가 없거나 거절하면 **조용히 실패하지 않는다.** 법정 고지 문서로 가는 길이
/// 막혔다는 건 회원이 알아야 할 사실이고, 아무 반응 없는 행은 앱이 고장 난 것으로
/// 보인다. 주소를 함께 띄워 다른 기기에서라도 열 수 있게 한다.
Future<void> openLegalDocument(BuildContext context, String url) async {
  // 메신저는 await 전에 잡는다 — 돌아왔을 때 context가 죽어 있을 수 있다.
  final messenger = ScaffoldMessenger.of(context);
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (ok) return;
  messenger.showSnackBar(
    riseSnackBar('브라우저를 열지 못했어요 — 주소: $url', kind: RiseSnackKind.danger),
  );
}
