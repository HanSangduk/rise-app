import 'package:clock/clock.dart';
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
import 'package:rise_member/features/my/presentation/widgets/pass_list.dart';

// 마이 탭 회원권 카드의 "일시정지 중" 배지 + **재개 버튼**이 자정에 굳던 문제(P17).
//
// `PassDetail.activeHold`는 부를 때마다 `todayKst()`를 다시 읽는 getter지만, 마이 탭은
// `StatefulShellRoute.indexedStack`에 상주해 아무도 리빌드해 주지 않는다. 홀딩
// 마지막 날 자정을 넘겨도 재개 버튼이 살아 있었고, 누르면 서버 `ResumePass`가
// 400으로 거부한다. 그 전에 **되돌릴 수 없는 소진**("이번 1회는 쓴 것으로 남아요")을
// 알리는 확인 다이얼로그가 이미 틀린 판정 위에 뜬다.
//
// 홈 회원권 카드와 같은 처방(`TimeBoundaryBuilder(atMidnight: true)`) — 서버 왕복 0.
// 시각은 UTC로 주입하고 기대값은 KST로 읽는다(TZ 독립).
void main() {
  late _FakeMyRepository repo;

  setUp(() => repo = _FakeMyRepository());

  /// KST 벽시계 2026-08-[day] [h]:[m]:[s]에 해당하는 절대 시각.
  DateTime kst(int day, int h, int m, [int s = 0]) => DateTime.utc(2026, 8, day, h - 9, m, s);

  PassDetail heldUntil(DateTime to) => PassDetail(
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
        holds: [PassHold(from: DateTime(2026, 8, 20), to: to)],
      );

  Future<void> pump(WidgetTester tester, PassDetail pass) async {
    final container = ProviderContainer.test(
      overrides: [
        myRepositoryProvider.overrideWithValue(repo),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
      ],
    );
    container.read(sessionProvider.notifier).set(
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1'),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: PassList(passes: [pass], onHoldTap: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 23:50 → 00:00:01. 경계 타이머는 +1초 여유를 두고 예약된다.
  Future<void> crossMidnight(WidgetTester tester, void Function(DateTime) setNow) async {
    setNow(kst(24, 0, 0, 1));
    await tester.pump(const Duration(minutes: 10, seconds: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('홀딩 마지막 날 자정을 넘기면 배지와 재개 버튼이 사라진다', (tester) async {
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      await pump(tester, heldUntil(DateTime(2026, 8, 23)));
      expect(find.text('일시정지 중 ~8/23'), findsOneWidget);
      expect(find.text('재개'), findsOneWidget);

      await crossMidnight(tester, (t) => now = t);

      expect(find.text('재개'), findsNothing,
          reason: '서버 ResumePass가 400으로 거부할 액션에 살아 있는 버튼을 주면 안 된다');
      expect(find.text('일시정지 중 ~8/23'), findsNothing,
          reason: '끝난 일시정지를 "중"이라고 말하면 회원은 회원권이 아직 멈춰 있다고 읽는다');
    });
  });

  testWidgets('아직 이어지는 홀딩은 자정을 넘겨도 그대로 — 배지를 잃으면 안 된다', (tester) async {
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      await pump(tester, heldUntil(DateTime(2026, 8, 30)));
      expect(find.text('재개'), findsOneWidget);

      await crossMidnight(tester, (t) => now = t);

      expect(find.text('일시정지 중 ~8/30'), findsOneWidget);
      expect(find.text('재개'), findsOneWidget);
    });
  });

  testWidgets('탭에 없는 동안엔 타이머를 돌리지 않는다', (tester) async {
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      final container = ProviderContainer.test(
        overrides: [
          myRepositoryProvider.overrideWithValue(repo),
          centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        ],
      );
      container.read(sessionProvider.notifier).set(
            const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1'),
          );
      Widget tree({required bool enabled}) => UncontrolledProviderScope(
            container: container,
            // go_router가 indexedStack의 비활성 브랜치를 감싸는 것과 같은 모양.
            child: MaterialApp(
              theme: buildAppTheme(),
              home: TickerMode(
                enabled: enabled,
                child: Scaffold(
                  body: PassList(passes: [heldUntil(DateTime(2026, 8, 23))], onHoldTap: () {}),
                ),
              ),
            ),
          );

      await tester.pumpWidget(tree(enabled: false));
      await tester.pumpAndSettle();
      await crossMidnight(tester, (t) => now = t);
      expect(find.text('재개'), findsOneWidget); // 안 보였으니 아직 안 그렸다

      // 탭으로 돌아오면 그때 맞춰진다(TickerMode는 InheritedWidget).
      await tester.pumpWidget(tree(enabled: true));
      await tester.pumpAndSettle();
      expect(find.text('재개'), findsNothing);
    });
  });
}

class _FakeMyRepository implements MyRepository {
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
  }) async =>
      const Ok(null);

  @override
  Future<Result<void>> resumeHold(String passId) async => const Ok(null);

  @override
  Future<Result<void>> requestHold({
    required String passId,
    required DateTime from,
    required DateTime to,
    String? reason,
  }) async =>
      const Ok(null);


  @override
  Future<Result<void>> signContract(String contractId, {String? signaturePng}) async =>
      const Ok(null);

  // 이 파일들은 탈퇴를 다루지 않는다 — 호출되면 그 자체가 결함이므로 조용히 성공시키지 않는다.
  @override
  Future<Result<AccountDeletionSummary>> deleteAccount() => throw UnimplementedError();
}
