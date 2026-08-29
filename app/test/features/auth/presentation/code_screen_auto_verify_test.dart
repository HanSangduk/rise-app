import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/router/app_router.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';
import 'package:rise_member/features/auth/domain/auth_repository.dart';
import 'package:rise_member/features/auth/domain/join_request_store.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';

// 안드로이드 SMS 자동 회수가 codeSent **이후** 도착하는 경우의 화면 회귀.
//
// P08은 codeSent **이전**(즉시 인증)만 처리했다. 정상 SMS 흐름에서 자동 회수가
// 나중에 끝나면 알릴 통로가 없어, 사용자는 이미 로그인이 됐는데도 코드 화면에서
// 오지 않을 입력을 기다리며 재전송 카운트다운을 계속 봤다("확인"을 누르면 되는
// 줄 아는 사람만 빠져나갔다).
void main() {
  late _FakeAuthRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeAuthRepository();
    container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        joinRequestStoreProvider.overrideWithValue(_FakeJoinRequestStore()),
        // 센터 확인 화면이 담당 코치 아바타를 위해 watch한다 — 네트워크로 새지 않게.
        staffMapProvider.overrideWithValue(const AsyncValue<Map<String, StaffDto>>.data({})),
      ],
    );
  });

  /// 번호 입력 → 인증번호 발송(codeSent) → 코드 화면. 실제 진입 경로 그대로.
  Future<void> pumpCodeScreen(WidgetTester tester) async {
    final notifier = container.read(authViewModelProvider.notifier);
    notifier.setPhone('010-1234-5678');
    await notifier.sendCode();

    final router = createRouter();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.go('/login/code');
    await tester.pumpAndSettle();
    expect(find.text('인증번호 입력'), findsOneWidget);
  }

  testWidgets('자동 회수로 로그인이 끝나면 코드 화면이 스스로 다음으로 넘어간다', (tester) async {
    await pumpCodeScreen(tester);
    expect(repo.matchJoinCount, 0);

    repo.signedIn.add('+821012345678');
    await tester.pumpAndSettle();

    expect(find.text('인증번호 입력'), findsNothing);
    expect(find.text('센터 선택'), findsOneWidget); // CenterConfirmScreen
    expect(repo.matchJoinCount, 1);
  });

  testWidgets('다른 번호로 남아 있던 세션은 화면을 밀어내지 못한다', (tester) async {
    await pumpCodeScreen(tester);

    repo.signedIn.add('+821099998888');
    await tester.pumpAndSettle();

    expect(find.text('인증번호 입력'), findsOneWidget);
    expect(repo.matchJoinCount, 0);
  });

  testWidgets('로그아웃 이벤트(null)는 아무것도 하지 않는다', (tester) async {
    await pumpCodeScreen(tester);

    repo.signedIn.add(null);
    await tester.pumpAndSettle();

    expect(find.text('인증번호 입력'), findsOneWidget);
    expect(repo.matchJoinCount, 0);
  });

  testWidgets('같은 로그인이 여러 번 흘러도 매칭은 한 번만 나간다', (tester) async {
    await pumpCodeScreen(tester);

    repo.signedIn.add('+821012345678');
    await tester.pump(); // 진행 중(매칭 대기)
    repo.signedIn.add('+821012345678');
    await tester.pumpAndSettle();

    expect(repo.matchJoinCount, 1);
    expect(find.text('센터 선택'), findsOneWidget);
  });

  testWidgets('자동 진행에 실패하면 화면에 남고 사유를 보여준다 — "확인"은 계속 살아 있다',
      (tester) async {
    await pumpCodeScreen(tester);
    repo.matchResult = const Err(NetworkFailure());

    repo.signedIn.add('+821012345678');
    await tester.pumpAndSettle();

    expect(find.text('인증번호 입력'), findsOneWidget);
    expect(find.text(const NetworkFailure().message), findsOneWidget);
    expect(find.text('확인'), findsOneWidget);
  });

  testWidgets('화면을 떠나면 구독이 끊긴다 — 뒤늦은 이벤트가 죽은 화면을 건드리지 않는다',
      (tester) async {
    await pumpCodeScreen(tester);
    // 구독이 살아 있는 상태(코드 화면 mount 중).
    expect(repo.signedIn.hasListener, isTrue);

    // 뒤로가기는 Material Icon이 아니라 RiseIcon(SVG)이라 byIcon으로 못 찾는다
    // — 위젯 자체를 술어로 집는다(rise_icons.arrowLeft).
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is RiseIcon && w.svg == RiseIcons.arrowLeft,
        description: 'RiseIcon(arrowLeft)',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('인증번호 받기'), findsOneWidget); // PhoneScreen

    // autoDispose provider가 구독자와 함께 정리돼야 한다(수동 StreamSubscription을
    // 들지 않는 이유 — dispose 누락이 곧 누수다).
    expect(repo.signedIn.hasListener, isFalse);

    repo.signedIn.add('+821012345678');
    await tester.pumpAndSettle();
    expect(find.text('인증번호 받기'), findsOneWidget);
    expect(repo.matchJoinCount, 0);
  });
}

class _FakeAuthRepository implements AuthRepository {
  int matchJoinCount = 0;
  Result<JoinMatch>? matchResult;

  /// 실구현은 FirebaseAuth.authStateChanges().skip(1) — 테스트는 그 전이만 흘린다.
  final signedIn = StreamController<String?>();

  @override
  Stream<String?> signedInPhoneChanges() => signedIn.stream;

  @override
  Future<Result<PhoneVerificationSession>> requestVerificationCode(
    String phone, {
    int? resendToken,
  }) async =>
      const Ok(PhoneVerificationSession(verificationId: 'vid'));

  @override
  Future<Result<void>> verifyCode({
    required String phone,
    required String verificationId,
    required String code,
  }) async =>
      const Ok(null);

  @override
  Future<Result<JoinMatch>> matchJoin(String phone) async {
    matchJoinCount++;
    return matchResult ??
        const Ok(JoinMatch(
          member: MatchedMember(id: 'm1', name: '김라이즈', status: 'active'),
          needsConfirm: true,
        ));
  }

  @override
  Future<Result<void>> confirmJoin({
    required String memberId,
    required bool confirm,
    required String phone,
  }) async =>
      const Ok(null);

  @override
  Future<Result<void>> requestJoin({required String name, required String phone}) async =>
      const Ok(null);

  @override
  Future<Result<AppSession>> loadSession() async => const Err(MemberNotLinkedFailure());

  @override
  Future<void> signOut() async {}
}

class _FakeJoinRequestStore implements JoinRequestStore {
  @override
  Future<JoinRequestRecord?> read() async => null;

  @override
  Future<void> save(JoinRequestRecord value) async {}

  @override
  Future<void> clear() async {}
}
