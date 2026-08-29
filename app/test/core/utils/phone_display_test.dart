// P09 실기기 회귀: 안내 문구의 전화번호는 입력란 힌트와 같은 표기여야 한다.
// 실기기에서 "01012345678로 보냈어요"가 그대로 노출되는 걸 발견했다(힌트는 010-1234-5678).
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/utils/phone_format.dart';

void main() {
  test('표시용 포맷 — 휴대폰·지역번호', () {
    expect(formatKoreanPhoneForDisplay('01012345678'), '010-1234-5678');
    expect(formatKoreanPhoneForDisplay('010-1234-5678'), '010-1234-5678'); // 멱등
    expect(formatKoreanPhoneForDisplay('01112345678'), '011-1234-5678');
    expect(formatKoreanPhoneForDisplay('0212345678'), '02-1234-5678');
    expect(formatKoreanPhoneForDisplay('0311234567'), '031-123-4567');
  });

  test('모르는 형식은 원본 유지 — 억지로 끊지 않는다', () {
    for (final s in ['', '1234', '+821012345678', '15881234', 'abc']) {
      expect(formatKoreanPhoneForDisplay(s), s, reason: s);
    }
  });

  test('정규화와 표시는 목적이 다르다 — 같은 입력에서 서로 다른 결과', () {
    expect(normalizeKoreanPhone('010-1234-5678'), '+821012345678');
    expect(formatKoreanPhoneForDisplay('010-1234-5678'), '010-1234-5678');
  });
}
