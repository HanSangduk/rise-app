// 전화 인증 "앱 검증 생략" 스위치의 판정(P77).
//
// 스위치(appVerificationDisabledForTesting)는 Auth 인스턴스에 남는다(프로세스 전역). 종전엔 디버그·심사 번호일 때
// **켜기만** 해서, 같은 실행에서 심사 번호 다음 다른 번호도 앱 검증 없이 나갔다(실기기 재현 — work_log/P77).
// 지금은 요청마다 이 판정값을 그대로 넣는다. Android는 그 값을 적용하고, iOS는 FlutterFire 플러그인이 true만
// 적용해 한 번 켜지면 앱을 다시 켤 때까지 남는다(auth_repository_impl.dart 주석).
//
// 이 시험이 지키는 것은 **판정식**이다(릴리스에서 심사 번호만 true, 다른 번호는 명시적 false). setSettings를
// 요청마다 부르는 **배선**은 FirebaseAuth.instance를 직접 써서 여기서 못 잰다 — 실기기 하네스 t4가 본다.
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/auth/data/auth_repository_impl.dart';
import 'package:rise_member/features/auth/domain/auth_config.dart';

void main() {
  test('릴리스: 심사 번호만 앱 검증을 건너뛰고, 다른 번호는 false다(스위치가 남지 않게 명시)', () {
    expect(skipAppVerificationFor(AuthConfig.reviewPhoneE164, debug: false), isTrue);
    expect(skipAppVerificationFor('+821055556666', debug: false), isFalse);
    expect(skipAppVerificationFor('+821012345678', debug: false), isFalse);
    // 심사 번호와 한 자리만 다른 번호 — 앞부분 일치로 판정하면 실번호가 우회 통로가 된다.
    expect(skipAppVerificationFor('+821000000001', debug: false), isFalse);
  });

  test('디버그: 모든 번호에서 건너뛴다(시뮬레이터·에뮬레이터엔 APNs·Play Integrity가 없다)', () {
    expect(skipAppVerificationFor('+821055556666', debug: true), isTrue);
    expect(skipAppVerificationFor(AuthConfig.reviewPhoneE164, debug: true), isTrue);
  });
}
