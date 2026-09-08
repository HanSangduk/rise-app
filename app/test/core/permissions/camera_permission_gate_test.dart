import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';

/// [PermissionHandlerCameraGate]의 불변식 — "아직 묻지 않은 상태(iOS NotDetermined = status
/// denied)는 **반드시 시스템 프롬프트(request)에 닿는다**". 2026-09-07 App Store 리젝 5.1.1(iv)
/// (work_log/P67)의 네이티브 원인(매크로 누락)은 Dart에서 재현할 수 없지만, Dart 쪽 절반인
/// "denied면 한 번 request한다 / 그 밖의 상태에선 request하지 않는다"는 여기서 못 박는다.
/// 이 규약이 무너지면 매크로가 있어도 프롬프트가 안 뜬다.
void main() {
  late _FakePlatform platform;

  setUp(() {
    platform = _FakePlatform();
    PermissionHandlerPlatform.instance = platform;
  });

  const gate = PermissionHandlerCameraGate();

  test('status denied(아직 안 물어봄) → request를 정확히 한 번 부르고, 허용이면 granted', () async {
    platform.status = PermissionStatus.denied;
    platform.requestResult = PermissionStatus.granted;

    expect(await gate.ensureGranted(), CameraPermissionResult.granted);
    expect(platform.requestCalls, 1);
    expect(platform.requested, [Permission.camera]);
  });

  test('프롬프트에서 "허용 안 함" → permanentlyDenied(설정 경로) — 프롬프트 뒤에만 설정 안내', () async {
    platform.status = PermissionStatus.denied;
    platform.requestResult = PermissionStatus.permanentlyDenied;

    expect(await gate.ensureGranted(), CameraPermissionResult.permanentlyDenied);
    expect(platform.requestCalls, 1);
  });

  test('request가 denied를 되돌려도(안드로이드 일시 거부) denied — 다시 물어볼 수 있는 상태', () async {
    platform.status = PermissionStatus.denied;
    platform.requestResult = PermissionStatus.denied;

    expect(await gate.ensureGranted(), CameraPermissionResult.denied);
  });

  test('이미 granted / limited 면 request 없이 통과', () async {
    for (final s in [PermissionStatus.granted, PermissionStatus.limited]) {
      platform.status = s;
      expect(await gate.ensureGranted(), CameraPermissionResult.granted, reason: '$s');
    }
    expect(platform.requestCalls, 0);
  });

  test('이미 permanentlyDenied / restricted 면 request 없이 설정 경로', () async {
    for (final s in [PermissionStatus.permanentlyDenied, PermissionStatus.restricted]) {
      platform.status = s;
      expect(await gate.ensureGranted(), CameraPermissionResult.permanentlyDenied, reason: '$s');
    }
    expect(platform.requestCalls, 0);
  });

  test('플러그인이 없는 환경(MissingPluginException)은 unsupported — 권한으로 막지 않는다', () async {
    platform.throwOnStatus = true;
    expect(await gate.ensureGranted(), CameraPermissionResult.unsupported);
  });

  test('openSettings는 플랫폼의 openAppSettings로 간다', () async {
    await gate.openSettings();
    expect(platform.openSettingsCalls, 1);
  });
}

class _FakePlatform extends PermissionHandlerPlatform with MockPlatformInterfaceMixin {
  PermissionStatus status = PermissionStatus.denied;
  PermissionStatus requestResult = PermissionStatus.granted;
  bool throwOnStatus = false;
  int requestCalls = 0;
  int openSettingsCalls = 0;
  final requested = <Permission>[];

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    if (throwOnStatus) throw MissingPluginException('no plugin');
    return status;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(List<Permission> permissions) async {
    requestCalls++;
    requested.addAll(permissions);
    return {for (final p in permissions) p: requestResult};
  }

  @override
  Future<bool> openAppSettings() async {
    openSettingsCalls++;
    return true;
  }
}
