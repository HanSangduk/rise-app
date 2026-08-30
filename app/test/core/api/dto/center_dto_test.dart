import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/center_dto.dart';
import 'package:rise_member/core/policy/center_policy.dart';

// GET /v1/center policy — 운영시간(open_hour/close_hour) 파싱 규약.
//
// 이 두 필드는 이웃 정책 필드와 달리 **nullable이고 @Default가 없다**: "서버가 안
// 줬다"를 null로 그대로 올려, 기본값(9·21)과 유효성 판정을 경계 한 곳
// ([CenterPolicy.resolveHours])이 전담하게 하려는 것이다. DTO가 기본값을 알면 같은
// 숫자가 CenterPolicy.fallback과 두 군데에 살면서 따로 움직일 수 있다.
void main() {
  CenterPolicyDto policy(Map<String, dynamic> json) => CenterPolicyDto.fromJson(json);

  group('CenterPolicyDto — open_hour/close_hour 파싱', () {
    test('둘 다 존재 → 그대로 파싱(슬롯 시작 시각, 양끝 포함)', () {
      final p = policy({'open_hour': 6, 'close_hour': 23});

      expect(p.openHour, 6);
      expect(p.closeHour, 23);
      expect(CenterPolicy.resolveHours(p.openHour, p.closeHour), (6, 23));
    });

    test('키 부재(구버전 서버) → null — 경계가 9·21로 해석한다', () {
      final p = policy({'slot_capacity': 3, 'cancel_cutoff_hours': 48});

      expect(p.openHour, isNull);
      expect(p.closeHour, isNull);
      // 나머지 정책은 정상 파싱돼야 한다(운영시간 부재가 다른 값을 건드리면 안 된다).
      expect(p.cancelCutoffHours, 48);
      expect(CenterPolicy.resolveHours(p.openHour, p.closeHour), (9, 21));
    });

    test('명시적 null → null(계약은 null 금지지만 방어)', () {
      final p = policy({'open_hour': null, 'close_hour': null});

      expect(p.openHour, isNull);
      expect(p.closeHour, isNull);
    });

    test('한쪽만 존재 → 온 쪽만 값, 나머지는 null', () {
      final p = policy({'open_hour': 7});

      expect(p.openHour, 7);
      expect(p.closeHour, isNull);
      expect(CenterPolicy.resolveHours(p.openHour, p.closeHour), (7, 21));
    });

    test('정수가 아닌 값 → null(= 안 준 것과 동일), **나머지 정책은 살아남는다**', () {
      // as num 캐스트를 그대로 뒀다면 여기서 파싱 전체가 던져지고, 정책 provider의
      // catch가 취소 컷오프·홀딩 상한까지 통째로 폴백시킨다 — 운영시간 한 필드의
      // 오타가 다른 정책들의 실값을 지우게 된다.
      final p = policy({
        'open_hour': '9',
        'close_hour': true,
        'cancel_cutoff_hours': 48,
        'max_holds_per_pass': -1,
      });

      expect(p.openHour, isNull);
      expect(p.closeHour, isNull);
      expect(p.cancelCutoffHours, 48);
      expect(p.maxHoldsPerPass, -1);
      expect(CenterPolicy.resolveHours(p.openHour, p.closeHour), (9, 21));
    });

    test('실수로 오면 정수로 절삭(JSON 숫자에 소수점이 붙어 오는 서버 방어)', () {
      final p = policy({'open_hour': 6.0, 'close_hour': 23.0});

      expect(p.openHour, 6);
      expect(p.closeHour, 23);
    });

    test('범위 밖 정수는 DTO를 통과하고 경계가 걸러낸다(파싱과 정책 판정의 분업)', () {
      final p = policy({'open_hour': 22, 'close_hour': 6});

      expect(p.openHour, 22);
      expect(p.closeHour, 6);
      expect(CenterPolicy.resolveHours(p.openHour, p.closeHour), (9, 21));
    });

    test('이웃 정책 필드의 @Default는 그대로 — 운영시간 추가가 기존 파싱을 바꾸지 않았다', () {
      final p = policy(const <String, dynamic>{});

      expect(p.slotCapacity, 3);
      expect(p.cancelCutoffHours, 24);
      expect(p.graceOnce, isTrue);
      expect(p.penaltyRate, 0.10);
      expect(p.expiringDays, 7);
      expect(p.maxHoldsPerPass, 2);
      expect(p.maxHoldTotalDays, 30);
    });
  });

  group('CenterResponseDto', () {
    test('운영시간이 포함된 전체 응답(v1.4 + 운영시간)', () {
      final dto = CenterResponseDto.fromJson({
        'center_id': 'c1',
        'policy': {
          'slot_capacity': 3,
          'cancel_cutoff_hours': 24,
          'grace_once': true,
          'penalty_rate': 0.10,
          'expiring_days': 7,
          'max_holds_per_pass': 2,
          'max_hold_total_days': 30,
          'open_hour': 6,
          'close_hour': 23,
        },
      });

      expect(dto.centerId, 'c1');
      expect(dto.policy.openHour, 6);
      expect(dto.policy.closeHour, 23);
    });
  });
}
