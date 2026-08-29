import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/utils/date_format.dart';

// 시간축 규약 회귀 — 서버는 전 계층이 **고정 KST(+09:00)** 로 판정하는데
// (backend/internal/domain/booking.go `KST = time.FixedZone("KST", 9*60*60)`,
// api/service.go `today()`), 앱은 슬롯키를 로컬 시각으로 파싱해 놓고 `DateTime.now()`와
// 비교하고 있었다. 국내에선 우연히 맞고 해외 체류·기기 시계 오설정에선 조용히 틀린다.
//
// 이 파일이 고정하는 것:
//  1. [DateFmt.toKst]는 **호스트 타임존과 무관하게** 같은 KST 벽시계를 낸다.
//     (검증 방식: 절대 시각(UTC)을 주입해 필드를 확인한다 — 테스트 자체가 TZ 독립적이다.
//      `TZ=UTC`·`TZ=America/New_York`·`TZ=Pacific/Auckland`·`TZ=Asia/Seoul` 네 가지로
//      실제로 돌려 같은 결과를 확인했다.)
//  2. 슬롯키 표현과 [DateFmt.nowKst]의 표현이 **같은 축**이라 비교가 성립한다.
//
// ⚠️ 실행 TZ에 대하여: `nowKst()`가 진짜 시계를 읽는 탓에, 호스트가 KST면
// `nowKst() == DateTime.now()`라 회귀가 보이지 않는다(뮤테이션 검증에서 확인 —
// `nowKst() => DateTime.now()`로 되돌리면 TZ=Asia/Seoul에선 전부 통과하고
// TZ=UTC에선 "간격은 (9시간 - 로컬오프셋)" 테스트가 깨진다).
// **이 파일을 KST 아닌 TZ로도 한 번 돌리는 것까지가 검증이다.**
void main() {
  group('DateFmt.toKst — 절대 시각 → 센터(KST) 벽시계', () {
    test('UTC 11:00 → KST 20:00 (같은 날)', () {
      final kst = DateFmt.toKst(DateTime.utc(2026, 8, 14, 11));

      expect(kst.year, 2026);
      expect(kst.month, 8);
      expect(kst.day, 14);
      expect(kst.hour, 20);
      expect(kst.minute, 0);
    });

    test('UTC 자정 직전 → KST는 이미 다음 날 (날짜 경계가 서버와 같다)', () {
      // 서버 `today()`가 2026-08-15를 말하는 순간 앱도 8/15여야 한다.
      final kst = DateFmt.toKst(DateTime.utc(2026, 8, 14, 15, 30));

      expect(kst.day, 15);
      expect(kst.hour, 0);
      expect(kst.minute, 30);
    });

    test('로컬 플래그 입력도 절대 시각으로 환산된다(입력의 isUtc에 의존하지 않는다)', () {
      final instant = DateTime.utc(2026, 8, 14, 11);
      // .toLocal()은 호스트 TZ에 따라 필드가 달라지지만 가리키는 순간은 같다.
      final fromLocal = DateFmt.toKst(instant.toLocal());
      final fromUtc = DateFmt.toKst(instant);

      expect(fromLocal, fromUtc);
      expect(fromLocal.hour, 20);
    });

    test('오프셋은 정확히 +9시간 — 임의의 시각에서도 성립', () {
      for (final instant in [
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 3, 8, 6, 59), // 미국 DST 전환일(호스트가 흔들려도)
        DateTime.utc(2026, 6, 30, 23, 59, 59),
        DateTime.utc(2026, 12, 31, 15),
      ]) {
        final expected = instant.toUtc().add(const Duration(hours: 9));
        final kst = DateFmt.toKst(instant);

        expect(
          [kst.year, kst.month, kst.day, kst.hour, kst.minute, kst.second],
          [expected.year, expected.month, expected.day, expected.hour, expected.minute, expected.second],
          reason: '$instant → KST 필드가 +9h와 달랐다',
        );
      }
    });
  });

  group('slotKeyToDateTime과 nowKst는 같은 축 위에 있다', () {
    // 핵심 판정 — "이 슬롯은 지났나"·"컷오프 안인가"는 두 값을 빼서 정한다.
    // 표현이 어긋나면(로컬 vs KST) 국내에선 0, 해외에선 오프셋 차만큼 오차가 난다.
    DateTime nowKstAt(DateTime instant) => DateFmt.toKst(instant);

    test('KST 20:00 슬롯 - KST 19:00 현재 = 1시간', () {
      final slot = DateFmt.slotKeyToDateTime('20260814-20');
      final now = nowKstAt(DateTime.utc(2026, 8, 14, 10)); // = KST 19:00

      expect(slot.difference(now), const Duration(hours: 1));
      expect(slot.isBefore(now), isFalse);
    });

    test('이미 지난 슬롯은 isBefore(now) — 기기가 어느 TZ든 같다', () {
      final slot = DateFmt.slotKeyToDateTime('20260814-09');
      final now = nowKstAt(DateTime.utc(2026, 8, 14, 3)); // = KST 12:00

      expect(slot.isBefore(now), isTrue);
    });

    test('취소 컷오프 24시간 — 경계 앞뒤가 뒤집히지 않는다', () {
      final slot = DateFmt.slotKeyToDateTime('20260815-20'); // KST 8/15 20:00
      final justInside = nowKstAt(DateTime.utc(2026, 8, 14, 11)); // KST 8/14 20:00 = 정확히 24h 전
      final justOutside = nowKstAt(DateTime.utc(2026, 8, 14, 11, 1)); // 23h59m 전

      expect(slot.difference(justInside) >= const Duration(hours: 24), isTrue);
      expect(slot.difference(justOutside) >= const Duration(hours: 24), isFalse);
    });
  });

  group('slotKeyToDateTime — 필드는 슬롯키 그대로(표시·날짜 판정이 서버와 일치)', () {
    test('20260814-20 → 8/14 20:00', () {
      final d = DateFmt.slotKeyToDateTime('20260814-20');

      expect([d.year, d.month, d.day, d.hour], [2026, 8, 14, 20]);
      expect(DateFmt.hhmm(d), '20:00');
      expect(DateFmt.monthDayWeekday(d), '8/14 (금)');
    });

    test('한 자리 시(09)도 표시와 날짜가 흔들리지 않는다', () {
      // 절대 시각으로 바꾸면 이 슬롯이 해외 기기에서 전날로 읽힌다 — 유효기간·홀딩
      // 판정이 하루 어긋나는 지점이라 필드 표현을 고정한다.
      final d = DateFmt.slotKeyToDateTime('20260815-09');

      expect([d.year, d.month, d.day, d.hour], [2026, 8, 15, 9]);
      expect(DateFmt.hhmm(d), '09:00');
    });

    test('toSlotKey ↔ slotKeyToDateTime 왕복', () {
      final d = DateFmt.slotKeyToDateTime('20260901-14');

      expect(DateFmt.toSlotKey(d, d.hour), '20260901-14');
    });
  });

  group('nowKst / todayKst — 실제 시계를 쓰지만 축은 KST', () {
    test('nowKst와 DateTime.now()의 간격은 (9시간 - 로컬오프셋)', () {
      // 기기가 KST면 0, UTC면 9시간. "무엇이 달라지는지"를 식으로 고정해 둔다.
      final wall = DateTime.now();
      final kst = DateFmt.nowKst();
      final localOffset = wall.timeZoneOffset;
      final expected = const Duration(hours: 9) - localOffset;

      expect(
        (kst.difference(wall) - expected).abs() < const Duration(seconds: 2),
        isTrue,
        reason: 'nowKst=$kst, now=$wall, localOffset=$localOffset',
      );
    });

    test('todayKst는 nowKst의 날짜를 자정으로 자른 값', () {
      final now = DateFmt.nowKst();
      final today = DateFmt.todayKst();

      expect([today.year, today.month, today.day], [now.year, now.month, now.day]);
      expect([today.hour, today.minute, today.second], [0, 0, 0]);
    });

    test('todayKst는 서버 today()와 같은 날짜 문자열을 만든다', () {
      // 서버: `time.Now().In(domain.KST).Format("2006-01-02")`.
      final expected = DateTime.now().toUtc().add(const Duration(hours: 9));
      String pad(int v) => v.toString().padLeft(2, '0');

      expect(
        DateFmt.isoDate(DateFmt.todayKst()),
        '${expected.year}-${pad(expected.month)}-${pad(expected.day)}',
      );
    });
  });
}
