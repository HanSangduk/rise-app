import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';

// P2R — "본인이 아니에요" 무반응 버그의 원인이었던 copyWith null 클리어 회귀 방지.
void main() {
  const match = JoinMatch(
    member: MatchedMember(id: 'm1', name: '김라이즈', status: 'active'),
    needsConfirm: true,
  );

  group('AuthState.copyWith', () {
    test('clearMatch: true면 match가 null로 지워진다 (본인 아님 거부)', () {
      const state = AuthState(match: match);
      final next = state.copyWith(clearMatch: true, matchDeclined: true);
      expect(next.match, isNull);
      expect(next.matchDeclined, isTrue);
    });

    test('clearMatch 없이 match를 넘기지 않으면 기존 match 유지', () {
      const state = AuthState(match: match);
      final next = state.copyWith(submitting: true);
      expect(next.match, same(match));
      expect(next.matchDeclined, isFalse);
    });

    test('새 매칭 성공 시 matchDeclined는 false로 리셋 가능', () {
      const state = AuthState(matchDeclined: true);
      final next = state.copyWith(match: match, matchDeclined: false);
      expect(next.match, same(match));
      expect(next.matchDeclined, isFalse);
    });

    test('clearError는 기존 동작 유지 — error만 지운다', () {
      const state = AuthState(error: RejectedFailure('거부'), match: match);
      final next = state.copyWith(clearError: true);
      expect(next.error, isNull);
      expect(next.match, same(match));
    });

    test('submitting과 resending은 서로 독립 — 재전송이 확인 표시를 켜지 않는다', () {
      const state = AuthState();
      final resending = state.copyWith(resending: true);
      expect(resending.resending, isTrue);
      expect(resending.submitting, isFalse);
      expect(resending.busy, isTrue);

      final submitting = state.copyWith(submitting: true);
      expect(submitting.submitting, isTrue);
      expect(submitting.resending, isFalse);
      expect(submitting.busy, isTrue);

      expect(state.busy, isFalse);
    });

    test('checkingConnection도 독립 — 다만 busy에는 포함(동시 요청 차단)', () {
      final checking = const AuthState().copyWith(checkingConnection: true);
      expect(checking.checkingConnection, isTrue);
      expect(checking.submitting, isFalse);
      expect(checking.resending, isFalse);
      expect(checking.busy, isTrue);
    });

    test('clearVerification은 verificationId·resendToken을 한 쌍으로 비운다', () {
      const state = AuthState(verificationId: 'vid', resendToken: 7, phone: '010-1111-2222');
      final next = state.copyWith(phone: '010-3333-4444', clearVerification: true);
      expect(next.verificationId, isNull);
      expect(next.resendToken, isNull);
      expect(next.phone, '010-3333-4444');
    });

    // P63 검증 반영 — 서버가 "요청 없음"(null)이라 답해도 `?? this`가 옛 pending을 남겨
    // 삭제 고지가 지운 적 없는 요청을 단정하던 자리. clearMatch와 같은 명시적 플래그.
    test('serverJoinStatus는 null 인자로는 안 지워지고 clearServerJoinStatus로만 지워진다', () {
      const state = AuthState(serverJoinStatus: 'pending');
      expect(state.copyWith(serverJoinStatus: null).serverJoinStatus, 'pending');
      final cleared = state.copyWith(clearServerJoinStatus: true);
      expect(cleared.serverJoinStatus, isNull);
      expect(cleared.joinRequestTrace, JoinRequestTrace.unknown);
    });
  });

  // P2R — CTA가 사라져 탈출구가 없어지던 화면. 화면은 항상 4가지 중 하나로
  // 확정되어야 하고, 어떤 상태에서도 "빈 CTA"가 나오면 안 된다.
  group('AuthState.centerConfirmStage', () {
    test('매칭된 회원이 있으면 matched', () {
      expect(const AuthState(match: match).centerConfirmStage, CenterConfirmStage.matched);
    });

    test('"본인이 아니에요" 직후(match 비움 + matchDeclined)는 declined', () {
      const state = AuthState(matchDeclined: true);
      expect(state.centerConfirmStage, CenterConfirmStage.declined);
    });

    test('가입 요청을 보냈으면 pendingApproval — 거부 상태보다 우선', () {
      final state = AuthState(matchDeclined: true, joinRequestedAt: DateTime(2026, 8, 22));
      expect(state.centerConfirmStage, CenterConfirmStage.pendingApproval);
    });

    test('매칭이 살아 있으면 승인 대기보다 matched가 우선 (가장 빠른 연결 경로)', () {
      final state = AuthState(match: match, joinRequestedAt: DateTime(2026, 8, 22));
      expect(state.centerConfirmStage, CenterConfirmStage.matched);
    });

    test('아무것도 없으면 notFound — 기본값도 반드시 분기 하나로 확정된다', () {
      expect(const AuthState().centerConfirmStage, CenterConfirmStage.notFound);
    });

    // 복원이 GET /v1/me에 실패한 상태. "찾지 못했어요"(notFound)로 뭉뚱그리면
    // 이미 연결된 회원에게 가입 요청을 권하게 된다(대표 화면에 중복 줄).
    test('연결 여부를 확인하지 못했으면 notFound가 아니라 connectionUnknown', () {
      const state = AuthState(connectionUnknown: true);
      expect(state.centerConfirmStage, CenterConfirmStage.connectionUnknown);
    });

    test('대기 기록이 있으면 대기 카드가 이긴다 — 그 카드가 재확인 버튼을 갖는다', () {
      final state = AuthState(
        connectionUnknown: true,
        joinRequestedAt: DateTime(2026, 8, 22),
      );
      expect(state.centerConfirmStage, CenterConfirmStage.pendingApproval);
    });

    test('매칭이 살아 있으면 connectionUnknown보다 matched가 우선', () {
      const state = AuthState(match: match, connectionUnknown: true);
      expect(state.centerConfirmStage, CenterConfirmStage.matched);
    });

    test('member가 없는 JoinMatch는 matched가 아니다', () {
      const state = AuthState(match: JoinMatch(needsConfirm: false));
      expect(state.centerConfirmStage, CenterConfirmStage.notFound);
    });
  });

  // P63 — 계정 삭제 고지의 단일 판별자. `none`(요청 없음)이 없는 이유: 앱은 "요청이 없다"를
  // 알 수 없다 — 코드 인증 직후엔 /v1/me를 부른 적이 없고, 서버도 키 부재로 "없음"과
  // "조회 실패"를 구분해 주지 않는다. 모르면 unknown이고, 화면은 "있다면"으로 말한다.
  group('AuthState.joinRequestTrace', () {
    test('아무 근거도 없으면 unknown — "없음"으로 단정하지 않는다', () {
      expect(const AuthState().joinRequestTrace, JoinRequestTrace.unknown);
    });

    test('연결 여부를 모르는 상태도 unknown — /v1/me 실패는 요청 상태도 모른다는 뜻', () {
      expect(const AuthState(connectionUnknown: true).joinRequestTrace, JoinRequestTrace.unknown);
    });

    test('매칭만 있는 상태도 unknown — 로그인 경로는 서버 요청 상태를 묻지 않는다', () {
      // `_matchAfterSignIn`은 member가 있으면 로컬 기록조차 보지 않는다. matched라고 요청이
      // 없다는 뜻이 아니고, 있다는 뜻도 아니다.
      expect(const AuthState(match: match).joinRequestTrace, JoinRequestTrace.unknown);
    });

    // P63 검증 반영 — 코드 인증 직후 경로는 서버를 묻지 않는다. 그 사이 센터가 거절·삭제한
    // 요청도 로컬 기록은 그대로라, 로컬만 믿으면 "보낸 가입 요청 (이름·전화번호)"를 단정한다.
    // 화면(centerConfirmStage)은 로컬 기록으로 대기 카드를 세워도 되지만 고지는 아니다.
    test('로컬 기록(joinRequestedAt)만 있으면 unknown — 서버가 확답한 적이 없다', () {
      final state = AuthState(joinRequestedAt: DateTime(2026, 9, 6));
      expect(state.joinRequestTrace, JoinRequestTrace.unknown);
      expect(state.centerConfirmStage, CenterConfirmStage.pendingApproval, reason: '화면은 종전대로 대기');
    });

    test('서버가 pending이면 pending — 로컬 기록 없이도(기기 변경)', () {
      expect(const AuthState(serverJoinStatus: 'pending').joinRequestTrace, JoinRequestTrace.pending);
    });

    test('서버 pending + 로컬 기록(requestJoin 성공 직후)도 pending', () {
      final state = AuthState(serverJoinStatus: 'pending', joinRequestedAt: DateTime(2026, 9, 6));
      expect(state.joinRequestTrace, JoinRequestTrace.pending);
    });

    test('서버가 rejected면 settled — 센터가 이름·번호를 비웠고 기록만 남았다', () {
      expect(const AuthState(serverJoinStatus: 'rejected').joinRequestTrace, JoinRequestTrace.settled);
    });

    test('서버가 approved(부분 잔여)여도 settled — 문서 모양이 rejected와 같다', () {
      expect(const AuthState(serverJoinStatus: 'approved').joinRequestTrace, JoinRequestTrace.settled);
    });

    test('서버 rejected가 로컬 대기 기록을 이긴다 — centerConfirmStage와 같은 우선순위', () {
      final state = AuthState(serverJoinStatus: 'rejected', joinRequestedAt: DateTime(2026, 9, 6));
      expect(state.joinRequestTrace, JoinRequestTrace.settled);
    });
  });

  // P69 C2 — "다시 요청"은 서버가 pending을 확답하지 않은 대기 화면에서만. 확답 뒤 재요청은 100% 409.
  group('AuthState.canRetryJoinRequest', () {
    test('로컬 기록만(unknown) → true', () {
      expect(AuthState(joinRequestedAt: DateTime(2026, 9, 8)).canRetryJoinRequest, isTrue);
    });

    test('서버 확답 pending → false (로컬 기록이 함께 있어도)', () {
      expect(const AuthState(serverJoinStatus: 'pending').canRetryJoinRequest, isFalse);
      expect(
        AuthState(serverJoinStatus: 'pending', joinRequestedAt: DateTime(2026, 9, 8)).canRetryJoinRequest,
        isFalse,
      );
    });

    test('rejected·notFound·matched → false (재요청은 CTA 블록의 몫이거나 요청이 없다)', () {
      expect(const AuthState(serverJoinStatus: 'rejected').canRetryJoinRequest, isFalse);
      expect(const AuthState().canRetryJoinRequest, isFalse);
      expect(const AuthState(match: match).canRetryJoinRequest, isFalse);
    });

    test('서버 null 확답 뒤(clearServerJoinStatus) 로컬 기록이 남으면 다시 true — 막다른 길 없음', () {
      final state = AuthState(serverJoinStatus: 'pending', joinRequestedAt: DateTime(2026, 9, 8));
      expect(state.copyWith(clearServerJoinStatus: true).canRetryJoinRequest, isTrue);
    });
  });

  // P69 H2 — 스텝퍼 현재 단계. matched·rejected·connectionUnknown은 그리지 않는다.
  group('AuthState.lobbyStep', () {
    test('notFound·declined → requested', () {
      expect(const AuthState().lobbyStep, LobbyStep.requested);
      expect(const AuthState(matchDeclined: true).lobbyStep, LobbyStep.requested);
    });

    test('pendingApproval → waiting (로컬 기록·서버 pending 모두)', () {
      expect(AuthState(joinRequestedAt: DateTime(2026, 9, 8)).lobbyStep, LobbyStep.waiting);
      expect(const AuthState(serverJoinStatus: 'pending').lobbyStep, LobbyStep.waiting);
    });

    test('approved 잔여 → connecting (연결이 진행 중이다)', () {
      expect(const AuthState(serverJoinStatus: 'approved').lobbyStep, LobbyStep.connecting);
      expect(
        AuthState(serverJoinStatus: 'approved', joinRequestedAt: DateTime(2026, 9, 8)).lobbyStep,
        LobbyStep.connecting,
      );
    });

    test('matched·rejected·connectionUnknown → null', () {
      expect(const AuthState(match: match).lobbyStep, isNull);
      expect(const AuthState(serverJoinStatus: 'rejected').lobbyStep, isNull);
      expect(const AuthState(connectionUnknown: true).lobbyStep, isNull);
    });
  });

  // P69 H3 — 요청 센터: 서버 값 → 로컬 기록 → ''. 빈 값은 "모른다"이지 "지운다"가 아니다.
  group('AuthState.copyWith — joinCenterId·centerId·확인 시각', () {
    test('빈 joinCenterId는 기존 값을 덮지 않는다 — 구서버 응답이 로컬 폴백을 지우면 안 된다', () {
      const state = AuthState(joinCenterId: 'gangnam-2');
      expect(state.copyWith(joinCenterId: '').joinCenterId, 'gangnam-2');
      expect(state.copyWith().joinCenterId, 'gangnam-2');
      expect(state.copyWith(joinCenterId: 'rise').joinCenterId, 'rise');
    });

    test('centerId도 같은 규약', () {
      const state = AuthState(centerId: 'rise');
      expect(state.copyWith(centerId: '').centerId, 'rise');
      expect(state.copyWith(centerId: 'gangnam-2').centerId, 'gangnam-2');
    });

    test('lastCheckedAt·lastCheckFailedAt는 각자 보존된다', () {
      final checked = DateTime(2026, 9, 8, 12, 14);
      final failed = DateTime(2026, 9, 8, 12, 20);
      final state = const AuthState().copyWith(lastCheckedAt: checked);
      final next = state.copyWith(lastCheckFailedAt: failed);
      expect(next.lastCheckedAt, checked);
      expect(next.lastCheckFailedAt, failed);
    });
  });
}
