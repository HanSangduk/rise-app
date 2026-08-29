/// 법정 고지 문서의 공개 주소(P26).
///
/// Firebase Hosting의 `admin/dist/legal/*`로 배포된다. 정적 파일이라 SPA 폴백(`**` →
/// `/index.html`)보다 **먼저** 매칭되므로 확장자까지 쓴 이 주소가 정식 주소다 —
/// 확장자를 떼면 어드민 SPA로 떨어진다.
///
/// 앱에 문구를 복사해 두지 않고 링크로 보내는 이유: 개인정보처리방침은 변경 시 고지
/// 의무가 있고(개인정보보호법 제30조②), 앱에 박아 두면 스토어 심사를 다시 통과해야
/// 갱신된다. 웹에 두면 대표가 고친 즉시 모두가 같은 문서를 본다.
///
/// 호스트를 dart-define으로 뺀 이유는 스테이징·자체 도메인 전환 때문이다. 기본값은
/// 배포된 Firebase Hosting.
abstract final class LegalLinks {
  static const _host = String.fromEnvironment(
    'LEGAL_BASE_URL',
    defaultValue: 'https://rize-218c1.web.app/legal',
  );

  static const terms = '$_host/terms.html';
  static const privacy = '$_host/privacy.html';
  static const sensitiveConsent = '$_host/sensitive-consent.html';
  static const accountDeletion = '$_host/account-deletion.html';
}
