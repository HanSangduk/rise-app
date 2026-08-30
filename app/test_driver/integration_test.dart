// 스토어 스크린샷 드라이버(P46) — integration_test의 takeScreenshot 바이트를
// 파일로 저장한다. 실행은 store/screenshots/capture.sh 참고.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final dir = Platform.environment['STORE_SHOT_DIR'] ?? 'build/store_screenshots';
      final file = File('$dir/$name.png');
      file.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      // ignore: avoid_print
      print('[SHOT] ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
