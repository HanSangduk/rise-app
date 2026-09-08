// `app.dart` 세션 리스너의 판정 — 순수 함수 `sessionListenerRoute`(P64 검증 반영).
//
// 리스너 본문은 위젯 안에 있어 그동안 테스트가 닿지 않았다. 판정을 뽑아 네 전이를 고정한다:
// null → null(앱 시작·대기실)은 이동 없음, → 채워짐(로그인)은 라우터 몫, 채워짐 → 채워짐(재검증
// 갱신)도 이동 없음, 채워짐 → null만 이유대로 착지.
//
// 뮤테이션: `prev == null` 조건을 지우면 첫 테스트가 죽는다(복원이 끝나기 전에 로그인으로 튕긴다).
// `reason ?? unauthorized`를 `?? notLinked`로 바꾸면 마지막 테스트가 죽는다.

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';

void main() {
  const me = AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1');
  const renamed = AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람');

  test('null → null은 이동하지 않는다 — 앱 시작 시점에 로그인으로 튕기면 복원이 죽는다', () {
    expect(sessionListenerRoute(null, null, null), isNull);
    expect(sessionListenerRoute(null, null, SessionEndReason.deleted), isNull,
        reason: '대기실 scope의 탈퇴 — 세션이 없었으니 리스너가 아니라 화면이 직접 옮긴다');
  });

  test('null → 세션은 로그인 성공 — 라우터가 다루므로 이동하지 않는다', () {
    expect(sessionListenerRoute(null, me, null), isNull);
  });

  test('세션 → 세션은 재검증 갱신 — 이동하지 않는다', () {
    expect(sessionListenerRoute(me, renamed, null), isNull);
    expect(sessionListenerRoute(me, me, SessionEndReason.notLinked), isNull,
        reason: '옛 종료 이유가 남아 있어도 세션이 살아 있으면 착지가 없다');
  });

  test('세션 → null만 이유대로 착지한다 — 이유가 없으면 신원 상실(가장 보수적)', () {
    expect(sessionListenerRoute(me, null, SessionEndReason.notLinked), '/login/center-confirm');
    expect(sessionListenerRoute(me, null, SessionEndReason.signedOut), '/login');
    expect(sessionListenerRoute(me, null, SessionEndReason.deleted), '/login');
    expect(sessionListenerRoute(me, null, null), '/login',
        reason: '이유를 모르면 대기실이 아니라 전화번호 화면 — 신원이 살아 있다고 가정하면 안 된다');
  });
}
