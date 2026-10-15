// OS가 앱에 넘긴 URL은 라우터로 들어오지 않는다 — 두 플랫폼의 Flutter 딥링크 스위치가 꺼져 있다(P75).
// 함께: iOS reCAPTCHA 복귀 스킴이 Firebase 앱 ID와 맞는다(P46 — 같은 복귀 경로의 다른 고장).
//
// 2026-10-14 실사용자 제보: iOS에서 전화번호를 넣자 화면 전체가 go_router 기본 에러 화면
// "Page Not Found — no routes for location: app-1-…://firebaseauth/link?deep_link_id=…"로 바뀌었다.
// APNs 사일런트 검증이 없으면 Firebase 전화 인증은 reCAPTCHA(SFSafariViewController)로 가고, 끝나면
// 그 URL로 앱에 돌아온다. FirebaseAuth가 씬 델리게이트 스위즐러로 URL을 **먼저** 소비한 뒤
// 원래 FlutterSceneDelegate에도 같은 URL이 가는데, 플러그인의 두 번째 `canHandleURL`은 이미 소비된
// 뒤라 NO → 엔진이 딥링크로 프레임워크에 넘겼다(FlutterDeepLinkingEnabled 미설정 = 켜짐, Flutter
// 3.27+). PhoneScreen이 내려가 codeSent 뒤 이동도 사라져, 인증번호는 발송됐는데 갈 곳이 없었다.
//
// 이 앱은 딥링크를 쓰지 않는다(app_router.dart). P64 D4는 **시작 라우트**만 막았고
// (`overridePlatformDefaultLocation`), 실행 중 들어오는 URL(iOS openURL · Android onNewIntent의
// data)은 열려 있었다. 둘 다 엔진의 같은 스위치가 지키므로 스위치를 끄고 여기서 고정한다.
// Firebase는 이 스위치와 무관하게 URL을 네이티브에서 먼저 받는다(스위즐러 인터셉터 → 플러그인
// → 그다음에야 딥링크 단계) — 끄는 것이 인증을 깨지 않는다는 실물 확인은
// integration_test/phone_auth_recaptcha_return_test.dart(실기기).
//
// **딥링크를 넣는 날**(예: 데스크 QR로 예약 열기): 스위치를 켜기 전에 라우터가
// `firebaseauth/link`(Firebase 인증 복귀 URL)를 무시하게 만들고, 셸 경로 세션 가드
// (shell_gate_test.dart)를 함께 손본 뒤 이 테스트를 바꾼다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 주석 안의 선언이 통과로 읽히지 않게 XML 주석을 걷어 낸다.
String _withoutXmlComments(String xml) => xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

/// [index] 위치의 dict 중첩 깊이 — 1이면 최상위 dict의 직속이다. 엔진은 `objectForInfoDictionaryKey`로
/// **최상위 키만** 읽으므로 하위 dict(예: UIApplicationSceneManifest) 안의 같은 이름은 무효다
/// (P75 반박 검토 N1: 그렇게 옮겨도 plutil은 OK, 정규식만 보던 시험은 초록이었다).
int _dictDepthAt(String xml, int index) {
  final before = xml.substring(0, index);
  return RegExp(r'<dict\s*>').allMatches(before).length -
      RegExp(r'</dict\s*>').allMatches(before).length;
}

