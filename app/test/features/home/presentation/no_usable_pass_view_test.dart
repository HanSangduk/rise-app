import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/empty_passes_view.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/presentation/home_screen.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';
import 'package:rise_member/features/home/presentation/widgets/remaining_ring.dart';

// 가진 회원권이 전부 만료·환불인 회원의 홈.
//
// 데이터 계층이 `hasUsablePass=false`로 사실을 올려도 화면이 종전 본문을 그대로
// 그리면 아무것도 달라지지 않는다 — 잔여 링 + 담당 코치 + 다음 예약이 모두 살아 있는
// 회원권의 모습 그 자체다.
//
// (P30에서 "잔여 8회 — 연장 상담 가능" 배지는 사라졌다: 조건 없이 항상 켜져 있었고,
//  회원이 앱에서 갈 경로가 없는 약속이었다. 그래서 이 테스트는 잔여 **링**으로
//  "회원권이 살아 있는 화면"을 식별한다.)
// 스위처 칩의 "(환불)" 한 조각으로는 그 인상을 뒤집지 못한다(앞선 팀이 칩 표기를
// 고쳤는데도 이 결함이 남아 있던 이유).
void main() {
  Future<void> pumpHome(WidgetTester tester, {required bool hasUsablePass}) async {
    final container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(_FakeHomeRepository(hasUsablePass)),
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
        child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('이용 가능한 회원권이 없을 때', () {
    testWidgets('전용 빈 상태로 떨어지고 이유를 말한다', (tester) async {
      await pumpHome(tester, hasUsablePass: false);

      expect(find.byType(EmptyPassesView), findsOneWidget);
      expect(find.text('이용 가능한 회원권이 없어요'), findsOneWidget);
      expect(find.textContaining('만료·환불된 회원권만'), findsOneWidget);
      // 회원권이 0개일 때의 문구를 재활용하면 "나 회원권 샀는데?"와 어긋난다.
      expect(find.text('아직 회원권이 없어요'), findsNothing);
    });

    testWidgets('잔여 링을 그리지 않는다', (tester) async {
      await pumpHome(tester, hasUsablePass: false);

      expect(find.byType(RemainingRing), findsNothing);
      // 경로 없는 약속은 이제 어떤 상태에서도 뜨지 않는다(P30).
      expect(find.textContaining('연장 상담'), findsNothing);
    });

    testWidgets('헤더의 "상품 · 잔여" 배지와 담당 코치 앵커도 함께 사라진다', (tester) async {
      // 헤더는 async.when 밖이라, 본문만 바꾸면 빈 상태 위에 "PT 20회 · 잔여 8"이
      // 그대로 떠 있는다 — 화면이 두 가지 말을 동시에 하는 셈이다.
      await pumpHome(tester, hasUsablePass: false);

      expect(find.textContaining('잔여 8'), findsNothing);
      expect(find.textContaining('담당 정혜린 코치'), findsNothing);
      expect(find.text('람 님'), findsOneWidget);
    });
  });

  testWidgets('쓸 수 있는 회원권이 있으면 종전 홈 그대로 — 가드가 과잉 차단하지 않는다', (tester) async {
    await pumpHome(tester, hasUsablePass: true);

    expect(find.byType(EmptyPassesView), findsNothing);
    expect(find.byType(RemainingRing), findsOneWidget);
    expect(find.text('람 님 · 담당 정혜린 코치'), findsOneWidget);
  });
}

class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository(this.hasUsablePass);
  final bool hasUsablePass;

  @override
  Future<Result<HomeSummary>> loadHome({
    required String memberId,
    String? preferredPassId,
  }) async {
    return Ok(HomeSummary(
      passes: [
        PassOption(
          id: 'p1',
          product: 'PT 20회',
          trainerId: 't1',
          trainerName: '정혜린',
          status: hasUsablePass ? 'active' : 'refunded',
          remaining: 8,
          totalSessions: 20,
          validFrom: DateTime(2026, 1, 1),
          validUntil: DateTime(2030, 12, 31),
        ),
      ],
      selectedPassId: 'p1',
      hasUsablePass: hasUsablePass,
      homeworkItems: const [],
      // 실제 repository가 하는 것과 같게 **로드 시점의 센터(KST) 오늘**을 싣는다
      // — 쓰기 가드(HomeSummary.homeworkDate)가 이 값을 기준으로 판정한다.
      homeworkDate: DateFmt.todayKst(),
    ));
  }

  @override
  Future<Result<void>> submitHomeworkChecks({
    required String memberId,
    required String hwId,
    required DateTime date,
    required List<bool> done,
  }) async =>
      const Ok(null);

  @override
  Future<Result<void>> selfCheckIn({String? scannedToken}) async => const Ok(null);
}
