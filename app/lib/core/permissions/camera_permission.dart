import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'camera_permission.g.dart';

/// 카메라 권한 판정 결과 — **일시 거부와 영구 거부를 구분**한다.
///
/// mobile_scanner·camera 두 패키지 모두 자체적으로 권한을 요청하지만,
/// 돌려주는 건 "실패했다"뿐이라 화면이 안내를 나눌 수 없다. 일시 거부는 버튼 한 번으로
/// 다시 물어볼 수 있고, 영구 거부는 **앱 설정으로 보내는 것 말고는 방법이 없다** —
/// 두 경우에 같은 문구를 띄우면 영구 거부한 회원은 눌러도 아무 일도 안 나는 버튼 앞에
/// 갇힌다. 그래서 요청 자체는 permission_handler로 먼저 통과시킨다.
enum CameraPermissionResult {
  granted,

  /// 이번엔 거부 — 다시 물어볼 수 있다.
  denied,

  /// 영구 거부(안드로이드 "다시 묻지 않음") 또는 iOS restricted —
  /// 앱 안에서는 되돌릴 수 없고 시스템 설정에서만 켤 수 있다.
  permanentlyDenied,

  /// 권한 개념이 없거나 플러그인이 없는 환경(테스트·데스크톱) —
  /// 여기서 막지 않고 그대로 통과시켜 카메라 초기화 실패로 판정하게 둔다.
  unsupported,
}

/// 카메라 권한 게이트 — 화면/뷰모델이 permission_handler를 직접 부르지 않게 감싼다.
/// 테스트는 [cameraPermissionGateProvider]를 override해서 각 분기를 재현한다.
abstract interface class CameraPermissionGate {
  /// 필요하면 권한을 요청하고 최종 상태를 돌려준다.
  Future<CameraPermissionResult> ensureGranted();

  /// 시스템 설정 앱 열기(영구 거부 복구 경로).
  Future<void> openSettings();
}

/// iOS 주의: permission_handler_apple은 카메라 코드를 `PERMISSION_CAMERA=1` 매크로가 있을 때만
/// 컴파일한다(ios/Podfile post_install). 매크로가 빠지면 플러그인이 프롬프트 없이
/// status=denied → request=permanentlyDenied 를 돌려주고, 이 게이트는 그걸 "사용자가 거부했다"로
/// 읽어 곧장 설정 안내를 띄운다 — 2026-09-07 App Store 리젝 1.0(7) 5.1.1(iv)(work_log/P67).
/// Dart에서는 두 경우를 구분할 수 없으므로 방어선은 빌드 페이즈(ios/scripts/check_release_target.sh)다.
class PermissionHandlerCameraGate implements CameraPermissionGate {
  const PermissionHandlerCameraGate();

  @override
  Future<CameraPermissionResult> ensureGranted() async {
    try {
      var status = await Permission.camera.status;
      // 안드로이드는 "한 번도 안 물어본" 상태도 denied로 준다 — 그래서 denied면
      // 곧바로 판정하지 않고 반드시 한 번 요청해 본다(요청 후의 denied가 진짜 거부).
      // limited(iOS 사진 전용 상태 — 카메라엔 안 오지만)도 이미 허용이라 묻지 않는다.
      if (!status.isGranted && !status.isLimited && !status.isPermanentlyDenied && !status.isRestricted) {
        status = await Permission.camera.request();
      }
      if (status.isGranted || status.isLimited) return CameraPermissionResult.granted;
      // restricted(iOS 자녀보호 등)도 앱에서 되돌릴 수 없다 — 영구 거부와 같은 안내.
      if (status.isPermanentlyDenied || status.isRestricted) {
        return CameraPermissionResult.permanentlyDenied;
      }
      return CameraPermissionResult.denied;
    } catch (_) {
      // MissingPluginException(위젯 테스트) / 미지원 플랫폼 — 권한으로 막지 않는다.
      return CameraPermissionResult.unsupported;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {
      // 설정 앱을 못 여는 환경(테스트) — 조용히 무시(호출부가 안내 문구를 이미 띄웠다).
    }
  }
}

@riverpod
CameraPermissionGate cameraPermissionGate(Ref ref) => const PermissionHandlerCameraGate();
