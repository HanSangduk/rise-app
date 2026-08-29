import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/widgets/next_booking_card.dart';

// P51 — "셀프 체크인 버튼이 시간이 지나도 스스로 열리지 않는다"(갤럭시 S21 실기기).
//
// 재현: 19:00 예약. 18:26에 홈을 열면 버튼 비활성 + "수업 시작 전후 30분에 열려요".
// 앱을 켜 둔 채 18:32까지 기다려도(창은 18:30~19:30) 버튼은 여전히 회색이고, 당겨서
// 새로고침해야 열렸다. 회원은 그걸 알 방법이 없으니 데스크로 간다 — 셀프 체크인이
// 없애려던 바로 그 왕복이다.
//
// 원인은 `canCheckIn`이 **홈 로드 시점에 계산된 bool 필드**였다는 것. 시각 의존 값을
// 스냅샷에 넣으면 시계가 흘러도 절대 바뀌지 않는다. 지금은 [NextBooking]이 startAt만
// 들고 가고 카드가 `now`로 파생 계산하며, TimeBoundaryBuilder가 경계마다 다시 그린다.
//
// 이 파일의 시각 검증은 두 갈래다:
//  ① `withClock` 고정 시각 — **같은 데이터에 시각만 바꿔** 판정이 갈리는지. TZ 무관.
//  ② 실제 시계 + "가장 가까운 정시" — 프로덕션 호출부가 `DateTime.now()`가 아니라
//     `DateFmt.nowKst()`를 쓰는지(KST 축). 이쪽은 home_kst_axis_test.dart에서
//     repository 레이어에 있던 것을 판정이 옮겨오면서 함께 옮겼다.
//     ⚠️ 호스트가 KST면 두 값이 같아 회귀가 원리상 안 보인다 — **`TZ=UTC` 등
//     KST 아닌 TZ로도 한 번 돌리는 것까지가 검증이다**(date_format_test.dart 규약).
void main() {
  /// KST 벽시계 [h]시 [m]분에 해당하는 절대 시각(주입용).
  DateTime at(int h, int m) => DateTime.utc(2026, 8, 23, h - 9, m);

  /// 실기기 재현과 같은 예약 — 2026-08-23 19:00, 체크인 창 18:30~19:30.
  NextBooking booking({DateTime? startAt}) => NextBooking(
        id: 'b1',
        startAt: startAt ?? DateTime(2026, 8, 23, 19),
        kind: 'pt',
        trainerName: '정혜린',
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required NextBooking? booking,
    int cutoffHours = 24,
    String? checkedInBookingId,
    List<String>? taps,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: NextBookingCard(
            booking: booking,
            cutoffHours: cutoffHours,
            checkedInBookingId: checkedInBookingId,
            onCheckIn: () => taps?.add('tap'),
          ),
        ),
      ),
    );
  }

  bool checkInEnabled(WidgetTester tester) => tester
      .widget<RiseButton>(
        find.ancestor(
          of: find.text('셀프 체크인 (데스크 QR 스캔)'),
          matching: find.byType(RiseButton),
        ),
      )
      .onPressed !=
      null;

  const windowNotice = '셀프 체크인은 수업 시작 전후 30분에 열려요';

  group('셀프 체크인 창 — 같은 데이터, 시각만 바뀐다', () {
    testWidgets('창 이전(18:26)에는 비활성 + 안내 문구', (tester) async {
      await withClock(Clock.fixed(at(18, 26)), () async {
        await pumpCard(tester, booking: booking());

        expect(checkInEnabled(tester), isFalse);
        expect(find.text(windowNotice), findsOneWidget);
      });
    });

    testWidgets('창 안(18:32)에서는 활성 + 안내 문구 사라짐 — 데이터는 한 글자도 안 바뀌었다', (tester) async {
      await withClock(Clock.fixed(at(18, 32)), () async {
        await pumpCard(tester, booking: booking());

        expect(checkInEnabled(tester), isTrue);
        expect(find.text(windowNotice), findsNothing);
      });
    });

    testWidgets('창 이후(19:31)에는 다시 비활성 — 서버도 이때부턴 400이다', (tester) async {
      await withClock(Clock.fixed(at(19, 31)), () async {
        await pumpCard(tester, booking: booking());

        expect(checkInEnabled(tester), isFalse);
        expect(find.text(windowNotice), findsOneWidget);
      });
    });

    testWidgets('경계는 정확히 ±30분 — 서버 domain.CheckinWindow와 같은 닫힌 구간', (tester) async {
      await withClock(Clock.fixed(at(18, 30)), () async {
        await pumpCard(tester, booking: booking());
        expect(checkInEnabled(tester), isTrue, reason: '시작 −30분 정각은 서버가 열어 준다');
      });
      await withClock(Clock.fixed(at(19, 30)), () async {
        await pumpCard(tester, booking: booking());
        expect(checkInEnabled(tester), isTrue, reason: '시작 +30분 정각도 서버가 열어 준다');
      });
      await withClock(Clock.fixed(at(18, 29)), () async {
        await pumpCard(tester, booking: booking());
        expect(checkInEnabled(tester), isFalse);
      });
    });

    testWidgets('경계 판정은 초 단위 — 30분 30초는 이미 창 밖이다', (tester) async {
      // `inMinutes`는 절삭이라 30분 0~59초 구간이 통째로 "30분"으로 읽힌다.
      // 그러면 서버(±1800초)가 이미 거부하는 시각에 버튼만 열려 있고, 회원은
      // QR을 스캔한 뒤에야 400을 본다 — 창이 닫혔다는 사실을 데스크 앞에서 안다.
      await withClock(Clock.fixed(DateTime.utc(2026, 8, 23, 10, 30, 30)), () async {
        await pumpCard(tester, booking: booking()); // KST 19:30:30
        expect(checkInEnabled(tester), isFalse, reason: '시작 +30분 30초 — 서버는 400이다');
      });
      await withClock(Clock.fixed(DateTime.utc(2026, 8, 23, 9, 29, 30)), () async {
        await pumpCard(tester, booking: booking()); // KST 18:29:30
        expect(checkInEnabled(tester), isFalse, reason: '시작 −30분 30초 — 아직 창 전이다');
      });
    });
  });

  group('P51 회귀 — 앱을 켜 둔 채 기다리면 스스로 열린다', () {
    testWidgets('18:26에 열어 두고 18:32까지 기다리면, 새로고침 없이 버튼이 열린다', (tester) async {
      var fake = at(18, 26);
      final taps = <String>[];

      await withClock(Clock(() => fake), () async {
        await pumpCard(tester, booking: booking(), taps: taps);

        // 실기기 1~2단계 그대로.
        expect(checkInEnabled(tester), isFalse);
        expect(find.text(windowNotice), findsOneWidget);

        // 회원은 아무것도 하지 않는다. 당겨서 새로고침도 하지 않는다.
        fake = at(18, 32);
        await tester.pump(const Duration(minutes: 6));

        expect(checkInEnabled(tester), isTrue,
            reason: '창이 열렸는데 버튼이 회색이면 회원은 데스크로 간다 — 셀프 체크인의 존재 이유가 사라진다');
        expect(find.text(windowNotice), findsNothing);

        await tester.tap(find.text('셀프 체크인 (데스크 QR 스캔)'));
        expect(taps, ['tap'], reason: '열린 버튼은 실제로 눌려야 한다');
      });
    });

    testWidgets('창이 닫히는 19:30에도 스스로 잠긴다 — 열어 두면 400을 부르는 버튼이 남는다', (tester) async {
      var fake = at(19, 29);

      await withClock(Clock(() => fake), () async {
        await pumpCard(tester, booking: booking());
        expect(checkInEnabled(tester), isTrue);

        fake = at(19, 31);
        await tester.pump(const Duration(minutes: 2));

        expect(checkInEnabled(tester), isFalse);
        expect(find.text(windowNotice), findsOneWidget);
      });
    });

    testWidgets('다른 탭에 있는 동안 창이 열려도, 돌아오면 곧바로 열려 있다', (tester) async {
      var fake = at(18, 26);

      Widget tree({required bool visible}) => MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: TickerMode(
                // go_router indexedStack이 비활성 브랜치를 감싸는 방식.
                enabled: visible,
                child: NextBookingCard(
                  booking: booking(),
                  cutoffHours: 24,
                  onCheckIn: () {},
                ),
              ),
            ),
          );

      await withClock(Clock(() => fake), () async {
        await tester.pumpWidget(tree(visible: true));
        expect(checkInEnabled(tester), isFalse);

        // 예약 탭으로 이동 — 홈 위젯은 트리에 그대로 남는다(indexedStack).
        await tester.pumpWidget(tree(visible: false));
        fake = at(18, 40);
        await tester.pump(const Duration(minutes: 14));

        // 홈으로 복귀.
        await tester.pumpWidget(tree(visible: true));
        expect(checkInEnabled(tester), isTrue);
      });
    });

    testWidgets('체크인에 성공한 예약은 창이 열려도 "체크인 완료"로 잠긴 채다', (tester) async {
      var fake = at(18, 26);

      await withClock(Clock(() => fake), () async {
        await pumpCard(tester, booking: booking(), checkedInBookingId: 'b1');
        expect(find.text('체크인 완료'), findsOneWidget);

        fake = at(18, 32);
        await tester.pump(const Duration(minutes: 6));

        expect(find.text('체크인 완료'), findsOneWidget);
        expect(find.text('셀프 체크인 (데스크 QR 스캔)'), findsNothing);
        // 이미 출석한 회원에게 "아직 안 열렸어요"라고 말하지 않는다.
        expect(find.text(windowNotice), findsNothing);
      });
    });
  });

  group('무료 취소 컷오프 — 돈이 걸린 문구', () {
    const free = '24시간 전까지 취소 가능(예약 탭)';
    const charged = '지금 취소하면 세션 1회가 차감돼요(예약 탭)';

    testWidgets('컷오프 이전이면 "무료", 이후면 "1회 차감" — 시각만 다른 같은 예약', (tester) async {
      final start = DateTime(2026, 8, 24, 19); // 내일 19:00, 컷오프 = 오늘 19:00
      await withClock(Clock.fixed(at(18, 0)), () async {
        await pumpCard(tester, booking: booking(startAt: start));
        expect(find.text(free), findsOneWidget);
      });
      await withClock(Clock.fixed(at(20, 0)), () async {
        await pumpCard(tester, booking: booking(startAt: start));
        expect(find.text(charged), findsOneWidget);
      });
    });

    testWidgets('컷오프를 넘기는 순간 문구가 스스로 바뀐다 — 무료인 줄 알고 누르면 세션이 날아간다', (tester) async {
      var fake = at(18, 59);
      final start = DateTime(2026, 8, 24, 19); // 컷오프 = 오늘 19:00

      await withClock(Clock(() => fake), () async {
        await pumpCard(tester, booking: booking(startAt: start));
        expect(find.text(free), findsOneWidget);

        fake = at(19, 1);
        await tester.pump(const Duration(minutes: 2));

        expect(find.text(charged), findsOneWidget,
            reason: '굳어 있으면 회원은 "아직 무료"를 읽고 예약 탭으로 건너간다 — 차감은 되돌릴 수 없다');
        expect(find.text(free), findsNothing);
      });
    });

    testWidgets('컷오프는 센터 정책 실값 — 12시간이면 12시간으로 가른다', (tester) async {
      final start = DateTime(2026, 8, 24, 4); // 내일 04:00, 12h 컷오프 = 오늘 16:00
      await withClock(Clock.fixed(at(15, 0)), () async {
        await pumpCard(tester, booking: booking(startAt: start), cutoffHours: 12);
        expect(find.text('12시간 전까지 취소 가능(예약 탭)'), findsOneWidget);
      });
      await withClock(Clock.fixed(at(17, 0)), () async {
        await pumpCard(tester, booking: booking(startAt: start), cutoffHours: 12);
        expect(find.text(charged), findsOneWidget);
      });
    });
  });

  group("'오늘' 배지 — 자정을 넘겨도 굳지 않는다", () {
    testWidgets('내일 예약은 배지 없음 → 자정을 지나면 붙는다', (tester) async {
      var fake = at(23, 50); // 8/23 23:50 KST
      final tomorrow = DateTime(2026, 8, 24, 19);

      await withClock(Clock(() => fake), () async {
        await pumpCard(tester, booking: booking(startAt: tomorrow));
        expect(find.text('오늘'), findsNothing);

        fake = DateTime.utc(2026, 8, 23, 15, 0, 30); // 8/24 00:00:30 KST
        await tester.pump(const Duration(minutes: 10, seconds: 40));

        expect(find.text('오늘'), findsOneWidget);
      });
    });
  });

  group('시간축 — "지금"은 기기 로컬이 아니라 센터(KST)다', () {
    // ⚠️ 이 그룹만 실제 시계를 읽는다(withClock 없음). 프로덕션 호출부가
    // `DateFmt.nowKst()`인지 확인하는 게 목적이라 시각을 고정하면 의미가 없다.
    // 호스트가 KST면 `nowKst() == DateTime.now()`라 회귀가 안 보인다 —
    // TZ=UTC / TZ=Pacific/Honolulu로도 돌려야 검증이 끝난다.
    //
    // slotKey는 시간 단위라 "가장 가까운 정시"는 언제 돌려도 ±30분 안에 있다.
    DateTime nearestHourKst() {
      final now = DateFmt.nowKst();
      final floor = DateTime(now.year, now.month, now.day, now.hour);
      return now.difference(floor) < const Duration(minutes: 30)
          ? floor
          : floor.add(const Duration(hours: 1));
    }

    testWidgets('가장 가까운 정시 예약은 체크인이 열린다 (로컬 축이면 9시간 어긋나 닫힌다)', (tester) async {
      await pumpCard(tester, booking: booking(startAt: nearestHourKst()));

      expect(checkInEnabled(tester), isTrue,
          reason: '해외에서 수업 직전에 버튼이 안 열린다 — 서버는 열어 두는데 앱만 막는다');
    });

    testWidgets('세 시간 뒤 예약은 창 밖 — 항상 열리는 버튼이 아니다', (tester) async {
      await pumpCard(
        tester,
        booking: booking(startAt: nearestHourKst().add(const Duration(hours: 3))),
      );

      expect(checkInEnabled(tester), isFalse);
    });

    testWidgets('20시간 뒤 예약은 컷오프(24h) 밖 (로컬 축이면 29시간으로 읽혀 "무료"가 된다)', (tester) async {
      await pumpCard(
        tester,
        booking: booking(startAt: nearestHourKst().add(const Duration(hours: 20))),
      );

      expect(find.text('지금 취소하면 세션 1회가 차감돼요(예약 탭)'), findsOneWidget,
          reason: '"무료 취소" 안내를 믿고 취소했는데 세션이 차감되면 되돌릴 방법이 없다');
    });

    testWidgets('30시간 뒤 예약은 컷오프 안 — 판정이 상시 false로 굳지 않는다', (tester) async {
      await pumpCard(
        tester,
        booking: booking(startAt: nearestHourKst().add(const Duration(hours: 30))),
      );

      expect(find.text('24시간 전까지 취소 가능(예약 탭)'), findsOneWidget);
    });
  });

  testWidgets('예약이 없으면 빈 상태 그대로 — 타이머 걸 것도 없다', (tester) async {
    await withClock(Clock.fixed(at(18, 26)), () async {
      await pumpCard(tester, booking: null);

      expect(find.textContaining('예정된 예약이 없어요'), findsOneWidget);
      expect(find.text(windowNotice), findsNothing);
    });
  });
}
