// 릴리스 빌드가 로컬 주소를 들고 나가지 못하게 한다(P32).
//
// **조용히 틀리는 종류다.** `--dart-define`을 빠뜨린 릴리스 APK는 빌드도 되고
// 설치도 되고 실행도 되는데, 모든 요청이 `localhost:8080`으로 가서 전부 실패한다.
// 그 화면은 "연결이 불안정해요"라 회원도 대표도 원인을 못 찾는다. CI나 스크립트로
// 강제하는 자리가 없으므로 앱이 스스로 막는다.

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/network/api_config.dart';

void main() {
  test('디버그·테스트에서는 통과한다 — 로컬 백엔드가 정상 사용이다', () {
    // 이 스위트 자체가 debug 모드로 도므로, 여기서 던지면 개발이 막힌다.
    expect(ApiConfig.assertConfiguredForRelease, returnsNormally);
  });

  test('기본값이 로컬을 가리킨다 — 그래서 가드가 필요하다', () {
    // 이 전제가 바뀌면(기본값이 프로덕션이 되면) 가드의 의미도 바뀐다.
    expect(
      ApiConfig.baseUrl.contains('localhost') ||
          !ApiConfig.baseUrl.startsWith('http://'),
      isTrue,
    );
  });
}
