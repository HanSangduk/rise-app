import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rise_member/core/brand/rise_mark.dart';

/// 기동 중 화면을 덮는 브랜드 층.
///
/// ## 이게 애니메이션이기 이전에 **버그 수정**인 이유
///
/// `app_router.dart`의 최상위 `redirect`는 **async**라 세션 복원을 `await`한다.
/// 그동안 go_router는 아무것도 그리지 않는다(`SizedBox.shrink()`) — 그리고 그 빈
/// 프레임이 렌더되는 순간 **네이티브 스플래시가 걷힌다.** 회원이 실제로 보는 순서는
/// 이랬다:
///
/// ```
/// 네이티브 흰 화면 → 빈 창(최악 20초) → 완성 화면이 전환 0프레임으로 딱
/// ```
///
/// 람이 "로고 나오고 바로 나오니까 이상하다"고 한 건 이 세 번째 구간이고, 진짜
/// 문제는 두 번째 구간이다. **모션만 얹으면 더 나빠진다** — 스플래시가 끝나는 자리가
/// 여전히 빈 창이기 때문이다. 그래서 이 층은 "예뻐 보이려고" 있는 게 아니라
/// **덮으라고** 있다.
///
/// ## 라우트가 아니라 오버레이인 이유
///
/// `/splash` 라우트로 만들면 그 라우트 자체가 **덮어야 할 구멍 안에** 놓인다 —
/// redirect가 await하는 동안엔 어떤 라우트도 그려지지 않는다. `MaterialApp.builder`는
/// 라우터 바깥이라 그 구간에도 살아 있다.
///
/// ## 인트로가 아니라 아웃트로인 이유
///
/// targetSdk 36이라 **Android 12+는 시스템 스플래시가 런처 아이콘을 먼저 띄운다.**
/// Flutter가 첫 프레임을 그릴 때 로고는 **이미 화면에 있다.** 등장 애니메이션은
/// 그걸 먼저 지워야 해서 글리치로 읽힌다.
///
/// ### 처음엔 "점이 도착한다"로 만들었다가 되돌렸다
///
/// 마크가 네이비 획 3개 + 베이지 점 1개라, 네이티브는 점 없이 보여주고 Flutter가
/// 점을 도착시키는 그림을 만들었다. **그런데 시스템 스플래시가 쓰는 건 런처
/// 아이콘이고, 그 아이콘에는 점이 이미 있다**(실기기 캡처로 확인). 결과는
/// `점 있음 → 없음 → 다시 나타남`이라는 정확히 그 깜빡임이었다. iOS의 앱 아이콘
/// 확대 전환도 같은 이유로 점을 보여준다.
///
/// **그래서 첫 프레임은 아이콘과 똑같다**(점 포함). 모션은 브랜드 면이 살짝 커지며
/// 걷히는 것 하나다 — 아이콘에서 이어지는 동작이라 끊기는 자리가 없다.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.ready, required this.child});

  /// 앱이 화면을 보여줄 준비가 됐는가(세션 복원 완료).
  final bool ready;
  final Widget child;

  /// 브랜드 면이 걷히는 시간.
  ///
  /// **머무는 구간(hold)을 두지 않는다.** 이 층은 `ready` 전까지 이미 떠 있으므로
  /// 회원은 마크를 충분히 본 뒤다. 거기에 hold를 더하면 그건 전환이 아니라
  /// **새로 만들어낸 기다림**이다 — 특히 로그아웃 상태처럼 복원이 즉시 끝나는
  /// 경로에서는 그 시간이 통째로 순수 대기가 된다.
  static const fadeOut = Duration(milliseconds: 320);

  /// **절대 상한.** 이 시간이 지나면 `ready`와 무관하게 걷는다.
  ///
  /// 이 층은 화면 전체를 덮으므로, 걷히지 않으면 회원은 앱을 **아예 못 쓴다** —
  /// 덮으라고 만든 층이 가두는 층이 된다. 복원 쪽에도 예산(6초)이 있지만 그건
  /// 네트워크 호출 하나에만 걸려 있고, 그 앞뒤(Firebase 토큰 획득·로컬 저장소
  /// 읽기)에서 멈추면 신호가 영영 오지 않는다.
  ///
  /// 8초인 근거: 복원 예산 6초 + 그 전후 여유. 정상 경로에서는 절대 도달하지
  /// 않는다(실기기 기동 실측 1.3초).
  static const ceiling = Duration(seconds: 8);

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SplashGate.fadeOut,
  );

  /// 층을 트리에서 뺐는가. 완전히 사라진 뒤에는 다시 나타나지 않는다 —
  /// 세션이 만료돼 `ready`가 false로 돌아가도 스플래시가 다시 뜨면
  /// **회원은 앱이 재시작한 줄 안다.**
  bool _gone = false;

  /// 이미 걷기 시작했는가 — [didChangeDependencies]가 여러 번 불릴 수 있어서
  /// (배율·테마 변경 등) 애니메이션을 두 번 시작하지 않도록 잠근다.
  bool _started = false;

  Timer? _ceiling;

  /// **필드로 둔다.** `AnimatedBuilder` 본문에서 만들면 프레임마다 새
  /// [CurvedAnimation]이 부모 컨트롤러에 상태 리스너를 등록하고 아무도 해제하지
  /// 않는다 — 초당 60~120개씩 새는 구조다(누수 추적 테스트가 잡는 종류).
  late final Animation<double> _out = CurvedAnimation(
    parent: _c,
    curve: Curves.easeInOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _gone = true);
      }
    });
    // 신호가 오지 않아도 반드시 걷는다.
    _ceiling = Timer(SplashGate.ceiling, () {
      if (mounted && !_gone) _start();
    });
  }

  /// **`initState`가 아니라 여기서 시작한다.** 시작 판단이 `MediaQuery`를 읽는데
  /// (모션 끄기 설정) `initState`에서는 상속 위젯을 읽을 수 없어 assert로 죽는다.
  /// 첫 프레임에 이미 `ready`인 경우(웜 스타트에서 복원이 즉시 끝나는 경로)에만
  /// 터지는 종류라 위젯 테스트를 쓰기 전까지 드러나지 않았다.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.ready) _start();
  }

  @override
  void didUpdateWidget(SplashGate old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) _start();
  }

  /// 모션을 끈 사용자인가. 확대를 끄고 전환을 짧게 하는 데 쓴다.
  bool _reducedMotion = false;

  void _start() {
    if (_started) return;
    _started = true;
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reducedMotion) {
      // **하드 컷으로 돌아가지 않는다.** 즉시 걷어내면 그게 바로 이 층이
      // 고치려던 "완성 화면이 전환 0프레임으로 딱" 그 장면이다. 불투명도
      // 변화는 WCAG 2.3.3이 말하는 '모션'이 아니므로(위치·크기 변화가 아니다)
      // 짧은 페이드는 남긴다 — 확대만 끈다.
      _c.duration = const Duration(milliseconds: 120);
    }
    _c.forward();
  }

  @override
  void dispose() {
    _ceiling?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final out = _out.value;
              final veil = 1 - out;
              // 2.2%만 커진다. 1% 남짓은 눈이 못 잡고, 6%면 "튀어나온다"가 된다.
              // 이 모션이 노리는 건 브랜드 면이 **들려서 걷히는** 느낌이다.
              //
              // 모션을 끈 사용자에겐 확대를 **아예 끈다**(줄이지 않는다) — 같은
              // 거리를 짧은 시간에 움직이면 오히려 튀는 동작이 된다.
              final scale = _reducedMotion ? 1.0 : 1 + 0.022 * out;
              // **포인터 분기를 두지 않는다.** 층은 `_gone`이 되는 순간 트리에서
              // 통째로 빠지므로(위 build 첫 줄), "투명해졌지만 아직 남아 있는"
              // 상태는 한 프레임도 관찰되지 않는다. 조건을 달면 어떤 테스트로도
              // 죽일 수 없는 분기가 생긴다(뮤테이션에서 실제로 살아남았다).
              // 층이 보이는 동안 탭을 막는 건 옳다 — 가려진 화면이니까.
              // **`Opacity` 위젯을 쓰지 않는다.** 전체화면 `Opacity`는 오프스크린
              // 레이어(`saveLayer`)를 떠서 기동 중 가장 바쁜 래스터 스레드에
              // 화면 크기만 한 합성을 매 프레임 얹는다. 여기서는 알파를 **색에
              // 직접** 넣으면 되고, 그게 가능한 이유는 크림 면과 마크가 겹치지
              // 않는 단순한 그림이라 알파 합성 결과가 같기 때문이다.
              return ColoredBox(
                color: RiseMarkGeometry.cream.withValues(alpha: veil),
                child: Center(
                  // 마크만 커진다 — 크림 면까지 같이 키우면 가장자리가 밀려
                  // 확대가 눈에 보인다.
                  child: Transform.scale(
                    scale: scale,
                    child: RiseMark(size: 132, opacity: veil),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
