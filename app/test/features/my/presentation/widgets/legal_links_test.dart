// 앱 안 약관 접근(P26).
//
// 스토어 메타데이터의 처리방침 URL만으로는 부족하다 — Apple 5.1.1(i)·Play 모두 앱
// **안에서** 접근 가능할 것을 본다. 이 앱은 인바디·체형사진이라는 민감정보를 다루므로
// 동의의 근거 문서를 회원이 언제든 다시 읽을 수 있어야 한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/config/legal_links.dart';
import 'package:rise_member/features/my/presentation/widgets/legal_links_card.dart';

void main() {
  group('약관 카드', () {
    testWidgets('다섯 문서가 모두 행으로 있다', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: LegalLinksCard())),
        ),
      );

      // 운영자 방침과 센터 방침은 **다른 문서**다 — 라벨이 그것을 구분해야 회원이 어느 쪽을
      // 읽고 있는지 안다(여러 센터가 함께 쓰는 앱이다).
      expect(find.text('앱 개인정보처리방침 (운영자)'), findsOneWidget);
      expect(find.text('이용약관'), findsOneWidget);
      expect(find.text('개인정보처리방침 (센터)'), findsOneWidget);
      expect(find.text('민감정보(인바디·체형사진) 처리 안내'), findsOneWidget);
      expect(find.text('계정·데이터 삭제 안내'), findsOneWidget);
    });

    testWidgets('좁은 실기기 폭(360dp)에서 넘치지 않는다', (tester) async {
      // 민감정보 행 라벨이 길다 — 기본 800dp 테스트 화면에서는 안 터진다.
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: LegalLinksCard())),
        ),
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

  group('센터별 고지 (v2.33)', () {
    // 여러 센터가 이 앱을 쓴다. 법정 문서가 인쇄하는 개인정보처리자·삭제 요청 접수 창구는
    // 센터마다 다르므로, 센터를 안 실으면 **2호점 회원이 1호점의 고지를 읽고 그 연락처로
    // 삭제를 요청한다.**
    test('센터가 있으면 네 주소 모두에 실린다', () {
      final rows = legalRowsFor('gangnam-2');
      expect(rows, hasLength(5));
      // 운영자 방침만 센터가 붙지 않는다 — 운영자는 하나뿐이라 센터에 따라 달라지지 않는다.
      final operator = rows.firstWhere((r) => r.url.contains('app-privacy'));
      expect(operator.url, isNot(contains('center=')));
      for (final r in rows.where((r) => !r.url.contains('app-privacy'))) {
        expect(r.url, contains('?center=gangnam-2'), reason: '센터가 빠진 주소: ${r.url}');
      }
    });

    test('센터를 모르면 원래 주소 그대로 — 빈 파라미터는 서버가 404를 준다', () {
      for (final r in legalRowsFor('')) {
        expect(r.url, isNot(contains('center=')));
      }
    });

    testWidgets('카드가 세션의 센터를 읽는다', (tester) async {
      final container = ProviderContainer.test();
      container.read(sessionProvider.notifier).set(const AppSession(
            uid: 'u1',
            role: 'member',
            centerId: 'gangnam-2',
            memberId: 'mem_1',
          ));
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: LegalLinksCard())),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('개인정보처리방침 (센터)'), findsOneWidget);
    });
  });
}
