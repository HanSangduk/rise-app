// 마이 탭의 **데이터가 필요 없는 행**은 로드 상태와 무관하게 보인다(P56 B4).
//
// 종전엔 로그아웃·회원탈퇴·약관 카드가 `async.when`의 `data` 브랜치 **안**에 있었다.
// 요약 로드가 한 번 실패하면 넷이 동시에 사라졌다 — 서버가 지속 403을 주는 계정(권한
// 상실·탈퇴 잔여 인덱스)은 401이 아니라 세션도 안 비워지고(api_result_guard는 401만
// 로그아웃 신호로 본다), 회원은 [다시 시도] 하나뿐인 화면에 갇혀 **재설치가 유일한
// 탈출구**였다. 로그아웃도 탈퇴도 회원 데이터를 한 글자도 안 쓰는 행이다.
//
// 뮤테이션: 세 줄을 `data` 브랜치 안으로 되돌리면 아래 두 테스트가 죽는다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
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
import 'package:rise_member/features/my/presentation/my_screen.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';

void main() {
  late _FakeMyRepository repo;

  setUp(() => repo = _FakeMyRepository());

  Future<void> pumpMy(WidgetTester tester) async {
    final container = ProviderContainer.test(
      // Riverpod 3은 실패한 provider를 자동 재시도한다(지수 백오프 타이머) — 실패 경로
      // 테스트에서 그 타이머가 트리 dispose 후까지 살아남지 않게 끈다.
      retry: (_, __) => null,
      overrides: [
        myRepositoryProvider.overrideWithValue(repo),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        staffMapProvider.overrideWithValue(const AsyncValue<Map<String, StaffDto>>.data({})),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).set(
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람'),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const MyScreen()),
      ),
    );
    await tester.pump();
  }

  Future<void> scrollTo(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
  }

  testWidgets('요약 로드가 실패해도 로그아웃·회원탈퇴·약관은 그대로 있다', (tester) async {
    repo.loadFailure = const RejectedFailure('요청을 처리할 수 없어요');
    await pumpMy(tester);
    await tester.pumpAndSettle();

    // 실패는 실패대로 보인다(재시도 포함) — 숨기는 게 아니라 **함께** 보이는 것이다.
    expect(find.text('문제가 생겼어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    for (final row in ['이용약관', '개인정보처리방침 (센터)', '로그아웃', '회원탈퇴']) {
      await scrollTo(tester, row);
      expect(find.text(row), findsOneWidget, reason: '"$row" — 로드 실패에 딸려 사라졌다');
    }
  });

  testWidgets('로딩이 끝나지 않아도(타임아웃 20초 창) 같은 행들이 보인다', (tester) async {
    repo.loadGate = Completer<Result<MySummary>>(); // 영원히 안 끝나는 로드
    await pumpMy(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    for (final row in ['이용약관', '로그아웃', '회원탈퇴']) {
      await scrollTo(tester, row);
      expect(find.text(row), findsOneWidget, reason: '"$row" — 로딩 뒤에 숨었다');
    }
  });

  testWidgets('정상 로드에서는 종전대로 회원권 카드 뒤에 온다 — 순서 회귀 방지', (tester) async {
    // 둘 다 한 화면에 들어오게 세로를 넉넉히 — ListView는 보이는 만큼만 만든다.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpMy(tester);
    await tester.pumpAndSettle();

    final passCard = tester.getTopLeft(find.textContaining('내 회원권'));
    final withdrawal = tester.getTopLeft(find.text('회원탈퇴'));
    expect(withdrawal.dy, greaterThan(passCard.dy));
  });
}

class _FakeMyRepository implements MyRepository {
  Failure? loadFailure;
  Completer<Result<MySummary>>? loadGate;

  @override
  Future<Result<MySummary>> load(String memberId) async {
    if (loadGate case final gate?) return gate.future;
    if (loadFailure case final f?) return Err(f);
    return const Ok(
      MySummary(
        passes: [],
        ledgerByPass: {},
        contracts: [],
        consent: ConsentState(general: true, sensitive: true),
      ),
    );
  }

  // 이 파일의 관심사는 행의 존재다 — 나머지가 불리면 그 자체가 결함이다.
  @override
  Future<Result<AccountDeletionSummary>> deleteAccount() => throw UnimplementedError();

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
