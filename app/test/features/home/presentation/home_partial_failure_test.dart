// 부분 실패가 화면을 뺏지 않는다 · 빈 상태가 실패를 삼키지 않는다(P33).
//
// 둘 다 **화면이 멀쩡해 보여서** 늦게 잡힌 결함이다. 그래서 규칙을 테스트 안에서
// 재현하지 않고 **진짜 홈 화면을 띄워** 검사한다 — 규칙만 베끼면 화면 배선이
// 끊어져도 통과한다(실제로 그렇게 썼다가 뮤테이션이 살아남아 다시 썼다).

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
import 'package:rise_member/core/widgets/empty_passes_view.dart';
import 'package:rise_member/core/widgets/rise_error_view.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/presentation/home_screen.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';
import 'package:rise_member/features/home/presentation/widgets/remaining_ring.dart';

void main() {
  late _SwitchableRepo repo;
  late ProviderContainer container;

  Future<void> pumpHome(WidgetTester tester, {required bool hasUsablePass}) async {
    repo = _SwitchableRepo(hasUsablePass: hasUsablePass);
    container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(repo),
        centerPolicyProvider
            .overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        staffMapProvider
            .overrideWithValue(const AsyncValue<Map<String, StaffDto>>.data({})),
      ],
    );
    container.read(sessionProvider.notifier).set(const AppSession(
          uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1',
          memberName: '람',
        ));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('② 칩 전환 실패가 보고 있던 홈을 뺏지 않는다', () {
    testWidgets('실패해도 홈이 그대로 있고 스낵바로만 알린다', (tester) async {
      // 종전엔 실패를 `AsyncError`에 그대로 넣어서 **멀쩡하던 홈이 통째로 사라지고**
      // "다시 시도" 버튼만 남았다. 칩 탭은 부분 갱신이라 "안 바뀌었다"고 알리면 된다.
      await pumpHome(tester, hasUsablePass: true);
      expect(find.byType(RemainingRing), findsOneWidget);

      repo.failNext = const NetworkFailure('연결이 불안정해요');
      await container.read(homeViewModelProvider.notifier).selectPass('p1');
      await tester.pumpAndSettle();

      expect(find.byType(RiseErrorView), findsNothing,
          reason: '칩 한 번 실패했다고 홈을 통째로 치웠다');
      expect(find.byType(RemainingRing), findsOneWidget,
          reason: '보고 있던 홈이 사라졌다');
      expect(find.text('연결이 불안정해요'), findsOneWidget,
          reason: '실패를 조용히 삼켰다 — 회원은 칩이 안 먹은 줄 모른다');
    });

    testWidgets('스낵바 문구가 서버 메시지 그대로 — 하지도 않은 체크 얘기를 하지 않는다', (tester) async {
      // 종전 문구가 "체크 저장에 실패했어요"로 고정돼 있어서, 칩 전환 실패에도
      // 홈워크 체크 얘기가 나왔다.
      await pumpHome(tester, hasUsablePass: true);
      repo.failNext = const NetworkFailure('연결이 불안정해요');
      await container.read(homeViewModelProvider.notifier).selectPass('p1');
      await tester.pumpAndSettle();

      expect(find.textContaining('체크 저장'), findsNothing);
    });
  });

  group('③ 만료 회원권 빈 상태가 실패를 삼키지 않는다', () {
    testWidgets('새로고침이 실패하면 빈 상태 대신 에러가 보인다', (tester) async {
      // riverpod은 새로고침 중에도 직전 값을 유지한다. 그래서 `noUsablePass`를
      // 값만 보고 판정하면 만료 상태에서 실패가 **영영 안 보인다** — 회원은
      // 새로고침을 눌러도 아무 반응이 없는 화면을 본다.
      await pumpHome(tester, hasUsablePass: false);
      expect(find.byType(EmptyPassesView), findsOneWidget);

      repo.failAlways = const NetworkFailure('연결이 불안정해요');
      container.read(homeViewModelProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.byType(RiseErrorView), findsOneWidget,
          reason: '새로고침 실패가 화면에 전혀 안 보인다');
    });

    testWidgets('실패가 없으면 종전대로 빈 상태 — 과잉 차단이 아니다', (tester) async {
      await pumpHome(tester, hasUsablePass: false);
      expect(find.byType(EmptyPassesView), findsOneWidget);
      expect(find.byType(RiseErrorView), findsNothing);
    });
  });
}

class _SwitchableRepo implements HomeRepository {
  _SwitchableRepo({required this.hasUsablePass});
  final bool hasUsablePass;

  /// 다음 호출 한 번만 실패시킨다(부분 갱신 실패 재현).
  Failure? failNext;

  /// 계속 실패시킨다(새로고침이 안 되는 상황 재현) — 한 번짜리로 두면
  /// `pumpAndSettle`이 도는 사이 다음 로드가 성공해 상태가 되돌아간다.
  Failure? failAlways;

  @override
  Future<Result<HomeSummary>> loadHome({
    required String memberId,
    String? preferredPassId,
  }) async {
    if (failAlways != null) return Err(failAlways!);
    final f = failNext;
    if (f != null) {
      failNext = null;
      return Err(f);
    }
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
      homeworkDate: DateTime(2026, 8, 29),
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
