// 세션 로컬 캐시(P32).
//
// 종전엔 `Session.build()`가 `null`이라 앱을 켤 때마다 `GET /v1/me`가 성공해야
// "내가 누구인지" 알 수 있었다. 지하철에서 켜면 그 왕복이 끝날 때까지 아무것도
// 못 하고, 실패하면 **이미 로그인한 회원인데도** 로그인 계열 화면으로 떨어졌다.
//
// 캐시는 편의지만 **신원**을 다루므로, 이 스위트가 잠그는 건 속도가 아니라
// "남의 신원이 실리지 않는가"와 "지워야 할 때 지워지는가"다.

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const me = AppSession(
    uid: 'firebase-uid-A',
    role: 'member',
    centerId: 'rise',
    memberId: 'm-A',
    memberName: '김민지',
  );

  late PrefsSessionStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = const PrefsSessionStore();
  });

  group('uid로 잠근다 — 한 기기를 두 사람이 쓴다', () {
    test('저장한 uid로 읽으면 그대로 나온다', () async {
      await store.write(me);
      final got = await store.read('firebase-uid-A');
      expect(got, isNotNull);
      expect(got!.memberId, 'm-A');
      expect(got.memberName, '김민지');
    });

    test('다른 uid로 읽으면 주지 않는다 — 이게 핵심 방어선이다', () async {
      // 센터 태블릿·가족 공용폰에서 이 대조가 없으면 다음 사람이 **앞사람의
      // 신원으로** 앱을 쓰게 된다. 로그아웃이 지우는 것과 별개의 방어선이다 —
      // 지우기를 한 곳이라도 빠뜨렸을 때 이게 막는다.
      await store.write(me);
      expect(await store.read('firebase-uid-B'), isNull);
    });

    test('지우면 원래 uid로도 안 나온다', () async {
      await store.write(me);
      await store.clear();
      expect(await store.read('firebase-uid-A'), isNull);
    });
  });

  group('캐시가 앱을 죽이지 않는다', () {
    test('저장된 값이 깨져 있으면 없는 것으로 친다', () async {
      // 형식이 바뀌었거나 반쯤 쓰인 경우. 여기서 던지면 **기동 자체가 막힌다** —
      // 캐시 하나 때문에 앱을 못 켜는 건 있으나 마나 한 최적화가 아니라 손해다.
      SharedPreferences.setMockInitialValues({'rise.session.v1': '{not json'});
      expect(await store.read('firebase-uid-A'), isNull);
    });

    test('빈 저장소에서 읽어도 조용히 null', () async {
      expect(await store.read('firebase-uid-A'), isNull);
    });
  });

  group('무엇을 담는가', () {
    test('인증 토큰은 담지 않는다 — 이 파일을 훔쳐도 누구도 될 수 없다', () async {
      // 토큰은 Firebase Auth가 자기 저장소에 갖고 있고, 서버는 매 요청의 ID
      // 토큰으로만 신원을 판정한다. 여기 담기는 건 식별자와 표시 이름뿐이다.
      await store.write(me);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('rise.session.v1')!;
      for (final forbidden in ['token', 'Bearer', 'password', 'secret']) {
        expect(raw.toLowerCase().contains(forbidden.toLowerCase()), isFalse,
            reason: '캐시에 $forbidden 비슷한 게 들어갔다');
      }
    });

    test('표시 이름이 비어도 왕복한다 — 서버 name은 best-effort다', () async {
      const noName = AppSession(
        uid: 'u', role: 'member', centerId: 'rise', memberId: 'm',
      );
      await store.write(noName);
      expect((await store.read('u'))!.memberName, isEmpty);
    });
  });
}
