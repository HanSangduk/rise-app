// 전화 인증 reCAPTCHA 폴백에서 회원이 마주칠 오류 문구(P75).
//
// APNs 사일런트 검증이 없어(푸시 엔타이틀먼트 미설정) iOS 실번호 인증은 전부 reCAPTCHA 사파리 시트를
// 거친다(Android는 Play Integrity가 실패하면 Custom Tab). P75 전에는 시트가 끝나는 순간 라우터 누수
// ("Page Not Found")에 갇혀 이 문구들에 닿을 일이 없었다 — 고친 뒤엔 시트를 닫거나 망이 끊기면 아래 코드가
// 화면에 그대로 뜬다. 매핑이 없으면 기본 갈래가 "인증에 실패했어요 (web-context-cancelled)"처럼 영문 코드를 보인다.
//
// 코드 문자열의 출처: iOS `AuthErrors.swift`(ERROR_WEB_CONTEXT_CANCELLED …) · Android firebase-auth
// (ERROR_WEB_CONTEXT_CANCELED …)를 FlutterFire가 ERROR_ 제거 → '_'를 '-'로 → 소문자로 바꾼다.
// **철자가 플랫폼마다 다르다**(cancelled / canceled).
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/features/auth/data/auth_repository_impl.dart';

void main() {
  Failure map(String code) => mapPhoneAuthError(FirebaseAuthException(code: code));

  test('reCAPTCHA 시트를 닫으면 다시 시도하라는 한국어 안내 — 두 플랫폼 철자 모두', () {
    for (final code in const ['web-context-cancelled', 'web-context-canceled']) {
      final f = map(code);
      expect(f.message, isNot(contains('web-context')), reason: code);
      // 일반 "앱 인증 실패"가 아니라 **회원이 창을 닫았다**고 알려야 한다 — 철자 하나가 빠지면 그 코드는
      // web-* 계열 규칙에 먹혀 "앱 인증에 실패했어요. 잠시 후 다시…"가 된다(변이 MP1이 그걸로 살아남았다).
      expect(f.message, contains('창이 닫혔'), reason: code);
      expect(f.message, contains('다시'), reason: code);
      // 번호 화면("인증번호 받기")과 코드 화면("인증번호 재전송") 둘 다에서 뜬다 — 버튼 이름을 말하지 않는다.
      expect(f.message, isNot(anyOf(contains('받기'), contains('재전송'))), reason: code);
    }
  });

  test('reCAPTCHA 시트 안에서 망이 끊기면 연결 문제로 안내한다', () {
    expect(map('web-network-request-failed'), isA<NetworkFailure>());
  });

  test('reCAPTCHA·웹 확인 갈래(web-*·*recaptcha*)와 앱 검증 코드는 화면에 원시 코드를 보이지 않는다', () {
    // 목록은 견본이다 — 매핑은 web-*·*recaptcha* **계열 전체**를 받는다(새 코드가 생겨도 영문이 새지 않게).
    for (final code in const [
      // iOS(AuthErrors.swift)
      'web-context-already-presented',
      'web-internal-error',
      'web-user-interaction-failure', // 콜백 URL이 firebaseError를 싣고 오면 대부분 이것(AuthErrorUtils.urlResponseError)
      'app-verification-failed',
      'app-not-verified',
      'missing-app-token',
      'missing-app-credential',
      'notification-not-forwarded',
      'invalid-client-id',
      'internal-error',
      'captcha-check-failed',
      'invalid-app-credential',
      // Android(firebase-auth 24.2.0)
      'web-storage-unsupported',
      'missing-recaptcha-token',
      'invalid-recaptcha-token',
      'recaptcha-not-enabled',
      'invalid-recaptcha-version',
      // 아직 없는 이름이라도 같은 계열이면
      'web-something-new',
    ]) {
      expect(map(code).message, isNot(contains(code)), reason: '$code가 화면에 그대로 나간다');
    }
  });

  test('계열 밖의 모르는 코드는 여전히 코드를 붙여 보인다 — 문의 때 원인 추적용(기존 동작)', () {
    expect(map('some-new-code').message, contains('some-new-code'));
  });
}
