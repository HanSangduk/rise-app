import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';

/// 자필 서명 패드(P44 결정 1·5) — **그리기 단일**.
///
/// 법적 요건이 아니라 관행·체감·증거 보강이 목적이다(전자서명법 §2-2는 기술중립 —
/// 효력의 뿌리는 휴대폰 인증 계정 + 동의 행위고, 어떤 표식이든 유효하다). 그래서
/// 판정도 관대하다: 획 1개 이상 + 바운딩 박스가 패드 폭의 15% 이상이면 실제 표식으로
/// 본다(점 하나·스친 자국만 거른다).
///
/// 그림은 P32 계보(rise_mark) 그대로 위젯이 아니라 캔버스다 — 외부 패키지 없이
/// GestureDetector + CustomPainter로 긋고, 내보내기는 dart:ui PictureRecorder→PNG.
///
/// **점은 패드 크기 비율(0~1) 정규화로 저장한다** — 회전·리사이즈로 레이아웃이
/// 바뀌어도 획이 사라지지 않고 새 크기로 스케일된다. 절대 좌표로 저장하고 회전 시
/// 전부 잃는 것이 signature_pad JS 라이브러리 계열의 알려진 함정이다(P44 리서치).
class SignaturePadController extends ChangeNotifier {
  /// 획 목록 — 각 획은 정규화 좌표(0~1)의 점 목록. 점 하나짜리 획(탭)도 획이다.
  final List<List<Offset>> _strokes = [];

  /// 마지막 레이아웃 크기(dp) — 유효성 판정·내보내기 종횡비의 기준.
  /// 첫 레이아웃 전 기본값은 시트 실측 근사(360dp 폭 시트 − 좌우 여백).
  Size _padSize = const Size(320, 180);

  /// 유효 판정 하한 — 획 바운딩 박스(가로·세로 중 큰 쪽)가 패드 **폭**의 15% 이상
  /// (P44 결정 5 "관대하게"): 실제 서명이면 아무리 흘려 써도 넘고, 점 하나는 걸린다.
  static const minBoxRatio = 0.15;

  /// 획 굵기(dp) — 내보내기에도 같은 값이 쓰인다(본 것 = 저장되는 것).
  static const strokeWidth = 2.5;

  /// 내보내기 크기 상한 — 결정 2의 실측 창(5~18KB)을 넘는 비정상 서명만 걸린다.
  static const maxExportBytes = 40 * 1024;

  /// 축소 하한(출력 픽셀) — 이보다 작으면 서명 판독성이 무너진다.
  static const _minExportWidth = 320.0;
  static const _minExportHeight = 140.0;

  int get strokeCount => _strokes.length;

  bool get isEmpty => _strokes.isEmpty;

  /// 테스트 전용 — 정규화 저장이 리사이즈에 불변임을 검증하기 위한 읽기 창.
  @visibleForTesting
  List<List<Offset>> get debugStrokes => [for (final s in _strokes) List.unmodifiable(s)];

  /// 테스트 전용 — 40KB 상한 경로 재현용 합성 획 주입(정규화 0~1 좌표).
  /// 실제 서명은 결정 2의 실측 창(5~18KB) 안이라 제스처로는 상한을 못 넘는다.
  @visibleForTesting
  void debugAddStroke(List<Offset> normalizedPoints) {
    if (normalizedPoints.isEmpty) return;
    _strokes.add(List.of(normalizedPoints));
    notifyListeners();
  }

  /// 테스트 전용 — 마지막 내보내기의 축소 재렌더 횟수(0 = 첫 렌더로 통과).
  @visibleForTesting
  int get debugLastExportRerenders => _lastExportRerenders;
  int _lastExportRerenders = 0;

