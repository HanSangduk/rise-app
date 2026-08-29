// P09 실기기 회귀: 하단 탭바가 오버플로하면 안 된다.
//
// Pretendard 번들 후 실제 안드로이드(Pixel 6 / density 420)에서 `BOTTOM OVERFLOWED BY 1.00 PIXELS`가
// 떴다. 가운데 촬영 탭의 레이아웃 높이(원 48 + 라벨 줄높이)가 고정 62를 넘긴 것인데,
// 폴백 폰트로 도는 테스트에서는 줄높이가 달라 재현되지 않았다 — 그래서 **번들 폰트를 실제로
// 로드해서** 잰다. 텍스트 배율 상한(1.35)까지 함께 확인한다.
//
// 탭바 구조를 여기 복제한 이유: 실제 셸은 go_router `StatefulShellRoute`를 요구해 위젯 테스트에서
// 띄우기 어렵다. 대신 오버플로를 냈던 **치수 조합 그대로**를 재현한다 — 수치가 바뀌면
// `app_shell.dart`와 함께 갱신해야 한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';

import '../../support/font_loader.dart';


Widget bar() => Container(
      constraints: const BoxConstraints(minHeight: 62),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final label in ['홈', '예약'])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 21),
                const SizedBox(height: 3),
                Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
              ]),
            ),
          // 가운데 촬영 탭 — 오버플로를 냈던 조합(원 48 + 라벨, Transform은 레이아웃을 줄이지 않는다)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Transform.translate(
              offset: const Offset(0, -18),
              child: Container(width: 48, height: 48, color: const Color(0xFFF43F5E)),
            ),
            Transform.translate(
              offset: const Offset(0, -12),
              child: const Text('촬영',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
            ),
          ]),
        ],
      ),
    );

void main() {
  setUpAll(loadPretendard);

  for (final scale in [1.0, 1.15, 1.35]) {
    testWidgets('하단 탭바가 배율 $scale 에서 오버플로하지 않는다', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625; // Pixel 6 (density 420)
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: const SizedBox.shrink(), bottomNavigationBar: bar()),
        ),
      ));
      await tester.pump();

      // 오버플로는 Flutter가 예외로 올린다 — 잡히면 실패한다.
      expect(tester.takeException(), isNull,
          reason: '배율 $scale 에서 탭바가 넘쳤다(고정 높이 회귀)');
    });
  }
}
