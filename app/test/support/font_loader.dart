import 'dart:io';

import 'package:flutter/services.dart' show FontLoader;

/// 번들 Pretendard를 테스트 런타임에 실제로 로드한다.
///
/// 폴백 폰트는 줄높이가 달라 **실기기에서만 나는 1px 오버플로를 재현하지 못한다** —
/// P09에서 실제로 그랬다(안드로이드에서 `BOTTOM OVERFLOWED BY 1.00 PIXELS`가 떴는데
/// 위젯 테스트는 통과했다). 레이아웃을 재는 테스트는 이걸 먼저 부른다.
Future<void> loadPretendard() async {
  final bytes = await File('assets/fonts/PretendardVariable.ttf').readAsBytes();
  final loader = FontLoader('Pretendard')..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}
