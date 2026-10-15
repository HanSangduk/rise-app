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
  const JoinMatch({this.member, required this.needsConfirm, this.centerName = ''});

  final MatchedMember? member;
  final bool needsConfirm;

  /// 매칭된 **그 회원의 센터** 상호(계약 v2.32 `center.name`). 미매칭·상호 미등록·구서버면 ''.
  ///
  /// 대기실의 매칭 카드는 종전에 `GET /v1/public/center`(무인증이라 **기본 센터 고정**)의
  /// 상호를 찍었다 — 2호점 회원에게 1호점 이름을 보여줬다(P65 후속 3, P73에서 반영). 매칭
  /// 응답이 "당신의 센터"를 아는 유일한 지점이라 서버가 여기 실어 준다.
  final String centerName;

  bool get found => member != null;
  bool get hasCenterName => centerName.trim().isNotEmpty;
}

/// GET /v1/join/centers 응답 한 건 — 가입 요청을 보낼 수 있는 센터(계약 v2.33).
///
/// 회원이 **고르는 데 필요한 것만** 담는다. 정책·사업자 정보·회원 수는 서버가 주지 않는다 —
/// 이 목록을 읽는 사람은 아직 어느 센터의 회원도 아니고, B2B2C에서 타 센터의 운영 수치는
/// 남에게 보일 값이 아니다.
class CenterDirectory {
  const CenterDirectory({
    required this.id,
    required this.name,
    this.address = '',
    this.phone = '',
  });

  final String id;

  /// 센터 상호. **빈 값일 수 있다** — 상호를 아직 등록하지 않은 센터가 목록에서 빠지면
  /// 그 센터를 고를 방법 자체가 사라지기 때문에 서버가 빈 이름으로라도 실어 보낸다.
  /// 화면은 [displayName]으로 폴백 라벨을 쓴다.
  final String name;
  final String address;
  final String phone;

  /// 상호가 비었는가 — 화면이 폴백 라벨을 쓸지 판단한다. 폴백 문자열 자체는 이 파일에 두지
  /// 않는다(이 레이어는 Flutter·앱 설정 의존 0을 유지한다).
  bool get hasName => name.isNotEmpty;
}