void main() {
  test('iOS — Info.plist가 FlutterDeepLinkingEnabled를 false로 둔다', () {
    final plist = _withoutXmlComments(File('ios/Runner/Info.plist').readAsStringSync());
    final keys = RegExp(r'<key>\s*FlutterDeepLinkingEnabled\s*</key>').allMatches(plist).length;
    expect(keys, 1,
        reason: 'FlutterDeepLinkingEnabled 키가 정확히 하나 있어야 한다(없으면 엔진 기본값이 켜짐) — '
            '찾은 개수: $keys');
    final entry = RegExp(r'<key>\s*FlutterDeepLinkingEnabled\s*</key>\s*<false\s*/>').firstMatch(plist);
    expect(entry, isNotNull,
        reason: 'FlutterDeepLinkingEnabled가 false가 아니다 — reCAPTCHA 복귀 URL이 go_router로 샌다');
    expect(_dictDepthAt(plist, entry!.start), 1,
        reason: 'FlutterDeepLinkingEnabled가 최상위 dict 밖(하위 dict 안)에 있다 — 엔진은 최상위만 읽어 기본값(켜짐)이 된다');
  });

  // 같은 복귀 경로의 다른 고장(P46): 스킴이 없으면 reCAPTCHA를 열려다 PhoneAuthProvider가 크래시한다.
  // 이 프로젝트엔 REVERSED_CLIENT_ID가 없어 SDK는 **인코딩 앱 ID 스킴**을 쓰고, 앱 ID가 바뀌면(P46의
  // 패키지명 변경처럼) 스킴도 바뀐다 — 손으로 맞추던 세 곳을 대조한다.
  test('iOS — reCAPTCHA 복귀 스킴이 Firebase iOS 앱 ID에서 유도한 값이다', () {
    String plistString(String xml, String key) {
      final m = RegExp('<key>$key</key>\\s*<string>([^<]+)</string>').firstMatch(xml);
      expect(m, isNotNull, reason: '$key를 못 찾았다');
      return m!.group(1)!;
    }

    final service = File('ios/Runner/GoogleService-Info.plist').readAsStringSync();
    expect(service.contains('<key>REVERSED_CLIENT_ID</key>'), isFalse,
        reason: 'REVERSED_CLIENT_ID가 생기면 SDK가 그 스킴을 먼저 쓴다 — 이 가드의 전제를 다시 볼 것');
    final appId = plistString(service, 'GOOGLE_APP_ID');

    final options = File('lib/firebase_options.dart').readAsStringSync();
    final iosBlock = RegExp(r'FirebaseOptions ios = FirebaseOptions\(([\s\S]*?)\);').firstMatch(options);
    expect(iosBlock, isNotNull, reason: 'firebase_options.dart의 ios 옵션을 못 찾았다');
    expect(RegExp(r"appId: '([^']+)'").firstMatch(iosBlock!.group(1)!)?.group(1), appId,
        reason: 'firebase_options.dart와 GoogleService-Info.plist의 iOS 앱 ID가 갈렸다');

    final plist = _withoutXmlComments(File('ios/Runner/Info.plist').readAsStringSync());
    final schemes = RegExp(r'<key>CFBundleURLSchemes</key>\s*<array>([\s\S]*?)</array>')
        .allMatches(plist)
        .expand((m) => RegExp(r'<string>([^<]+)</string>').allMatches(m.group(1)!))
        .map((m) => m.group(1)!.trim())
        .toList();
    final scheme = 'app-${appId.replaceAll(':', '-')}';
    expect(schemes, contains(scheme),
        reason: 'Info.plist CFBundleURLSchemes에 $scheme 가 없다(있는 것: $schemes) — '
            'reCAPTCHA 폴백에서 크래시(P46)');
  });

  test('Android — MainActivity가 flutter_deeplinking_enabled를 false로 둔다', () {
    final manifest =
        _withoutXmlComments(File('android/app/src/main/AndroidManifest.xml').readAsStringSync());
    // 엔진은 **액티비티** 메타데이터만 읽는다(FlutterActivity.getMetaData) — application 단에 두면 무효.
    final activity =
        RegExp(r'<activity\b[^>]*android:name="\.MainActivity"[\s\S]*?</activity>').firstMatch(manifest);
    expect(activity, isNotNull, reason: 'MainActivity 선언을 못 찾았다 — 이 가드를 갱신할 것');

    final metas = RegExp(r'<meta-data\b[^>]*>')
        .allMatches(activity!.group(0)!)
        .map((m) => m.group(0)!)
        .where((tag) => tag.contains('android:name="flutter_deeplinking_enabled"'))
        .toList();
    expect(metas, hasLength(1),
        reason: 'MainActivity 안에 flutter_deeplinking_enabled 메타데이터가 정확히 하나 있어야 한다 '
            '(없으면 엔진 기본값이 켜짐 — 명시적 인텐트의 data가 onNewIntent로 라우터에 들어온다)');
    expect(metas.single, contains('android:value="false"'),
        reason: 'flutter_deeplinking_enabled가 false가 아니다: ${metas.single}');
    // 병합 마커가 붙으면 선언이 산출물에서 사라진다(tools:node="remove" 등 — P75 반박 검토 N2).
    expect(metas.single, isNot(contains('tools:')),
        reason: 'flutter_deeplinking_enabled에 매니페스트 병합 마커가 붙었다 — 산출물에서 빠질 수 있다: ${metas.single}');
  });
}
