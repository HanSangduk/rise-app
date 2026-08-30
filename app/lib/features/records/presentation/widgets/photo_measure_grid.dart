import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/grid_overlay.dart';

/// 저장된 체형 사진 위에 **계측 격자**를 얹는다(P46).
///
/// ## 왜 필요한가
/// 촬영 화면에는 격자가 있는데 **저장된 파일에는 없었다** — `takePicture()`가 카메라
/// 원본 JPEG을 그대로 주고, 격자는 프리뷰 위에 얹힌 CustomPaint였기 때문이다. 그래서
/// 회원이 두 장을 나란히 놓고도 "어깨가 몇 칸 내려왔나"를 읽을 수 없었다(비교 화면의
/// 존재 이유가 반쯤 비어 있었다 — body_photo_timeline.dart가 이 결함을 주석으로
/// 자각하고 있었다).
///
/// ## 왜 사진에 굽지 않고 표시할 때 그리는가
/// 촬영 시 픽셀에 구우면 (a) 되돌릴 수 없고 (b) 격자 선이 덮은 몇 픽셀만큼 어깨선
/// 판독에 오차가 되며(grid_overlay.dart가 "굵은 선은 그 자체가 오차"라고 적어 둔
/// 이유와 같다) (c) 촬영 세션마다 다른 밀도로 구워지면 두 사진의 눈금이 서로 달라
/// **비교 자체가 성립하지 않는다.** 표시할 때 그리면 두 장에 언제나 **같은 눈금**이
/// 올라가고, 나중에 더 촘촘한 눈금으로 다시 볼 수도 있다. 원본은 손대지 않는다.
///
/// ## 좌표계
/// 격자는 **이미지 실영역**에 그려야 한다. 타일은 3:4인데 사진은 보통 9:16이라
/// `BoxFit.contain`이 좌우에 레터박스를 남기고, 그 위에 통짜로 그리면 눈금이 사진
/// 밖으로 새어 위치가 어긋난다. 그래서 이미지의 실제 비율을 얻어
/// `AspectRatio`로 페인트 박스 == 이미지 박스를 만든 뒤 그 위에 그린다.
class MeasureGridPhoto extends StatefulWidget {
  const MeasureGridPhoto({
    super.key,
    required this.bytes,
    required this.showGrid,
    this.density = GridDensity.coarse,
    this.refLine,
    this.cacheWidth,
    this.overlay,
  });

  final Uint8List bytes;
  final bool showGrid;
  final GridDensity density;

  /// 두 사진이 **공유하는** 가로 기준선(0~1). null이면 그리지 않는다.
  ///
  /// 공유가 핵심이다 — 기준 사진의 어깨에 선을 맞춰 두면 비교 사진에서 그 선이
  /// 어깨 위·아래 어디에 걸리는지가 곧 변화량이다. 사진마다 다른 선을 그리면
  /// 눈금자가 두 개인 셈이라 아무것도 못 잰다.
  final double? refLine;

  /// 타일처럼 작은 자리에서 디코드 해상도를 낮춘다(뷰어는 null — 확대가 목적).
  final int? cacheWidth;

  /// 이미지 위(격자 아래)에 얹을 것 — 날짜·역할 pill 등. 이미지 실영역 기준으로
  /// 배치되므로 레터박스에 떠 있지 않는다.
  final Widget? overlay;

  @override
  State<MeasureGridPhoto> createState() => _MeasureGridPhotoState();
}

