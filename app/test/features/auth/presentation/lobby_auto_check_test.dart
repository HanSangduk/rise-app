import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';
import 'package:rise_member/features/auth/domain/auth_repository.dart';
import 'package:rise_member/features/auth/domain/join_request_store.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
import 'package:rise_member/features/auth/presentation/widgets/lobby_auto_check.dart';

// P69 H1 — 대기실 자동 확인. "센터가 승인하면 연결돼요"를 참으로 만드는 유일한 장치다(푸시 없음).
//
// 규칙: 마운트 시 서버 미확답이면 즉시 1회 · 포그라운드 30초 주기 · 실패 30→60→120초 백오프(성공
// 시 리셋) · paused면 정지, resumed 즉시 1회 · busy면 틱 스킵(실패 아님) · connected → onConnected ·
// dispose 후 타이머 0. 뮤테이션: 타이머 예약을 지우면 "30초 뒤 2회"가 죽고, `_failures` 백오프를
// 지우면 백오프 테스트가 죽고, dispose의 cancel을 지우면 마지막 테스트가 "Timer still pending"으로 죽는다.
void main() {
  late _FakeAuthRepository repo;
  late ProviderContainer container;
  late int connected;

  setUp(() {
    repo = _FakeAuthRepository();
    connected = 0;
    container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        joinRequestStoreProvider.overrideWithValue(_FakeJoinRequestStore()),
        lobbyAutoCheckIntervalProvider.overrideWithValue(const Duration(seconds: 30)),
      ],
    );
    // 다른 테스트가 paused로 남겨 두면 다음 테스트가 백그라운드에서 시작한다.
    addTearDown(() => TestWidgetsFlutterBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  });

  AuthViewModel notifier() => container.read(authViewModelProvider.notifier);

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: LobbyAutoCheck(onConnected: () => connected++)),
        ),
      ),
    );
    // 프레임 → post-frame 틱 → await 뒤 예약까지.
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  testWidgets('마운트 시 서버 미확답(unknown)이면 즉시 1회', (tester) async {
    await mount(tester);
    expect(repo.loadSessionCount, 1);
    await unmount(tester);
  });

  testWidgets('서버가 pending을 확답한 직후면 즉시 확인은 없고 30초 뒤 1회', (tester) async {
    notifier().applyServerJoinStatus('pending');
    await mount(tester);
    expect(repo.loadSessionCount, 0, reason: '방금 물어본 것과 같다');

    await tester.pump(const Duration(seconds: 30));
    expect(repo.loadSessionCount, 1);
    await unmount(tester);
  });

  testWidgets('30초마다 반복한다 (성공 시 간격 유지)', (tester) async {
    await mount(tester);
    expect(repo.loadSessionCount, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(repo.loadSessionCount, 2);
    await tester.pump(const Duration(seconds: 30));
    expect(repo.loadSessionCount, 3);
    await unmount(tester);
  });

  testWidgets('paused면 정지하고, resumed 복귀 즉시 1회', (tester) async {
    await mount(tester);
    expect(repo.loadSessionCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 90));
    expect(repo.loadSessionCount, 1, reason: '백그라운드에선 타이머를 놓는다');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(repo.loadSessionCount, 2, reason: '복귀 즉시 — 백그라운드에서 승인됐을 수 있다');

    await tester.pump(const Duration(seconds: 30));
    expect(repo.loadSessionCount, 3, reason: '주기도 다시 돈다');
    await unmount(tester);
  });

  testWidgets('실패하면 30 → 60 → 120초로 물러나고(상한 120), 성공하면 30초로 돌아온다', (tester) async {
    repo.sessionResult = const Err(NetworkFailure());
    await mount(tester); // 실패 1
    expect(repo.loadSessionCount, 1);

    await tester.pump(const Duration(seconds: 30));
    expect(repo.loadSessionCount, 1, reason: '실패 1회 뒤 간격은 60초');
    await tester.pump(const Duration(seconds: 30)); // t=60 → 실패 2
    expect(repo.loadSessionCount, 2);

    await tester.pump(const Duration(seconds: 60));
    expect(repo.loadSessionCount, 2, reason: '실패 2회 뒤 간격은 120초');
    await tester.pump(const Duration(seconds: 60)); // t=180 → 실패 3
    expect(repo.loadSessionCount, 3);

    await tester.pump(const Duration(seconds: 120)); // 상한 120 유지 → 실패 4
    expect(repo.loadSessionCount, 4);

    repo.sessionResult = null; // 이제 서버가 답한다(notYet)
    await tester.pump(const Duration(seconds: 120)); // 성공
    expect(repo.loadSessionCount, 5);
    await tester.pump(const Duration(seconds: 30));
    expect(repo.loadSessionCount, 6, reason: '성공 뒤 30초로 리셋');
    await unmount(tester);
  });

  testWidgets('busy면 그 틱을 건너뛴다 — 실패로 세지 않는다(백오프 없음)', (tester) async {
    await mount(tester);
    expect(repo.loadSessionCount, 1);

    // 사용자가 수동 확인을 눌렀고 응답이 매달려 있다 → busy.
    final gate = Completer<Result<AppSession>>();
    repo.pendingLoadSession = gate.future;
    final manual = notifier().checkConnection();
    await tester.pump();
    expect(repo.loadSessionCount, 2);
    expect(container.read(authViewModelProvider).busy, isTrue);

    await tester.pump(const Duration(seconds: 30)); // 자동 틱 — busy라 건너뜀
    expect(repo.loadSessionCount, 2);

    repo.pendingLoadSession = null;
    gate.complete(const Err(MemberNotLinkedFailure()));
    await manual;
    await tester.pump();

    await tester.pump(const Duration(seconds: 30)); // 백오프 없이 30초 뒤 정상 틱
    expect(repo.loadSessionCount, 3);
    await unmount(tester);
  });

  testWidgets('이 화면 위에 시트·다이얼로그가 떠 있으면 그 틱을 건너뛴다 — 시트 위에서 홈으로 튀지 않는다',
      (tester) async {
    await mount(tester);
    expect(repo.loadSessionCount, 1);

    // 가입 요청 시트처럼 대기실 위에 라우트가 하나 더 올라간 상태.
    final host = tester.element(find.byType(LobbyAutoCheck));
    unawaited(showModalBottomSheet<void>(
      context: host,
      builder: (_) => const SizedBox(height: 120, child: Text('가입 요청 시트')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('가입 요청 시트'), findsOneWidget);

    // 그 사이 서버가 승인했더라도 시트 위에서는 묻지 않는다 → connected로 튀지 않는다.
    repo.session = const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1');
    await tester.pump(const Duration(seconds: 30));
    expect(repo.loadSessionCount, 1, reason: '시트가 떠 있는 동안은 건너뛴다');
    expect(connected, 0);

    // 시트가 닫히면 다음 틱(백오프 없이 30초)이 확인해 연결한다.
    Navigator.of(host, rootNavigator: true).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 30));
    expect(repo.loadSessionCount, 2);
    expect(connected, 1);
    await unmount(tester);
  });

  testWidgets('connected면 onConnected 1회 — 이후 타이머 없음', (tester) async {
    repo.session = const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1');
    await mount(tester);
    expect(connected, 1);
    expect(repo.loadSessionCount, 1);

    await tester.pump(const Duration(minutes: 5));
    expect(repo.loadSessionCount, 1, reason: '연결 뒤엔 더 묻지 않는다');
    expect(connected, 1);
    await unmount(tester);
  });

  testWidgets('자동 틱은 실패 시각·성공 시각을 뷰모델에 남긴다', (tester) async {
    await mount(tester);
    expect(container.read(authViewModelProvider).lastCheckedAt, isNotNull);
    expect(container.read(authViewModelProvider).lastCheckFailedAt, isNull);

    repo.sessionResult = const Err(NetworkFailure());
    await tester.pump(const Duration(seconds: 30));
    expect(container.read(authViewModelProvider).lastCheckFailedAt, isNotNull);
    await unmount(tester);
  });

  testWidgets('dispose 후 타이머가 남지 않는다', (tester) async {
    await mount(tester);
    await unmount(tester);
    await tester.pump(const Duration(minutes: 10));
    expect(repo.loadSessionCount, 1, reason: 'dispose 뒤 틱이 돌았다');
    // 타이머가 남았다면 testWidgets가 "A Timer is still pending"으로 이 테스트를 죽인다.
  });

  testWidgets('간격이 null이면 아무것도 하지 않는다 — 위젯 테스트 하네스의 전제', (tester) async {
    container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        joinRequestStoreProvider.overrideWithValue(_FakeJoinRequestStore()),
        lobbyAutoCheckIntervalProvider.overrideWithValue(null),
      ],
    );
    await mount(tester);
    await tester.pump(const Duration(minutes: 5));
    expect(repo.loadSessionCount, 0);
    await unmount(tester);
  });
}

