import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/me_api.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/network/dio_client.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/utils/phone_format.dart';
import 'package:rise_member/features/auth/data/auth_remote_data_source.dart';
import 'package:rise_member/features/auth/data/auth_repository_impl.dart';
import 'package:rise_member/features/auth/data/join_request_store_impl.dart';
import 'package:rise_member/features/auth/domain/auth_repository.dart';
import 'package:rise_member/features/auth/domain/join_request_store.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';

part 'auth_view_model.g.dart';

@riverpod
AuthRepository authRepository(Ref ref) {
  final dio = ref.watch(dioProvider);
  return AuthRepositoryImpl(AuthRemoteDataSource(dio), MeApi(dio));
}

/// 코드 화면이 "로그인이 방금 끝났다"를 알아채는 유일한 통로 —
/// 안드로이드 SMS 자동 회수가 `codeSent` **이후** 도착하는 정상 흐름을 잡는다.
/// (구독 시점의 기존 세션은 흘러오지 않는다 — [AuthRepository.signedInPhoneChanges].)
///
/// autoDispose인 채로 둔다: 구독자는 코드 화면 하나뿐이고, 그 화면이 사라지면
/// Firebase 스트림 구독까지 함께 정리돼야 한다(수명주기는 화면이 소유).
@riverpod
Stream<String?> signedInPhone(Ref ref) =>
    ref.watch(authRepositoryProvider).signedInPhoneChanges();

/// 가입 요청("승인 대기 중")의 로컬 영속 — 앱 재실행 복원(session_restore)과
/// 뷰모델이 공유한다.
@riverpod
JoinRequestStore joinRequestStore(Ref ref) => const SharedPreferencesJoinRequestStore();

/// [AuthViewModel.sendCode]의 다음 행선지 — 호출 화면이 이 값만 보고 라우팅한다.
/// bool 하나로는 "발송됨"과 "이미 인증됨"을 구분할 수 없어 화면이 항상
/// 코드 입력으로 갔다(오지 않을 코드를 기다리는 막다른 길).
enum SendCodeOutcome {
  /// 인증번호가 나갔다 — 코드 입력 화면으로.
  codeSent,

  /// 안드로이드 즉시 인증이 SMS 없이 로그인을 끝냈고 매칭까지 마쳤다 —
  /// 코드 화면을 건너뛰고 센터 확인으로.
  verified,

  /// 실패 — `state.error`가 화면에 인라인으로 뜬다(이동 없음).
  failed,
}

/// [AuthViewModel.checkConnection]의 결과 — "연결됐는지 확인" 버튼의 3갈래.
enum ConnectionCheck {
  /// 연결 완료 — 세션까지 세웠다. 호출부는 홈으로.
  connected,

  /// 서버가 "아직 연결 전"이라고 확답 — 대기 상태를 그대로 유지한다.
  notYet,

  /// 확인 자체를 못 했다(네트워크 등) — 아무 상태도 뒤집지 않는다.
  failed,
}

/// 전화번호 → 인증번호 → 센터 자동매칭 → 이름확인(P48) 전체 흐름을 관리.
/// 화면 3개(phone/code/center_confirm)가 이 하나의 Notifier를 공유한다.
///
/// keepAlive: sessionProvider와 같은 이유 — 라우팅 레이스로 상태가 사라지면 안 된다.
/// autoDispose면 앱 시작 복원 경로(session_restore가 화면 mount 전에 승인 대기
/// 상태를 심어 두는 구간)에서 구독자가 0이라 상태가 그대로 폐기된다(실측 확인).
/// 상태 초기화는 수명주기가 아니라 restartWithNewPhone()로 명시 처리한다.
@Riverpod(keepAlive: true)
class AuthViewModel extends _$AuthViewModel {
  @override
  AuthState build() => const AuthState();

