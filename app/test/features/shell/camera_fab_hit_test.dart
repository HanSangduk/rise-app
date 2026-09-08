// 촬영 FAB 히트 영역 규약(P54).
//
// 실기기 이분 탐색으로 확인한 결함: FAB는 탭 바 위로 18 튀어나오게 그려지는데
// 조상 박스는 62뿐이라, `RenderBox.hitTest`의 `size.contains(position)` 검사가
// **원의 위쪽 18을 걸러냈다**. 눈에 보이는 큰 버튼의 윗부분이 안 눌렸고, 더 나쁘게는
// 그 탭이 뒤의 본문 콘텐츠로 내려갔다 — 버튼을 눌렀는데 뒤 목록이 반응한다.
//
// 회귀 방향이 뚜렷하다: 누군가 헤드룸을 없애거나(막대 높이만 남기거나) 항목 행을
// 다시 62로 묶으면 조용히 되돌아간다. 그리기는 그대로라 **눈으로는 안 보인다.**

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 셸의 구조를 그대로 재현한다(위젯 자체는 go_router 셸이 필요해 직접 못 띄운다).
/// 구조가 갈리면 이 테스트가 지키는 대상이 사라지므로, app_shell.dart를 고치면
/// 여기도 함께 고쳐야 한다.
const double kBarHeight = 62;
const double kFabRaise = 18;

Widget _bar({required VoidCallback onCamera, required VoidCallback onBody}) {
  return MaterialApp(
    home: Scaffold(
      // 뒤에 깔린 본문 — FAB 상단을 눌렀을 때 여기로 새면 안 된다.
      body: GestureDetector(
        onTap: onBody,
        child: Container(color: const Color(0xFFEEEEEE)),
      ),
      bottomNavigationBar: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              left: 0,
              right: 0,
              top: kFabRaise,
              bottom: 0,
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.white)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                const SizedBox(width: 40, height: kBarHeight + kFabRaise),
                InkWell(
                  onTap: onCamera,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.only(top: kFabRaise),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: kBarHeight),
                      child: Center(
                        heightFactor: 1,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.translate(
                              offset: const Offset(0, -kFabRaise),
                              child: Container(
                                key: const Key('fab'),
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(0, -12),
                              child: const Text('촬영', style: TextStyle(fontSize: 9.5)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 40, height: kBarHeight + kFabRaise),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('그려진 원 전체가 눌린다 — 위쪽 가장자리 포함', (tester) async {
    var camera = 0, body = 0;
    await tester.pumpWidget(_bar(onCamera: () => camera++, onBody: () => body++));

    final circle = tester.getRect(find.byKey(const Key('fab')));
    // 원의 위·중간·아래 세 지점. 종전 구현은 위쪽에서 실패했다.
    for (final dy in [2.0, circle.height / 2, circle.height - 2]) {
      await tester.tapAt(Offset(circle.center.dx, circle.top + dy));
      await tester.pump();
    }

    expect(camera, 3, reason: '원 안을 눌렀는데 촬영으로 가지 않았다');
    expect(body, 0, reason: '원 위쪽 탭이 뒤 본문으로 샜다 — 눌렀는데 목록이 반응하는 그 증상');
  });

  testWidgets('원의 위쪽 가장자리가 막대 밖에 있다 — 헤드룸이 실제로 필요한 모양인지 고정', (tester) async {
    // 이 단언이 깨지면(= 원이 막대 안에 들어오면) 헤드룸이 필요 없어진 것이고,
    // 그때는 위 테스트도 함께 재검토해야 한다. 디자인이 바뀐 신호다.
    await tester.pumpWidget(_bar(onCamera: () {}, onBody: () {}));

    final circle = tester.getRect(find.byKey(const Key('fab')));
    final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final barTop = screenH - kBarHeight;

    expect(circle.top, lessThan(barTop), reason: '원이 막대 위로 나오지 않는다 — 디자인이 바뀌었다면 이 파일을 갱신할 것');
  });

  testWidgets('탭 바 전체 높이가 막대 + 헤드룸이다', (tester) async {
    await tester.pumpWidget(_bar(onCamera: () {}, onBody: () {}));

    final barRect = tester.getRect(find.byType(Stack).first);
    expect(
      barRect.height,
      greaterThanOrEqualTo(kBarHeight + kFabRaise),
      reason: '헤드룸이 사라지면 FAB 위쪽이 다시 안 눌린다',
    );
    // 상한도 잰다 — 구현 중 실제로 밟은 함정이다. Stack의 자식이 전부 Positioned이면
    // Stack이 `constraints.biggest`로, Row에 `CrossAxisAlignment.stretch`를 주면 Flex가
    // 교차축을 `maxHeight`로 타이트하게 잡아, **둘 다 탭 바가 화면 전체를 먹는다.**
    // 그리기는 배경이 하단에만 칠해져 스크린샷으로는 멀쩡해 보이므로 눈으로 못 잡는다.
    expect(
      barRect.height,
      lessThan(kBarHeight + kFabRaise + 40),
      reason: '탭 바가 부풀었다 — 행이 Positioned이거나 stretch를 쓰고 있지 않은지 확인',
    );
  });
}
