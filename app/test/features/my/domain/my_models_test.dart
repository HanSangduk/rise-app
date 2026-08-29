import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

// P2R — 홀딩 가시화(일시정지 중 배지/재개 버튼)의 구간 판정 로직.
void main() {
  group('PassHold.contains — from~to 양끝 포함, 날짜 단위', () {
    final hold = PassHold(from: DateTime(2026, 8, 10), to: DateTime(2026, 8, 20));

    test('구간 안 날짜는 true', () {
      expect(hold.contains(DateTime(2026, 8, 15)), isTrue);
    });

    test('양끝(from/to 당일)도 true — 시각이 있어도 날짜만 비교', () {
      expect(hold.contains(DateTime(2026, 8, 10, 23, 59)), isTrue);
      expect(hold.contains(DateTime(2026, 8, 20, 0, 1)), isTrue);
    });

    test('구간 밖은 false', () {
      expect(hold.contains(DateTime(2026, 8, 9)), isFalse);
      expect(hold.contains(DateTime(2026, 8, 21)), isFalse);
    });
  });

  group('LedgerReason.label', () {
    test('noshow_waived → "노쇼 · 최초 1회 유예"', () {
      expect(LedgerReason.fromWire('noshow_waived').label, '노쇼 · 최초 1회 유예');
    });

    // 서버 `ledger.go`의 9종을 그대로 옮긴 표. 값이 바뀌면 여기가 먼저 깨진다.
    const wireToLabel = {
      'issue': '발급',
      'complete': '수업 완료',
      'noshow': '노쇼',
      'noshow_waived': '노쇼 · 최초 1회 유예',
      'revert': '취소 복구',
      'refund': '환불',
      'hold': '일시정지',
      'resume': '재개',
      'transfer': '담당 코치 이관',
    };

    test('서버 9종이 전부 한국어 라벨로 해석된다', () {
      for (final entry in wireToLabel.entries) {
        final reason = LedgerReason.fromWire(entry.key);

        expect(reason.isKnown, isTrue, reason: '${entry.key}를 미지 값으로 떨어뜨렸다');
        expect(reason.label, entry.value);
        expect(reason.wire, entry.key);
      }
      // 표와 구현이 서로를 빠뜨리지 않는지 — 새 reason을 enum에만 추가하고 라벨을
      // 잊는 반대 방향도 잡는다.
      expect(LedgerReason.known.map((r) => r.wire).toSet(), wireToLabel.keys.toSet());
    });

    test('transfer는 "양도"가 아니라 "담당 코치 이관" — 서버 의미가 트레이너 이관이다', () {
      // backend/internal/domain/ledger.go: `ReasonTransfer = "transfer" // 트레이너 이관(P18)`.
      // 생성 지점은 코치 인수인계(service_staff.go, delta 0 감사 기록)라 회원권을
      // 남에게 넘긴 것이 아니다 — "양도"는 원장을 정반대로 읽게 만들었다.
      final transfer = LedgerReason.fromWire('transfer');

      expect(transfer.label, '담당 코치 이관');
      expect(transfer.label, isNot(contains('양도')));
      expect(transfer, same(LedgerReason.transfer));
    });
  });

  group('LedgerReason.fromWire — 미지 값은 원문 보존(라벨을 지어내지 않는다)', () {
    // 예전 폴백은 `_ => LedgerReason.complete`였다. 서버가 10번째 reason을 앱
    // 릴리스보다 먼저 내보내면 금전·회차 기록이 "수업 완료"라는 **그럴듯하게 틀린**
    // 라벨을 달았다. ContractItem.statusLabel의 `_ => status`와 같은 규약으로 고쳤다.
    test('모르는 reason은 complete로 접히지 않는다', () {
      final unknown = LedgerReason.fromWire('gift_bonus');

      expect(unknown.isKnown, isFalse);
      expect(unknown, isNot(LedgerReason.complete));
      expect(unknown.label, isNot('수업 완료'));
    });

    test('모르는 reason의 라벨은 wire 원문 그대로', () {
      expect(LedgerReason.fromWire('gift_bonus').label, 'gift_bonus');
      expect(LedgerReason.fromWire('gift_bonus').wire, 'gift_bonus');
    });

    test('빈 wire는 빈 라벨 대신 "기타" — 사유 칸이 통째로 사라지지 않게', () {
      expect(LedgerReason.fromWire('').label, '기타');
    });

    test('같은 wire의 미지 값끼리는 동등(리스트 비교·set 사용에 안전)', () {
      expect(LedgerReason.fromWire('gift_bonus'), LedgerReason.fromWire('gift_bonus'));
      expect(
        LedgerReason.fromWire('gift_bonus').hashCode,
        LedgerReason.fromWire('gift_bonus').hashCode,
      );
      expect(LedgerReason.fromWire('gift_bonus'), isNot(LedgerReason.fromWire('other')));
    });

    test('대소문자·공백이 다르면 다른 값 — 조용히 흡수하지 않는다', () {
      expect(LedgerReason.fromWire('Transfer').isKnown, isFalse);
      expect(LedgerReason.fromWire('Transfer').label, 'Transfer');
      expect(LedgerReason.fromWire(' transfer').isKnown, isFalse);
    });
  });
}
