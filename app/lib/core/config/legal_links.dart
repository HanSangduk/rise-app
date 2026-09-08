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

  /// 앱 **운영자**(개발자) 개인정보처리방침 — 앱 스토어에 등록된 방침이 이것이다(P66).
  ///
  /// 아래 [privacy]와 다른 문서다: 이 앱은 여러 센터가 함께 쓰므로 특정 센터 하나를
  /// 개인정보처리자로 선언한 문서를 앱 전체의 방침으로 걸 수 없다. 센터가 처리하는 기록의
  /// 고지는 [privacy]가, 앱·서버 운영자가 직접 처리하는 것은 이 문서가 맡는다.
  ///
  /// **센터 파라미터를 붙이지 않는다** — 운영자는 하나뿐이라 센터에 따라 달라지지 않는다.
  static const appPrivacy = '$_host/app-privacy.html';

  static const terms = '$_host/terms.html';
  static const privacy = '$_host/privacy.html';
  static const sensitiveConsent = '$_host/sensitive-consent.html';
  static const accountDeletion = '$_host/account-deletion.html';

  /// **어느 센터의 고지인가**를 URL에 싣는다(계약 v2.33).
  ///
  /// 여러 센터가 이 앱을 쓰므로 법정 문서가 인쇄하는 사업자 정보(개인정보처리자·삭제 요청
  /// 접수 창구)는 센터마다 다르다. 문서는 `?center=`를 그대로 서버에 넘겨 그 센터의 값을
  /// 받는다 — 파라미터가 없으면 서버가 기본 센터를 준다.
  ///
  /// [centerId]가 비면 **원래 주소 그대로**다: 로그인 전(대기실)처럼 센터를 모르는 자리에서
  /// 빈 파라미터를 붙이면 서버가 404를 주고 문서가 자리표시자만 남는다.
  static String forCenter(String url, String centerId) =>
      centerId.isEmpty ? url : '$url?center=${Uri.encodeQueryComponent(centerId)}';
}
