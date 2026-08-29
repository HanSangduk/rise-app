import 'package:flutter/material.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';

/// 배경 확인 안내 — **다른 사람이 함께 찍히지 않게** 회원이 직접 보고 비켜 서라는 말.
///
/// 종전 문구는 "배경에 다른 사람이 감지됐어요 — 저장할 때 자동으로 흐림 처리합니다"였다.
/// 둘 다 사실이 아니었다: 감지 상태(`backgroundPersonDetected`)는 `true`로 고정돼 아무도
/// 갱신하지 않았고, 업로드는 언제나 `blurred: false`로 나갔다. 사람 많은 헬스장에서
/// 그 문구를 믿고 찍은 사진에 남의 얼굴이 그대로 남는다 — 안내가 아예 없느니만 못하다.
///
/// 그래서 **지킬 수 있는 말만** 남겼다. 감지·블러를 실제로 붙이기 전까지는 이게 최선이고,
/// 붙이는 날 이 위젯을 감지 상태에 다시 연결하면 된다(그때는 danger 톤이 맞다).
class BackgroundPersonBanner extends StatelessWidget {
  const BackgroundPersonBanner({super.key});

  @override
  Widget build(BuildContext context) {
    // **자리를 스스로 정하지 않는다.** 종전엔 `Positioned`라 프리뷰 Stack 안에서만
    // 쓸 수 있었는데, 프리뷰가 화면 전체를 쓰게 되면서 이 주의문은 하단 컨트롤 존
    // (Column)으로 옮겨졌다. 배치는 쓰는 쪽이 정하게 둔다.
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          // 지금 뭔가 잘못됐다는 뜻이 아니라 늘 붙어 있는 주의문이라 danger가 아니다.
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: AppColors.camWarnBorder.withValues(alpha: 0.5)),
          // 반경 9는 목업 `.camwrap .warnbg`의 값 — 일회성이라 토큰으로 올리지 않는다.
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Row(
          children: [
            RiseIcon(RiseIcons.users, size: 14, color: AppColors.camWarnFg),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                '뒤에 다른 사람이 함께 찍히지 않는지 확인해주세요',
                style: TextStyle(fontSize: 10, color: AppColors.camWarnFg, height: 1.4),
              ),
            ),
          ],
        ),
    );
  }
}
