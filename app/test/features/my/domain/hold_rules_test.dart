import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/my/domain/hold_rules.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

// 일시정지 상한을 앱이 **사전에** 판정하지 않던 결함의 고정 테스트.
//
// 종전: `maxHoldsPerPass`/`maxHoldTotalDays`는 앱 전역에서 표시 문자열로만 쓰였고
// (`CenterPolicy.holdLimitLabel`), 신청 전 검증 코드가 0건이었다. 이미 2회를 쓴
// 회원이 날짜까지 다 채워 제출한 뒤에야 서버 400을 받았다 — 같은 앱의 다른 자리
// (PassOnHoldForSlot·NotYetValid·퇴사 코치·잔여 0)는 전부 사전 차단이 원칙인데
// 여기만 비일관이었다.
//
// 골든값의 출처는 문서가 아니라 **서버 코드**다:
//  · `backend/internal/domain/pass.go` `ValidateNewHold` — `len(existing)+1 > maxCount`,
//    `Σdays + nextDays > maxTotalDays`, 두 상한 모두 `> 0`일 때만 적용(0 이하 = 무제한).
//  · 같은 파일 `ValidateHoldWindow` — 과거 시작·유효기간 밖 시작·기존 구간 겹침 금지.
//  · 같은 파일 `HoldDurationDays` — 양끝 포함(09-01~09-10 = 10일).
//  · `backend/internal/api/service.go` `HoldPass` — active 패스만, 그리고 위 두 검증의 호출 순서.
void main() {
  // 판정 기준일 — 서버 `today()`(KST 고정)에 대응. 테스트는 시계를 읽지 않는다.
  final today = DateTime(2026, 9, 1);

  PassDetail pass({
    String status = 'active',
    List<PassHold> holds = const [],
    DateTime? validFrom,
    DateTime? validUntil,
  }) {
    return PassDetail(
      id: 'p1',
      product: 'PT 20회',
      trainerId: 't1',
      status: status,
      remaining: 12,
      totalSessions: 20,
      paidAmount: 1200000,
      validFrom: validFrom ?? DateTime(2026, 1, 1),
      validUntil: validUntil ?? DateTime(2026, 12, 31),
      holds: holds,
    );
  }

  PassHold hold(int fromDay, int toDay, {int month = 9}) =>
      PassHold(from: DateTime(2026, month, fromDay), to: DateTime(2026, month, toDay));

  HoldRequestState evaluate({
    PassDetail? target,
    required DateTime from,
    required DateTime to,
    int maxHoldsPerPass = 2,
    int maxHoldTotalDays = 30,
  }) {
    return HoldRules.evaluate(
      pass: target ?? pass(),
      from: from,
      to: to,
      today: today,
      maxHoldsPerPass: maxHoldsPerPass,
      maxHoldTotalDays: maxHoldTotalDays,
    );
  }

  group('HoldDurationDays 미러 — 양끝 포함', () {
    test('09-01~09-10 = 10일 (서버 주석의 골든값)', () {
      expect(HoldRules.durationDays(DateTime(2026, 9, 1), DateTime(2026, 9, 10)), 10);
    });

    test('같은 날 하루짜리도 1일 — 0일이 아니다', () {
      expect(HoldRules.durationDays(DateTime(2026, 9, 1), DateTime(2026, 9, 1)), 1);
    });

    test('월·연 경계를 넘어도 달력 일수 그대로', () {
      expect(HoldRules.durationDays(DateTime(2026, 12, 30), DateTime(2027, 1, 2)), 4);
    });

    test('기존 구간 합 — 역전된(깨진) 구간은 서버처럼 건너뛴다', () {
      final holds = [
        hold(1, 3), // 3일
        PassHold(from: DateTime(2026, 9, 20), to: DateTime(2026, 9, 10)), // 역전 — 무시
        hold(15, 16), // 2일
      ];
      expect(HoldRules.usedDays(holds), 5);
    });
  });

  group('패스 상태 — 서버 HoldPass는 active만 받는다', () {
    test('active면 통과', () {
      expect(
        evaluate(from: DateTime(2026, 9, 2), to: DateTime(2026, 9, 5)),
        isA<HoldAllowed>(),
      );
    });

    test('scheduled(시작 예정)는 거부 — 종전 후보 필터가 이걸 올려 놨었다', () {
      final state = evaluate(
        target: pass(status: 'scheduled', validFrom: DateTime(2026, 10, 1)),
        from: DateTime(2026, 10, 2),
        to: DateTime(2026, 10, 5),
      );
      expect(state, isA<HoldPassNotActive>());
      expect((state as HoldRejected).message, contains('10/1부터 시작하는 회원권'));
    });

    test('refunded는 거부 — 유효기간이 남아 있어도(RefundPass는 status만 바꾼다)', () {
      final state = evaluate(
        target: pass(status: 'refunded', validUntil: DateTime(2027, 6, 30)),
        from: DateTime(2026, 9, 2),
        to: DateTime(2026, 9, 5),
      );
      expect(state, isA<HoldPassNotActive>());
      expect((state as HoldRejected).message, contains('환불된 회원권'));
    });

    test('expired도 거부', () {
      expect(
        evaluate(target: pass(status: 'expired'), from: DateTime(2026, 9, 2), to: DateTime(2026, 9, 5)),
        isA<HoldPassNotActive>(),
      );
    });

    test('미지의 status는 라벨을 지어내지 않고 공통 문구로', () {
      final state = evaluate(
        target: pass(status: 'suspended_v2'),
        from: DateTime(2026, 9, 2),
        to: DateTime(2026, 9, 5),
      );
      expect((state as HoldRejected).message, '이용 중인 회원권만 일시정지할 수 있어요');
      expect(state.message, isNot(contains('suspended_v2')));
    });

    test('candidates()는 active만 남기고, 비면 **빈 목록**이다(원본 폴백 금지)', () {
      final all = [pass(status: 'refunded'), pass(status: 'scheduled'), pass(status: 'expired')];
      expect(HoldRules.candidates(all), isEmpty);
      expect(HoldRules.candidates([...all, pass()]), hasLength(1));
    });
  });

  group('ValidateHoldWindow 미러 — 구간 검증', () {
    test('종료일이 시작일보다 앞서면 거부', () {
      final state = evaluate(from: DateTime(2026, 9, 5), to: DateTime(2026, 9, 2));
      expect(state, isA<HoldRangeReversed>());
    });

    test('오늘 시작은 통과 — 경계는 열려 있다(`From < today`만 거부)', () {
      expect(evaluate(from: today, to: DateTime(2026, 9, 3)), isA<HoldAllowed>());
    });

    test('어제 시작은 거부 — 지난 날을 정지해 유효기간을 공짜로 늘리는 경로', () {
      final state = evaluate(from: DateTime(2026, 8, 31), to: DateTime(2026, 9, 3));
      expect(state, isA<HoldStartsInPast>());
      expect((state as HoldRejected).message, contains('9/1'));
    });

    test('유효기간 마지막 날 시작은 통과, 하루 넘기면 거부', () {
      final p = pass(validUntil: DateTime(2026, 9, 30));
      expect(
        evaluate(target: p, from: DateTime(2026, 9, 30), to: DateTime(2026, 10, 3)),
        isA<HoldAllowed>(),
      );
      final state = evaluate(target: p, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 3));
      expect(state, isA<HoldStartsAfterValidUntil>());
      expect((state as HoldRejected).message, contains('9/30까지'));
    });

    test('기존 구간과 하루라도 겹치면 거부(양끝 포함)', () {
      final p = pass(holds: [hold(10, 20)]);
      // 끝점만 스치는 경우도 서버는 겹침으로 본다(`next.From <= h.To`).
      final touching = evaluate(target: p, from: DateTime(2026, 9, 20), to: DateTime(2026, 9, 25));
      expect(touching, isA<HoldOverlapsExisting>());
      expect((touching as HoldRejected).message, contains('9/10~9/20'));
    });

    test('바로 다음 날부터는 겹치지 않아 통과', () {
      final p = pass(holds: [hold(10, 20)]);
      expect(
        evaluate(target: p, from: DateTime(2026, 9, 21), to: DateTime(2026, 9, 25)),
        isA<HoldAllowed>(),
      );
    });
  });

  group('ValidateNewHold 미러 — 횟수 상한', () {
    test('과거 홀딩 0건이면 언제나 횟수 통과', () {
      expect(
        evaluate(from: DateTime(2026, 9, 2), to: DateTime(2026, 9, 3), maxHoldsPerPass: 2),
        isA<HoldAllowed>(),
      );
    });

    test('상한 직전(2회 중 1회 사용) — 통과', () {
      final p = pass(holds: [hold(1, 3, month: 3)]);
      expect(
        evaluate(target: p, from: DateTime(2026, 9, 2), to: DateTime(2026, 9, 3), maxHoldsPerPass: 2),
        isA<HoldAllowed>(),
      );
    });

    test('상한 도달(2회 중 2회 사용) — 거부, 문구에 정책 실값과 사용 횟수가 함께 나온다', () {
      final p = pass(holds: [hold(1, 3, month: 3), hold(1, 3, month: 5)]);
      final state = evaluate(
        target: p,
        from: DateTime(2026, 9, 2),
        to: DateTime(2026, 9, 3),
        maxHoldsPerPass: 2,
      );
      expect(state, isA<HoldCountExceeded>());
      expect((state as HoldCountExceeded).used, 2);
      expect(state.maxCount, 2);
      expect(state.message, contains('최대 2회'));
      expect(state.message, contains('이미 2회를 썼어요'));
      // 다음 행동을 준다 — 스태프는 서버에서 상한을 건너뛸 수 있다(HoldPass의 member 분기).
      expect(state.message, contains('센터에 문의'));
    });

    test('조기 종료된 홀딩도 1회로 센다 — 재개 다이얼로그가 말하는 값과 같아야 한다', () {
      // 10일 예정 중 2일 만에 재개하면 holds에 짧아진 구간이 그대로 남는다.
      final p = pass(holds: [hold(1, 2, month: 3), hold(1, 1, month: 5)]);
      expect(
        evaluate(target: p, from: DateTime(2026, 9, 2), to: DateTime(2026, 9, 3), maxHoldsPerPass: 2),
        isA<HoldCountExceeded>(),
      );
    });

    test('횟수 무제한(-1)이면 몇 번을 썼든 통과 — 없는 상한을 만들지 않는다', () {
      final p = pass(holds: [hold(1, 2, month: 3), hold(1, 2, month: 4), hold(1, 2, month: 5)]);
      expect(
        evaluate(
          target: p,
          from: DateTime(2026, 9, 2),
          to: DateTime(2026, 9, 3),
          maxHoldsPerPass: -1,
        ),
        isA<HoldAllowed>(),
      );
      expect(HoldRules.countUnlimited(-1), isTrue);
      // 서버 가드가 `maxCount > 0`이라 0도 무제한이다 — 앱이 서버보다 엄해지면 안 된다.
      expect(HoldRules.countUnlimited(0), isTrue);
      expect(HoldRules.countUnlimited(1), isFalse);
    });
  });

  group('ValidateNewHold 미러 — 총 일수 상한', () {
    test('경계 정확히 채우면 통과 (기존 20일 + 이번 10일 = 30일)', () {
      final p = pass(holds: [PassHold(from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 20))]);
      final state = evaluate(
        target: p,
        from: DateTime(2026, 9, 2),
        to: DateTime(2026, 9, 11), // 10일
        maxHoldsPerPass: -1,
        maxHoldTotalDays: 30,
      );
      expect(state, isA<HoldAllowed>());
      expect((state as HoldAllowed).days, 10);
    });

    test('경계 +1일이면 거부 (20일 + 11일 = 31일 > 30)', () {
      final p = pass(holds: [PassHold(from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 20))]);
      final state = evaluate(
        target: p,
        from: DateTime(2026, 9, 2),
        to: DateTime(2026, 9, 12), // 11일
        maxHoldsPerPass: -1,
        maxHoldTotalDays: 30,
      );
      expect(state, isA<HoldTotalDaysExceeded>());
      final rejected = state as HoldTotalDaysExceeded;
      expect(rejected.usedDays, 20);
      expect(rejected.requestedDays, 11);
      expect(rejected.remainingDays, 10);
      expect(rejected.message, contains('총 30일'));
      expect(rejected.message, contains('10일 이내로 줄여주세요'));
    });

    test('과거 홀딩 0건 — 이번 신청만으로 상한을 넘길 수도 있다', () {
      final state = evaluate(
        from: DateTime(2026, 9, 2),
        to: DateTime(2026, 10, 2), // 31일
        maxHoldsPerPass: -1,
        maxHoldTotalDays: 30,
      );
      expect(state, isA<HoldTotalDaysExceeded>());
      expect((state as HoldTotalDaysExceeded).usedDays, 0);
      expect(state.remainingDays, 30);
    });

    test('남은 날이 0이면 "줄여주세요" 대신 문의를 안내한다 — 줄일 수 있는 여지가 없다', () {
      final p = pass(holds: [PassHold(from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 30))]);
      final state = evaluate(
        target: p,
        from: DateTime(2026, 9, 2),
        to: DateTime(2026, 9, 2),
        maxHoldsPerPass: -1,
        maxHoldTotalDays: 30,
      ) as HoldTotalDaysExceeded;
      expect(state.remainingDays, 0);
      expect(state.message, contains('남은 날이 없어요'));
      expect(state.message, contains('센터에 문의'));
      expect(state.message, isNot(contains('이내로 줄여주세요')));
    });

    test('일수 무제한(-1)이면 아무리 길어도 통과', () {
      expect(
        evaluate(
          from: DateTime(2026, 9, 2),
          to: DateTime(2027, 8, 1),
          maxHoldsPerPass: -1,
          maxHoldTotalDays: -1,
        ),
        isA<HoldAllowed>(),
      );
      expect(HoldRules.daysUnlimited(-1), isTrue);
      expect(HoldRules.daysUnlimited(0), isTrue);
      expect(HoldRules.daysUnlimited(1), isFalse);
    });
  });

  group('판정 순서 — 서버 HoldPass의 거부 순서 그대로', () {
    test('상태가 먼저다 — 환불 패스가 상한도 넘겼으면 "환불"이라고 말한다', () {
      final p = pass(
        status: 'refunded',
        holds: [hold(1, 3, month: 3), hold(1, 3, month: 5)],
      );
      expect(
        evaluate(target: p, from: DateTime(2026, 9, 2), to: DateTime(2026, 9, 3)),
        isA<HoldPassNotActive>(),
      );
    });

    test('구간 검증이 상한보다 먼저 — 상한도 넘긴 과거 시작이면 "지난 날짜"라고 말한다', () {
      final p = pass(holds: [hold(1, 3, month: 3), hold(1, 3, month: 5)]);
      expect(
        evaluate(target: p, from: DateTime(2026, 8, 20), to: DateTime(2026, 8, 25)),
        isA<HoldStartsInPast>(),
      );
    });

    test('횟수가 일수보다 먼저 — 둘 다 넘겼으면 "횟수"라고 말한다', () {
      final p = pass(holds: [
        PassHold(from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 20)),
        PassHold(from: DateTime(2026, 5, 1), to: DateTime(2026, 5, 9)),
      ]);
      expect(
        evaluate(
          target: p,
          from: DateTime(2026, 9, 2),
          to: DateTime(2026, 9, 12),
          maxHoldsPerPass: 2,
          maxHoldTotalDays: 30,
        ),
        isA<HoldCountExceeded>(),
      );
    });
  });

  group('잔여 요약(HoldAllowance) — 표시와 판정이 같은 값을 쓴다', () {
    HoldAllowance allowance(PassDetail p, {int maxCount = 2, int maxDays = 30}) =>
        HoldRules.allowance(pass: p, maxHoldsPerPass: maxCount, maxHoldTotalDays: maxDays);

    test('둘 다 상한 있으면 잔여가 헤드라인, 상한·사용량이 근거 줄', () {
      final p = pass(holds: [PassHold(from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 7))]);
      final a = allowance(p);
      expect(a.remainingDays, 23);
      expect(a.remainingCount, 1);
      expect(a.exhausted, isFalse);
      expect(a.headline, '남은 일시정지 23일 · 1회');
      expect(a.detail, '최대 2회/30일 중 1회 · 7일 사용');
    });

    test('"1회 남았다"는 표시와 판정이 갈리지 않는다 — 같은 입력으로 둘 다 확인', () {
      // 표시가 "1회 남았다"면 판정은 반드시 통과해야 하고,
      final oneUsed = pass(holds: [hold(1, 3, month: 3)]);
      expect(allowance(oneUsed).remainingCount, 1);
      expect(allowance(oneUsed).exhausted, isFalse);
      expect(
        evaluate(target: oneUsed, from: DateTime(2026, 9, 2), to: DateTime(2026, 9, 3)),
        isA<HoldAllowed>(),
      );
      // "남은 일시정지가 없어요"면 반드시 거부여야 한다.
      final twoUsed = pass(holds: [hold(1, 3, month: 3), hold(1, 3, month: 5)]);
      expect(allowance(twoUsed).exhausted, isTrue);
      expect(allowance(twoUsed).headline, '남은 일시정지가 없어요');
      expect(allowance(twoUsed).detail, contains('최대 2회를 모두 썼어요'));
      expect(
        evaluate(target: twoUsed, from: DateTime(2026, 9, 2), to: DateTime(2026, 9, 3)),
        isA<HoldCountExceeded>(),
      );
    });

    test('구속 조건(min) — 일수가 남아도 횟수가 0이면 잔여를 큰 숫자로 말하지 않는다', () {
      final p = pass(holds: [hold(1, 3, month: 3), hold(1, 3, month: 5)]);
      final a = allowance(p); // 일수 6/30 사용, 횟수 2/2 사용.
      expect(a.remainingDays, 24, reason: '일수 축만 보면 24일이 남아 있다');
      expect(a.remainingCount, 0);
      expect(a.exhausted, isTrue, reason: '하지만 횟수가 0이라 실효 잔여는 0이다');
      expect(a.headline, isNot(contains('24일')));
    });

    test('무제한(-1)이면 그 축의 숫자를 지어내지 않는다', () {
      final p = pass(holds: [hold(1, 3, month: 3)]);
      final noCount = allowance(p, maxCount: -1);
      expect(noCount.remainingCount, isNull);
      expect(noCount.headline, '남은 일시정지 27일');
      expect(noCount.detail, contains('횟수 제한 없음'));
      expect(noCount.headline + noCount.detail!, isNot(contains('-1')));

      final noDays = allowance(p, maxDays: -1);
      expect(noDays.remainingDays, isNull);
      expect(noDays.headline, '남은 일시정지 1회');
      expect(noDays.detail, contains('일수 제한 없음'));
      expect(noDays.headline + noDays.detail!, isNot(contains('-1')));

      final neither = allowance(p, maxCount: -1, maxDays: -1);
      expect(neither.exhausted, isFalse, reason: '무제한은 소진될 수 없다');
      expect(neither.headline, '지금까지 1회 · 3일 쉬었어요');
      expect(neither.detail, '횟수·일수 제한 없음');
    });

    test('이력 0건은 "사용 가능" 프레이밍 — 근거 줄 없이 성립한다', () {
      final a = allowance(pass());
      expect(a.headline, '일시정지 30일 · 2회 사용 가능');
      expect(a.detail, isNull);
    });

    test('상한을 이미 넘긴 데이터도 음수 없이 0으로 말한다', () {
      final p = pass(holds: [hold(1, 20, month: 3), hold(1, 20, month: 5)]);
      final a = allowance(p); // 40일 사용 > 30일 상한.
      expect(a.remainingDays, 0);
      expect(a.exhausted, isTrue);
      expect(a.headline, isNot(contains('-')));
    });
  });
}
