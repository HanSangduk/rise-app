import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';

part 'body_camera_provider.g.dart';

/// 체형 촬영 프리뷰의 상태. 화면은 이 셋 중 하나만 그린다.
sealed class BodyCameraState {
  const BodyCameraState();
}

/// 프리뷰를 그릴 수 있다.
final class BodyCameraReady extends BodyCameraState {
  const BodyCameraReady(this.controller);
  final CameraController controller;

  /// **세로 프레임 기준** 종횡비(width / height). `previewSize`는 센서 방향(가로
  /// 기준)으로 오므로 뒤집어 준다.
  ///
  /// 화면이 이 값을 그대로 프레임에 쓰기 때문에 **프리뷰에 보이는 것이 곧 저장되는
  /// 사진**이 된다. 하드코딩한 비율을 쓰면 둘이 어긋나서, 회원이 격자에 맞춰 세운
  /// 자세가 파일에서는 프레임 밖에 있거나 여백이 더 붙는다.
  double get captureAspect => aspectFromPreviewSize(controller.value.previewSize);

  /// [previewSize] → **세로 프레임 기준** 종횡비. 순수 함수(테스트 대상).
  ///
  /// 뒤집는 이유: `previewSize`는 센서 방향(가로 기준)으로 온다. 그대로 쓰면 16/9가
  /// 되어 프레임이 가로로 눕는다. 0이나 음수가 오면(드라이버가 아직 값을 못 채운
  /// 순간) 프레임이 붕괴하므로 기본값으로 떨어진다.
  static double aspectFromPreviewSize(Size? previewSize) {
    final s = previewSize;
    if (s == null || s.width <= 0 || s.height <= 0) return defaultCaptureAspect;
    return s.height / s.width;
  }

  /// 카메라가 준비되기 전에 쓸 값. 프레임이 0으로 붕괴하거나 준비 직후 크게
  /// 튀지 않게, 요즘 기기의 흔한 세로 촬영 비율(9:16)로 둔다.
  static const defaultCaptureAspect = 9 / 16;
}

/// 권한이 없어 못 연다 — [permission]으로 일시/영구 거부를 구분해 안내가 갈린다.
final class BodyCameraBlocked extends BodyCameraState {
  const BodyCameraBlocked(this.permission);
  final CameraPermissionResult permission;
}

/// 카메라가 없거나 초기화가 실패했다(에뮬레이터·테스트·하드웨어 오류).
/// 오버레이는 그대로 두고 프리뷰 자리에만 문구를 얹는다 — 화면이 깨지지 않게.
final class BodyCameraFailed extends BodyCameraState {
  const BodyCameraFailed(this.message);
  final String message;
}

/// 체형 촬영용 [CameraController] 수명주기 소유자.
///
/// **autoDispose인 게 핵심이다.** 촬영 탭은 `StatefulShellRoute.indexedStack`
/// 안에 있어 다른 탭으로 가도 위젯이 트리에 남는다(IndexedStack + maintainState).
/// 화면이 안 보일 때 이 provider를 watch하지 않으면 구독이 0이 되어 provider가
/// 버려지고, `ref.onDispose`가 카메라를 닫는다 — 홈 탭에서 카메라가 계속 켜져
/// 배터리를 먹고 기기가 뜨거워지는 걸 이 한 줄이 막는다(camera_screen.dart의
/// TickerMode 판정과 짝).
@riverpod
class BodyCamera extends _$BodyCamera {
  CameraController? _controller;
  bool _disposed = false;

  @override
  Future<BodyCameraState> build() async {
    ref.onDispose(() {
      _disposed = true;
      // dispose()는 멱등하다(camera 0.12.0+2: _isDisposed면 즉시 return).
      unawaited(_controller?.dispose());
      _controller = null;
    });

    final permission = await ref.read(cameraPermissionGateProvider).ensureGranted();
    if (permission == CameraPermissionResult.denied ||
        permission == CameraPermissionResult.permanentlyDenied) {
      return BodyCameraBlocked(permission);
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return const BodyCameraFailed('사용할 수 있는 카메라가 없어요');
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // enableAudio: false — 사진만 찍는다. true면 안드로이드 병합 매니페스트의
      // RECORD_AUDIO가 실제로 요구되고, 회원에게 마이크 권한을 묻게 된다.
      //
      // veryHigh(1080p): 어깨·골반 기울기를 몇 달 뒤 사진과 비교하는 용도라
      // high(720p)로는 디테일이 아쉽고, ultraHigh(4K)는 JPEG 한 장이 5~8MB로
      // 커져 storage.rules의 10MB 상한(BodyPhotoStoragePath.maxUploadBytes)에
      // 위험하게 붙는다. 1080p JPEG은 보통 0.5~1.5MB로 여유가 크다.
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();

      // 초기화가 끝나기 전에 화면을 벗어났을 수 있다 — 그 사이 onDispose가 돌았다면
      // 여기서 다시 정리하고 준비 완료라고 말하지 않는다(유령 프리뷰 방지).
      if (_disposed) {
        unawaited(controller.dispose());
        return const BodyCameraFailed('카메라를 닫았어요');
      }
      return BodyCameraReady(controller);
    } on CameraException catch (e) {
      _controller = null;
      // 시스템이 권한을 회수한 경우도 여기로 온다(플랫폼별 코드가 제각각이라
      // 문자열 포함으로 판정 — 권한 안내로 보내야 회원이 다음 행동을 안다).
      final code = e.code.toLowerCase();
      if (code.contains('permission') || code.contains('access')) {
        return const BodyCameraBlocked(CameraPermissionResult.permanentlyDenied);
      }
      return const BodyCameraFailed('카메라를 열지 못했어요 — 앱을 다시 실행해주세요');
    } catch (_) {
      // MissingPluginException(위젯 테스트)·미지원 플랫폼 — 화면은 오버레이만 그린다.
      _controller = null;
      return const BodyCameraFailed('이 기기에서는 카메라를 쓸 수 없어요');
    }
  }

  /// 셔터 — JPEG 바이트를 돌려준다. 준비 안 됐거나 실패하면 null.
  ///
  /// [XFile]은 플랫폼 임시 디렉터리에 떨어진다. 바이트를 읽은 뒤 **파일을 지운다**
  /// — 체형 사진(민감정보)이 앱 캐시에 남아 다른 앱의 캐시 정리 도구나 기기 백업에
  /// 딸려 나가지 않게. 삭제 실패는 무시한다(업로드는 이미 바이트로 끝난다).
  Future<Uint8List?> takeJpeg() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    if (controller.value.isTakingPicture) return null; // 셔터 연타 방어.
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      unawaited(_deleteQuietly(file));
      return bytes;
    } on CameraException {
      return null;
    }
  }

  Future<void> _deleteQuietly(XFile file) async {
    try {
      await File(file.path).delete();
    } catch (_) {
      // 이미 없거나 권한 문제 — 업로드는 바이트로 끝났으므로 무시한다.
    }
  }
}
