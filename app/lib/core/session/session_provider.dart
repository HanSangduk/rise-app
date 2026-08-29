import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_store.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';

part 'session_provider.g.dart';

/// 로그인 세션 — 로그인 플로우(join/confirm) 완료 시 채워지고,
/// 셸(홈/예약/촬영/기록/마이) 이하 모든 화면이 memberId를 여기서 읽는다.
/// keepAlive: 화면 전환 사이 구독이 잠시 끊겨도 세션이 유실되지 않아야 한다
/// (autoDispose면 로그인 직후 라우팅 레이스로 세션이 사라질 수 있음).
@Riverpod(keepAlive: true)
class Session extends _$Session {
  @override
  AppSession? build() => null;

  bool get isLoggedIn => state != null;

  /// 세션을 채운다 — **캐시 저장도 여기서 한다.**
  ///
  /// 호출부마다 저장을 붙이면(로그인 2곳·복원 1곳·재검증 1곳) 언젠가 한 곳을
  /// 빠뜨리고, 그 경로로 로그인한 회원만 다음 기동이 느려진다. 조용히 틀리는
  /// 종류라 단일 지점으로 둔다 — [clear]가 지우는 것과 대칭이다.
  void set(AppSession session) {
    state = session;
    unawaited(ref.read(sessionStoreProvider).write(session));
  }

  /// 세션 종료 — **체형사진 바이트 캐시도 함께 비운다.**
  ///
  /// 여기서 비우는 이유는 이 자리가 **단일 지점**이기 때문이다: 로그아웃
  /// (`my_screen`)·회원탈퇴(`account_deletion_screen`)·토큰 만료(dio 401 인터셉터)
  /// 세 경로가 전부 이 메서드를 지난다. 로그아웃 화면에만 붙이면 401 만료로 세션이
  /// 끊긴 기기에는 남의 사진이 그대로 남는다.
  void clear() {
    ref.read(bodyPhotoLoaderProvider).clear();
    // **캐시도 함께 지운다.** 안 지우면 다음 기동에 그 신원으로 다시 들어온다 —
    // 로그아웃·탈퇴·401 어느 쪽이든 "이 사람이 아니다"라는 뜻이므로, 세션을
    // 비우는 이 단일 지점이 캐시를 지울 자리이기도 하다.
    //
    // 결과를 기다리지 않는다: 화면 전환을 막을 이유가 없고, 실패해도 다음 기동의
    // uid 대조와 서버 재검증이 다시 막는다(`SessionStore` 주석).
    unawaited(ref.read(sessionStoreProvider).clear());
    state = null;
  }

  /// 로그인 이후 화면에서만 호출 — 세션 없으면 라우팅 버그이므로 즉시 실패.
  AppSession get requireValue {
    final s = state;
    if (s == null) {
      throw StateError('세션이 없는 상태에서 로그인 전용 화면에 접근했어요.');
    }
    return s;
  }
}
