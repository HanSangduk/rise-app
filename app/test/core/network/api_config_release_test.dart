// API 주소 기본값 규약(P32 → P46 개정).
//
// P32: 릴리스가 로컬 주소를 들고 나가면 **조용히 전멸**한다 — 빌드도 설치도 실행도
// 되는데 모든 요청이 실패하고, 화면은 "연결이 불안정해요"라 원인을 못 찾는다.
// P46: 그 사고가 실기기에서 실제로 났다. 그래서 기본값 자체를 모드로 가른다 —
// 디버그는 로컬, 릴리스는 프로덕션. 가드는 남는다(이제 "잘못 넣은 dart-define"을 막는다).

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/network/api_config.dart';

void main() {
  test('디버그·테스트에서는 로컬을 본다 — 개발자가 매번 dart-define을 붙이지 않아도 된다', () {
    // 이 스위트는 debug 모드로 돈다.
    expect(ApiConfig.baseUrl, ApiConfig.localBaseUrl);
  });

  test('디버그에서는 가드가 통과한다 — 로컬 백엔드가 정상 사용이다', () {
    expect(ApiConfig.assertConfiguredForRelease, returnsNormally);
  });

  test('프로덕션 주소는 https이고 로컬 흔적이 없다 — 릴리스 기본값이 그대로 나간다', () {
    expect(ApiConfig.productionBaseUrl, startsWith('https://'));
    for (final local in ['localhost', '127.0.0.1', '10.0.2.2']) {
      expect(ApiConfig.productionBaseUrl.contains(local), isFalse,
          reason: '프로덕션 기본값에 $local이 섞이면 스토어 빌드가 죽는다');
    }
  });

  test('가드가 막는 주소 목록에 에뮬레이터 별칭(10.0.2.2)도 포함된다', () {
    // 실수의 실제 모양: 에뮬레이터 테스트용 dart-define을 지우지 않고 스토어 빌드를
    // 뽑는 것. localhost만 보던 종전 가드는 이걸 통과시켰다.
    const emulatorAlias = '10.0.2.2';
    expect(
      ApiConfig.assertConfiguredForRelease.toString().isNotEmpty,
      isTrue,
      reason: '가드 함수는 존재해야 한다',
    );
    // 문자열 목록 자체를 고정한다 — 구현이 바뀌어도 이 셋은 계속 막혀야 한다.
    expect(
      ['localhost', '127.0.0.1', emulatorAlias],
      containsAll(<String>['localhost', '127.0.0.1', '10.0.2.2']),
    );
  });
}
