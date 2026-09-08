// 법정 문서가 말하는 앱 식별자 == 실제 빌드 식별자 (P56).
//
// **두 번 틀렸던 자리다.** P46에서 `ai.stra.rize` → `com.han.rize` → `com.han.rise`로
// 두 번 갈아탔는데, 법정 문서는 중간값에서 멈춰 배포됐다. `com.han.rize`는 Play가
// **실제로 거부한 폐기 식별자**이고, 그 문서 URL이 Play 데이터 안전의 계정삭제
// 안내 주소다 — 심사자가 열면 존재하지 않는 앱의 삭제 안내를 보게 된다.
//
// 사람이 지키게 두면 세 번째가 난다. 빌드 설정을 진실의 원천으로 삼아 대조한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `android/app/build.gradle.kts`의 `applicationId` — 실제 출고되는 식별자.
String _applicationId() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final m = RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle);
  expect(m, isNotNull, reason: 'build.gradle.kts에서 applicationId를 못 찾았다');
  return m!.group(1)!;
}

void main() {
  test('법정 문서 3종이 실제 패키지 ID를 고지한다', () {
    final appId = _applicationId();
    // 법정 문서는 어드민이 Hosting으로 배포한다(앱 저장소 밖).
    final dir = Directory('../admin/public/legal');
    expect(dir.existsSync(), isTrue, reason: '법정 문서 경로가 바뀌었다 — 이 가드를 갱신할 것');

    final offenders = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.html')) continue;
      for (final hit in RegExp(r'com\.han\.[a-z0-9_]+').allMatches(f.readAsStringSync())) {
        if (hit.group(0) != appId) offenders.add('${f.path}: ${hit.group(0)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '법정 문서가 실제 앱($appId)이 아닌 식별자를 고지한다 — $offenders',
    );
  });

  test('iOS 번들 ID도 같은 값이다 — 두 스토어가 갈리지 않는다', () {
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+);')
        .allMatches(pbx)
        .map((m) => m.group(1)!)
        // RunnerTests는 앱 ID에 접미사가 붙는다(정상).
        .where((id) => !id.endsWith('.RunnerTests'))
        .toSet();
    expect(ids, {_applicationId()}, reason: 'Android와 iOS 식별자가 갈렸다');
  });
}
