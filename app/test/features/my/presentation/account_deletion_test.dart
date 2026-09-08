import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:rise_member/features/auth/domain/auth_models.dart';
import 'package:rise_member/features/auth/domain/auth_repository.dart';
import 'package:rise_member/features/auth/domain/join_request_store.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
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
  late _FakeJoinRequestStore joinStore;

  setUp(() {
    repo = _FakeMyRepository();
    joinStore = _FakeJoinRequestStore();
  });

  /// 인증 쪽 가짜 — 성공 뒤 `_signOut`이 `restartWithNewPhone()`(Firebase 로그아웃 + 인증
  /// 플로우 초기화)을 부르므로 실제 Firebase에 닿지 않게 막는다.
  final authRepo = _FakeAuthRepository();

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<PassDetail> passes = const [],
    AccountDeletionScope scope = AccountDeletionScope.member,
    JoinRequestTrace trace = JoinRequestTrace.unknown,
    AccountDeletionUnknownReason unknownReason = AccountDeletionUnknownReason.connectionCheckFailed,
  }) async {
    repo.passes = passes;
    final container = ProviderContainer.test(
      // Riverpod 3은 실패한 provider를 **자동 재시도**한다(지수 백오프 타이머). 조회 실패
      // 경로를 검증하는 테스트에서 그 타이머가 트리 dispose 후까지 살아 남아 실패한다.
      retry: (_, __) => null,
      overrides: [
        myRepositoryProvider.overrideWithValue(repo),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        authRepositoryProvider.overrideWithValue(authRepo),
        joinRequestStoreProvider.overrideWithValue(joinStore),
      ],
    );
    addTearDown(container.dispose);
    // 대기실 계정에는 세션이 없다 — 회원 scope에서만 심는다.
    if (scope == AccountDeletionScope.member) {
      container.read(sessionProvider.notifier).set(
            const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1'),
          );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: AccountDeletionScreen(scope: scope, joinRequestTrace: trace, unknownReason: unknownReason),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// 성공 경로 전용 하네스 — 탈퇴 뒤의 `context.go('/login')`까지 실제로 태운다.
  /// 라우터 없이 pump하면 그 이동이 던져서, **되돌릴 수 없는 동작의 마지막 절반**이
  /// 테스트를 한 번도 지나지 않게 된다.
  ///
  /// 확인 화면은 운영과 같이 **push된 라우트**로 띄운다(마이 탭·대기실이 `Navigator.push`).
  /// 라우터의 페이지로 직접 두면 시스템 백이 앱 종료(bubble)로 빠져 PopScope 유무를 잴 수
  /// 없다 — M2 테스트가 그 차이를 본다.
  Future<ProviderContainer> pumpWithRouter(
    WidgetTester tester, {
    AccountDeletionScope scope = AccountDeletionScope.member,
    JoinRequestTrace trace = JoinRequestTrace.unknown,
  }) async {
    final container = ProviderContainer.test(
      retry: (_, __) => null,
      overrides: [
        myRepositoryProvider.overrideWithValue(repo),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        authRepositoryProvider.overrideWithValue(authRepo),
        joinRequestStoreProvider.overrideWithValue(joinStore),
      ],
    );
    addTearDown(container.dispose);
    if (scope == AccountDeletionScope.member) {
      container.read(sessionProvider.notifier).set(
            const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1'),
          );
    }
    final router = GoRouter(
      initialLocation: '/my',
      routes: [
        GoRoute(
          path: '/my',
          builder: (_, __) => _PushHost(scope: scope, trace: trace),
        ),
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
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return container;
  }

  /// 엔진이 하드웨어 백에서 보내는 것과 같은 플랫폼 메시지(login_back_test와 같은 관용구).
  Future<void> pressSystemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pump();
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

      // 5년 보존이 곧 "내 이름이 5년 남는다"로 읽히지 않게 해명하되, **예외를 숨기지 않는다**.
      //
      // 종전 문구는 "보존되는 기록에서도 이름과 전화번호는 함께 지워져요"라고 단정했는데
      // 서명한 계약서는 예외다(P53 결정 3 — 봉인 해시가 vars를 포함해 이름을 바꾸면 위·변조
      // 검출이 영구 불가). 서버가 안 지우는 것을 화면이 "지웁니다"라고 말하면 그건 문구
      // 실수가 아니라 **개인정보에 대한 거짓 고지**다(account_deletion.dart 헤더의 경고).
      expect(find.textContaining('이름과 전화번호가 지워져요'), findsOneWidget);
      expect(
        find.textContaining('계약서는 문서 그대로'),
        findsOneWidget,
        reason: '계약서 예외를 숨기면 헤더가 경고한 거짓 고지가 된다',
      );
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

  group('대기실 계정(unlinked scope) — 없는 것에 대한 고지를 하지 않는다 (P56 A1)', () {
    // 서버 `deleteUnlinkedAccount`(v2.27)가 실제로 하는 일은 셋뿐이다 — Firebase 계정·
    // 가입 요청·로그인 매핑. 회원 화면을 그대로 쓰면 회원권도 사진도 없는 사람에게
    // "체형사진이 삭제되고 회원권 내역은 5년 보관돼요"라고 말하게 된다.
    testWidgets('제목·파기 목록·남는 것·체크 문구가 전부 대기실 계정의 것이다', (tester) async {
      await pump(tester, scope: AccountDeletionScope.unlinked);

      expect(find.text('계정 삭제'), findsOneWidget); // AppBar
      expect(find.text('회원탈퇴'), findsNothing);
      for (final item in unlinkedDeletionPurgedItems(JoinRequestTrace.unknown)) {
        expect(find.text(item), findsOneWidget, reason: '"$item"이 화면에 없다');
      }
      for (final item in withdrawalPurgedItems) {
        expect(find.text(item), findsNothing, reason: '"$item" — 없는 것에 대한 고지');
      }
      expect(find.text('법에 따라 보관되는 정보'), findsNothing);
      expect(find.text('여기서 지워지지 않는 정보'), findsOneWidget);
      expect(find.textContaining('센터에 직접 요청해주세요'), findsOneWidget); // 다음 행동
      // 회원권 상자는 그리지 않는다 — "확인하지 못했어요"도 없는 회원권을 있을지 모른다고 말한다.
      expect(find.textContaining('남은 회차'), findsNothing);

      await scrollToConfirm(tester);
      expect(find.text('위 내용을 모두 확인했고, 계정 삭제에 동의해요'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, '삭제하기'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, '탈퇴하기'), findsNothing);
    });

    testWidgets('두 겹 확인을 지나면 호출되고, 로그인으로 나가며, 로컬 대기 기록과 인증 상태를 지운다',
        (tester) async {
      // 요청을 보낸 상태(pending) — 서버는 그 요청 1건을 지우고 건수를 돌려준다.
      repo.summary = const AccountDeletionSummary(memberId: '', joinRequests: 1);
      final container = await pumpWithRouter(
        tester,
        scope: AccountDeletionScope.unlinked,
        trace: JoinRequestTrace.pending,
      );
      // 대기실에 있던 사람의 상태 — 번호와 로컬 대기 기록이 남아 있다.
      container.read(authViewModelProvider.notifier).setPhone('01012345678');
      joinStore.record = JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime.now());

      await scrollToConfirm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '삭제하기'));
      await tester.pumpAndSettle();
      expect(inDialog('보낸 가입 요청과 인증 계정을 삭제해요'), findsOneWidget);
      expect(repo.deleteCalls, 0);
      await tester.tap(inDialog('삭제하기'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 1);
      expect(find.byKey(const Key('login-stub')), findsOneWidget, reason: '로그인 화면으로 나가지 않았다');
      expect(find.textContaining('계정과 보낸 가입 요청을 삭제했어요'), findsOneWidget);
      expect(find.textContaining('탈퇴가 완료됐어요'), findsNothing, reason: '회원이 된 적 없는 사람에게 탈퇴라 말했다');
      // 서버가 가입 요청을 파기했으므로 로컬 기록은 거짓이다 — 남기면 같은 번호로 다시
      // 인증했을 때 보낸 적 없는 "승인 대기 중"이 뜬다.
      expect(joinStore.record, isNull, reason: '로컬 대기 기록이 남았다');
      // 인증 플로우 상태도 버린다 — 남기면 로그인 화면에 지운 계정의 번호가 채워진 채 뜬다.
      expect(container.read(authViewModelProvider).phone, isEmpty, reason: '지운 계정의 번호가 남았다');
      expect(container.read(sessionProvider), isNull);

      await tester.pump(const Duration(seconds: 5)); // 스낵바 타이머
    });
  });

  group('대기실 계정의 고지는 가입 요청의 흔적(JoinRequestTrace)대로 말한다 (P63)', () {
    // 서버 ⑤는 요청 문서를 상태 무관 전부 지우지만 문서의 모양이 다르다: pending은 이름·번호
    // 원본, rejected·approved는 센터가 비운 {상태, 요청 시각}. 그리고 앱은 "요청 없음"을
    // 확답할 수 없다(코드 인증 직후엔 /v1/me를 부른 적이 없다) — unknown은 "있다면"으로.
    // 목록·경고 상자·다이얼로그 셋이 **같은 trace**를 따라야 한다(한 화면이 두 말 금지).

    testWidgets('unknown — 목록·경고 상자가 "있다면"으로 헤지한다', (tester) async {
      await pump(tester, scope: AccountDeletionScope.unlinked, trace: JoinRequestTrace.unknown);

      expect(find.text('보낸 가입 요청이 있다면 그 요청 (이름·전화번호)'), findsOneWidget);
      expect(find.text('보낸 가입 요청 (이름·전화번호)'), findsNothing, reason: '물어본 적 없는 요청을 단정했다');
      expect(find.text('앱 로그인 계정 (인증한 전화번호)'), findsOneWidget);
      expect(find.textContaining('보낸 가입 요청이 있다면 함께 지워지고'), findsOneWidget); // 경고 상자
      expect(find.textContaining('센터 연결 화면부터 다시 시작해요'), findsOneWidget);
      expect(find.textContaining('이 화면부터'), findsNothing, reason: '읽는 자리(삭제 화면)를 가리키는 자기지시');
    });

    testWidgets('pending — 목록·경고 상자가 단정형이다', (tester) async {
      await pump(tester, scope: AccountDeletionScope.unlinked, trace: JoinRequestTrace.pending);

      expect(find.text('보낸 가입 요청 (이름·전화번호)'), findsOneWidget);
      expect(find.textContaining('있다면'), findsNothing, reason: '요청이 있는 것을 알면서 헤지했다');
      expect(find.textContaining('가입 요청부터 다시 보내야 해요'), findsOneWidget); // 경고 상자
    });

    testWidgets('settled — 이름·번호가 없는 "가입 요청 기록"이라고 정확히 말한다', (tester) async {
      await pump(tester, scope: AccountDeletionScope.unlinked, trace: JoinRequestTrace.settled);

      expect(find.text('가입 요청 기록 (처리 상태·요청 시각)'), findsOneWidget);
      expect(find.text('보낸 가입 요청 (이름·전화번호)'), findsNothing, reason: '센터가 이미 비운 이름·번호를 지운다고 했다');
      expect(find.textContaining('가입 요청 기록도 함께 지워지고'), findsOneWidget); // 경고 상자
    });

    /// 체크 → 삭제하기 → 다이얼로그까지.
    Future<void> reachDialog(WidgetTester tester) async {
      await scrollToConfirm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '삭제하기'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    testWidgets('unknown — 다이얼로그도 헤지하고, 서버가 0건이면 완료 안내는 "계정을 삭제했어요"', (tester) async {
      // 뮤테이션: 완료 문구가 서버 건수를 무시하고 항상 "계정과 보낸 가입 요청을 삭제했어요"라
      // 말하면 여기서 죽는다.
      repo.summary = const AccountDeletionSummary(memberId: '', joinRequests: 0);
      await pumpWithRouter(tester, scope: AccountDeletionScope.unlinked, trace: JoinRequestTrace.unknown);

      await reachDialog(tester);
      expect(inDialog('인증 계정을 삭제해요'), findsOneWidget);
      expect(inDialog('보낸 가입 요청이 있다면 함께 삭제돼요'), findsOneWidget);
      expect(inDialog('보낸 가입 요청과 인증 계정을 삭제해요'), findsNothing);
      await tester.tap(inDialog('삭제하기'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-stub')), findsOneWidget);
      expect(find.text('계정을 삭제했어요.'), findsOneWidget);
      expect(find.textContaining('보낸 가입 요청을 삭제했어요'), findsNothing, reason: '지운 적 없는 요청을 지웠다고 했다');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('unknown으로 고지했는데 서버가 1건을 지웠으면 완료 안내는 그 사실을 말한다', (tester) async {
      // 기기 변경 뒤 로그인한 사람 — 앱은 몰랐지만 서버엔 pending이 있었다. 사전 고지는
      // "있다면"이었고, 완료 안내는 건수를 알므로 단정한다(서버가 실제로 한 일).
      repo.summary = const AccountDeletionSummary(memberId: '', joinRequests: 1);
      await pumpWithRouter(tester, scope: AccountDeletionScope.unlinked, trace: JoinRequestTrace.unknown);

      await reachDialog(tester);
      await tester.tap(inDialog('삭제하기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('계정과 보낸 가입 요청을 삭제했어요'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('settled — 다이얼로그가 "가입 요청 기록과 인증 계정"을 말한다', (tester) async {
      repo.summary = const AccountDeletionSummary(memberId: '', joinRequests: 1);
      await pumpWithRouter(tester, scope: AccountDeletionScope.unlinked, trace: JoinRequestTrace.settled);

      await reachDialog(tester);
      expect(inDialog('가입 요청 기록과 인증 계정을 삭제해요'), findsOneWidget);
      expect(inDialog('보낸 가입 요청과 인증 계정을 삭제해요'), findsNothing);
      expect(inDialog('가입 요청을 새로 보내야 해요'), findsOneWidget);
      await tester.tap(inDialog('그대로 두기'));
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 0);
    });

    testWidgets('settled — 완료 안내도 "가입 요청 기록"이다 (한 화면이 두 말 금지, P63 검증 반영)', (tester) async {
      // 뮤테이션: 완료 문구가 trace를 무시하면(항상 "보낸 가입 요청") 여기서 죽는다.
      repo.summary = const AccountDeletionSummary(memberId: '', joinRequests: 1);
      await pumpWithRouter(tester, scope: AccountDeletionScope.unlinked, trace: JoinRequestTrace.settled);

      await reachDialog(tester);
      await tester.tap(inDialog('삭제하기'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-stub')), findsOneWidget);
      expect(find.text('계정과 가입 요청 기록을 삭제했어요.'), findsOneWidget);
      expect(find.textContaining('보낸 가입 요청을 삭제했어요'), findsNothing, reason: '비워진 껍데기를 이름·번호 원본처럼 불렀다');
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('연결 여부를 모르는 계정(unknown scope) — 최악(회원) 고지 + 그 사실을 밝힌다', () {
    testWidgets('배너와 회원 고지가 함께 보인다', (tester) async {
      await pump(tester, scope: AccountDeletionScope.unknown);

      expect(find.text('계정 삭제'), findsOneWidget);
      expect(find.textContaining('연결 상태를 확인하지 못했어요'), findsOneWidget);
      // /v1/me 실패 = 가입 요청 유무도 모른다 — "있다면"으로 말한다(P63).
      expect(find.textContaining('보낸 가입 요청이 있다면 그것만 삭제돼요'), findsOneWidget);
      expect(find.textContaining('보낸 가입 요청과 로그인 계정만 삭제돼요'), findsNothing);
      // 회원 쪽 고지가 그대로 — 이미 연결된 회원일 수 있으므로 과소 고지를 하지 않는다.
      expect(find.text('체형사진(원본 파일까지 삭제)'), findsOneWidget);
      expect(find.text('법에 따라 보관되는 정보'), findsOneWidget);
      expect(find.textContaining('남은 회차를 확인하지 못했어요'), findsOneWidget);
    });

    // P63 검증 반영 — matched(번호로 회원을 찾음, 이름 확인 전)도 unknown이다. 모르는 이유가
    // 다르니 배너 첫 줄만 다르고 본문(회원 고지)은 같다.
    testWidgets('번호 매칭 사유(phoneMatched)면 배너 첫 줄이 "등록된 회원이 있어요"다', (tester) async {
      await pump(
        tester,
        scope: AccountDeletionScope.unknown,
        unknownReason: AccountDeletionUnknownReason.phoneMatched,
      );

      expect(find.textContaining('이 번호로 등록된 회원이 있어요'), findsOneWidget);
      expect(find.textContaining('이미 이 계정에 연결돼 있었다면 아래 내용대로 모두 삭제돼요'), findsOneWidget);
      expect(find.textContaining('연결 상태를 확인하지 못했어요'), findsNothing);
      expect(find.textContaining('보낸 가입 요청이 있다면 그것만 삭제돼요'), findsOneWidget); // 헤지는 같다
      expect(find.text('체형사진(원본 파일까지 삭제)'), findsOneWidget);
      expect(find.text('법에 따라 보관되는 정보'), findsOneWidget);
    });

    // 완료 안내는 scope가 아니라 **서버 응답**으로 고른다(P63) — 앱은 어느 경로가 돌지 몰랐지만
    // 서버는 답에 `member_id`로 알려준다(회원 경로면 id, 미연결 경로면 빈 값, 계약 v2.27).
    Future<void> deleteThrough(WidgetTester tester) async {
      await scrollToConfirm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '삭제하기'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog('삭제하기'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-stub')), findsOneWidget);
    }

    testWidgets('서버가 미연결 경로를 돌았으면(member_id 빈 값) 완료 안내는 "계정을 삭제했어요"', (tester) async {
      repo.summary = const AccountDeletionSummary(memberId: '', joinRequests: 0);
      await pumpWithRouter(tester, scope: AccountDeletionScope.unknown);

      await deleteThrough(tester);
      expect(find.text('계정을 삭제했어요.'), findsOneWidget);
      expect(find.textContaining('탈퇴가 완료됐어요'), findsNothing, reason: '회원이 아니었던 사람에게 탈퇴라 말했다');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('서버가 회원 경로를 돌았으면(member_id 있음) 회원 완료 문구다', (tester) async {
      repo.summary = const AccountDeletionSummary(memberId: 'm1', bodyPhotos: 4);
      await pumpWithRouter(tester, scope: AccountDeletionScope.unknown);

      await deleteThrough(tester);
      expect(find.textContaining('탈퇴가 완료됐어요'), findsOneWidget);
      expect(find.textContaining('계정을 삭제했어요'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('제출 중에는 화면을 벗어날 수 없다 (P56 M2)', () {
    // DELETE가 날아가는 동안 시스템 백으로 화면이 pop되면 서버는 계정을 지웠는데
    // `!mounted`가 로그아웃·`/login` 이동·완료 안내를 셋 다 삼킨다 — 앱은 지워진 계정의
    // 세션을 든 채 남고 이후 모든 새로고침이 403이다. 뮤테이션: PopScope를 빼면 죽는다.
    testWidgets('시스템 백을 눌러도 화면이 남고, 응답이 오면 끝까지 마무리된다', (tester) async {
      repo.deleteGate = Completer<Result<AccountDeletionSummary>>();
      final container = await pumpWithRouter(tester);

      await scrollToConfirm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '탈퇴하기'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog('탈퇴하기'));
      await tester.pump();
      expect(find.text('처리 중…'), findsOneWidget);

      await pressSystemBack(tester);
      await tester.pumpAndSettle();
      expect(find.text('처리 중…'), findsOneWidget, reason: '제출 중 백으로 화면이 사라졌다');
      expect(find.byType(AccountDeletionScreen), findsOneWidget);

      repo.deleteGate!.complete(const Ok(AccountDeletionSummary()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-stub')), findsOneWidget, reason: '성공했는데 로그인으로 못 나갔다');
      expect(container.read(sessionProvider), isNull, reason: '지워진 계정의 세션이 남았다');
      expect(find.textContaining('탈퇴가 완료됐어요'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5)); // 스낵바 타이머
    });

    testWidgets('제출 전에는 종전대로 백으로 나갈 수 있다 — 과잉 잠금이 아니다', (tester) async {
      await pumpWithRouter(tester);
      expect(find.byType(AccountDeletionScreen), findsOneWidget);

      await pressSystemBack(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AccountDeletionScreen), findsNothing);
      expect(repo.deleteCalls, 0);
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

    test('미연결 완료 안내 — "보낸 가입 요청"은 서버가 실제로 지웠을 때만 (P63)', () {
      for (final trace in JoinRequestTrace.values) {
        expect(
          const AccountDeletionSummary(joinRequests: 0).unlinkedCompletionMessage(trace),
          '계정을 삭제했어요.',
          reason: '$trace — 0건인데 지웠다고 했다',
        );
      }
      expect(
        const AccountDeletionSummary(joinRequests: 1).unlinkedCompletionMessage(JoinRequestTrace.pending),
        '계정과 보낸 가입 요청을 삭제했어요.',
      );
      // unknown으로 고지했는데 서버가 지웠으면 — 건수를 아니 단정한다.
      expect(
        const AccountDeletionSummary(joinRequests: 1).unlinkedCompletionMessage(JoinRequestTrace.unknown),
        '계정과 보낸 가입 요청을 삭제했어요.',
      );
      // 거절 껍데기 + 재요청 pending이 함께 지워진 경우 — 재요청 성공이 trace를 pending으로
      // 세우므로 "보낸 가입 요청"이 참이다.
      expect(
        const AccountDeletionSummary(joinRequests: 2).unlinkedCompletionMessage(JoinRequestTrace.pending),
        contains('보낸 가입 요청'),
      );
    });

    // P63 검증 반영 — settled(거절·승인 뒤)의 문서는 이름·번호가 비워진 껍데기다. 사전 고지가
    // '가입 요청 기록'이라 부른 것을 완료 안내가 '보낸 가입 요청'으로 바꿔 부르면 두 말이다.
    test('settled면 "가입 요청 기록"을 지웠다고 말한다 — 사전 고지와 같은 이름', () {
      expect(
        const AccountDeletionSummary(joinRequests: 1).unlinkedCompletionMessage(JoinRequestTrace.settled),
        '계정과 가입 요청 기록을 삭제했어요.',
      );
      expect(
        const AccountDeletionSummary(joinRequests: 1).unlinkedCompletionMessage(JoinRequestTrace.settled),
        isNot(contains('보낸 가입 요청')),
      );
    });

    test('member_id 빈 값 = 미연결 경로, 값 있음 = 회원 경로 (계약 v2.27)', () {
      expect(const AccountDeletionSummary(memberId: '').ranUnlinkedPath, isTrue);
      expect(const AccountDeletionSummary().ranUnlinkedPath, isTrue); // 키 없음(구서버)도 빈 값
      expect(const AccountDeletionSummary(memberId: 'm1').ranUnlinkedPath, isFalse);
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

    test('purged.join_requests와 member_id를 읽는다 — 키 없음은 0 / 빈 문자열 (P63)', () {
      final unlinked = AccountDeletionSummary.fromJson(const {
        'deleted': true,
        'member_id': '',
        'purged': {'body_photos': 0, 'join_requests': 1},
      });
      expect(unlinked.joinRequests, 1);
      expect(unlinked.memberId, '');
      expect(unlinked.ranUnlinkedPath, isTrue);

      final member = AccountDeletionSummary.fromJson(const {'member_id': 'm1', 'purged': {'body_photos': 4}});
      expect(member.joinRequests, 0, reason: '키 없음(구서버)은 0 — 던지지 않는다');
      expect(member.memberId, 'm1');
      expect(member.ranUnlinkedPath, isFalse);

      expect(AccountDeletionSummary.fromJson(const {}).joinRequests, 0);
      expect(AccountDeletionSummary.fromJson(const {}).memberId, '');
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

/// 운영과 같은 진입 방식 — 확인 화면을 **push**해서 띄운다(my_screen·center_confirm_screen).
class _PushHost extends StatelessWidget {
  const _PushHost({required this.scope, required this.trace});
  final AccountDeletionScope scope;
  final JoinRequestTrace trace;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).push<void>(
            MaterialPageRoute(
              builder: (_) => AccountDeletionScreen(scope: scope, joinRequestTrace: trace),
            ),
          ),
          child: const Text('열기'),
        ),
      ),
    );
  }
}

class _FakeMyRepository implements MyRepository {
  int deleteCalls = 0;
  Failure? failure;
  List<PassDetail> passes = const [];

  /// 심어 두면 DELETE가 이 completer가 끝날 때까지 **매달린다**(제출 중 상태 재현).
  Completer<Result<AccountDeletionSummary>>? deleteGate;

  /// 서버 응답 — 기본은 회원 경로(member_id 있음). 미연결 경로를 재현하는 테스트는
  /// `member_id` 빈 값 + `purged.join_requests` 건수를 심는다(계약 v2.27).
  AccountDeletionSummary summary =
      const AccountDeletionSummary(bodyPhotos: 4, inbody: 2, remainingSessions: 0, memberId: 'm1');

  @override
  Future<Result<AccountDeletionSummary>> deleteAccount() async {
    deleteCalls++;
    if (deleteGate case final gate?) return gate.future;
    if (failure case final f?) return Err(f);
    return Ok(summary);
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

class _FakeJoinRequestStore implements JoinRequestStore {
  JoinRequestRecord? record;

  @override
  Future<JoinRequestRecord?> read() async => record;

  @override
  Future<void> save(JoinRequestRecord value) async => record = value;

  @override
  Future<void> clear() async => record = null;
}

/// 이 파일은 인증을 다루지 않는다 — 로그아웃만 조용히 성공하고 나머지는 불리면 결함이다.
class _FakeAuthRepository implements AuthRepository {
  @override
  Future<void> signOut() async {}

  @override
  Future<Result<PhoneVerificationSession>> requestVerificationCode(
    String phone, {
    int? resendToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> verifyCode({
    required String phone,
    required String verificationId,
    required String code,
  }) =>
      throw UnimplementedError();

  @override
  Future<Result<JoinMatch>> matchJoin(String phone) => throw UnimplementedError();

  @override
  Future<Result<void>> confirmJoin({
    required String memberId,
    required bool confirm,
    required String phone,
  }) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> requestJoin({
    required String name,
    required String phone,
    String centerId = '',
  }) =>
      throw UnimplementedError();

  /// v2.33 — 센터 목록. 이 스위트는 선택 UI를 다루지 않으므로 빈 목록(= 고를 것 없음)이다.
  @override
  Future<Result<List<CenterDirectory>>> fetchJoinCenters() async =>
      const Ok(<CenterDirectory>[]);

  @override
  Future<Result<AppSession>> loadSession() => throw UnimplementedError();

  @override
  Stream<String?> signedInPhoneChanges() => const Stream<String?>.empty();
}
