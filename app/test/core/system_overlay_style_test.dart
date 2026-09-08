// 시스템 바 스타일 규약(P54).
//
// 이 앱은 밝은 크림 UI인데 종전엔 **내비게이션 바가 검게** 칠해졌다. `MaterialApp`이
// 밝은 테마에서 `SystemUiOverlayStyle.dark`를 보내는데, 그 값의 실제 내용이
// "내비바 배경 검정 + 아이콘 흰색"이기 때문이다(이름과 정반대로 읽히는 자리다).
// `AppBarTheme.systemOverlayStyle`로는 못 막는다 — AppBar가 있는 화면에만 걸리고
// 홈·로그인에는 AppBar가 없다. 그래서 루트 `AnnotatedRegion`으로 건다.
//
// 회귀가 눈에 잘 안 띈다: 개발자는 대개 제스처 내비(얇은 핸들)를 쓰고, 3버튼 내비에서만
// 검은 띠가 넓게 보인다. 스토어 캡처에도 그대로 박힌다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('밝은 화면 — 내비바를 검게 칠하지 않고 아이콘을 어둡게 둔다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: const AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: Scaffold(body: SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final style = SystemChrome.latestStyle;
    expect(style, isNotNull, reason: '루트 AnnotatedRegion이 스타일을 내보내지 않았다');
    expect(
      style!.systemNavigationBarIconBrightness,
      Brightness.dark,
      reason: '크림 배경 위에 흰 아이콘이면 제스처 내비에서 거의 안 보인다',
    );
    expect(
      style.systemNavigationBarColor,
      isNot(const Color(0xFF000000)),
      reason: '밝은 앱 아래 검은 띠 — 종전 SystemUiOverlayStyle.dark의 그 값이다',
    );
    expect(style.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('검은 전체화면은 루트 스타일을 덮는다 — 카메라·사진 뷰어', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: const AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          // 실제 구조: 루트 영역 안쪽에 검은 화면이 자기 영역을 얹는다.
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Scaffold(backgroundColor: Colors.black, body: SizedBox()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      SystemChrome.latestStyle!.statusBarIconBrightness,
      Brightness.light,
      reason: '검은 프리뷰 위 검은 시계·배터리 — 안쪽 영역이 이겨야 한다',
    );
  });
}
