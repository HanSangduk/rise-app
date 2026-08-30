import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/grid_overlay.dart';
import 'package:rise_member/features/records/presentation/widgets/photo_measure_grid.dart';

// P46 — 계측 격자. 이 위젯의 존재 이유는 "두 사진에 **같은 눈금**을 얹어 변화량을
// 읽게 하는 것"이라, 검증도 그 성질(같은 눈금·이미지 실영역·원본 무변경)에 건다.
void main() {
  // 1×1 투명 PNG(가로세로 1:1) — 디코드가 실제로 일어나야 aspect가 잡힌다.
  final png1x1 = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  Future<void> pumpPhoto(
    WidgetTester tester, {
    required bool showGrid,
    double? refLine,
    GridDensity density = GridDensity.coarse,
  }) async {
    final app = MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 300, // 사진(1:1)보다 세로로 길다 — 레터박스가 생기는 조건
            child: MeasureGridPhoto(
              bytes: png1x1,
              showGrid: showGrid,
              density: density,
              refLine: refLine,
            ),
          ),
        ),
      ),
    );
    // 이미지 디코드는 **실제 비동기**라 가짜 시계(pumpAndSettle)만으로는 끝나지
    // 않는다 — runAsync 안에서 돌려야 비율이 잡히고 그제서야 격자가 자리를 얻는다.
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('격자를 켜면 이미지 **실영역**에만 그린다 — 레터박스로 새지 않는다', (tester) async {
    await pumpPhoto(tester, showGrid: true);

    final painter = find.byType(CustomPaint).evaluate().where(
      (e) => (e.widget as CustomPaint).painter is MeasureGridPainter,
    );
    expect(painter, isNotEmpty, reason: '격자 페인터가 있어야 한다');

    // 1:1 사진이 200×300 상자에 contain으로 들어가면 실영역은 200×200이다.
    // 페인트 박스가 그 크기여야 눈금이 사진 좌표와 일치한다(300이면 세로로 새어
    // 어깨 높이를 잘못 가리킨다).
    final size = tester.getSize(
      find.ancestor(
        of: find.byType(CustomPaint).last,
        matching: find.byType(AspectRatio),
      ).first,
    );
    expect(size.width, closeTo(200, 0.5));
    expect(size.height, closeTo(200, 0.5));
  });

  testWidgets('격자를 끄면 페인터를 만들지 않는다 — 사진만 본다', (tester) async {
    await pumpPhoto(tester, showGrid: false);

    final painters = find.byType(CustomPaint).evaluate().where(
      (e) => (e.widget as CustomPaint).painter is MeasureGridPainter,
    );
    expect(painters, isEmpty);
  });

  testWidgets('기준선 값이 페인터에 그대로 전달된다 — 두 사진이 같은 높이를 받는다', (tester) async {
    await pumpPhoto(tester, showGrid: true, refLine: 0.37);

    final painter = find.byType(CustomPaint).evaluate()
        .map((e) => (e.widget as CustomPaint).painter)
        .whereType<MeasureGridPainter>()
        .first;
    expect(painter.refLine, 0.37);
  });

  group('MeasureGridPainter 재페인트 규약', () {
    test('밀도·기준선이 바뀌면 다시 그린다', () {
      const a = MeasureGridPainter(density: GridDensity.coarse, refLine: 0.4);
      expect(
        a.shouldRepaint(
          const MeasureGridPainter(density: GridDensity.fine, refLine: 0.4),
        ),
        isTrue,
      );
      expect(
        a.shouldRepaint(
          const MeasureGridPainter(density: GridDensity.coarse, refLine: 0.5),
        ),
        isTrue,
      );
      expect(
        a.shouldRepaint(
          const MeasureGridPainter(density: GridDensity.coarse, refLine: 0.4),
        ),
        isFalse,
      );
    });
  });
}
