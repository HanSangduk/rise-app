import 'package:flutter/material.dart';
import 'package:rise_member/core/config/legal_links.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:url_launcher/url_launcher.dart';

/// 약관·처리방침 카드(P26).
///
/// **앱 안에 반드시 있어야 한다.** 스토어 메타데이터의 개인정보처리방침 URL만으로는
/// 부족하다 — Apple 5.1.1(i)·Play 모두 앱 내에서 접근 가능할 것을 본다. 특히 이 앱은
/// 인바디·체형사진이라는 민감정보를 다뤄 동의의 근거 문서를 회원이 언제든 다시 읽을
/// 수 있어야 한다.
///
/// 외부 브라우저로 연다(웹뷰 아님) — 회원이 주소창으로 출처를 확인하고 저장·공유할 수
/// 있어야 하고, 문서 안의 외부 링크(분쟁조정위·KISA)까지 앱이 떠안지 않기 위해서다.
class LegalLinksCard extends StatelessWidget {
  const LegalLinksCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseCardHeader(title: '약관 · 방침'),
          _LegalRow('이용약관', LegalLinks.terms),
          _LegalRow('개인정보처리방침', LegalLinks.privacy),
          _LegalRow('민감정보(인바디·체형사진) 처리 안내', LegalLinks.sensitiveConsent),
          _LegalRow('계정·데이터 삭제 안내', LegalLinks.accountDeletion, last: true),
        ],
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  const _LegalRow(this.label, this.url, {this.last = false});

  final String label;
  final String url;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: RiseRow(
        showDivider: !last,
        minHeight: 44,
        child: Text(label),
        trailing: const RiseIcon(
          RiseIcons.chevronRight,
          size: 14,
          color: AppColors.muted,
        ),
      ),
    );
  }

  /// 브라우저가 없거나 거절하면 **조용히 실패하지 않는다**. 법정 고지 문서로 가는 길이
  /// 막혔다는 건 회원이 알아야 할 사실이고, 아무 반응 없는 행은 앱이 고장 난 것으로 보인다.
  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (ok) return;
    messenger.showSnackBar(
      riseSnackBar('브라우저를 열지 못했어요 — 주소: $url', kind: RiseSnackKind.danger),
    );
  }
}
