// 서명 시트 2단 전환(P44 결정 5) + 제출 바디 + 체결 완료 단계.
//
// 고정하는 것:
//  · 1단 게이트는 오늘 그대로(동의 체크가 "서명하기"를 연다) — 서명하기는 이제
//    제출이 아니라 2단 진입이다.
//  · 2단: 문서는 확인 한 줄로 접히고, 패드에 실제 표식이 있어야 "동의하고
//    서명합니다"가 열린다. [다시 보기]로 1단에 다녀와도 동의·읽음 래치가 산다.
//  · 시트 라우트 enableDrag=false — 패드 세로 획과 시트 드래그-닫기의 제스처
//    아레나 경합 차단(라우트 파라미터는 생성 시점 고정이라 시트 전체에서 끈다).
//  · 제출은 내보낸 서명 PNG를 base64로 동봉한다(레거시 요약 경로도 동일) —
//    가짜 저장소가 받은 바디를 디코드해 PNG 매직까지 확인한다.
//  · 성공 시 시트가 닫히는 대신 체결 완료 단계 — [계약서 보기]는 재조회 반영본으로
//    호출자 콜백을 부른다(상세를 여는 쪽은 살아남는 화면의 context).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/domain/my_repository.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_sign_sheet.dart';
import 'package:rise_member/features/my/presentation/widgets/signature_pad.dart';

import '../../../../support/fake_asset_bundle.dart';
import '../../../../support/font_loader.dart';

