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
}
