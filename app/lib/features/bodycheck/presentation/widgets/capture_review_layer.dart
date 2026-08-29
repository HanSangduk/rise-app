import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';

/// 방금 찍은 사진을 **올리기 전에** 보여주고 회원의 판단을 받는 층.
///
/// ## 왜 필요한가
///
/// 종전에는 셔터가 눌리는 즉시 Storage와 서버로 갔다. 되돌리려면 저장된 뒤에
/// 기록 탭에서 지우는 수밖에 없었는데, 그 시점엔 이미 **민감정보(P8)가 서버에
/// 올라간 뒤**다.
///
/// 자동 촬영에서는 이게 이론이 아니라 실제로 터졌다. 자동 촬영은 사람이 프레임
/// 안에 있는지 알 방법이 없다 — **수평만 본다.** 그래서 책상에 세워 둔 폰이 빈
/// 방을 찍어 그대로 올렸고, 버킷에 쓰레기가 50장 쌓였다. 눈이 한 번 보고
/// 통과시킨 것만 나가야 한다.
///
/// ## 화면을 덮는 이유
///
/// 프리뷰 위에 작은 섬네일로 얹으면 회원이 **작은 그림을 보고 판단**하게 된다.
/// 흔들렸는지·잘렸는지·뒤에 사람이 지나갔는지는 그 크기에서 안 보인다. 판단을
/// 요구하려면 판단할 수 있는 크기를 줘야 한다.
///
/// ## 두 버튼의 무게가 다르다
///
/// 「다시 찍기」는 **아무것도 올라가지 않았으므로 잃을 게 없다**(테두리 버튼).
/// 「이 사진으로 저장」이 되돌리기 어려운 쪽이라 채운 버튼이다.
class CaptureReviewLayer extends StatelessWidget {
  const CaptureReviewLayer({
    super.key,
    required this.bytes,
    required this.poseLabel,
    required this.submitting,
    required this.onRetake,
    required this.onConfirm,
  });

  final Uint8List bytes;
  final String poseLabel;
  final bool submitting;
  final VoidCallback onRetake;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    '$poseLabel · 이대로 저장할까요?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    bytes,
                    // **저장될 파일 그대로 보여준다.** 촬영 프리뷰는 `BoxFit.cover`로
                    // 잘라 채우지만 파일에는 프레임 밖까지 들어 있다 — 여기서까지
                    // 잘라 보여주면 회원이 승인한 그림과 저장되는 그림이 달라진다.
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                '얼굴·뒷사람이 함께 찍혔거나 흔들렸으면 다시 찍어주세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ReviewButton(
                      label: '다시 찍기',
                      filled: false,
                      onPressed: submitting ? null : onRetake,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _ReviewButton(
                      label: submitting ? '저장 중…' : '이 사진으로 저장',
                      filled: true,
                      onPressed: submitting ? null : onConfirm,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      // 촬영 화면은 폰을 세워 두고 물러났다 돌아와서 누르는 자리라 타깃을 넉넉히 준다.
      height: 52,
      child: Material(
        color: filled
            ? (disabled ? AppColors.red.withValues(alpha: 0.5) : AppColors.red)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: filled
              ? BorderSide.none
              : BorderSide(color: Colors.white.withValues(alpha: 0.45)),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: disabled ? 0.7 : 1),
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
