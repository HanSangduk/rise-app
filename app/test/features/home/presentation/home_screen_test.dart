import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/config/app_config.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/domain/home_repository.dart';
import 'package:rise_member/features/home/presentation/home_screen.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';

// 홈 헤더/회원권 카드의 코치 표기 회귀.
//
// ① trim 규칙이 반쪽이던 문제 — isUnresolved()는 trim해서 통과시키는데 뒤이은
//    보간은 원본이라 " 정혜린 "이 "담당  정혜린  코치"로 렌더됐다.
// ② 회원 이름이 비면 퇴사 앵커(_coachAnchor)가 통째로 사라지던 문제 — 이름을 못
//    받은 회원만 담당 코치가 바뀐 사실을 홈에서 볼 수 없었다.
// ③ 상품명이 비면 " · 정혜린"처럼 구분자가 매달리던 문제(이름 쪽만 막고 있었다).
void main() {
  late _FakeHomeRepository repo;

  setUp(() => repo = _FakeHomeRepository());

  Future<void> pumpHome(
    WidgetTester tester, {
    String memberName = '람',
    String? trainerName = '정혜린',
    bool trainerInactive = false,
    String product = 'PT 20회',
  }) async {
    repo
      ..trainerName = trainerName
      ..trainerInactive = trainerInactive
      ..product = product;
    final container = ProviderContainer.test(
      overrides: [
        homeRepositoryProvider.overrideWithValue(repo),
        centerPolicyProvider.overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
        staffMapProvider.overrideWithValue(const AsyncValue<Map<String, StaffDto>>.data({})),
      ],
    );
    container.read(sessionProvider.notifier).set(
          AppSession(
            uid: 'u1',
            role: 'member',
            centerId: 'c1',
            memberId: 'm1',
            memberName: memberName,
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('헤더 — 담당 코치 앵커', () {
    testWidgets('현직이면 이름만', (tester) async {
      await pumpHome(tester);

      expect(find.text('람 님 · 담당 정혜린 코치'), findsOneWidget);
    });

    testWidgets('퇴사면 이름 뒤에 "(퇴사)"', (tester) async {
      await pumpHome(tester, trainerInactive: true);

      expect(find.text('람 님 · 담당 정혜린 코치 (퇴사)'), findsOneWidget);
    });

    testWidgets('앞뒤 공백이 낀 이름도 이중 공백 없이', (tester) async {
      await pumpHome(tester, trainerName: ' 정혜린 ', trainerInactive: true);

      expect(find.text('람 님 · 담당 정혜린 코치 (퇴사)'), findsOneWidget);
    });

    testWidgets('회원 이름이 비어도 퇴사 앵커는 살아남는다', (tester) async {
      await pumpHome(tester, memberName: '', trainerInactive: true);

      expect(
        find.text('${AppConfig.centerFullName} · 담당 정혜린 코치 (퇴사)'),
        findsOneWidget,
      );
    });

    // P10 — 이름의 출처가 GET /v1/me로 바뀌었다(계약 v2.2). 그 값은 best-effort라
    // 없을 수 있으므로, 폴백 사슬은 그대로 살아 있어야 한다. 두 방향을 고정한다.
    testWidgets('세션에 이름이 있으면 "OOO 님" — 재실행 복원도 이 경로를 탄다', (tester) async {
      await pumpHome(tester, memberName: '김민지');

      expect(find.text('김민지 님 · 담당 정혜린 코치'), findsOneWidget);
    });

    testWidgets('이름이 없으면 센터명 — "  님"을 렌더하지 않는다', (tester) async {
      await pumpHome(tester, memberName: '', trainerName: null);

      expect(find.text(AppConfig.centerFullName), findsOneWidget);
      expect(find.textContaining('님'), findsNothing);
    });

    testWidgets('공백뿐인 이름도 같은 폴백 — 서버가 " "를 줘도 깨지지 않는다', (tester) async {
      await pumpHome(tester, memberName: '   ', trainerName: null);

      expect(find.text(AppConfig.centerFullName), findsOneWidget);
      expect(find.textContaining('님'), findsNothing);
    });

    testWidgets('코치 이름을 해석하지 못하면 문구를 통째로 생략', (tester) async {
      await pumpHome(tester, trainerName: '   ');

      // "람 님 · 담당  코치"(빈자리)도, 매달린 " · "도 남지 않는다.
      // (스위처 칩의 "담당 코치 · …"는 이름 자리 폴백이라 별개 — 그쪽은 유지된다.)
      expect(find.text('람 님'), findsOneWidget);
      expect(find.textContaining('람 님 ·'), findsNothing);
    });
  });

  group('회원권 카드 — 상품 · 코치 줄', () {
    testWidgets('둘 다 있으면 " · "로 잇는다', (tester) async {
      await pumpHome(tester);

      expect(find.text('PT 20회 · 정혜린'), findsOneWidget);
    });

    testWidgets('코치 이름이 없으면 상품명만', (tester) async {
      await pumpHome(tester, trainerName: null);

      expect(find.text('PT 20회'), findsOneWidget);
    });

    testWidgets('상품명이 비면 코치 이름만 — 앞에 " · "가 매달리지 않는다', (tester) async {
      await pumpHome(tester, product: '');

      // **회원권 카드 안에서만** 센다 — P30에서 담당 코치 카드가 생기면서 같은
      // 이름이 홈에 두 번 뜬다(이 카드의 "상품 · 코치" 줄과 코치 카드의 이름).
      // 화면 전체로 세면 이 테스트가 코치 카드의 존재 여부까지 잠그게 되어,
      // 정작 검증하려던 것(" · "가 매달리지 않는가)과 무관하게 깨진다.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('내 회원권'),
            matching: find.byType(RiseCard),
          ),
          matching: find.text('정혜린'),
        ),
        findsOneWidget,
      );
      // 헤더 배지도 같은 규칙(" · 잔여 8"처럼 매달리지 않는다).
      expect(find.text('잔여 8'), findsOneWidget);
    });
  });

  // 헤더는 `Expanded`(이름 줄) + `RiseBadge`(상품 · 잔여) 두 칸짜리 Row인데
  // 배지가 비유연이었다 — 상품명이 길면 배지가 Expanded를 밀어내고 화면 밖으로
  // 넘쳤다(RenderFlex 오버플로). 상품명은 서버 문자열이라 길이 상한이 없다.
  group('헤더 — 긴 상품명 · 큰 글꼴 배율', () {
    testWidgets('좁은 화면 + 배율 1.35에서도 넘치지 않는다', (tester) async {
      tester.view
        ..physicalSize = const Size(320 * 3, 640 * 3)
        ..devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.35; // app.dart 클램프 상한
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      await pumpHome(
        tester,
        memberName: '남궁민수정혜린',
        product: '3개월 집중 바디프로필 프리미엄 관리 프로그램 20회권',
      );

      expect(
        tester.takeException(),
        isNull,
        reason: '헤더 Row가 넘친다 — 배지가 비유연이면 긴 상품명에서 터진다',
      );
    });
  });
}

class _FakeHomeRepository implements HomeRepository {
  String? trainerName = '정혜린';
  bool trainerInactive = false;
  String product = 'PT 20회';

  @override
  Future<Result<HomeSummary>> loadHome({
    required String memberId,
    String? preferredPassId,
  }) async {
    return Ok(HomeSummary(
      passes: [
        PassOption(
          id: 'p1',
          product: product,
          trainerId: 't1',
          trainerName: trainerName,
          trainerInactive: trainerInactive,
          status: 'active',
          remaining: 8,
          totalSessions: 20,
          validFrom: DateTime(2026, 1, 1),
          validUntil: DateTime(2030, 12, 31),
        ),
      ],
      selectedPassId: 'p1',
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

  /// 스캔한 QR 원문을 그대로 기록한다 — 이 테스트는 코치 표기만 보지만, 시그니처가
  /// 계약(HomeRepository)과 어긋나면 컴파일이 깨지므로 인자를 받아 둔다.
  String? lastScannedToken;

  @override
  Future<Result<void>> selfCheckIn({String? scannedToken}) async {
    lastScannedToken = scannedToken;
    return const Ok(null);
  }
}
