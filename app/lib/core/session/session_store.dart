import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'session_store.g.dart';

/// 세션을 기기에 남겨 **콜드 스타트가 네트워크를 기다리지 않게** 한다.
///
/// ## 왜 필요한가
///
/// 종전엔 `Session.build()`가 `null`이라, 앱을 켤 때마다 `GET /v1/me`가 성공해야
/// "내가 누구인지" 알 수 있었다. 지하철·엘리베이터에서 켜면 그 왕복이 끝날 때까지
/// 아무것도 못 하고, 실패하면 로그인 계열 화면으로 떨어졌다 — **이미 로그인한
/// 회원인데도.**
///
/// ## 무엇을 저장하고, 무엇을 저장하지 않는가
///
/// [AppSession]의 다섯 값(uid·role·centerId·memberId·memberName)만 담는다.
/// **인증 토큰은 여기 없다** — 그건 Firebase Auth가 자기 저장소에 따로 갖고 있고,
/// 서버는 매 요청의 ID 토큰으로만 신원을 판정한다. 즉 이 파일을 통째로 훔쳐도
/// **누구도 될 수 없다.** 회원 식별자와 표시 이름을 알게 될 뿐이고, 그것도 앱
/// 전용 저장소라 루팅 없이는 다른 앱이 못 읽는다.
///
/// 그래서 `flutter_secure_storage`(Keystore/Keychain)를 쓰지 않았다. 키체인은
/// 비밀을 담는 자리인데 여기엔 비밀이 없고, 대신 기동 경로에 네이티브 채널
/// 왕복을 하나 더 얹는다 — 이 캐시의 존재 이유(기동을 빠르게)와 정면으로 어긋난다.
///
/// ## uid로 잠근다
///
/// 저장할 때 Firebase uid를 함께 넣고, 읽을 때 **지금 로그인한 uid와 대조**한다.
/// 한 기기를 두 회원이 쓰는 자리(센터 태블릿·가족 공용폰)에서 이 대조가 없으면
/// 다음 사람이 **앞사람의 신원으로** 앱을 쓰게 된다. 로그아웃이 지우는 것과
/// 별개의 방어선이다 — 지우기를 한 곳이라도 빠뜨렸을 때 이게 막는다.
abstract class SessionStore {
  /// 지금 uid의 캐시된 세션. 없거나 uid가 다르면 null.
  Future<AppSession?> read(String uid);
  Future<void> write(AppSession session);
  Future<void> clear();
}

class PrefsSessionStore implements SessionStore {
  const PrefsSessionStore();

  static const _key = 'rise.session.v1';

  /// **저장소 실패는 절대 밖으로 내보내지 않는다.**
  ///
  /// 이건 캐시다 — 없으면 네트워크로 가면 그만이고, 있으면 빠른 것뿐이다. 플러그인
  /// 채널이 없거나(위젯 테스트·바인딩 미초기화) 디스크가 꽉 차서 실패했다고 로그인
  /// 자체가 깨지면, 있으나 마나 한 최적화가 앱을 죽이는 셈이 된다.
  @override
  Future<AppSession?> read(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      // **uid 대조가 이 클래스의 핵심 방어선이다.**
      if (m['uid'] != uid) return null;
      return AppSession(
        uid: m['uid'] as String,
        role: m['role'] as String,
        centerId: m['center_id'] as String,
        memberId: m['member_id'] as String,
        memberName: (m['member_name'] as String?) ?? '',
      );
    } catch (_) {
      // 형식이 깨졌거나 저장소를 못 읽었으면 **없는 것으로 친다** — 그러면 종전처럼
      // 네트워크로 복원한다(느릴 뿐 틀리지 않는다).
      return null;
    }
  }

  @override
  Future<void> write(AppSession s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'uid': s.uid,
          'role': s.role,
          'center_id': s.centerId,
          'member_id': s.memberId,
          'member_name': s.memberName,
        }),
      );
    } catch (_) {
      // 다음 기동이 느려질 뿐이다.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // 지우지 못했어도 읽기 쪽 uid 대조와 서버 재검증이 다시 막는다.
    }
  }
}

@Riverpod(keepAlive: true)
SessionStore sessionStore(Ref ref) => const PrefsSessionStore();
