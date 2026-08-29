// 계약 열람(P22).
//
// 종전 결함: 서명하는 순간 계약을 다시 볼 길이 사라졌다. `sent` 행만 서명 시트로
// 열리고 `signed`·`draft`·`voided`는 배지만 붙은 죽은 행이었다 — 회원이 무엇에
// 얼마를 내고 위약금율 몇 %에 동의했는지 나중에 확인할 수 없었다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_sign_sheet.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_detail_sheet.dart';
import 'package:rise_member/features/my/presentation/widgets/contracts_row.dart';

void main() {
  const signed = ContractItem(
    id: 'c-signed',
    passId: 'p1',
    product: 'PT 20회',
    paidAmount: 1200000,
    status: 'signed',
    penaltyRate: 0.1,
  );

  Widget host(List<ContractItem> contracts, {required void Function(ContractItem) onDetail}) =>
      MaterialApp(
        home: Scaffold(
          body: ContractsRow(
            contracts: contracts,
            consent: const ConsentState(general: true, sensitive: true),
            onConsentTap: () {},
            onSignTap: (_) => fail('서명 완료된 계약에 서명 시트를 열면 안 된다'),
            onDetailTap: onDetail,
          ),
        ),
      );

  group('행 탭', () {
    testWidgets('서명 완료된 계약도 탭하면 열린다 — 서명 후 열람 불가가 결함이었다', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(host(const [signed], onDetail: (c) => taps.add(c.id)));

      await tester.tap(find.text('PT 20회 계약'));
      await tester.pumpAndSettle();

      expect(taps, ['c-signed']);
    });

    testWidgets('센터가 작성 중(draft)인 계약도 내용은 볼 수 있다', (tester) async {
      final taps = <String>[];
      const draft = ContractItem(
        id: 'c-draft',
        passId: 'p2',
        product: 'PT 10회',
        paidAmount: 700000,
        status: 'draft',
      );
      await tester.pumpWidget(host(const [draft], onDetail: (c) => taps.add(c.id)));

      await tester.tap(find.text('PT 10회 계약'));
      await tester.pumpAndSettle();

      expect(taps, ['c-draft']);
    });
  });

  group('행 표시', () {
    testWidgets('긴 상품명도 360dp에서 행을 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(
        const [
          ContractItem(
            id: 'c-long',
            passId: 'p9',
            product: '주 3회 · 12주 다이어트 집중 관리 프로그램 (식단 코칭 포함)',
            paidAmount: 12345678,
            status: 'signed',
          ),
        ],
        onDetail: (_) {},
      ));

      expect(tester.takeException(), isNull);
    });
  });

  group('서명 시트 — 보여준 적 없는 조건에 동의시키지 않는다', () {
    // 종전엔 상품·금액·발송일 세 줄만 띄우고 "위 계약 내용을 확인했으며 동의합니다"를
    // 받았다. 위약금율조차 없었다 — 방문판매법 제30조②의 필수 기재사항 누락이고,
    // 회원 입장에서는 본 적 없는 조건에 서명한 것이 된다.
    // 정책과 스냅샷을 **다른 값**으로 둔다. 둘이 같으면 어느 쪽을 그리는지 테스트가
    // 구분하지 못해, 스냅샷을 무시하는 회귀를 놓친다(뮤테이션에서 실제로 살아남았다).
    Future<void> openSign(WidgetTester tester, ContractItem c, {double policyRate = 0.05}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            centerPolicyProvider.overrideWith((ref) async => CenterPolicy(
                  slotCapacity: 3,
                  cancelCutoffHours: 24,
                  graceOnce: true,
                  penaltyRate: policyRate,
                  expiringDays: 7,
                  maxHoldsPerPass: 2,
                  maxHoldTotalDays: 30,
                )),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showContractSignSheet(context, contract: c),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
    }

    const sent = ContractItem(
      id: 'c-sent',
      passId: 'p1',
      product: 'PT 20회',
      paidAmount: 1200000,
      status: 'sent',
      penaltyRate: 0.1,
    );

    testWidgets('위약금율이 동의 전에 보인다 — 계약 스냅샷이 현재 정책을 이긴다', (tester) async {
      // 서명 스냅샷(10%)과 현재 정책(5%)이 다르다. 서버 refundBasis는 스냅샷을 먼저
      // 쓰므로 화면도 그래야 한다 — 갈리면 "계약서 5% / 실제 공제 10%"가 된다.
      await openSign(tester, sent, policyRate: 0.05);
      expect(find.text('중도 해지 위약금'), findsOneWidget);
      expect(find.textContaining('10%'), findsWidgets);
      expect(find.textContaining('5%'), findsNothing);
    });

    testWidgets('해지 시 정산 방식을 말한다', (tester) async {
      await openSign(tester, sent);
      expect(find.textContaining('해지하면 이렇게 정산돼요'), findsOneWidget);
      expect(find.textContaining('환불액 = 지금까지 낸 금액'), findsOneWidget);
      // 기준액을 밝히지 않으면 회원은 "내가 낸 돈의 10%"로 읽는다 — 분할이면 갈린다.
      expect(find.textContaining('계약가의 10%'), findsOneWidget);
      expect(find.textContaining('낸 금액이 아니라 계약가 기준'), findsOneWidget);
      expect(find.textContaining('24시간 전까지'), findsOneWidget);
    });

    testWidgets('스냅샷이 없으면 현재 센터 정책을 쓴다 — 서버 refundBasis와 같은 순서', (tester) async {
      // 여기서 다른 값을 그리면 "계약서 30% / 실제 공제 10%"로 갈렸던 사고의 재현이 된다.
      const legacy = ContractItem(
        id: 'c-legacy', passId: 'p1', product: 'PT 10회',
        paidAmount: 700000, status: 'sent',
      );
      await openSign(tester, legacy, policyRate: 0.05);
      expect(find.textContaining('5%'), findsWidgets);
    });

    testWidgets('약관 전문으로 가는 길이 있다', (tester) async {
      await openSign(tester, sent);
      expect(find.text('이용약관 전문 보기'), findsOneWidget);
      expect(find.textContaining('이용약관을 확인했으며 동의합니다'), findsOneWidget);
    });
  });

  group('상세 시트', () {
    Future<void> open(WidgetTester tester, ContractItem c, {double? penaltyRate}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showContractDetailSheet(context, contract: c, penaltyRate: penaltyRate),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
    }

    testWidgets('상품·금액·상태를 그대로 보여준다', (tester) async {
      await open(tester, signed);

      expect(find.text('PT 20회 계약'), findsOneWidget);
      expect(find.text('계약가'), findsOneWidget);
      expect(find.text('1,200,000원'), findsOneWidget);
      expect(find.text('서명 완료'), findsOneWidget);
    });

    testWidgets('위약금율을 보여준다 — 해지 시 얼마를 떼이는지가 계약의 핵심이다', (tester) async {
      await open(tester, signed, penaltyRate: 0.1);
      expect(find.text('10%'), findsOneWidget);
    });

    testWidgets('위약금율을 모르면 행을 아예 뺀다 — 0%로 오해시키지 않는다', (tester) async {
      // 서버 penalty_rate는 포인터라 null이 legacy(모름)를 뜻한다.
      // 여기서 0%를 그려 넣으면 "위약금 없음"이라는 없는 약속을 만든다.
      await open(tester, signed, penaltyRate: null);
      expect(find.text('위약금율(계약가 기준)'), findsNothing);
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('좁은 실기기 폭(360dp)에서 넘치지 않는다', (tester) async {
      // 기본 테스트 화면은 800dp라 실기기(360dp)에서만 터지는 오버플로를 못 잡는다.
      // 상품명·금액은 센터가 자유 입력하므로 길이 상한이 계약에 없다.
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await open(
        tester,
        const ContractItem(
          id: 'c-long',
          passId: 'p9',
          product: '주 3회 · 12주 다이어트 집중 관리 프로그램 (식단 코칭 포함)',
          paidAmount: 12345678,
          status: 'signed',
        ),
        penaltyRate: 0.125,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('12.5%'), findsOneWidget);
    });

    testWidgets('본문 PDF가 없다는 사실을 숨기지 않는다', (tester) async {
      await open(tester, signed);
      expect(find.textContaining('아직 앱에 올라와 있지 않아요'), findsOneWidget);
    });
  });
}
