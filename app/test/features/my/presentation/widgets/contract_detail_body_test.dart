// 상세 시트 계약서 본문(P39 §D ⑥) — 문서 스냅샷이 있는 계약은 "계약서 본문"을 열어
// **서명 당시 문서를 재현**하고(읽기 전용 — 끝-스크롤 게이트는 서명 시트만, §D ⑤),
// 스냅샷 없는 레거시는 지금 문구를 한 글자도 바꾸지 않는다(§D ⑥ "지금 문구를 그대로
// 유지" — 없는 걸 있는 척하지 않는다는 원래 판단).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_detail_sheet.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_document_view.dart';

import '../../../../support/fake_asset_bundle.dart';
import '../../../../support/font_loader.dart';

/// 1×1 투명 PNG — 서명 이미지 자리에 넣는 최소 유효 PNG(P44 테스트 공용).
const kTinyPngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

void main() {
  setUpAll(loadPretendard);

  ContractItem docSigned({
    String templateVersion = 'pt-v1-reported',
    Map<String, String> vars = const {'상품명': 'PT 20회'},
    DateTime? signedAt,
    DateTime? firstSentAt,
    String signaturePng = '',
    String signatureSha256 = '',
  }) =>
      ContractItem(
        id: 'c-signed',
        passId: 'p1',
        product: 'PT 20회',
        paidAmount: 1200000,
        status: 'signed',
        penaltyRate: 0.1,
        signedAt: signedAt ?? DateTime(2026, 8, 25),
        firstSentAt: firstSentAt ?? DateTime(2026, 8, 20),
        templateVersion: templateVersion,
        vars: vars,
        signaturePng: signaturePng,
        signatureSha256: signatureSha256,
      );

  Future<void> open(WidgetTester tester, ContractItem c, {FakeAssetBundle? bundle}) async {
    // showRiseSheet는 세션 감시자(_SessionSheetGuard)를 달아 연다 — 앱과 같은 DI 루트가 필요하다.
    Widget app = ProviderScope(
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Pretendard'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showContractDetailSheet(context, contract: c, penaltyRate: 0.1),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    if (bundle != null) {
      app = DefaultAssetBundle(bundle: bundle, child: app);
    }
    await tester.pumpWidget(app);
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  group('계약서 본문 섹션(§D ⑥)', () {
    testWidgets('"보기"를 열면 서명 당시 문서가 재현된다 — 기본은 접힘', (tester) async {
      final bundle = FakeAssetBundle({
        'assets/legal/contract_pt_v1_reported.md': '## 본문 표제\n\n계약 전문입니다.\n',
      });

      await open(tester, docSigned(), bundle: bundle);

      // 행은 있으나 접혀 있다 — 메타(금액·상태·날짜)가 먼저다.
      expect(find.text('계약서 본문'), findsOneWidget);
      expect(find.text('보기'), findsOneWidget);
      expect(find.byType(ContractDocumentView), findsNothing);

      await tester.tap(find.text('계약서 본문'));
      await tester.pumpAndSettle();

      expect(find.byType(ContractDocumentView), findsOneWidget);
      expect(find.text('본문 표제'), findsOneWidget);
      expect(find.text('계약 전문입니다.'), findsOneWidget);
      expect(find.text('접기'), findsOneWidget);
      // 화면 열람이 생겨도 PDF **파일**이 없다는 말은 여전히 참 — 안내 줄은 남는다(§D ③).
      expect(find.textContaining('아직 앱에 올라와 있지 않아요'), findsOneWidget);
    });

    testWidgets('{{계약 체결일}} — 서명된 계약은 SignedAt이 이긴다(:781)', (tester) async {
      final bundle = FakeAssetBundle({
        'assets/legal/contract_pt_v1_reported.md': '체결일: {{계약 체결일}}\n',
      });

      await open(
        tester,
        docSigned(signedAt: DateTime(2026, 8, 25), firstSentAt: DateTime(2026, 8, 20)),
        bundle: bundle,
      );
      await tester.tap(find.text('계약서 본문'));
      await tester.pumpAndSettle();

      expect(find.textContaining('체결일: 2026-08-25'), findsOneWidget);
      // P44 재고정: 광역 '2026-08-20' 부재 단언은 체결 정보의 정당한 "최초 발송일"
      // 행(P44 결정 7)까지 걸어 넘어뜨린다 — 원래 의도(문서의 {{계약 체결일}}이
      // 발송일로 렌더되면 안 된다)만 정확히 좁혀 고정한다.
      expect(find.textContaining('체결일: 2026-08-20'), findsNothing,
          reason: '서명일이 있는데 발송일로 렌더하면 체결일이 거짓이 된다');
    });

    testWidgets('KST 자정 경계 — 문서 체결일과 체결 정보가 같은 날짜를 말한다 (P44 마감 리뷰 H)',
        (tester) async {
      // UTC 8/29 22:00 = KST 8/30 07:00 — toKst 없이 isoDate를 찍으면 법적 문서에는
      // 08-29, 바로 아래 체결 정보(서명 일시, toKst 적용)에는 08-30이 찍혀 같은 시트가
      // 하루 어긋난 두 날짜를 말했다(KST 00~09시 체결 = 하루의 37.5%가 해당).
      final bundle = FakeAssetBundle({
        'assets/legal/contract_pt_v1_reported.md': '체결일: {{계약 체결일}}\n',
      });

      await open(
        tester,
        docSigned(signedAt: DateTime.utc(2026, 8, 29, 22, 0)),
        bundle: bundle,
      );
      await tester.tap(find.text('계약서 본문'));
      await tester.pumpAndSettle();

      expect(find.textContaining('체결일: 2026-08-30'), findsOneWidget,
          reason: '체결일은 KST 벽시계 날짜여야 한다');
      expect(find.textContaining('체결일: 2026-08-29'), findsNothing,
          reason: 'UTC 날짜가 새면 체결 정보와 하루 모순이 난다');
      expect(find.textContaining('2026-08-29'), findsNothing,
          reason: '시트 어디에도 UTC 날짜 잔재가 없어야 한다(서명일 행 포함 전 행 KST 통일)');
    });

    testWidgets('레거시(Vars 없음) — 본문 행이 생기지 않고 지금 문구가 한 글자도 그대로', (tester) async {
      const legacy = ContractItem(
        id: 'c-legacy',
        passId: 'p1',
        product: 'PT 20회',
        paidAmount: 1200000,
        status: 'signed',
      );

      await open(tester, legacy);

      expect(find.text('계약서 본문'), findsNothing);
      expect(find.byType(ContractDocumentView), findsNothing);
      // §D ⑥ verbatim 고정 — 문구를 고치면 이 단언이 시끄럽게 죽어야 한다.
      expect(
        find.text('계약서 원본 파일은 아직 앱에 올라와 있지 않아요 — 센터에 요청하면 보내드려요.'),
        findsOneWidget,
      );
    });

    testWidgets('미지 버전 — 서명 시트와 같은 업데이트 안내, 렌더 없음(§D ④)', (tester) async {
      await open(tester, docSigned(templateVersion: 'pt-v99'));

      expect(find.textContaining('새 계약서 양식입니다'), findsOneWidget);
      expect(find.textContaining('앱을 업데이트하면 전문을 열람할 수 있어요'), findsOneWidget);
      expect(find.text('계약서 본문'), findsNothing);
      expect(find.byType(ContractDocumentView), findsNothing);
    });

    testWidgets('표시 불가(값 누락 방어) — 사실대로 한 줄, 가짜 문서 없음', (tester) async {
      final bundle = FakeAssetBundle({
        'assets/legal/contract_pt_v1_reported.md': '안내 {{회원명}}\n',
      });

      await open(tester, docSigned(vars: const {'상품명': 'PT'}), bundle: bundle);

      expect(find.textContaining('계약서 전문을 표시할 수 없어요'), findsOneWidget);
      expect(find.byType(ContractDocumentView), findsNothing);
      expect(find.text('계약서 본문'), findsNothing);
    });
  });

  group('서명란 도킹 블록(P44 결정 4) — 본문 안, 마지막 표 직하단', () {
    // 서명란 표 + [별지] 펜스가 있는 축소 문서 — 실자산 구조의 최소 재현.
    const miniDoc = '본문 문단입니다.\n\n'
        '| | |\n|---|---|\n| 센터 | 라이즈 대표 김대표 (인) |\n| 회원 | 홍길동 (서명) |\n\n'
        '## [별지] 서식\n\n```\n서식 본문\n```';

    testWidgets('서명 이미지 있는 계약 — 본문을 열면 회원 서명 블록이 서명란 표 뒤에 선다', (tester) async {
      final bundle = FakeAssetBundle({'assets/legal/contract_pt_v1_reported.md': miniDoc});

      await open(
        tester,
        docSigned(
          signaturePng: kTinyPngB64,
          signedAt: DateTime.utc(2026, 8, 25, 5, 3), // KST 2026-08-25 14:03
        ),
        bundle: bundle,
      );
      await tester.tap(find.text('계약서 본문'));
      await tester.pumpAndSettle();

      expect(find.text('회원 서명'), findsOneWidget);
      expect(find.text('서명일 2026-08-25'), findsOneWidget);
      // 위치 — 서명란 표 아래 · [별지] 표제 위(마지막 표 직하단 도킹).
      final tableBottom = tester.getBottomLeft(find.byType(Table).last).dy;
      final blockTop = tester.getTopLeft(find.text('회원 서명')).dy;
      final annexTop = tester.getTopLeft(find.text('[별지] 서식')).dy;
      expect(blockTop, greaterThanOrEqualTo(tableBottom));
      expect(blockTop, lessThan(annexTop));
    });

    testWidgets('서명 이미지 없는 계약(레거시·체크 동의) — 블록이 아예 없다', (tester) async {
      final bundle = FakeAssetBundle({'assets/legal/contract_pt_v1_reported.md': miniDoc});

      await open(tester, docSigned(), bundle: bundle);
      await tester.tap(find.text('계약서 본문'));
      await tester.pumpAndSettle();

      expect(find.byType(ContractDocumentView), findsOneWidget);
      expect(find.text('회원 서명'), findsNothing,
          reason: '이미지가 없는데 블록 틀만 그리면 빈 서명란을 지어내는 것');
    });

    testWidgets('깨진 base64(방어) — 죽지 않고 블록 없이 렌더한다', (tester) async {
      final bundle = FakeAssetBundle({'assets/legal/contract_pt_v1_reported.md': miniDoc});

      await open(tester, docSigned(signaturePng: '%%%깨진값%%%'), bundle: bundle);
      await tester.tap(find.text('계약서 본문'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ContractDocumentView), findsOneWidget);
      expect(find.text('회원 서명'), findsNothing);
    });
  });
}
