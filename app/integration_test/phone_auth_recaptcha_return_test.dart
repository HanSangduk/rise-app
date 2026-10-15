// iOS 전화 인증 reCAPTCHA 복귀 점검(P75) — **iOS 실기기 · 프로필 모드 전용.**
//
// 지키는 것: APNs 사일런트 검증이 없으면(이 앱의 iOS 기본 — 푸시 엔타이틀먼트 없음) Firebase가
// reCAPTCHA(SFSafariViewController)를 띄우고, 끝나면 `app-1-…://firebaseauth/link?deep_link_id=…`
// 로 앱에 돌아온다. 그 URL이 Flutter 딥링크로 go_router까지 새면 화면 전체가 go_router 기본
// 에러 화면("Page Not Found")으로 바뀌고, 그 사이 PhoneScreen이 내려가 codeSent 뒤 이동도
// 사라진다(phone_screen.dart `if (!mounted) return;`) — 인증번호는 발송됐는데 갈 곳이 없다.
// 2026-10-14 실사용자 제보(work_log/P75).
//
// 디버그·시뮬레이터로 못 재는 이유: 디버그 빌드는 앱 검증을 끈다(auth_repository_impl.dart의
// `kDebugMode` 분기) → reCAPTCHA 자체가 안 뜬다. 시뮬레이터는 프로필/릴리스를 돌리지 못한다.
//
// 번호는 반드시 **Firebase 콘솔에 등록된 테스트 번호**를 넘긴다(실 SMS·과금 없음). 미등록 번호면
// 그 번호로 실제 SMS가 나간다 — 그래서 기본값을 두지 않는다. 심사 번호(010-0000-0000)는 앱이
// 앱 검증을 끄는 번호라 reCAPTCHA가 안 떠 이 점검에 쓸 수 없다.
// 인증번호 화면 도착까지만 본다 — 코드 입력·로그인은 하지 않는다(프로덕션 매칭 API에 흔적 0).
//
// 결과는 앱 임시 폴더에도 남긴다(tmp/p75_result.json · tmp/p75_after.png) — Xcode 자동화 없이
// 돌릴 때 회수용. 실행(app/에서, 기기 잠금 해제 — reCAPTCHA가 그림 문제를 내면 기기에서 푼다):
//   A) flutter drive --profile -d <UDID> --driver=test_driver/integration_test.dart \
//        --target=integration_test/phone_auth_recaptcha_return_test.dart --dart-define=P75_PHONE=<번호>
//      (iOS 17+ 실기기는 Flutter가 Xcode 자동화로 띄운다 — Mac 화면이 잠겨 있으면 멈춘다)
//   B) 헤드리스: flutter build ios --profile --target=<위 파일> --dart-define=P75_PHONE=<번호>
//      → xcrun devicectl device install app --device <ID> build/ios/iphoneos/Runner.app
//      → xcrun devicectl device process launch --device <ID> --terminate-existing com.han.rise
//      → 3~4분 뒤 xcrun devicectl device copy from --device <ID> --domain-type appDataContainer \
//          --domain-identifier com.han.rise --source tmp/p75_result.json --destination <경로>
// 끝나면 Generated.xcconfig 복원(P60 — 진입점이 integration_test로 남는다):
//   flutter build ios --config-only --release
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rise_member/app.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
import 'package:rise_member/features/auth/presentation/code_screen.dart';
import 'package:rise_member/features/auth/presentation/phone_screen.dart';
import 'package:rise_member/firebase_options.dart';

const _phone = String.fromEnvironment('P75_PHONE');

/// reCAPTCHA를 사람이 풀어야 하는 경우까지 기다리는 상한.
const _deadline = Duration(minutes: 3);