  /// 번호가 바뀌면 직전 번호로 받아 둔 발송 세션은 통째로 무효다 —
  /// 남겨 두면 새 번호 요청에 옛 verificationId/resendToken이 실려 나가고,
  /// 입력해 둔 옛 코드가 그대로 제출된다.
  ///
  /// 같은 이유로 **직전 번호의 매칭 결과도 함께 버린다**. 매칭은 번호에 딸린
  /// 사실이라, 남겨 두면 새 번호를 입력한 사용자에게 옛 번호 주인의 이름이 뜬
  /// 채로 센터 확인 화면이 그려진다("네, OO 본인이에요"가 남의 이름을 가리킨다).
  void setPhone(String phone) {
    final changed = normalizeKoreanPhone(phone) != normalizeKoreanPhone(state.phone);
    state = state.copyWith(
      phone: phone,
      clearError: true,
      code: changed ? '' : null,
      clearVerification: changed,
      clearMatch: changed,
    );
  }

  void setCode(String code) => state = state.copyWith(code: code, clearError: true);

  /// 시트 안에서 인라인으로 소비한 에러가 시트 뒤 화면에 남지 않도록 정리.
  void clearError() => state = state.copyWith(clearError: true);

  /// phone_screen → "인증번호 받기". 재전송(code_screen)도 같은 경로 —
  /// 직전 codeSent의 resendToken을 함께 전달하되 [resend]로 진행 플래그를
  /// 분리한다(재전송 중에 확인 버튼이 "확인 중…"이라고 거짓 표시되던 문제).
  ///
  /// 돌려주는 [SendCodeOutcome]이 곧 다음 화면이다 — 특히 안드로이드 즉시 인증은
  /// **코드 화면을 건너뛴다**.
  Future<SendCodeOutcome> sendCode({bool resend = false}) async {
    state = resend
        ? state.copyWith(resending: true, clearError: true)
        : state.copyWith(submitting: true, clearError: true);
    final repo = ref.read(authRepositoryProvider);
    final result =
        await repo.requestVerificationCode(state.phone, resendToken: state.resendToken);

    switch (result) {
      case Err(:final failure):
        state = state.copyWith(submitting: false, resending: false, error: failure);
        return SendCodeOutcome.failed;

      case Ok(:final value):
        state = state.copyWith(
          verificationId: value.verificationId,
          resendToken: value.resendToken,
          // 새 코드가 나갔으니 직전에 입력해 둔 코드는 무효 — 화면의 입력창도 같이 비운다.
          code: '',
        );

        // 안드로이드 즉시 인증(verificationCompleted): SMS 없이 로그인이 이미
        // 끝나 verificationId가 **빈 문자열**로 온다. 입력할 코드가 존재하지
        // 않으므로 코드 화면으로 보내면 "…로 보냈어요"라고 거짓 안내하고 오지
        // 않을 코드의 재전송 카운트다운을 돈다 — 코드 확인 뒤와 같은 매칭 경로로
        // 곧장 잇는다(진행 표시는 매칭이 끝날 때 함께 내린다).
        //
        // 빈 verificationId는 상태에도 그대로 남긴다(null이 아니다) — 매칭이
        // 실패해 사용자가 이 화면에 머물더라도 "확인"이 currentUser 지름길로
        // 재시도할 수 있어야 한다.
        if (value.verificationId.isEmpty) {
          final matched = await _matchAfterSignIn();
          return matched ? SendCodeOutcome.verified : SendCodeOutcome.failed;
        }

        state = state.copyWith(submitting: false, resending: false);
        return SendCodeOutcome.codeSent;
    }
  }

  /// code_screen → "확인". 인증 성공 시 곧바로 join/match까지 호출.
  Future<bool> verifyAndMatch() async {
    final verificationId = state.verificationId;
    if (verificationId == null) {
      // 발송 성공 없이 코드 화면에 온 상태(라우팅 이상) — 재발송 유도.
      state = state.copyWith(error: const AuthFailure('인증번호를 다시 요청해주세요'));
      return false;
    }

    state = state.copyWith(submitting: true, clearError: true);
    final repo = ref.read(authRepositoryProvider);

    final verify = await repo.verifyCode(
      phone: state.phone,
      verificationId: verificationId,
      code: state.code,
    );
    if (verify case Err(:final failure)) {
      state = state.copyWith(submitting: false, error: failure);
      return false;
    }

    return _matchAfterSignIn();
  }

