// 촬영 격자와 기준선(P22).
//
// 격자는 장식이 아니라 **나중에 두 장을 비교할 때의 눈금자**다. 칸이 크면 어깨가 반 칸
// 내려온 건지 한 칸인지 구분이 안 되고, 그게 곧 "얼마나 변했는지"를 못 읽는다는 뜻이다.
// 기준선은 사람마다 키가 달라 고정 높이가 아무 데도 안 맞으므로 끌어 옮길 수 있어야 한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/grid_overlay.dart';

void main() {
  group('격자 밀도', () {
    test('기본은 촘촘 — 예전 9×12보다 촘촘해야 변화량이 읽힌다', () {
      const d = GridDensity.fine;
      expect(d.cols, greaterThan(9));
      expect(d.rows, greaterThan(12));
    });

    test('세 단계가 실제로 촘촘해지는 순서다', () {
      expect(GridDensity.coarse.cols, lessThan(GridDensity.fine.cols));
      expect(GridDensity.fine.cols, lessThan(GridDensity.ultra.cols));
      expect(GridDensity.coarse.rows, lessThan(GridDensity.fine.rows));
      expect(GridDensity.fine.rows, lessThan(GridDensity.ultra.rows));
    });

    test('순환은 세 단계를 돌아 제자리로 — 버튼 하나로 다 고를 수 있다', () {
      var d = GridDensity.coarse;
      final seen = <GridDensity>[];
      for (var i = 0; i < 3; i++) {
        seen.add(d);
        d = d.next;
      }
      expect(seen.toSet().length, 3, reason: '순환이 한 단계를 건너뛴다');
      expect(d, GridDensity.coarse, reason: '세 번 눌러도 제자리로 안 온다');
    });

    test('주선 간격이 칸 수보다 작다 — 칸을 셀 수 있어야 판독이 된다', () {
      // 균일한 촘촘한 격자는 눈이 위치를 못 세서 오히려 판독이 어렵다.
      for (final d in GridDensity.values) {
        expect(d.majorEvery, greaterThan(1));
        expect(d.majorEvery, lessThan(d.cols),
            reason: '${d.label}: 주선이 한 줄도 안 그려진다');
        expect(d.majorEvery, lessThan(d.rows));
      }
    });

    test('모든 단계에 한국어 라벨이 있다(버튼에 그대로 뜬다)', () {
      for (final d in GridDensity.values) {
        expect(d.label, isNotEmpty);
        expect(RegExp(r'[가-힣]').hasMatch(d.label), isTrue);
      }
    });
  });

  group('기준선 드래그', () {
    testWidgets('크게 쓸면 그만큼 움직인다 — 손가락을 따라와야 한다', (tester) async {
      await tester.pumpWidget(const _DragProbe());
      final probe = tester.state<_DragProbeState>(find.byType(_DragProbe));
      expect(probe.hLine, closeTo(0.60, 1e-9));

      // 400px 프레임의 중앙(0.5=200px)에서 40px(=0.1) 위로.
      final center = tester.getCenter(find.byType(GridOverlay));
      await tester.dragFrom(center, const Offset(0, -40));
      await tester.pump();

      // 델타 누적이었다면 여기서 훨씬 덜 움직인다.
      expect(probe.hLine, closeTo(0.40, 0.02),
          reason: '손가락이 멈춘 지점(160/400)에 선이 있어야 한다');
    });

    testWidgets('프레임 밖까지 쓸어도 선을 잃어버리지 않는다', (tester) async {
      await tester.pumpWidget(const _DragProbe());
      final probe = tester.state<_DragProbeState>(find.byType(_DragProbe));

      await tester.dragFrom(tester.getCenter(find.byType(GridOverlay)), const Offset(0, -500));
      await tester.pump();
      expect(probe.hLine, greaterThan(0.0));
      expect(probe.hLine, lessThan(1.0));
    });
  });

  group('수평 기준선', () {
    testWidgets('밀도·기준선이 바뀌면 다시 그린다', (tester) async {
      await tester.pumpWidget(const _Host(density: GridDensity.fine, hLine: 0.6));
      final first = tester.widget<GridOverlay>(find.byType(GridOverlay));
      expect(first.hLine, 0.6);

      await tester.pumpWidget(const _Host(density: GridDensity.ultra, hLine: 0.3));
      final second = tester.widget<GridOverlay>(find.byType(GridOverlay));
      expect(second.density, GridDensity.ultra);
      expect(second.hLine, 0.3);
    });

    testWidgets('프레임 밖 값이 와도 그리기가 깨지지 않는다', (tester) async {
      // 드래그가 범위를 넘겨도(뷰모델이 clamp하지만 이중 방어) 예외 없이 그려야 한다.
      for (final v in [-1.0, 0.0, 1.0, 2.0]) {
        await tester.pumpWidget(_Host(density: GridDensity.fine, hLine: v));
        expect(tester.takeException(), isNull, reason: 'hLine=$v에서 터졌다');
      }
    });
  });
}

/// 드래그가 **손가락 위치를 그대로 따라오는지**. 델타 누적 방식이었을 때는 포인터
/// 이벤트가 리빌드보다 빨라 한 프레임 묵은 값에 더해지면서 이동분이 통째로 사라졌다
/// (실기기에서 크게 쓸어도 선이 조금만 따라왔다).
class _DragProbe extends StatefulWidget {
  const _DragProbe();
  @override
  State<_DragProbe> createState() => _DragProbeState();
}

class _DragProbeState extends State<_DragProbe> {
  double hLine = 0.60;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 400,
              child: Stack(
                children: [
                  GridOverlay(density: GridDensity.fine, hLine: hLine),
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (_, constraints) {
                        void place(Offset local) {
                          final h = constraints.maxHeight;
                          if (h <= 0) return;
                          setState(() => hLine = (local.dy / h).clamp(0.05, 0.95));
                        }

                        return GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragStart: (d) => place(d.localPosition),
                          onVerticalDragUpdate: (d) => place(d.localPosition),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Host extends StatelessWidget {
  const _Host({required this.density, required this.hLine});
  final GridDensity density;
  final double hLine;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Stack(children: [GridOverlay(density: density, hLine: hLine)]),
        ),
      );
}
