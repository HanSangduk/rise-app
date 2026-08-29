import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';

// 계약 v2.0 — "새 예약의 코치 선택지"에서 퇴사자를 빼는 규칙([BookablePass.isSelectable]).
//
// 회원 앱엔 별도의 코치 드롭다운이 없다: POST /v1/bookings는 트레이너가 아니라
// pass_id로 코치가 정해지므로 "내 회원권 전체" 보기의 패스 목록이 곧 선택지다.
// 그래서 필터는 패스 상태(isUsable)와 담당 코치 재직 여부를 함께 본다.
//
// 이미 잡힌 예약은 이 목록과 무관하다(MyBookingsList가 따로 렌더) — 그쪽 이름
// 해석은 계약대로 계속 유지된다.
void main() {
  BookablePass pass({
    String status = 'active',
    bool trainerInactive = false,
    int remaining = 5,
    int openBookings = 0,
    Set<String> offdays = const {},
  }) {
    return BookablePass(
      passId: 'p1',
      trainerId: 't1',
      trainerName: '정혜린',
      trainerInactive: trainerInactive,
      trainerOffdays: offdays,
      product: 'PT 20회',
      validFrom: DateTime(2026, 1, 1),
      validUntil: DateTime(2026, 12, 31),
      status: status,
      remaining: remaining,
      openBookings: openBookings,
    );
  }

  group('BookablePass.isSelectable', () {
    test('현직 코치 + 사용 가능한 패스 + 잔여 있음 → 선택지에 뜬다', () {
      expect(pass().isSelectable, isTrue);
    });

    test('담당 코치가 퇴사하면 사용 가능한 패스라도 선택지에서 빠진다', () {
      expect(pass(trainerInactive: true).isSelectable, isFalse);
    });

    test('만료·환불 패스는 종전대로 선택지에서 빠진다(isUsable 규칙 유지)', () {
      expect(pass(status: 'expired').isSelectable, isFalse);
      expect(pass(status: 'refunded').isSelectable, isFalse);
    });

    test('잔여 0이면 서버가 100% 거부하므로 선택지에서 빠진다', () {
      // 백엔드엔 패스를 expired로 넘기는 코드가 없어, 다 쓴 패스도 유효기간이
      // 남는 한 status는 계속 active다 — status만 봐서는 절대 걸러지지 않는다.
      expect(pass(remaining: 0).isSelectable, isFalse);
      expect(pass(remaining: -1).isSelectable, isFalse);
      expect(pass(remaining: 1).isSelectable, isTrue);
    });

    test('isUsable은 active·scheduled — 서버 BookableStatus와 같다', () {
      // 서버가 회원권 상태를 유효기간에서 계산하기 시작하면서(P25) scheduled가
      // **실제로 내려오기 시작했다**. `CreateBooking`은 그 상태를 통과시킨다 —
      // 아직 시작 전인 재등록 회원권으로도 유효기간 안의 슬롯이면 선예약이 되어야
      // 하고(v1.3 시간축), 날짜 적합성은 NotYetValid가 슬롯별로 따로 본다.
      // 여기서 또 막으면 **서버는 받아주는 예약을 앱이 거부**한다.
      expect(pass().isUsable, isTrue);
      expect(pass(status: 'scheduled').isUsable, isTrue);
      expect(pass(status: 'scheduled').isSelectable, isTrue);
    });

    test('expired·refunded는 여전히 막는다 — 화이트리스트라 모르는 값도 막힌다', () {
      expect(pass(status: 'expired').isUsable, isFalse);
      expect(pass(status: 'refunded').isUsable, isFalse);
      expect(pass(status: 'weird_new_status').isUsable, isFalse);
    });

    test('isUsable 자체는 코치 재직·잔여에 영향받지 않는다(패스 상태만 본다)', () {
      // 퇴사 사실이 패스를 무효로 만들지는 않는다 — 회원은 잔여 회차를 그대로
      // 갖고 있고 센터가 담당을 재배정하면 다시 예약할 수 있다.
      expect(pass(trainerInactive: true).isUsable, isTrue);
      expect(pass(remaining: 0).isUsable, isTrue);
    });

    test('trainerInactive 기본값은 false — 구버전 서버/미해석은 현직으로 본다', () {
      final p = BookablePass(
        passId: 'p1',
        trainerId: 't1',
        product: 'PT 20회',
        validFrom: DateTime(2026, 1, 1),
        validUntil: DateTime(2026, 12, 31),
        status: 'active',
        remaining: 3,
        openBookings: 0,
      );
      expect(p.trainerInactive, isFalse);
      expect(p.trainerOffdays, isEmpty);
      expect(p.isSelectable, isTrue);
    });
  });

  // P13 H1 — 서버 예약 예산: `pass.Remaining − 이 패스의 confirmed 예약 수`.
  // 잔여는 완료 시점에만 차감되므로(P4) 예약을 잡아도 줄지 않는다.
  group('BookablePass 예약 예산(bookingBudget / hasBookingBudget)', () {
    test('경계 — 잔여 2·확정 1이면 1건 더, 잔여 2·확정 2면 0건', () {
      expect(pass(remaining: 2, openBookings: 1).bookingBudget, 1);
      expect(pass(remaining: 2, openBookings: 1).hasBookingBudget, isTrue);
      expect(pass(remaining: 2, openBookings: 2).bookingBudget, 0);
      expect(pass(remaining: 2, openBookings: 2).hasBookingBudget, isFalse);
    });

    test('음수 예산도 그대로 노출하되 판정은 서버와 같은 `<= 0`', () {
      expect(pass(remaining: 2, openBookings: 5).bookingBudget, -3);
      expect(pass(remaining: 2, openBookings: 5).hasBookingBudget, isFalse);
    });

    test('isSelectable은 예산을 보지 않는다 — 다 잡아 둔 회원권도 목록엔 남는다', () {
      // 여기서 걸러 버리면 "내 회원권 전체" 뷰의 패스 목록이 통째로 비고, 그 회원이
      // **이미 잡아 둔 자기 예약의 "확정" 배지까지** 사라진다. 잔여 10회를 10주치
      // 고정으로 채운 회원이 곧 이 상태라 예외가 아니라 정상 상태다.
      final full = pass(remaining: 2, openBookings: 2);
      expect(full.isSelectable, isTrue);
      expect(full.canBookNew, isFalse);
    });

    test('canBookNew는 선택지 조건 + 예산을 함께 본다', () {
      expect(pass(remaining: 2, openBookings: 1).canBookNew, isTrue);
      expect(pass(remaining: 2, openBookings: 2).canBookNew, isFalse);
      // 예산이 남아도 선택지 조건이 어긋나면 새 예약은 못 만든다.
      expect(pass(remaining: 2, trainerInactive: true).canBookNew, isFalse);
      expect(pass(remaining: 2, status: 'refunded').canBookNew, isFalse);
      expect(pass(remaining: 0).canBookNew, isFalse);
    });
  });

  // 계약: GET /v1/staff는 member 응답에서도 offdays를 그대로 내려준다(payout만 마스킹).
  // 서버는 슬롯 날짜를 "YYYY-MM-DD"로 찍어 이 목록과 문자열 비교하므로 앱도 같은
  // 포맷으로 맞춘다 — 느슨하게 맞추면 앱만 막고 서버는 통과하는 반대 불일치가 난다.
  group('BookablePass.isTrainerOffday', () {
    test('같은 날짜면 true, 하루라도 벗어나면 false', () {
      final p = pass(offdays: {'2026-08-14', '2026-08-15'});
      expect(p.isTrainerOffday(DateTime(2026, 8, 14)), isTrue);
      expect(p.isTrainerOffday(DateTime(2026, 8, 15)), isTrue);
      expect(p.isTrainerOffday(DateTime(2026, 8, 13)), isFalse);
      expect(p.isTrainerOffday(DateTime(2026, 8, 16)), isFalse);
    });

    test('시각이 붙어 있어도 날짜 단위로 판정한다', () {
      final p = pass(offdays: {'2026-08-14'});
      expect(p.isTrainerOffday(DateTime(2026, 8, 14, 23, 59)), isTrue);
    });

    test('휴무 정보가 없으면(조회 실패·구버전 서버) 아무 날도 막지 않는다', () {
      expect(pass().isTrainerOffday(DateTime(2026, 8, 14)), isFalse);
    });
  });

  // 예약 탭은 "퇴사 여부"를 두 곳에서 읽고 있었다 — repository가 매번 새로 만드는
  // 이 플래그와, 15분 TTL 스태프 캐시(staffMapProvider). 그래서 한 화면 안에서
  // 라벨은 "(퇴사)"인데 아바타는 총천연색이고, 그 칩이 여는 프로필 시트는 퇴사를
  // 설명하지 못했다. 화면이 단일 출처로 쓰는 조회 지점을 여기서 고정한다.
  group('BookingScreenData.trainerInactiveOf', () {
    BookingScreenData data(List<BookablePass> passes) => BookingScreenData(
          selectedDate: DateTime(2026, 8, 23),
          slots: const [],
          myBookings: const [],
          myPasses: passes,
          primaryPassId: passes.first.passId,
        );

    test('내 패스의 코치면 그 패스의 플래그가 답', () {
      final d = data([
        pass(trainerInactive: true),
        BookablePass(
          passId: 'p2',
          trainerId: 't2',
          trainerName: '김태오',
          product: 'PT 10회',
          validFrom: DateTime(2026, 1, 1),
          validUntil: DateTime(2026, 12, 31),
          status: 'active',
          remaining: 4,
          openBookings: 0,
        ),
      ]);

      expect(d.trainerInactiveOf('t1'), isTrue);
      expect(d.trainerInactiveOf('t2'), isFalse);
    });

    test('모르는 코치면 null — "모른다"와 "현직"을 뭉치지 않는다', () {
      // false로 뭉개면 캐시가 아는 퇴사 사실까지 화면이 덮어써 현직으로 만든다.
      expect(data([pass()]).trainerInactiveOf('t-unknown'), isNull);
    });
  });
}