const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  setUpAll(loadPretendard);

  late _FakeMyRepository repo;
  setUp(() => repo = _FakeMyRepository());

  const sent = ContractItem(
    id: 'c-sent',
    passId: 'p1',
    product: 'PT 20회',
    paidAmount: 1200000,
    status: 'sent',
    penaltyRate: 0.1,
  );

  ContractItem docContract() => ContractItem(
        id: 'c-doc',
        passId: 'p1',
        product: 'PT 20회',
        paidAmount: 1200000,
        status: 'sent',
        penaltyRate: 0.1,
        firstSentAt: DateTime(2026, 8, 20),
        templateVersion: 'pt-v1-reported',
        vars: const {'상품명': 'PT 20회'},
      );

  Future<void> openSign(
    WidgetTester tester,
    ContractItem c, {
    FakeAssetBundle? bundle,
    void Function(ContractItem contract)? onViewSigned,
    CenterPolicy policy = CenterPolicy.fallback,
  }) async {
    final container = ProviderContainer.test(
      overrides: [
        myRepositoryProvider.overrideWithValue(repo),
        centerPolicyProvider.overrideWithValue(AsyncValue.data(policy)),
      ],
    );
    container.read(sessionProvider.notifier).set(
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1'),
        );
    // 운영에서는 my_screen이 myViewModelProvider를 watch한다 — 리스너가 있어야
    // refresh()의 invalidate가 실제 재조회(load)로 이어진다. 그 조건을 재현한다.
    final sub = container.listen(myViewModelProvider, (_, __) {});
    addTearDown(sub.close);
    Widget app = UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Pretendard'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showContractSignSheet(
                context,
                contract: c,
                onViewSigned: onViewSigned,
              ),
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

  Finder padCanvas() => find.descendant(
      of: find.byType(SignaturePad), matching: find.byType(CustomPaint));

  Future<void> drawSignature(WidgetTester tester) async {
    await tester.dragFrom(tester.getCenter(padCanvas()), const Offset(150, 20));
    await tester.pump();
  }

  /// 최종 버튼(2단) — 라벨로 집는다(1단 버튼과 혼동 방지).
  RiseButton finalButton(WidgetTester t) => t.widget<RiseButton>(
      find.widgetWithText(RiseButton, '동의하고 서명합니다'));

  /// 제출 — 내보내기(toImage→PNG)는 진짜 엔진 비동기라 FakeAsync 존에서 완주하지
  /// 못한다. runAsync 창 안에서 탭과 실시간 대기를 함께 돌린다.
  Future<void> submit(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('동의하고 서명합니다'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
  }

  group('정산 박스 — 정책을 못 받았으면 숫자를 말하지 않는다 (P56 H3)', () {
    // 이 박스 바로 아래서 "위 계약 내용을 확인했으며 동의합니다"를 받는다. 폴백 24시간을
    // 사실처럼 찍으면 센터 실제 마감이 48시간일 때 그 문구에 동의한 회원이 30시간 전
    // 취소로 차감되고, 그 문구를 근거로 다툰다. `isFallback`의 dartdoc이 적은 사고다.
    const serverPolicy = CenterPolicy(
      slotCapacity: 3,
      cancelCutoffHours: 48,
      graceOnce: true,
      penaltyRate: 0.05,
      expiringDays: 7,
      maxHoldsPerPass: 2,
      maxHoldTotalDays: 30,
    );

    testWidgets('폴백이면 취소 마감 시간을 찍지 않고 모른다고 말한다', (tester) async {
      await openSign(tester, sent); // 기본 = CenterPolicy.fallback

      expect(find.textContaining('24시간'), findsNothing, reason: '폴백 24시간을 사실처럼 말했다');
      expect(find.textContaining('센터 정책을 확인하지 못했어요'), findsOneWidget);
      expect(find.textContaining('계약서 본문의 기준을 따라요'), findsOneWidget);
      // 위약금율은 계약 스냅샷(0.1)이라 폴백과 무관하게 그대로 말한다.
      expect(find.text('10%'), findsOneWidget);
    });

    testWidgets('서버 값이면 그 시간을 말한다 — 과잉 차단이 아니다', (tester) async {
      await openSign(tester, sent, policy: serverPolicy);

      expect(find.textContaining('48시간 전까지 무료로 취소'), findsOneWidget);
      expect(find.textContaining('확인하지 못했어요'), findsNothing);
    });

    testWidgets('스냅샷 없는 레거시 계약 + 폴백이면 위약금율도 모른다고 말한다', (tester) async {
      // 서버 refundBasis는 스냅샷 → 현재 정책 순으로 고른다. 둘 다 없는 상태에서 폴백
      // 10%를 찍으면, 센터 실제 요율이 5%일 때 회원은 더 큰 위약금에 동의한 셈이 된다.
      const legacy = ContractItem(
        id: 'c-legacy',
        passId: 'p1',
        product: 'PT 20회',
        paidAmount: 1200000,
        status: 'sent',
      );
      await openSign(tester, legacy);

      expect(find.text('10%'), findsNothing, reason: '폴백 요율을 사실처럼 말했다');
      expect(find.text('확인하지 못했어요'), findsOneWidget); // 요약 행의 값
      expect(find.textContaining('위약금율은 센터 정책을 확인하지 못했어요'), findsOneWidget);
    });

    testWidgets('스냅샷 없는 레거시 계약 + 서버 정책이면 현재 요율로 말한다 — refundBasis와 같은 순서', (tester) async {
      const legacy = ContractItem(
        id: 'c-legacy',
        passId: 'p1',
        product: 'PT 20회',
        paidAmount: 1200000,
        status: 'sent',
      );
      await openSign(tester, legacy, policy: serverPolicy);

      expect(find.text('5%'), findsOneWidget);
      expect(find.textContaining('확인하지 못했어요'), findsNothing);
    });
  });

  group('2단 전환 — 서명하기는 제출이 아니라 서명 단계 진입이다(결정 5)', () {
    testWidgets('동의 → 서명하기 → 2단: 확인 라인·교부 고지·패드가 서고 요약·체크는 접힌다', (tester) async {
      await openSign(tester, sent);

      // 1단 게이트는 오늘 그대로 — 동의 전 잠김.
      final stage1 = tester.widget<RiseButton>(
          find.widgetWithText(RiseButton, '서명하기'));
      expect(stage1.onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('서명하기'));
      await tester.pumpAndSettle();

      // 진입만 했을 뿐 제출은 없다.
      expect(repo.signCalls, isEmpty,
          reason: '서명하기가 제출을 쏘면 2단(자필 표식)이 통째로 우회된다');
      // 2단 구성 요소.
      expect(find.text('계약 내용을 확인했습니다'), findsOneWidget);
      expect(find.text('다시 보기'), findsOneWidget);
      expect(find.textContaining('전자문서로 체결·교부되며'), findsOneWidget);
      expect(find.byType(SignaturePad), findsOneWidget);
      expect(find.text('여기에 서명해 주세요'), findsOneWidget);
      // 1단 요소는 접혔다(높이 경합 해소).
      expect(find.text('계약가'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      // 패드가 비어 있는 동안 최종 버튼 잠김.
      expect(finalButton(tester).onPressed, isNull);
    });

    testWidgets('패드 표식 → 최종 버튼 활성, 다시 쓰기 → 다시 잠김', (tester) async {
      await openSign(tester, sent);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('서명하기'));
      await tester.pumpAndSettle();

      await drawSignature(tester);
      expect(finalButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('다시 쓰기'));
      await tester.pump();
      expect(finalButton(tester).onPressed, isNull,
          reason: '지운 뒤에도 열려 있으면 빈 서명이 제출된다');
    });

    testWidgets('다시 보기 → 1단 복귀: 동의 체크·끝까지 읽음 래치가 그대로 산다', (tester) async {
      // 뷰포트보다 긴 전문 — 읽음 래치가 실제로 세워진 상태에서 왕복해야
      // "보존"이 증명된다(짧은 문서는 래치가 자동이라 검증력이 없다).
      final longTemplate = List.generate(
          80, (i) => '제${i + 1}문단. 스크롤을 강제하기 위한 본문입니다.\n').join('\n');
      final bundle = FakeAssetBundle(
          {'assets/legal/contract_pt_v1_reported.md': longTemplate});
      await openSign(tester, docContract(), bundle: bundle);

      final docScroller = find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.scrollDirection == Axis.vertical);
      await tester.drag(docScroller, const Offset(0, -100000));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('서명하기'));
      await tester.pumpAndSettle();
      expect(find.byType(SignaturePad), findsOneWidget);

      await tester.tap(find.text('다시 보기'));
      await tester.pumpAndSettle();

      final checkbox =
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
      expect(checkbox.value, isTrue, reason: '왕복이 동의를 지우면 역행이다');
      expect(checkbox.onChanged, isNotNull, reason: '읽음 래치도 시트 상태라 보존돼야 한다');
      expect(find.text('전문을 끝까지 읽으면 동의할 수 있어요'), findsNothing);
      // 다시 2단으로 — 패드도 컨트롤러가 시트 소유라 그대로다.
      await tester.tap(find.text('서명하기'));
      await tester.pumpAndSettle();
      expect(find.byType(SignaturePad), findsOneWidget);
    });

    testWidgets('시트 라우트 enableDrag=false — 패드 세로 획이 시트 드래그로 새지 않는다', (tester) async {
      await openSign(tester, sent);

      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.enableDrag, isFalse,
          reason: '켜져 있으면 패드 위 세로 획이 아레나 경합에서 시트를 끌어내린다(P44 리서치)');
    });
  });

  group('제출 — 서명 PNG base64 동봉(결정 2·6)', () {
    testWidgets('스냅샷 없는 레거시 경로도 같은 2단 패드로 서명하고 바디를 실어 보낸다', (tester) async {
      await openSign(tester, sent);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('서명하기'));
      await tester.pumpAndSettle();
      await drawSignature(tester);

      await submit(tester);

      expect(repo.signCalls, hasLength(1));
      final call = repo.signCalls.single;
      expect(call.contractId, 'c-sent');
      expect(call.signaturePng, isNotNull,
          reason: '패드로 서명했는데 바디가 비면 증거 이미지가 조용히 유실된 것');
      final bytes = base64Decode(call.signaturePng!);
      expect(bytes.sublist(0, 8), _pngMagic);
      expect(bytes.length, lessThanOrEqualTo(40 * 1024));
    });

    testWidgets('실패(4xx 거부) — 2단에 남아 인라인 에러 + 목록 재동기화', (tester) async {
      repo.signResult = const Err(RejectedFailure('이미 서명된 계약이에요'));
      await openSign(tester, sent);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('서명하기'));
      await tester.pumpAndSettle();
      await drawSignature(tester);

      await submit(tester);

      expect(find.text('이미 서명된 계약이에요'), findsOneWidget);
      expect(find.byType(SignaturePad), findsOneWidget, reason: '실패가 완료 단계로 넘어가면 안 된다');
      expect(find.text('계약이 체결되었습니다'), findsNothing);
      expect(repo.loadCount, greaterThanOrEqualTo(2),
          reason: 'RejectedFailure는 목록 재동기화를 걸어야 한다(기존 규약)');
    });
  });

  group('체결 완료 단계 — 닫는 대신 확인시킨다', () {
    testWidgets('성공 → 완료 문구·서명 썸네일·[계약서 보기]·[닫기]', (tester) async {
      await openSign(tester, sent, onViewSigned: (_) {});
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('서명하기'));
      await tester.pumpAndSettle();
      await drawSignature(tester);

      await submit(tester);

      expect(find.text('계약이 체결되었습니다'), findsOneWidget);
      expect(find.textContaining('마이 > 계약에서 언제든'), findsOneWidget);
      // 방금 내보낸 로컬 바이트 썸네일.
      expect(
        find.descendant(of: find.byType(Container), matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(find.text('계약서 보기'), findsOneWidget);
      expect(find.text('닫기'), findsOneWidget);
      // 패드·요약은 더 이상 없다.
      expect(find.byType(SignaturePad), findsNothing);
    });

    testWidgets('[계약서 보기] — 시트를 닫고 재조회 반영본으로 콜백한다', (tester) async {
      // 재조회(load)가 돌려줄 서명 반영본 — 서명 이미지·서명일이 실려 있다.
      repo.contracts = [
        ContractItem(
          id: 'c-sent',
          passId: 'p1',
          product: 'PT 20회',
          paidAmount: 1200000,
          status: 'signed',
          penaltyRate: 0.1,
          signedAt: DateTime.utc(2026, 8, 29, 5, 0),
          signaturePng: base64Encode(const [1, 2, 3]),
          signatureSha256: 'ab12',
        ),
      ];
      ContractItem? viewed;
      await openSign(tester, sent, onViewSigned: (c) => viewed = c);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('서명하기'));
      await tester.pumpAndSettle();
      await drawSignature(tester);
      await submit(tester);

      await tester.runAsync(() async {
        await tester.tap(find.text('계약서 보기'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.text('계약이 체결되었습니다'), findsNothing, reason: '시트가 닫혀야 한다');
      expect(viewed, isNotNull);
      expect(viewed!.status, 'signed', reason: '콜백 인자는 재조회 반영본이어야 한다');
      expect(viewed!.hasSignatureImage, isTrue);
    });

    testWidgets('콜백 없는 호출자 — [계약서 보기] 없이 [닫기]만, 탭하면 닫힌다', (tester) async {
      await openSign(tester, sent); // onViewSigned 없음
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('서명하기'));
      await tester.pumpAndSettle();
      await drawSignature(tester);
      await submit(tester);

      expect(find.text('계약서 보기'), findsNothing,
          reason: '아무 데도 못 여는 버튼을 그리면 안 된다');
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(find.text('계약이 체결되었습니다'), findsNothing);
    });
  });
}

/// 마이 저장소 가짜 — 서명 호출(계약 id·동봉 바디)과 재조회 횟수를 기록한다.
class _FakeMyRepository implements MyRepository {
  final List<({String contractId, String? signaturePng})> signCalls = [];
  Result<void> signResult = const Ok(null);

  /// load가 돌려줄 계약 목록 — [계약서 보기] 테스트가 서명 반영본을 심는다.
  List<ContractItem> contracts = const [];
  int loadCount = 0;

  @override
  Future<Result<MySummary>> load(String memberId) async {
    loadCount += 1;
    return Ok(MySummary(
      passes: const [],
      ledgerByPass: const {},
      contracts: contracts,
      consent: const ConsentState(general: true, sensitive: true),
    ));
  }

  @override
  Future<Result<void>> signContract(String contractId, {String? signaturePng}) async {
    signCalls.add((contractId: contractId, signaturePng: signaturePng));
    return signResult;
  }

  @override
  Future<Result<void>> requestHold({
    required String passId,
    required DateTime from,
    required DateTime to,
    String? reason,
  }) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> resumeHold(String passId) => throw UnimplementedError();

  @override
  Future<Result<void>> updateConsent({
    required String memberId,
    required bool general,
    required bool sensitive,
  }) =>
      throw UnimplementedError();

  @override
  Future<Result<AccountDeletionSummary>> deleteAccount() => throw UnimplementedError();
}
