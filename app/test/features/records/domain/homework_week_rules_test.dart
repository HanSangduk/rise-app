import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/records/domain/homework_week_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

// 순수 도메인 — GET /v1/hw-checks 실데이터를 주 단위(월~일)로 집계(v1.4).
// 기준 시각: 2026-08-19(수) → 이번 주 = 8/17(월)~8/23(일), 지난 주 = 8/10~8/16.
void main() {
  final now = DateTime(2026, 8, 19); // 수요일

  group('HomeworkWeekRules.summarize', () {
    test('이번 주/지난 주 라벨·done/total 집계 (일요일도 같은 주에 포함)', () {
      final checks = [
        // 이번 주: 월(2/3) + 수(1/1) = 3/4
        HomeworkCheckDay(date: DateTime(2026, 8, 17), done: const [true, false, true]),
        HomeworkCheckDay(date: DateTime(2026, 8, 19), done: const [true]),
        // 지난 주 일요일(8/16) — 월~일 주 규칙에서 지난 주로 집계돼야 한다.
        HomeworkCheckDay(date: DateTime(2026, 8, 16), done: const [true, true]),
      ];

      final weeks = HomeworkWeekRules.summarize(now: now, checks: checks);

      expect(weeks, hasLength(2));

      expect(weeks[0].label, '이번 주');
      expect(weeks[0].isCurrent, isTrue);
      expect(weeks[0].done, 3);
      expect(weeks[0].total, 4);

      expect(weeks[1].label, '지난 주');
      expect(weeks[1].isCurrent, isFalse);
      expect(weeks[1].done, 2);
      expect(weeks[1].total, 2);
    });

    test('체크 없는 주는 행 생략, 3주 전 라벨, 4주 범위 밖은 제외', () {
      final checks = [
        // 3주 전(7/27~8/2): 0/1
        HomeworkCheckDay(date: DateTime(2026, 8, 2), done: const [false]),
        // 5주 전 — 기본 4주 범위 밖이라 제외.
        HomeworkCheckDay(date: DateTime(2026, 7, 14), done: const [true]),
      ];

      final weeks = HomeworkWeekRules.summarize(now: now, checks: checks);

      // 이번 주·지난 주·2주 전은 체크가 없어 행이 없다(0/0 노이즈 방지).
      expect(weeks, hasLength(1));
      expect(weeks[0].label, '3주 전');
      expect(weeks[0].done, 0);
      expect(weeks[0].total, 1);
      expect(weeks[0].isCurrent, isFalse);
    });

    test('체크가 하나도 없으면 빈 목록', () {
      expect(HomeworkWeekRules.summarize(now: now, checks: const []), isEmpty);
    });
  });
}