  /// 안드로이드 SMS 자동 회수가 **codeSent 이후** 로그인을 끝낸 경우 —
  /// 코드 화면이 [signedInPhoneProvider]로 감지해 부른다.
  ///
  /// P08이 처리한 즉시 인증(codeSent **이전**)은 [sendCode]가 빈 verificationId로
  /// 받아 그 자리에서 매칭까지 끝내므로 코드 화면에 도달조차 하지 않는다. 여기는
  /// 그 반대편 — 코드 화면에 이미 들어와 카운트다운을 도는 동안 문자가 자동으로
  /// 회수되는, 오히려 더 흔한 정상 흐름이다.
  ///
  /// 두 경로가 겹쳐 매칭이 두 번 나가지 않게 두 겹으로 막는다:
  ///  · [AuthState.busy] — 사용자가 방금 "확인"을 눌렀거나 재전송이 진행 중이면
  ///    그쪽이 같은 [_matchAfterSignIn]에 도달한다. 여기서는 물러난다.
  ///  · [AuthState.match] — 이미 매칭을 마쳤으면 다시 물을 이유가 없다. 번호를
  ///    바꾸면 [setPhone]이 이 값을 비우므로 재인증 흐름을 막지 않는다.
  ///
  /// [signedInPhone]은 Firebase가 준 E.164 번호다. **이 화면이 인증하려던 번호와
  /// 같을 때만** 진행한다 — 다른 번호로 남아 있던 세션이 지금 인증을 가로채
  /// 남의 계정으로 넘어가면 안 된다.
  Future<bool> completeAutoVerification(String signedInPhone) async {
    if (state.busy || state.match != null) return false;
    if (signedInPhone != normalizeKoreanPhone(state.phone)) return false;

    state = state.copyWith(submitting: true, clearError: true);
    return _matchAfterSignIn();
  }

  /// 로그인이 끝난 직후 공통 경로 — 코드 확인([verifyAndMatch])과 즉시 인증
  /// ([sendCode])이 도달하는 지점이 같으므로 매칭도 한 곳에서만 한다.
  /// 성공/실패 어느 쪽이든 진행 플래그(submitting·resending)를 함께 내린다.
  Future<bool> _matchAfterSignIn() async {
    final matchResult = await ref.read(authRepositoryProvider).matchJoin(state.phone);
    switch (matchResult) {
      case Err(:final failure):
        state = state.copyWith(submitting: false, resending: false, error: failure);
        return false;
      case Ok(:final value):
        // 매칭이 없으면 이 번호로 이미 보낸 가입 요청이 남아 있는지 본다.
        // 확인하지 않으면 재인증한 사용자에게 "찾지 못했어요"만 보여주게 되고,
        // 사용자는 같은 요청을 또 보내 대표 화면에 같은 사람이 두 줄 쌓인다.
        final pending = value.member == null ? await _pendingFor(state.phone) : null;
        state = state.copyWith(
          submitting: false,
          resending: false,
          match: value,
          matchDeclined: false,
          joinRequestedAt: pending?.requestedAt,
          // 서버가 매칭에 답했다 = 연결 상태를 물어볼 수 있는 상태 —
          // 복원 때 걸어 둔 "확인 못 함" 폴백은 여기서 내린다.
          connectionUnknown: false,
        );
        final trainerId = value.member?.trainerId;
        if (trainerId != null) _resolveTrainerName(trainerId);
        return true;
    }
  }

  /// 로컬에 남은 가입 요청 중 [phone]의 것만 돌려준다(번호 대조 필수 —
  /// 대기는 기기가 아니라 번호의 상태다).
  Future<JoinRequestRecord?> _pendingFor(String phone) async {
    final record = await ref.read(joinRequestStoreProvider).read();
    return record != null && record.matches(phone) ? record : null;
  }

  Future<void> _resolveTrainerName(String trainerId) async {
    try {
      final map = await ref.read(staffMapProvider.future);
      if (!ref.mounted) return;
      state = state.copyWith(trainerName: map[trainerId]?.name);
    } catch (_) {
      // best-effort — 이름 보강 실패해도 로그인 흐름은 계속.
    }
  }

