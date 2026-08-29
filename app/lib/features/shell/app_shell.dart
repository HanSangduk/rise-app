import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';

/// 바텀 내비 셸 — 탭 **4개**(홈·예약·기록·마이) + 가운데 촬영 **버튼**.
///
/// 촬영은 탭이 아니다(P21): 전체화면 라우트를 rootNavigator 위로 push한다. 가운데 빨간
/// 원이 탭바 행에 있는 건 목업 `.cam-tab` 그대로지만, 눌렀을 때 브랜치를 바꾸는 게 아니라
/// 촬영 모드로 들어간다 — 그래서 이 버튼은 **선택 상태를 갖지 않는다**.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  // 탭 인덱스는 `AppTab`이 단일 출처다 — 카드 안 버튼도 같은 enum으로 이동한다
  // (core/router/tab_navigation.dart). 여기만 숫자를 받는 건 하단바가 순회 렌더라서다.
  void _go(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final current = navigationShell.currentIndex;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        child: Container(
          // 고정 높이가 아니라 **최소 높이**다(P09 실기기 회귀). 가운데 촬영 탭의 레이아웃 높이는
          // 원 48 + 라벨 줄높이인데, Pretendard를 번들하면서 9.5pt 라벨의 줄높이가 폴백 폰트보다
          // 미세하게 커져 63px가 됐고 `height: 62`에서 1px 오버플로가 났다. 폰트·배율이 바뀌어도
          // 다시 깨지지 않도록 내용이 더 크면 막대가 늘어나게 한다(평상시 렌더는 62 그대로).
          // `Transform.translate`는 그리기만 옮기고 레이아웃 높이는 줄이지 않는다.
          constraints: const BoxConstraints(minHeight: 62),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(RiseIcons.home, '홈', 0, current, _go),
              _NavItem(RiseIcons.calendar, '예약', 1, current, _go),
              _CameraNavItem(onTap: () => context.push('/camera')),
              _NavItem(RiseIcons.chart, '기록', 2, current, _go),
              _NavItem(RiseIcons.person, '마이', 3, current, _go),
            ],
          ),
        ),
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
    final color = on ? AppColors.red : AppColors.tabInactive;
    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(AppRadius.chip),
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
    );
  }
}

/// 목업 `.cam-tab .ic`: 48x48 빨간 원, margin-top:-22px로 탭바 위로 띄움.
class _CameraNavItem extends StatelessWidget {
  const _CameraNavItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(0, -18),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.red.withValues(alpha: 0.4),
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
    );
  }
}
