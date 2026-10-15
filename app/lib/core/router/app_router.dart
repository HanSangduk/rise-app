import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/features/auth/presentation/center_confirm_screen.dart';
import 'package:rise_member/features/auth/presentation/code_screen.dart';
import 'package:rise_member/features/auth/presentation/phone_screen.dart';
import 'package:rise_member/features/bodycheck/presentation/camera_screen.dart';
import 'package:rise_member/features/booking/presentation/booking_screen.dart';
import 'package:rise_member/features/home/presentation/home_screen.dart';
import 'package:rise_member/features/my/presentation/my_screen.dart';
import 'package:rise_member/features/records/presentation/records_screen.dart';
import 'package:rise_member/features/shell/app_shell.dart';

/// go_router — 로그인 스택(전화번호→인증→센터확인, P48) + 바텀탭 4목적지 + 전체화면 촬영
/// (홈/예약/촬영/기록/마이) StatefulShellRoute.
///
/// 참고(wodshot 아키텍처): 예약 확정 시트·일시정지 신청 시트는 라우트가 아니라
/// showModalBottomSheet(D38과 동일 원칙 — 짧은 액션은 시트로).
///
/// [restoreLanding] — 앱 시작 1회, 남아 있는 Firebase 세션으로 착지할 라우트를
/// 돌려준다(`/home` = 세션 복원, `/login/center-confirm` = 가입 승인 대기 복귀,
/// null = 기존 온보딩 흐름). P06 세션 복원 + 승인 대기 영속 복귀.
///
/// 이 redirect는 **첫 1회만** 동작한다(restoreAttempted 래치) — 이후 화면들이
/// 부르는 context.go('/login')(로그아웃·"번호 다시 인증하기")와 충돌하지 않는다.
///
/// 세션 소멸(만료·토큰 폐기) 시 로그인 복귀는 **여기가 아니라 `app.dart`의
/// `ref.listen(sessionProvider)`** 가 담당한다. redirect에 넣지 않은 이유: 위 래치가
/// 첫 1회만 도는 구조라 이후 세션 변화를 잡지 못하고, 래치를 풀면 화면들이 직접 부르는
/// `context.go('/login')`과 서로 밀어내며 루프가 된다.
/// 세션을 비우는 쪽은 로그아웃·회원탈퇴 화면·dio 인터셉터의 401·캐시 재검증의 미연결
/// 확답이고, 착지는 그 이유(`SessionEndReason`)가 고른다.
GoRouter createRouter({Future<String?> Function()? restoreLanding}) {
  // 복원은 첫 redirect에서만 시도 — 이후 모든 내비게이션은 통과.
  var restoreAttempted = restoreLanding == null;
  return GoRouter(
    // **플랫폼 초기 라우트를 무시한다**(P64 D4). go_router는 OS가 넘긴 기본 라우트
    // (`platformDispatcher.defaultRouteName`)가 '/'가 아니면 `initialLocation`을 그걸로
    // 덮어쓴다(`_effectiveInitialLocation`). 그 값이 `/home`이고 복원할 세션이 없으면
    // 위 redirect가 null을 돌려 **세션 없이 셸에 착지**했고 — 4탭 뷰모델이 세션을
    // 요구하는 에러를 그렸다. 이 앱엔 딥링크가 없으므로 플랫폼 값이 옳을 경우가 없다.
    // 딥링크(예: 데스크 QR로 예약 열기)를 넣는 날 이 플래그를 풀어야 하는데, 그때는
    // redirect에 "복원 결과가 null이면 셸 경로를 /login으로" 가드를 넣어야 한다 —
    // `test/core/router/shell_gate_test.dart`가 그 회귀를 잡는다.
    //
    // **실행 중 들어오는 URL은 여기가 아니라 네이티브 스위치가 막는다**(P75). 위 플래그는 시작
    // 라우트만 본다 — OS가 실행 중에 넘기는 URL(iOS openURL · Android onNewIntent의 data)은
    // 엔진이 곧장 라우터로 밀어 넣는다(Flutter 3.27+ 기본값). iOS `Info.plist`의
    // `FlutterDeepLinkingEnabled`와 Android `MainActivity`의 `flutter_deeplinking_enabled`를
    // false로 둔 이유다. 켜져 있던 동안 Firebase 전화 인증의 reCAPTCHA 복귀 URL
    // (`app-1-…://firebaseauth/link`)이 여기로 새어 화면 전체가 "Page Not Found"가 됐다.
    // 딥링크를 넣는 날엔 그 URL을 라우터가 무시하게 만든 뒤 스위치를 켠다 —
    // `test/core/router/platform_deeplink_gate_test.dart`가 스위치를 지킨다.
    overridePlatformDefaultLocation: true,
    initialLocation: '/login',
    redirect: (context, state) async {
      if (restoreAttempted) return null;
      restoreAttempted = true;
      final landing = await restoreLanding!();
      // 착지 목적지가 이미 현재 위치면 리다이렉트하지 않는다(go_router 루프 방지).
      return landing == state.matchedLocation ? null : landing;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const PhoneScreen()),
      GoRoute(path: '/login/code', builder: (_, __) => const CodeScreen()),
      GoRoute(
        path: '/login/center-confirm',
        builder: (_, __) => const CenterConfirmScreen(),
      ),
      // 체형 촬영은 **탭이 아니라 모드**다(P21). 4포즈를 연속으로 찍는 동안 탭바·앱바가
      // 차지하던 세로 공간을 프리뷰에 돌려주고, 화면을 벗어나면 카메라가 확실히 꺼진다
      // (탭 브랜치는 indexedStack이라 떠나도 살아 있어 수명주기 판정이 이중이었다).
      // QR 스캐너와 같은 패턴 — rootNavigator 위의 fullscreenDialog.
      GoRoute(
        path: '/camera',
        pageBuilder: (_, state) => const MaterialPage(
          fullscreenDialog: true,
          child: CameraScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/booking', builder: (_, __) => const BookingScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/records', builder: (_, __) => const RecordsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/my', builder: (_, __) => const MyScreen())],
          ),
        ],
      ),
    ],
  );
}
