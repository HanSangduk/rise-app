import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/brand/splash_gate.dart';
import 'package:rise_member/core/router/app_router.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/auth/presentation/session_restore.dart';

/// 시스템 글꼴 배율 상·하한.
///
/// **왜 클램프가 필요한가** — 이 앱의 타이포는 목업 CSS의 px를 1:1로 옮긴 값이라
/// 9.5~16.5px로 촘촘하고, 그 위에 고정 높이가 몇 군데 있다(탭바 62 · 체형 사진
/// 130 · 인바디 차트 80). 배율이 커지면 이 상자들이 먼저 터져 RenderFlex 오버플로
/// (줄무늬 + 글자 잘림)가 난다 — 글자가 커지는 게 아니라 **화면을 못 쓰게** 된다.
///
/// **하한 1.0** — 시스템에서 글자를 줄여도 따라가지 않는다. 본문이 이미 11.5px라
/// 0.85배(안드로이드 '작게')면 9.8px가 되어 읽기 어렵다.
///
/// **상한 1.35** — 감사 지시는 1.3이었지만 0.05를 올렸다. 1.35는 iOS Dynamic Type
/// 의 **비접근성 최대치(xxxLarge)** 와 정확히 같고, 안드로이드 '가장 크게'(1.3)도
/// 함께 덮는다. 1.3에서 끊으면 xxxLarge 사용자만 한 단계 축소된 화면을 보는데,
/// 아래 [_maxTextScale] 회귀 테스트(test/core/widgets/text_scale_overflow_test.dart)
/// 로 1.35에서 주요 화면에 오버플로가 없음을 확인했으므로 얻는 쪽이 크다.
///
/// 접근성 배율(iOS AX1~AX5, 최대 ~3.1배)은 여전히 잘린다 — 이건 의도한 타협이
/// 아니라 **남은 빚**이다. 상한을 더 올리려면 위 고정 높이 세 곳을 내용 기반
/// (IntrinsicHeight/최소 높이)으로 바꾸는 게 선행되어야 한다.
const _minTextScale = 1.0;
const _maxTextScale = 1.35;

class RiseMemberApp extends ConsumerStatefulWidget {
  const RiseMemberApp({super.key});

  @override
  ConsumerState<RiseMemberApp> createState() => _RiseMemberAppState();
}

class _RiseMemberAppState extends ConsumerState<RiseMemberApp> {
  /// 세션 복원이 끝났는가 — [SplashGate]가 걷힐 신호.
  ///
  /// 라우터의 `redirect`가 **async**라 복원 중에는 go_router가 아무것도 그리지
  /// 않는다(`SizedBox.shrink()`). 그 구간을 브랜드 층으로 덮으려면 "언제 끝났는지"를
  /// 라우터 바깥에서 알아야 하고, 그 신호가 이 값이다.
  bool _restored = false;

  /// 라우터는 앱 수명 동안 1개 — 재빌드마다 만들면 내비게이션 스택이 초기화된다.
  late final GoRouter _router = createRouter(
    restoreLanding: () async {
      try {
        final landing = await restoreAuthLanding(ref);
        // 신원을 알게 된 **그 순간** 홈 데이터를 부른다 — 스플래시가 걷히는
        // 320ms 동안 요청이 날아간다.
        if (landing == '/home') _warmHome();
        return landing;
      } finally {
        // **성공·실패·타임아웃 어느 쪽이든 걷는다.** finally가 아니면 복원이 던진
        // 경우 스플래시가 영원히 남아 회원이 앱을 못 쓴다 — 덮으라고 만든 층이
        // 가두는 층이 된다.
        if (mounted) setState(() => _restored = true);
      }
    },
  );

  /// 예열 구독 — 홈 화면이 `watch`를 시작할 때까지 provider를 살려 둔다.
  ProviderSubscription<AsyncValue<HomeSummary>>? _warm;

  /// 스플래시가 걷히는 동안 홈 데이터를 미리 받는다.
  ///
  /// **왜 구독을 들고 있어야 하는가.** `homeViewModelProvider`는 autoDispose라
  /// 듣는 사람이 없으면 다음 이벤트 루프에서 폐기된다. 그냥 `read`만 하면 요청은
  /// 나가지만 응답이 도착할 즈음 element가 사라져서, 홈이 열릴 때 **처음부터 다시**
  /// 받는다 — 트래픽만 두 배가 되고 얻는 게 없다.
  ///
  /// **실패는 물려주지 않는다.** 성공한 데이터는 홈이 그대로 이어받으면 되지만,
  /// 예열이 실패한 상태를 이어받으면 홈이 **얼어붙은 에러 화면**으로 열린다 —
  /// 하필 전파가 불안정한 기동 순간의 일시적 실패가 "다시 시도"를 눌러야만
  /// 풀리는 상태로 굳는다. 그래서 에러가 오면 구독을 놓아 다음 `watch`가
  /// 새 element에서 정상적으로 로딩을 시작하게 한다.
  void _warmHome() {
    _warm?.close();
    _warm = ref.listenManual<AsyncValue<HomeSummary>>(
      homeViewModelProvider,
      (prev, next) {
        if (next is AsyncError) _releaseWarm();
      },
      fireImmediately: true,
    );
    // 홈이 열리지 않는 경로(딥링크·즉시 로그아웃)에서 구독이 영원히 남지 않게.
    Timer(const Duration(seconds: 30), _releaseWarm);
  }

  void _releaseWarm() {
    _warm?.close();
    _warm = null;
  }

  @override
  void dispose() {
    _releaseWarm();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 세션이 **사라지면** 로그인으로 되돌린다(app_router의 TODO 이행).
    //
    // 세션을 비우는 주체는 두 곳이다: ① 로그아웃·회원탈퇴처럼 화면이 직접 비우는 경우
    // (그 화면들은 이미 context.go('/login')을 부르므로 여기 리다이렉트는 같은 자리로
    // 가는 무해한 중복이다) ② **dio 인터셉터의 401** — 토큰이 폐기돼 신원이 사라진 경우.
    // ②가 이 리스너의 존재 이유다. 종전엔 남은 화면들이 영원히 "요청을 처리할 수 없어요"만
    // 보여주고 로그인으로 돌아갈 길을 안내하지 못했다.
    //
    // **null → null은 무시한다**(prev != null 조건). 앱 시작 시점의 세션은 null이고,
    // 조건이 없으면 세션 복원이 끝나기도 전에 로그인으로 튕겨 복원 자체가 죽는다.
    ref.listen(sessionProvider, (prev, next) {
      if (prev == null || next != null) return;
      _router.go('/login');
    });

    return MaterialApp.router(
      title: '라이즈 컨디셔닝',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: _minTextScale,
              maxScaleFactor: _maxTextScale,
            ),
          ),
          // **라우터 바깥이라 복원 중에도 살아 있다.** `/splash` 라우트로 만들면
          // 그 라우트가 덮어야 할 구멍 안에 놓인다(redirect가 await하는 동안엔
          // 어떤 라우트도 그려지지 않는다).
          child: SplashGate(ready: _restored, child: child!),
        );
      },
    );
  }
}
