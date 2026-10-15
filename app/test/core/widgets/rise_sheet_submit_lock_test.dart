// `showRiseSheet(submitting:)` — 제출 중 잠금(P56 M1).
//
// 제출 중인 시트를 닫으면 실패가 통째로 사라진다(에러는 시트 안 인라인이고 State는
// dispose된다). `isDismissible`·`enableDrag`는 라우트 생성 시점에 굳어 제출 시작 순간에
// 켤 수 없으므로 래퍼가 세 경로(스크림 탭·시스템 백·아래로 쓸기)를 직접 막는다.
//
// 세 경로를 **따로** 잰다 — 셋의 차단 원리가 다르기 때문이다. 스크림·백은 `maybePop`을
// 타 PopScope에 걸리지만, 쓸기는 `BottomSheet.onClosing → Navigator.pop`이라 PopScope를
// 지나지 않는다(SDK bottom_sheet.dart). 뮤테이션: `_SubmitLock`의 PopScope를 빼면 앞 둘이,
// GestureDetector의 콜백을 빼면 쓸기가 죽는다.
//
// 그리고 **풀리는 것**도 잰다 — 영구 잠금은 이 저장소가 가장 싫어하는 막다른 길이다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/widgets/rise_sheet.dart';

void main() {
  late ValueNotifier<bool> submitting;

  setUp(() => submitting = ValueNotifier(false));
  tearDown(() => submitting.dispose());

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      // showRiseSheet는 세션 감시자(_SessionSheetGuard)를 달아 연다 — 앱과 같은 DI 루트가 필요하다.
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showRiseSheet<void>(
                    context,
                    submitting: submitting,
                    builder: (_) => const SizedBox(
                      height: 240,
                      child: Center(child: Text('본문')),
                    ),
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('본문'), findsOneWidget);
  }

  /// 시트(240dp)는 화면 아래 붙는다 — (20,20)은 스크림이다.
  Future<void> tapScrim(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
  }

  Future<void> swipeDown(WidgetTester tester) async {
    await tester.fling(find.text('본문'), const Offset(0, 400), 1500);
    await tester.pumpAndSettle();
  }

  /// 엔진이 하드웨어 백에서 보내는 것과 같은 플랫폼 메시지(login_back_test와 같은 관용구).
  Future<void> pressSystemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  group('잠금 중에는 닫히지 않는다', () {
    testWidgets('스크림 탭', (tester) async {
      await openSheet(tester);
      submitting.value = true;
      await tester.pump();

      await tapScrim(tester);
      expect(find.text('본문'), findsOneWidget, reason: '제출 중 스크림 탭으로 닫혔다');
    });

    testWidgets('시스템 백', (tester) async {
      await openSheet(tester);
      submitting.value = true;
      await tester.pump();

      await pressSystemBack(tester);
      expect(find.text('본문'), findsOneWidget, reason: '제출 중 시스템 백으로 닫혔다');
    });

    testWidgets('아래로 쓸기 — PopScope가 못 막는 경로', (tester) async {
      await openSheet(tester);
      submitting.value = true;
      await tester.pump();

      await swipeDown(tester);
      expect(find.text('본문'), findsOneWidget, reason: '제출 중 쓸기로 닫혔다');
    });
  });

  group('잠금이 풀리면 종전대로 닫힌다 — 영구 잠금 방지', () {
    testWidgets('스크림 탭', (tester) async {
      await openSheet(tester);
      submitting.value = true;
      await tester.pump();
      submitting.value = false;
      await tester.pump();

      await tapScrim(tester);
      expect(find.text('본문'), findsNothing);
    });

    testWidgets('시스템 백', (tester) async {
      await openSheet(tester);
      submitting.value = true;
      await tester.pump();
      submitting.value = false;
      await tester.pump();

      await pressSystemBack(tester);
      expect(find.text('본문'), findsNothing);
    });

    testWidgets('아래로 쓸기', (tester) async {
      await openSheet(tester);
      submitting.value = true;
      await tester.pump();
      submitting.value = false;
      await tester.pump();

      await swipeDown(tester);
      expect(find.text('본문'), findsNothing);
    });
  });

  group('신호를 안 넘긴 시트는 종전과 같다 — 회귀 없음', () {
    testWidgets('쓸기·스크림·백 전부 닫힌다', (tester) async {
      Future<void> openPlain() async {
        await tester.pumpWidget(
          // showRiseSheet는 세션 감시자(_SessionSheetGuard)를 달아 연다 — 앱과 같은 DI 루트가 필요하다.
          ProviderScope(
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showRiseSheet<void>(
                        context,
                        builder: (_) => const SizedBox(height: 240, child: Center(child: Text('본문'))),
                      ),
                      child: const Text('열기'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
      }

      await openPlain();
      await swipeDown(tester);
      expect(find.text('본문'), findsNothing);

      await openPlain();
      await tapScrim(tester);
      expect(find.text('본문'), findsNothing);

      await openPlain();
      await pressSystemBack(tester);
      expect(find.text('본문'), findsNothing);
    });
  });
}
