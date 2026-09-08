import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/features/auth/presentation/session_restore.dart';

// P2R — 세션 복원이 loadSession() 실패를 전부 같게 취급하던 문제.
// 이미 연결된 회원이 지하철에서 앱을 켜면 "미연결"로 오독돼 승인 대기 화면
// (또는 온보딩)에 떨어졌고, 그 화면에서 할 수 있는 건 가입 **재요청**뿐이라
// 대표 화면에 같은 사람이 한 줄 더 쌓이는 것으로 끝났다.
void main() {
  const session =
      AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1');

  group('classifyRestore — 실패의 종류를 가른다', () {
    test('성공은 connected', () {
      expect(classifyRestore(const Ok(session)), RestoreOutcome.connected);
    });

    test('서버가 "아직 연결 전"이라고 확답하면 notLinked', () {
      expect(
        classifyRestore(const Err(MemberNotLinkedFailure())),
        RestoreOutcome.notLinked,
      );
    });

    test('네트워크 오류는 미연결이 아니라 unknown', () {
      expect(classifyRestore(const Err(NetworkFailure())), RestoreOutcome.unknown);
    });

    test('그 밖의 실패도 unknown — 미연결로 단정하는 건 확답뿐', () {
      expect(
        classifyRestore(const Err(RejectedFailure('요청을 처리할 수 없어요'))),
        RestoreOutcome.unknown,
      );
      expect(classifyRestore(const Err(UnknownFailure())), RestoreOutcome.unknown);
      // 일반 AuthFailure(예: 토큰 만료)는 "회원 미연결"과 다른 사건이다.
      expect(classifyRestore(const Err(AuthFailure())), RestoreOutcome.unknown);
    });

    test('MemberNotLinkedFailure는 AuthFailure로도 성립한다 (기존 분기 보존)', () {
      expect(const MemberNotLinkedFailure(), isA<AuthFailure>());
    });
  });

  group('restoreLandingRoute — 판정별 착지', () {
    test('connected면 홈', () {
      expect(restoreLandingRoute(outcome: RestoreOutcome.connected), '/home');
    });

    // P64 검증 반영 — 종전엔 로컬 대기 기록이 없으면 null(전화번호 화면)이라, 같은 회원·
    // 같은 서버 상태가 캐시 유무로 갈렸다(캐시 있음 → 재검증 → 대기실 / 캐시 없음 → SMS
    // 재인증). 뮤테이션: notLinked를 null로 되돌리면 아래 두 테스트가 죽는다.
    test('notLinked → 대기실 — 로컬 대기 기록이 없어도 전화번호 화면으로 밀지 않는다', () {
      expect(
        restoreLandingRoute(outcome: RestoreOutcome.notLinked),
        '/login/center-confirm',
        reason: 'Firebase 신원은 살아 있다 — SMS 재인증을 시킬 이유가 없고, 대기실이 서버 상태를 보여 준다',
      );
    });

    test('notLinked 착지는 재검증 경로(sessionEndRoute)와 한 규칙이다', () {
      expect(
        restoreLandingRoute(outcome: RestoreOutcome.notLinked),
        sessionEndRoute(SessionEndReason.notLinked),
        reason: '캐시 유무로 착지가 갈리면 같은 사람이 켤 때마다 다른 화면을 본다',
      );
    });

    test('unknown이면 대기 기록이 없어도 온보딩으로 밀지 않는다', () {
      // 인증을 처음부터 다시 시키는 대신 재확인할 수 있는 화면에 세운다.
      expect(restoreLandingRoute(outcome: RestoreOutcome.unknown), '/login/center-confirm');
    });

    test('notLinked·unknown 어느 쪽도 null(전화번호 화면)을 돌려주지 않는다', () {
      for (final o in [RestoreOutcome.notLinked, RestoreOutcome.unknown]) {
        expect(restoreLandingRoute(outcome: o), isNotNull, reason: '$o — 신원이 살아 있는 착지다');
      }
    });
  });
}