  /// center_confirm_screen → "네, OO 본인이에요" / "본인이 아니에요".
  Future<bool> confirmMatch(bool confirm) async {
    final memberId = state.match?.member?.id;
    if (memberId == null) return false;

    state = state.copyWith(submitting: true, clearError: true);
    final repo = ref.read(authRepositoryProvider);
    final store = ref.read(joinRequestStoreProvider);
    // 인증 플로우의 전화번호를 함께 보낸다 — 서버가 회원 레코드와 재대조(계약 v1.3, 탈취 체인 차단).
    final confirmResult = await repo.confirmJoin(memberId: memberId, confirm: confirm, phone: state.phone);

    if (confirmResult case Err(:final failure)) {
      state = state.copyWith(submitting: false, error: failure);
      return false;
    }
    if (!confirm) {
      // 매칭 카드를 지우고(clearMatch) 거부 안내 카드로 전환 — 가입 요청 경로와
      // "다른 번호로 다시 시도" 탈출구는 화면이 상시 노출한다.
      state = state.copyWith(submitting: false, clearMatch: true, matchDeclined: true);
      return false;
    }

    final sessionResult = await repo.loadSession();
    switch (sessionResult) {
      case Err(:final failure):
        state = state.copyWith(submitting: false, error: failure);
        return false;
      case Ok(:final value):
        ref.read(sessionProvider.notifier).set(_withDisplayName(value));
        state = state.copyWith(submitting: false);
        // 연결이 끝났으니 "승인 대기 중" 로컬 기록은 폐기 — 남겨 두면 다음 실행에서
        // 이미 연결된 사용자에게 대기 카드가 뜬다.
        await store.clear();
        return true;
    }
  }

  /// "우리 센터가 안 보여요" → 이름·연락처(인증 플로우의 번호)로 가입 요청.
  /// 성공 시각을 기록해 center_confirm이 "승인 대기 중" 카드로 고정되고
  /// 30초 카운트다운 후에만 재요청을 허용한다(중복 제출 방지).
  /// 같은 시각을 로컬에도 남겨(JoinRequestStore) 앱을 껐다 켜도 대기 상태로 복귀한다.
  Future<bool> requestJoin(String name) async {
    state = state.copyWith(submitting: true, clearError: true);
    final repo = ref.read(authRepositoryProvider);
    final store = ref.read(joinRequestStoreProvider);
    final result = await repo.requestJoin(name: name, phone: state.phone);

    if (result case Err(:final failure)) {
      state = state.copyWith(submitting: false, error: failure);
      return false;
    }

    final requestedAt = DateTime.now();
    final phone = normalizeKoreanPhone(state.phone);
    state = state.copyWith(submitting: false, joinRequestedAt: requestedAt);
    await store.save(JoinRequestRecord(phone: phone, requestedAt: requestedAt));
    return true;
  }

  /// 앱 재실행 복원 전용 — 로컬에 남은 가입 요청을 "승인 대기 중"으로 되살린다.
  /// 번호 대조는 호출부(session_restore)가 이미 끝낸 상태로 들어온다.
  void restorePendingJoinRequest(JoinRequestRecord record) {
    state = state.copyWith(phone: record.phone, joinRequestedAt: record.requestedAt);
  }

  /// 앱 재실행 복원 전용 — 연결 여부를 **확인하지 못했음**을 화면에 남긴다.
  /// 미연결로 단정하지 않으므로 온보딩으로 밀지 않고, [checkConnection] 재시도가
  /// 정상 경로가 된다. 실패 사유는 화면이 인라인으로 보여준다.
  void markConnectionUnknown(Failure failure) {
    state = state.copyWith(connectionUnknown: true, error: failure);
  }

