// iOS 전화 인증 reCAPTCHA 경로 점검(P75 · P77) — **iOS 실기기 · 프로필 모드 전용.**
//
// 지키는 것: APNs 사일런트 검증이 없으면(이 앱의 iOS 기본 — 푸시 엔타이틀먼트 없음) Firebase가
// reCAPTCHA(SFSafariViewController)를 띄우고, 끝나면 `app-1-…://firebaseauth/link?deep_link_id=…`
// 로 앱에 돌아온다. 그 URL이 Flutter 딥링크로 go_router까지 새면 화면 전체가 go_router 기본
// 에러 화면("Page Not Found")으로 바뀌고, 그 사이 PhoneScreen이 내려가 codeSent 뒤 이동도
// 사라진다(phone_screen.dart `if (!mounted) return;`) — 인증번호는 발송됐는데 갈 곳이 없다.
// 2026-10-14 실사용자 제보(work_log/P75). P77에서 같은 경로의 다른 입구를 더했다:
//   t1 첫 요청 → 인증번호 화면 · t2 "인증번호 재전송"(reCAPTCHA 재진입) · t3 돌아가 다시 요청
//   (정상 완료 뒤 시트가 다시 열리나) · t4 심사 번호 다음 테스트 번호(앱 검증 스위치가 남지 않나).
//
// 디버그·시뮬레이터로 못 재는 이유: 디버그 빌드는 앱 검증을 끈다(auth_repository_impl.dart의
// `kDebugMode` 분기) → reCAPTCHA 자체가 안 뜬다. 시뮬레이터는 프로필/릴리스를 돌리지 못한다.
//
// 번호는 반드시 **Firebase 콘솔에 등록된 테스트 번호**를 넘긴다(실 SMS·과금 없음). 미등록 번호면
// 그 번호로 실제 SMS가 나간다 — 그래서 기본값을 두지 않는다. 심사 번호(010-0000-0000)는 앱이
// 앱 검증을 끄는 번호라 t4에서만 쓴다(그래서 t4가 맨 끝 — 스위치가 남으면 뒤 시험을 오염시킨다).
// 인증번호 화면 도착까지만 본다 — 코드 입력·로그인은 하지 않는다(프로덕션 매칭 API에 흔적 0).
//
// 결과는 앱 임시 폴더에 남긴다(tmp/p75_<시험>.json·png, 끝나면 tmp/p75_done.json) — Xcode 자동화
// 없이 돌릴 때 회수용. **시나리오는 하나씩, 몇 분 간격으로**(`--dart-define=P77_ONLY=t1|t2|t3|t4`): 같은 기기에서
// 몇 분 안에 reCAPTCHA를 다시 요청하면 사파리 시트가 자동 통과하지 않고 머물고(P77 실측 — 30~50분 지속), 시트가
// 떠 있는 동안엔 Flutter 프레임이 멈춰 하네스도 멈춘다. 그래서 넷을 한 번에 돌리면 t2에서 멈춘다.
// 실행(app/에서, 기기 잠금 해제 — reCAPTCHA가 그림 문제를 내면 기기에서 푼다):
//   A) flutter drive --profile -d <UDID> --driver=test_driver/integration_test.dart \
//        --target=integration_test/phone_auth_recaptcha_return_test.dart --dart-define=P75_PHONE=<번호> \
//        --dart-define=P77_ONLY=t1
//      (iOS 17+ 실기기는 Flutter가 Xcode 자동화로 띄운다 — Mac 화면이 잠겨 있으면 멈춘다)
//   B) 헤드리스: flutter build ios --profile --target=<위 파일> --dart-define=P75_PHONE=<번호> --dart-define=P77_ONLY=t1
//      → xcrun devicectl device install app --device <ID> build/ios/Profile-iphoneos/Runner.app
//        (build/ios/iphoneos/Runner.app 사본은 서명이 깨져 설치가 안 된다 — 실측)
//      → xcrun devicectl device process launch --device <ID> --terminate-existing com.han.rise
//      → 1~2분 뒤(t2는 쿨다운 30초 포함 2~3분) xcrun devicectl device copy from --device <ID> --domain-type appDataContainer \
//          --domain-identifier com.han.rise --source tmp/p75_done.json --destination <경로>
// 끝나면 Generated.xcconfig 복원(P60 — 진입점이 integration_test로 남는다):
//   flutter build ios --config-only --release   (+ project.pbxproj는 빌드 전 사본으로 되돌린다)
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rise_member/app.dart';
import 'package:rise_member/features/auth/domain/auth_config.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
import 'package:rise_member/features/auth/presentation/code_screen.dart';
import 'package:rise_member/features/auth/presentation/phone_screen.dart';
import 'package:rise_member/firebase_options.dart';

