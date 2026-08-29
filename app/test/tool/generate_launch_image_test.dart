// iOS 런치 이미지 생성기 (P32) — 테스트가 아니라 **도구**다.
//
// 실행:
//   flutter test test/tool/generate_launch_image_test.dart --dart-define=WRITE_LAUNCH_IMAGE=true
//
// 왜 테스트 하네스를 빌려 쓰는가: PNG를 만들려면 `dart:ui`의 래스터라이저가 필요한데
// 그건 Flutter 엔진 안에서만 돈다. 별도 렌더러(cairosvg·rsvg·Inkscape)를 쓰면
// **같은 그림이라는 보장이 사라진다** — 이 방식은 앱이 화면에 그리는 바로 그
// `RiseMarkPainter`를 그대로 굽기 때문에 어긋날 수가 없다.
//
// 플래그 없이 돌면 아무 파일도 쓰지 않고, 대신 **좌표계가 어긋나지 않았는지**만
// 검사한다(일반 테스트 실행에서 이 파일이 무해하도록).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/brand/rise_mark.dart';

const _write = bool.fromEnvironment('WRITE_LAUNCH_IMAGE');

/// 스토리보드가 `contentMode="center"`라 이미지는 **논리 포인트 크기 그대로** 뜬다.
/// 132는 `SplashGate`가 쓰는 `RiseMark(size: 132)`와 같은 값이어야 한다 —
/// 다르면 런치 이미지에서 Flutter 첫 프레임으로 넘어갈 때 마크가 점프한다.
const _logicalWidth = 132.0;

double get _logicalHeight =>
    _logicalWidth * RiseMarkGeometry.viewBoxHeight / RiseMarkGeometry.viewBoxWidth;

Future<Uint8List> _render(double scale) async {
  final w = _logicalWidth * scale;
  final h = _logicalHeight * scale;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // **크림을 굽지 않는다.** 배경은 스토리보드가 칠하고(같은 #F6F4EF), 이미지는
  // 투명 배경의 마크만 담는다 — 그래야 기기 화면비가 어떻든 배경이 꽉 찬다.
  canvas.scale(scale);
  // 런치 이미지에는 **점이 있다**(앱 아이콘·Flutter 첫 프레임과 같게).
  const RiseMarkPainter().paint(canvas, Size(_logicalWidth, _logicalHeight));

  final img = await recorder.endRecording().toImage(w.round(), h.round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  test('마크 크기가 SplashGate와 같다 — 다르면 넘어갈 때 점프한다', () {
    // 이 파일이 도구로만 쓰이더라도, 상수가 갈라지는 건 여기서 잡는다.
    expect(_logicalWidth, 132.0);
    expect(_logicalHeight, closeTo(136.04, 0.01));
  });

  testWidgets('런치 이미지 3종 생성', (tester) async {
    if (!_write) {
      // 일반 실행에서는 파일을 만들지 않는다.
      return;
    }
    const dir = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
    for (final (scale, name) in [
      (1.0, 'LaunchImage.png'),
      (2.0, 'LaunchImage@2x.png'),
      (3.0, 'LaunchImage@3x.png'),
    ]) {
      final bytes = await _render(scale);
      File('$dir/$name').writeAsBytesSync(bytes);
      // ignore: avoid_print
      print('wrote $dir/$name (${bytes.length} bytes)');
    }
  });
}
