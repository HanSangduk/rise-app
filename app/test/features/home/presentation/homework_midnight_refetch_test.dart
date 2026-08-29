import 'package:clock/clock.dart';
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
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/presentation/home_screen.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';

// Home Work 카드가 자정에 **스스로 오늘 목록으로 갈아탄다**(P17).
//
// 다른 자정 판정(유효기간 D-day·홀딩 배지·"지남")은 손에 든 값으로 다시 계산하면
// 되므로 서버 왕복이 0이다. 여기만 다르다: 날짜는 판정의 입력이 아니라 **어느
// 문서를 읽고 쓸지 고르는 키**이고(`GET/POST /v1/hw-checks?date=`), 배정 자체가
// 요일 스케줄로 달라져 항목 수까지 바뀐다. 오늘 목록은 로컬에서 만들 수가 없다.
//
// 그래서 이 파일이 고정하는 건 "재조회가 일어난다"와 "그 재조회가 폭주하지
// 않는다" 두 가지다 — 왕복을 여는 순간 후자가 진짜 위험이 된다.
//
// 시각은 UTC로 주입하고 기대값은 KST로 읽는다(TZ 독립 — time_boundary_builder_test와 같은 규약).
void main() {
  late _CountingHomeRepository repo;

  setUp(() => repo = _CountingHomeRepository());

  /// KST 벽시계 2026-08-[day] [h]:[m]:[s]에 해당하는 절대 시각.
  DateTime kst(int day, int h, int m, [int s = 0]) => DateTime.utc(2026, 8, day, h - 9, m, s);

  Future<void> pumpHome(WidgetTester tester, {bool visible = true}) async {
    final container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(repo),
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
        child: MaterialApp(
          theme: buildAppTheme(),
          // go_router가 indexedStack의 비활성 브랜치를 감싸는 것과 같은 모양.
          home: TickerMode(enabled: visible, child: const HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 23:50 → 00:00:01. 타이머는 +1초 여유를 두고 예약되므로 10분 2초를 흘린다.
  Future<void> crossMidnight(WidgetTester tester, void Function(DateTime) setNow) async {
    setNow(kst(24, 0, 0, 1));
    await tester.pump(const Duration(minutes: 10, seconds: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('23:50에 연 홈이 자정에 오늘 목록을 다시 읽어 온다', (tester) async {
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      await pumpHome(tester);
      expect(repo.loadCount, 1);
      expect(find.text('HW 2026-08-23'), findsOneWidget);

      // 회원은 아무것도 하지 않는다 — 시계만 흐른다.
      await crossMidnight(tester, (t) => now = t);

      expect(repo.loadCount, 2);
      expect(find.text('HW 2026-08-24'), findsOneWidget,
          reason: '어제 배정이 "Home Work · 오늘" 카드에 남아 있으면, 체크 한 번이 오늘 문서를 덮는다');
      expect(find.text('HW 2026-08-23'), findsNothing);
    });
  });

  testWidgets('재조회해도 날짜가 안 맞으면 그날치 한 번으로 멈춘다 — 재조회 루프 금지', (tester) async {
    // 재조회가 상황을 못 고치는 경우(서버·기기 시계가 계속 어제를 준다). 가드가
    // 없으면 "화면이 어제 → 재조회 → 여전히 어제 → 재조회"가 매 프레임 돌면서
    // 홈 로드 5~6 왕복을 무한 반복한다.
    repo.pinnedDate = DateTime(2026, 8, 23);
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      await pumpHome(tester);
      await crossMidnight(tester, (t) => now = t);

      expect(repo.loadCount, 2);

      // 프레임을 더 흘려도(리빌드가 계속돼도) 늘지 않는다.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(repo.loadCount, 2);
    });
  });

  testWidgets('다른 탭에 있는 동안엔 재조회하지 않는다 — 보이지도 않는 화면에 5~6 왕복', (tester) async {
    var now = kst(23, 23, 50);
    await withClock(Clock(() => now), () async {
      await pumpHome(tester, visible: false);
      expect(repo.loadCount, 1);

      await crossMidnight(tester, (t) => now = t);

      expect(repo.loadCount, 1,
          reason: 'TickerMode 게이팅이 풀리면 5개 탭이 자정에 동시에 깨어난다');
    });
  });

  testWidgets('날짜가 그대로면 앱을 재개해도 다시 읽지 않는다 — 왕복 0 원칙은 그대로', (tester) async {
    await withClock(Clock.fixed(kst(23, 10, 0)), () async {
      await pumpHome(tester);
      expect(repo.loadCount, 1);

      // resumed는 TimeBoundaryBuilder의 재평가 트리거다 — 재평가 자체는 공짜여야 한다.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(repo.loadCount, 1, reason: '앱을 열 때마다 홈이 두 번 로드되면 그건 그냥 낭비다');
    });
  });
}

class _CountingHomeRepository implements HomeRepository {
  int loadCount = 0;

  /// null이면 실제 `todayKst()` — 값을 박으면 "재조회해도 어제가 온다"를 만든다.
  DateTime? pinnedDate;

  @override
  Future<Result<HomeSummary>> loadHome({
    required String memberId,
    String? preferredPassId,
  }) async {
    loadCount++;
    final date = pinnedDate ?? DateFmt.todayKst();
    return Ok(HomeSummary(
      passes: [
        PassOption(
          id: 'p1',
          product: 'PT 20회',
          trainerId: 't1',
          trainerName: '정혜린',
          status: 'active',
          remaining: 8,
          totalSessions: 20,
          validFrom: DateTime(2026, 1, 1),
          validUntil: DateTime(2030, 12, 31),
        ),
      ],
      selectedPassId: 'p1',
      // 배정은 날짜마다 다르다(요일 스케줄) — 어느 날 목록을 보고 있는지 화면에서 읽힌다.
      homeworkItems: [
        HomeworkItem(hwId: 'h1', index: 0, name: 'HW ${DateFmt.isoDate(date)}', done: false),
      ],
      homeworkDate: date,
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