const _phone = String.fromEnvironment('P75_PHONE');

/// 시나리오 하나만 돌리기 — 빌드 때 `--dart-define=P77_ONLY=t4`. (devicectl 실행 환경변수 `-e`는 Dart
/// Platform.environment에 닿지 않았다 — P77 실측.) 한 번에 넷을 돌리면 reCAPTCHA 요청이 몰려 사파리 시트가
/// 닫히지 않고 머무는데(그림 문제로 추정), 시트가 떠 있는 동안엔 Flutter 프레임이 멈춰 하네스도 멈춘다.
const _onlyDefine = String.fromEnvironment('P77_ONLY');
final String? _only = _onlyDefine.isNotEmpty ? _onlyDefine : Platform.environment['P77_ONLY'];
bool _skip(String id) => _only != null && _only != id;

/// reCAPTCHA를 사람이 풀어야 하는 경우까지 기다리는 상한.
const _deadline = Duration(minutes: 3);

/// 라우터 누수가 보인 뒤 codeSent가 따라오는지 지켜보는 시간 — 오면 Firebase는 reCAPTCHA를
/// 끝냈는데(URL을 먼저 소비) 같은 URL이 라우터에도 갔다는 뜻이다(이중 배달 확증).
const _afterLeakWatch = Duration(seconds: 45);

final _results = <String, Object?>{};

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

// go_router 기본 에러 화면의 본문(GoException 문자열) — 원인(라우터 누수)을 가리킨다.
final _routerLeak = find.textContaining('no routes for location');
final _codeScreen = find.byType(CodeScreen);
final _phoneScreen = find.byType(PhoneScreen);

/// 새 앱을 띄우고 로그인 화면을 확인한다. 통합 테스트 바인딩은 가짜 키보드를 등록하지 않으므로
/// (registerTestTextInput => false) 그대로면 enterText가 입력란에 닿지 않는다(P75 첫 실측 — 무효 측정).
Future<ProviderContainer> _startApp(WidgetTester tester) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  tester.testTextInput.register();
  addTearDown(tester.testTextInput.unregister);
  debugPrint('[P75] harness v7: test text input registered'); // 산출물 신선도 표식(strings로 확인)
  await tester.pumpWidget(const ProviderScope(child: RiseMemberApp()));
  await _pumpFor(tester, const Duration(seconds: 5));
  expect(_phoneScreen, findsOneWidget, reason: '세션 없는 첫 실행은 로그인 화면이어야 한다');
  return ProviderScope.containerOf(tester.element(find.byType(RiseMemberApp)));
}

/// 번호를 넣고(입력이 실제로 들어갔나 단언) "인증번호 받기"를 누른다.
Future<DateTime> _request(WidgetTester tester, String phone) async {
  final field = find.byType(TextField).first;
  await tester.enterText(field, phone);
  await tester.pump(const Duration(milliseconds: 300));
  final digits = RegExp(r'\D');
  expect(tester.widget<TextField>(field).controller!.text.replaceAll(digits, ''), phone.replaceAll(digits, ''),
      reason: '번호가 입력란에 안 들어갔다 — 이 측정은 무효(reCAPTCHA까지 가지 않는다)');
  await tester.tap(find.text('인증번호 받기'));
  debugPrint('[P75] 인증번호 받기 탭 ($phone)');
  return DateTime.now();
}

