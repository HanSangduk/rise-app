import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/widgets/time_boundary_builder.dart';

// [TimeBoundaryBuilder]의 계약 — "시간이 흐르면 스스로 다시 그린다"(P51).
//
// 이 위젯이 없던 시절의 결함: 시각 판정이 그린 순간에 굳어, 회원이 화면을 켜 둔 채
// 기다리면 창이 열려도 버튼이 회색으로 남았다. 여기서 고정하는 건 네 가지다.
//  ① 경계를 지나면 builder가 **새 now**로 다시 불린다.
//  ② 경계가 여러 개면 가장 이른 것부터 하나씩.
//  ③ 보이지 않으면(TickerMode off) 타이머를 돌리지 않는다 — indexedStack 때문에
//     탭을 떠나도 위젯이 살아 있다.
//  ④ 다시 보이게 되면(그리고 앱이 resumed되면) 즉시 재평가한다.
//
// "지금"은 `withClock`으로 고정한다 — `DateFmt.nowKst()`가 `clock.now()`를 읽으므로
// (date_format.dart) 실제로 기다리지 않고 경계를 넘길 수 있고, 존 스코프라 테스트
// 간 누수가 없다. 시각은 UTC로 주입하고 기대값은 KST로 읽는다(TZ 독립).
void main() {
  /// KST 벽시계 [h]시 [m]분에 해당하는 절대 시각.
  DateTime kst(int h, int m) => DateTime.utc(2026, 8, 23, h - 9, m);

  testWidgets('경계를 지나면 새 now로 다시 그린다 — 아무도 새로고침하지 않았는데', (tester) async {
    var fake = kst(18, 26);
    final rendered = <String>[];

    await withClock(Clock(() => fake), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimeBoundaryBuilder(
            boundaries: [DateTime(2026, 8, 23, 18, 30)],
            builder: (context, now) {
              final open = !now.isBefore(DateTime(2026, 8, 23, 18, 30));
              rendered.add(open ? '열림' : '닫힘');
              return Text(open ? '열림' : '닫힘');
            },
          ),
        ),
      );
      expect(find.text('닫힘'), findsOneWidget);

      // 회원은 아무것도 하지 않는다 — 시계만 흐른다.
      fake = kst(18, 32);
      await tester.pump(const Duration(minutes: 6));

      expect(find.text('열림'), findsOneWidget,
          reason: '창이 열렸는데 화면이 그대로다 — 회원은 당겨서 새로고침해야 한다는 걸 알 방법이 없다');
      expect(rendered, ['닫힘', '열림']);
    });
  });

  testWidgets('경계가 여러 개면 가장 이른 것부터 하나씩 넘는다', (tester) async {
    var fake = kst(18, 0);
    final seen = <String>[];

    await withClock(Clock(() => fake), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimeBoundaryBuilder(
            // 일부러 뒤섞고 과거 경계도 섞는다 — 정렬·필터는 위젯 몫이다.
            boundaries: [
              DateTime(2026, 8, 23, 19, 30),
              DateTime(2026, 8, 23, 10, 0), // 이미 지남
              DateTime(2026, 8, 23, 18, 30),
            ],
            builder: (context, now) {
              seen.add('${now.hour}:${now.minute.toString().padLeft(2, '0')}');
              return const SizedBox();
            },
          ),
        ),
      );

      fake = kst(18, 31);
      await tester.pump(const Duration(minutes: 31));
      fake = kst(19, 31);
      await tester.pump(const Duration(minutes: 60));

      expect(seen, ['18:00', '18:31', '19:31']);
    });
  });

  testWidgets('경계가 하나도 남지 않으면 더 깨지 않는다 — 주기 폴링이 아니다', (tester) async {
    var fake = kst(18, 0);
    var builds = 0;

    await withClock(Clock(() => fake), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimeBoundaryBuilder(
            boundaries: [DateTime(2026, 8, 23, 18, 30)],
            builder: (context, now) {
              builds++;
              return const SizedBox();
            },
          ),
        ),
      );
      fake = kst(18, 31);
      await tester.pump(const Duration(minutes: 31));
      expect(builds, 2);

      // 남은 경계가 없다 → 몇 시간이 흘러도 리빌드 0.
      fake = kst(23, 0);
      await tester.pump(const Duration(hours: 5));
      expect(builds, 2, reason: '경계가 없는데도 계속 깨우면 그건 폴링이고 배터리를 먹는다');
    });
  });

  testWidgets('보이지 않으면(TickerMode off) 타이머를 돌리지 않는다', (tester) async {
    var fake = kst(18, 0);
    var builds = 0;

    await withClock(Clock(() => fake), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: TickerMode(
            // go_router의 indexedStack이 비활성 브랜치를 이렇게 감싼다.
            enabled: false,
            child: TimeBoundaryBuilder(
              boundaries: [DateTime(2026, 8, 23, 18, 30)],
              builder: (context, now) {
                builds++;
                return Text('${now.hour}:${now.minute.toString().padLeft(2, '0')}');
              },
            ),
          ),
        ),
      );
      expect(builds, 1);

      fake = kst(18, 31);
      await tester.pump(const Duration(minutes: 31));
      expect(builds, 1, reason: '다른 탭에 있는 동안 타이머가 도는 건 순수한 배터리 낭비다');
    });
  });

  testWidgets('탭으로 돌아오면(TickerMode on) 곧바로 새 now로 그린다', (tester) async {
    var fake = kst(18, 0);

    Widget tree({required bool enabled}) => MaterialApp(
          home: TickerMode(
            enabled: enabled,
            child: TimeBoundaryBuilder(
              boundaries: [DateTime(2026, 8, 23, 18, 30)],
              builder: (context, now) =>
                  Text('${now.hour}:${now.minute.toString().padLeft(2, '0')}'),
            ),
          ),
        );

    await withClock(Clock(() => fake), () async {
      await tester.pumpWidget(tree(enabled: false));
      expect(find.text('18:00'), findsOneWidget);

      // 다른 탭에 있는 동안 경계를 지났다.
      fake = kst(18, 40);
      await tester.pump(const Duration(minutes: 40));
      expect(find.text('18:00'), findsOneWidget); // 아직 안 그렸다(안 보였으니까)

      // 홈 탭으로 복귀 — TickerMode는 InheritedWidget이라 리빌드가 따라온다.
      await tester.pumpWidget(tree(enabled: true));
      expect(find.text('18:40'), findsOneWidget,
          reason: '탭을 오가는 것만으로는 갱신이 안 되면, 회원은 여전히 굳은 판정을 본다');
    });
  });

  testWidgets('앱이 resumed되면 재평가한다 — 백그라운드에서 경계를 지나도', (tester) async {
    var fake = kst(18, 0);

    await withClock(Clock(() => fake), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimeBoundaryBuilder(
            boundaries: [DateTime(2026, 8, 23, 18, 30)],
            builder: (context, now) =>
                Text('${now.hour}:${now.minute.toString().padLeft(2, '0')}'),
          ),
        ),
      );

      // 회원이 앱을 백그라운드로 보낸다 → 타이머를 놓는다.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // 그 사이에 창이 열렸다. paused 상태라 타이머는 깨지 않는다.
      fake = kst(18, 45);
      await tester.pump(const Duration(minutes: 45));
      expect(find.text('18:00'), findsOneWidget);

      // 복귀 — 이 한 번의 재평가가 백그라운드 공백을 메운다.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('18:45'), findsOneWidget,
          reason: '회원은 앱을 백그라운드에 두고 기다리는 쪽이 더 흔하다 — 복귀가 곧 재평가여야 한다');
    });
  });

  testWidgets('atMidnight — 자정마다, 하루로 끝나지 않고 계속', (tester) async {
    var fake = kst(23, 50);
    final days = <int>[];

    await withClock(Clock(() => fake), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimeBoundaryBuilder(
            atMidnight: true,
            builder: (context, now) {
              days.add(now.day);
              return const SizedBox();
            },
          ),
        ),
      );

      fake = DateTime.utc(2026, 8, 23, 15, 0, 1); // KST 8/24 00:00:01
      await tester.pump(const Duration(minutes: 10, seconds: 2));
      fake = DateTime.utc(2026, 8, 24, 15, 0, 1); // KST 8/25 00:00:01
      await tester.pump(const Duration(hours: 24));

      expect(days, [23, 24, 25],
          reason: '경계 목록에 자정을 하나 넣는 방식이면 이튿날부터 다시 굳는다');
    });
  });

  testWidgets('dispose되면 타이머를 놓는다 — 죽은 위젯에 setState하지 않는다', (tester) async {
    var fake = kst(18, 0);
    var builds = 0;

    await withClock(Clock(() => fake), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimeBoundaryBuilder(
            boundaries: [DateTime(2026, 8, 23, 18, 30)],
            builder: (context, now) {
              builds++;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      fake = kst(19, 0);
      await tester.pump(const Duration(hours: 1));

      expect(builds, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
