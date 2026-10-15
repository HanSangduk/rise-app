import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/home/domain/home_models.dart';

// `PassOption.daysUntilExpiry`(D-day)는 **달력 날짜 차이**다(P73).
//
// 종전엔 로컬 플래그 `DateTime`끼리 `difference().inDays`였다 — 절대 시각 차라, 기기가
// 서머타임 지역이면 전환일을 낀 하루가 23시간이 되어 `inDays`가 0으로 떨어졌다(D-1이 D-0).
// 한국엔 DST가 없지만 이 산술은 **기기** 타임존 규칙을 탄다(해외 체류·외국 기기).
//
// ⚠️ 실행 TZ에 대하여(date_format_test.dart와 같은 주의): 호스트가 KST면 종전 코드도 전부
// 통과한다. `TZ=America/New_York`(2026-03-08 봄 전환)·`TZ=Europe/Berlin`(2026-03-29)로도
// 돌려야 되돌림이 죽는다 — **KST 아닌 TZ로도 한 번 돌리는 것까지가 검증이다.**
void main() {
  PassOption pass(DateTime validUntil) => PassOption(
        id: 'p1',
        product: 'PT 20회',
        trainerId: 't1',
        status: 'active',
        remaining: 5,
        totalSessions: 20,
        validFrom: DateTime(2026, 1, 1),
        validUntil: validUntil,
      );

  /// KST 자정 = 전날 15:00Z. `todayKst()`가 그 날짜를 돌려주도록 시계를 고정한다.
  Future<void> onKstDate(int y, int m, int d, Future<void> Function() body) =>
      withClock(Clock.fixed(DateTime.utc(y, m, d).subtract(const Duration(hours: 9))), body);

  test('미국 봄 전환일(2026-03-08) 기준 다음 날 만료는 D-1이다 — 23시간짜리 하루가 아니다', () async {
    await onKstDate(2026, 3, 8, () async {
      expect(pass(DateTime(2026, 3, 9)).daysUntilExpiry, 1);
      expect(pass(DateTime(2026, 3, 9)).expiryLabel, 'D-1');
      expect(pass(DateTime(2026, 3, 8)).daysUntilExpiry, 0);
      expect(pass(DateTime(2026, 3, 7)).expiryLabel, '만료');
    });
  });

  test('유럽 봄 전환일(2026-03-29)·미국 가을 전환일(2026-11-01)을 낀 구간도 달력 일수 그대로', () async {
    await onKstDate(2026, 3, 28, () async {
      expect(pass(DateTime(2026, 3, 30)).daysUntilExpiry, 2);
      expect(pass(DateTime(2026, 4, 4)).daysUntilExpiry, 7);
    });
    await onKstDate(2026, 10, 31, () async {
      expect(pass(DateTime(2026, 11, 2)).daysUntilExpiry, 2);
    });
  });

  test('validUntil의 시각 성분은 무시한다 — 만료 당일은 자정 뒤에도 D-0', () async {
    await onKstDate(2026, 8, 20, () async {
      expect(pass(DateTime(2026, 8, 20, 23, 59)).daysUntilExpiry, 0);
      expect(pass(DateTime(2026, 8, 21, 0, 1)).daysUntilExpiry, 1);
    });
  });
}
