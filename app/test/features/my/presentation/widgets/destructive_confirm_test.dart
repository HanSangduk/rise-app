import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/domain/my_repository.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';
import 'package:rise_member/features/my/presentation/widgets/consent_toggles.dart';
import 'package:rise_member/features/my/presentation/widgets/pass_list.dart';

// 마이 탭의 **비가역 액션 두 개**가 확인 없이 실행되던 문제(P12 감사 M10).
//
// ① 동의 철회 — PUT 한 번으로 서버에 `revoked_at`이 남고(감사 기록),
//    sensitive는 그 즉시 인바디·체형사진 신규 저장이 400으로 막힌다
//    (backend `domain/member.go` SensitiveConsentValid + CreateInbody/CreateBodyPhoto).
// ② 조기 재개 — 서버는 줄어든 홀딩도 횟수 상한에 계속 포함한다
//    (`domain/pass.go`: "조기 종료(Resume)된 홀딩도 횟수 상한에 포함된다").
//    10일 중 2일 만에 재개한 회원은 나중에 "상한 초과"로 거부당하고서야 알게 됐다.
//
// 기준선은 계약 서명 시트다 — 그쪽만 동의 체크박스로 방어되고 있었다.
void main() {
  late _FakeMyRepository repo;

  setUp(() => repo = _FakeMyRepository());

  Future<ProviderContainer> pump(
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
    return container;
  }

  group('동의 철회 — 저장 전에 확인을 받는다', () {
    /// 시트를 띄운 상태까지 만들어 준다(모달 라우팅은 이 테스트의 관심사가 아니지만,
    /// 실제 진입점 `showConsentToggles`를 그대로 거쳐야 회귀가 잡힌다).
    Future<void> openSheet(WidgetTester tester, ConsentState consent) async {
      await pump(tester, _SheetHost(consent: consent));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
    }

    testWidgets('민감정보 토글을 끄면 결과가 먼저 보인다(저장 누르기 전)', (tester) async {
      await openSheet(tester, const ConsentState(general: true, sensitive: true));

      expect(find.textContaining('인바디·체형 기록을 새로 저장할 수 없어요'), findsNothing);

      await tester.tap(find.text('민감정보(인바디·체형사진) 동의'));
      await tester.pumpAndSettle();

      expect(find.textContaining('인바디·체형 기록을 새로 저장할 수 없어요'), findsOneWidget);
      expect(find.textContaining('이미 저장된 기록은 그대로 볼 수 있어요'), findsOneWidget);
    });

    testWidgets('저장을 눌러도 확인 전에는 PUT이 나가지 않는다', (tester) async {
      await openSheet(tester, const ConsentState(general: true, sensitive: true));

      await tester.tap(find.text('민감정보(인바디·체형사진) 동의'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(find.text('동의를 철회할까요?'), findsOneWidget);
      expect(repo.consentCalls, isEmpty);
    });

    testWidgets('"그대로 두기"를 고르면 철회되지 않는다', (tester) async {
      await openSheet(tester, const ConsentState(general: true, sensitive: true));

      await tester.tap(find.text('민감정보(인바디·체형사진) 동의'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('그대로 두기'));
      await tester.pumpAndSettle();

      expect(repo.consentCalls, isEmpty);
      // 시트는 열린 채로 남아 다시 켤 수 있어야 한다(작업이 사라지면 안 된다).
      expect(find.text('동의 관리'), findsOneWidget);
    });

    testWidgets('"철회하기"를 고르면 그때 PUT이 나간다', (tester) async {
      await openSheet(tester, const ConsentState(general: true, sensitive: true));

      await tester.tap(find.text('민감정보(인바디·체형사진) 동의'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('철회하기'));
      await tester.pumpAndSettle();

      expect(repo.consentCalls, [(general: true, sensitive: false)]);
    });

    testWidgets('일반 이용 동의 철회도 무경고로 지나가지 않는다', (tester) async {
      await openSheet(tester, const ConsentState(general: true, sensitive: false));

      await tester.tap(find.text('일반 이용 동의'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(find.text('동의를 철회할까요?'), findsOneWidget);
      expect(find.textContaining('예약·결제 등 서비스 이용의 근거'), findsWidgets);
    });

    testWidgets('켜는 방향만 있으면 묻지 않는다(마찰을 늘리지 않는다)', (tester) async {
      await openSheet(tester, const ConsentState(general: true, sensitive: false));

      await tester.tap(find.text('민감정보(인바디·체형사진) 동의'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(find.text('동의를 철회할까요?'), findsNothing);
      expect(repo.consentCalls, [(general: true, sensitive: true)]);
    });
  });

  group('조기 재개 — 무엇이 소진되는지 말하고 확인을 받는다', () {
    PassDetail heldPass({List<PassHold>? holds}) {
      final today = DateTime.now();
      return PassDetail(
        id: 'pass1',
        product: 'PT 20회',
        trainerId: 't1',
        trainerName: '정혜린',
        status: 'active',
        remaining: 12,
        totalSessions: 20,
        paidAmount: 800000,
        validFrom: DateTime(2026, 1, 1),
        validUntil: DateTime(2026, 12, 31),
        holds: holds ??
            [
              PassHold(
                from: today.subtract(const Duration(days: 2)),
                to: today.add(const Duration(days: 8)),
              ),
            ],
      );
    }

    testWidgets('재개 버튼은 곧장 POST하지 않고 확인을 띄운다', (tester) async {
      await pump(tester, PassList(passes: [heldPass()], onHoldTap: () {}));

      await tester.tap(find.text('재개'));
      await tester.pumpAndSettle();

      expect(find.text('일시정지를 지금 끝낼까요?'), findsOneWidget);
      expect(repo.resumeCalls, isEmpty);
    });

    testWidgets('문구가 "1회 소진"과 상한 실값을 말한다', (tester) async {
      await pump(tester, PassList(passes: [heldPass()], onHoldTap: () {}));

      await tester.tap(find.text('재개'));
      await tester.pumpAndSettle();

      expect(find.textContaining('이번 일시정지 1회는 쓴 것으로 남아요'), findsOneWidget);
      // 정책 실값(fallback = 2회) + 이 패스가 쓴 횟수(1회).
      expect(find.textContaining('최대 2회 중 1회를 썼어요'), findsOneWidget);
      // 되돌아가는 유효기간도 말한다(서버 ResumeHold가 안 쓴 날짜를 회수한다).
      // hold.to를 "만료일"로 오독하게 쓰지 않는지도 함께 고정한다.
      expect(find.textContaining('실제로 쉰 날짜만 남기고 다시 당겨져요'), findsOneWidget);
      expect(find.textContaining('정지 예정일'), findsOneWidget);
    });

    testWidgets('"더 쉬기"면 재개하지 않는다', (tester) async {
      await pump(tester, PassList(passes: [heldPass()], onHoldTap: () {}));

      await tester.tap(find.text('재개'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('더 쉬기'));
      await tester.pumpAndSettle();

      expect(repo.resumeCalls, isEmpty);
    });

    testWidgets('"지금 재개"면 그때 POST가 나간다', (tester) async {
      await pump(tester, PassList(passes: [heldPass()], onHoldTap: () {}));

      await tester.tap(find.text('재개'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('지금 재개'));
      await tester.pumpAndSettle();

      expect(repo.resumeCalls, ['pass1']);
    });

    testWidgets('횟수 무제한 정책(-1)에선 "최대 N회" 문구를 지어내지 않는다', (tester) async {
      await pump(
        tester,
        PassList(passes: [heldPass()], onHoldTap: () {}),
        policy: const CenterPolicy(
          slotCapacity: 3,
          cancelCutoffHours: 24,
          graceOnce: true,
          penaltyRate: 0.10,
          expiringDays: 7,
          maxHoldsPerPass: -1,
          maxHoldTotalDays: 30,
        ),
      );

      await tester.tap(find.text('재개'));
      await tester.pumpAndSettle();

      expect(find.textContaining('이번 일시정지 1회는 쓴 것으로 남아요'), findsOneWidget);
      expect(find.textContaining('최대 -1회'), findsNothing);
    });
  });

  group('일시정지 신청 안내 — 조기 재개 비용을 신청 전에 말한다', () {
    testWidgets('회원권 카드 안내가 "그냥 늘어난다"로 끝나지 않는다', (tester) async {
      await pump(
        tester,
        PassList(
          passes: [
            PassDetail(
              id: 'pass1',
              product: 'PT 20회',
              trainerId: 't1',
              trainerName: '정혜린',
              status: 'active',
              remaining: 12,
              totalSessions: 20,
              paidAmount: 800000,
              validFrom: DateTime(2026, 1, 1),
              validUntil: DateTime(2026, 12, 31),
            ),
          ],
          onHoldTap: () {},
        ),
      );

      expect(find.textContaining('중간에 재개해도 그 1회는 쓴 것으로 남아요'), findsOneWidget);
    });
  });
}

/// 시트를 모달이 아니라 화면에 직접 얹는 호스트 — 시트 위젯 자체의 판정만 본다
/// (showModalBottomSheet의 라우팅은 이 테스트의 관심사가 아니다).
class _SheetHost extends ConsumerWidget {
  const _SheetHost({required this.consent});
  final ConsentState consent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (inner) => Center(
        child: TextButton(
          onPressed: () => showConsentToggles(inner, consent: consent),
          child: const Text('열기'),
        ),
      ),
    );
  }
}

class _FakeMyRepository implements MyRepository {
  final List<({bool general, bool sensitive})> consentCalls = [];
  final List<String> resumeCalls = [];

  @override
  Future<Result<MySummary>> load(String memberId) async => const Ok(
        MySummary(
          passes: [],
          ledgerByPass: {},
          contracts: [],
          consent: ConsentState(general: true, sensitive: true),
        ),
      );

  @override
  Future<Result<void>> updateConsent({
    required String memberId,
    required bool general,
    required bool sensitive,
  }) async {
    consentCalls.add((general: general, sensitive: sensitive));
    return const Ok(null);
  }

  @override
  Future<Result<void>> resumeHold(String passId) async {
    resumeCalls.add(passId);
    return const Ok(null);
  }

  @override
  Future<Result<void>> requestHold({
    required String passId,
    required DateTime from,
    required DateTime to,
    String? reason,
  }) async =>
      const Ok(null);


  @override
  Future<Result<void>> signContract(String contractId) async => const Ok(null);

  // 이 파일들은 탈퇴를 다루지 않는다 — 호출되면 그 자체가 결함이므로 조용히 성공시키지 않는다.
  @override
  Future<Result<AccountDeletionSummary>> deleteAccount() => throw UnimplementedError();
}
