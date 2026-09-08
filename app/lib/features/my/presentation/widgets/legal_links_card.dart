import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/config/legal_links.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/legal_document_link.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/widgets/rise_card.dart';

/// 약관·처리방침 카드(P26).
///
/// **앱 안에 반드시 있어야 한다.** 스토어 메타데이터의 개인정보처리방침 URL만으로는
/// 부족하다 — Apple 5.1.1(i)·Play 모두 앱 내에서 접근 가능할 것을 본다. 특히 이 앱은
/// 인바디·체형사진이라는 민감정보를 다뤄 동의의 근거 문서를 회원이 언제든 다시 읽을
/// 수 있어야 한다.
///
/// 여는 방식(외부 브라우저 + 실패 시 주소를 띄우는 스낵바)은 [openLegalDocument]에
/// 있다 — 로그인 전 화면(대기실)도 같은 함수로 연다(P56 B5). 여기 카드는 셸 안
/// 마이 탭 전용이고, 그 화면들은 회원 데이터 없이도 문서에 닿아야 한다.
class LegalLinksCard extends ConsumerWidget {
  const LegalLinksCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **자기 센터의 고지를 연다**(계약 v2.33). 여러 센터가 이 앱을 쓰므로 개인정보처리자와
    // 삭제 요청 접수 창구가 센터마다 다르다 — 센터를 안 싣으면 2호점 회원이 1호점의 법정
    // 고지를 읽게 되고, 그 문서에 적힌 연락처로 삭제를 요청하면 남의 센터로 간다.
    final rows = legalRowsFor(ref.watch(sessionProvider)?.centerId ?? '');

    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseCardHeader(title: '약관 · 방침'),
          for (final (i, row) in rows.indexed)
            _LegalRow(row.label, row.url, last: i == rows.length - 1),
        ],
      ),
    );
  }
}

/// 약관 카드 한 줄 — 라벨과 주소.
typedef LegalRow = ({String label, String url});

/// 이 회원이 열어야 할 법정 문서 4종(계약 v2.33).
///
/// **순수 함수로 뽑아 둔 이유**: 센터가 주소에 실리는지가 이 카드의 유일한 로직인데, 위젯
/// 안에 두면 그걸 확인할 방법이 "탭해서 브라우저가 열리는지" 뿐이라 테스트가 못 잡는다.
/// 실제로 센터를 빠뜨리면 **2호점 회원이 1호점의 개인정보처리방침을 읽고 그 연락처로 삭제를
/// 요청하게 된다** — 조용히 틀리는 종류라 단언으로 고정한다.
@visibleForTesting
List<LegalRow> legalRowsFor(String centerId) {
  String at(String base) => LegalLinks.forCenter(base, centerId);
  return [
    // 운영자 방침은 **센터를 붙이지 않는다** — 운영자가 하나뿐이라 센터에 따라 달라지지 않는다.
    (label: '앱 개인정보처리방침 (운영자)', url: LegalLinks.appPrivacy),
    (label: '이용약관', url: at(LegalLinks.terms)),
    (label: '개인정보처리방침 (센터)', url: at(LegalLinks.privacy)),
    (label: '민감정보(인바디·체형사진) 처리 안내', url: at(LegalLinks.sensitiveConsent)),
    (label: '계정·데이터 삭제 안내', url: at(LegalLinks.accountDeletion)),
  ];
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
      onTap: () => openLegalDocument(context, url),
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
}
