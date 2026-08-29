/// 순수 도메인 — 로그인 플로우(전화번호 → 인증 → 센터 자동매칭 → 이름확인 1탭, P48).
/// Flutter/외부 의존 0, codegen 0.
class MatchedMember {
  const MatchedMember({
    required this.id,
    required this.name,
    this.trainerId,
    this.trainerName,
    this.passProduct,
    required this.status,
  });

  final String id;
  final String name;
  final String? trainerId;

  /// GET /v1/staff 조회로 채워지는 표시용 필드(Member DTO엔 이름이 없음).
  final String? trainerName;

  /// 매칭 카드에 "PT 20회권"처럼 보여줄 대표 상품명(있으면).
  final String? passProduct;
  final String status; // active|dormant
}

/// 인증번호 발송(codeSent) 결과 — Firebase 타입을 도메인에 노출하지 않는 순수 값.
/// [verificationId]는 코드 확인 시 필수, [resendToken]은 재전송 시
/// forceResendingToken으로 전달(Android 전용 — iOS는 항상 null).
class PhoneVerificationSession {
  const PhoneVerificationSession({required this.verificationId, this.resendToken});

  final String verificationId;
  final int? resendToken;
}

/// POST /v1/join/match 응답.
class JoinMatch {
  const JoinMatch({this.member, required this.needsConfirm});

  final MatchedMember? member;
  final bool needsConfirm;

  bool get found => member != null;
}
