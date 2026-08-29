import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dev_session.g.dart';

/// 로컬 개발 인증 우회 — API계약_v1.md:
/// "로컬 개발: `X-Dev-Role: owner|trainer|member` + `X-Dev-Uid` 허용".
///
/// 회원 앱은 항상 role=member. Firebase 실연동(P06) 이후에도 이 경로를 남겨 둔 이유는
/// 로컬 백엔드(FIREBASE_PROJECT 미설정)가 dev 헤더로만 신원을 판별하기 때문이다.
/// dio_client는 Bearer와 dev 헤더를 함께 실어 보내고 **백엔드가 모드별로 하나만** 쓴다.
///
/// [enabled] 기본값은 디버그 빌드에서만 true — 릴리스 빌드는 dart-define 없이도 자동으로
/// 꺼진다. 디버그에서 프로덕션 백엔드를 붙여볼 땐 `--dart-define=DEV_SESSION=false`.
class DevSession {
  const DevSession({
    this.enabled = defaultEnabled,
    this.uid = 'dev-member-uid-001',
  });

  static const defaultEnabled =
      bool.fromEnvironment('DEV_SESSION', defaultValue: kDebugMode);

  final bool enabled;
  final String uid;
  static const role = 'member';
}

@riverpod
DevSession devSession(Ref ref) => const DevSession();
