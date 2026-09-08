// 스토어 심사 계정 규약(P46).
//
// 이 값들이 어긋나면 **심사자가 로그인하지 못하고 리젝이 온다** — 그 왕복은 며칠이다.
// 앱 코드·Firebase 콘솔·스토어 심사 노트 세 곳이 같은 번호를 말해야 하는데, 코드가
// 진실의 원천이고 나머지 둘은 사람이 옮겨 적는다. 그래서 형식만이라도 여기서 고정한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/utils/phone_format.dart';
import 'package:rise_member/features/auth/domain/auth_config.dart';

void main() {
  test('심사 번호의 표기형과 E.164형이 같은 번호다 — 안내와 코드가 갈리지 않는다', () {
    // 심사 노트엔 국내 표기(010-0000-0000)를 적고, 앱은 E.164로 비교한다.
    // 정규화를 통과시켰을 때 같은 값이 나와야 그 둘이 같은 번호다.
    expect(
      normalizeKoreanPhone(AuthConfig.reviewPhoneDisplay),
      AuthConfig.reviewPhoneE164,
    );
  });

  test('심사 번호는 실제 가입자가 없는 대역이다 — 남의 번호로 SMS가 가지 않는다', () {
    expect(AuthConfig.reviewPhoneE164, startsWith('+8210'));
    // 010-0000-xxxx는 국내 이동통신에 할당되지 않는다(가공 번호).
    expect(AuthConfig.reviewPhoneDisplay, startsWith('010-0000-'));
  });

  test('고정 코드는 6자리 숫자 — Firebase 테스트 번호 형식', () {
    expect(AuthConfig.reviewCode, matches(RegExp(r'^\d{6}$')));
  });

  test('사용자가 어떻게 입력해도 같은 번호로 정규화된다 — 심사자가 하이픈을 빼도 통한다', () {
    for (final typed in [
      '010-0000-0000',
      '01000000000',
      '+82 10-0000-0000',
      '+821000000000',
      ' 010 0000 0000 ',
    ]) {
      expect(
        normalizeKoreanPhone(typed),
        AuthConfig.reviewPhoneE164,
        reason: '"$typed" 입력이 심사 번호로 정규화되어야 앱 무결성 우회 분기를 탄다',
      );
    }
  });
}
