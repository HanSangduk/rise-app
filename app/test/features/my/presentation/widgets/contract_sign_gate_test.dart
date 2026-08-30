// 서명 시트 전문 게이트(P39 §D ⑤) — 문서 스냅샷(template_version+vars, v2.18)이
// 있으면 요약 위에 전문이 뜨고, **끝까지 스크롤해야** 동의 체크박스가 열린다.
//
// 지키는 것 두 가지:
//   · 전문이 뜨는 순간에도 P28 요약 고지(위약금율·정산 박스·약관 링크)는 전부
//     그대로다 — 전문은 요약을 대체하지 않고 위에 얹힌다(적법 기준선).
//   · 전문을 못 그리는 어떤 경우(미지 버전·값 누락·스냅샷 없음)에도 서명 자체는
//     막히지 않는다 — 요약 고지 서명이 오늘의 정상 경로다(§D ④, P39 결정 1).
//
// 게이트 분기는 가짜 번들(FakeAssetBundle)로 몇 줄짜리 템플릿을 주입해 결정적으로
// 검증하고, 실자산(pt-v1-reported) 렌더는 첫 테스트가 rootBundle 그대로 통합 검증한다.
// 시트는 버전 표(ContractTemplates)만 보므로 변형 선택 로직이 따로 없다 — exempt
// 자산 렌더는 렌더러 골든이, 표 매핑은 contract_templates_test가 덮는다(P42).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_document_view.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_sign_sheet.dart';

import '../../../../support/contract_render_fixture.dart';
import '../../../../support/fake_asset_bundle.dart';
import '../../../../support/font_loader.dart';

