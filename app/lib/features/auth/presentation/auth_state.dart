import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';

/// center_confirm 화면이 실제로 그려야 하는 상태 — CTA 분기의 단일 기준.
///
/// "member가 null이 아닌가"로 분기하면 거부·요청 후에 CTA 블록이 통째로 사라져
/// 탈출구 없는 화면이 된다. 화면은 항상 이 4가지 중 하나로 확정된다.
enum CenterConfirmStage {
  /// 번호로 회원을 찾음 — "네, OO 본인이에요"가 주 CTA.
  matched,

  /// 가입 요청을 보낸 뒤 — "승인 대기 중"이 주 상태.
  pendingApproval,

  /// "본인이 아니에요"로 매칭을 거부한 뒤.
  declined,

  /// 앱 시작 복원이 연결 여부를 **확인하지 못함**(네트워크 등).
  /// [notFound]와 반드시 구분한다 — "찾지 못했어요"는 서버가 확답한 결론이지만
  /// 이쪽은 물어보지도 못한 상태라, 같은 화면을 보여주면 이미 연결된 회원에게
  /// 가입 요청을 권하게 된다(대표 화면에 같은 사람이 한 줄 더 쌓인다).
  connectionUnknown,

  /// 이 번호로 등록된 회원을 찾지 못함.
  notFound,
}

/// 로그인 플로우 UI State — freezed 미사용(회원 앱 컨벤션: freezed는 DTO 전용).
/// 3개 화면(전화번호/인증번호/센터확인)이 공유.
class AuthState {
  const AuthState({
    this.phone = '',
    this.code = '',
    this.submitting = false,
    this.resending = false,
    this.checkingConnection = false,
    this.connectionUnknown = false,
    this.error,
    this.match,
    this.trainerName,
    this.matchDeclined = false,
    this.joinRequestedAt,
    this.verificationId,
    this.resendToken,
  });

  final String phone;
  final String code;

  /// 주 액션(발송/확인/본인확인/가입요청) 진행 중.
  final bool submitting;

  /// 인증번호 **재전송** 진행 중 — [submitting]과 분리해야 재전송 중에
  /// 확인 버튼이 "확인 중…"이라고 거짓말하지 않는다.
  final bool resending;

  /// "연결됐는지 확인"(GET /v1/me 재조회) 진행 중 — 같은 이유로 [submitting]과 분리.
  /// 연타 방지는 [busy]가 겸한다.
  final bool checkingConnection;

  /// 앱 시작 복원이 연결 여부를 확인하지 못한 채 이 화면에 세웠다(네트워크 등).
  /// "미연결"로 단정하지 않기 위한 플래그 — 재확인이 정상 경로다.
  /// 서버가 확답을 주는 순간(연결됨/아직) 곧바로 내려간다.
  final bool connectionUnknown;

  final Failure? error;
  final JoinMatch? match;

  /// Firebase codeSent가 준 검증 세션 — 코드 확인 시 필수.
  final String? verificationId;

  /// 재전송 시 forceResendingToken으로 전달(Android 전용, iOS는 null).
  final int? resendToken;

  /// GET /v1/staff로 보강한 표시용 트레이너 이름(best-effort).
  final String? trainerName;

  /// "본인이 아니에요"로 매칭을 거부한 상태 — 매칭 카드 대신 안내 카드를 보여준다.
  final bool matchDeclined;

  /// 가입 요청(POST /v1/join/request) 성공 시각 — center_confirm 화면을
  /// "승인 대기 중" 카드로 고정하고 30초 뒤에야 "다시 요청"을 허용한다(중복 제출 방지).
  /// 로컬에도 영속되어(JoinRequestStore) 앱 재실행 시 이 상태로 복귀한다.
  final DateTime? joinRequestedAt;

  /// 발송/확인/재전송/연결확인 중 어느 하나라도 진행 중 — 동시 요청 차단용.
  bool get busy => submitting || resending || checkingConnection;

  /// center_confirm 화면 분기. 매칭이 살아 있으면 그게 가장 빠른 경로이므로
  /// 승인 대기보다 우선한다(대기 카드는 아래 슬롯에 그대로 함께 노출).
  ///
  /// [CenterConfirmStage.connectionUnknown]은 "아는 게 없을 때"의 폴백이라
  /// 실제 근거가 있는 세 분기보다 뒤에 온다 — 대기 기록이 있으면 대기 카드가
  /// 이기고(그 카드에 재확인 버튼이 있다), 아무 근거도 없을 때만 재확인 화면이 뜬다.
  CenterConfirmStage get centerConfirmStage {
    if (match?.member != null) return CenterConfirmStage.matched;
    if (joinRequestedAt != null) return CenterConfirmStage.pendingApproval;
    if (matchDeclined) return CenterConfirmStage.declined;
    if (connectionUnknown) return CenterConfirmStage.connectionUnknown;
    return CenterConfirmStage.notFound;
  }

  AuthState copyWith({
    String? phone,
    String? code,
    bool? submitting,
    bool? resending,
    bool? checkingConnection,
    bool? connectionUnknown,
    Failure? error,
    bool clearError = false,
    JoinMatch? match,
    bool clearMatch = false,
    String? trainerName,
    bool? matchDeclined,
    DateTime? joinRequestedAt,
    String? verificationId,
    int? resendToken,
    bool clearVerification = false,
  }) {
    return AuthState(
      phone: phone ?? this.phone,
      code: code ?? this.code,
      submitting: submitting ?? this.submitting,
      resending: resending ?? this.resending,
      checkingConnection: checkingConnection ?? this.checkingConnection,
      connectionUnknown: connectionUnknown ?? this.connectionUnknown,
      error: clearError ? null : (error ?? this.error),
      // `match ?? this.match`만으로는 null 클리어가 불가능(본인 아님 거부가 무반응이 되는 버그)
      // → clearError와 동일한 명시적 플래그 패턴.
      match: clearMatch ? null : (match ?? this.match),
      trainerName: trainerName ?? this.trainerName,
      matchDeclined: matchDeclined ?? this.matchDeclined,
      joinRequestedAt: joinRequestedAt ?? this.joinRequestedAt,
      // verificationId와 resendToken은 codeSent 한 번의 산물이라 항상 한 쌍으로 무효화한다
      // (번호가 바뀌면 둘 다 옛 번호의 것 — 하나만 지우면 반쪽짜리 세션이 남는다).
      verificationId: clearVerification ? null : (verificationId ?? this.verificationId),
      resendToken: clearVerification ? null : (resendToken ?? this.resendToken),
    );
  }
}
