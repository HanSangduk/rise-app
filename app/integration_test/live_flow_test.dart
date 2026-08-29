// 실플로우 점검용 통합 테스트(P09) — **프로덕션 백엔드에 실제로 붙는다.**
//
// 목적은 단위 검증이 아니라 "회원이 앱을 켜서 예약까지 가는 길"이 실제로 뚫려 있는지 보는 것이다.
// 각 화면에서 잠시 멈춰 바깥에서 스크린샷을 찍을 시간을 준다(시뮬레이터 UI 자동화 도구가
// 없어 화면 확인은 외부 캡처에 의존한다).
//
// 실행:
//   flutter test integration_test/live_flow_test.dart -d <simulator-id> \
//     --dart-define=API_BASE_URL=... --dart-define=DEV_SESSION=false
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rise_member/app.dart';
import 'package:rise_member/firebase_options.dart';

/// 콘솔 등록 테스트 번호 — 실 SMS·과금 없음(P06).
const testPhone = '010-1234-5678';
const testCode = '123456';

/// 화면을 눈으로 확인할 시간. 외부 스크린샷 루프가 이 창에서 캡처한다.
Future<void> hold(WidgetTester tester, String label, {int seconds = 4}) async {
  debugPrint('[FLOW] $label');
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// 네트워크 응답을 기다리며 프레임을 돌린다(pumpAndSettle은 무한 애니메이션에서 멈추지 않는다).
Future<void> settle(WidgetTester tester, {int seconds = 8}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('회원 실플로우: 로그인 → 매칭 → 홈 → 예약', (tester) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await tester.pumpWidget(const ProviderScope(child: RiseMemberApp()));
    await settle(tester, seconds: 5);
    await hold(tester, '01 로그인 화면');

    // ── 번호 입력
    final phoneField = find.byType(TextField);
    expect(phoneField, findsWidgets, reason: '로그인 화면에 번호 입력란이 있어야 한다');
    await tester.enterText(phoneField.first, testPhone);
    await tester.pump(const Duration(milliseconds: 300));
    await hold(tester, '02 번호 입력됨', seconds: 2);

    await tester.tap(find.text('인증번호 받기'));
    await settle(tester, seconds: 12);
    await hold(tester, '03 인증번호 화면');

    // ── 코드 입력
    final codeField = find.byType(TextField);
    if (codeField.evaluate().isNotEmpty) {
      await tester.enterText(codeField.first, testCode);
      await tester.pump(const Duration(milliseconds: 300));
      await hold(tester, '04 코드 입력됨', seconds: 2);
      final confirm = find.text('확인');
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(confirm.first);
        await settle(tester, seconds: 15);
      }
    }
    await hold(tester, '05 매칭/센터 확인 화면', seconds: 6);

    // ── 본인 확인(있으면)
    for (final label in ['시작하기', '네,', '맞아요']) {
      final f = find.textContaining(label);
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await settle(tester, seconds: 12);
        break;
      }
    }
    await hold(tester, '06 홈 화면', seconds: 6);

    // ── 예약 탭
    final bookingTab = find.text('예약');
    if (bookingTab.evaluate().isNotEmpty) {
      await tester.tap(bookingTab.first);
      await settle(tester, seconds: 10);
      await hold(tester, '07 예약 화면', seconds: 6);
    }

    // ── 마이 탭
    final myTab = find.text('마이');
    if (myTab.evaluate().isNotEmpty) {
      await tester.tap(myTab.first);
      await settle(tester, seconds: 8);
      await hold(tester, '08 마이 화면', seconds: 5);
    }

    debugPrint('[FLOW] 완료');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
