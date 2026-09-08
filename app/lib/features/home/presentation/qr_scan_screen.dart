import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/camera_permission_view.dart';
import 'package:rise_member/core/widgets/rise_button.dart';

/// 데스크 셀프 체크인 QR 스캐너(P44).
///
/// 스캔에 성공하면 **QR의 원문 문자열**을 담아 pop한다 — 검증(토큰 일치 · 예약 시작
/// ±30분 · 본인 확정 예약 자동 탐색)은 전부 서버가 한다. 앱이 토큰 모양을 미리
/// 판정하면 데스크 QR을 바꾼 날 앱이 먼저 막아버려 서버 문구가 회원에게 닿지 않는다.
/// 취소(뒤로가기·취소 버튼)면 null로 pop한다.
///
/// 사용:
/// ```dart
/// final token = await Navigator.of(context, rootNavigator: true)
///     .push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
/// ```
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> with WidgetsBindingObserver {
  /// 컨트롤러를 직접 소유한다 — [MobileScanner]는 컨트롤러를 넘기지 않을 때만
  /// 스스로 생명주기를 챙긴다(mobile_scanner 7.4.0 `_initializeController`).
  /// QR만 읽도록 포맷을 좁히려면 컨트롤러가 필요하므로, 백그라운드 전환 시
  /// 카메라를 내리는 일도 이 화면이 직접 한다.
  MobileScannerController? _controller;
  StreamSubscription<BarcodeCapture>? _barcodes;

  CameraPermissionResult? _permission;

  /// 연속 프레임에서 같은 QR이 여러 번 잡힌다 — 첫 값으로만 pop한다.
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_requestPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 구독을 먼저 끊고 컨트롤러를 버린다 — 순서가 반대면 dispose 직후 도착한
    // 프레임이 이미 unmount된 State의 setState/pop을 호출한다.
    unawaited(_barcodes?.cancel());
    _barcodes = null;
    unawaited(_controller?.dispose());
    _controller = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(controller.start());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // 홈 버튼·전화 수신으로 화면을 떠나면 카메라를 붙잡고 있지 않는다(배터리·발열).
        unawaited(controller.stop());
    }
  }

  Future<void> _requestPermission() async {
    final result = await ref.read(cameraPermissionGateProvider).ensureGranted();
    if (!mounted) return;
    setState(() {
      _permission = result;
      // unsupported(플러그인 없음)는 막지 않고 스캐너에 맡긴다 — 실패하면
      // MobileScanner의 errorBuilder가 문구를 띄운다.
      if (result == CameraPermissionResult.granted ||
          result == CameraPermissionResult.unsupported) {
        _controller = MobileScannerController(
          // 데스크 QR만 읽는다 — 헬스장 기구의 바코드가 잡혀 서버로 가는 걸 막는다.
          formats: const [BarcodeFormat.qrCode],
          detectionSpeed: DetectionSpeed.noDuplicates,
          facing: CameraFacing.back,
        );
        _barcodes = _controller!.barcodes.listen(_onDetect, onError: (_, __) {});
      }
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _handled = true;
      // stop을 await하지 않고 곧바로 닫는다 — dispose가 어차피 정리하고,
      // 여기서 기다리면 셔터가 닫히는 동안 다음 프레임이 또 들어온다.
      if (mounted) Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final permission = _permission;
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('체크인 QR 스캔'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '취소',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: switch (permission) {
          null => const Center(child: CircularProgressIndicator(color: AppColors.brand)),
          CameraPermissionResult.denied || CameraPermissionResult.permanentlyDenied =>
            CameraPermissionView(
              result: permission,
              purpose: '데스크의 체크인 QR을 읽으려면',
              onRetry: () {
                setState(() => _permission = null);
                unawaited(_requestPermission());
              },
              onOpenSettings: () =>
                  unawaited(ref.read(cameraPermissionGateProvider).openSettings()),
              onCancel: () => Navigator.of(context).pop(),
            ),
          _ => controller == null
              ? const SizedBox.shrink()
              : Stack(
                  children: [
                    Positioned.fill(
                      child: MobileScanner(
                        controller: controller,
                        errorBuilder: (context, error) => _ScannerError(
                          error: error,
                          onOpenSettings: () => unawaited(
                            ref.read(cameraPermissionGateProvider).openSettings(),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 28,
                      child: _ScanHint(),
                    ),
                  ],
                ),
        },
      ),
    );
  }
}

class _ScanHint extends StatelessWidget {
  const _ScanHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 28),
      child: Text(
        '데스크에 붙은 체크인 QR을 화면 가운데에 맞춰주세요\n'
        '수업 시작 30분 전부터 30분 후까지 체크인할 수 있어요',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 11.5, height: 1.6),
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error, required this.onOpenSettings});
  final MobileScannerException error;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    // 스캐너가 자체 판정한 권한 거부 — permission_handler가 granted를 준 뒤에도
    // 시스템이 막는 경우(사용 중 권한 회수)가 있어 여기서도 설정 경로를 준다.
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return CameraPermissionView(
        result: CameraPermissionResult.permanentlyDenied,
        purpose: '데스크의 체크인 QR을 읽으려면',
        onRetry: () => Navigator.of(context).pop(),
        onOpenSettings: onOpenSettings,
        onCancel: () => Navigator.of(context).pop(),
      );
    }

    // 권한 외 실패(카메라 점유·미지원 기기 등) — 권한 안내로 오도하지 않는다.
    // 앱 안에서 할 수 있는 게 없으니 데스크 태그(스태프 tap 체크인)로 보낸다.
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '카메라를 열지 못했어요',
            style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            '다른 앱이 카메라를 쓰고 있을 수 있어요. 앱을 다시 실행해도 안 되면 '
            '데스크에 말씀해주세요 — 코치가 직접 체크인해 드립니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.5),
          ),
          const SizedBox(height: 14),
          RiseButton(label: '닫기', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}
