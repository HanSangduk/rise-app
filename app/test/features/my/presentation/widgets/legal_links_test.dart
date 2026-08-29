// 앱 안 약관 접근(P26).
//
// 스토어 메타데이터의 처리방침 URL만으로는 부족하다 — Apple 5.1.1(i)·Play 모두 앱
// **안에서** 접근 가능할 것을 본다. 이 앱은 인바디·체형사진이라는 민감정보를 다루므로
// 동의의 근거 문서를 회원이 언제든 다시 읽을 수 있어야 한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/config/legal_links.dart';
import 'package:rise_member/features/my/presentation/widgets/legal_links_card.dart';

void main() {
  group('약관 카드', () {
    testWidgets('네 문서가 모두 행으로 있다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LegalLinksCard())),
      );

      expect(find.text('이용약관'), findsOneWidget);
      expect(find.text('개인정보처리방침'), findsOneWidget);
      expect(find.text('민감정보(인바디·체형사진) 처리 안내'), findsOneWidget);
      expect(find.text('계정·데이터 삭제 안내'), findsOneWidget);
    });

    testWidgets('좁은 실기기 폭(360dp)에서 넘치지 않는다', (tester) async {
      // 민감정보 행 라벨이 길다 — 기본 800dp 테스트 화면에서는 안 터진다.
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LegalLinksCard())),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('주소', () {
    test('확장자까지 쓴 주소다 — 떼면 어드민 SPA로 떨어진다', () {
      // Hosting은 정적 파일을 `**` → /index.html 폴백보다 먼저 매칭한다.
      for (final url in [
        LegalLinks.terms,
        LegalLinks.privacy,
        LegalLinks.sensitiveConsent,
        LegalLinks.accountDeletion,
      ]) {
        expect(url, endsWith('.html'), reason: '$url — 확장자가 없으면 SPA 폴백');
        expect(url, startsWith('https://'), reason: '$url — 법정 고지 문서를 평문으로 보내면 안 된다');
      }
    });

    test('네 주소가 서로 다르다 — 복붙 실수로 같은 문서를 가리키지 않게', () {
      final urls = {
        LegalLinks.terms,
        LegalLinks.privacy,
        LegalLinks.sensitiveConsent,
        LegalLinks.accountDeletion,
      };
      expect(urls.length, 4);
    });
  });
}
