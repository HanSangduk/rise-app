import 'package:flutter/material.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_button.dart';

/// 탭 공용 에러 뷰 — 아이콘 + 제목 + 사유 + "다시 시도" 버튼
/// (호출부가 해당 VM invalidate 전달). 4개 탭(홈/예약/기록/마이)의
/// AsyncValue error 브랜치에서 공용으로 사용한다.
///
/// 골격은 [EmptyPassesView]와 **의도적으로 동일**하다(아이콘 34 → 제목 14/w900 →
/// 설명 11.5 → 버튼, 바깥 `Center` + `padding: all(24)`). 두 뷰는 같은 자리에
/// 교대로 나타난다 — 회원권 0개면 아이콘 있는 화면, 네트워크 오류면 맨 문단이라
/// 같은 탭이 새로고침할 때마다 다른 앱처럼 보였다. 아이콘·제목만 갈아끼우면
/// 같은 화면의 두 상태로 읽힌다.
class RiseErrorView extends StatelessWidget {
  const RiseErrorView({super.key, this.message, required this.onRetry});

  /// 실패 사유(서버/네트워크 문구) — 제목이 "무슨 일"인지 말하고, 이 줄이 "왜"를
  /// 말한다. 사유를 모르면 null — 예전엔 호출부가 '문제가 생겼어요'를 폴백으로
  /// 넘겼는데 그건 이제 **제목**이라, 그대로 두면 같은 문장이 두 줄로 겹친다.
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RiseIcon(RiseIcons.alertTriangle, size: 34, color: AppColors.muted),
            const SizedBox(height: 12),
            const Text('문제가 생겼어요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              // 사유를 모를 때 원인을 지어내지 않는다("네트워크를 확인하세요"는
              // 서버 5xx일 수도 있다) — 다음 행동만 말한다.
              message ?? '잠시 후 다시 시도해주세요',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 14),
            RiseButton(label: '다시 시도', small: true, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
