import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
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
      expect(
        restoreLandingRoute(outcome: RestoreOutcome.connected, hasPending: false),
        '/home',
      );
    });

    test('notLinked + 대기 기록 → 승인 대기 화면으로 복귀', () {
      expect(
        restoreLandingRoute(outcome: RestoreOutcome.notLinked, hasPending: true),
        '/login/center-confirm',
      );
    });

    test('notLinked + 기록 없음 → 온보딩(null)', () {
      expect(
        restoreLandingRoute(outcome: RestoreOutcome.notLinked, hasPending: false),
        isNull,
      );
    });

    test('unknown이면 대기 기록이 없어도 온보딩으로 밀지 않는다', () {
      // 인증을 처음부터 다시 시키는 대신 재확인할 수 있는 화면에 세운다.
      expect(
        restoreLandingRoute(outcome: RestoreOutcome.unknown, hasPending: false),
        '/login/center-confirm',
      );
    });

    test('unknown + 대기 기록도 같은 화면 — 대기 카드로 그려진다', () {
      expect(
        restoreLandingRoute(outcome: RestoreOutcome.unknown, hasPending: true),
        '/login/center-confirm',
      );
    });
  });
}
