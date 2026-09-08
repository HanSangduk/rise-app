// 세션이 끊기면 체형사진 캐시도 비운다(P31).
//
// `clearCache()`는 처음부터 있었고 주석도 "테스트·로그아웃용"이라 적혀 있었는데
// **프로덕션 호출자가 0개**였다. 바이트 캐시는 프로세스 수명을 따라가므로 로그아웃해도
// 그대로 남는다 — 한 기기를 두 회원이 번갈아 쓰면(센터 태블릿, 가족) 다음 회원 화면에
// 이전 회원의 P8 민감정보가 그려질 수 있다.
//
// 세션 `clear()`에 붙인 이유는 **거기가 단일 지점**이기 때문이다: 로그아웃·회원탈퇴·
// 토큰 만료(dio 401 인터셉터) 세 경로가 전부 이 메서드를 지난다.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';

void main() {
  late _SpyLoader loader;
  late ProviderContainer container;

  setUp(() {
    loader = _SpyLoader();
    container = ProviderContainer(
      overrides: [bodyPhotoLoaderProvider.overrideWithValue(loader)],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).set(const AppSession(
          uid: 'u1',
          role: 'member',
          centerId: 'rise',
          memberId: 'm1',
        ));
  });

  test('세션을 비우면 사진 캐시도 비운다', () {
    expect(loader.cleared, 0);

    container.read(sessionProvider.notifier).clear(reason: SessionEndReason.signedOut);

    expect(container.read(sessionProvider), isNull);
    expect(loader.cleared, 1, reason: '남의 사진이 프로세스에 남는다');
  });

  test('세션을 채우는 것만으로는 캐시를 건드리지 않는다', () {
    // 로그인할 때마다 비우면 세션 복원(session_restore) 직후 방금 받은 사진까지
    // 날아가 같은 바이트를 다시 받는다.
    container.read(sessionProvider.notifier).set(const AppSession(
          uid: 'u2',
          role: 'member',
          centerId: 'rise',
          memberId: 'm2',
        ));
    expect(loader.cleared, 0);
  });
}

class _SpyLoader implements BodyPhotoLoader {
  int cleared = 0;

  @override
  void clear() => cleared++;

  @override
  void evict(String storagePath) {}

  @override
  Uint8List? peek(String storagePath) => null;

  @override
  Future<Result<Uint8List>> load(String storagePath) => throw UnimplementedError();
}
