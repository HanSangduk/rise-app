import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 하단 탭 목적지 — 브랜치 인덱스는 `app_router.dart`의 `StatefulShellRoute` 순서다.
///
/// 인덱스를 숫자로 흩뿌리지 않는 이유: 탭이 하나 추가·이동되는 순간 호출부마다
/// 조용히 다른 탭으로 가게 된다. 순서를 바꾸면 여기 한 곳만 고치면 된다.
enum AppTab {
  home(0),
  booking(1),
  records(2),
  my(3);

  const AppTab(this.branchIndex);
  final int branchIndex;
}

/// 카드 안의 버튼에서 다른 탭으로 보낸다.
///
/// `context.go('/booking')`이 아니라 `goBranch`를 쓰는 이유는 **탭 상태 보존**이다 —
/// 회원이 예약 탭에서 날짜를 골라 둔 상태로 홈에 왔다가 다시 오면 그 날짜가 남아 있어야
/// 한다. `initialLocation: false`가 그 뜻이다(이미 그 탭에 있으면 루트로 되돌린다는
/// go_router 규약을 따라, 같은 탭이면 true로 올린다).
///
/// 셸 **밖**에서 부르면(위젯 테스트, 전체화면 라우트) `maybeOf`가 null을 준다 —
/// 그때는 조용히 아무 일도 하지 않는다. 카드 하나를 테스트에 띄웠다고 예외로 죽는 것보다
/// 낫고, 실제 화면에서는 항상 셸 안이다.
void goToTab(BuildContext context, AppTab tab) {
  final shell = StatefulNavigationShell.maybeOf(context);
  if (shell == null) return;
  shell.goBranch(
    tab.branchIndex,
    initialLocation: tab.branchIndex == shell.currentIndex,
  );
}
