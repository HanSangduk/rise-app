import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/features/booking/domain/booking_rules.dart';

// 센터 운영시간(policy.open_hour/close_hour) — **기본값이 정해지는 유일한 지점**.
//
// 예전엔 `BookingRules.openHour = 9` / `closeHour = 21`이 규칙 파일에 상수로 박혀
// 있었다. 06시에 열거나 23시에 닫는 센터는 그 시간대를 앱에서 표현할 방법 자체가
// 없어, 실제 영업 중인 시간을 회원이 예약할 수 없었다. 지금은 서버 정책이 진실이고
// 여기(정책을 읽는 경계)에서만 "서버가 안 줬을 때"와 "말이 안 되는 값일 때"를 정한다.
//
// 이 파일이 지키는 두 약속:
//  ① 구버전 서버(필드 부재) = **오늘 동작 그대로** 09~21시 13칸. 한 칸도 달라지면 안 된다.
//  ② open_hour/close_hour는 슬롯 **시작** 시각이고 **양끝 포함**이다.
void main() {
  group('CenterPolicy.resolveHours — 와이어 값 → 실제로 쓸 운영시간', () {
    test('둘 다 부재(구버전 서버) → 9·21 = 이 필드가 생기기 전과 같은 동작', () {
      expect(CenterPolicy.resolveHours(null, null), (9, 21));
      expect(CenterPolicy.defaultOpenHour, 9);
      expect(CenterPolicy.defaultCloseHour, 21);
    });

    test('둘 다 유효 → 그대로 통과(넓은 구간·좁은 구간·한 칸)', () {
      expect(CenterPolicy.resolveHours(6, 23), (6, 23));
      expect(CenterPolicy.resolveHours(10, 11), (10, 11));
      expect(CenterPolicy.resolveHours(14, 14), (14, 14));
      expect(CenterPolicy.resolveHours(0, 23), (0, 23));
    });

    test('한쪽만 옴 → 온 값은 존중하고 빠진 쪽만 기본값', () {
      // 서버가 말한 사실을 "짝이 안 맞는다"는 이유로 버리지 않는다.
      expect(CenterPolicy.resolveHours(6, null), (6, 21));
      expect(CenterPolicy.resolveHours(null, 23), (9, 23));
    });

    test('open > close(뒤집힘) → 기본값 — 그대로 두면 그날이 통째로 빈 화면이 된다', () {
      // 합성 루프가 한 칸도 돌지 않아 "이 날짜엔 열린 슬롯이 없어요"만 남는다.
      expect(CenterPolicy.resolveHours(22, 6), (9, 21));
      expect(CenterPolicy.resolveHours(21, 20), (9, 21));
    });

    test('범위 밖(0..23) → 기본값 — 없는 영업시간을 만들어내지 않는다', () {
      expect(CenterPolicy.resolveHours(9, 99), (9, 21)); // 78칸이 생길 뻔한 값
      expect(CenterPolicy.resolveHours(-3, 21), (9, 21));
      expect(CenterPolicy.resolveHours(-1, 24), (9, 21));
    });

    test('경계값 0과 23은 유효 — 범위 검사가 한 칸 좁으면 24시간 센터가 막힌다', () {
      expect(CenterPolicy.resolveHours(0, 0), (0, 0));
      expect(CenterPolicy.resolveHours(23, 23), (23, 23));
    });
  });

  group('CenterPolicy 기본값', () {
    test('fallback(정책 조회 실패)의 운영시간도 9·21', () {
      // "서버가 필드를 안 준 구버전"과 "정책 조회 자체가 실패"가 회원에게 다르게
      // 보이면 안 된다 — 둘 다 오늘의 09~21시다.
      expect(CenterPolicy.fallback.openHour, 9);
      expect(CenterPolicy.fallback.closeHour, 21);
      expect(
        (CenterPolicy.fallback.openHour, CenterPolicy.fallback.closeHour),
        CenterPolicy.resolveHours(null, null),
      );
    });

    test('생성자 기본값도 같은 상수를 쓴다(다른 정책 테스트가 운영시간을 몰라도 안전)', () {
      const p = CenterPolicy(
        slotCapacity: 3,
        cancelCutoffHours: 48,
        graceOnce: false,
        penaltyRate: 0.10,
        expiringDays: 7,
        maxHoldsPerPass: 2,
        maxHoldTotalDays: 30,
      );
      expect(p.openHour, CenterPolicy.defaultOpenHour);
      expect(p.closeHour, CenterPolicy.defaultCloseHour);
    });
  });

  group('경계 → 규칙 연결 — 정책이 없을 때 슬롯 목록이 종전과 동일한가', () {
    final date = DateTime(2026, 8, 14);

    List<String> keysFor(int? wireOpen, int? wireClose) {
      final (openHour, closeHour) = CenterPolicy.resolveHours(wireOpen, wireClose);
      return BookingRules.mergeWithOpenHours(
        date: date,
        serverSlots: const [],
        capacity: 3,
        openHour: openHour,
        closeHour: closeHour,
      ).map((s) => s.slotKey).toList();
    }

    test('와이어에 값이 없으면 09~21시 13칸(첫 09시 · 마지막 21시) — 하드코딩 시절 그대로', () {
      expect(keysFor(null, null), [
        '20260814-09',
        '20260814-10',
        '20260814-11',
        '20260814-12',
        '20260814-13',
        '20260814-14',
        '20260814-15',
        '20260814-16',
        '20260814-17',
        '20260814-18',
        '20260814-19',
        '20260814-20',
        '20260814-21',
      ]);
    });

    test('06시 개장·23시 마지막 수업이 실제로 목록에 나온다(종전엔 표현 불가)', () {
      final k = keysFor(6, 23);
      expect(k.first, '20260814-06');
      expect(k.last, '20260814-23');
      expect(k, hasLength(18));
    });

    test('말이 안 되는 값이 와도 빈 화면이 아니라 기본 13칸', () {
      expect(keysFor(22, 6), hasLength(13));
      expect(keysFor(9, 99), hasLength(13));
    });
  });
}
