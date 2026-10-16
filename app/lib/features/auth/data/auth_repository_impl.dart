import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:rise_member/core/api/me_api.dart';
import 'package:rise_member/core/network/api_result_guard.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/utils/phone_format.dart';
import 'package:rise_member/features/auth/domain/auth_config.dart';
import 'package:rise_member/features/auth/data/auth_remote_data_source.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';
import 'package:rise_member/features/auth/domain/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._remote, this._meApi);

  final AuthRemoteDataSource _remote;
  final MeApi _meApi;

  /// 지연 접근 — 리포지토리 생성 시점엔 Firebase 미초기화여도 안전(테스트 등).
  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// codeSent가 정상 응답에서 즉시 오는 데 대한 보험 — 어떤 콜백도 안 오는
  /// 플랫폼 이상 상황에서 UI가 "전송 중…"에 갇히지 않게 하는 상한.
  ///
  /// **사람이 reCAPTCHA를 푸는 시간을 담아야 한다**(P75). APNs가 없는 iOS는 실번호 인증이 전부 사파리
  /// 시트를 지나고(Android는 Play Integrity 실패 시 Custom Tab), 그림 문제가 뜨면 사람이 푼다. 시계는
  /// verifyPhoneNumber가 리스너만 걸고 반환한 직후부터 흐르고 네이티브 시트는 이 상한과 무관하게 계속
  /// 돈다 — 종전 70초는 문제를 늦게 푼 회원에게 "지연" 오류를 띄운 뒤 SMS를 보내고(늦은 codeSent는
  /// completeOnce가 버린다), 다시 누르면 두 번째 SMS가 나갔다. reCAPTCHA 문제 화면은 약 2분이면 만료되므로
  /// 그보다 넉넉하게 둔다. 시트가 떠 있는 동안 회원은 시트를 닫아 즉시 오류(web-context-cancelled)를 받을
  /// 수 있으니, 늘린 비용은 "콜백이 영영 안 오는" 병적 경우의 대기뿐이다.
  static const _codeSentTimeout = Duration(seconds: 180);

  // ── 전화번호 인증: Firebase Phone Auth 실연동 (P06) ───────────────────────
  @override
  Future<Result<PhoneVerificationSession>> requestVerificationCode(
    String phone, {
    int? resendToken,
  }) async {
    if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
      return const Err(ValidationFailure('휴대폰 번호를 다시 확인해주세요'));
    }
    final normalized = normalizeKoreanPhone(phone);

    // 앱 무결성 검증(Play Integrity/reCAPTCHA/APNs) 생략 스위치.
    //
    // 디버그: 시뮬레이터·에뮬레이터엔 APNs·Play Integrity가 없어 이게 없으면 개발이 막힌다.
    //
    // 릴리스: **스토어 심사 계정 한 번호에만** 연다. 심사자는 우리 기기·네트워크가 아니라
    // 어떤 환경에서 열지 알 수 없는데, APNs 사일런트 검증이나 reCAPTCHA 웹뷰가 한 번이라도
    // 걸리면 로그인 못 한 채로 리젝이 온다(왕복 며칠). 이 스위치를 켠 상태에서 Firebase는
    // **콘솔에 등록된 테스트 번호만** 받아준다 — 실번호로는 인증이 되레 실패하므로,
    // 이 분기가 일반 회원의 인증을 우회시키는 통로가 되지 않는다.
    //
    // **요청마다 켜고 끈다**(P77): 이 스위치는 Auth 인스턴스에 남는다(프로세스 전역). 종전엔 켜기만 해서
    // 같은 실행에서 심사 번호 다음에 다른 번호를 넣으면 앱 검증이 꺼진 채 나갔다 — 실번호였다면 위 이유로
    // 거부된다(심사자가 심사 번호 뒤 자기 번호를 넣어 보는 경우 등).
    // ⚠️ **iOS에선 끄기가 먹지 않는다**: FlutterFire iOS 플러그인이 true일 때만 적용한다
    // (FLTFirebaseAuthPlugin setSettings `if (settings.appVerificationDisabledForTesting)` — 6.5.7·6.7.0·7.0.0
    // 동일, 실기기 실측 P77). Android는 값을 그대로 적용해 여기서 꺼진다. iOS는 앱을 다시 켜야 풀린다 —
    // 심사자 경로 한정(LOW)이라 네이티브 채널로 우회하지 않았다(다시 열 조건: 심사 리젝 사유로 나오면).
    await _auth.setSettings(appVerificationDisabledForTesting: skipAppVerificationFor(normalized));

    final completer = Completer<Result<PhoneVerificationSession>>();
    void completeOnce(Result<PhoneVerificationSession> result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: normalized,
        forceResendingToken: resendToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          // Android 즉시 인증/SMS 자동 회수 — 코드 입력 없이 로그인 완료.
          try {
            await _auth.signInWithCredential(credential);
          } on FirebaseAuthException {
            // 자동 인증 실패 시 수동 코드 입력 경로가 그대로 살아 있다.
          }
          // codeSent 없이 이 콜백만 오는 경우(즉시 인증)에도 흐름이 멈추지 않게
          // 빈 세션으로 성공 처리 — verifyCode가 currentUser로 스킵한다.
          completeOnce(const Ok(PhoneVerificationSession(verificationId: '')));
        },
        verificationFailed: (e) => completeOnce(Err(_mapPhoneAuthError(e))),
        codeSent: (verificationId, forceResendingToken) {
          completeOnce(Ok(PhoneVerificationSession(
            verificationId: verificationId,
            resendToken: forceResendingToken,
          )));
        },
        codeAutoRetrievalTimeout: (_) {
          // 자동 회수 타임아웃 — codeSent 이후에만 오므로 별도 처리 없음.
        },
      );
    } on FirebaseAuthException catch (e) {
      return Err(_mapPhoneAuthError(e));
    } catch (_) {
      return const Err(UnknownFailure());
    }

    return completer.future.timeout(
      _codeSentTimeout,
      onTimeout: () => const Err(NetworkFailure('인증 요청이 지연되고 있어요. 다시 시도해주세요')),
    );
  }

  @override
  Future<Result<void>> verifyCode({
    required String phone,
    required String verificationId,
    required String code,
  }) async {
    // 즉시 인증(Android verificationCompleted)이 이미 이 번호로 로그인을 끝냈으면
    // 사용자에게는 입력할 코드 자체가 없다 — 길이 검증보다 **먼저** 통과시켜야
    // 한다(순서가 반대면 무엇을 넣어도 "6자리…" 에러에 갇힌다).
    final current = _auth.currentUser;
    if (current != null && current.phoneNumber == normalizeKoreanPhone(phone)) {
      return const Ok(null);
    }

    if (code.length != 6) {
      return const Err(ValidationFailure('6자리 인증번호를 입력해주세요'));
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      await _auth.signInWithCredential(credential);
      return const Ok(null);
    } on FirebaseAuthException catch (e) {
      return Err(_mapPhoneAuthError(e));
    } catch (_) {
      return const Err(UnknownFailure());
    }
  }

  @override
  Stream<String?> signedInPhoneChanges() {
    final Stream<User?> source;
    try {
      source = _auth.authStateChanges();
    } catch (_) {
      // Firebase 미초기화(위젯 테스트 등) — 자동 진행 없이 수동 "확인" 경로만 남는다.
      return const Stream<String?>.empty();
    }
    // firebase_auth 계약: authStateChanges()는 **구독 즉시 현재 사용자를 한 번**
    // 흘린 뒤 이후 변화를 흘린다. 그 첫 이벤트는 "방금 완료된 인증"이 아니므로
    // 버린다(도메인 주석 참조) — 남은 건 구독 중에 일어난 전이뿐이다.
    return source.skip(1).map((user) => user?.phoneNumber);
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // 로그아웃 실패가 "번호 다시 인증하기"를 막으면 안 된다 —
      // 미초기화(테스트)·네트워크 무관하게 화면은 항상 전화번호 입력으로 돌아간다.
    }
  }

  /// FirebaseAuthException → 한국어 도메인 Failure.
  Failure _mapPhoneAuthError(FirebaseAuthException e) => mapPhoneAuthError(e);

  // ── 여기서부터는 실제 API계약 엔드포인트 ──────────────────────────────────
  @override
  Future<Result<JoinMatch>> matchJoin(String phone) async {
    final result = await guardApi(() => _remote.matchJoin(phone));
    return result.map(_toDomain);
  }

  JoinMatch _toDomain(JoinMatchPayload payload) {
    final dto = payload.dto;
    final m = dto.member;
    if (m == null) return JoinMatch(needsConfirm: dto.needsConfirm);
    return JoinMatch(
      needsConfirm: dto.needsConfirm,
      centerName: payload.centerName,
      member: MatchedMember(
        id: m.id,
        name: m.name,
        trainerId: m.trainerId,
        status: m.status,
      ),
    );
  }

  @override
  Future<Result<void>> confirmJoin({required String memberId, required bool confirm, required String phone}) {
    return guardApi(() => _remote.confirmJoin(memberId: memberId, confirm: confirm, phone: phone));
  }

  @override
  Future<Result<void>> requestJoin({
    required String name,
    required String phone,
    String centerId = '',
  }) {
    if (name.trim().isEmpty) {
      return Future.value(const Err(ValidationFailure('이름을 입력해주세요')));
    }
    return guardApi(
      () => _remote.requestJoin(name: name.trim(), phone: phone, centerId: centerId),
    );
  }

  @override
  Future<Result<List<CenterDirectory>>> fetchJoinCenters() {
    return guardApi(() async {
      final dtos = await _remote.fetchJoinCenters();
      return dtos
          .map((d) => CenterDirectory(
                id: d.id,
                name: d.name.trim(),
                address: d.address.trim(),
                phone: d.phone.trim(),
              ))
          .toList(growable: false);
    });
  }

  @override
  Future<Result<AppSession>> loadSession() async {
    final result = await guardApi(_meApi.fetchMe);
    return result.fold(
      (me) {
        final memberId = me.memberId;
        if (memberId == null) {
          // "아직 연결 전"은 네트워크 실패와 전혀 다른 결론(온보딩 vs 재시도)으로
          // 이어진다 — 호출부가 문구가 아니라 타입으로 가를 수 있게 전용 Failure.
          //
          // 계약 v2.27: 같은 응답에 가입 요청 상태가 함께 온다. 결론과 이유를 갈라
          // 나르면 호출부가 이유를 로컬 기록에서 다시 추론하게 되고, 그 추론이
          // 기기 변경에서 틀린다 — 함께 싣는다.
          //
          // 계약 v2.34: 요청이 귀속된 센터(`join_request.center_id`)와 Principal 센터(`center_id`)
          // 도 함께 나른다 — 대기실이 "어느 센터의 연락처·코치를 보여줘도 되는지"를 이 둘로 판정한다.
          final jr = me.joinRequest;
          return Err(MemberNotLinkedFailure(
            joinStatus: jr?.status,
            joinRequestedAt: jr == null ? null : DateTime.tryParse(jr.createdAt)?.toLocal(),
            centerId: me.centerId,
            joinCenterId: jr?.centerId ?? '',
          ));
        }
        return Ok(AppSession(
          uid: me.uid,
          role: me.role,
          centerId: me.centerId,
          memberId: memberId,
          // 계약 v2.2 — /v1/me가 표시용 이름을 준다. best-effort라 없을 수 있으므로
          // 정규화해서 담고(공백뿐인 이름도 ''), 비면 호출부 폴백에 맡긴다.
          // 이 값이 없던 시절엔 세션 복원 경로만 이름을 못 받아, 같은 홈 헤더가
          // 최초 로그인 땐 "김민지 님", 재실행 뒤엔 센터명으로 갈렸다.
          memberName: CoachLabel.nameOrNull(me.name) ?? '',
        ));
      },
      Err.new,
    );
  }
}

