import 'package:flutter/material.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_button.dart';

/// 카메라 권한이 없을 때 프리뷰 자리에 대신 들어가는 안내 — QR 스캐너·체형 촬영 공용.
///
/// 일시 거부와 영구 거부의 **행동이 다르다**: 전자는 앱 안에서 다시 물어볼 수 있고,
/// 후자는 시스템 설정에서만 켤 수 있다. 같은 버튼을 보여주면 영구 거부한 회원은
/// 눌러도 아무 일도 안 일어나는 버튼 앞에 갇힌다(camera_permission.dart 주석).
class CameraPermissionView extends StatelessWidget {
  const CameraPermissionView({
    super.key,
    required this.result,
    required this.purpose,
    required this.onRetry,
    required this.onOpenSettings,
    this.note,
    this.onCancel,
    this.dark = true,
  });

  /// [CameraPermissionResult.granted]가 아닌 값만 온다.
  final CameraPermissionResult result;

  /// "체크인 QR을 읽으려면" 처럼 **왜 필요한지** — 문장 앞머리에 붙는다.
  final String purpose;

  /// 요청 문장 뒤에 덧붙는 **용도별 사실 한 문장**(예: 체형 촬영의 "찍은 사진을
  /// 누가 보는지"). null이면 아무 말도 덧붙이지 않는다.
  ///
  /// 공용 위젯에 문장을 박아 두면 한 용도의 사실이 다른 용도에선 거짓이 된다 —
  /// 실제로 "사진은 …만 볼 수 있게 저장돼요"가 사진을 저장하지도 않는 QR 스캔
  /// 화면에 그대로 붙어 있었다. 그래서 문장은 각 호출부가 자기 용도의 사실만
  /// 가져온다.
  final String? note;

  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback? onCancel;

  /// 어두운 프리뷰 자리에 얹히는지(스캐너·카메라 프레임) 여부 — 밝은 카드 위면 false.
  final bool dark;

  bool get _permanent => result == CameraPermissionResult.permanentlyDenied;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppColors.ink;
    final subFg = dark ? Colors.white70 : AppColors.muted;

    return Container(
      color: dark ? Colors.black : null,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RiseIcon(RiseIcons.camera, size: 28, color: subFg),
          const SizedBox(height: 12),
          Text(
            _permanent ? '카메라 권한이 꺼져 있어요' : '카메라 권한이 필요해요',
            textAlign: TextAlign.center,
            style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            _permanent
                // 영구 거부에서는 [note]를 붙이지 않는다 — 이 화면의 유일한 다음
                // 행동은 설정 경로라, 그 앞에 다른 문장이 끼면 경로가 묻힌다.
                // 경로는 플랫폼 중립으로 — iOS는 설정 > (앱 이름) > 카메라이고 "권한" 항목이
                // 없어 종전의 안드로이드식 "설정 > 권한 > 카메라"가 iOS에선 거짓 안내였다(P67).
                ? '$purpose 카메라 권한이 필요해요. 설정 앱에서 이 앱의 카메라 권한을 켠 뒤 다시 들어와주세요.'
                : '$purpose 카메라 권한이 필요해요.${note == null ? '' : ' $note'}',
            textAlign: TextAlign.center,
            style: TextStyle(color: subFg, fontSize: 11.5, height: 1.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (_permanent)
                RiseButton(label: '설정 열기', onPressed: onOpenSettings)
              else
                RiseButton(label: '권한 허용하기', onPressed: onRetry),
              if (onCancel != null)
                // 어두운 배경에서는 outline 버튼의 글자색(ink)이 거의 안 보인다
                // — 취소는 텍스트 버튼으로 두고 색만 배경에 맞춘다.
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(foregroundColor: fg),
                  child: const Text('취소'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
