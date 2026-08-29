// 탭 인덱스 단일 출처(P30).
//
// 카드 안 버튼이 다른 탭으로 보낼 때 숫자를 직접 쓰면, 탭이 하나 추가·이동되는 순간
// 호출부마다 조용히 다른 탭으로 간다. `AppTab`이 그 숫자를 혼자 들고 있고,
// 이 테스트가 그 값이 `app_router.dart`의 브랜치 순서와 어긋나지 않게 잠근다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/router/tab_navigation.dart';

void main() {
  test('브랜치 순서 — 홈 0 · 예약 1 · 기록 2 · 마이 3', () {
    // app_router.dart의 StatefulShellRoute 브랜치 선언 순서와 같아야 한다.
    // 촬영은 탭 브랜치가 아니라 전체화면 라우트라 여기 없다(P21).
    expect(AppTab.home.branchIndex, 0);
    expect(AppTab.booking.branchIndex, 1);
    expect(AppTab.records.branchIndex, 2);
    expect(AppTab.my.branchIndex, 3);
  });

  test('인덱스가 서로 겹치지 않는다', () {
    final seen = {for (final t in AppTab.values) t.branchIndex};
    expect(seen.length, AppTab.values.length, reason: '두 탭이 같은 브랜치를 가리킨다');
  });

  testWidgets('셸 밖에서 불러도 죽지 않는다 — 위젯 테스트에 카드 하나만 띄우는 경우', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));

    goToTab(ctx, AppTab.booking); // StatefulNavigationShell이 없다 — 조용히 무시
    expect(tester.takeException(), isNull);
  });
}
