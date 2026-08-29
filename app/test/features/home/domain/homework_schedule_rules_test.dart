import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/home/domain/homework_schedule_rules.dart';

// API계약_v1.md Homework.schedule {type:"once|weekly", days:["tue","fri"], from, to}.
// 2026-08-14는 금요일("fri").
void main() {
  final friday = DateTime(2026, 8, 14);

  group('HomeworkScheduleRules.isActiveOn — weekly', () {
    test('오늘 요일이 days에 포함되면 true', () {
      expect(
        HomeworkScheduleRules.isActiveOn(date: friday, type: 'weekly', days: ['tue', 'fri']),
        isTrue,
      );
    });

    test('오늘 요일이 days에 없으면 false', () {
      expect(
        HomeworkScheduleRules.isActiveOn(date: friday, type: 'weekly', days: ['tue']),
        isFalse,
      );
    });

    test('days가 비면 매일로 간주', () {
      expect(HomeworkScheduleRules.isActiveOn(date: friday, type: 'weekly'), isTrue);
    });

    test('from/to 기간 밖이면 요일이 맞아도 false', () {
      expect(
        HomeworkScheduleRules.isActiveOn(
          date: friday,
          type: 'weekly',
          days: ['fri'],
          from: '2026-08-15',
        ),
        isFalse,
      );
      expect(
        HomeworkScheduleRules.isActiveOn(
          date: friday,
          type: 'weekly',
          days: ['fri'],
          to: '2026-08-13',
        ),
        isFalse,
      );
    });

    test('from/to 기간 내 + 요일 일치면 true', () {
      expect(
        HomeworkScheduleRules.isActiveOn(
          date: friday,
          type: 'weekly',
          days: ['fri'],
          from: '2026-08-01',
          to: '2026-08-31',
        ),
        isTrue,
      );
    });
  });

  group('HomeworkScheduleRules.isActiveOn — once', () {
    test('from == 오늘이면 true(당일 1회)', () {
      expect(
        HomeworkScheduleRules.isActiveOn(date: friday, type: 'once', from: '2026-08-14'),
        isTrue,
      );
    });

    test('from이 오늘이 아니고 to가 없으면 false', () {
      expect(
        HomeworkScheduleRules.isActiveOn(date: friday, type: 'once', from: '2026-08-15'),
        isFalse,
      );
    });

    test('from~to 기간 내면 true, 밖이면 false', () {
      expect(
        HomeworkScheduleRules.isActiveOn(
          date: friday,
          type: 'once',
          from: '2026-08-10',
          to: '2026-08-20',
        ),
        isTrue,
      );
      expect(
        HomeworkScheduleRules.isActiveOn(
          date: friday,
          type: 'once',
          from: '2026-08-01',
          to: '2026-08-13',
        ),
        isFalse,
      );
    });

    test('from이 없으면 매일 취급', () {
      expect(HomeworkScheduleRules.isActiveOn(date: friday, type: 'once'), isTrue);
    });
  });

  group('HomeworkScheduleRules.isActiveOn — 스케줄 없음/미지원 type', () {
    test('type null(스케줄 미지정)은 매일 노출', () {
      expect(HomeworkScheduleRules.isActiveOn(date: friday), isTrue);
    });

    test('알 수 없는 type은 weekly처럼 폴백', () {
      expect(
        HomeworkScheduleRules.isActiveOn(date: friday, type: 'daily', days: ['fri']),
        isTrue,
      );
    });
  });
}
