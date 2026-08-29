import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
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
import 'package:rise_member/features/my/presentation/my_screen.dart';

// 동의 조회 실패 → 저장 한 번에 실제 동의가 법적 기록과 함께 철회되던 경로.
//
// 재현: 마이 탭 로드 중 일시적 네트워크 실패(실제 동의는 true/true) → 탭은 정상
// 렌더, 배지만 "동의 필요" → 회원이 시트를 열어 스위치가 꺼진 걸 보고 **토글을
// 건드리지 않은 채** "저장" → PUT이 false/false를 보내고, 서버가 sensitive
// true→false를 철회로 보아 revoked_at을 기록한다(normalizeConsentTransition).
// 그 순간부터 인바디·체형사진 저장이 400으로 잠긴다(SensitiveConsentValid).
//
// 이 앱에서 **법적 기록을 남기는 유일한 결함**이라 UI까지 내려와 고정한다:
// 화면이 거짓 배지를 띄우지 않고, 시트가 PUT을 아예 내보내지 않아야 한다.
void main() {
  late _FakeMyRepository repo;

  setUp(() => repo = _FakeMyRepository());

  Future<void> pumpMy(WidgetTester tester) async {
    final container = ProviderContainer.test(
      overrides: [
        myRepositoryProvider.overrideWithValue(repo),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        staffMapProvider.overrideWithValue(const AsyncValue<Map<String, StaffDto>>.data({})),
      ],
    );
    container.read(sessionProvider.notifier).set(
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람'),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const MyScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openConsentSheet(WidgetTester tester) async {
    await tester.tap(find.text('민감정보(인바디·체형사진) 동의').first);
    await tester.pumpAndSettle();
  }

  group('동의 조회 실패 — 저장 자체를 막는다', () {
    testWidgets('배지가 "동의 필요"가 아니라 "확인 실패" — 모름을 미동의로 말하지 않는다', (tester) async {
      repo.consentFailed = true;
      await pumpMy(tester);

      expect(find.text('확인 실패'), findsOneWidget);
      expect(find.text('동의 필요'), findsNothing);
    });

    testWidgets('시트에 "저장" 버튼이 없다 — 누를 수 있으면 언젠가 눌린다', (tester) async {
      repo.consentFailed = true;
      await pumpMy(tester);
      await openConsentSheet(tester);

      expect(find.widgetWithText(ElevatedButton, '저장'), findsNothing);
      expect(find.text('다시 불러오기'), findsOneWidget, reason: '막았으면 빠져나갈 길을 줘야 한다');
    });

    testWidgets('스위치도 잠긴다 — 켰다 끄면 저장이 열리는 뒷문이 없어야 한다', (tester) async {
      repo.consentFailed = true;
      await pumpMy(tester);
      await openConsentSheet(tester);

      final tiles = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
      expect(tiles, hasLength(2));
      expect(tiles.map((t) => t.onChanged), everyElement(isNull));
    });

    testWidgets('시트를 열고 닫는 동안 PUT은 한 번도 나가지 않는다', (tester) async {
      repo.consentFailed = true;
      await pumpMy(tester);
      await openConsentSheet(tester);

      // 회원이 실제로 하는 일: 스위치를 눌러 보고 버튼을 누른다.
      await tester.tap(find.byType(SwitchListTile).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('다시 불러오기'));
      await tester.pumpAndSettle();

      expect(repo.consentWrites, isEmpty,
          reason: '조회 실패 상태의 화면 값이 서버로 나가면 실제 동의가 철회된다');
    });

    testWidgets('"다시 불러오기"는 재조회 — 데드엔드로 두지 않는다', (tester) async {
      repo.consentFailed = true;
      await pumpMy(tester);
      final before = repo.loadCount;
      await openConsentSheet(tester);
      await tester.tap(find.text('다시 불러오기'));
      await tester.pumpAndSettle();

      expect(repo.loadCount, greaterThan(before));
    });
  });

  group('정상 조회 — 종전 동작 유지', () {
    testWidgets('동의 상태를 알면 배지·저장이 그대로 살아 있다', (tester) async {
      // 잠금이 상시화되면 회원이 동의를 켜지도, 정당하게 철회하지도 못한다.
      repo.consent = const ConsentState(general: true, sensitive: true);
      await pumpMy(tester);

      expect(find.text('동의함 · 철회 가능'), findsOneWidget);
      expect(find.text('확인 실패'), findsNothing);

      await openConsentSheet(tester);
      final tiles = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
      expect(tiles.map((t) => t.onChanged), everyElement(isNotNull));
    });

    testWidgets('저장하면 화면 값이 그대로 PUT된다', (tester) async {
      repo.consent = const ConsentState(general: true, sensitive: true);
      await pumpMy(tester);
      await openConsentSheet(tester);

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(repo.consentWrites, [(general: true, sensitive: true)]);
    });
  });

  group('원장 조회 실패 — "아직 내역이 없어요"로 위장하지 않는다', () {
    testWidgets('실패한 패스의 원장 카드는 실패 문구를 보여준다', (tester) async {
      repo.ledgerFailedPassIds = {'p1'};
      await pumpMy(tester);

      expect(find.textContaining('이용 내역을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('아직 내역이 없어요'), findsNothing);
    });

    testWidgets('진짜 0건은 종전대로 빈 상태 문구', (tester) async {
      await pumpMy(tester);

      expect(find.text('아직 내역이 없어요'), findsOneWidget);
      expect(find.textContaining('이용 내역을 불러오지 못했어요'), findsNothing);
    });
  });
}

class _FakeMyRepository implements MyRepository {
  bool consentFailed = false;
  ConsentState consent = const ConsentState(general: false, sensitive: false);
  Set<String> ledgerFailedPassIds = const {};

  int loadCount = 0;

  /// 서버로 나간 동의 값 — "저장을 막았는가"의 유일한 증거.
  final List<({bool general, bool sensitive})> consentWrites = [];

  @override
  Future<Result<MySummary>> load(String memberId) async {
    loadCount++;
    return Ok(MySummary(
      passes: [
        PassDetail(
          id: 'p1',
          product: 'PT 20회',
          trainerId: 't1',
          status: 'active',
          remaining: 8,
          totalSessions: 20,
          paidAmount: 1200000,
          validFrom: DateTime(2026, 1, 1),
          validUntil: DateTime(2030, 12, 31),
        ),
      ],
      ledgerByPass: const {'p1': []},
      contracts: const [],
      consent: consent,
      ledgerFailedPassIds: ledgerFailedPassIds,
      consentFailed: consentFailed,
    ));
  }

  @override
  Future<Result<void>> updateConsent({
    required String memberId,
    required bool general,
    required bool sensitive,
  }) async {
    consentWrites.add((general: general, sensitive: sensitive));
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
  Future<Result<void>> resumeHold(String passId) async => const Ok(null);


  @override
  Future<Result<void>> signContract(String contractId) async => const Ok(null);

  // 이 파일들은 탈퇴를 다루지 않는다 — 호출되면 그 자체가 결함이므로 조용히 성공시키지 않는다.
  @override
  Future<Result<AccountDeletionSummary>> deleteAccount() => throw UnimplementedError();
}
