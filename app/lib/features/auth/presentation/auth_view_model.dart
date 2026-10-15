import 'package:clock/clock.dart';
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
import 'package:rise_member/features/auth/domain/auth_models.dart';
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

/// 가입 요청을 보낼 수 있는 센터 목록(계약 v2.33).
///
/// **고를 것이 2곳 이상일 때만 화면이 선택을 묻는다**(`hasChoice`). 센터가 하나뿐인데 선택
/// 화면을 띄우면 회원에게 "고를 수 있다"는 거짓 인상을 주고 탭만 하나 늘린다.
///
/// 실패는 **빈 목록으로 접는다** — 이 조회가 실패했다고 가입 요청 자체를 막으면 안 된다.
/// 센터 없이 보낸 요청은 서버가 기본 센터로 폴백하므로(v2.33) 종전 동작이 그대로 남는다.
/// autoDispose: 대기실을 떠나면 필요 없다.
@riverpod
Future<List<CenterDirectory>> joinCenters(Ref ref) async {
  final result = await ref.watch(authRepositoryProvider).fetchJoinCenters();
  return switch (result) {
    Ok(:final value) => value,
    Err() => const <CenterDirectory>[],
  };
}

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

/// [AuthViewModel.requestJoin]의 결과 — 시트가 닫을지·무슨 스낵바를 띄울지 이 값만 본다.
enum JoinRequestOutcome {
  /// 서버가 접수했다 — 대기 화면으로.
  sent,

  /// 서버에 **이미 pending이 있다**(409 `join_pending`, 계약 v2.34). 실패가 아니라 pending 확답 —
  /// 뷰모델이 상태를 pending으로 승격했으므로 화면은 성공처럼 닫되 문구만 다르다.
  alreadyPending,

  /// 실패 — `state.error`가 시트 안에 인라인으로 뜬다.
  failed,
}

/// [AuthViewModel.checkConnection]의 결과 — "연결됐는지 확인" 버튼의 4갈래.
enum ConnectionCheck {
  /// 연결 완료 — 세션까지 세웠다. 호출부는 홈으로.
  connected,

  /// 서버는 "아직 연결 전"이라 답했지만, **같은 번호로 회원 레코드를 새로 찾았다**(P72 C1).
  /// 데스크가 그 사이 회원을 등록했거나 번호를 고친 경우다 — 이름 확인 한 번이면 연결된다.
  /// 화면은 그대로 머물되(`centerConfirmStage`가 이미 `matched`로 바뀌었다) 무슨 일이
  /// 일어났는지 알려야 한다. [connected]와 달리 **홈으로 보내지 않는다** — 남의 계정에
  /// 붙지 않게 막는 이름 확인 1탭을 건너뛸 수 없다.
  nowMatched,

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
  /// 같을 때만** 진행한다 — 다른 번호의 세션이 남아 있다가 지금 인증을 가로채
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

