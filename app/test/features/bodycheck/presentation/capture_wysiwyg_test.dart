// 보이는 대로 저장된다(P31).
//
// 람의 요청: *"실제 저장되는 사진이랑 똑같이 보이는 카메라 뷰면 좋을거 같아"*.
//
// 종전엔 프리뷰 프레임이 `AspectRatio(392/472)`로 **고정**돼 있었다(목업에서 이식한
// 숫자). 카메라 비율이 다르면 `BoxFit.cover`가 잘라서 채웠고, 회원은 **잘린 그림을
// 보고 자세를 맞췄는데 파일에는 프레임 밖까지** 들어 있었다 — 3:4면 9.7%, 9:16이면
// 32.3%가 화면에 없던 영역이다. 격자로 어깨선을 맞추라고 해 놓고 저장본은 다른
// 그림이었다.
//
// 실기기(SM-G998N) 실측: 프리뷰 0.5625 == 파일 0.5625(1080×1920). 이 스위트는 그
// 계약이 코드에서 유지되는지를 본다.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/bodycheck/presentation/body_camera_provider.dart';

void main() {
  double aspect(Size? s) => BodyCameraReady.aspectFromPreviewSize(s);

  test('센서 방향(가로)으로 오는 값을 세로 프레임 비율로 뒤집는다', () {
    // 뒤집지 않으면 16/9(1.78)가 되어 프레임이 가로로 눕는다.
    expect(aspect(const Size(1920, 1080)), closeTo(9 / 16, 1e-9));
    expect(aspect(const Size(1600, 1200)), closeTo(3 / 4, 1e-9));
  });

  test('실기기 실측값 — 1080×1920 파일과 같은 비율이 나온다', () {
    expect(aspect(const Size(1920, 1080)), closeTo(1080 / 1920, 1e-9));
  });

  group('프레임이 붕괴하지 않는다', () {
    test('아직 값이 없으면 기본 9:16', () {
      // null·0을 그대로 쓰면 AspectRatio가 0이 되거나 NaN이 되어 화면이 깨진다.
      expect(aspect(null), closeTo(9 / 16, 1e-9));
      expect(aspect(const Size(0, 0)), closeTo(9 / 16, 1e-9));
      expect(aspect(const Size(1920, 0)), closeTo(9 / 16, 1e-9));
    });

    test('기본값은 0이 아니다 — 준비 전에도 프레임이 서 있어야 한다', () {
      expect(BodyCameraReady.defaultCaptureAspect, greaterThan(0));
    });
  });
}
