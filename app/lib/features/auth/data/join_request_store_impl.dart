import 'package:rise_member/features/auth/domain/join_request_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// shared_preferences 기반 구현 — 민감정보가 아니라 "요청을 보냈다"는 사실만
/// 담으므로 평문 prefs로 충분하다(보안 저장소 불필요).
///
/// 레거시 `SharedPreferences.getInstance()` 대신 [SharedPreferencesAsync]를 쓴다
/// (2.3.0+ 권장 API — 인메모리 캐시 없이 매번 플랫폼을 읽으므로 앱 재실행·
/// 백그라운드 갱신 사이에 stale 값을 보지 않는다).
///
/// 모든 호출을 try/catch로 감싼다: 저장소가 없는 환경(위젯 테스트의 플랫폼 채널
/// 미등록 등)에서 예외가 나도 로그인 흐름 자체는 막히면 안 된다.
class SharedPreferencesJoinRequestStore implements JoinRequestStore {
  const SharedPreferencesJoinRequestStore();

  static const _key = 'auth.join_request';

  SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  @override
  Future<JoinRequestRecord?> read() async {
    try {
      return JoinRequestRecord.decode(await _prefs.getString(_key));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(JoinRequestRecord record) async {
    try {
      await _prefs.setString(_key, record.encode());
    } catch (_) {
      // 영속 실패 = 재실행 후 복귀만 못 할 뿐, 이번 세션 흐름은 그대로 진행.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _prefs.remove(_key);
    } catch (_) {
      // 위와 동일 — 삭제 실패가 화면 전환을 막지 않는다.
    }
  }
}
