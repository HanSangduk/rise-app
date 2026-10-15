import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/features/booking/presentation/widgets/date_strip.dart';

// 날짜 스트립은 **오늘부터 14개의 서로 다른 달력 날짜**다(P73).
//
// 종전 `base.add(Duration(days: i))`는 절대 시각 +24h×i라, 기기가 서머타임 지역이면 가을
// 전환(2026-11-01, 미국) 뒤 칩이 전날 23:00으로 밀려 "일 1"이 두 번 나오고 하루가 빠졌다.
// ⚠️ 호스트가 KST면 종전 코드도 통과한다 — `TZ=America/New_York`으로도 한 번 돌리는
// 것까지가 검증이다(date_format_test.dart와 같은 규약).
void main() {
  testWidgets('미국 가을 전환(11-01)을 낀 14일이 중복·누락 없이 이어진다', (tester) async {
    // KST 2026-10-25 00:00 = 10-24 15:00Z.
    await withClock(Clock.fixed(DateTime.utc(2026, 10, 24, 15)), () async {
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateStrip(selected: DateTime(2026, 10, 25), onSelect: (d) => picked = d),
          ),
        ),
      );

      final labels = tester.widgetList<RiseChip>(find.byType(RiseChip)).map((c) => c.label).toList();
      final dayNumbers = labels.map((l) => int.parse(l.split(' ').last)).toList();
      expect(dayNumbers, [25, 26, 27, 28, 29, 30, 31, 1, 2, 3, 4, 5, 6, 7]);
      expect(dayNumbers.toSet(), hasLength(14), reason: '같은 날짜 칩이 둘이다');
      // 11-01은 일요일, 11-02는 월요일 — 요일 라벨도 달력과 맞아야 한다.
      expect(labels[7], '일 1');
      expect(labels[8], '월 2');

      await tester.ensureVisible(find.text('월 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('월 2'));
      await tester.pump();
      expect(picked, DateTime(2026, 11, 2), reason: '탭으로 넘기는 값도 그 날짜의 자정이어야 한다');
    });
  });
}
