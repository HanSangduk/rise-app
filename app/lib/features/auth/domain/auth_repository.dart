import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';

/// 도메인 인터페이스 — 구현은 data/auth_repository_impl.dart.
abstract interface class AuthRepository {
  /// 전화번호로 인증번호 발송 (Firebase Phone Auth).
  /// [resendToken]은 재전송 시 직전 발송의 [PhoneVerificationSession.resendToken].
  Future<Result<PhoneVerificationSession>> requestVerificationCode(
    String phone, {
    int? resendToken,
  });

  /// 인증번호 확인 — [verificationId]는 [requestVerificationCode] 성공 결과에서.
  Future<Result<void>> verifyCode({
    required String phone,
    required String verificationId,
    required String code,
  });

  /// 인증된 번호 기준 센터 자동 매칭 조회 (POST /v1/join/match {phone}).
  Future<Result<JoinMatch>> matchJoin(String phone);

  /// 이름확인 1탭 (POST /v1/join/confirm) — confirm=false면 매칭 취소.
  Future<Result<void>> confirmJoin({required String memberId, required bool confirm, required String phone});

  /// 매칭 실패 시 가입 요청 경로 (POST /v1/join/request {center_id, name, phone}).
  /// center_id는 비워 보내면 서버가 기본 센터로 폴백한다.
  Future<Result<void>> requestJoin({required String name, required String phone});

  /// 로그인 완료 후 세션 부트스트랩 (GET /v1/me).
  Future<Result<AppSession>> loadSession();

  /// 인증 상태 초기화 — "다른 번호로 다시 시도" 탈출구가 쓴다.
  /// 실패해도 화면 전환을 막지 않도록 Result가 아닌 void.
  Future<void> signOut();

  /// 구독 **이후** 새로 일어난 로그인/로그아웃만 흘리는 스트림(로그인 = E.164 번호,
  /// 로그아웃 = null).
  ///
  /// 존재 이유는 안드로이드 SMS 자동 회수 하나다: 자동 회수가 `codeSent` **이전**에
  /// 끝나는 즉시 인증은 [requestVerificationCode]가 빈 verificationId로 알려주지만,
  /// 정상 SMS 흐름에서 **나중에** 도착하면 알릴 통로가 없어 사용자는 이미 로그인이
  /// 끝났는데도 코드 화면이 오지 않을 입력을 기다리며 카운트다운을 돌았다.
  ///
  /// **구독 시점의 현재 상태는 흘리지 않는다.** 그건 "방금 완료된 인증"이 아니라
  /// 이전부터 남아 있던 세션이라, 화면을 즉시 밀어내면 사용자가 열어 둔 화면을
  /// 빼앗는 셈이 된다(그 경우 "확인" 버튼이 currentUser 지름길로 처리한다).
  Stream<String?> signedInPhoneChanges();
}
