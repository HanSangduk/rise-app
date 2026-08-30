// 계약서 본문 뷰(P39) — 모델→위젯 매핑 스모크 + 실기기 폭(360dp) 레이아웃 가드.
//
// 픽셀 골든이 아니라 구조·텍스트 존재 검증인 이유: 하우스에 이미지 골든 선례가 없고
// (matchesGoldenFile 0건), 이 뷰의 계약은 "모델의 모든 블록이 넘치지 않고 그려진다"다.
// 폰트는 번들 Pretendard를 실제 로드한다 — 폴백 폰트는 줄높이가 달라 실기기에서만
// 나는 1px 오버플로를 재현하지 못한 P09 선례(test/support/font_loader.dart 주석).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/my/domain/contract_render_model.dart';
import 'package:rise_member/features/my/domain/contract_template_renderer.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_document_view.dart';

import '../../../../support/contract_render_fixture.dart';
import '../../../../support/font_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String template;

  setUpAll(() async {
    await loadPretendard();
    // 레이아웃 가드는 reported로 고정한다(P42) — exempt는 당사자 표가 한 행 적고
    // 몇 문단이 더 짧을 뿐 새로운 블록 형태가 없어, reported가 레이아웃 상한이다.
    template = await rootBundle.loadString('assets/legal/contract_pt_v1_reported.md');
  });

  ContractDocument doc({String? t, Map<String, String>? vars, Map<String, String>? entityVars}) {
    final o = ContractTemplateRenderer.render(
      template: t ?? template,
      vars: vars ?? contractReportedVarsFixture,
      entityVars: entityVars ?? contractEntityVarsFixture,
    );
    if (o is ContractRenderRefused) fail('렌더 거부: ${o.reason}');
    return (o as ContractRenderReady).document;
  }

  Future<void> pump(WidgetTester tester, ContractDocument d) {
    // 스크롤은 호출자 몫(뷰 주석) — 시트가 할 일을 테스트가 대신한다.
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Pretendard'),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ContractDocumentView(document: d),
          ),
        ),
      ),
    );
  }

  testWidgets('전문 142블록(pt-v1-reported)이 360dp 폭에서 오버플로 없이 그려진다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester, doc());

    // Column은 게으르지 않다 — 접힘 없이 전 블록이 레이아웃되므로, 셀 안 장문·
    // 여러 줄 납부일정·[별지] 서식까지 넘침이 있으면 여기서 예외가 난다.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('퍼스널 트레이닝(PT) 이용계약서', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('제23조 (계약서의 교부와 약관)', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('라이즈 컨디셔닝', findRichText: true), findsWidgets);
    // 표 셀 여러 줄 값(납부일정)도 그려진다.
    expect(find.textContaining('납부예정', findRichText: true), findsWidgets);
  });

  testWidgets('빈 헤더 표(서명란)는 헤더 행 없이, 값 있는 헤더는 헤더 행과 함께 그린다',
      (tester) async {
    // 서명란형 — 헤더가 전부 빈 표.
    await pump(
      tester,
      doc(
        t: '| | |\n|---|---|\n| 센터 | 라이즈 컨디셔닝 대표 김대표 (인) |\n| 회원 | 홍길동 (서명) |',
        vars: const {},
        entityVars: const {},
      ),
    );
    var table = tester.widget<Table>(find.byType(Table));
    expect(table.children, hasLength(2)); // 본문 2행뿐 — 빈 회색 헤더 띠를 만들지 않는다.
    expect(table.children.first.decoration, isNull);

    // 라벨형 — 헤더가 있는 표는 헤더 행(배경 장식)이 첫 행이다.
    await pump(
      tester,
      doc(t: '| 구분 | 내용 |\n|---|---|\n| 상호 | 라이즈 컨디셔닝 |', vars: const {}, entityVars: const {}),
    );
    table = tester.widget<Table>(find.byType(Table));
    expect(table.children, hasLength(2)); // 헤더 1 + 본문 1.
    expect(table.children.first.decoration, isNotNull);
    expect(tester.takeException(), isNull);
  });

  group('서명란 도킹 블록(P44 결정 4) — 마지막 표 직하단, 기본값은 0 변화', () {
    // 서명란 표(마지막 표) 뒤에 [별지]류 블록이 이어지는 축소 문서 — 도킹 위치가
    // "마지막 표 뒤 · 다음 블록 앞"임을 순서로 잰다.
    const miniDoc = '| 구분 | 내용 |\n|---|---|\n| 상호 | 라이즈 |\n\n'
        '중간 문단입니다.\n\n'
        '| | |\n|---|---|\n| 회원 | 홍길동 (서명) |\n\n'
        '## [별지] 서식\n\n```\n서식 본문\n```';

    testWidgets('블록이 마지막 표 바로 뒤에 선다 — 첫 표도, 문서 끝도 아니다', (tester) async {
      const key = Key('sig-block');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Pretendard'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ContractDocumentView(
                document: doc(t: miniDoc, vars: const {}, entityVars: const {}),
                signatureBlock: const SizedBox(key: key, height: 40),
              ),
            ),
          ),
        ),
      );

      final tables = tester.widgetList(find.byType(Table)).toList();
      expect(tables, hasLength(2), reason: '축소 문서 전제 — 표 2개');
      final lastTableBottom = tester.getBottomLeft(find.byType(Table).last).dy;
      final blockTop = tester.getTopLeft(find.byKey(key)).dy;
      final annexTop = tester.getTopLeft(find.text('[별지] 서식')).dy;
      expect(blockTop, greaterThanOrEqualTo(lastTableBottom),
          reason: '서명란 표(마지막 표) 아래여야 한다');
      expect(blockTop, lessThan(annexTop),
          reason: '[별지] 앞이어야 한다 — 문서 끝에 붙으면 서명란과 떨어진다');
    });

    testWidgets('signatureBlock 기본값(null) — 위젯 트리에 아무것도 더해지지 않는다', (tester) async {
      const key = Key('sig-block');
      await pump(tester, doc(t: miniDoc, vars: const {}, entityVars: const {}));
      expect(find.byKey(key), findsNothing);
    });

    testWidgets('표 없는 문서(방어) — 끝에 붙는다: 자리를 못 찾아도 서명을 숨기지 않는다', (tester) async {
      const key = Key('sig-block');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Pretendard'),
          home: Scaffold(
            body: ContractDocumentView(
              document: doc(t: '문단 하나뿐입니다.', vars: const {}, entityVars: const {}),
              signatureBlock: const SizedBox(key: key, height: 40),
            ),
          ),
        ),
      );
      final paraBottom =
          tester.getBottomLeft(find.text('문단 하나뿐입니다.')).dy;
      expect(tester.getTopLeft(find.byKey(key)).dy, greaterThanOrEqualTo(paraBottom));
    });
  });

  testWidgets('서식 블록([별지])은 가로 스크롤 컨테이너 안에서 원문 배치 그대로다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      doc(
        t: '```\n  받는 사람   {{사업자명}}  (   {{대표 이메일}}  /  {{대표 전화}}  )\n```',
        vars: const {
          '사업자명': '라이즈 컨디셔닝',
          '대표 이메일': 'hello@rise.example',
          '대표 전화': '02-1234-5678',
        },
        entityVars: const {},
      ),
    );
    expect(tester.takeException(), isNull);
    // 좁은 폭에서 줄바꿈 대신 가로 스크롤 — 서식 칸이 뭉개지지 않는다.
    final scrolls = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((s) => s.scrollDirection == Axis.horizontal);
    expect(scrolls, hasLength(1));
    expect(
      find.textContaining('받는 사람   라이즈 컨디셔닝', findRichText: true),
      findsOneWidget,
    );
  });
}
