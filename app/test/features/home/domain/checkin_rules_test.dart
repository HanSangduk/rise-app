import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/home/domain/checkin_rules.dart';

// 셀프 체크인 시간창 — 서버 `domain.CheckinWindow`(±30분, 닫힌 구간)의 거울(P44).
//
// 경계는 **절삭 없이** 재야 한다(P73). 종전 `inSeconds` 비교는 30분 0.0~0.999초를 "30분"으로
// 읽어 서버(`time.Time` 정확 비교)가 이미 거부하는 시각에 버튼이 열려 보였다 — 그 전의
// `inMinutes`가 0~59초를 삼키던 것과 같은 종류의 결함이 단위만 줄어 남아 있었다.
void main() {
  final start = DateTime(2026, 9, 26, 19); // 19:00 수업

  group('CheckinRules.isOpen — 닫힌 구간 [시작−30분, 시작+30분]', () {
    test('정확히 ±30:00.000은 열려 있다(양끝 포함 — 서버와 동일)', () {
      expect(CheckinRules.isOpen(startAt: start, now: start.subtract(const Duration(minutes: 30))), isTrue);
      expect(CheckinRules.isOpen(startAt: start, now: start.add(const Duration(minutes: 30))), isTrue);
      expect(CheckinRules.isOpen(startAt: start, now: start), isTrue);
    });

    test('±30:00.500 — 1초 미만이라도 넘으면 닫힌다(초 절삭이 있으면 여기서 열려 보인다)', () {
      const halfSecondPast = Duration(minutes: 30, milliseconds: 500);
      expect(CheckinRules.isOpen(startAt: start, now: start.add(halfSecondPast)), isFalse,
          reason: '30분 0.5초 뒤 — 서버는 이미 400인데 앱 버튼이 켜져 있었다');
      expect(CheckinRules.isOpen(startAt: start, now: start.subtract(halfSecondPast)), isFalse,
          reason: '30분 0.5초 전 — 아직 안 열렸는데 버튼이 켜져 있었다');
    });

    test('±30:01은 닫힌다(분 절삭이 있으면 여기서 열려 보인다)', () {
      const overByOneSecond = Duration(minutes: 30, seconds: 1);
      expect(CheckinRules.isOpen(startAt: start, now: start.add(overByOneSecond)), isFalse);
      expect(CheckinRules.isOpen(startAt: start, now: start.subtract(overByOneSecond)), isFalse);
    });

    test('opensAt/closesAt는 isOpen의 경계와 같은 시각이다(화면이 이 시각에 다시 그린다)', () {
      final opens = CheckinRules.opensAt(start);
      final closes = CheckinRules.closesAt(start);
      expect(opens, start.subtract(const Duration(minutes: 30)));
      expect(closes, start.add(const Duration(minutes: 30)));
      expect(CheckinRules.isOpen(startAt: start, now: opens), isTrue);
      expect(CheckinRules.isOpen(startAt: start, now: closes), isTrue);
      expect(CheckinRules.isOpen(startAt: start, now: opens.subtract(const Duration(microseconds: 1))), isFalse);
      expect(CheckinRules.isOpen(startAt: start, now: closes.add(const Duration(microseconds: 1))), isFalse);
    });
  });
}
