import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderListenable`은 flutter_riverpod 3.0.x가 재수출하지 않는다 — 코드젠 패키지가
// 공개하는 같은 타입을 쓴다(`WidgetRef.read`·`ProviderContainer.read`의 인자 타입).
import 'package:riverpod_annotation/riverpod_annotation.dart' show ProviderListenable;
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/features/auth/domain/join_request_store.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/session/session_store.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';

/// 기동 시 세션 복원에 허용하는 최대 시간. 넘기면 "모름"으로 분류한다.
const restoreBudget = Duration(seconds: 6);

/// GET /v1/me 한 번으로 알 수 있는 것 — 실패를 뭉뚱그리면 안 되는 이유가 여기 있다.
enum RestoreOutcome {
  /// 세션 복원 성공 — 연결된 회원.
  connected,

  /// 서버가 "아직 회원 연결 전"이라고 **확답**했다(MemberNotLinkedFailure).
  notLinked,

  /// 확인 자체를 못 했다(네트워크·서버 오류). 연결됐는지 **모르는** 상태이지
  /// 미연결이 아니다.
  unknown,
}

/// `AuthRepository.loadSession()` 결과를 세 갈래로 가른다.
///
/// 예전엔 실패를 전부 같게 봐서, 이미 연결된 회원이 지하철에서 앱을 켜면
/// "미연결"로 오독돼 승인 대기 화면(또는 온보딩)에 떨어졌다 — 그 화면에서
/// 사용자가 할 수 있는 건 가입 **재요청**뿐이라, 대표 화면에 같은 사람이
/// 한 줄 더 쌓이는 것으로 끝났다.
///
/// 미연결로 단정하는 건 서버가 그렇게 답한 경우([MemberNotLinkedFailure])뿐이고,
/// 나머지는 전부 "모름"으로 둔다 — 모름 쪽으로 잘못 분류돼도 화면에 재확인과
/// "번호 다시 인증하기"가 함께 있어 사용자가 갇히지 않는다(반대 방향의
/// 오분류는 인증을 처음부터 다시 시킨다).
RestoreOutcome classifyRestore(Result<AppSession> result) => switch (result) {
      Ok<AppSession>() => RestoreOutcome.connected,
      Err<AppSession>(failure: MemberNotLinkedFailure()) => RestoreOutcome.notLinked,
      Err<AppSession>() => RestoreOutcome.unknown,
    };

/// 착지 라우트 — 판정만으로 결정되는 순수 함수. Firebase 신원이 살아 있는 전제에서만
/// 부른다(미로그인은 호출부가 먼저 null을 돌려준다).
///
/// **notLinked는 재검증 경로와 한 규칙이다**(P64 검증 반영). 종전엔 로컬 대기 기록이 있을
/// 때만 대기실이고 없으면 null(전화번호 화면)이라, 같은 회원·같은 서버 상태가 **캐시 유무**로
/// 갈렸다 — 캐시가 있으면 홈에 들어갔다가 재검증의 미연결 확답으로 대기실
/// (`sessionEndRoute(notLinked)`), 캐시가 없으면 콜드스타트에서 전화번호 화면(SMS 재인증).
/// 신원은 살아 있고 센터 연결만 없는 상태라 어느 쪽이든 대기실이 맞고, 대기실은 서버 상태
/// (거절·대기·요청 없음)를 그대로 보여 준다. 착지 문자열을 `sessionEndRoute`에서 가져오는
/// 이유가 그것이다 — 두 경로가 갈리면 같은 사람이 켤 때마다 다른 화면을 본다.
String? restoreLandingRoute({required RestoreOutcome outcome}) => switch (outcome) {
      RestoreOutcome.connected => '/home',
      RestoreOutcome.notLinked => sessionEndRoute(SessionEndReason.notLinked),
      // 모름 — 인증을 처음부터 시키는 대신 재확인할 수 있는 화면에 세운다.
      // (대기 기록이 있으면 그 화면이 대기 카드로 그려지고, 카드 안의
      // "연결됐는지 확인"이 그대로 재시도 버튼이 된다.)
      RestoreOutcome.unknown => '/login/center-confirm',
    };

/// 앱 시작 시 1회 — 남아 있는 Firebase 세션으로 되돌아갈 화면을 정한다.
///
/// 반환값이 곧 착지 라우트다:
/// - `/home` — GET /v1/me로 앱 세션 복원 성공(연결된 회원).
/// - `/login/center-confirm` — 서버가 확답한 미연결(대기실이 서버 상태를 보여 준다),
///   또는 연결 여부를 확인하지 못함(재확인 화면). 로컬 대기 기록이 번호와 맞으면
///   "승인 대기 중" 카드로 복귀한다.
/// - `null` — 복원할 게 없음(Firebase 미로그인). 온보딩 그대로.
///
/// 대기 상태를 로컬에 남기지 않던 시절엔 재실행 = 인증 처음부터 + "우리 센터가
/// 안 보여요" 도착이라, 사용자가 요청한 적 없다고 믿고 중복 요청을 보냈다.
Future<String?> restoreAuthLanding(WidgetRef ref) async {
  final User? user;
  try {
    user = FirebaseAuth.instance.currentUser;
  } catch (_) {
    return null; // Firebase 미초기화(위젯 테스트 등) — 온보딩 흐름.
  }
  if (user == null) return null;

  final store = ref.read(joinRequestStoreProvider);

  // ── 캐시된 세션이 있으면 **네트워크를 기다리지 않고** 홈으로 보낸다 ──
  //
  // 종전엔 앱을 켤 때마다 `GET /v1/me`가 성공해야 신원을 알 수 있어서, 지하철·
  // 엘리베이터에서 켜면 그 왕복이 끝날 때까지 아무것도 못 했고 실패하면 **이미
  // 로그인한 회원인데도** 로그인 계열 화면으로 떨어졌다.
  //
  // 캐시는 uid로 잠겨 있어(`SessionStore`) 다른 사람의 신원이 실릴 수 없다.
  final cached = await ref.read(sessionStoreProvider).read(user.uid);
  if (cached != null) {
    ref.read(sessionProvider.notifier).set(cached);
    // **여기서 기다리지 않고 검증을 띄운다.** 서버가 "이 회원 없음/권한 없음"이라
    // 답하면 그때 정정한다(아래 [_revalidate]). 기다리면 캐시를 둔 의미가 없다.
    _revalidate(ref, store);
    return '/home';
  }

  // **기동 예산에 상한을 둔다.** dio의 connect 10s + receive 10s는 재시도가 없어도
  // 최악 20초인데, 그동안 라우터는 아무것도 그리지 않는다(async redirect가 await
  // 중이라 `SizedBox.shrink()`). 회원은 그 20초를 **빈 창**으로 본다.
  //
  // 여기서 끊어도 잃는 게 없다: 시간이 초과하면 `unknown`으로 분류되고, 그 판정의
  // 착지 화면(`/login/center-confirm`)에는 **"연결됐는지 다시 확인"** 버튼이 있어
  // 회원이 직접 재시도할 수 있다. 20초를 더 기다려 같은 화면에 도착하는 것보다
  // 낫다.
  //
  // 6초인 근거: Cloud Run 콜드스타트가 실측 380~525ms(P12)라 서버는 싸고, 변동은
  // 전부 무선 구간이다. 6초를 넘기는 회선이면 한 번 더 기다리는 것보다 재시도
  // 버튼을 주는 편이 빠르다.
  final result = await ref
      .read(authRepositoryProvider)
      .loadSession()
      .timeout(restoreBudget, onTimeout: () => const Err(NetworkFailure(
            '연결이 느려요 — 아래에서 다시 확인해주세요',
          )));
  final outcome = classifyRestore(result);

  if (result case Ok(:final value)) {
    // memberName은 /v1/me의 name(계약 v2.2)에서 온다 — 이 경로엔 매칭 응답이
    // 없으므로(재실행이라 플로우 상태가 비어 있다) 이게 유일한 출처다.
    // best-effort라 비어 올 수 있고, 그때는 홈 헤더가 센터명으로 폴백한다.
    // `set()`이 캐시 저장까지 한다 — 다음 콜드 스타트는 이 값으로 즉시 뜬다.
    ref.read(sessionProvider.notifier).set(value);
    // 이미 연결됐으니 남아 있던 대기 기록은 폐기(승인된 뒤 첫 실행 경로).
    await store.clear();
    return restoreLandingRoute(outcome: outcome);
  }

  final notifier = ref.read(authViewModelProvider.notifier);
  await seedLobbyIdentity(notifier: notifier, joinStore: store, phone: user.phoneNumber);

  // **서버가 들고 있는 상태를 반영한다**(계약 v2.27, P56에서 보강).
  //
  // 종전엔 `MemberNotLinkedFailure`가 `joinStatus`·`joinRequestedAt`를 실어 오는데
  // 이 경로가 **한 번도 읽지 않았다**. 그래서 재확인(`checkConnection`)은 서버 상태를
  // 쓰고 콜드 스타트는 로컬 기록만 쓰는 **두 경로 분기**가 생겼다.
  // 재현: 가입 요청 → 대표가 **거절** → 앱 완전 종료 후 재실행 → 로컬 기록만 살아
  // "승인 대기 중"(거짓)이 뜨고, [연결됐는지 확인]을 눌러야만 거절 화면으로 정정된다.
  // `applyServerJoinStatus`의 dartdoc이 정확히 이 divergence를 막겠다고 선언해 뒀는데
  // 호출부가 여기 하나 비어 있었다.
  if (result case Err(failure: final MemberNotLinkedFailure f)) {
    notifier.applyServerJoinStatus(
      f.joinStatus,
      requestedAt: f.joinRequestedAt,
      centerId: f.centerId,
      joinCenterId: f.joinCenterId,
    );
  }
  if (result case Err(:final failure) when outcome == RestoreOutcome.unknown) {
    // 미연결로 단정하지 않는다 — 화면은 실패 사유를 보여주고 재확인을 권한다.
    notifier.markConnectionUnknown(failure);
  }

  return restoreLandingRoute(outcome: outcome);
}

/// 대기실에 서는 회원의 **신원**을 auth 상태에 세운다 — 콜드스타트([restoreAuthLanding])와
/// 캐시 재검증([applyRevalidation])이 같은 함수를 지난다(P64 검증 반영).
///
/// ① [phone](Firebase가 준 E.164)을 `AuthState.phone`으로. 종전엔 로컬 대기 기록이 맞을 때만
///    번호가 채워져, 기록이 없는 대기실은 빈 번호로 떴다(가입 요청의 로컬 기록이 ''로 저장).
/// ② 이 번호로 보낸 요청이 로컬에 남아 있으면 "승인 대기 중"으로 복귀. 번호 대조는 필수 —
///    대기는 기기가 아니라 **번호**의 상태라, 번호를 바꿔 로그인한 사용자에게 남의 대기 카드가
///    뜨면 안 된다.
///
/// 서버 가입 상태(`applyServerJoinStatus`)는 호출부가 **이 뒤에** 넘긴다 — 서버 상태가 로컬
/// 기록을 이기는 순서다(`centerConfirmStage` 규약).
@visibleForTesting
Future<void> seedLobbyIdentity({
  required AuthViewModel notifier,
  required JoinRequestStore joinStore,
  required String? phone,
}) async {
  if (phone == null || phone.isEmpty) return;
  notifier.restoreSignedInPhone(phone);
  final record = await joinStore.read();
  if (record != null && record.matches(phone)) notifier.restorePendingJoinRequest(record);
}


/// 캐시로 먼저 들여보낸 뒤 **뒤에서** 신원을 확인한다.
///
/// 화면은 이미 홈이다. 여기서 할 일은 둘뿐이다:
///  ① 서버가 확답한 실패(탈퇴·권한 상실 등)면 캐시를 지운다 — 안 지우면 다음
///     기동에도 같은 유령 신원으로 들어온다.
///  ② 성공이면 최신 값으로 갱신한다(이름이 바뀌었을 수 있다).
///
/// **네트워크 실패로는 지우지 않는다.** 지하철에서 한 번 실패했다고 캐시를 버리면
/// 이 기능이 존재하는 이유가 사라진다 — 신원이 틀렸다는 근거가 아니라 확인을
/// 못 했다는 뜻일 뿐이다.
///
/// 401은 여기서 다루지 않는다. dio 인터셉터가 세션을 비우고, 그 리스너가
/// 로그인으로 되돌린다(`app.dart`) — 캐시 삭제도 거기 묶여 있다.
Future<void> _revalidate(WidgetRef ref, JoinRequestStore joinStore) async {
  final result = await ref.read(authRepositoryProvider).loadSession();
  if (!ref.context.mounted) return;
  String? phone;
  try {
    phone = FirebaseAuth.instance.currentUser?.phoneNumber;
  } catch (_) {
    phone = null; // Firebase 미초기화(위젯 테스트 등) — 번호 없이 판정한다.
  }
  await applyRevalidation(read: ref.read, result: result, joinStore: joinStore, phone: phone);
}

/// [_revalidate]의 판정 본문 — 네트워크·위젯 수명 의존을 바깥에 두어 테스트가
/// `Result` 하나로 세 갈래의 부작용을 고정할 수 있게 뽑았다(P64).
///
/// [read]는 `WidgetRef.read`든 `ProviderContainer.read`든 같은 모양이다.
/// [phone]은 Firebase 신원의 번호 — notLinked 착지(대기실)에 세운다([seedLobbyIdentity]).
@visibleForTesting
Future<void> applyRevalidation({
  required T Function<T>(ProviderListenable<T> provider) read,
  required Result<AppSession> result,
  required JoinRequestStore joinStore,
  required String? phone,
}) async {
  // 세션이 이미 없다 — 그사이 로그아웃·탈퇴·401이 먼저 비웠다. 그쪽이 고른 착지를
  // 여기서 덮어쓰면(notLinked로 대기실) 탈퇴한 사람을 대기실에 세운다. 캐시도 그쪽이 지웠다.
  if (read(sessionProvider) == null) return;
  switch (classifyRestore(result)) {
    case RestoreOutcome.connected:
      if (result case Ok(:final value)) {
        read(sessionProvider.notifier).set(value);
        await joinStore.clear();
      }
    case RestoreOutcome.notLinked:
      // 서버가 **확답**한 미연결 — 캐시가 가리키는 회원이 더는 없다.
      //
      // 콜드스타트 경로([restoreAuthLanding]의 `applyServerJoinStatus` 호출)와 **같은
      // 규약**으로 서버가 든 대기 상태를 먼저 대기실에 넘긴다. 세션 리스너(`app.dart`)가
      // notLinked를 대기실로 착지시키는데, 이 호출이 없으면 대기실이 서버 상태(거절·
      // 대기)를 모른 채 빈 화면으로 뜬다 — 종전엔 이 경로만 이 값을 읽지 않았다.
      final notifier = read(authViewModelProvider.notifier);
      await seedLobbyIdentity(notifier: notifier, joinStore: joinStore, phone: phone);
      if (result case Err(failure: final MemberNotLinkedFailure f)) {
        notifier.applyServerJoinStatus(
          f.joinStatus,
          requestedAt: f.joinRequestedAt,
          centerId: f.centerId,
          joinCenterId: f.joinCenterId,
        );
      }
      await read(sessionStoreProvider).clear();
      read(sessionProvider.notifier).clear(reason: SessionEndReason.notLinked);
    case RestoreOutcome.unknown:
      // 확인 못 함. 캐시를 그대로 둔다(위 주석).
      break;
  }
}
