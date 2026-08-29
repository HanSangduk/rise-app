import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/auth/domain/join_request_store.dart';

// P2R — 승인 대기 상태를 로컬에 영속시킬 때, 저장/복원 자체보다 **번호 대조**가
// 핵심이다. 대기는 기기가 아니라 번호의 상태라서, 대조를 빠뜨리면 다른 번호로
// 로그인한 사용자에게 남의 "승인 대기 중" 카드가 뜬다.
void main() {
  final requestedAt = DateTime(2026, 8, 22, 14, 30, 5);
  final record = JoinRequestRecord(phone: '+821012345678', requestedAt: requestedAt);

  group('JoinRequestRecord 직렬화', () {
    test('encode → decode 왕복에서 번호와 시각이 보존된다', () {
      final restored = JoinRequestRecord.decode(record.encode());
      expect(restored, isNotNull);
      expect(restored!.phone, '+821012345678');
      expect(restored.requestedAt, requestedAt);
    });

    test('null · 빈 문자열 · 깨진 JSON은 조용히 null (로그인을 막지 않는다)', () {
      expect(JoinRequestRecord.decode(null), isNull);
      expect(JoinRequestRecord.decode(''), isNull);
      expect(JoinRequestRecord.decode('{not json'), isNull);
      expect(JoinRequestRecord.decode('"문자열만"'), isNull);
    });

    test('필수 필드가 빠지거나 시각이 파싱 불가면 null', () {
      expect(JoinRequestRecord.decode('{"phone":"+821012345678"}'), isNull);
      expect(JoinRequestRecord.decode('{"requested_at":"2026-08-22T14:30:05.000"}'), isNull);
      expect(
        JoinRequestRecord.decode('{"phone":"","requested_at":"2026-08-22T14:30:05.000"}'),
        isNull,
      );
      expect(
        JoinRequestRecord.decode('{"phone":"+821012345678","requested_at":"어제"}'),
        isNull,
      );
    });
  });

  group('JoinRequestRecord.matches — 다른 번호로 로그인했을 때의 오복원 방지', () {
    test('표기가 달라도 같은 번호면 true (정규화 후 비교)', () {
      expect(record.matches('+821012345678'), isTrue);
      expect(record.matches('010-1234-5678'), isTrue);
      expect(record.matches('01012345678'), isTrue);
      expect(record.matches(' 010 1234 5678 '), isTrue);
    });

    test('다른 번호면 false — 남의 승인 대기 카드가 뜨지 않는다', () {
      expect(record.matches('010-9999-8888'), isFalse);
      expect(record.matches('+821099998888'), isFalse);
    });
  });
}
