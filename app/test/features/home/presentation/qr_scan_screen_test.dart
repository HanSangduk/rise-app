import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/home/presentation/qr_scan_screen.dart';

// 체크인 스캐너의 **취소 가능성**과 **권한 안내 분기**.
//
// 스캐너를 열었는데 나갈 길이 없으면 회원은 앱을 강제 종료한다. 그리고 권한을
// 영구 거부한 상태에서 "권한 허용하기"만 보여주면 눌러도 아무 일이 없는 버튼
// 앞에 갇힌다 — 두 경우가 코드에서 실제로 갈리는지 확인한다.
//
// 실제 스캔(권한 granted) 경로는 MobileScanner가 플랫폼 뷰를 요구해 위젯 테스트로
// 재현할 수 없다 — 실기기 체크리스트로 넘긴다(P11 보고).
void main() {
  Future<void> pushScanner(
    WidgetTester tester, {
    required CameraPermissionGate gate,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cameraPermissionGateProvider.overrideWithValue(gate)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => const QrScanScreen()),
                  ),
                  child: const Text('체크인'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('체크인'));
    await tester.pumpAndSettle();
  }

  testWidgets('일시 거부 — 다시 요청하는 버튼과 취소가 함께 있다', (tester) async {
    await pushScanner(tester, gate: _FakeGate(CameraPermissionResult.denied));

    expect(find.text('카메라 권한이 필요해요'), findsOneWidget);
    expect(find.text('권한 허용하기'), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);
    // QR 스캔은 사진을 저장하지 않는다 — 체형 촬영용 "사진은 …만 볼 수 있게
    // 저장돼요"가 공용 위젯에 박혀 여기까지 붙어 있었다(안 하는 일을 한다고
    // 말하는 거짓). 문장은 용도별 note로 갈라졌고, QR 쪽엔 없어야 한다.
    expect(find.textContaining('사진'), findsNothing);
    expect(find.textContaining('저장'), findsNothing);
  });

  testWidgets('영구 거부 — 설정 열기로 안내한다', (tester) async {
    final gate = _FakeGate(CameraPermissionResult.permanentlyDenied);
    await pushScanner(tester, gate: gate);

    expect(find.text('카메라 권한이 꺼져 있어요'), findsOneWidget);
    expect(find.text('권한 허용하기'), findsNothing);

    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    expect(gate.openedSettings, isTrue);
  });

  // 영구 거부에서 이 화면이 주는 유일한 다음 행동은 "설정 열기"다. 켜고 돌아왔는데
  // 옛 판정이 그대로면 회원은 **이미 켠 설정을 또 여는 버튼** 앞에 갇혀, 체크인을
  // 포기하거나 앱을 강제 종료한다 — 돌아오는 것만으로 복구돼야 한다.
  //
  // 뮤테이션: `didChangeAppLifecycleState`의 재확인 분기를 지우면 요청 수가 1에 멈춘다.
  testWidgets('영구 거부 — 설정에서 켜고 돌아오면 권한을 다시 확인한다', (tester) async {
    final gate = _FakeGate(CameraPermissionResult.permanentlyDenied);
    await pushScanner(tester, gate: gate);
    expect(gate.requests, 1);

    await backgroundAndReturn(tester);

    expect(gate.requests, 2, reason: '복귀 시 다시 묻지 않으면 화면이 스스로 못 푼다');
  });

  // 일시 거부에는 살아 있는 "권한 허용하기" 버튼이 있어 갇히지 않는다 — 복귀할 때마다
  // 부르지도 않은 시스템 프롬프트를 띄우는 쪽이 나쁘다(ensureGranted는 곧바로 묻는다).
  testWidgets('일시 거부 — 복귀만으로 권한을 다시 묻지 않는다', (tester) async {
    final gate = _FakeGate(CameraPermissionResult.denied);
    await pushScanner(tester, gate: gate);
    expect(gate.requests, 1);

    await backgroundAndReturn(tester);

    expect(gate.requests, 1);
  });

  testWidgets('취소하면 null로 닫힌다 — 체크인 요청을 보내지 않는다', (tester) async {
    String? popped = 'sentinel';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cameraPermissionGateProvider
              .overrideWithValue(_FakeGate(CameraPermissionResult.denied)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    popped = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const QrScanScreen()),
                    );
                  },
                  child: const Text('체크인'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('체크인'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(popped, isNull);
    expect(find.text('체크인'), findsOneWidget, reason: '원래 화면으로 돌아온다');
  });

  testWidgets('앱바 닫기(X)로도 취소된다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cameraPermissionGateProvider
              .overrideWithValue(_FakeGate(CameraPermissionResult.denied)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => const QrScanScreen()),
                  ),
                  child: const Text('체크인'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('체크인'));
    await tester.pumpAndSettle();
    expect(find.text('체크인 QR 스캔'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('체크인 QR 스캔'), findsNothing);
  });
}

/// 홈 버튼 → 설정 → 앱 복귀. 수명주기 전이는 **건너뛸 수 없다**(프레임워크가 인접
/// 전이만 허용한다) — resumed에서 곧장 paused로 보내면 단언에 걸린다.
Future<void> backgroundAndReturn(WidgetTester tester) async {
  const path = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];
  for (final state in path) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _FakeGate implements CameraPermissionGate {
  _FakeGate(this.result);
  final CameraPermissionResult result;
  bool openedSettings = false;
  int requests = 0;

  @override
  Future<CameraPermissionResult> ensureGranted() async {
    requests++;
    return result;
  }

  @override
  Future<void> openSettings() async => openedSettings = true;
}
