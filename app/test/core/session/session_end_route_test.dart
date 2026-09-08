// 세션 종료의 **이유**가 착지를 고른다(P64).
//
// 종전엔 `app.dart`의 세션 리스너가 원인 불문 `/login`(전화번호 화면)으로 보냈다.
// 캐시 세션 재검증에서 서버가 "회원 연결 없음"을 확답한 경우 Firebase 신원은 살아
// 있고 센터 연결만 사라진 것인데, 전화번호 화면은 SMS 재인증(건당 비용)을 강제하고
// 대기실이 보여 줄 서버 상태(거절·대기)도 못 보게 했다.
//
// 뮤테이션: `sessionEndRoute`를 항상 '/login'으로 바꾸면 첫 테스트가 죽는다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/session/session_store.dart';

void main() {
  group('sessionEndRoute — 신원이 살아 있는 종료는 전화번호 화면으로 보내지 않는다', () {
    test('notLinked → 대기실(/login/center-confirm)', () {
      expect(
        sessionEndRoute(SessionEndReason.notLinked),
        '/login/center-confirm',
        reason: '연결 해제 확답을 전화번호 화면으로 보내면 SMS 재인증을 강제한다',
      );
    });

    test('signedOut · unauthorized · deleted → 온보딩 첫 화면(/login)', () {
      for (final r in [
        SessionEndReason.signedOut,
        SessionEndReason.unauthorized,
        SessionEndReason.deleted,
      ]) {
        expect(sessionEndRoute(r), '/login', reason: '$r — 신원 자체가 끝난 사건이다');
      }
    });

    test('모든 이유가 착지를 갖는다 — enum이 늘면 컴파일이 아니라 이 테스트가 잡는다', () {
      for (final r in SessionEndReason.values) {
        expect(sessionEndRoute(r), startsWith('/login'));
      }
    });
  });

  group('Session.clear(reason:) — 이유를 남기고, set()이 지운다', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer.test(
        overrides: [sessionStoreProvider.overrideWithValue(_NoopStore())],
      );
    });

    const me = AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1');

    test('clear가 남긴 이유를 리스너가 읽을 수 있다', () {
      final s = container.read(sessionProvider.notifier);
      s.set(me);
      expect(s.lastEndReason, isNull, reason: '살아 있는 세션에 종료 이유가 붙어 있으면 안 된다');

      s.clear(reason: SessionEndReason.notLinked);

      expect(container.read(sessionProvider), isNull);
      expect(s.lastEndReason, SessionEndReason.notLinked);
    });

    test('다시 채우면 옛 이유가 지워진다 — 다음 종료가 옛 이유를 읽지 않게', () {
      final s = container.read(sessionProvider.notifier);
      s.set(me);
      s.clear(reason: SessionEndReason.deleted);
      s.set(me);

      expect(s.lastEndReason, isNull);
    });

    // P64 검증 반영 — 종전엔 "마지막 이유가 이긴다"였는데, 재검증이 notLinked로 비운 뒤
    // 탈퇴 화면의 `_signOut`이 deleted로 덮어쓰는 식으로 리스너·탈출 버튼이 첫 종료와 다른
    // 착지를 가리킬 수 있었다. 이미 비어 있으면 재진입이다 — 첫 이유가 남는다.
    test('이미 null이면 재진입 — 이유를 덮어쓰지 않는다', () {
      final s = container.read(sessionProvider.notifier);
      s.set(me);
      s.clear(reason: SessionEndReason.notLinked);
      s.clear(reason: SessionEndReason.unauthorized);

      expect(s.lastEndReason, SessionEndReason.notLinked, reason: '첫 종료가 착지를 골랐다');
    });

    test('세션 없이 clear만 부르면 이유도 남지 않는다 — 대기실 scope의 탈퇴가 이 경우다', () {
      final s = container.read(sessionProvider.notifier);
      s.clear(reason: SessionEndReason.deleted);

      expect(container.read(sessionProvider), isNull);
      expect(s.lastEndReason, isNull);
    });

    test('다시 채운 뒤의 clear는 새 이유를 남긴다 — 재진입 가드는 살아 있는 세션을 막지 않는다', () {
      final s = container.read(sessionProvider.notifier);
      s.set(me);
      s.clear(reason: SessionEndReason.notLinked);
      s.set(me);
      s.clear(reason: SessionEndReason.unauthorized);

      expect(s.lastEndReason, SessionEndReason.unauthorized);
    });
  });
}

class _NoopStore implements SessionStore {
  @override
  Future<AppSession?> read(String uid) async => null;
  @override
  Future<void> write(AppSession session) async {}
  @override
  Future<void> clear() async {}
}
