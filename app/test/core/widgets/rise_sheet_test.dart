// 바텀시트 하단 안전영역 규약(P54).
//
// 람이 실기기에서 발견했다 — "바텀시트가 하드웨어 네비게이션 바에 걸린다".
// 원인은 설정 누락이 아니라 플랫폼 정책 변화였다: targetSdk 36에서 edge-to-edge는
// 강제라 시스템 바가 콘텐츠 위에 겹치는데, 시트들은 하단 여백을 `viewInsets`(키보드)
// 로만 잡고 있었다. 그래서 **키보드가 없는 시트에서만** CTA가 내비바 아래로 들어갔다.
//
// 함정 하나를 여기 박아 둔다: `useSafeArea: true`는 이 문제를 고치지 못한다.
// Flutter의 그 옵션은 `SafeArea(bottom: false)`라 하단을 의도적으로 제외한다.
// 아래 첫 그룹이 그 사실 자체를 고정한다 — 누군가 "useSafeArea면 되잖아"로
// 래퍼를 걷어내면 여기서 터진다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/widgets/rise_sheet.dart';

/// 3버튼 내비(48) · 제스처(24) · iOS 홈 인디케이터(34).
const _navInsets = <String, double>{
  'Android 3버튼': 48,
  'Android 제스처': 24,
  'iOS 홈 인디케이터': 34,
};

/// 테스트 하네스 함정: `MaterialApp` 안에 `MediaQuery`를 끼워 인셋을 주입해도
/// 모달 라우트는 **그 위의 Navigator**에서 만들어져 전부 0으로 읽힌다.
/// 반드시 `tester.view`(물리 픽셀)로 주입해야 한다.
void _setInsets(WidgetTester tester, {double bottomPadding = 0, double keyboard = 0}) {
  final dpr = tester.view.devicePixelRatio;
  tester.view.viewPadding = FakeViewPadding(bottom: bottomPadding * dpr);
  tester.view.padding = FakeViewPadding(bottom: (bottomPadding - keyboard).clamp(0, 1e9) * dpr);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
}

Future<void> _openSheet(WidgetTester tester, WidgetBuilder builder) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showRiseSheet<void>(context, builder: builder),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

/// 호출부들이 실제로 쓰는 관용구 — 시트 본문이 `viewInsets.bottom + 20`으로
/// 하단 여백을 잡는다. 래퍼가 없으면 이 코드가 시스템 바를 못 본다.
Widget _sheetBody(BuildContext context) => Padding(
  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20),
  child: SizedBox(
    height: 120,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: ElevatedButton(onPressed: () {}, child: const Text('확정')),
    ),
  ),
);

void main() {
  group('Flutter의 useSafeArea는 하단을 담당하지 않는다 — 래퍼가 필요한 이유', () {
    testWidgets('useSafeArea: true여도 시트는 화면 맨 아래까지 내려간다', (tester) async {
      _setInsets(tester, bottomPadding: 48);
      addTearDown(tester.view.reset);

      late double sheetBottom;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true, // ← 켜도 하단은 그대로다
                  builder: (_) => const SizedBox(key: Key('body'), height: 100),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      sheetBottom = tester.getRect(find.byKey(const Key('body'))).bottom;

      expect(
        sheetBottom,
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
        reason: 'useSafeArea가 하단을 막아 준다는 믿음이 이 결함의 원인이었다',
      );
    });
  });

  group('showRiseSheet — 시스템 바 위에서 CTA가 눌린다', () {
    for (final entry in _navInsets.entries) {
      testWidgets('${entry.key}(${entry.value.toInt()}dp) — 키보드 없음', (tester) async {
        _setInsets(tester, bottomPadding: entry.value);
        addTearDown(tester.view.reset);

        await _openSheet(tester, _sheetBody);

        final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final safeLine = screenH - entry.value;
        expect(
          tester.getRect(find.text('확정')).bottom,
          lessThanOrEqualTo(safeLine),
          reason: '${entry.key}에서 CTA가 시스템 바 아래로 들어갔다',
        );
      });
    }

    testWidgets('키보드가 올라와도 CTA가 키보드 위에 머문다 — 이중 여백 없음', (tester) async {
      // Android는 IME가 뜨면 viewInsets에 내비바가 이미 포함된다. 그래서 래퍼는
      // 더하지 않고 max를 쓴다 — 더하면 CTA가 키보드 위로 48dp 붕 뜬다.
      _setInsets(tester, bottomPadding: 48, keyboard: 300);
      addTearDown(tester.view.reset);

      await _openSheet(tester, _sheetBody);

      final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final ctaBottom = tester.getRect(find.text('확정')).bottom;
      expect(ctaBottom, lessThanOrEqualTo(screenH - 300));
      expect(
        screenH - 300 - ctaBottom,
        lessThan(48),
        reason: 'max가 아니라 +로 합치면 여기서 내비바 높이만큼 떠 버린다',
      );
    });

    testWidgets('인셋이 0인 기기에서는 종전과 동일하게 동작한다', (tester) async {
      _setInsets(tester);
      addTearDown(tester.view.reset);

      await _openSheet(tester, _sheetBody);

      final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(tester.getRect(find.text('확정')).bottom, lessThanOrEqualTo(screenH));
    });
  });

  group('시트 안에서 SafeArea를 함께 써도 이중 여백이 생기지 않는다', () {
    // 종전부터 SafeArea로 하단을 처리하던 시트 3곳이 있었다. 래퍼는 viewInsets만
    // 손대고 SafeArea는 padding을 읽으므로 두 여백이 겹치지 않아야 한다.
    testWidgets('SafeArea 시트의 하단 여백이 인셋 1회분이다', (tester) async {
      _setInsets(tester, bottomPadding: 48);
      addTearDown(tester.view.reset);

      await _openSheet(
        tester,
        (_) => SafeArea(
          child: SizedBox(
            height: 100,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ElevatedButton(onPressed: () {}, child: const Text('확정')),
            ),
          ),
        ),
      );

      final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final gap = screenH - tester.getRect(find.text('확정')).bottom;
      expect(gap, greaterThanOrEqualTo(48), reason: 'SafeArea가 인셋을 못 받았다');
      expect(gap, lessThan(96), reason: '48dp가 두 번 들어갔다 — 이중 계상');
    });
  });
}