  /// "연결됐는지 확인" — 대표가 승인했는지 서버에 한 번 더 물어본다(GET /v1/me).
  ///
  /// 가입 요청을 **다시 보내는 것**만이 유일한 확인 수단이던 시절엔, 확인하려는
  /// 시도가 곧 대표 화면에 같은 사람을 한 줄 더 쌓는 행위였다. 이 경로는
  /// 아무것도 새로 만들지 않는 읽기 전용 확인이다.
  ///
  /// 실패해도 대기 상태([AuthState.joinRequestedAt])는 건드리지 않는다 —
  /// 확인에 실패했다고 대기 사실이 사라지면 사용자는 또 요청을 보낸다.
  Future<ConnectionCheck> checkConnection() async {
    // 연타 방지 — 버튼도 busy로 잠그지만, 진행 중 재진입이 세션을 두 번 세우는
    // 일이 없도록 뷰모델에서도 막는다.
    if (state.busy) return ConnectionCheck.failed;

    state = state.copyWith(checkingConnection: true, clearError: true);
    final result = await ref.read(authRepositoryProvider).loadSession();

    switch (result) {
      case Ok(:final value):
        ref.read(sessionProvider.notifier).set(_withDisplayName(value));
        state = state.copyWith(checkingConnection: false, connectionUnknown: false);
        // 연결됐으니 "승인 대기 중" 로컬 기록은 폐기(confirmMatch와 같은 이유).
        await ref.read(joinRequestStoreProvider).clear();
        return ConnectionCheck.connected;

      case Err(failure: MemberNotLinkedFailure()):
        // 서버가 "아직"이라고 확답했다 — 오류가 아니므로 error로 남기지 않고
        // (빨간 문구는 과잉) 호출부가 안내 문구로 처리한다.
        state = state.copyWith(checkingConnection: false, connectionUnknown: false);
        return ConnectionCheck.notYet;

      case Err(:final failure):
        // 확인 실패 — 연결됐는지 여전히 모른다. connectionUnknown은 그대로 둔다
        // (대기 화면에서 눌렀다면 대기 화면 그대로, 재확인 화면이었다면 그대로).
        state = state.copyWith(checkingConnection: false, error: failure);
        return ConnectionCheck.failed;
    }
  }

  /// 세션에 표시용 이름을 확정한다 — **로그인 경로와 재실행 복원 경로가 같은
  /// 결과를 내게 하는 지점**이다.
  ///
  /// 1차 출처는 GET /v1/me의 `name`(계약 v2.2). 앱 재실행 복원은 /v1/me 하나로
  /// 세션을 세우므로 이것 말고는 이름의 출처가 없고, 그래서 이 필드가 생기기
  /// 전까진 같은 홈 헤더가 최초 로그인 땐 "김민지 님", 재실행 뒤엔 센터명으로
  /// 갈렸다(P09 실기기 점검).
  ///
  /// 2차는 이 플로우가 방금 받아 둔 매칭 응답의 이름 — 서버 쪽 `name`은
  /// best-effort라 비어 올 수 있고(조회 실패·구버전 서버), 그 경우에도 최초
  /// 로그인만큼은 이름을 띄울 수 있으면 띄운다. 둘 다 없으면 ''로 두고
  /// 헤더의 센터명 폴백에 맡긴다(빈 문자열을 그대로 렌더하면 "  님"이 된다).
  AppSession _withDisplayName(AppSession session) {
    if (session.memberName.isNotEmpty) return session;
    final fallback = CoachLabel.nameOrNull(state.match?.member?.name);
    return fallback == null ? session : session.withMemberName(fallback);
  }

  /// "다른 번호로 다시 시도" — 어떤 상태(매칭됨/본인 아님/승인 대기/매칭 실패)에서도
  /// 열려 있어야 하는 탈출구. Firebase 세션을 끊고 플로우 상태를 처음으로 되돌린다.
  ///
  /// 로컬 대기 기록은 **일부러 지우지 않는다**. 대기는 기기가 아니라 그 번호의
  /// 상태이고(다른 번호로는 JoinRequestRecord.matches가 막는다), 여기서 지우면
  /// 번호를 잘못 눌러 나갔다 같은 번호로 돌아온 사용자가 대기 사실을 잃고 같은
  /// 요청을 또 보내게 된다. 폐기 시점은 오직 "연결 완료"다.
  Future<void> restartWithNewPhone() async {
    state = state.copyWith(submitting: true, clearError: true);
    await ref.read(authRepositoryProvider).signOut();
    if (!ref.mounted) return;
    state = const AuthState();
  }
}