/// 인증번호 화면 도착 또는 라우터 누수까지 돈다. 도착하면 전환이 끝나도록 2초 더 돈다(첫 프레임엔
/// 이전 화면이 찍힌다 — 실측). 반환: 도착/누수 시각(탭 기준 초), 시간 초과면 null.
Future<({double? arrivedSec, double? leakSec})> _awaitCodeScreen(WidgetTester tester, DateTime from,
    {Duration within = _deadline}) async {
  final end = from.add(within);
  double since() => DateTime.now().difference(from).inMilliseconds / 1000;
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (_routerLeak.evaluate().isNotEmpty) return (arrivedSec: null, leakSec: since());
    if (_codeScreen.evaluate().isNotEmpty) {
      final t = since();
      await _pumpFor(tester, const Duration(seconds: 2));
      return (arrivedSec: t, leakSec: null);
    }
  }
  return (arrivedSec: null, leakSec: null);
}

Future<void> _record(
    IntegrationTestWidgetsFlutterBinding binding, WidgetTester tester, String id, Map<String, Object?> r) async {
  r['at'] = DateTime.now().toIso8601String();
  final location = GoRouter.of(tester.element(find.byType(Navigator).first)).routerDelegate.currentConfiguration.uri;
  r['routerLocation'] = '${location.scheme}://${location.host}${location.path}'; // 토큰 든 쿼리는 남기지 않는다
  _results[id] = r;
  final json = jsonEncode(r);
  debugPrint('[P75-RESULT] $id $json');
  try {
    File('${Directory.systemTemp.path}/p75_$id.json').writeAsStringSync(json);
    if (id == 't1') File('${Directory.systemTemp.path}/p75_result.json').writeAsStringSync(json); // P75 스크립트 호환
    final png = await binding.takeScreenshot('p75_$id');
    File('${Directory.systemTemp.path}/p75_$id.png').writeAsBytesSync(png);
  } catch (e) {
    debugPrint('[P75] 결과 파일·스크린샷 저장 실패(판정과 무관): $e');
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    expect(_phone, isNotEmpty,
        reason: '--dart-define=P75_PHONE=<콘솔 등록 테스트 번호> 필수(미등록 번호는 실 SMS가 나간다)');
    // 오타면 넷 다 건너뛰고 "All tests skipped"로 초록이 된다(P77 반박 검토) — 이름을 먼저 확인한다.
    expect(_only == null || const {'t1', 't2', 't3', 't4'}.contains(_only), isTrue,
        reason: 'P77_ONLY는 t1·t2·t3·t4 중 하나여야 한다: "$_only"');
  });

  // 시험 하나가 죽어도 끝 표식은 남긴다 — 헤드리스 스크립트가 이걸 기다린다.
  tearDownAll(() {
    try {
      File('${Directory.systemTemp.path}/p75_done.json')
          .writeAsStringSync(jsonEncode({'at': DateTime.now().toIso8601String(), 'results': _results}));
    } catch (_) {}
  });

  testWidgets('t1 reCAPTCHA 복귀 URL이 라우터로 새지 않고 인증번호 화면에 도착한다', skip: _skip('t1'), (tester) async {
    final container = await _startApp(tester);
    final tappedAt = await _request(tester, _phone);
    final o = await _awaitCodeScreen(tester, tappedAt);
    // codeSent 시각은 **누수 때만** 잰다(이중 배달 확증용). 도착한 경우엔 도착 자체가 codeSent 뒤라 arrivedSec이 신호다 —
    // 도착 뒤 2초 대기를 지나 재면 도착보다 늦은 값이 찍혀 순서가 뒤집혀 보였다(P77 반박 검토).
    double? codeSentAt;
    if (o.leakSec != null) {
      // 누수 뒤 codeSent가 오는지 — 오면 이중 배달 확증(P75).
      final watchEnd = DateTime.now().add(_afterLeakWatch);
      while (codeSentAt == null && DateTime.now().isBefore(watchEnd)) {
        await tester.pump(const Duration(milliseconds: 250));
        if (container.read(authViewModelProvider).verificationId != null) {
          codeSentAt = DateTime.now().difference(tappedAt).inMilliseconds / 1000;
        }
      }
    }
    await _record(binding, tester, 't1', {
      'routerLeak': o.leakSec != null,
      'leakAtSec': o.leakSec,
      'codeScreen': _codeScreen.evaluate().isNotEmpty,
      'arrivedSec': o.arrivedSec,
      'codeSentAtSec': codeSentAt,
      'authError': container.read(authViewModelProvider).error?.message,
    });
    expect(_routerLeak, findsNothing,
        reason: 'reCAPTCHA 복귀 URL이 Flutter 딥링크로 go_router까지 새어 "Page Not Found"가 떴다 — '
            'Info.plist FlutterDeepLinkingEnabled가 false인지 확인(P75)');
    expect(_codeScreen, findsOneWidget,
        reason: '${_deadline.inMinutes}분 안에 인증번호 화면에 못 왔다 — reCAPTCHA를 못 풀었거나 인증 요청이 실패했다');
  });

  testWidgets('t2 "인증번호 재전송"(reCAPTCHA 재진입)도 라우터로 새지 않고 코드 화면에 남는다', skip: _skip('t2'),
      (tester) async {
    final container = await _startApp(tester);
    final first = await _awaitCodeScreen(tester, await _request(tester, _phone));
    expect(first.arrivedSec, isNotNull, reason: '재전송 전제(첫 요청 → 코드 화면)가 깨졌다: $first');
    final firstId = container.read(authViewModelProvider).verificationId;
    // 재전송은 30초 쿨다운 뒤에 열린다(code_screen.dart _resendCooldownSeconds).
    await _pumpFor(tester, const Duration(seconds: 31));
    await tester.tap(find.text('인증번호 재전송'));
    final resentAt = DateTime.now();
    debugPrint('[P75] 인증번호 재전송 탭');
    final sent = find.text('인증번호를 다시 보냈어요');
    double? sentSec, leakSec;
    final end = resentAt.add(_deadline);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
      final t = DateTime.now().difference(resentAt).inMilliseconds / 1000;
      if (_routerLeak.evaluate().isNotEmpty) {
        leakSec = t;
        break;
      }
      if (sent.evaluate().isNotEmpty) {
        sentSec = t;
        break;
      }
    }
    final newId = container.read(authViewModelProvider).verificationId;
    await _record(binding, tester, 't2', {
      'routerLeak': leakSec != null,
      'leakAtSec': leakSec,
      'resentSnackSec': sentSec,
      'stillOnCodeScreen': _codeScreen.evaluate().isNotEmpty,
      'verificationIdChanged': newId != null && newId != firstId,
      'authError': container.read(authViewModelProvider).error?.message,
    });
    expect(_routerLeak, findsNothing, reason: '재전송의 reCAPTCHA 복귀 URL이 라우터로 샜다');
    expect(sentSec, isNotNull, reason: '재전송 완료 안내가 안 떴다');
    expect(_codeScreen, findsOneWidget, reason: '재전송 뒤 코드 화면을 벗어났다');
  });

  testWidgets('t3 코드 화면에서 돌아가 다시 요청해도 reCAPTCHA가 다시 열려 코드 화면에 도착한다', skip: _skip('t3'),
      (tester) async {
    await _startApp(tester);
    final first = await _awaitCodeScreen(tester, await _request(tester, _phone));
    expect(first.arrivedSec, isNotNull, reason: '전제(첫 요청 → 코드 화면)가 깨졌다: $first');
    // 화면 맨 위 ← (code_screen.dart _goBackToPhone → context.go('/login')).
    await tester.tap(find.byType(IconButton).first);
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(_phoneScreen, findsOneWidget, reason: '← 가 번호 화면으로 돌아가지 않았다');
    final second = await _awaitCodeScreen(tester, await _request(tester, _phone));
    await _record(binding, tester, 't3', {
      'firstArrivedSec': first.arrivedSec,
      'secondArrivedSec': second.arrivedSec,
      'routerLeak': second.leakSec != null,
    });
    expect(second.leakSec, isNull, reason: '두 번째 요청의 복귀 URL이 라우터로 샜다');
    expect(second.arrivedSec, isNotNull,
        reason: '두 번째 요청이 코드 화면에 못 왔다 — Firebase 시트 상태(isPresenting)가 갇혔을 수 있다');
  });

  // 맨 끝에 둔다 — 심사 번호가 켠 "앱 검증 생략" 스위치는 Auth 인스턴스(프로세스 전역)에 남으므로,
  // 고치기 전 코드에선 이 뒤의 모든 요청이 앱 검증 없이 나간다.
  // iOS 전용 특성 시험: Android는 앱 검증 경로(보통 보이지 않는 Play Integrity)가 수 초 안에 끝날 수 있어 "빨리 끝났나"
  // 문턱(3초)이 맞는지 실측이 없다 — 가짜 빨강을 피하려고 보정 전까지 건너뛴다(Android 판정식은 단위 시험
  // test/features/auth/data/app_verification_switch_test.dart가 지킨다).
  testWidgets('t4 (iOS) 심사 번호 다음 테스트 번호 — FlutterFire iOS 한계로 앱 검증 생략 스위치가 남는다',
      skip: _skip('t4') || !Platform.isIOS,
      (tester) async {
    final container = await _startApp(tester);
    final review = await _awaitCodeScreen(tester, await _request(tester, AuthConfig.reviewPhoneDisplay));
    expect(review.arrivedSec, isNotNull, reason: '심사 번호가 코드 화면에 못 왔다: $review');
    await tester.tap(find.byType(IconButton).first);
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(_phoneScreen, findsOneWidget);
    // 스위치가 남으면 앱 검증 없이 수 초에 끝난다. 앱 검증(reCAPTCHA)을 타면 그보다 늦거나, 그림 문제가 뜨면
    // 사람이 풀 때까지 안 끝난다 — 30초 안에 "빨리" 끝났는지만 본다(문제 화면이 떠도 판정이 된다).
    debugPrint('[P75] t4 review arrived ${review.arrivedSec}s'); // 하네스가 시트에서 멈춰도 기기 로그로 판정한다
    final after = await _awaitCodeScreen(tester, await _request(tester, _phone), within: const Duration(seconds: 30));
    debugPrint('[P75] t4 test-number arrived ${after.arrivedSec}s');
    final err = container.read(authViewModelProvider).error?.message;
    final fast = after.arrivedSec != null && after.arrivedSec! - review.arrivedSec! <= _reviewGapThresholdSec;
    await _record(binding, tester, 't4', {
      'reviewArrivedSec': review.arrivedSec,
      'testNumberArrivedSec': after.arrivedSec,
      'testNumberPendingAfter30s': after.arrivedSec == null && after.leakSec == null,
      'routerLeak': after.leakSec != null,
      'authError': err,
    });
    expect(after.leakSec, isNull, reason: '테스트 번호의 복귀 URL이 라우터로 샜다');
    expect(err, isNull, reason: '테스트 번호 요청이 오류로 끝났다: $err');
    // **알려진 한계를 그대로 단언한다**(특성 시험): FlutterFire iOS 플러그인은 이 스위치를 true일 때만 적용해
    // 한 번 켜지면 프로세스가 끝날 때까지 남는다(auth_repository_impl.dart 주석 · work_log/P77 — 실측 1.07s/0.80s).
    // 플러그인이 false를 받기 시작하면 이 단언이 깨진다 — 그때 주석과 이 시험을 "남지 않는다" 쪽으로 뒤집는다.
    expect(fast, isTrue,
        reason: 'iOS에서 앱 검증 생략 스위치가 꺼졌다(${after.arrivedSec}s) — 플러그인 한계가 풀렸다: '
            'auth_repository_impl.dart 주석·이 시험 정리');
  });
}

/// t4 판정 문턱(초) — work_log/P77 실측 표에서 정한다.
const double _reviewGapThresholdSec = 3;