class _FakeAuthRepository implements AuthRepository {
  int loadSessionCount = 0;
  AppSession? session;
  Result<AppSession>? sessionResult;
  Future<Result<AppSession>>? pendingLoadSession;

  @override
  Future<Result<AppSession>> loadSession() {
    loadSessionCount++;
    final gate = pendingLoadSession;
    if (gate != null) return gate;
    final override = sessionResult;
    if (override != null) return Future.value(override);
    final s = session;
    return Future.value(s == null ? const Err(MemberNotLinkedFailure()) : Ok(s));
  }

  @override
  Future<Result<PhoneVerificationSession>> requestVerificationCode(String phone, {int? resendToken}) async =>
      const Ok(PhoneVerificationSession(verificationId: 'vid'));

  @override
  Future<Result<void>> verifyCode({required String phone, required String verificationId, required String code}) async =>
      const Ok(null);

  @override
  Future<Result<JoinMatch>> matchJoin(String phone) async => const Ok(JoinMatch(needsConfirm: false));

  @override
  Future<Result<void>> confirmJoin({required String memberId, required bool confirm, required String phone}) async =>
      const Ok(null);

  @override
  Future<Result<void>> requestJoin({required String name, required String phone, String centerId = ''}) async =>
      const Ok(null);

  @override
  Future<Result<List<CenterDirectory>>> fetchJoinCenters() async => const Ok(<CenterDirectory>[]);

  @override
  Future<void> signOut() async {}

  @override
  Stream<String?> signedInPhoneChanges() => const Stream<String?>.empty();
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