/// 라우터 누수가 보인 뒤 codeSent가 따라오는지 지켜보는 시간 — 오면 Firebase는 reCAPTCHA를
/// 끝냈는데(URL을 먼저 소비) 같은 URL이 라우터에도 갔다는 뜻이다(이중 배달 확증).
const _afterLeakWatch = Duration(seconds: 45);

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reCAPTCHA 복귀 URL이 라우터로 새지 않고 인증번호 화면에 도착한다', (tester) async {
    expect(_phone, isNotEmpty,
        reason: '--dart-define=P75_PHONE=<콘솔 등록 테스트 번호> 필수(미등록 번호는 실 SMS가 나간다)');

    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await tester.pumpWidget(const ProviderScope(child: RiseMemberApp()));
    await _pumpFor(tester, const Duration(seconds: 5));
    expect(find.byType(PhoneScreen), findsOneWidget, reason: '세션 없는 첫 실행은 로그인 화면이어야 한다');

    final container = ProviderScope.containerOf(tester.element(find.byType(RiseMemberApp)));
    bool codeSent() => container.read(authViewModelProvider).verificationId != null;

    // 통합 테스트 바인딩은 가짜 키보드를 등록하지 않는다(registerTestTextInput => false) — 그대로면
    // enterText가 입력란에 닿지 않고 빈 번호로 "다시 확인해주세요"가 떠 **측정이 무효**가 된다(첫 실측).
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    debugPrint('[P75] harness v3: test text input registered'); // 산출물 신선도 표식(strings로 확인)
    final phoneField = find.byType(TextField).first;
    await tester.enterText(phoneField, _phone);
    await tester.pump(const Duration(milliseconds: 300));
    final digits = RegExp(r'\D');
    expect(tester.widget<TextField>(phoneField).controller!.text.replaceAll(digits, ''),
        _phone.replaceAll(digits, ''),
        reason: '번호가 입력란에 안 들어갔다 — 이 측정은 무효(reCAPTCHA까지 가지 않는다)');
    await tester.tap(find.text('인증번호 받기'));
    final tappedAt = DateTime.now();
    int sinceTap() => DateTime.now().difference(tappedAt).inSeconds;
    debugPrint('[P75] 인증번호 받기 탭');

    // go_router 기본 에러 화면의 본문(GoException 문자열). 제목 "Page Not Found"는 앱 문구와
    // 겹칠 일이 없지만, 예외 문자열이 원인(라우터 누수)을 더 정확히 가리킨다.
    final routerLeak = find.textContaining('no routes for location');
    final codeScreen = find.byType(CodeScreen);
    int? leakAt;
    int? codeSentAt;
    final end = tappedAt.add(_deadline);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (codeSentAt == null && codeSent()) codeSentAt = sinceTap();
      if (routerLeak.evaluate().isNotEmpty) {
        leakAt = sinceTap();
        break;
      }
      if (codeScreen.evaluate().isNotEmpty) break;
    }
    // 인증번호 화면이 트리에 붙는 첫 프레임엔 전환 애니메이션 전이라 이전 화면이 찍힌다(실측) —
    // 사용자가 보게 될 화면을 찍으려고 전환이 끝날 때까지 돌린다.
    if (codeScreen.evaluate().isNotEmpty) await _pumpFor(tester, const Duration(seconds: 2));
    if (leakAt != null) {
      final watchEnd = DateTime.now().add(_afterLeakWatch);
      while (codeSentAt == null && DateTime.now().isBefore(watchEnd)) {
        await tester.pump(const Duration(milliseconds: 250));
        if (codeSent()) codeSentAt = sinceTap();
      }
    }

    // 라우터가 지금 서 있는 곳 — 토큰이 든 쿼리는 남기지 않는다.
    final location = GoRouter.of(tester.element(find.byType(Navigator).first))
        .routerDelegate
        .currentConfiguration
        .uri;
    final result = <String, Object?>{
      'at': DateTime.now().toIso8601String(),
      'routerLeak': routerLeak.evaluate().isNotEmpty,
      'leakAtSec': leakAt,
      'codeScreen': codeScreen.evaluate().isNotEmpty,
      'codeSentAtSec': codeSentAt,
      'routerLocation': '${location.scheme}://${location.host}${location.path}',
      'authError': container.read(authViewModelProvider).error?.message,
      'waitedSec': sinceTap(),
    };
    final json = jsonEncode(result);
    debugPrint('[P75-RESULT] $json');
    try {
      File('${Directory.systemTemp.path}/p75_result.json').writeAsStringSync(json);
      final png = await binding.takeScreenshot('p75_after_recaptcha');
      File('${Directory.systemTemp.path}/p75_after.png').writeAsBytesSync(png);
    } catch (e) {
      debugPrint('[P75] 결과 파일·스크린샷 저장 실패(판정과 무관): $e');
    }

    expect(routerLeak, findsNothing,
        reason: 'reCAPTCHA 복귀 URL이 Flutter 딥링크로 go_router까지 새어 "Page Not Found"가 떴다 '
            '— Info.plist FlutterDeepLinkingEnabled가 false인지 확인(P75). $json');
    expect(codeScreen, findsOneWidget,
        reason: '${_deadline.inMinutes}분 안에 인증번호 화면에 못 왔다 — reCAPTCHA를 못 풀었거나 '
            '인증 요청이 실패했다. $json');
  });
}
