// 세션이 끊기면 캐시도 지운다(P32).
//
// **안 지우면 다음 기동에 그 신원으로 다시 들어온다.** 로그아웃·탈퇴·401은 전부
// "이 사람이 아니다"라는 뜻이므로, 세션을 비우는 단일 지점이 캐시를 지울 자리이기도
// 하다. 호출부마다 붙이면(로그아웃·탈퇴 화면·dio 인터셉터) 언젠가 한 곳을 빠뜨리고,
// 그 경로로 나간 회원만 유령 신원이 남는다 — 조용히 틀리는 종류다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/session/session_store.dart';

void main() {
  late _SpyStore store;
  late ProviderContainer container;

  setUp(() {
    store = _SpyStore();
    container = ProviderContainer(
      overrides: [sessionStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
  });

  const me = AppSession(
    uid: 'u1', role: 'member', centerId: 'rise', memberId: 'm1',
  );

  test('세션을 비우면 캐시도 지운다', () async {
    container.read(sessionProvider.notifier).set(me);
    await pumpEventQueue();
    expect(store.writes, hasLength(1));

    container.read(sessionProvider.notifier).clear(reason: SessionEndReason.signedOut);
    await pumpEventQueue();

    expect(store.cleared, 1, reason: '다음 기동에 그 신원으로 다시 들어온다');
  });

  test('세션을 채우면 캐시에 쓴다 — 호출부마다 붙이면 언젠가 빠뜨린다', () async {
    container.read(sessionProvider.notifier).set(me);
    await pumpEventQueue();

    expect(store.writes.single.memberId, 'm1');
    expect(store.cleared, 0);
  });
}

class _SpyStore implements SessionStore {
  final writes = <AppSession>[];
  int cleared = 0;

  @override
  Future<AppSession?> read(String uid) async => null;

  @override
  Future<void> write(AppSession s) async => writes.add(s);

  @override
  Future<void> clear() async => cleared++;
}
