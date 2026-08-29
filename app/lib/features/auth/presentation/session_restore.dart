import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
/// "다른 번호로 다시 시도"가 함께 있어 사용자가 갇히지 않는다(반대 방향의
/// 오분류는 인증을 처음부터 다시 시킨다).
RestoreOutcome classifyRestore(Result<AppSession> result) => switch (result) {
      Ok<AppSession>() => RestoreOutcome.connected,
      Err<AppSession>(failure: MemberNotLinkedFailure()) => RestoreOutcome.notLinked,
      Err<AppSession>() => RestoreOutcome.unknown,
    };

/// 착지 라우트 — 판정과 대기 기록 유무만으로 결정되는 순수 함수.
/// null이면 기존 온보딩 흐름(`/login`).
String? restoreLandingRoute({
  required RestoreOutcome outcome,
  required bool hasPending,
}) =>
    switch (outcome) {
      RestoreOutcome.connected => '/home',
      // 서버가 확답한 미연결일 때만 온보딩으로 내려간다.
      RestoreOutcome.notLinked => hasPending ? '/login/center-confirm' : null,
      // 모름 — 인증을 처음부터 시키는 대신 재확인할 수 있는 화면에 세운다.
      // (대기 기록이 있으면 그 화면이 대기 카드로 그려지고, 카드 안의
      // "연결됐는지 확인"이 그대로 재시도 버튼이 된다.)
      RestoreOutcome.unknown => '/login/center-confirm',
    };

/// 앱 시작 시 1회 — 남아 있는 Firebase 세션으로 되돌아갈 화면을 정한다.
///
/// 반환값이 곧 착지 라우트다:
/// - `/home` — GET /v1/me로 앱 세션 복원 성공(연결된 회원).
/// - `/login/center-confirm` — 회원 연결은 아직이지만 이 번호로 보낸 가입 요청이
///   로컬에 남아 있음("승인 대기 중"으로 복귀), 또는 연결 여부를 확인하지 못함
///   (재확인 화면).
/// - `null` — 복원할 게 없음(미로그인, 또는 서버가 확답한 미연결). 온보딩 그대로.
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
    return restoreLandingRoute(outcome: outcome, hasPending: false);
  }

  // 이 번호로 보낸 요청이 남아 있으면 대기 화면으로 복귀시킨다. 번호 대조는
  // 필수: 대기는 기기가 아니라 **번호**의 상태라, 다른 번호로 로그인한
  // 사용자에게 남의 대기 카드가 뜨면 안 된다.
  final record = await store.read();
  final phone = user.phoneNumber;
  final pending =
      record != null && phone != null && record.matches(phone) ? record : null;

  final notifier = ref.read(authViewModelProvider.notifier);
  if (pending != null) notifier.restorePendingJoinRequest(pending);
  if (result case Err(:final failure) when outcome == RestoreOutcome.unknown) {
    // 미연결로 단정하지 않는다 — 화면은 실패 사유를 보여주고 재확인을 권한다.
    notifier.markConnectionUnknown(failure);
  }

  return restoreLandingRoute(outcome: outcome, hasPending: pending != null);
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
  switch (classifyRestore(result)) {
    case RestoreOutcome.connected:
      if (result case Ok(:final value)) {
        ref.read(sessionProvider.notifier).set(value);
        await joinStore.clear();
      }
    case RestoreOutcome.notLinked:
      // 서버가 **확답**한 미연결 — 캐시가 가리키는 회원이 더는 없다.
      await ref.read(sessionStoreProvider).clear();
      ref.read(sessionProvider.notifier).clear();
    case RestoreOutcome.unknown:
      // 확인 못 함. 캐시를 그대로 둔다(위 주석).
      break;
  }
}
