import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_rules.dart';
import 'package:rise_member/features/my/domain/my_models.dart' show PassHold;

// 도메인은 순수 Dart라 codegen/SDK 없이 검증 가능(wodshot 09 Q6과 동일 원칙).
// API계약_v1.md P35: 용량3 + 트레이너동시1 + 잔여>0.
// 유효기간 판정은 "슬롯 날짜" 기준 — 슬롯 날짜가 [validFrom, validUntil] 밖이면 예약 불가.
//
// evaluate의 판정 순서는 백엔드 `CreateBooking`의 거부 순서를 그대로 따른다
// (status → 잔여 → 예약 예산 → 유효기간 → 홀딩 → 휴무일 → 슬롯 사정). 두 제약이 겹칠 때
// 앱이 서버와 다른 이유를 안내하지 않게 하려는 것이고, 아래 "우선순위" 그룹이
// 그 순서를 못박는다.
void main() {
  const slotKey = '20260814-20'; // 2026-08-14 20:00
  final validFromPast = DateTime(2026, 1, 1);
  final validUntilFuture = DateTime(2026, 12, 31);

  BookablePass pass({
    String trainerId = 't1',
    String status = 'active',
    int remaining = 5,
    int openBookings = 0,
    DateTime? validFrom,
    DateTime? validUntil,
    List<PassHold> holds = const [],
    Set<String> offdays = const {},
  }) {
    return BookablePass(
      passId: 'p1',
      trainerId: trainerId,
      trainerName: '정혜린',
      trainerOffdays: offdays,
      product: 'PT 20회',
      validFrom: validFrom ?? validFromPast,
      validUntil: validUntil ?? validUntilFuture,
      status: status,
      remaining: remaining,
      openBookings: openBookings,
      holds: holds,
    );
  }

  SlotBookState evaluate(Slot slot, BookablePass p, {String myMemberId = 'me'}) =>
      BookingRules.evaluate(slot: slot, pass: p, myMemberId: myMemberId);

  group('BookingRules.evaluate', () {
    test('빈 슬롯 → Bookable(잔여 3/3)', () {
      const slot = Slot(slotKey: slotKey, capacity: 3, teams: []);
      final state = evaluate(slot, pass());
      expect(state, isA<Bookable>());
      expect((state as Bookable).remaining, 3);
      expect(state.capacity, 3);
    });

    test('다른 트레이너 팀이 1개 있어도 내 트레이너는 비어있으면 → Bookable(잔여 2/3)', () {
      const slot = Slot(
        slotKey: slotKey,
        capacity: 3,
        teams: [SlotTeam(bookingId: 'b1', trainerId: 't2', memberId: 'other', kind: 'pt')],
      );
      final state = evaluate(slot, pass());
      expect(state, isA<Bookable>());
      expect((state as Bookable).remaining, 2);
    });

    test('같은 트레이너가 이미 이 슬롯에 팀이 있으면(잔여 있어도) → CoachBusy', () {
      const slot = Slot(
        slotKey: slotKey,
        capacity: 3,
        teams: [SlotTeam(bookingId: 'b1', trainerId: 't1', memberId: 'other', kind: 'pt')],
      );
      expect(evaluate(slot, pass()), isA<CoachBusy>());
    });

    test('용량 3 전부 참(다른 트레이너들) → SlotFull', () {
      const slot = Slot(
        slotKey: slotKey,
        capacity: 3,
        teams: [
          SlotTeam(bookingId: 'b1', trainerId: 't2', memberId: 'm1', kind: 'pt'),
          SlotTeam(bookingId: 'b2', trainerId: 't3', memberId: 'm2', kind: 'pt'),
          SlotTeam(bookingId: 'b3', trainerId: 't4', memberId: 'm3', kind: 'pt'),
        ],
      );
      expect(evaluate(slot, pass()), isA<SlotFull>());
    });

    test('이미 내 예약이 있으면 다른 조건과 무관하게 → AlreadyBookedByMe', () {
      const slot = Slot(
        slotKey: slotKey,
        capacity: 3,
        teams: [
          SlotTeam(bookingId: 'b1', trainerId: 't1', memberId: 'me', kind: 'pt'),
          SlotTeam(bookingId: 'b2', trainerId: 't2', memberId: 'm2', kind: 'pt'),
          SlotTeam(bookingId: 'b3', trainerId: 't3', memberId: 'm3', kind: 'pt'),
        ],
      );
      expect(evaluate(slot, pass()), isA<AlreadyBookedByMe>());
    });

    test('슬롯 날짜(8/14)가 패스 유효기간 시작(9/1) 전이면 → NotYetValid', () {
      const slot = Slot(slotKey: slotKey, capacity: 3, teams: []);
      final futureValidFrom = DateTime(2026, 9, 1);
      final state = evaluate(slot, pass(validFrom: futureValidFrom));
      expect(state, isA<NotYetValid>());
      expect((state as NotYetValid).validFrom, futureValidFrom);
    });

    test('슬롯 날짜(8/14)가 패스 유효기간 만료(8/10) 후면 → PassExpiredForSlot', () {
      const slot = Slot(slotKey: slotKey, capacity: 3, teams: []);
      final pastValidUntil = DateTime(2026, 8, 10);
      final state = evaluate(slot, pass(validUntil: pastValidUntil));
      expect(state, isA<PassExpiredForSlot>());
      expect((state as PassExpiredForSlot).validUntil, pastValidUntil);
    });

    test('슬롯 날짜가 일시정지(홀드) 구간 안이면 → PassOnHoldForSlot, 밖이면 영향 없음', () {
      const slot = Slot(slotKey: slotKey, capacity: 3, teams: []); // 2026-08-14
      final hold = PassHold(from: DateTime(2026, 8, 10), to: DateTime(2026, 8, 20));

      final onHold = evaluate(slot, pass(holds: [hold]));
      expect(onHold, isA<PassOnHoldForSlot>());
      expect((onHold as PassOnHoldForSlot).hold, same(hold));

      // 홀드 구간(8/1~8/13)이 슬롯 날짜(8/14)를 벗어나면 평소처럼 Bookable.
      final outsideHold = evaluate(
        slot,
        pass(holds: [PassHold(from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 13))]),
      );
      expect(outsideHold, isA<Bookable>());
    });

    test('슬롯 날짜 == validFrom / validUntil 경계일은 예약 가능(포함)', () {
      const slot = Slot(slotKey: slotKey, capacity: 3, teams: []); // 2026-08-14
      expect(evaluate(slot, pass(validFrom: DateTime(2026, 8, 14))), isA<Bookable>());
      expect(evaluate(slot, pass(validUntil: DateTime(2026, 8, 14))), isA<Bookable>());
    });
  });

  // ── CRITICAL: 잔여 0 ──────────────────────────────────────────────────────
  // 서버는 `pass.Remaining <= 0`이면 400 "잔여 세션이 없어요"로 100% 거부한다.
  // 그런데 백엔드엔 패스를 expired로 넘기는 코드가 없다(PassStatusExpired는 통계에서
  // 읽기만) — 20회를 다 쓴 패스도 유효기간이 남는 한 영원히 active로 온다. 즉 잔여 0은
  // 예외가 아니라 **모든 회원의 종착 상태**라, 여기가 뚫리면 회원 전원이 언젠가
  // "눌리는데 100% 실패하는 예약 버튼"을 만난다.
  group('잔여 세션(NoRemainingSessions) — 서버 "잔여 세션이 없어요"', () {
    const slot = Slot(slotKey: slotKey, capacity: 3, teams: []);

    test('잔여 0이면 슬롯이 텅 비어 있어도 예약 불가', () {
      expect(evaluate(slot, pass(remaining: 0)), isA<NoRemainingSessions>());
    });

    test('경계 — 1회 남으면 예약 가능, 0회면 불가', () {
      expect(evaluate(slot, pass(remaining: 1)), isA<Bookable>());
      expect(evaluate(slot, pass(remaining: 0)), isA<NoRemainingSessions>());
    });

    test('원장 정정 등으로 음수가 와도 "남았다"로 읽지 않는다', () {
      // 서버 판정이 `<= 0`이므로 음수도 거부다. `== 0`으로 짰다면 여기서 갈린다.
      expect(evaluate(slot, pass(remaining: -1)), isA<NoRemainingSessions>());
    });

    test('유효기간이 한참 남아 있어도(status는 계속 active) 잔여 0이면 막힌다', () {
      final state = evaluate(
        slot,
        pass(remaining: 0, validFrom: DateTime(2026, 1, 1), validUntil: DateTime(2030, 12, 31)),
      );
      expect(state, isA<NoRemainingSessions>());
    });

    test('잔여 0이어도 이미 잡힌 내 예약은 확정 그대로', () {
      // 예약을 잡을 때 이미 차감된 자리다 — "잔여 0"으로 덮으면 확정된 수업이
      // 취소된 것처럼 보인다.
      const bookedSlot = Slot(
        slotKey: slotKey,
        capacity: 3,
        teams: [SlotTeam(bookingId: 'b1', trainerId: 't1', memberId: 'me', kind: 'pt')],
      );
      expect(evaluate(bookedSlot, pass(remaining: 0)), isA<AlreadyBookedByMe>());
    });
  });

  // ── CRITICAL: 예약 예산(잔여 − 이미 잡힌 confirmed) ────────────────────────
  // P13 H1으로 서버 `CreateBooking`에 생긴 규칙:
  //     생성 가능 = pass.Remaining − countOpenPassBookings(이 패스의 confirmed)
  // 잔여는 **완료 시점에만** 차감되므로(P4) 예약을 잡아도 줄지 않는다 — 이 뺄셈이
  // 없으면 잔여 2회 패스에 예약을 무한히 잡을 수 있었다(실측: 4건 예약 → 4건 완료
  // → 잔여 −2). 즉 `remaining > 0`이어도 서버는 400으로 거부한다.
  //
  // 앱이 이 뺄셈을 안 하면 회원은 "잔여 2회"라고 적힌 화면에서 100% 거부될 예약
  // 버튼을 누르게 된다. 잔여 숫자가 멀쩡히 보이는 만큼 잔여 0보다 더 헷갈린다.
  group('예약 예산(AllRemainingBooked) — 서버 "이미 잡힌 예약 N건이 잔여 M회를 채웠어요"', () {
    const slot = Slot(slotKey: slotKey, capacity: 3, teams: []);

    test('경계 — 잔여 2·확정 1이면 가능, 잔여 2·확정 2면 불가', () {
      expect(evaluate(slot, pass(remaining: 2, openBookings: 1)), isA<Bookable>());

      final state = evaluate(slot, pass(remaining: 2, openBookings: 2));
      expect(state, isA<AllRemainingBooked>());
      // 문구가 두 숫자를 함께 말할 수 있어야 한다 — "잔여 2회인데 왜 안 되지"가
      // 이 상태의 기본 반응이라, 원인(예약 2건)을 같이 보여주지 않으면 설명이 안 된다.
      expect((state as AllRemainingBooked).remaining, 2);
      expect(state.openBookings, 2);
    });

    test('예산이 음수여도(원장 정정·수기 예약) "남았다"로 읽지 않는다', () {
      // 서버 판정이 `Remaining-open <= 0`이므로 음수도 거부다. `== 0`으로 짰다면 여기서 갈린다.
      expect(evaluate(slot, pass(remaining: 2, openBookings: 3)), isA<AllRemainingBooked>());
    });

    test('확정이 하나도 없으면 종전대로 잔여만 본다', () {
      expect(evaluate(slot, pass(remaining: 1, openBookings: 0)), isA<Bookable>());
    });

    test('잔여 0은 AllRemainingBooked가 아니라 NoRemainingSessions — 다음 행동이 다르다', () {
      // 잔여 0 = 실제 소진(재등록), 예산 0 = 이미 다 잡아 둠(기존 예약 취소).
      // 뭉치면 회차가 남은 회원에게 "재등록해주세요"라고 안내하게 된다.
      expect(evaluate(slot, pass(remaining: 0, openBookings: 0)), isA<NoRemainingSessions>());
      expect(evaluate(slot, pass(remaining: 0, openBookings: 5)), isA<NoRemainingSessions>());
    });

    test('예산 소진이 유효기간·홀딩·휴무보다 먼저(서버: 잔여 → 예산 → 시간축)', () {
      // 순서가 어긋나면 회원은 앱이 시킨 대로 날짜를 옮기고 또 거부당한다.
      final state = evaluate(
        slot,
        pass(
          remaining: 2,
          openBookings: 2,
          validUntil: DateTime(2026, 8, 10), // 기간도 지났고
          holds: [PassHold(from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31))], // 홀딩 중이고
          offdays: {'2026-08-14'}, // 휴무일이기도 하다
        ),
      );
      expect(state, isA<AllRemainingBooked>());
    });

    test('status·잔여 검사는 예산보다 먼저(서버 거부 순서)', () {
      expect(
        evaluate(slot, pass(status: 'refunded', remaining: 2, openBookings: 2)),
        isA<PassNotUsable>(),
      );
    });

    test('예산이 0이어도 이미 잡힌 내 예약은 확정 그대로', () {
      // 이 슬롯을 문 예약이 곧 예산을 소진시킨 그 예약이다 — "예약 불가"로 덮으면
      // 회원이 방금 잡은 수업이 취소된 것처럼 보인다.
      const bookedSlot = Slot(
        slotKey: slotKey,
        capacity: 3,
        teams: [SlotTeam(bookingId: 'b1', trainerId: 't1', memberId: 'me', kind: 'pt')],
      );
      expect(
        evaluate(bookedSlot, pass(remaining: 2, openBookings: 2)),
        isA<AlreadyBookedByMe>(),
      );
    });
  });

  // 서버 `countOpenPassBookings`의 거울. 세는 범위가 어긋나면 판정식이 맞아도
  // 결과가 갈린다 — 특히 "완료/노쇼는 이미 차감된 회차"와 "지난 confirmed도 센다"가
  // 반대 방향의 오차를 만든다.
  group('BookingRules.countOpenBookings — 서버 countOpenPassBookings와 같은 모집단', () {
    MyBooking booking(String id, {String passId = 'p1', String status = 'confirmed', int day = 20}) =>
        MyBooking(
          id: id,
          slotKey: '202608${day.toString().padLeft(2, '0')}-10',
          passId: passId,
          trainerId: 't1',
          kind: 'pt',
          status: status,
        );

    test('이 패스의 confirmed만 센다 — 다른 패스 예약은 이 패스의 예산과 무관하다', () {
      final list = [
        booking('b1'),
        booking('b2'),
        booking('b3', passId: 'p2'), // 다른 회원권(코치·유효기간이 다르다)
      ];
      expect(BookingRules.countOpenBookings(list, 'p1'), 2);
      expect(BookingRules.countOpenBookings(list, 'p2'), 1);
      expect(BookingRules.countOpenBookings(list, 'p-none'), 0);
    });

    test('취소·완료·노쇼·대기는 세지 않는다', () {
      // 완료/노쇼는 **이미 원장에서 차감된** 회차라 다시 세면 이중 차감이고,
      // 취소는 청구권을 되돌려준 건이다. 서버도 status == confirmed만 센다.
      final list = [
        booking('b1'),
        booking('b2', status: 'completed'),
        booking('b3', status: 'noshow'),
        booking('b4', status: 'cancelled'),
        booking('b5', status: 'waitlist'),
      ];
      expect(BookingRules.countOpenBookings(list, 'p1'), 1);
    });

    test('지난 회차의 confirmed도 센다 — 곧 완료·노쇼로 차감될 청구권이다', () {
      // 서버는 날짜 필터 없이 ListBookingsByMember 전체를 센다. 여기서 "다가오는
      // 예약만" 세면 앱만 예산을 넉넉히 보고 서버가 거부한다.
      final list = [booking('b1', day: 1), booking('b2', day: 30)];
      expect(BookingRules.countOpenBookings(list, 'p1'), 2);
    });

    test('예약이 없으면 0 — 예산은 잔여 그대로', () {
      expect(BookingRules.countOpenBookings(const [], 'p1'), 0);
    });
  });

  // ── HIGH: 담당 코치 휴무일 ────────────────────────────────────────────────
  // 서버는 슬롯이 비어 있어도 담당 코치 휴무일이면 400 "담당 코치의 휴무일이에요"
  // (v1.4에서 recurring 선행 생성뿐 아니라 일반 예약까지 확장). 앱은 offdays를 아예
  // 파싱하지 않아 휴무일 슬롯이 정상 "예약 가능"으로 보였다.
  group('담당 코치 휴무일(TrainerOffday) — 서버 "담당 코치의 휴무일이에요"', () {
    const slot = Slot(slotKey: slotKey, capacity: 3, teams: []); // 2026-08-14

    test('슬롯 날짜가 휴무일이면 슬롯이 비어 있어도 예약 불가', () {
      expect(evaluate(slot, pass(offdays: {'2026-08-14'})), isA<TrainerOffday>());
    });

    test('경계 — 전날/다음날 휴무는 이 슬롯에 영향 없다', () {
      expect(evaluate(slot, pass(offdays: {'2026-08-13'})), isA<Bookable>());
      expect(evaluate(slot, pass(offdays: {'2026-08-15'})), isA<Bookable>());
      // 여러 날 중 하루만 걸려도 그날은 막힌다.
      expect(
        evaluate(slot, pass(offdays: {'2026-08-13', '2026-08-14', '2026-08-15'})),
        isA<TrainerOffday>(),
      );
    });

    test('휴무일이 비어 있으면(미해석·구버전 서버) 평소대로 열린다', () {
      // 스태프 조회 실패는 빈 집합으로 떨어진다 — 모르는 것 때문에 예약을 막지
      // 않는다(staffMapReader의 best-effort 규약). 실제 휴무면 서버가 거부한다.
      expect(evaluate(slot, pass()), isA<Bookable>());
    });

    test('제로패딩 없는 값은 매칭되지 않는다 — 계약 포맷("YYYY-MM-DD")만 인정', () {
      // 서버도 `start.Format("2006-01-02")` 결과와 문자열 비교하므로 같은 판정이다.
      // 여기서 느슨하게 맞추면 앱만 막고 서버는 통과하는 반대 방향 불일치가 생긴다.
      expect(evaluate(slot, pass(offdays: {'2026-8-14'})), isA<Bookable>());
    });

    test('만석·코치 수업중보다 먼저 판정한다 — 휴무면 슬롯 사정은 의미가 없다', () {
      const fullSlot = Slot(
        slotKey: slotKey,
        capacity: 3,
        teams: [
          SlotTeam(bookingId: 'b1', trainerId: 't2', memberId: 'm1', kind: 'pt'),
          SlotTeam(bookingId: 'b2', trainerId: 't3', memberId: 'm2', kind: 'pt'),
          SlotTeam(bookingId: 'b3', trainerId: 't4', memberId: 'm3', kind: 'pt'),
        ],
      );
      expect(evaluate(fullSlot, pass(offdays: {'2026-08-14'})), isA<TrainerOffday>());
    });
  });

  // ── 패스 상태 ─────────────────────────────────────────────────────────────
  // 서버는 예약도 홀딩도 PassStatusActive만 통과시킨다. 앱은 scheduled까지 "쓸 수
  // 있음"으로 봤는데, 백엔드가 scheduled를 한 번도 쓰지 않아 드러나지 않던 잠재
  // 결함이었다. refunded는 지금도 실제로 발생하고(환불 플로우) 유효기간이 남아 있을
  // 수 있어, 그대로 두면 "잔여 0"과 똑같은 형태로 살아 있는 버튼이 뜬다.
  group('패스 상태(PassNotUsable) — 서버는 active만 받는다', () {
    const slot = Slot(slotKey: slotKey, capacity: 3, teams: []);

    test('환불된 패스는 유효기간이 남아 있어도 예약 불가', () {
      final state = evaluate(slot, pass(status: 'refunded', validUntil: DateTime(2030, 12, 31)));
      expect(state, isA<PassNotUsable>());
      expect((state as PassNotUsable).status, 'refunded');
    });

    test('expired는 막는다 — 만료된 회원권으로는 어떤 슬롯도 잡을 수 없다', () {
      expect(evaluate(slot, pass(status: 'expired')), isA<PassNotUsable>());
    });

    test('scheduled는 통과한다 — 시작 전 회원권의 선예약(서버도 받는다)', () {
      // 서버 `domain.Pass.BookableStatus()`가 scheduled를 통과시킨다(P25).
      // 슬롯이 valid_from보다 앞서면 그건 NotYetValid가 따로 잡는다.
      expect(evaluate(slot, pass(status: 'scheduled')), isA<Bookable>());
    });

    test('active·scheduled만 통과한다 — 모르는 값도 열어주지 않는다', () {
      expect(evaluate(slot, pass()), isA<Bookable>());
      expect(evaluate(slot, pass(status: 'weird_new_status')), isA<PassNotUsable>());
    });
  });

  group('판정 우선순위 — 서버 거부 순서와 같아야 한다', () {
    const slot = Slot(slotKey: slotKey, capacity: 3, teams: []);

    test('status 검사가 잔여보다 먼저(서버: status → remaining)', () {
      expect(evaluate(slot, pass(status: 'refunded', remaining: 0)), isA<PassNotUsable>());
    });

    test('잔여가 유효기간·홀딩·휴무보다 먼저', () {
      final state = evaluate(
        slot,
        pass(
          remaining: 0,
          validUntil: DateTime(2026, 8, 10), // 기간도 지났고
          holds: [PassHold(from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31))], // 홀딩 중이고
          offdays: {'2026-08-14'}, // 휴무일이기도 하다
        ),
      );
      expect(state, isA<NoRemainingSessions>());
    });

    test('홀딩이 휴무보다 먼저(서버: hold → offday)', () {
      final state = evaluate(
        slot,
        pass(
          holds: [PassHold(from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31))],
          offdays: {'2026-08-14'},
        ),
      );
      expect(state, isA<PassOnHoldForSlot>());
    });
  });

  group('BookingRules.mergeWithOpenHours (빈 시간대 합성 — P04 예약 여정 단절 해소)', () {
    final date = DateTime(2026, 8, 14);

    List<String> keys({
      required int openHour,
      required int closeHour,
      List<Slot> serverSlots = const [],
    }) =>
        BookingRules.mergeWithOpenHours(
          date: date,
          serverSlots: serverSlots,
          capacity: 3,
          openHour: openHour,
          closeHour: closeHour,
        ).map((s) => s.slotKey).toList();

    test('합성이 서버 슬롯을 덮어쓰지 않는다 — 같은 slot_key는 서버 우선, 빈 시간대만 채움', () {
      // 서버 슬롯: 10시(팀 1·용량 2 — 정책 기본과 다른 값), 08시(운영시간 밖 수기 등록).
      const server10 = Slot(
        slotKey: '20260814-10',
        capacity: 2,
        teams: [SlotTeam(bookingId: 'b1', trainerId: 't1', memberId: 'me', kind: 'pt')],
      );
      const server08 = Slot(slotKey: '20260814-08', capacity: 3, teams: []);

      final merged = BookingRules.mergeWithOpenHours(
        date: date,
        serverSlots: const [server10, server08],
        capacity: 3,
        openHour: 9,
        closeHour: 21,
      );

      // 09~21시 13칸 + 운영시간 밖 서버 슬롯(08시) 1칸 = 14칸, 시간순 정렬.
      expect(merged.length, 14);
      expect(merged.map((s) => s.slotKey).toList(),
          List.of(merged.map((s) => s.slotKey))..sort());
      expect(merged.first.slotKey, '20260814-08'); // 운영시간 밖 서버 슬롯 보존

      // 서버 우선 — 실제 예약(teams)·서버 용량(2)이 합성 빈 슬롯으로 대체되지 않는다.
      final at10 = merged.singleWhere((s) => s.slotKey == '20260814-10');
      expect(at10, same(server10));
      expect(at10.capacity, 2);
      expect(at10.teams, hasLength(1));

      // 서버에 없던 시간대는 빈 슬롯(정책 용량·teams=[])으로 합성된다.
      final at9 = merged.singleWhere((s) => s.slotKey == '20260814-09');
      expect(at9.capacity, 3);
      expect(at9.teams, isEmpty);
      final at21 = merged.singleWhere((s) => s.slotKey == '20260814-21');
      expect(at21.teams, isEmpty);
    });

    // ── 운영시간은 센터 정책값이다(하드코딩 9·21 제거) ──────────────────────────
    // open_hour/close_hour는 **슬롯 시작 시각, 양끝 포함**이다. 이 경계에서 하나만
    // 틀리면 센터의 영업 한 시간이 사라지거나(마지막 칸 증발) 없는 한 시간이 생긴다
    // (서버가 거부할 예약 버튼). 그래서 개수뿐 아니라 **첫/마지막 slot_key를 직접**
    // 단언한다 — 개수만 보면 구간 전체가 한 칸씩 밀려도 통과한다.
    group('운영시간 경계 — closeHour는 마지막 슬롯의 "시작" 시각(양끝 포함)', () {
      test('9..21 = 13칸, 첫 09시 · 마지막 21시', () {
        final k = keys(openHour: 9, closeHour: 21);
        expect(k, hasLength(13));
        expect(k.first, '20260814-09');
        expect(k.last, '20260814-21'); // 21시 "시작" 수업이 있다 — h < close면 사라진다
        expect(k.contains('20260814-22'), isFalse); // h <= close+1이면 없는 영업이 생긴다
        expect(k.contains('20260814-08'), isFalse);
      });

      test('06시 개장 · 23시 마지막 수업(9..21로는 표현 불가능했던 센터) = 18칸', () {
        final k = keys(openHour: 6, closeHour: 23);
        expect(k, hasLength(18));
        expect(k.first, '20260814-06');
        expect(k.last, '20260814-23');
        // 종전 하드코딩이면 06~08시와 22~23시가 통째로 없었다.
        expect(k, containsAll(['20260814-06', '20260814-08', '20260814-22', '20260814-23']));
      });

      test('10..11 = 2칸뿐 — 좁은 구간도 그대로', () {
        final k = keys(openHour: 10, closeHour: 11);
        expect(k, ['20260814-10', '20260814-11']);
      });

      test('open == close = 1칸(하루 한 타임만 여는 센터)', () {
        expect(keys(openHour: 14, closeHour: 14), ['20260814-14']);
      });

      test('00..23 = 24시간 — 자정 슬롯도 제로패딩돼 문자열 정렬이 곧 시간순', () {
        final k = keys(openHour: 0, closeHour: 23);
        expect(k, hasLength(24));
        expect(k.first, '20260814-00');
        expect(k.last, '20260814-23');
        expect(k, List.of(k)..sort());
      });

      test('운영시간이 바뀌어도 운영시간 밖 서버 슬롯은 계속 살아남는다', () {
        // 대표가 개장을 10시로 늦춰도 이미 09시에 잡힌 예약이 화면에서 사라지면 안 된다.
        const server09 = Slot(
          slotKey: '20260814-09',
          capacity: 3,
          teams: [SlotTeam(bookingId: 'b1', trainerId: 't1', memberId: 'me', kind: 'pt')],
        );
        final k = keys(openHour: 10, closeHour: 11, serverSlots: const [server09]);
        expect(k, ['20260814-09', '20260814-10', '20260814-11']);
      });
    });
  });

  group('v1.5 슬롯 최소노출 — 타인 팀 member_id="" 오판 방지', () {
    test('타인 팀 member_id가 빈 문자열이어도 내 예약으로 오판하지 않는다', () {
      // member 응답: 타인 팀의 member_id·booking_id는 ""(최소노출), 본인 팀만 원문.
      const slot = Slot(
        slotKey: slotKey,
        capacity: 3,
        teams: [SlotTeam(bookingId: '', trainerId: 't2', memberId: '', kind: 'pt')],
      );
      final state = evaluate(slot, pass());
      // "" != 'me' → AlreadyBookedByMe 아님. 점유율은 teams 길이 기준이라 잔여 2/3.
      expect(state, isA<Bookable>());
      expect((state as Bookable).remaining, 2);
    });

    test('빈 myMemberId(비로그인 방어)는 ""팀과 매칭돼 가짜 확정이 되지 않는다', () {
      const slot = Slot(
        slotKey: slotKey,
        capacity: 3,
        teams: [SlotTeam(bookingId: '', trainerId: 't2', memberId: '', kind: 'pt')],
      );
      expect(evaluate(slot, pass(), myMemberId: ''), isNot(isA<AlreadyBookedByMe>()));
    });
  });

  // 컷오프는 "취소 가능 여부"가 아니라 "무차감 여부"다 — 서버는 취소를 항상 허용하고
  // (CancelBooking: "막으면 노쇼로 위장할 유인만 커짐") 컷오프 경과엔 원장 차감만
  // 붙인다. 그래서 이 판정으로 취소 버튼을 감추면 안 되고, 확인 문구만 갈린다.
  group('BookingRules.isFreeCancel (정책 컷오프 — policy.cancel_cutoff_hours 파라미터)', () {
    test('24시간 이상 남으면 무차감 취소', () {
      final startAt = DateTime(2026, 8, 14, 20);
      final at = DateTime(2026, 8, 13, 19, 59); // 24h + 1min 전
      expect(BookingRules.isFreeCancel(startAt: startAt, now: at, cutoffHours: 24), isTrue);
    });

    test('정확히 24시간이면 무차감(경계 포함)', () {
      final startAt = DateTime(2026, 8, 14, 20);
      final at = DateTime(2026, 8, 13, 20); // 정확히 24h 전
      expect(BookingRules.isFreeCancel(startAt: startAt, now: at, cutoffHours: 24), isTrue);
    });

    test('24시간 미만 남으면 차감 대상(그래도 취소 자체는 가능하다)', () {
      final startAt = DateTime(2026, 8, 14, 20);
      final at = DateTime(2026, 8, 13, 21); // 23h 전
      expect(BookingRules.isFreeCancel(startAt: startAt, now: at, cutoffHours: 24), isFalse);
    });

    test('정책이 12시간이면 23시간 전은 물론 13시간 전도 무차감, 11시간 전은 차감', () {
      final startAt = DateTime(2026, 8, 14, 20);
      expect(
        BookingRules.isFreeCancel(startAt: startAt, now: DateTime(2026, 8, 14, 7), cutoffHours: 12),
        isTrue, // 13h 전
      );
      expect(
        BookingRules.isFreeCancel(startAt: startAt, now: DateTime(2026, 8, 14, 9), cutoffHours: 12),
        isFalse, // 11h 전
      );
    });
  });
}
