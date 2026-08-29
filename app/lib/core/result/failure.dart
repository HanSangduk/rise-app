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
  const MemberNotLinkedFailure([super.message = '회원 정보가 아직 연결되지 않았어요']);
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
