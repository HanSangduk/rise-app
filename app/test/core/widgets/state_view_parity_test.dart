import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/empty_passes_view.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_error_view.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';

/// 상태 표현(묶음 J) — 같은 자리에 교대로 나타나는 화면들이 같은 언어를 쓰는지.
///
/// ① 빈 상태와 에러 상태의 **골격 일치**. 두 뷰는 4개 탭의 같은 자리에 교대로
///    나타난다 — 회원권 0개면 [EmptyPassesView], 네트워크 오류면 [RiseErrorView].
///    예전엔 앞은 아이콘 34 + 제목 14/w900 + 설명 + 버튼이었고 뒤는 **아이콘도
///    제목도 없이** 12.5 문단 + 버튼이라, 같은 탭을 새로고침할 때마다 다른 앱처럼
///    보였다.
/// ② 스낵바의 성공/실패가 **색으로 구분**되는지 — 특히 체형 사진 저장 성공과
///    실패가 시각적으로 완전히 같았다.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child)),
    );
  }

  /// 두 뷰가 공유해야 하는 골격: 바깥 여백 24 · 아이콘 34 · 제목 14/w900 · 버튼.
  void expectSharedSkeleton(WidgetTester tester, {required String title}) {
    final padding = tester.widget<Padding>(
      find.ancestor(of: find.byType(Column), matching: find.byType(Padding)).first,
    );
    expect(padding.padding, const EdgeInsets.all(24));

    expect(tester.widget<RiseIcon>(find.byType(RiseIcon)).size, 34);

    final titleStyle = tester.widget<Text>(find.text(title)).style!;
    expect(titleStyle.fontSize, 14);
    expect(titleStyle.fontWeight, FontWeight.w900);

    expect(find.byType(RiseButton), findsOneWidget);
  }

  testWidgets('회원권 0개 뷰 — 기준 골격', (tester) async {
    await pump(tester, EmptyPassesView(onRefresh: () {}));
    expectSharedSkeleton(tester, title: '아직 회원권이 없어요');
  });

  testWidgets('에러 뷰 — 같은 골격에 아이콘·제목만 갈아끼운다', (tester) async {
    await pump(tester, RiseErrorView(message: '서버에 연결하지 못했어요', onRetry: () {}));
    expectSharedSkeleton(tester, title: '문제가 생겼어요');

    // 사유는 제목 아래 설명 줄로 — 카드 안 빈 상태 한 줄과 같은 11.5(J2).
    expect(tester.widget<Text>(find.text('서버에 연결하지 못했어요')).style!.fontSize, 11.5);
  });

  testWidgets('사유를 모르면 제목을 반복하지 않고 다음 행동을 말한다', (tester) async {
    await pump(tester, RiseErrorView(onRetry: () {}));

    // 예전 호출부는 폴백으로 '문제가 생겼어요'를 넘겼다 — 그게 이제 제목이라
    // 그대로 두면 같은 문장이 두 줄로 겹친다.
    expect(find.text('문제가 생겼어요'), findsOneWidget);
    expect(find.text('잠시 후 다시 시도해주세요'), findsOneWidget);
  });

  group('스낵바 (J3)', () {
    /// 실제 앱 테마로 스낵바를 띄우고 배경색을 읽어 온다.
    /// (`SnackBarBehavior.floating`이 테마에 들어갔으므로 실제로 뜨는지도 함께 확인 —
    ///  floating은 Scaffold가 없으면 런타임에 단언 실패한다.)
    final messengerKey = GlobalKey<ScaffoldMessengerState>();

    Future<Color?> showAndReadBg(WidgetTester tester, RiseSnackKind kind) async {
      await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: messengerKey,
        theme: buildAppTheme(),
        home: const Scaffold(body: SizedBox.shrink()),
      ));
      // 앞 케이스의 스낵바가 큐에 남아 있으면 그걸 다시 재는 셈이 된다.
      messengerKey.currentState!.clearSnackBars();
      await tester.pumpAndSettle();

      messengerKey.currentState!.showSnackBar(riseSnackBar('메시지', kind: kind));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'floating 스낵바가 뜨지 못했다');
      expect(find.text('메시지'), findsOneWidget);

      final material = tester.widget<Material>(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first,
      );
      return material.color;
    }

    testWidgets('성공과 실패가 서로 다른 색이고, 둘 다 중립과도 다르다', (tester) async {
      final ok = await showAndReadBg(tester, RiseSnackKind.ok);
      final danger = await showAndReadBg(tester, RiseSnackKind.danger);
      final neutral = await showAndReadBg(tester, RiseSnackKind.neutral);

      // 예전엔 셋 다 M3 기본값 하나였다 — 사진 저장 성공/실패를 색으로 구분 못 했다.
      expect(ok, isNot(danger));
      expect(ok, isNot(neutral));
      expect(danger, isNot(neutral));
    });

    testWidgets('색은 새로 만들지 않고 배지의 ok/danger 쌍을 그대로 쓴다', (tester) async {
      expect(await showAndReadBg(tester, RiseSnackKind.ok), AppColors.badgeOkBg);
      expect(await showAndReadBg(tester, RiseSnackKind.danger), AppColors.badgeDanBg);
      // 중립은 팔레트의 잉크 — M3 기본 inverseSurface(보라 계열)가 아니다.
      expect(await showAndReadBg(tester, RiseSnackKind.neutral), AppColors.ink);
    });
  });
}