/// 전화 인증의 앱 검증(Play Integrity·reCAPTCHA·APNs)을 건너뛸지 — 디버그 빌드이거나 심사 번호일 때만.
/// 요청마다 이 값을 **그대로** setSettings에 넣는다(켜기만 하면 스위치가 남는다 — P77). [debug]는 시험용 주입.
@visibleForTesting
bool skipAppVerificationFor(String normalizedPhone, {bool debug = kDebugMode}) =>
    debug || normalizedPhone == AuthConfig.reviewPhoneE164;

/// FirebaseAuthException → 한국어 도메인 Failure. 화면은 `message`를 그대로 보여 준다.
@visibleForTesting
Failure mapPhoneAuthError(FirebaseAuthException e) {
  return switch (e.code) {
    'invalid-phone-number' => const ValidationFailure('휴대폰 번호를 다시 확인해주세요'),
    'invalid-verification-code' => const AuthFailure('인증번호가 맞지 않아요'),
    'invalid-verification-id' ||
    'session-expired' ||
    'code-expired' =>
      const AuthFailure('인증 시간이 지났어요. 인증번호를 다시 요청해주세요'),
    'too-many-requests' => const RejectedFailure('시도가 너무 많았어요. 잠시 후 다시 시도해주세요'),
    'quota-exceeded' => const RejectedFailure('인증 문자 발송 한도를 넘었어요. 잠시 후 다시 시도해주세요'),
    'user-disabled' => const AuthFailure('사용이 중지된 계정이에요. 센터에 문의해주세요'),
    'operation-not-allowed' => const AuthFailure('전화번호 로그인이 아직 열려 있지 않아요'),
    'network-request-failed' || 'web-network-request-failed' => const NetworkFailure(),
    // reCAPTCHA 폴백 갈래 — iOS는 사파리 시트, Android는 Play Integrity가 실패하면 Custom Tab(P75). APNs
    // 사일런트 검증이 없는 동안 iOS 실번호 인증은 전부 이 길을 지난다. 매핑이 없으면 아래 기본 갈래가 영문 코드를
    // 그대로 보인다. 철자가 플랫폼마다 다르다(iOS cancelled · Android canceled). 이 문구는 번호 화면("인증번호
    // 받기")과 코드 화면("인증번호 재전송") 둘 다에서 뜨므로 버튼 이름을 말하지 않는다.
    'web-context-cancelled' || 'web-context-canceled' =>
      const AuthFailure('보안 확인이 끝나기 전에 창이 닫혔어요. 다시 시도해주세요'),
    'internal-error' => const AuthFailure('일시적인 문제로 인증하지 못했어요. 잠시 후 다시 시도해주세요'),
    'app-not-authorized' ||
    'missing-client-identifier' ||
    'captcha-check-failed' ||
    'invalid-app-credential' ||
    'missing-app-credential' ||
    'app-not-verified' ||
    'missing-app-token' ||
    'notification-not-forwarded' ||
    'app-verification-failed' ||
    'invalid-client-id' =>
      const AuthFailure('앱 인증에 실패했어요. 잠시 후 다시 시도해주세요'),
    // 웹 확인(reCAPTCHA 시트·Custom Tab)과 reCAPTCHA 계열은 **이름을 하나씩 세지 않고 계열로** 받는다 —
    // 콜백 URL이 firebaseError를 싣고 오면 iOS는 대부분 web-user-interaction-failure로 뭉치고, SDK가
    // 판마다 새 이름을 더한다(목록으로 쫓으면 반드시 빠진다 — P75 반박 검토에서 실제로 둘이 빠졌다).
    final code when code.startsWith('web-') || code.contains('recaptcha') =>
      const AuthFailure('앱 인증에 실패했어요. 잠시 후 다시 시도해주세요'),
    _ => AuthFailure('인증에 실패했어요 (${e.code})'),
  };
}
