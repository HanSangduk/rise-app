// 스플래시가 걷히는 동안 홈 데이터를 미리 받는다(P32).
//
// 람의 지적: *"스플래시 넣은 이유가 그런 로딩 같은 걸 스플래시 화면이 나오는 동안
// 미리 가져오면 좋잖아?"* — 맞다. 다만 두 가지를 지켜야 실제로 이득이 된다:
//
//  ① **구독을 들고 있어야 한다.** `homeViewModelProvider`는 autoDispose라 듣는
//     사람이 없으면 다음 이벤트 루프에서 폐기된다. `read`만 하면 요청은 나가지만
//     응답이 올 즈음 element가 사라져 홈이 **처음부터 다시** 받는다 — 트래픽만
//     두 배다.
//  ② **실패는 물려주지 않는다.** 예열이 실패한 상태를 홈이 이어받으면, 전파가
//     불안정한 기동 순간의 일시적 실패가 **"다시 시도"를 눌러야만 풀리는 화면**으로
//     굳는다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('예열 계약', () {
    test('autoDispose provider는 구독이 없으면 폐기된다 — 그래서 붙잡아야 한다', () async {
      // 이 성질이 예열 설계의 전제다. 전제가 바뀌면(keepAlive로 바뀌는 등)
      // 예열 코드의 구독 유지가 불필요해지므로 여기서 알아채야 한다.
      var built = 0;
      final p = FutureProvider.autoDispose<int>((ref) async {
        built++;
        return 1;
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(p); // 구독 없이 읽기만
      await pumpEventQueue();
      c.read(p); // 다시 읽으면 새로 만들어진다
      await pumpEventQueue();
      expect(built, greaterThan(1), reason: '구독 없이는 재사용되지 않는다');
    });

    test('구독을 들고 있으면 재사용된다', () async {
      var built = 0;
      final p = FutureProvider.autoDispose<int>((ref) async {
        built++;
        return 1;
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final sub = c.listen(p, (_, __) {}, fireImmediately: true);
      await pumpEventQueue();
      c.read(p);
      await pumpEventQueue();
      expect(built, 1, reason: '예열한 결과를 홈이 그대로 이어받아야 한다');
      sub.close();
    });

    test('구독을 놓으면 다음 읽기가 새로 시작한다 — 실패를 물려주지 않는 수단', () async {
      var built = 0;
      final p = FutureProvider.autoDispose<int>((ref) async {
        built++;
        return 1;
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final sub = c.listen(p, (_, __) {}, fireImmediately: true);
      await pumpEventQueue();
      sub.close();
      await pumpEventQueue();
      c.read(p);
      await pumpEventQueue();

      expect(built, 2, reason: '놓았으면 새 element에서 정상 로딩이 시작돼야 한다');
    });
  });
}
