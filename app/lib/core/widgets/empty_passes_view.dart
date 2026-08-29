import 'package:flutter/material.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_button.dart';

/// 발급된 회원권이 0개인 상태(EmptyPassesFailure) — 에러 뷰가 아니라 온보딩
/// 성격의 안내용 빈 상태 뷰(데드엔드 방지). 홈·예약 탭이 공용으로 사용한다.
///
/// [title]/[message]는 **같은 골격에 문구만 갈아끼우기 위한** 것이다(state_view_parity
/// 규약 — 아이콘 34 → 제목 14/w900 → 설명 11.5 → 버튼). 홈은 "회원권이 0개"와
/// "가진 회원권이 전부 만료·환불"을 서로 다른 문장으로 말해야 하는데, 두 상태에
/// 각각 다른 모양의 뷰를 만들면 같은 자리에서 앱이 두 개처럼 보인다.
class EmptyPassesView extends StatelessWidget {
  const EmptyPassesView({
    super.key,
    required this.onRefresh,
    this.title = '아직 회원권이 없어요',
    this.message = '센터에서 회원권 등록 후 이용할 수 있어요',
  });

  final VoidCallback onRefresh;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RiseIcon(RiseIcons.fileText, size: 34, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 14),
            RiseButton(label: '새로고침', small: true, onPressed: onRefresh),
          ],
        ),
      ),
    );
  }
}