void main() {
  setUpAll(loadPretendard);

  ContractItem docContract({
    String templateVersion = 'pt-v1-reported',
    Map<String, String> vars = contractReportedVarsFixture,
    DateTime? signedAt,
  }) =>
      ContractItem(
        id: 'c-doc',
        passId: 'p1',
        product: 'PT 20회',
        paidAmount: 1200000,
        status: 'sent',
        penaltyRate: 0.1,
        // 미서명이므로 {{계약 체결일}}은 이 값으로 렌더돼야 한다(계약서doc :781).
        firstSentAt: DateTime(2026, 8, 20),
        signedAt: signedAt,
        templateVersion: templateVersion,
        vars: vars,
      );

  Future<void> openSign(WidgetTester tester, ContractItem c, {FakeAssetBundle? bundle}) async {
    Widget app = ProviderScope(
      overrides: [
        centerPolicyProvider.overrideWith((ref) async => const CenterPolicy(
              slotCapacity: 3,
              cancelCutoffHours: 24,
              graceOnce: true,
              penaltyRate: 0.05,
              expiringDays: 7,
              maxHoldsPerPass: 2,
              maxHoldTotalDays: 30,
            )),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Pretendard'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showContractSignSheet(context, contract: c),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    // 시트는 루트 Navigator 아래(MaterialApp 하위)에 뜨므로, 번들 래퍼는 MaterialApp
    // 바깥이면 어디든 조상이다 — 운영은 래퍼가 없어 rootBundle로 폴백한다.
    if (bundle != null) {
      app = DefaultAssetBundle(bundle: bundle, child: app);
    }
    await tester.pumpWidget(app);
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  CheckboxListTile checkbox(WidgetTester t) =>
      t.widget<CheckboxListTile>(find.byType(CheckboxListTile));

  RiseButton signButton(WidgetTester t) => t.widget<RiseButton>(find.byType(RiseButton));

  // 전문 세로 스크롤러 — [별지] 서식 블록의 **가로** 스크롤러와 구분한다.
  // 함수인 이유: FinderBase는 평가 결과를 캐시하므로 인스턴스를 테스트 간 재사용하면
  // 이전 트리의 결과(0개)를 물고 온다 — 쓸 때마다 새로 만든다.
  Finder docScroller() => find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.vertical);

  group('전문 스크롤 게이트 — 끝까지 읽어야 동의할 수 있다(§D ⑤)', () {
    testWidgets('실자산 pt-v1-reported 전문이 뜨고, 끝까지 스크롤하기 전엔 체크박스가 잠긴다', (tester) async {
      // 실기기 폭 — 전문이 뷰포트보다 길어 스크롤이 강제되는 조건.
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await openSign(tester, docContract()); // 번들 주입 없음 → 진짜 자산(rootBundle)

      // 전문이 진짜로 떴다 — 자산의 표제와 뷰가 존재한다.
      expect(find.text('퍼스널 트레이닝(PT) 이용계약서'), findsOneWidget);
      expect(find.byType(ContractDocumentView), findsOneWidget);
      // P28 요약 고지는 전문이 떠도 전부 그대로다(적법 기준선).
      expect(find.text('중도 해지 위약금'), findsWidgets);
      expect(find.textContaining('해지하면 이렇게 정산돼요'), findsWidgets);
      expect(find.text('이용약관 전문 보기'), findsOneWidget);
      // 아직 끝까지 안 읽음 — 체크박스 잠김 + 잠긴 이유 한 줄.
      expect(checkbox(tester).onChanged, isNull,
          reason: '끝까지 읽기 전에 동의가 열리면 §D ⑤ 게이트가 없는 것이다');
      expect(find.text('전문을 끝까지 읽으면 동의할 수 있어요'), findsOneWidget);
      expect(signButton(tester).onPressed, isNull);

      // 끝까지 스크롤(클램핑 물리라 한 번의 큰 드래그가 maxScrollExtent에 닿는다).
      await tester.drag(docScroller(), const Offset(0, -100000));
      await tester.pumpAndSettle();

      expect(checkbox(tester).onChanged, isNotNull);
      expect(find.text('전문을 끝까지 읽으면 동의할 수 있어요'), findsNothing);

      // 읽음 → 체크 → 서명 버튼 활성(서명 API 자체는 이 테스트 영역 밖).
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(checkbox(tester).value, isTrue);
      expect(signButton(tester).onPressed, isNotNull);
    });

    testWidgets('끝까지 읽으면 위로 되감아도 게이트는 열려 있다 — 래치', (tester) async {
      // 실자산 rootBundle은 이 파일에서 첫 테스트만 쓴다 — CachingAssetBundle의
      // 캐시 Future가 이전 테스트의 FakeAsync 존에 묶여, 두 번째 testWidgets의
      // 캐시 히트는 pump 안에서 완료되지 않는다(운영엔 FakeAsync가 없어 무영향,
      // 프로브로 실증). 여기선 긴 가짜 템플릿으로 스크롤을 강제한다 — 새
      // FakeAssetBundle 인스턴스라 캐시도 테스트마다 독립이다.
      final longTemplate =
          List.generate(80, (i) => '제${i + 1}문단. 스크롤을 강제하기 위한 본문입니다.\n').join('\n');
      final bundle = FakeAssetBundle({'assets/legal/contract_pt_v1_reported.md': longTemplate});

      await openSign(tester, docContract(), bundle: bundle);

      expect(checkbox(tester).onChanged, isNull,
          reason: '뷰포트보다 긴 문서는 스크롤 전 잠겨 있어야 래치 검증이 성립한다');
      await tester.drag(docScroller(), const Offset(0, -100000));
      await tester.pumpAndSettle();
      expect(checkbox(tester).onChanged, isNotNull);

      // 맨 위로 되감기 — "끝까지 본 사실"은 사라지지 않는다.
      await tester.drag(docScroller(), const Offset(0, 100000));
      await tester.pumpAndSettle();

      expect(checkbox(tester).onChanged, isNotNull);
      expect(find.text('전문을 끝까지 읽으면 동의할 수 있어요'), findsNothing);
    });

    testWidgets('문서가 뷰포트보다 짧으면 읽은 것으로 친다 — 첫 레이아웃 판정', (tester) async {
      final bundle = FakeAssetBundle({
        'assets/legal/contract_pt_v1_reported.md': '## 짧은 계약\n\n한 문단짜리 계약서입니다.\n',
      });

      await openSign(tester, docContract(), bundle: bundle);

      expect(find.text('짧은 계약'), findsOneWidget);
      expect(checkbox(tester).onChanged, isNotNull,
          reason: '스크롤할 것이 없는 문서는 첫 레이아웃에서 바로 읽음 처리돼야 한다 — '
              '아니면 짧은 계약서는 영원히 동의 불가다');
      expect(find.text('전문을 끝까지 읽으면 동의할 수 있어요'), findsNothing);
    });

    testWidgets('{{계약 체결일}}은 엔티티에서 온다 — 미서명이면 FirstSentAt(:781)', (tester) async {
      final bundle = FakeAssetBundle({
        'assets/legal/contract_pt_v1_reported.md': '체결일: {{계약 체결일}}\n',
      });

      await openSign(tester, docContract(vars: const {'상품명': 'PT 20회'}), bundle: bundle);

      // 발송일·서명일 행과 같은 표기(YYYY-MM-DD, DateFmt.isoDate).
      expect(find.textContaining('체결일: 2026-08-20'), findsOneWidget);
    });

    testWidgets('체결일이 vars에 실려 오면 조용히 덮지 않고 거부한다 — 원천 충돌(P39 결정 3)', (tester) async {
      final bundle = FakeAssetBundle({
        'assets/legal/contract_pt_v1_reported.md': '체결일: {{계약 체결일}}\n',
      });

      // 서버가 규약을 어기고 {{계약 체결일}}을 Vars에 얼려 보낸 상황 — 어느 쪽이
      // 회원이 서명한 진실인지 렌더러가 정할 수 없으므로 문서를 그리지 않는다.
      await openSign(
        tester,
        docContract(vars: const {'계약 체결일': '2020-01-01'}),
        bundle: bundle,
      );

      expect(find.byType(ContractDocumentView), findsNothing);
      expect(find.textContaining('2020-01-01'), findsNothing);
      expect(find.textContaining('계약서 전문을 표시할 수 없어요'), findsOneWidget);
      // 표시 불가가 서명을 막지는 않는다 — 요약 고지 경로로 진행.
      expect(checkbox(tester).onChanged, isNotNull);
    });
  });

  group('전문 없는 경로 — 요약 고지 기준선(P28)은 어떤 경우에도 산다', () {
    testWidgets('미지 버전 — 렌더하지 않고 업데이트 안내, 서명은 그대로(§D ④ :916-917)', (tester) async {
      await openSign(tester, docContract(templateVersion: 'pt-v99'));

      expect(find.textContaining('새 계약서 양식입니다'), findsOneWidget);
      expect(find.textContaining('앱을 업데이트하면 전문을 열람할 수 있어요'), findsOneWidget);
      // 모르는 버전을 손의 템플릿으로 그리면 조용히 틀린 문서다 — 렌더 자체가 없어야 한다.
      expect(find.byType(ContractDocumentView), findsNothing);
      expect(checkbox(tester).onChanged, isNotNull);
      expect(find.text('중도 해지 위약금'), findsWidgets);
    });

    testWidgets('Vars 누락(방어) — 가짜 문서 없이 사실대로 알리고 요약 경로 진행', (tester) async {
      // 보존 규약(v2.18)상 부분 스냅샷은 서버에서 만들어지지 않지만, 온다면
      // 렌더러가 MissingVars로 거부한다 — 빈 칸이 뚫린 문서를 그리지 않는다.
      final bundle = FakeAssetBundle({
        'assets/legal/contract_pt_v1_reported.md': '안내 {{회원명}}\n',
      });

      await openSign(tester, docContract(vars: const {'상품명': 'PT'}), bundle: bundle);

      expect(find.byType(ContractDocumentView), findsNothing);
      expect(find.textContaining('계약서 전문을 표시할 수 없어요'), findsOneWidget);
      expect(checkbox(tester).onChanged, isNotNull);
    });

    testWidgets('스냅샷 없는 계약(래치 OFF 동안의 전부) — 화면·게이트 모두 오늘 그대로', (tester) async {
      const legacy = ContractItem(
        id: 'c-legacy',
        passId: 'p1',
        product: 'PT 20회',
        paidAmount: 1200000,
        status: 'sent',
        penaltyRate: 0.1,
      );

      await openSign(tester, legacy);

      // 전문 관련 위젯이 하나도 더해지지 않는다 — 기존 화면과 동일.
      expect(find.byType(ContractDocumentView), findsNothing);
      expect(find.textContaining('새 계약서 양식'), findsNothing);
      expect(find.textContaining('전문을 표시할 수 없어요'), findsNothing);
      expect(find.text('전문을 끝까지 읽으면 동의할 수 있어요'), findsNothing);
      // 즉시 동의 가능(기존 동작) → 체크 → 서명 버튼 활성.
      expect(checkbox(tester).onChanged, isNotNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(checkbox(tester).value, isTrue);
      expect(signButton(tester).onPressed, isNotNull);
    });
  });
}
