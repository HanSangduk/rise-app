/// 로그인 후 앱 전역에서 쓰는 최소 세션 정보.
/// GET /v1/me → {uid, role, center_id, member_id?, name?} 를 그대로 담는다.
class AppSession {
  const AppSession({
    required this.uid,
    required this.role,
    required this.centerId,
    required this.memberId,
    this.memberName = '',
  });

  final String uid;
  final String role;
  final String centerId;

  /// 회원 앱에서는 로그인 완료(join/confirm) 이후 항상 존재.
  final String memberId;

  /// 헤더 표시용(예: "김민지 님") — 1차 출처는 GET /v1/me의 `name`(계약 v2.2),
  /// 서버가 주지 못하면 join/match 응답의 이름으로 메운다.
  ///
  /// 서버 쪽 `name`은 **best-effort**라 없을 수 있고(미연결 계정·조회 실패·구버전
  /// 서버), 두 출처가 다 비면 ''로 남는다. 그래서 이 값을 그대로 문구에 끼우면
  /// 안 된다 — 헤더는 `CoachLabel.nameOrNull`로 판정해 센터명으로 떨어진다
  /// (빈 문자열을 보간하면 "  님"이 렌더된다).
  ///
  /// 담기는 시점에 이미 정규화돼 있다(공백뿐이면 '').
  final String memberName;

  /// 표시 이름만 갈아 끼울 때 쓴다(로그인 경로가 /v1/me의 빈 이름을 매칭 응답으로
  /// 메우는 자리). 손으로 다시 조립하면 나중에 필드가 늘 때 조용히 누락된다.
  AppSession withMemberName(String name) => AppSession(
        uid: uid,
        role: role,
        centerId: centerId,
        memberId: memberId,
        memberName: name,
      );
}