  /// 대기실에서 번호 매칭만 다시 묻는다 — 회원을 새로 찾았으면 true(P72 C1).
  ///
  /// [_matchAfterSignIn]을 재사용하지 **않는** 이유: 그쪽은 `joinRequestedAt`를 로컬 기록으로
  /// 덮어쓰고 `submitting`을 내린다. 대기실에서는 방금 서버가 준 가입 요청 상태가 로컬 기록을
  /// 이겨야 하고(`centerConfirmStage` 규약), 진행 플래그의 주인도 [checkConnection]이다.
  /// 여기서 만지는 칸은 **`match` 하나**다.
  ///
  /// 실패는 **삼킨다**. 방금 `GET /v1/me`가 "아직"이라고 성공적으로 답한 참이라, 보조 조회가
  /// 넘어졌다고 그 답을 빨간 에러로 덮으면 확인 상태 줄의 "마지막 확인 12:14"가 거짓이 된다.
  ///
  /// 이미 매칭이 살아 있으면 묻지 않는다 — 화면은 이미 `matched`이고 답이 바뀔 이유가 없다.
  Future<bool> _rematchInLobby() async {
    if (state.match?.member != null) return false;
    if (state.phone.isEmpty) return false; // 신원을 모르는 경로(복원 실패) — 물을 번호가 없다.
    final result = await ref.read(authRepositoryProvider).matchJoin(state.phone);
    if (result case Ok(:final value) when value.member != null) {
      state = state.copyWith(match: value, matchDeclined: false);
      final trainerId = value.member?.trainerId;
      if (trainerId != null) _resolveTrainerName(trainerId);
      return true;
    }
    return false;
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
      // "번호 다시 인증하기" 탈출구는 화면이 상시 노출한다.
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
  ///
  /// 409 `join_pending`([JoinPendingFailure], 계약 v2.34)은 실패로 다루지 않는다 — 서버가
  /// "이미 pending이 있다"고 **확답**한 것이라 `serverJoinStatus='pending'`으로 승격한다. 종전엔
  /// 이 409가 시트 안 빨간 문구로 끝나, 서버가 `/v1/me`에 요청을 안 실어 준 상태(타 센터 큐·
  /// 조회 실패)에서는 "다시 요청 → 409 → 다시 요청"의 막다른 길이었다(plan C 4-c).
  Future<JoinRequestOutcome> requestJoin(String name, {String centerId = ''}) async {
    state = state.copyWith(submitting: true, clearError: true);
    final repo = ref.read(authRepositoryProvider);
    final store = ref.read(joinRequestStoreProvider);
    final result =
        await repo.requestJoin(name: name, phone: state.phone, centerId: centerId);

    final phone = normalizeKoreanPhone(state.phone);
    if (result case Err(failure: final JoinPendingFailure pending)) {
      // 요청 시각은 모른다(서버 것이다) — 상태에 지어 넣지 않는다. 다음 확인(GET /v1/me)이
      // `created_at`을 준다. 로컬 기록은 재실행 복귀용이라 지금 시각으로 남긴다(종전 규약).
      state = state.copyWith(
        submitting: false,
        serverJoinStatus: 'pending',
        joinCenterId: pending.centerId.isNotEmpty ? pending.centerId : centerId,
      );
      if (phone.isNotEmpty) {
        await store.save(JoinRequestRecord(
          phone: phone,
          requestedAt: DateTime.now(),
          centerId: pending.centerId.isNotEmpty ? pending.centerId : centerId,
        ));
      }
      return JoinRequestOutcome.alreadyPending;
    }
    if (result case Err(:final failure)) {
      state = state.copyWith(submitting: false, error: failure);
      return JoinRequestOutcome.failed;
    }

    final requestedAt = DateTime.now();
    // `serverJoinStatus`를 **함께** 세운다(P56). `centerConfirmStage`는 `rejected`를
    // pending보다 먼저 판정하므로, 거절 화면에서 재요청이 성공해도 이 한 줄이 없으면
    // **화면이 한 픽셀도 안 바뀐다**. 그런데 서버는 이전 요청이 rejected면 중복 409를
    // 내지 않아 **요청은 실제로 접수된다** — 회원이 반복하면 대표 큐에 진짜로 여러 줄이
    // 쌓인다. P55가 없애려던 중복 큐가 정확히 이 자리로 되살아난다.
    state = state.copyWith(
      submitting: false,
      joinRequestedAt: requestedAt,
      serverJoinStatus: 'pending',
      // 고른 센터를 함께 남긴다(v2.33) — 대기실 센터 카드가 그 센터의 연락처를 보여준다.
      joinCenterId: centerId,
    );
    // 번호를 모르면 로컬 기록을 남기지 않는다(P64 검증 반영). 서버는 토큰의 번호로 접수하므로
    // 요청 자체는 유효하지만, 빈 번호로 저장한 기록은 어떤 번호와도 `matches`하지 않아 복원
    // 때 죽은 줄이 되거나, 정규화가 ''를 돌려주는 다른 입력과 잘못 맞는다. 번호는 로그인
    // 플로우와 복원 경로([restoreSignedInPhone])가 세운다 — 비어 있다면 그쪽이 빠진 것이다.
    if (phone.isNotEmpty) {
      await store.save(
        JoinRequestRecord(phone: phone, requestedAt: requestedAt, centerId: centerId),
      );
    }
    return JoinRequestOutcome.sent;
  }

  /// 복원·재검증 전용 — Firebase 신원의 번호를 대기실에 세운다(P64 검증 반영).
  ///
  /// 콜드스타트(캐시 없음)와 캐시 재검증이 미연결 확답을 받으면 둘 다 대기실에 서는데,
  /// 종전엔 로컬 대기 기록이 번호와 맞을 때만 [restorePendingJoinRequest]가 번호를 채웠다.
  /// 기록이 없으면 `phone`이 ''인 채 대기실이 떠서 가입 요청의 로컬 기록이 빈 번호로 저장됐다.
  /// [setPhone]과 달리 발송 세션·매칭 결과를 건드리지 않는다 — 사용자가 번호를 **바꾼**
  /// 게 아니라 같은 신원을 복원한 것이다.
  void restoreSignedInPhone(String phone) {
    state = state.copyWith(phone: normalizeKoreanPhone(phone));
  }

  /// 앱 재실행 복원 전용 — 로컬에 남은 가입 요청을 "승인 대기 중"으로 되살린다.
  /// 번호 대조는 호출부(session_restore)가 이미 끝낸 상태로 들어온다.
  void restorePendingJoinRequest(JoinRequestRecord record) {
    state = state.copyWith(
      phone: record.phone,
      joinRequestedAt: record.requestedAt,
      // 로컬 기록의 센터는 폴백이다 — 서버 값이 뒤에 오면(applyServerJoinStatus) 그쪽이 덮는다.
      joinCenterId: record.centerId,
    );
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
  /// [auto]면 **화면 컨트롤을 잠그지 않는다**(P72 C10) — 자동 틱은 사용자가 시작한 동작이
  /// 아니므로 그 30초 주기가 탈출구 링크를 함께 회색으로 만들면 안 된다.
  Future<ConnectionCheck> checkConnection({bool auto = false}) async {
    // 연타 방지 — 버튼도 busy로 잠그지만, 진행 중 재진입이 세션을 두 번 세우는
    // 일이 없도록 뷰모델에서도 막는다. 자동·수동 어느 쪽이 날아가는 중이든 막는다.
    if (state.busy || state.anyCheckInFlight) return ConnectionCheck.failed;

    state = auto
        ? state.copyWith(autoChecking: true)
        : state.copyWith(checkingConnection: true, clearError: true);
    final result = await ref.read(authRepositoryProvider).loadSession();

    // 확인 상태 줄의 시각 — **성공(connected/notYet)에만** lastCheckedAt, 실패엔 lastCheckFailedAt.
    // 실패한 호출의 시각을 "마지막 확인"으로 찍으면 그 문장이 거짓이 된다(plan B §3).
    final now = clock.now();
    switch (result) {
      case Ok(:final value):
        ref.read(sessionProvider.notifier).set(_withDisplayName(value));
        state = state.copyWith(
          checkingConnection: false,
          autoChecking: false,
          connectionUnknown: false,
          lastCheckedAt: now,
        );
        // 연결됐으니 "승인 대기 중" 로컬 기록은 폐기(confirmMatch와 같은 이유).
        await ref.read(joinRequestStoreProvider).clear();
        return ConnectionCheck.connected;

      case Err(failure: final MemberNotLinkedFailure f):
        // 서버가 "아직"이라고 확답했다 — 오류가 아니므로 error로 남기지 않고
        // (빨간 문구는 과잉) 호출부가 안내 문구로 처리한다.
        //
        // 계약 v2.27: 같은 응답이 가입 요청 상태도 들고 온다. **이 값이 로컬 기록을
        // 이긴다** — 기기를 바꿔 로컬 근거가 없어도 대기/거절 화면이 제대로 선다.
        //
        // 서버가 요청 없음(null)이라 답하면 옛 `pending`을 **명시적으로 지운다** — copyWith의
        // `?? this`는 null을 못 지우므로, 그 사이 센터가 지운 요청이 삭제 고지에 "보낸 가입
        // 요청 (이름·전화번호)"로 남는다. 로컬 대기 기록(joinRequestedAt)은 종전대로 둔다.
        state = state.copyWith(
          checkingConnection: false,
          autoChecking: false,
          connectionUnknown: false,
          serverJoinStatus: f.joinStatus,
          clearServerJoinStatus: f.joinStatus == null,
          joinRequestedAt: f.joinRequestedAt,
          centerId: f.centerId,
          joinCenterId: f.joinCenterId,
          lastCheckedAt: now,
        );
        // **여기서 번호 매칭을 한 번 더 묻는다**(P72 C1). `GET /v1/me`는 uid→UserIndex만
        // 보므로(`service.go` Me), 데스크가 그 사이 이 번호를 등록하거나 고쳐도 영원히
        // "아직"이라고 답한다. 연결을 만드는 유일한 호출은 `POST /v1/join/match`인데
        // 종전엔 **코드 인증 직후 1회**만 돌았다 — 그 창을 놓친 사람은 SMS 재인증 전까지
        // 구조적으로 연결될 수 없었고, 대표가 큐에서 승인하려 해도 "같은 번호로 등록된
        // 회원이 이미 있어요" 409에 막혔다(`JoinApprove` 중복 가드). 화면은 "센터가
        // 승인하면 연결돼요"라고 약속하며 30초마다 폴링만 했다.
        //
        // JoinMatch는 **읽기 전용·멱등**이고(조회만 한다) 프로덕션에선 번호를 토큰에서
        // 강제로 가져오므로(`joinPhone`) 재호출에 새 표면이 없다. 대표 큐에 줄을 쌓지도
        // 않는다(그건 `join/request`다).
        return await _rematchInLobby() ? ConnectionCheck.nowMatched : ConnectionCheck.notYet;

      case Err(:final failure):
        // 확인 실패 — 연결됐는지 여전히 모른다. connectionUnknown은 그대로 둔다
        // (대기 화면에서 눌렀다면 대기 화면 그대로, 재확인 화면이었다면 그대로).
        state = state.copyWith(
          checkingConnection: false,
          autoChecking: false,
          // 자동 틱의 실패로는 빨간 문구를 띄우지 않는다(P72) — 30초마다 에러가 나타났다
          // 사라지기를 반복한다. 실패 사실은 확인 상태 줄의 "HH:mm 확인 못 함"이 말한다.
          error: auto ? null : failure,
          clearError: auto,
          lastCheckFailedAt: now,
        );
        return ConnectionCheck.failed;
    }
  }

  /// 서버가 준 가입 요청 상태를 반영한다(계약 v2.27).
  ///
  /// 세션 복원(`restoreAuthLanding`)과 재확인(`checkConnection`)이 같은 값을 같은
  /// 자리에 넣게 하는 지점 — 두 경로가 갈리면 "복원했을 땐 거절인데 재확인하면
  /// 대기"처럼 화면이 흔들린다.
  ///
  /// null(서버에 요청 없음)은 **지우는 값**이다 — `checkConnection`의 미연결 분기와 같은 규약.
  void applyServerJoinStatus(
    String? status, {
    DateTime? requestedAt,
    String centerId = '',
    String joinCenterId = '',
  }) {
    state = state.copyWith(
      serverJoinStatus: status,
      clearServerJoinStatus: status == null,
      joinRequestedAt: requestedAt,
      centerId: centerId,
      joinCenterId: joinCenterId,
    );
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

  /// "번호 다시 인증하기" — 어떤 상태(매칭됨/본인 아님/승인 대기/매칭 실패)에서도
  /// 열려 있어야 하는 탈출구. Firebase 세션을 끊고 플로우 상태를 처음으로 되돌린다.
  ///
  /// 로컬 대기 기록은 **일부러 지우지 않는다**. 대기는 기기가 아니라 그 번호의
  /// 상태이고(번호가 다르면 JoinRequestRecord.matches가 막는다), 여기서 지우면
  /// 번호를 잘못 눌러 나갔다 같은 번호로 돌아온 사용자가 대기 사실을 잃고 같은
  /// 요청을 또 보내게 된다. 폐기 시점은 오직 "연결 완료"다.
  Future<void> restartWithNewPhone() async {
    state = state.copyWith(submitting: true, clearError: true);
    await ref.read(authRepositoryProvider).signOut();
    if (!ref.mounted) return;
    state = const AuthState();
  }
}
