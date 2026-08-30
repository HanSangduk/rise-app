import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/domain/my_repository.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';
import 'package:rise_member/features/my/presentation/widgets/contracts_row.dart';
import 'package:rise_member/features/my/presentation/widgets/hold_request_sheet.dart';
import 'package:rise_member/features/my/presentation/widgets/pass_list.dart';

// "서버가 거부할 동작에 살아 있는 버튼을 주지 않는다" — 마이 탭 전수 고정.
//
// 세 자리를 함께 잡는다(전부 같은 클래스의 결함이다):
//  ① 일시정지 신청 — 상한(횟수/총 일수)을 제출 전에 판정하지 않아, 날짜까지 다 채운
//     뒤 서버 400을 받았다(`domain.ValidateNewHold`).
//  ② 후보 패스 필터 — `isActive || isScheduled` + "비면 원본 폴백"이라 서버가
//     active만 받는 자리(`api.HoldPass`)에 scheduled·refunded 패스를 올렸다.
//  ③ 재개·계약 서명 — `ResumePass`는 active만, `SignContract`는 환불된 거래를 거부한다.
void main() {
  late _FakeMyRepository repo;
  // 센터(KST) 오늘 — 시트의 판정과 데이트피커가 쓰는 것과 같은 값.
  final today = DateFmt.todayKst();

  setUp(() => repo = _FakeMyRepository());

  PassDetail buildPass({
    String id = 'p1',
    String status = 'active',
    String product = 'PT 20회',
    List<PassHold> holds = const [],
    DateTime? validUntil,
  }) {
    return PassDetail(
      id: id,
      product: product,
      trainerId: 't1',
      status: status,
      remaining: 12,
      totalSessions: 20,
      paidAmount: 1200000,
      validFrom: DateTime(2026, 1, 1),
      validUntil: validUntil ?? today.add(const Duration(days: 300)),
      holds: holds,
    );
  }

  /// 이미 끝난 과거 홀딩 — 상한 카운트에는 잡히지만 새 구간과 겹치지 않는다.
  PassHold pastHold(int startedDaysAgo) => PassHold(
        from: today.subtract(Duration(days: startedDaysAgo)),
        to: today.subtract(Duration(days: startedDaysAgo - 2)), // 3일(양끝 포함)
      );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(
    WidgetTester tester, {
    required List<PassDetail> passes,
    String initialPassId = 'p1',
    CenterPolicy policy = CenterPolicy.fallback,
  }) async {
    await pump(
      tester,
      _SheetHost(passes: passes, initialPassId: initialPassId),
      policy: policy,
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  /// 데이트피커에서 **오늘**을 고른다 — firstDate가 오늘이라 언제 돌려도 항상 유효하고,
  /// 달력 초기 월에 반드시 보인다(실행 날짜에 따라 흔들리지 않는 유일한 선택지).
  Future<void> pickToday(WidgetTester tester, String fieldLabel) async {
    await tester.tap(find.text(fieldLabel));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(DatePickerDialog), matching: find.text('${today.day}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  group('① 홀딩 상한 — 제출 전에 판정한다', () {
    testWidgets('상한 직전(2회 중 1회)이면 신청이 그대로 나간다 — 막기만 하면 안 된다', (tester) async {
      await openSheet(tester, passes: [buildPass(holds: [pastHold(100)])]);
      await pickToday(tester, '시작일');
      await pickToday(tester, '종료일');

      await tester.tap(find.text('신청하기'));
      await tester.pumpAndSettle();

      expect(repo.holdCalls, hasLength(1));
      expect(repo.holdCalls.single.passId, 'p1');
    });

    testWidgets('상한 도달(2회 중 2회)이면 버튼이 잠기고 이유가 보인다', (tester) async {
      await openSheet(tester, passes: [
        buildPass(holds: [pastHold(100), pastHold(50)]),
      ]);
      await pickToday(tester, '시작일');
      await pickToday(tester, '종료일');

      expect(find.textContaining('최대 2회'), findsWidgets);
      expect(find.textContaining('이미 2회를 썼어요'), findsOneWidget);

      await tester.tap(find.text('신청하기'));
      await tester.pumpAndSettle();

      expect(repo.holdCalls, isEmpty, reason: '서버가 확실히 400을 줄 신청은 나가면 안 된다');
    });

    testWidgets('상한 잔량을 신청 전에 보여준다 — 거부당해야 아는 값이 아니어야 한다', (tester) async {
      await openSheet(tester, passes: [
        buildPass(holds: [pastHold(100)]),
      ]);

      // 정책 실값(fallback 2회/30일) − 이 패스가 쓴 양(1회·3일) = 잔여가 헤드라인,
      // 상한·사용량은 근거 줄로.
      expect(find.text('남은 일시정지 27일 · 1회'), findsOneWidget);
      expect(find.text('최대 2회/30일 중 1회 · 3일 사용'), findsOneWidget);
    });

    testWidgets('날짜를 다 고르기 전엔 버튼이 잠기고, 무엇을 하면 되는지 안내가 상시로 보인다', (tester) async {
      await openSheet(tester, passes: [buildPass()]);

      RiseButton button() => tester.widget<RiseButton>(find.byType(RiseButton));
      expect(button().onPressed, isNull, reason: '미입력 상태 — 버튼이 잠겨 있어야 한다');
      expect(find.text('시작일과 종료일을 선택하면 신청할 수 있어요'), findsOneWidget);
      expect(repo.holdCalls, isEmpty);

      // 시작일만 고르면 안내가 남은 한 칸만 지목한다.
      await pickToday(tester, '시작일');
      expect(button().onPressed, isNull);
      expect(find.text('종료일을 선택하면 신청할 수 있어요'), findsOneWidget);

      // 두 날짜가 유효해지면 버튼이 살아나고, 안내 자리는 신청 미리보기가 잇는다.
      await pickToday(tester, '종료일');
      expect(button().onPressed, isNotNull);
      expect(find.textContaining('이번 신청: 1일 정지'), findsOneWidget);
    });

    testWidgets('무제한 정책(-1)에선 상한을 지어내지도, 막지도 않는다', (tester) async {
      const unlimited = CenterPolicy(
        slotCapacity: 3,
        cancelCutoffHours: 24,
        graceOnce: true,
        penaltyRate: 0.10,
          expiringDays: 7,
        maxHoldsPerPass: -1,
        maxHoldTotalDays: -1,
      );
      await openSheet(
        tester,
        passes: [
          buildPass(holds: [pastHold(100), pastHold(70), pastHold(50)]),
        ],
        policy: unlimited,
      );

      expect(find.textContaining('최대 -1회'), findsNothing);

      await pickToday(tester, '시작일');
      await pickToday(tester, '종료일');
      await tester.tap(find.text('신청하기'));
      await tester.pumpAndSettle();

      expect(repo.holdCalls, hasLength(1));
    });
  });

  group('② 후보 패스 — 서버 HoldPass가 받는 active만', () {
    testWidgets('scheduled 패스는 드롭다운에 오르지 않는다', (tester) async {
      await openSheet(tester, passes: [
        buildPass(product: 'PT 20회'),
        buildPass(id: 'p2', status: 'scheduled', product: '시작 예정 30회'),
      ]);

      // 후보가 1개로 줄어 드롭다운 자체가 사라진다.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('시작 예정 30회'), findsNothing);
    });

    testWidgets('환불 패스가 대표여도 신청 폼이 뜨지 않는다 — 유효기간이 남아 살아 보였던 자리', (tester) async {
      await openSheet(
        tester,
        passes: [
          buildPass(status: 'refunded', validUntil: today.add(const Duration(days: 200))),
        ],
      );

      expect(find.text('신청하기'), findsNothing);
      expect(find.textContaining('환불된 회원권은 일시정지할 수 없어요'), findsOneWidget);
      // 막았으면 빠져나갈 길을 준다(동의 시트의 "다시 불러오기"와 같은 규약).
      expect(find.text('닫기'), findsOneWidget);
    });

    testWidgets('후보가 없으면 원본 목록으로 폴백하지 않는다', (tester) async {
      await openSheet(tester, passes: [
        buildPass(status: 'expired'),
        buildPass(id: 'p2', status: 'refunded'),
      ]);

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('신청하기'), findsNothing);
      expect(find.textContaining('이용 중인 회원권이 없어요'), findsOneWidget);
    });

    testWidgets('대표 패스가 후보에 없으면 남은 active 후보로 정규화된다', (tester) async {
      await openSheet(
        tester,
        // 대표(initialPassId)가 환불 패스 — 종전엔 그게 그대로 선택돼 제출됐다.
        passes: [buildPass(status: 'refunded'), buildPass(id: 'p2', product: '살아있는 30회')],
        initialPassId: 'p1',
      );
      await pickToday(tester, '시작일');
      await pickToday(tester, '종료일');
      await tester.tap(find.text('신청하기'));
      await tester.pumpAndSettle();

      expect(repo.holdCalls.single.passId, 'p2');
    });
  });

  group('③ 재개 — 서버 ResumePass는 active만 받는다', () {
    PassDetail heldPass({required String status}) => buildPass(
          status: status,
          holds: [
            PassHold(
              from: today.subtract(const Duration(days: 2)),
              to: today.add(const Duration(days: 8)),
            ),
          ],
        );

    testWidgets('active 패스면 종전대로 배지와 재개 버튼이 뜬다', (tester) async {
      await pump(tester, PassList(passes: [heldPass(status: 'active')], onHoldTap: () {}));

      expect(find.text('재개'), findsOneWidget);
      expect(find.textContaining('일시정지 중'), findsOneWidget);
    });

    testWidgets('환불 패스에 오늘을 덮는 홀딩이 남아 있어도 재개 버튼을 주지 않는다', (tester) async {
      // RefundPass는 status만 바꾸고 holds는 그대로 둔다 — 실제로 생기는 조합이다.
      await pump(tester, PassList(passes: [heldPass(status: 'refunded')], onHoldTap: () {}));

      expect(find.text('재개'), findsNothing);
      // '환불' 배지 옆의 '일시정지 중'은 "아직 살아 있는 회원권"으로 읽힌다 — 함께 감춘다.
      expect(find.textContaining('일시정지 중'), findsNothing);
      expect(find.text('환불'), findsOneWidget);
    });

    testWidgets('만료 패스도 마찬가지', (tester) async {
      await pump(tester, PassList(passes: [heldPass(status: 'expired')], onHoldTap: () {}));

      expect(find.text('재개'), findsNothing);
    });
  });

  group('③ 계약 서명 — 환불된 거래는 서버가 거부한다', () {
    const sentContract = ContractItem(
      id: 'c1',
      passId: 'p1',
      product: 'PT 20회',
      paidAmount: 1200000,
      status: 'sent',
    );

    final detailTaps = <String>[];

    Widget contractsRow({Set<String> refunded = const {}}) => ContractsRow(
          contracts: const [sentContract],
          consent: const ConsentState(general: true, sensitive: true),
          refundedPassIds: refunded,
          onConsentTap: () {},
          onSignTap: (c) => repo.signTaps.add(c.id),
          onDetailTap: (c) => detailTaps.add(c.id),
        );

    setUp(detailTaps.clear);

    testWidgets('정상 거래의 sent 계약은 종전대로 탭해서 서명한다', (tester) async {
      await pump(tester, contractsRow());

      expect(find.text('탭해서 내용 확인 후 서명할 수 있어요'), findsOneWidget);
      await tester.tap(find.text('PT 20회 계약'));
      await tester.pumpAndSettle();
      expect(repo.signTaps, ['c1']);
    });

    testWidgets('패스가 환불됐으면 sent 계약도 탭이 열리지 않고 이유를 말한다', (tester) async {
      await pump(tester, contractsRow(refunded: {'p1'}));

      expect(find.text('환불 처리된 거래예요 — 서명할 수 없어요'), findsOneWidget);
      expect(find.text('탭해서 내용 확인 후 서명할 수 있어요'), findsNothing);

      await tester.tap(find.text('PT 20회 계약'));
      await tester.pumpAndSettle();
      expect(repo.signTaps, isEmpty, reason: '서버가 400으로 막을 서명 시트를 열면 안 된다');
      // 대신 읽기 전용 상세로 간다 — 무엇에 얼마를 냈는지는 계속 볼 수 있어야 한다.
      expect(detailTaps, ['c1']);
      // 서버가 준 상태를 지어내 바꾸지는 않는다(status는 여전히 sent다).
      expect(find.text('서명 대기'), findsOneWidget);
    });
  });
}

/// 시트를 실제 진입점(`showHoldRequestSheet`)으로 띄우는 호스트.
class _SheetHost extends ConsumerWidget {
  const _SheetHost({required this.passes, required this.initialPassId});
  final List<PassDetail> passes;
  final String initialPassId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (inner) => Center(
        child: TextButton(
          onPressed: () =>
              showHoldRequestSheet(inner, passes: passes, initialPassId: initialPassId),
          child: const Text('열기'),
        ),
      ),
    );
  }
}

