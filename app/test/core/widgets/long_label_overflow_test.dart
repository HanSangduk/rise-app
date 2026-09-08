import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/pose_sequence_chips.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/presentation/widgets/my_bookings_list.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/widgets/pass_switcher_chips.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/widgets/pass_list.dart';

/// 한국어 긴 라벨 + 큰 글꼴 배율에서 RenderFlex 오버플로가 나지 않는지.
///
/// 상품명·코치 이름은 서버가 주는 문자열이라 길이 상한이 없는데, Row의 비유연
/// 자식으로 놓여 있어 길어지면 줄무늬 오버플로가 났다. 여기서 고정하는 건 두 가지다:
///  ① 긴 라벨에서 **넘치지 않는다**(Flexible + 말줄임).
///  ② 짧은 라벨에서는 **아무것도 달라지지 않는다** — 말줄임 처리가 평상시 렌더를
///     건드리면 그건 견고성이 아니라 회귀다.
///
/// 배율 상한은 `app.dart`의 클램프 상한(1.35)과 같은 값을 쓴다. 클램프를 올리려면
/// 이 테스트가 먼저 통과해야 한다.
void main() {
  const maxScale = 1.35;

  /// 실제 글리프 폭으로 재야 의미가 있다 — 테스트 기본 폰트는 모든 글자가 같은
  /// 폭이라 한국어 라벨의 실제 길이를 재현하지 못한다(touch_target_test와 같은 이유).
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Pretendard')
      ..addFont(
        File('assets/fonts/PretendardVariable.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
    await loader.load();
  });

  /// 좁은 기기(320dp — 아이폰 SE 1세대급)에서 [scale] 배율로 [child]를 그린다.
  Future<void> pump(WidgetTester tester, Widget child, {double scale = 1.0}) async {
    tester.view
      ..physicalSize = const Size(320 * 3, 640 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: const TextScaler.linear(1).clamp(
          minScaleFactor: scale,
          maxScaleFactor: scale,
        )),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 오버플로는 페인트 중 FlutterError로 보고된다 — 테스트가 붙잡아 둔 걸 꺼내 본다.
  void expectNoOverflow(WidgetTester tester) {
    expect(
      tester.takeException(),
      isNull,
      reason: 'RenderFlex 오버플로 — Row의 비유연 자식이 좁은 폭을 못 견딘다',
    );
  }

  // 실제로 들어올 수 있는 최악값: 긴 상품명 + 긴 코치 이름.
  const longProduct = '3개월 집중 바디프로필 프리미엄 관리 프로그램 20회권';
  const longCoach = '남궁민수정혜린';

  group('마이 탭 회원권 행 (PassList)', () {
    Widget passList(String product, String? coach) => ProviderScope(
          overrides: [
            centerPolicyProvider
                .overrideWithValue(const AsyncValue.data(CenterPolicy.fallback)),
          ],
          child: PassList(
            passes: [
              PassDetail(
                id: 'p1',
                product: product,
                trainerId: 't1',
                trainerName: coach,
                status: 'active',
                remaining: 8,
                totalSessions: 20,
                paidAmount: 1200000,
                validFrom: DateTime(2026, 1, 1),
                validUntil: DateTime(2030, 12, 31),
              ),
            ],
            onHoldTap: () {},
          ),
        );

    testWidgets('긴 상품명 + 긴 코치 이름 + 배지 — 넘치지 않는다', (tester) async {
      await pump(tester, passList(longProduct, longCoach), scale: maxScale);
      expectNoOverflow(tester);
      // 상태 배지는 잘리지 않는다 — 잘리면 "이용 중"인지 알 수 없다.
      expect(find.text('이용 중'), findsOneWidget);
    });

    testWidgets('짧은 라벨은 예전 그대로 온전히 보인다', (tester) async {
      await pump(tester, passList('PT 20회', '정혜린'));
      expectNoOverflow(tester);
      expect(find.text('PT 20회'), findsOneWidget);
      expect(find.text('· 정혜린'), findsOneWidget);
      expect(find.text('잔여 8회'), findsOneWidget);
    });
  });

  group('홈 패스 스위처 칩 (PassSwitcherChips)', () {
    Widget chips(String product, String? coach) => PassSwitcherChips(
          passes: [
            PassOption(
              id: 'p1',
              product: product,
              trainerId: 't1',
              trainerName: coach,
              status: 'active',
              remaining: 8,
              totalSessions: 20,
              validFrom: DateTime(2026, 1, 1),
              validUntil: DateTime(2030, 12, 31),
            ),
          ],
          selectedId: 'p1',
          onSelect: (_) {},
        );

    testWidgets('긴 라벨 — 알약이 두 줄로 접히지 않고 한 줄로 말줄임된다', (tester) async {
      await pump(tester, chips(longProduct, longCoach), scale: maxScale);
      expectNoOverflow(tester);

      final text = tester.widget<Text>(
        find.descendant(of: find.byType(RiseChip), matching: find.byType(Text)),
      );
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('짧은 라벨은 예전 그대로', (tester) async {
      await pump(tester, chips('PT 20회', '정혜린'));
      expectNoOverflow(tester);
      expect(find.text('정혜린 코치 · PT 20회 (활성)'), findsOneWidget);
    });
  });

  group('내 예약 행 (MyBookingsList)', () {
    testWidgets('긴 코치 이름 + 고정 표시 — 넘치지 않는다', (tester) async {
      await pump(
        tester,
        MyBookingsList(
          bookings: [
            MyBooking(
              id: 'b1',
              // MyBookingsList의 "다가오는 예약" 필터는 DateFmt.nowKst() 기준이다 —
              // 픽스처를 기기 로컬로 만들면 KST보다 뒤에 있는 지역에서 이 예약이
              // 필터에 걸려 행 자체가 렌더되지 않고, 넘침 검증이 조용히 공회전한다.
              slotKey: DateFmt.toSlotKey(DateFmt.todayKst().add(const Duration(days: 1)), 10),
              passId: 'p1',
              trainerId: 't1',
              trainerName: longCoach,
              kind: 'group',
              status: 'confirmed',
              recurringId: 'r1',
            ),
          ],
          onCancel: (_) async {},
          policy: CenterPolicy.fallback,
        ),
        scale: maxScale,
      );
      expectNoOverflow(tester);
    });
  });

  group('공용 위젯의 유계 처리', () {
    testWidgets('RiseBadge — 좁은 Row에서 두 줄로 늘어나지 않고 말줄임', (tester) async {
      await pump(
        tester,
        const Row(
          children: [
            Expanded(child: Text('앞 텍스트가 자리를 다 먹는 상황')),
            Flexible(child: RiseBadge('아주 긴 상품명 · 잔여 8', variant: RiseBadgeVariant.brand)),
          ],
        ),
        scale: maxScale,
      );
      expectNoOverflow(tester);
    });

    testWidgets('RiseChip(leading 있음) — 아바타 옆 라벨도 유계다', (tester) async {
      await pump(
        tester,
        RiseChip(
          leading: const SizedBox.square(dimension: 16),
          label: '내 코치 ($longCoach · 퇴사) 아주 긴 라벨입니다 정말로 길어요',
          onTap: () {},
        ),
        scale: maxScale,
      );
      expectNoOverflow(tester);

      // leading이 있으면 라벨이 `Row(mainAxisSize: min)` 안으로 들어간다 — Row는
      // 비유연 자식에게 무제한 폭을 주므로 Flexible이 없으면 알약이 화면 밖까지
      // 자란다(오버플로 없이 조용히 잘린다). 폭 자체를 재서 고정한다.
      expect(
        tester.getSize(find.byType(RiseChip)).width,
        lessThanOrEqualTo(320),
        reason: '칩이 화면(320dp)보다 넓다 — leading 옆 라벨이 유계가 아니다',
      );
    });

    testWidgets('촬영 포즈 칩 — 서버 상한(8개 × 12자)을 다 채워도 넘치지 않는다', (tester) async {
      // 포즈는 v2.10부터 **트레이너가 자유 입력**한다(하드코딩 4종이 아니다).
      // 서버 상한이 곧 최악의 경우다: `ValidateBodyPoses`가 개수 8 · 라벨 12자를 허용한다.
      // 320dp에서 8개를 늘어놓으면 Wrap이 여러 줄로 접히는데, 촬영 화면은 프리뷰가
      // Expanded라 이 줄 수만큼 위를 먹는다 — 세로로 밀어내는 쪽이 진짜 위험이다.
      const label = '가나다라마바사아자차카타'; // 정확히 12자
      final poses = [for (var i = 0; i < 8; i++) PoseSpec('pose_$i', label)];

      await pump(
        tester,
        PoseSequenceChips(
          poses: poses,
          completed: {poses.first.key},
          currentIndex: 0,
          onSelect: (_) {},
        ),
        scale: maxScale,
      );
      expectNoOverflow(tester);
    });

    testWidgets('RiseButton 전폭 CTA — 긴 이름이 들어가도 2줄에서 끊긴다', (tester) async {
      await pump(
        tester,
        RiseButton(
          label: '네, $longCoach 본인이에요 — 시작하기',
          expand: true,
          onPressed: () {},
        ),
        scale: maxScale,
      );
      expectNoOverflow(tester);

      final text = tester.widget<Text>(
        find.descendant(of: find.byType(RiseButton), matching: find.byType(Text)),
      );
      expect(text.maxLines, 2);
    });
  });
}
