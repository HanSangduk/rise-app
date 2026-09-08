/// 도메인 실패 타입 (Dart 3 sealed — exhaustive 패턴매칭, 의존성 0).
///
/// 외부(네트워크/서버) 예외를 data 레이어에서 [Failure]로 변환해
/// 도메인·presentation은 예외가 아니라 값으로 다룬다. (wodshot 아키텍처 참조)
sealed class Failure {
  const Failure(this.message);
  final String message;
}

/// 네트워크/서버 (백엔드 Cloud Run 등).
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = '연결이 불안정해요']);
}

/// 인증/세션 (로그인 만료, 인증번호 불일치 등).
final class AuthFailure extends Failure {
  const AuthFailure([super.message = '인증에 실패했어요']);
}

/// 전화번호 인증은 끝났지만 아직 센터 회원과 연결되지 않음(GET /v1/me의 member_id 없음).
/// 실패가 아니라 **"연결 전"이라는 확정된 상태**다.
///
/// [EmptyPassesFailure]와 같은 이유로 타입을 준다 — 세션 복원이 이걸 네트워크
/// 오류와 구분하지 못하면, 이미 연결된 회원이 지하철에서 앱을 켰을 때
/// "미연결"로 오독해 온보딩·승인 대기 화면으로 떨어뜨린다. 메시지 문자열 매칭은
/// 문구 한 번 다듬으면 조용히 깨지므로 쓰지 않는다.
///
/// [AuthFailure]의 하위 타입이라 기존 `is AuthFailure` 분기는 그대로 성립한다.
final class MemberNotLinkedFailure extends AuthFailure {
  const MemberNotLinkedFailure({
    String message = '회원 정보가 아직 연결되지 않았어요',
    this.joinStatus,
    this.joinRequestedAt,
    this.centerId = '',
    this.joinCenterId = '',
  }) : super(message);

  /// 서버가 들고 있는 가입 요청 상태(계약 v2.27): `pending` | `rejected` | `approved`.
  /// 요청한 적이 없으면 null — 서버가 키 자체를 빼기 때문이다.
  ///
  /// **왜 실패 객체가 이걸 나르나**: 미연결이라는 결론과 "왜 미연결인가"는 같은 응답에서
  /// 함께 오는데, 종전엔 결론만 타입으로 전달하고 이유는 **기기 로컬 기록**에서 다시
  /// 추론했다. 그래서 기기를 바꾸면 "요청한 적 없음"으로 오분류돼 중복 요청이 나갔다(P55).
  final String? joinStatus;

  /// 요청 시각(서버 기준). 쿨다운·경과 문구의 기준점이 로컬 시각이 아니라 이 값이 된다.
  final DateTime? joinRequestedAt;

  /// Principal의 센터(`GET /v1/me.center_id`). 미연결 uid는 **기본 센터 폴백**이라 "이
  /// 사람의 센터"가 아니라 "`/v1/staff`가 돌려주는 목록의 센터"다 — 대기실이 코치 줄을 그려도
  /// 되는지([joinCenterId]와 같은지)를 판정하는 데만 쓴다. 구서버·미지 응답이면 ''.
  final String centerId;

  /// 가입 요청이 귀속된 센터(계약 v2.34 `join_request.center_id`). 요청이 없거나 구서버면 ''.
  /// v2.33이 요청 시 센터 선택을 열었으므로 "어느 센터에 보냈는지"를 앱이 알아야 그 센터의
  /// 연락처·수업 시간을 보여줄 수 있다 — 기본 센터 것을 2호점 신청자에게 보여주면 남의 센터다.
  final String joinCenterId;
}

/// 가입 요청이 **이미 서버에 pending으로 있다**(POST /v1/join/request 409, 계약 v2.34
/// `code: join_pending`). 실패가 아니라 "서버가 pending을 확답한" 사건이다.
///
/// 종전엔 이 409가 [RejectedFailure]로 뭉개져 시트가 빨간 문구만 띄웠고, 서버가 `/v1/me`에
/// 요청을 안 실어 준 상태(조회 실패·타 센터 큐)에서는 재요청 → 409 → 재요청의 막다른 길이었다.
/// 타입을 주면 뷰모델이 이 응답을 **pending 승격**(serverJoinStatus·joinCenterId)으로 흡수한다.
///
/// [AuthFailure]의 하위 타입이라 기존 `is AuthFailure` 분기는 그대로 성립한다.
final class JoinPendingFailure extends AuthFailure {
  const JoinPendingFailure({
    String message = '이미 보낸 가입 요청이 있어요 — 센터에서 확인하면 연결돼요',
    this.centerId = '',
  }) : super(message);

