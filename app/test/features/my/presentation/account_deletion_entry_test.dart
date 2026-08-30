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
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/domain/my_repository.dart';
import 'package:rise_member/features/my/presentation/account_deletion_screen.dart';
import 'package:rise_member/features/my/presentation/my_screen.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';

// 회원탈퇴 **진입점**이 마이 탭에 실제로 있는가 (App Store Review Guideline 5.1.1(v)).
//
// 이 파일이 따로 있는 이유: 확인 화면이 아무리 잘 만들어져 있어도 **앱 안에서 닿을 수
// 없으면** 심사에서 리젝된다. 그리고 진입점은 카드 레이아웃을 손볼 때 가장 조용히
// 사라지는 종류의 위젯이다(행 하나 삭제로 끝난다). 심사 통과 여부가 걸린 한 줄이라
// 화면 로직과 분리해 고정한다.
void main() {
  Future<void> pumpMy(WidgetTester tester) async {
    final container = ProviderContainer.test(
      overrides: [
        myRepositoryProvider.overrideWithValue(_StubMyRepository()),
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
    await tester.pumpAndSettle();
  }

  Future<void> scrollToWithdrawal(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('회원탈퇴'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('마이 탭에 회원탈퇴 진입점이 있다', (tester) async {
    await pumpMy(tester);
    await scrollToWithdrawal(tester);

    expect(find.text('회원탈퇴'), findsOneWidget);
  });

  testWidgets('탭하면 확인 화면이 열린다 — 곧바로 실행되지 않는다', (tester) async {
    await pumpMy(tester);
    await scrollToWithdrawal(tester);

    await tester.tap(find.text('회원탈퇴'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountDeletionScreen), findsOneWidget);
    // 확인 화면일 뿐 아직 아무 일도 일어나지 않았다 — 진입 자체가 파괴적이면 안 된다.
    expect(find.text('삭제되는 정보'), findsOneWidget);
  });

  testWidgets('로그아웃과 같은 무게로 보이지 않는다(danger 색)', (tester) async {
    // 두 행이 바로 붙어 있어 오탭이 쉽다. 로그아웃은 되돌릴 수 있고 탈퇴는 아니다.
    await pumpMy(tester);
    await scrollToWithdrawal(tester);

    final withdrawal = tester.widget<Text>(find.text('회원탈퇴'));
    final logout = tester.widget<Text>(find.text('로그아웃'));
    expect(withdrawal.style?.color, AppColors.danger);
    expect(logout.style?.color, isNot(AppColors.danger));
  });
}

class _StubMyRepository implements MyRepository {
  @override
  Future<Result<MySummary>> load(String memberId) async => const Ok(
        MySummary(
          passes: [],
          ledgerByPass: {},
          contracts: [],
          consent: ConsentState(general: true, sensitive: true),
        ),
      );

  // 이 파일의 관심사는 진입점 하나다 — 나머지가 불리면 그 자체가 결함이다.
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
