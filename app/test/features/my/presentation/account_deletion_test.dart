import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/domain/my_repository.dart';
import 'package:rise_member/features/my/presentation/account_deletion_screen.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';

// 회원탈퇴 확인 화면(API계약 v2.11 · App Store Guideline 5.1.1(v)).
//
// 이 화면에서 지켜야 하는 것은 "버튼이 눌리는가"가 아니다:
//
//   ① **확인 전에는 절대 호출되지 않는다.** 탈퇴는 되돌릴 수 없고 서버에 재시도 경로도 없다
//      (두 번째 DELETE는 404다). 실수로 나간 요청 하나가 곧 영구 손실이다.
//   ② **화면이 사실만 말한다.** 무엇이 지워지고 무엇이 왜 남는지를 회원이 읽을 수 있어야
//      한다(Guideline 5.1.1(v)의 "구체적으로 고지"). 목록이 서버가 하는 일과 어긋나면
//      그건 문구 실수가 아니라 개인정보 처리에 대한 거짓 고지다.
//   ③ **남은 회차를 숨기지 않는다.** 서버는 잔여가 있어도 탈퇴를 막지 않으므로, 정산 기회를
//      주는 지점은 이 화면 하나뿐이다.
void main() {
  late _FakeMyRepository repo;

  setUp(() => repo = _FakeMyRepository());

  Future<ProviderContainer> pump(WidgetTester tester, {List<PassDetail> passes = const []}) async {
    repo.passes = passes;
    final container = ProviderContainer.test(
      // Riverpod 3은 실패한 provider를 **자동 재시도**한다(지수 백오프 타이머). 조회 실패
      // 경로를 검증하는 테스트에서 그 타이머가 트리 dispose 후까지 살아 남아 실패한다.
      retry: (_, __) => null,
      overrides: [
        myRepositoryProvider.overrideWithValue(repo),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).set(
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1'),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const AccountDeletionScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// 성공 경로 전용 하네스 — 탈퇴 뒤의 `context.go('/login')`까지 실제로 태운다.
  /// 라우터 없이 pump하면 그 이동이 던져서, **되돌릴 수 없는 동작의 마지막 절반**이
  /// 테스트를 한 번도 지나지 않게 된다.
  Future<ProviderContainer> pumpWithRouter(WidgetTester tester) async {
    final container = ProviderContainer.test(
      overrides: [
        myRepositoryProvider.overrideWithValue(repo),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).set(
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1'),
        );
    final router = GoRouter(
      initialLocation: '/my',
      routes: [
        GoRoute(path: '/my', builder: (_, __) => const AccountDeletionScreen()),
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('로그인', key: Key('login-stub'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// 확인 체크박스·버튼은 **고지문을 다 지나야** 나온다(ListView 지연 생성).
  /// 실기기에서도 같은 순서로 마주치므로 테스트가 그 동선을 그대로 따른다.
  Future<void> scrollToConfirm(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byType(Checkbox),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.textContaining(text));

  group('고지 — 무엇이 지워지고 무엇이 왜 남는지', () {
    testWidgets('삭제 항목과 보존 항목을 각각 이유와 함께 보여준다', (tester) async {
      await pump(tester);

      expect(find.text('삭제되는 정보'), findsOneWidget);
      expect(find.text('법에 따라 보관되는 정보'), findsOneWidget);

      // 민감정보(건강)는 **지운다**고 명시해야 한다 — 이 둘을 남기는 설계였다면 화면도
      // 달라야 하고, 반대로 화면만 "지운다"고 하면 거짓 고지가 된다.
      expect(find.text('체형사진(원본 파일까지 삭제)'), findsOneWidget);
      expect(find.text('인바디 기록'), findsOneWidget);

      // 보존 항목은 **이유가 반드시 붙는다**("일부 정보는 보관됩니다"로는 요건 미충족).
      for (final row in withdrawalRetainedItems) {
        expect(find.text(row.item), findsOneWidget, reason: '보존 항목 "${row.item}"이 화면에 없다');
        // 사유는 항목끼리 겹칠 수 있다(회원권 내역·전자계약서가 같은 조항) — 존재만 본다.
        expect(find.text(row.reason), findsWidgets, reason: '보존 사유 "${row.reason}"가 화면에 없다');
      }

      // 5년 보존이 곧 "내 이름이 5년 남는다"로 읽히지 않게 해명한다.
      expect(find.textContaining('이름과 전화번호는 함께 지워져요'), findsOneWidget);
    });

    testWidgets('비가역성을 진입 즉시 알린다(다이얼로그를 열기 전에)', (tester) async {
      await pump(tester);
      expect(find.textContaining('되돌릴 수 없어요'), findsWidgets);
      expect(find.textContaining('같은 번호로 다시 가입해도'), findsWidgets);
    });
  });

  group('잔여 회차 — 막지 않고 알린다', () {
    testWidgets('남은 회차가 있으면 자동 환불되지 않는다는 사실을 띄운다', (tester) async {
      await pump(tester, passes: [_pass(remaining: 7)]);

      expect(find.textContaining('아직 7회가 남아 있어요'), findsOneWidget);
      expect(find.textContaining('자동으로 환불되지 않아요'), findsOneWidget);
    });

    testWidgets('남은 회차가 있어도 탈퇴 자체는 막지 않는다', (tester) async {
      await pump(tester, passes: [_pass(remaining: 7)]);

      await scrollToConfirm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '탈퇴하기'));
      await tester.pumpAndSettle();

      // 다이얼로그가 떴다 = 버튼이 살아 있다(사업상 상태로 앱 내 삭제를 막을 수 없다).
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('만료·환불된 회원권의 잔여는 세지 않는다', (tester) async {
      // 쓸 수 없는 회원권의 숫자를 더하면 "환불받을 게 있다"는 잘못된 기대를 만든다.
      await pump(tester, passes: [_pass(remaining: 5, status: 'refunded')]);
      expect(find.textContaining('남아 있어요'), findsNothing);
    });

    testWidgets('회원권 조회에 실패하면 "확인하지 못했어요"라고 말한다(없다고 단정하지 않는다)', (tester) async {
      // 상자를 그냥 빼면 "남은 회차 없음"과 구별되지 않고, 회원은 정산할 게 있다는 사실을
      // 되돌릴 수 없게 된 뒤에야 알게 된다.
      repo.loadFailure = const NetworkFailure();
      await pump(tester);

      expect(find.textContaining('확인하지 못했어요'), findsOneWidget);
      expect(find.textContaining('자동으로 환불되지 않아요'), findsOneWidget);
      // 그래도 탈퇴 자체는 가능해야 한다 — 조회 실패가 계정 삭제를 막으면 심사에 걸린다.
      await scrollToConfirm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '탈퇴하기')).onPressed,
        isNotNull,
      );
    });
  });

  group('확인 — 요청은 두 겹을 통과해야만 나간다', () {
    testWidgets('체크 전에는 탈퇴 버튼이 잠겨 있다', (tester) async {
      await pump(tester);
      await scrollToConfirm(tester);

      // 버튼의 **활성 상태 자체**를 본다. 탭해서 "아무 일도 안 일어난다"만 확인하면,
      // 버튼이 활성인데 안쪽 재확인이 막아주는 상태와 구별되지 않는다 — 두 겹 중
      // 바깥 겹이 사라진 것을 그 테스트는 잡지 못한다(뮤테이션 A2에서 실측).
      ElevatedButton button() => tester.widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, '탈퇴하기'),
          );
      expect(button().onPressed, isNull, reason: '체크 전인데 탈퇴 버튼이 활성이다');

      await tester.tap(find.widgetWithText(ElevatedButton, '탈퇴하기'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing, reason: '체크 없이 다이얼로그가 열렸다');
      expect(repo.deleteCalls, 0, reason: '체크 없이 서버 호출이 나갔다 — 되돌릴 수 없는 요청이다');

      // 체크하면 열린다(가드가 항상 잠그는 구현으로 도망가지 못하게 반대편도 고정).
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(button().onPressed, isNotNull);
    });

    testWidgets('체크만으로는 호출되지 않는다(다이얼로그 확인이 필요하다)', (tester) async {
      await pump(tester);

      await scrollToConfirm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '탈퇴하기'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(repo.deleteCalls, 0, reason: '다이얼로그가 뜬 시점에 이미 호출됐다 — 확인 전 실행');
    });

    testWidgets('다이얼로그에서 취소하면 호출되지 않는다', (tester) async {
      await pump(tester);

      await scrollToConfirm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '탈퇴하기'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog('그대로 두기'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 0);
      // 취소 후에도 화면은 살아 있어야 한다(체크 상태 유지 — 다시 읽으라고 되돌리지 않는다).
      expect(find.text('삭제되는 정보'), findsOneWidget);
    });

    testWidgets('체크 + 다이얼로그 확인을 모두 지나야 실제로 호출된다', (tester) async {
      final container = await pumpWithRouter(tester);

      await scrollToConfirm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '탈퇴하기'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog('탈퇴하기'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 1);

      // 성공 뒤에는 이 계정으로 아무것도 부를 수 없다 — 세션을 비우고 로그인으로 나가야
      // 한다. 화면에 남아 있으면 다음 새로고침이 전부 403으로 떨어져, 방금 성공한 탈퇴가
      // 에러 화면으로 보인다.
      expect(find.byKey(const Key('login-stub')), findsOneWidget, reason: '로그인 화면으로 나가지 않았다');
      expect(container.read(sessionProvider), isNull, reason: '앱 세션이 남았다');
      expect(find.textContaining('탈퇴가 완료됐어요'), findsOneWidget);

      // 스낵바 자동 해제 타이머를 흘려보낸다(위젯 트리 dispose 후 pending timer 방지).
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('실패 처리', () {
    testWidgets('서버가 거부하면 서버 문구를 그대로 보여주고 화면에 남는다', (tester) async {
      repo.failure = const RejectedFailure('스태프 계정은 탈퇴할 수 없어요');
      await pump(tester);

      await scrollToConfirm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '탈퇴하기'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog('탈퇴하기'));
      await tester.pumpAndSettle();

      expect(find.text('스태프 계정은 탈퇴할 수 없어요'), findsOneWidget);
      // 실패했으면 다시 시도할 수 있어야 한다 — 버튼이 '처리 중…'에 갇히면 안 된다.
      expect(find.text('처리 중…'), findsNothing);
      expect(find.text('삭제되는 정보'), findsOneWidget);
    });
  });

  group('완료 안내 문구(AccountDeletionSummary)', () {
    test('남은 회차가 있으면 정산 안내를 먼저 말한다', () {
      const s = AccountDeletionSummary(remainingSessions: 7);
      expect(s.completionMessage, contains('남은 7회'));
      expect(s.completionMessage, contains('센터에 문의'));
    });

    test('남은 회차가 없으면 정산 문구를 넣지 않는다', () {
      const s = AccountDeletionSummary();
      expect(s.completionMessage, isNot(contains('정산')));
      expect(s.completionMessage, contains('탈퇴가 완료됐어요'));
    });

    test('응답 필드가 비어 있어도 파싱이 던지지 않는다', () {
      // 이 호출이 200이면 계정은 **이미** 지워졌다. 요약 숫자 하나 때문에 예외를 올리면
      // 성공한 탈퇴가 실패 화면으로 보이고, 다시 눌러도 이제 404만 돌아온다.
      expect(() => AccountDeletionSummary.fromJson(const {}), returnsNormally);
      expect(AccountDeletionSummary.fromJson(const {}).remainingSessions, 0);

      final parsed = AccountDeletionSummary.fromJson(const {
        'purged': {'body_photos': 4, 'inbody': 2, 'workout_logs': 9, 'hw_checks': 12},
        'retained': {'passes': 2, 'payments': 3, 'contracts': 2},
        'cancelled_bookings': 1,
        'remaining_sessions': 7,
      });
      expect(parsed.bodyPhotos, 4);
      expect(parsed.inbody, 2);
      expect(parsed.retainedPayments, 3);
      expect(parsed.cancelledBookings, 1);
      expect(parsed.remainingSessions, 7);
    });
  });
}

PassDetail _pass({required int remaining, String status = 'active'}) {
  final now = DateTime.now();
  return PassDetail(
    id: 'p1',
    product: 'PT 20회',
    trainerId: 't1',
    trainerName: '정혜린',
    status: status,
    remaining: remaining,
    totalSessions: 20,
    paidAmount: 1000000,
    validFrom: now.subtract(const Duration(days: 10)),
    validUntil: now.add(const Duration(days: 60)),
  );
}

class _FakeMyRepository implements MyRepository {
  int deleteCalls = 0;
  Failure? failure;
  List<PassDetail> passes = const [];

  @override
  Future<Result<AccountDeletionSummary>> deleteAccount() async {
    deleteCalls++;
    if (failure case final f?) return Err(f);
    return const Ok(AccountDeletionSummary(bodyPhotos: 4, inbody: 2, remainingSessions: 0));
  }

  Failure? loadFailure;

  @override
  Future<Result<MySummary>> load(String memberId) async {
    if (loadFailure case final f?) return Err(f);
    return Ok(
      MySummary(
        passes: passes,
        ledgerByPass: const {},
        contracts: const [],
        consent: const ConsentState(general: true, sensitive: true),
      ),
    );
  }

  @override
  Future<Result<void>> updateConsent({
    required String memberId,
    required bool general,
    required bool sensitive,
  }) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> resumeHold(String passId) => throw UnimplementedError();

  @override
  Future<Result<void>> requestHold({
    required String passId,
    required DateTime from,
    required DateTime to,
    String? reason,
  }) =>
      throw UnimplementedError();


  @override
  Future<Result<void>> signContract(String contractId, {String? signaturePng}) =>
      throw UnimplementedError();
}
