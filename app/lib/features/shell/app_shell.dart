import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';

/// 막대(배경·상단 보더가 칠해지는 부분)의 기준 높이.
const double _kBarHeight = 62;

/// 촬영 FAB가 막대 위로 튀어나오는 높이 = 각 항목이 위에 두는 투명 헤드룸.
///
/// **왜 헤드룸이 필요한가**(P54): FAB는 `Transform.translate(0,-18)`로 막대 위로
/// 나오게 그려지는데, 종전엔 항목 박스가 막대 높이(62)뿐이라 그 18이 박스 **밖**이었다.
/// `RenderBox.hitTest`는 `size.contains(position)`으로 먼저 거르므로 **원의 위쪽이
/// 눌리지 않았고**(갤럭시 실기기 이분 탐색으로 확인), 더 나쁘게는 그 자리의 탭이
/// 뒤의 본문 콘텐츠로 내려갔다 — 큰 버튼을 눌렀는데 뒤 목록이 반응한다.
/// 각 항목이 위에 18의 투명 패딩을 두면 원 전체가 박스 안에 들어온다.
const double _kFabRaise = 18;

/// 바텀 내비 셸 — 탭 **4개**(홈·예약·기록·마이) + 가운데 촬영 **버튼**.
///
/// 촬영은 탭이 아니다(P21): 전체화면 라우트를 rootNavigator 위로 push한다. 가운데 원이
/// 탭바 행에 있는 건 목업 `.cam-tab` 그대로지만, 눌렀을 때 브랜치를 바꾸는 게 아니라
/// 촬영 모드로 들어간다 — 그래서 이 버튼은 **선택 상태를 갖지 않는다**.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  // 탭 인덱스는 `AppTab`이 단일 출처다 — 카드 안 버튼도 같은 enum으로 이동한다
  // (core/router/tab_navigation.dart). 여기만 숫자를 받는 건 하단바가 순회 렌더라서다.
  void _go(int index) =>
      navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final current = navigationShell.currentIndex;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        child: Stack(
          children: [
            // 배경·상단 보더는 **아래 막대에만** 칠한다. 위 [_kFabRaise]는 투명이라
            // FAB가 그 위로 나오는 종전 모양이 그대로 유지된다.
            const Positioned(
              left: 0,
              right: 0,
              top: _kFabRaise,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
              ),
            ),
            // **이 행은 Positioned가 아니다** — Stack의 자식이 전부 Positioned면
            // Stack이 `constraints.biggest`(= 화면 전체 높이)로 부푼다. 이 행이
            // Stack의 높이를 정하는 유일한 자식이다(실측으로 잡은 함정).
            //
            // `crossAxisAlignment`도 기본값(center)을 쓴다. `stretch`로 두면 Flex가
            // 교차축 제약을 `constraints.maxHeight`로 **타이트하게** 주기 때문에
            // 역시 화면 전체 높이로 늘어난다 — 항목이 각자 자기 높이를 갖게 한다.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(RiseIcons.home, '홈', 0, current, _go),
                _NavItem(RiseIcons.calendar, '예약', 1, current, _go),
                _CameraNavItem(onTap: () => context.push('/camera')),
                _NavItem(RiseIcons.chart, '기록', 2, current, _go),
                _NavItem(RiseIcons.person, '마이', 3, current, _go),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 항목의 공통 껍데기 — 위에 [_kFabRaise]만큼 투명 헤드룸을 두고, 콘텐츠는 아래
/// 막대(62) 안에 가운데 정렬한다. 그리는 위치는 헤드룸 도입 전과 같고 **히트 영역만**
/// 위로 넓어진다. 탭 대상(`InkWell`)이 이 껍데기를 **감싸야** 의미가 있다.
///
/// 높이는 고정이 아니라 **최소**다(P09 실기기 회귀). Pretendard를 번들하면서 9.5pt
/// 라벨의 줄높이가 폴백 폰트보다 커져 63px가 됐고 `height: 62`에서 1px 오버플로가 났다 —
/// 폰트·배율이 커지면 막대가 늘어나야 한다.
class _NavItemShell extends StatelessWidget {
  const _NavItemShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: _kFabRaise),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kBarHeight),
        child: Center(heightFactor: 1, child: child),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.svg, this.label, this.index, this.current, this.onTap);
  final String svg;
  final String label;
  final int index;
  final int current;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final on = index == current;
    final color = on ? AppColors.brand : AppColors.tabInactive;
    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: _NavItemShell(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RiseIcon(svg, size: 21, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 목업 `.cam-tab .ic`: 48x48 원, margin-top:-22px로 탭바 위로 띄움.
class _CameraNavItem extends StatelessWidget {
  const _CameraNavItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: _NavItemShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: const Offset(0, -_kFabRaise),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brand.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Center(
                  child: RiseIcon(RiseIcons.camera, size: 22, color: Colors.white),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -12),
              child: const Text(
                '촬영',
                // 선택 상태가 없다 — 탭이 아니라 진입 버튼이다.
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.tabInactive,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
