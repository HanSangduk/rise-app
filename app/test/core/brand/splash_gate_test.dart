// 기동 브랜드 층(P32).
//
// **이건 애니메이션이기 이전에 버그 수정이다.** `app_router`의 최상위 `redirect`가
// async라 세션 복원을 await하는 동안 go_router는 아무것도 그리지 않고
// (`SizedBox.shrink()`), 그 빈 프레임이 렌더되는 순간 네이티브 스플래시가 걷힌다.
// 회원이 보던 순서는 `네이티브 흰 화면 → 빈 창(최악 20초) → 완성 화면이 딱`이었다.
//
// 그래서 이 스위트가 잠그는 첫 계약은 "예쁘다"가 아니라 **"덮는다"**이다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/brand/rise_mark.dart';
import 'package:rise_member/core/brand/splash_gate.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool ready,
    bool disableAnimations = false,
  }) {
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SplashGate(
            ready: ready,
            child: const Text('앱 화면'),
          ),
        ),
      ),
    );
  }

  /// 층이 실제로 가리고 있는가 — 위젯이 트리에 있는 것만으로는 부족하다.
  /// (전체화면 `Opacity`는 saveLayer를 떠서 쓰지 않는다. 알파는 색에 직접 들어간다.)
  bool covering(WidgetTester tester) {
    final marks = tester.widgetList<RiseMark>(find.byType(RiseMark));
    return marks.isNotEmpty && marks.first.opacity > 0;
  }

  group('덮는다 — 이게 존재 이유다', () {
    testWidgets('복원이 끝나기 전에는 화면을 가린다', (tester) async {
      await pump(tester, ready: false);
      expect(covering(tester), isTrue, reason: '빈 창이 그대로 드러난다');
      expect(find.byType(RiseMark), findsOneWidget);
    });

    testWidgets('가리는 동안에도 아래 화면은 트리에 있다', (tester) async {
      // 라우터를 걷어내면 복원이 끝난 뒤 처음부터 다시 그려야 한다.
      await pump(tester, ready: false);
      expect(find.text('앱 화면'), findsOneWidget);
    });

    testWidgets('복원이 끝나면 걷힌다', (tester) async {
      await pump(tester, ready: false);
      await pump(tester, ready: true);
      await tester.pumpAndSettle();

      expect(find.byType(RiseMark), findsNothing, reason: '층이 남아 앱을 덮고 있다');
      expect(find.text('앱 화면'), findsOneWidget);
    });
  });

  group('첫 프레임이 앱 아이콘과 같다', () {
    testWidgets('점이 처음부터 있다 — 도착 연출을 넣으면 깜빡인다', (tester) async {
      // **실제로 이 실수를 했다가 되돌렸다.** 마크가 획 3개 + 점 1개라 "점이
      // 도착하는" 연출을 만들었는데, Android 12+ 시스템 스플래시가 쓰는 건 **런처
      // 아이콘**이고 그 아이콘엔 점이 이미 있다(실기기 캡처로 확인). 결과는
      // `점 있음 → 없음 → 다시 나타남`. iOS의 앱 아이콘 확대 전환도 같다.
      await pump(tester, ready: false);

      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<RiseMarkPainter>()
          .first;
      expect(painter.dotProgress, 1,
          reason: '첫 프레임에 점이 없으면 아이콘에서 넘어올 때 깜빡인다');
    });
  });

  group('마크와 크림이 함께 걷힌다', () {
    testWidgets('전환 중간에 마크도 옅어진다 — 크림만 걷히면 마크가 툭 사라진다', (tester) async {
      // 알파를 크림 면에만 주면 마크는 끝까지 진하게 남아 있다가 층이 제거되는
      // 순간 **사라진다**. 그게 바로 이 층이 고치려던 "전환 0프레임" 장면이다.
      await pump(tester, ready: false);
      expect(covering(tester), isTrue);

      await pump(tester, ready: true);
      await tester.pump(SplashGate.fadeOut ~/ 2);

      final mark = tester.widgetList<RiseMark>(find.byType(RiseMark)).first;
      expect(mark.opacity, lessThan(1),
          reason: '크림만 걷히고 마크는 그대로다');
      expect(mark.opacity, greaterThan(0), reason: '중간인데 이미 다 사라졌다');
    });
  });

  group('기동을 느리게 만들지 않는다', () {
    testWidgets('머무는 구간이 없다 — 전환 시간이 곧 추가 시간의 전부', (tester) async {
      // 로그아웃 상태처럼 복원이 즉시 끝나는 경로에서는 hold가 통째로 **새로
      // 만들어낸 기다림**이 된다. 이 층은 ready 전까지 이미 떠 있으므로 회원은
      // 마크를 충분히 본 뒤다.
      await pump(tester, ready: false);
      await pump(tester, ready: true);

      await tester.pump(SplashGate.fadeOut + const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.byType(RiseMark), findsNothing,
          reason: '전환 시간을 넘겨 더 붙잡고 있다');
    });

    testWidgets('프레임마다 컨트롤러에 리스너를 쌓지 않는다', (tester) async {
      // `AnimatedBuilder` 본문에서 `CurvedAnimation`을 만들면 프레임마다 부모
      // 컨트롤러에 상태 리스너가 등록되고 아무도 해제하지 않는다.
      await pump(tester, ready: false);
      await pump(tester, ready: true);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // 누수가 있으면 프레임워크가 dispose 시점에 잡는다(leak tracking).
      await tester.pumpAndSettle();
      expect(find.byType(RiseMark), findsNothing);
    });
  });

  group('한 번 걷히면 돌아오지 않는다', () {
    testWidgets('세션이 만료돼 ready가 false로 돌아가도 다시 뜨지 않는다', (tester) async {
      // 401로 세션이 비면 앱은 로그인으로 되돌린다. 그때 스플래시가 다시 뜨면
      // 회원은 **앱이 재시작한 줄 안다.**
      await pump(tester, ready: false);
      await pump(tester, ready: true);
      await tester.pumpAndSettle();
      expect(find.byType(RiseMark), findsNothing);

      await pump(tester, ready: false);
      await tester.pump();

      expect(find.byType(RiseMark), findsNothing, reason: '스플래시가 되살아났다');
    });
  });

  group('걷힌 뒤에는 탭을 막지 않는다', () {
    testWidgets('투명해진 층이 아래 버튼의 탭을 삼키지 않는다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SplashGate(
              ready: true,
              child: Center(
                child: GestureDetector(
                  // `deferToChild`(기본)면 빈 SizedBox가 히트테스트에 참여하지 않아
                  // 층과 무관하게 탭이 빗나간다 — 그러면 이 테스트가 아무것도 검사하지
                  // 못한다.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox(width: 200, height: 200),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SizedBox).first, warnIfMissed: false);
      expect(taps, 1, reason: '걷힌 층이 탭을 가로챘다');
    });
  });

  group('절대 상한 — 가두지 않는다', () {
    testWidgets('신호가 오지 않아도 상한이 지나면 걷힌다', (tester) async {
      // 이 층은 화면 전체를 덮는다. 걷히지 않으면 회원은 앱을 **아예 못 쓴다** —
      // 덮으라고 만든 층이 가두는 층이 된다. 복원 예산은 네트워크 호출 하나에만
      // 걸려 있어서, 그 앞뒤(Firebase 토큰 획득·로컬 저장소)에서 멈추면 `ready`가
      // 영영 오지 않는다.
      await pump(tester, ready: false);
      expect(covering(tester), isTrue);

      await tester.pump(SplashGate.ceiling + const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(RiseMark), findsNothing, reason: '상한을 넘겼는데 갇혔다');
      expect(find.text('앱 화면'), findsOneWidget);
    });

    testWidgets('정상 경로에서는 상한을 기다리지 않는다', (tester) async {
      await pump(tester, ready: false);
      await pump(tester, ready: true);
      await tester.pumpAndSettle();
      expect(find.byType(RiseMark), findsNothing);
      // 타이머가 남아 있으면 테스트 프레임워크가 "Pending timers"로 깨진다 —
      // 즉 이 테스트는 정리까지 함께 잠근다.
    });
  });

  group('모션을 끈 사용자', () {
    testWidgets('층은 그대로 덮는다 — "애니메이션 없음"이 "층 없음"은 아니다', (tester) async {
      // 층이 없으면 덮어야 할 빈 창이 그대로 드러난다. 모션을 껐다고 회원이
      // 빈 화면을 봐야 할 이유는 없다.
      await pump(tester, ready: false, disableAnimations: true);
      expect(covering(tester), isTrue, reason: '모션을 껐다고 빈 창을 보여주면 안 된다');
    });

    testWidgets('확대는 끄되 하드 컷으로 돌아가지 않는다', (tester) async {
      // **하드 컷은 이 층이 고치려던 바로 그 장면이다**("완성 화면이 전환
      // 0프레임으로 딱"). 불투명도 변화는 WCAG 2.3.3이 말하는 모션이 아니므로
      // (위치·크기 변화가 아니다) 짧은 페이드는 남기고 **확대만** 끈다.
      await pump(tester, ready: false, disableAnimations: true);
      await pump(tester, ready: true, disableAnimations: true);

      // 확대가 걸려 있으면 Transform.scale의 배율이 1을 벗어난다.
      await tester.pump(const Duration(milliseconds: 60));
      final t = tester.widgetList<Transform>(find.byType(Transform)).toList();
      if (t.isNotEmpty) {
        final m = t.first.transform;
        expect(m.getMaxScaleOnAxis(), closeTo(1.0, 1e-6),
            reason: '모션을 껐는데 마크가 커진다');
      }

      // 그래도 결국 걷힌다 — 그리고 일반 전환보다 짧다.
      await tester.pumpAndSettle();
      expect(find.byType(RiseMark), findsNothing);
    });

    testWidgets('일반 전환보다 빨리 끝난다', (tester) async {
      await pump(tester, ready: false, disableAnimations: true);
      await pump(tester, ready: true, disableAnimations: true);
      await tester.pump(const Duration(milliseconds: 130));
      await tester.pump();
      expect(find.byType(RiseMark), findsNothing,
          reason: '모션을 껐는데 전체 전환 시간을 다 기다린다');
    });
  });
}