  /// pending 요청이 귀속된 센터(409 바디 `center_id`). 구서버·미지 응답이면 ''.
  final String centerId;
}

/// 셸(홈/예약/기록/마이/촬영)이 그려진 채 세션이 비었다 — **화면은 이걸 에러로 그리지
/// 않는다**(P64).
///
/// 세션은 셸 진입 전에 항상 채워지지만(`app_router` 규약) 셸이 떠 있는 동안 비워질 수
/// 있다: 401·로그아웃·탈퇴·캐시 재검증의 미연결 확답. 그 순간 `app.dart`의 세션
/// 리스너가 이유대로 착지 화면으로 보내는 중이고, 뷰모델은 그 이유를 모른다. 종전엔
/// 여기서 `AuthFailure('로그인이 필요해요')`를 던져 [다시 시도] 버튼과 함께 그렸는데,
/// 연결 해제면 그 문장은 거짓이고(신원은 살아 있다) 그 버튼은 세션을 만들지 못한다.
/// 그래서 문구가 아니라 **타입**만 낸다 — 화면은 이 타입을 전환 뷰로 그리고 재시도
/// 버튼을 두지 않는다(`SessionGoneView`).
///
/// [AuthFailure]의 하위 타입이라 기존 `is AuthFailure` 분기와 재시도 정책(Failure는
/// 재시도 없음)은 그대로 성립한다.
///
/// 메시지는 **중립 문구**다. 뮤테이션 표면(4탭 액션의 스낵바 — `showFailureSnackBar`,
/// 촬영 화면의 error 리스너)은 이 타입을 건너뛰거나 탈출 안내로 바꾸므로 보통 보이지 않는다.
/// 건너뛰지 못한 곳(인라인 에러 줄 등)에는 이 중립 문구가 그대로 보인다 — 그래서 '실패'도
/// '로그인 필요'도 말하지 않는다. 원인을 아는 쪽은 세션을 비운 쪽뿐이다.
final class SessionGoneFailure extends AuthFailure {
  const SessionGoneFailure() : super('로그인 정보가 바뀌어 화면을 다시 준비하고 있어요');
}

/// 입력 검증 (예: 잘못된 전화번호 형식).
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

/// 서버가 명시적으로 거부한 경우 (예: 슬롯 만석, 컷오프 경과, 동의 미체결).
final class RejectedFailure extends Failure {
  const RejectedFailure(super.message);
}

/// 같은 리소스가 이미 있어 거부(HTTP 409 — 예: 같은 날 인바디 중복).
///
/// [RejectedFailure]와 갈라 두는 이유: 409는 실패 중 유일하게 **"앱이 들고 있는
/// 목록이 서버와 다르다"는 신호**라서, 받은 쪽이 재조회로 응답해야 한다(충돌을
/// 일으킨 기존 기록이 화면에 보여야 회원이 "지우고 다시" 안내를 따라갈 수 있다).
/// 메시지 문자열 매칭으로 구분하면 서버 문구를 다듬는 순간 조용히 깨진다 —
/// [MemberNotLinkedFailure]와 같은 판단으로 타입을 준다.
///
/// [RejectedFailure]의 하위 타입이라 기존 `is RejectedFailure` 분기는 그대로 성립한다.
final class ConflictFailure extends RejectedFailure {
  const ConflictFailure(super.message);
}

/// 발급된 회원권이 0개 — 오류가 아니라 온보딩 성격의 "빈 상태"로 렌더한다.
/// 홈 탭이 메시지 문자열 매칭이 아니라 이 타입으로 전용 빈 상태 뷰를 구분한다.
final class EmptyPassesFailure extends Failure {
  const EmptyPassesFailure([super.message = '아직 회원권이 없어요']);
}

/// 캐시/로컬 저장.
final class CacheFailure extends Failure {
  const CacheFailure([super.message = '저장소 오류']);
}

/// 알 수 없는 예외.
final class UnknownFailure extends Failure {
  const UnknownFailure([super.message = '알 수 없는 오류가 발생했어요']);
}