class _MeasureGridPhotoState extends State<MeasureGridPhoto> {
  /// 이미지 가로/세로 비. 디코드 전에는 null이라 그동안은 격자를 그리지 않는다
  /// (모르는 비율로 그리면 눈금이 틀린 자리에 간다 — 없는 것보다 나쁘다).
  double? _aspect;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// **initState가 아니라 여기서** 해석한다 — `createLocalImageConfiguration`이
  /// MediaQuery(devicePixelRatio)에 의존해서, initState에서 부르면 Flutter가
  /// "dependOnInheritedWidgetOfExactType before initState completed"로 던진다.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream == null) _resolve();
  }

  @override
  void didUpdateWidget(MeasureGridPhoto old) {
    super.didUpdateWidget(old);
    if (!identical(old.bytes, widget.bytes)) {
      _aspect = null;
      _resolve();
    }
  }

  /// 이미지 비율을 얻는다 — **추가 디코드가 아니다.** Flutter 이미지 캐시에 붙어
  /// 어차피 일어날 디코드의 결과를 받아 온다(별도 `decodeImageFromList`를 부르면
  /// 같은 사진을 두 번 디코드하게 된다).
  void _resolve() {
    _detach();
    final stream = MemoryImage(widget.bytes).resolve(
      createLocalImageConfiguration(context),
    );
    final listener = ImageStreamListener((info, _) {
      final aspect = info.image.width / info.image.height;
      if (mounted && _aspect != aspect) setState(() => _aspect = aspect);
    }, onError: (_, __) {});
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _detach() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = Image.memory(
      widget.bytes,
      fit: BoxFit.contain,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
    );
    final aspect = _aspect;
    if (aspect == null || !aspect.isFinite || aspect <= 0) {
      // 비율 확정 전 — 사진만 그린다(격자는 자리를 못 잡으므로).
      return widget.overlay == null
          ? image
          : Stack(fit: StackFit.expand, children: [image, widget.overlay!]);
    }
    return Center(
      child: AspectRatio(
        // 페인트 박스를 이미지 실영역에 정확히 포갠다 — 이 한 줄이 레터박스 어긋남을 없앤다.
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (widget.showGrid)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: MeasureGridPainter(
                      density: widget.density,
                      refLine: widget.refLine,
                    ),
                  ),
                ),
              ),
            if (widget.overlay case final overlay?) overlay,
          ],
        ),
      ),
    );
  }
}

/// 계측 격자 페인터 — 촬영 격자([GridOverlay])와 **같은 정규화 좌표계**를 쓴다.
///
/// 촬영 쪽 페인터를 그대로 재사용하지 않는 이유: 그쪽엔 발위치 마커·드래그 손잡이처럼
/// **촬영을 돕는 장치**가 붙어 있는데, 다 찍은 사진 위에서는 아무 의미가 없고 시야만
/// 가린다. 눈금(격자·중심선·기준선)만 가져온다.
class MeasureGridPainter extends CustomPainter {
  const MeasureGridPainter({required this.density, this.refLine});

  final GridDensity density;
  final double? refLine;

  @override
  void paint(Canvas canvas, Size size) {
    // 사진은 밝은 벽부터 어두운 옷까지 섞여 있어 **한 가지 색으로는 어디선가 사라진다.**
    // 검은 그림자선을 먼저 깔고 그 위에 흰 선을 얹어 어떤 배경에서도 읽히게 한다
    // (촬영 프리뷰는 대체로 어두워서 흰 선만으로 충분했다).
    void line(Offset a, Offset b, double width, double alpha) {
      canvas.drawLine(
        a.translate(0.5, 0.5),
        b.translate(0.5, 0.5),
        Paint()
          ..color = Colors.black.withValues(alpha: alpha * 0.5)
          ..strokeWidth = width,
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..strokeWidth = width,
      );
    }

    for (var i = 1; i < density.cols; i++) {
      final x = size.width * i / density.cols;
      final major = i % density.majorEvery == 0;
      line(Offset(x, 0), Offset(x, size.height), major ? 1 : 0.5,
          major ? 0.55 : 0.28);
    }
    for (var i = 1; i < density.rows; i++) {
      final y = size.height * i / density.rows;
      final major = i % density.majorEvery == 0;
      line(Offset(0, y), Offset(size.width, y), major ? 1 : 0.5,
          major ? 0.55 : 0.28);
    }

    // 중심 수직선 — 좌우 대칭(어깨 기울기·골반 틀어짐)을 읽는 축.
    line(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), 1, 0.5);

    // 공유 기준선 — 두 사진에 같은 높이로 올라간다. 얇게 긋는다: 굵은 선은 그
    // 자체가 몇 픽셀을 덮어 "어디에 맞췄는지"를 흐린다(촬영 격자와 같은 규약).
    if (refLine case final ref?) {
      final y = size.height * ref.clamp(0.02, 0.98);
      canvas.drawLine(
        Offset(0, y + 0.5),
        Offset(size.width, y + 0.5),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..strokeWidth = 1.2,
      );
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = AppColors.camCrosshair
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MeasureGridPainter old) =>
      old.density != density || old.refLine != refLine;
}