  /// 실제 표식인가 — 획 ≥1 + 전체 획 합집합 바운딩 박스 하한(위 [minBoxRatio]).
  bool get isValid {
    if (_strokes.isEmpty) return false;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final stroke in _strokes) {
      for (final p in stroke) {
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
    }
    final boxW = (maxX - minX) * _padSize.width;
    final boxH = (maxY - minY) * _padSize.height;
    return math.max(boxW, boxH) >= minBoxRatio * _padSize.width;
  }

  /// [다시 쓰기] — 전부 지운다. 유효성이 함께 꺼져 최종 버튼이 잠긴다.
  void clear() {
    if (_strokes.isEmpty) return;
    _strokes.clear();
    notifyListeners();
  }

  // ── 위젯 쪽 훅(패키지 프라이빗) ─────────────────────────────────────────

  /// 레이아웃 크기 갱신 — 빌드 중에 불리므로 **알리지 않는다**(점은 정규화라 크기가
  /// 바뀌어도 그대로고, 리사이즈는 부모 리빌드가 이미 화면을 다시 그린다).
  void _attachSize(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _padSize = size;
  }

  void _startStroke(Offset local, Size size) {
    _strokes.add([_normalize(local, size)]);
    notifyListeners();
  }

  void _extendStroke(Offset local, Size size) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(_normalize(local, size));
    notifyListeners();
  }

  /// 패드 밖으로 나간 드래그는 가장자리에 클램프 — 획이 캔버스 밖으로 새지 않는다.
  Offset _normalize(Offset local, Size size) =>
      Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));

  // ── 내보내기(P44 결정 2) ───────────────────────────────────────────────

  /// 획을 PictureRecorder 캔버스에 재생해 **투명 배경 PNG** 바이트로 내보낸다.
  ///
  /// 픽셀 밀도는 기기 devicePixelRatio에 2x 상한(결정 2의 실측 5~18KB 창에 드는
  /// 밀도 — 3x는 크기만 늘고 판독성 이득이 없다). 40KB를 넘으면 0.7배씩 줄여
  /// 재렌더(최대 3회), 출력 픽셀 320×140 아래로는 내리지 않는다(판독성 바닥).
  /// 하한에 닿아도 바이트는 돌려준다 — 크기 초과를 이유로 서명을 버리지 않는다.
  ///
  /// 상한은 실측상 방어 레일이다: 균일 잉크 획은 PNG가 극단적으로 잘 눌러서
  /// 합성 노이즈 획 1,600개도 3KB대다(테스트 프로브) — 실서명은 넘을 수 없고,
  /// 넘는 입력은 렌더러 이상뿐이다. [maxBytes]는 그 루프를 테스트가 결정적으로
  /// 밟기 위한 시임(운영 호출은 기본값 그대로).
  Future<Uint8List> toPngBytes({
    required double devicePixelRatio,
    @visibleForTesting int maxBytes = maxExportBytes,
  }) async {
    final size = _padSize;
    final minScale = math.max(_minExportWidth / size.width, _minExportHeight / size.height);
    var scale = math.max(math.min(devicePixelRatio, 2.0), minScale);
    var bytes = await _renderPng(size, scale);
    var rerenders = 0;
    while (bytes.lengthInBytes > maxBytes && rerenders < 3 && scale > minScale) {
      rerenders += 1;
      scale = math.max(scale * 0.7, minScale);
      bytes = await _renderPng(size, scale);
    }
    _lastExportRerenders = rerenders;
    return bytes;
  }

  Future<Uint8List> _renderPng(Size size, double scale) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale, scale);
    // 화면과 같은 잉크색 고정(테마 무관) — 증거 이미지가 표시 환경에 따라 달라지면
    // 안 된다. 배경은 그리지 않는다(투명 PNG — 문서 어디에 얹어도 잉크만 앉는다).
    paintStrokes(canvas, size, _inkPaint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * scale).round(),
      (size.height * scale).round(),
    );
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Paint _inkPaint() => Paint()
    ..color = AppColors.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  /// 획 그리기 — 화면 페인터와 내보내기가 **같은 코드**를 쓴다(본 것 = 저장되는 것).
  /// 점 하나짜리 획은 라운드 캡 점으로 찍힌다.
  @visibleForTesting
  void paintStrokes(Canvas canvas, Size size, Paint paint) {
    for (final stroke in _strokes) {
      if (stroke.length == 1) {
        canvas.drawPoints(ui.PointMode.points, [_denormalize(stroke.single, size)], paint);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  Offset _denormalize(Offset norm, Size size) =>
      Offset(norm.dx * size.width, norm.dy * size.height);
}

/// 서명 패드 위젯 — 전폭 캔버스(기본 180dp) + 점선 기준선 + 힌트 + [다시 쓰기].
/// 상태는 전부 [controller]가 쥔다(시트가 단계를 오가도 획이 보존되는 이유).
class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller, this.height = 180});

  final SignaturePadController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, height);
            controller._attachSize(size);
            return SizedBox(
              height: height,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line, width: 1.5),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                clipBehavior: Clip.antiAlias,
                // 패드가 유일한 제스처 주인이다 — 시트 쪽은 enableDrag를 꺼서
                // (contract_sign_sheet) 세로 획이 시트 드래그로 새지 않는다.
                // 법적 구속력이 있는 계약의 서명란인데 시맨틱이 하나도 없었다
                // (P54). 플레이스홀더 안내문조차 획이 하나라도 그어지면 사라져,
                // 스크린리더 사용자에겐 아무 단서도 남지 않았다. 대체 입력(타이핑
                // 서명)은 별건이지만, 최소한 여기가 무엇이고 지금 서명이 있는지는
                // 읽혀야 한다.
                child: Semantics(
                  label: '서명란',
                  hint: '손가락으로 서명해 주세요',
                  value: controller.isEmpty ? '아직 서명하지 않았습니다' : '서명했습니다',
                  liveRegion: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => controller._startStroke(d.localPosition, size),
                    onPanUpdate: (d) => controller._extendStroke(d.localPosition, size),
                    child: AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) => Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(painter: _SignaturePadPainter(controller)),
                          if (controller.isEmpty)
                            const IgnorePointer(
                              child: Center(
                                child: Text(
                                  '여기에 서명해 주세요',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        // [다시 쓰기] — 캔버스 밖에 둔다: 캔버스 안 버튼은 그 위에서 시작한 획을
        // 먹어 버린다(제스처 히트 우선). 획이 없으면 잠긴다.
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: controller.isEmpty ? null : controller.clear,
              // 터치 영역 44dp 하한(P73) — 종전 세로 12+10 패딩 + 11.5px 글자는 ≈36dp라
              // 오획을 지우는 유일한 길이 앱 최소 타깃(`touch_target_test`)에 못 미쳤다.
              // RiseUnderlineLink와 같은 방식(ConstrainedBox minHeight).
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      '다시 쓰기',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: controller.isEmpty ? AppColors.muted : AppColors.brand,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SignaturePadPainter extends CustomPainter {
  _SignaturePadPainter(this.controller) : super(repaint: controller);

  final SignaturePadController controller;

  @override
  void paint(Canvas canvas, Size size) {
    // 점선 기준선 — 종이 서명란의 밑줄. 화면 안내일 뿐이라 내보내기에는 없다.
    final baselineY = size.height - 40;
    final dashPaint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    const dash = 5.0, gap = 5.0;
    var x = 16.0;
    while (x < size.width - 16) {
      canvas.drawLine(
        Offset(x, baselineY),
        Offset(math.min(x + dash, size.width - 16), baselineY),
        dashPaint,
      );
      x += dash + gap;
    }
    controller.paintStrokes(canvas, size, controller._inkPaint());
  }

  // repaint 리스너(컨트롤러)가 다시 그리게 한다 — 프레임마다 비교할 상태가 없다.
  @override
  bool shouldRepaint(_SignaturePadPainter oldDelegate) => oldDelegate.controller != controller;
}
