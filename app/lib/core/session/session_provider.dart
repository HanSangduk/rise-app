import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_store.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';

part 'session_provider.g.dart';

/// 세션이 비워진 **이유** — 착지 화면을 고르는 유일한 근거(P64).
///
/// 뷰모델은 이 값을 읽지 않는다. 뷰모델이 아는 건 "세션이 없다"뿐이고, 그 상태에
/// 어떤 문장을 넣어도 절반은 거짓이다(401이면 "연결이 끊겼어요"가, 연결 해제면
/// "로그인이 필요해요"가 거짓). 원인과 착지는 **세션을 비운 쪽**이 말한다.
enum SessionEndReason {
  /// 회원이 마이 탭에서 로그아웃했다.
  signedOut,

  /// dio 401 — 토큰이 폐기돼 신원이 사라졌다(갱신으로 살릴 수 없는 상태).
  unauthorized,

  /// 회원탈퇴가 끝났다(서버가 계정을 지웠다).
  deleted,

  /// 캐시 세션 재검증에서 서버가 "회원 연결 없음"을 **확답**했다 — Firebase 신원은
  /// 살아 있고 센터 연결만 사라진 상태라 전화번호 재인증을 시킬 이유가 없다.
  notLinked,
}

/// 이유 → 착지 라우트. 순수 함수라 테스트가 싸다.
///
/// [SessionEndReason.notLinked]만 대기실(`/login/center-confirm`)로 간다 — 신원이
/// 살아 있는 종료를 전화번호 화면으로 보내면 SMS 재인증(건당 비용)을 강제하고,
/// 대기실이 보여 줄 서버 상태(거절·대기)도 못 본다. 나머지 셋은 신원 자체가 끝난
/// 사건이라 온보딩 첫 화면이 맞다.
///
/// 되돌릴 수 있는 제품 판단이다(P64 결정 사항) — "연결이 끊긴 사람은 처음부터 다시
/// 인증시키고 싶다"면 notLinked 줄만 지우면 된다.
String sessionEndRoute(SessionEndReason reason) => switch (reason) {
      SessionEndReason.notLinked => '/login/center-confirm',
      SessionEndReason.signedOut ||
      SessionEndReason.unauthorized ||
      SessionEndReason.deleted =>
        '/login',
    };

/// `app.dart` 세션 리스너의 판정 본문 — 순수 함수로 뽑아 위젯 없이 고정한다(P64 검증 반영).
///
/// null이면 이동하지 않는다: 세션이 **사라진** 전이(prev != null → next == null)만 착지가
/// 있다. 앱 시작 시점의 세션은 null이라 `null → null`을 이동으로 보면 복원이 끝나기 전에
/// 로그인으로 튕겨 복원 자체가 죽고, `→ 채워짐`은 로그인 성공이라 라우터가 이미 다룬다.
///
/// [reason]이 없으면(옛 호출부·재진입) 신원 상실로 본다 — 가장 보수적인 착지다.
String? sessionListenerRoute(
  AppSession? prev,
  AppSession? next,
  SessionEndReason? reason,
) {
  if (prev == null || next != null) return null;
  return sessionEndRoute(reason ?? SessionEndReason.unauthorized);
}

/// 로그인 세션 — 로그인 플로우(join/confirm) 완료 시 채워지고,
/// 셸(홈/예약/촬영/기록/마이) 이하 모든 화면이 memberId를 여기서 읽는다.
/// keepAlive: 화면 전환 사이 구독이 잠시 끊겨도 세션이 유실되지 않아야 한다
/// (autoDispose면 로그인 직후 라우팅 레이스로 세션이 사라질 수 있음).
@Riverpod(keepAlive: true)
class Session extends _$Session {
  @override
  AppSession? build() => null;

  bool get isLoggedIn => state != null;

  /// 마지막으로 세션을 비운 이유 — `app.dart`의 세션 리스너가 착지를 고를 때 읽는다.
  ///
  /// notifier 필드에 두는 이유: 리스너는 `null`이 된 **뒤에** 불리므로 상태 자체에는
  /// 이유를 실을 수 없다. [set]이 다시 채우면 지운다(살아 있는 세션에 옛 종료 이유가
  /// 붙어 있으면 다음 종료가 그 이유를 잘못 읽을 수 있다). 리스너는 읽은 뒤 이 값을
  /// 되돌리지 않는다 — 재빌드로 리스너가 재등록되면 두 번 읽힐 수 있어서다.
  SessionEndReason? lastEndReason;

  /// 세션을 채운다 — **캐시 저장도 여기서 한다.**
  ///
  /// 호출부마다 저장을 붙이면(로그인 2곳·복원 1곳·재검증 1곳) 언젠가 한 곳을
  /// 빠뜨리고, 그 경로로 로그인한 회원만 다음 기동이 느려진다. 조용히 틀리는
  /// 종류라 단일 지점으로 둔다 — [clear]가 지우는 것과 대칭이다.
  void set(AppSession session) {
    lastEndReason = null;
    state = session;
    unawaited(ref.read(sessionStoreProvider).write(session));
  }

  /// 세션 종료 — **체형사진 바이트 캐시도 함께 비운다.**
  ///
  /// 여기서 비우는 이유는 이 자리가 **단일 지점**이기 때문이다: 로그아웃
  /// (`my_screen`)·회원탈퇴(`account_deletion_screen`)·토큰 만료(dio 401 인터셉터)·
  /// 캐시 재검증의 미연결 확답(`session_restore`) 네 경로가 전부 이 메서드를 지난다.
  /// 로그아웃 화면에만 붙이면 401 만료로 세션이 끊긴 기기에는 남의 사진이 그대로 남는다.
  ///
  /// [reason]은 필수다 — 이유 없는 종료는 착지를 고를 수 없고, 선택 인자로 두면
  /// 새 호출부가 조용히 기본값(전화번호 화면)으로 떨어진다. 컴파일이 강제하게 둔다.
  void clear({required SessionEndReason reason}) {
    // **재진입은 무시한다.** 이미 비어 있으면 첫 종료의 이유가 착지를 골랐고, 뒤따른
    // 호출(예: 탈퇴 화면의 `_signOut`이 재검증 뒤에 도착)이 이유를 덮어쓰면 리스너·
    // 탈출 버튼이 다른 화면을 가리킨다. 캐시도 첫 호출이 이미 지웠다.
    if (state == null) return;
    lastEndReason = reason;
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
