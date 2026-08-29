import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/camera_permission_view.dart';
import 'package:rise_member/features/bodycheck/presentation/body_camera_provider.dart';

/// 오버레이(그리드·크로스헤어·수평계·포즈칩·고스트·경고) **뒤에 깔리는 실 프리뷰**.
///
/// **프레임 비율 = 카메라가 실제로 찍는 비율**([BodyCameraReady.captureAspect]).
/// 그래서 여기서 `BoxFit.cover`는 아무것도 잘라내지 않는다 — 비율이 같으면 cover와
/// contain이 같은 결과다. 이게 "보이는 대로 저장된다"를 성립시키는 지점이다.
///
/// 종전엔 프레임이 `AspectRatio(392/472)`로 고정돼 있었고(목업에서 이식한 숫자),
/// 카메라 비율이 다르면 **cover가 잘라냈다.** 회원은 잘린 그림을 보고 자세를
/// 맞췄는데 파일에는 프레임 밖까지 들어 있었다 — 3:4면 9.7%, 9:16이면 32.3%가
/// 화면에 없던 영역이다. 격자로 어깨선을 맞추라고 해 놓고 저장본은 다른 그림이었다.
///
/// 준비 전·실패·권한 거부에도 이 자리는 항상 목업의 그라데이션 배경으로 남는다 —
/// 오버레이가 투명한 구멍 위에 뜨는 일이 없게.
class CameraPreviewLayer extends ConsumerWidget {
  const CameraPreviewLayer({super.key, required this.active});

  /// 촬영 탭이 실제로 보이고 앱이 포그라운드일 때만 true.
  /// false면 provider를 **watch하지 않아** 카메라가 닫힌다(BodyCamera 주석).
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!active) return const SizedBox.expand();

    final async = ref.watch(bodyCameraProvider);
    return async.when(
      loading: () => const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      ),
      // build()가 던지는 경우는 없지만(모두 상태로 감쌌다) 안전망.
      error: (_, __) => const _PreviewNotice('카메라를 열지 못했어요'),
      data: (state) => switch (state) {
        BodyCameraReady(:final controller) => _Preview(controller: controller),
        BodyCameraFailed(:final message) => _PreviewNotice(message),
        BodyCameraBlocked(:final permission) => CameraPermissionView(
            result: permission,
            purpose: '체형 사진을 찍으려면',
            // 서버 checkBodyPhotoAccess와 같은 말이어야 한다: 본인 · 담당 코치 ·
            // 센터 대표(동의 유효 시). 종전의 "나와 담당 코치만"은 대표를 숨긴
            // 거짓이었다 — 좁혀 말한 안내를 믿고 동의한 회원에게는 기만이 된다.
            note: '사진은 촬영 즉시 나와 담당 코치, 센터 대표만 볼 수 있게 저장돼요.',
            onRetry: () => ref.invalidate(bodyCameraProvider),
            onOpenSettings: () => ref.read(cameraPermissionGateProvider).openSettings(),
          ),
      },
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return const SizedBox.expand();

    // previewSize는 센서 방향(가로 기준)으로 온다 — 세로 프레임에 맞추려면 뒤집는다.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          '$message\n오버레이 가이드는 그대로 쓸 수 있어요',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.camWarnFg, fontSize: 11.5, height: 1.5),
        ),
      ),
    );
  }
}