class _FakeMyRepository implements MyRepository {
  /// 서버로 나간 홀딩 신청 — "막았는가"의 유일한 증거.
  final List<({String passId, DateTime from, DateTime to})> holdCalls = [];
  final List<String> signTaps = [];

  @override
  Future<Result<MySummary>> load(String memberId) async => const Ok(
        MySummary(passes: [], ledgerByPass: {}, contracts: [], consent: ConsentState(general: true, sensitive: true)),
      );

  @override
  Future<Result<void>> requestHold({
    required String passId,
    required DateTime from,
    required DateTime to,
    String? reason,
  }) async {
    holdCalls.add((passId: passId, from: from, to: to));
    return const Ok(null);
  }

  @override
  Future<Result<void>> resumeHold(String passId) async => const Ok(null);

  @override
  Future<Result<void>> updateConsent({
    required String memberId,
    required bool general,
    required bool sensitive,
  }) async =>
      const Ok(null);


  @override
  Future<Result<void>> signContract(String contractId, {String? signaturePng}) async =>
      const Ok(null);

  // 이 파일들은 탈퇴를 다루지 않는다 — 호출되면 그 자체가 결함이므로 조용히 성공시키지 않는다.
  @override
  Future<Result<AccountDeletionSummary>> deleteAccount() => throw UnimplementedError();
}
