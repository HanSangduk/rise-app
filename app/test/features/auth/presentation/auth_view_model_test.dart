import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';
import 'package:rise_member/features/auth/domain/auth_repository.dart';
import 'package:rise_member/features/auth/domain/join_request_store.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';

// P2R — 인증 여정 결함 회귀 방지.
//  · 가입 요청이 로컬에 남는가(재실행 복귀의 전제)
//  · "다른 번호로 다시 시도"가 세션·대기기록·상태를 전부 비우는가
//  · 재전송과 확인의 진행 플래그가 분리돼 있는가
void main() {
  late _FakeAuthRepository repo;
  late _FakeJoinRequestStore store;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeAuthRepository();
    store = _FakeJoinRequestStore();
    container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        joinRequestStoreProvider.overrideWithValue(store),
      ],
    );
    // autoDispose 프로바이더를 테스트 동안 살려 둔다.
    container.listen(authViewModelProvider, (_, __) {});
  });

  AuthViewModel notifier() => container.read(authViewModelProvider.notifier);
  AuthState read() => container.read(authViewModelProvider);

  group('requestJoin — 승인 대기 영속', () {
    test('성공하면 대기 시각을 상태와 로컬 저장소 양쪽에 남긴다', () async {
      notifier().setPhone('010-1234-5678');
      final outcome = await notifier().requestJoin('김라이즈');

      expect(outcome, JoinRequestOutcome.sent);
      expect(read().joinRequestedAt, isNotNull);
      expect(read().centerConfirmStage, CenterConfirmStage.pendingApproval);
      expect(store.record, isNotNull);
      // 저장은 항상 E.164 정규화 — 복원 시 Firebase의 phoneNumber와 그대로 대조된다.
      expect(store.record!.phone, '+821012345678');
      expect(store.record!.requestedAt, read().joinRequestedAt);
    });

    test('번호를 모르면 로컬 기록을 남기지 않는다 — 서버는 토큰 번호로 접수한다(P64 검증 반영)', () async {
      // 번호가 비어 있어도 요청은 유효하다(서버가 토큰의 번호로 접수). 다만 ''로 저장한
      // 기록은 어떤 번호와도 matches하지 않아 복원 때 죽은 줄이 된다.
      expect(read().phone, isEmpty);
      final outcome = await notifier().requestJoin('김라이즈');

      expect(outcome, JoinRequestOutcome.sent);
      expect(read().centerConfirmStage, CenterConfirmStage.pendingApproval, reason: '화면은 대기 카드');
      expect(store.record, isNull, reason: '빈 번호의 기록은 죽은 줄이다');
    });

    test('실패하면 아무것도 남기지 않는다 (있지도 않은 대기 카드 방지)', () async {
      notifier().setPhone('010-1234-5678');
      repo.requestJoinResult = const Err(NetworkFailure());

      expect(await notifier().requestJoin('김라이즈'), JoinRequestOutcome.failed);
      expect(read().joinRequestedAt, isNull);
      expect(store.record, isNull);
      expect(read().error, isA<NetworkFailure>());
    });
  });

  group('로그아웃도 같은 정리를 거쳐야 한다 (P32)', () {
    test('정리하지 않으면 다음 사람에게 남는 값이 무엇인지', () async {
      // **교차검증 팀이 찾은 결함**: `my_screen`의 로그아웃이 Firebase signOut과
      // 세션 clear만 하고 이 뷰모델은 건드리지 않았다. `authViewModelProvider`는
      // `keepAlive`라 로그아웃해도 살아남는다.
      //
      // 아래가 그때 남는 값들이다 — 한 기기를 두 회원이 쓰는 자리(센터 태블릿·
      // 가족 공용폰)에서 다음 사람이 그대로 본다.
      notifier().setPhone('01012345678');
      await notifier().requestJoin('김민지');
      expect(read().phone, isNotEmpty);
      expect(read().joinRequestedAt, isNotNull);

      // 로그아웃 경로가 이 함수를 부르면 전부 사라진다.
      await notifier().restartWithNewPhone();

      expect(read().phone, isEmpty,
          reason: '남의 번호가 채워진 채로 인증 문자가 그 사람에게 간다');
      expect(read().joinRequestedAt, isNull,
          reason: '보낸 적 없는 "승인 대기 중" 화면이 뜬다');
    });
  });

  group('restartWithNewPhone — 상시 탈출구', () {
    test('Firebase 로그아웃 + 플로우 상태 초기화', () async {
      notifier().setPhone('010-1234-5678');
      await notifier().requestJoin('김라이즈');

      await notifier().restartWithNewPhone();

      expect(repo.signOutCount, 1);
      expect(read().phone, isEmpty);
      expect(read().joinRequestedAt, isNull);
      expect(read().match, isNull);
      expect(read().matchDeclined, isFalse);
      expect(read().submitting, isFalse);
      expect(read().centerConfirmStage, CenterConfirmStage.notFound);
    });

    test('대기 기록은 남긴다 — 같은 번호로 돌아오면 중복 요청 대신 대기로 복귀', () async {
      notifier().setPhone('010-1234-5678');
      await notifier().requestJoin('김라이즈');
      await notifier().restartWithNewPhone();
      expect(store.record, isNotNull);

      // 같은 번호로 재인증 → 매칭은 여전히 없지만 대기 사실이 살아난다.
      notifier().setPhone('010-1234-5678');
      await notifier().sendCode();
      await notifier().verifyAndMatch();
      expect(read().centerConfirmStage, CenterConfirmStage.pendingApproval);
    });

    test('다른 번호로 재인증하면 남의 대기 카드가 뜨지 않는다', () async {
      notifier().setPhone('010-1234-5678');
      await notifier().requestJoin('김라이즈');
      await notifier().restartWithNewPhone();

      notifier().setPhone('010-9999-8888');
      await notifier().sendCode();
      await notifier().verifyAndMatch();
      expect(read().centerConfirmStage, CenterConfirmStage.notFound);
      expect(read().joinRequestedAt, isNull);
    });

    test('매칭을 거부한 상태에서도 동작한다 (막다른 길이던 분기)', () async {
      notifier().setPhone('010-1234-5678');
      repo.match = const JoinMatch(
        member: MatchedMember(id: 'm1', name: '김라이즈', status: 'active'),
        needsConfirm: true,
      );
      await notifier().sendCode();
      await notifier().verifyAndMatch();
      await notifier().confirmMatch(false);
      expect(read().centerConfirmStage, CenterConfirmStage.declined);

      await notifier().restartWithNewPhone();
      expect(repo.signOutCount, 1);
      expect(read().centerConfirmStage, CenterConfirmStage.notFound);
    });
  });

  group('sendCode — 재전송/확인 진행 상태 분리', () {
    test('재전송 중엔 resending만 켜진다 (확인 버튼이 "확인 중…"이 되지 않게)', () async {
      final gate = Completer<Result<PhoneVerificationSession>>();
      repo.pendingSend = gate.future;

      final future = notifier().sendCode(resend: true);
      await Future<void>.delayed(Duration.zero);

      expect(read().resending, isTrue);
      expect(read().submitting, isFalse);
      expect(read().busy, isTrue);

      gate.complete(const Ok(PhoneVerificationSession(verificationId: 'vid')));
      await future;

      expect(read().resending, isFalse);
      expect(read().submitting, isFalse);
    });

    test('최초 발송은 submitting만 켠다', () async {
      final gate = Completer<Result<PhoneVerificationSession>>();
      repo.pendingSend = gate.future;

      final future = notifier().sendCode();
      await Future<void>.delayed(Duration.zero);

      expect(read().submitting, isTrue);
      expect(read().resending, isFalse);

      gate.complete(const Ok(PhoneVerificationSession(verificationId: 'vid')));
      await future;
      expect(read().busy, isFalse);
    });

    test('새 코드가 나가면 직전에 입력해 둔 코드는 무효화된다', () async {
      notifier().setCode('111111');
      await notifier().sendCode(resend: true);
      expect(read().code, isEmpty);
    });
  });

  group('setPhone — 번호를 고치면 옛 발송 세션이 따라가지 않는다', () {
    test('번호가 바뀌면 verificationId·resendToken·code를 모두 버린다', () async {
      notifier().setPhone('010-1234-5678');
      await notifier().sendCode();
      notifier().setCode('123456');
      expect(read().verificationId, 'vid');

      notifier().setPhone('010-9999-8888');

      expect(read().verificationId, isNull);
      expect(read().resendToken, isNull);
      expect(read().code, isEmpty);
    });

    test('표기만 다른 같은 번호면 발송 세션을 유지한다', () async {
      notifier().setPhone('01012345678');
      await notifier().sendCode();
      notifier().setPhone('010-1234-5678');
      expect(read().verificationId, 'vid');
    });
  });

  test('restorePendingJoinRequest — 재실행 복귀 시 대기 카드로 되살아난다', () {
    notifier().restorePendingJoinRequest(
      JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime(2026, 8, 22, 9)),
    );

    expect(read().phone, '+821012345678');
    expect(read().joinRequestedAt, DateTime(2026, 8, 22, 9));
    expect(read().centerConfirmStage, CenterConfirmStage.pendingApproval);
  });

  // 라우터 복원은 화면이 mount되기 **전에** 상태를 심는다. 이 구간엔 구독자가
  // 0이라, autoDispose였을 땐 심어 둔 대기 상태가 조용히 폐기돼 복원이 통째로
  // 무력화됐다(실측). keepAlive 회귀 방지.
  test('구독자 없이 심어 둔 상태가 async gap을 건너 살아남는다', () async {
    final bare = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        joinRequestStoreProvider.overrideWithValue(store),
      ],
    );
    bare.read(authViewModelProvider.notifier).restorePendingJoinRequest(
          JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime(2026, 8, 22, 9)),
        );

    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(bare.read(authViewModelProvider).centerConfirmStage,
        CenterConfirmStage.pendingApproval);
  });

  // 안드로이드 Firebase 즉시 인증(verificationCompleted)은 SMS 없이 로그인을
  // 끝내고 **빈 verificationId**로 성공한다. 그때 코드 화면으로 보내면 오지 않을
  // 인증번호를 기다리며 재전송 카운트다운을 도는 막다른 길이 된다.
  group('sendCode — 즉시 인증은 코드 화면을 건너뛴다', () {
    const matched = JoinMatch(
      member: MatchedMember(id: 'm1', name: '김라이즈', status: 'active'),
      needsConfirm: true,
    );

    test('빈 verificationId면 매칭까지 끝내고 verified를 돌려준다', () async {
      notifier().setPhone('010-1234-5678');
      repo.sendResult = const Ok(PhoneVerificationSession(verificationId: ''));
      repo.match = matched;

      expect(await notifier().sendCode(), SendCodeOutcome.verified);

      expect(repo.matchJoinCount, 1);
      expect(read().match?.member?.name, '김라이즈');
      expect(read().centerConfirmStage, CenterConfirmStage.matched);
      // 진행 표시는 매칭이 끝나는 시점에 함께 내려가야 한다("전송 중…" 잔상 방지).
      expect(read().busy, isFalse);
    });

    test('정상 SMS 경로는 그대로 codeSent — 매칭을 미리 하지 않는다', () async {
      notifier().setPhone('010-1234-5678');

      expect(await notifier().sendCode(), SendCodeOutcome.codeSent);

      expect(repo.matchJoinCount, 0);
      expect(read().verificationId, 'vid');
      expect(read().match, isNull);
      expect(read().busy, isFalse);
    });

    test('즉시 인증인데 매칭이 실패하면 failed — 화면 이동 없이 사유만 남는다', () async {
      notifier().setPhone('010-1234-5678');
      repo.sendResult = const Ok(PhoneVerificationSession(verificationId: ''));
      repo.matchResult = const Err(NetworkFailure());

      expect(await notifier().sendCode(), SendCodeOutcome.failed);

      expect(read().error, isA<NetworkFailure>());
      expect(read().busy, isFalse);
    });

    test('재전송이 즉시 인증으로 끝나도 verified — 코드 화면에 남기지 않는다', () async {
      notifier().setPhone('010-1234-5678');
      await notifier().sendCode();
      repo.sendResult = const Ok(PhoneVerificationSession(verificationId: ''));
      repo.match = matched;

      expect(await notifier().sendCode(resend: true), SendCodeOutcome.verified);
      expect(read().resending, isFalse);
      expect(read().centerConfirmStage, CenterConfirmStage.matched);
    });

    test('빈 verificationId도 상태에 남는다 — 머무른 화면의 "확인"이 죽지 않게', () async {
      notifier().setPhone('010-1234-5678');
      repo.sendResult = const Ok(PhoneVerificationSession(verificationId: ''));
      repo.matchResult = const Err(NetworkFailure());
      await notifier().sendCode();

      // null이면 verifyAndMatch가 "인증번호를 다시 요청해주세요"로 막아 선다.
      expect(read().verificationId, '');
      repo.matchResult = null;
      expect(await notifier().verifyAndMatch(), isTrue);
    });
  });

  // 안드로이드 SMS 자동 회수가 codeSent **이후**에 도착하는 정상 흐름.
  // P08은 codeSent **이전**(즉시 인증)만 처리해서, 코드 화면에 이미 들어온 뒤
  // 자동 회수가 끝나면 사용자는 로그인이 됐는데도 오지 않을 입력을 기다리며
  // 재전송 카운트다운을 계속 돌았다.
  group('completeAutoVerification — codeSent 이후 자동 회수', () {
    const matched = JoinMatch(
      member: MatchedMember(id: 'm1', name: '김라이즈', status: 'active'),
      needsConfirm: true,
    );

    Future<void> onCodeScreen() async {
      notifier().setPhone('010-1234-5678');
      repo.match = matched;
      expect(await notifier().sendCode(), SendCodeOutcome.codeSent);
    }

    test('같은 번호로 로그인이 끝나면 코드 확인과 같은 매칭 경로로 잇는다', () async {
      await onCodeScreen();

      expect(await notifier().completeAutoVerification('+821012345678'), isTrue);

      expect(repo.matchJoinCount, 1);
      expect(read().centerConfirmStage, CenterConfirmStage.matched);
      expect(read().busy, isFalse);
    });

    test('다른 번호로 남아 있던 세션은 가로채지 못한다', () async {
      await onCodeScreen();

      expect(await notifier().completeAutoVerification('+821099998888'), isFalse);

      expect(repo.matchJoinCount, 0);
      expect(read().centerConfirmStage, CenterConfirmStage.notFound);
    });

    test('"확인"이 진행 중이면 물러난다 — 매칭이 두 번 나가지 않는다', () async {
      await onCodeScreen();
      final gate = Completer<Result<JoinMatch>>();
      repo.pendingMatch = gate.future;

      final manual = notifier().verifyAndMatch();
      await Future<void>.delayed(Duration.zero);
      expect(read().busy, isTrue);

      expect(await notifier().completeAutoVerification('+821012345678'), isFalse);
      expect(repo.matchJoinCount, 1);

      gate.complete(const Ok(matched));
      expect(await manual, isTrue);
      expect(repo.matchJoinCount, 1);
    });

    test('이미 매칭을 마쳤으면 다시 묻지 않는다(확인 직후 늦게 도착한 이벤트)', () async {
      await onCodeScreen();
      expect(await notifier().verifyAndMatch(), isTrue);
      expect(repo.matchJoinCount, 1);

      expect(await notifier().completeAutoVerification('+821012345678'), isFalse);
      expect(repo.matchJoinCount, 1);
    });

    test('즉시 인증(P08)과 이중으로 발화하지 않는다', () async {
      // 즉시 인증은 sendCode가 그 자리에서 매칭까지 끝내고 verified를 돌려준다
      // (그래서 코드 화면에 도달하지도 않는다). 그래도 같은 로그인 이벤트가
      // 흘러들면 match 가드가 두 번째 매칭을 막는다.
      notifier().setPhone('010-1234-5678');
      repo.sendResult = const Ok(PhoneVerificationSession(verificationId: ''));
      repo.match = matched;
      expect(await notifier().sendCode(), SendCodeOutcome.verified);
      expect(repo.matchJoinCount, 1);

      expect(await notifier().completeAutoVerification('+821012345678'), isFalse);
      expect(repo.matchJoinCount, 1);
    });

    test('매칭에 실패하면 사유만 남기고 화면은 그대로 — 다시 시도할 수 있다', () async {
      await onCodeScreen();
      repo.matchResult = const Err(NetworkFailure());

      expect(await notifier().completeAutoVerification('+821012345678'), isFalse);

      expect(read().error, isA<NetworkFailure>());
      expect(read().busy, isFalse);
      expect(read().centerConfirmStage, CenterConfirmStage.notFound);

      // 아직 매칭이 없으므로 다음 이벤트/버튼이 다시 시도할 수 있어야 한다.
      repo.matchResult = null;
      expect(await notifier().completeAutoVerification('+821012345678'), isTrue);
    });
  });

  test('setPhone — 번호를 바꾸면 직전 번호의 매칭 결과도 함께 버린다', () async {
    notifier().setPhone('010-1234-5678');
    repo.match = const JoinMatch(
      member: MatchedMember(id: 'm1', name: '김라이즈', status: 'active'),
      needsConfirm: true,
    );
    await notifier().sendCode();
    await notifier().verifyAndMatch();
    expect(read().centerConfirmStage, CenterConfirmStage.matched);

    // 남겨 두면 새 번호를 입력한 사용자에게 옛 번호 주인의 이름으로 "본인이에요"를
    // 묻게 된다(그리고 자동 진행의 중복 가드도 영영 잠긴 채로 남는다).
    notifier().setPhone('010-9999-8888');

    expect(read().match, isNull);
    expect(read().centerConfirmStage, CenterConfirmStage.notFound);
  });

  // 대표가 승인해도 앱은 알 방법이 없었다 — 앱 재실행이나 가입 **재요청**뿐이고,
  // 재요청은 대표 화면에 같은 사람을 한 줄 더 쌓는다. 읽기 전용 확인 경로.
  group('checkConnection — "연결됐는지 확인"', () {
    Future<void> waitPending() async {
      notifier().setPhone('010-1234-5678');
      await notifier().requestJoin('김라이즈');
    }

    test('연결됐으면 세션을 세우고 대기 기록을 폐기한다', () async {
      await waitPending();
      repo.session =
          const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1');

      expect(await notifier().checkConnection(), ConnectionCheck.connected);

      expect(container.read(sessionProvider)?.memberId, 'm1');
      expect(store.record, isNull);
      expect(read().busy, isFalse);
    });

    test('아직이면 notYet — 대기 상태도 로컬 기록도 그대로 둔다', () async {
      await waitPending();

      expect(await notifier().checkConnection(), ConnectionCheck.notYet);

      expect(read().centerConfirmStage, CenterConfirmStage.pendingApproval);
      expect(store.record, isNotNull);
      // "아직"은 오류가 아니다 — 빨간 문구를 띄우지 않는다.
      expect(read().error, isNull);
    });

    // P63 검증 반영 — 서버가 요청 없음(joinStatus null)이라 답하면 requestJoin이 세운
    // 'pending'을 지운다. copyWith의 `?? this`로는 못 지우던 자리(clearServerJoinStatus).
    test('아직인데 서버에 요청이 없으면 serverJoinStatus를 지운다 — 삭제 고지가 unknown으로', () async {
      await waitPending();
      expect(read().joinRequestTrace, JoinRequestTrace.pending);

      expect(await notifier().checkConnection(), ConnectionCheck.notYet);

      expect(read().serverJoinStatus, isNull);
      expect(read().joinRequestTrace, JoinRequestTrace.unknown);
      // 로컬 대기 기록은 종전대로 — 화면은 대기 카드를 유지한다(재확인 버튼이 거기 있다).
      expect(read().centerConfirmStage, CenterConfirmStage.pendingApproval);
    });

    test('applyServerJoinStatus(null)도 지운다 — 복원·재확인이 같은 규약', () async {
      await waitPending();
      notifier().applyServerJoinStatus(null);
      expect(read().serverJoinStatus, isNull);
      expect(read().joinRequestTrace, JoinRequestTrace.unknown);
    });

    // P69 C2 — 서버 null은 "없음 ∪ 조회 실패"다. joinRequestedAt을 지우면 화면이 빈 상태로 떨어져
    // 중복 요청이 나가고, 남기면 `unknown`이라 "다시 요청"이 다시 열린다(막다른 길 없음).
    test('서버 null 응답은 joinRequestedAt을 유지한다 — 그래서 "다시 요청"이 다시 열린다', () async {
      await waitPending();
      final before = read().joinRequestedAt;
      expect(read().canRetryJoinRequest, isFalse, reason: '서버 확답 pending');

      await notifier().checkConnection();

      expect(read().joinRequestedAt, before);
      expect(read().canRetryJoinRequest, isTrue);
    });

    // P69 H1·H2 — 확인 상태 줄의 시각. 성공(notYet/connected)에만 lastCheckedAt, 실패에만 failedAt.
    test('notYet은 lastCheckedAt만, 실패는 lastCheckFailedAt만 세운다', () async {
      await waitPending();
      await withClock(Clock.fixed(DateTime(2026, 9, 8, 12, 14)), () async {
        await notifier().checkConnection();
      });
      expect(read().lastCheckedAt, DateTime(2026, 9, 8, 12, 14));
      expect(read().lastCheckFailedAt, isNull);

      repo.sessionResult = const Err(NetworkFailure());
      await withClock(Clock.fixed(DateTime(2026, 9, 8, 12, 20)), () async {
        await notifier().checkConnection();
      });
      expect(read().lastCheckFailedAt, DateTime(2026, 9, 8, 12, 20));
      expect(read().lastCheckedAt, DateTime(2026, 9, 8, 12, 14), reason: '실패가 성공 시각을 덮지 않는다');
    });

    test('connected도 lastCheckedAt을 세운다', () async {
      await waitPending();
      repo.session = const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1');
      await withClock(Clock.fixed(DateTime(2026, 9, 8, 12, 30)), () async {
        expect(await notifier().checkConnection(), ConnectionCheck.connected);
      });
      expect(read().lastCheckedAt, DateTime(2026, 9, 8, 12, 30));
    });

    // P69 H3 — 계약 v2.34: /v1/me가 요청 센터와 Principal 센터를 함께 준다.
    test('MemberNotLinkedFailure의 centerId·joinCenterId를 상태에 나른다', () async {
      await waitPending();
      repo.sessionResult = const Err(MemberNotLinkedFailure(
        joinStatus: 'pending',
        centerId: 'rise',
        joinCenterId: 'gangnam-2',
      ));
      await notifier().checkConnection();
      expect(read().centerId, 'rise');
      expect(read().joinCenterId, 'gangnam-2');
    });
    test('네트워크 실패면 failed — 대기 상태를 뒤집지 않고 사유만 남긴다', () async {
      await waitPending();
      repo.sessionResult = const Err(NetworkFailure());

      expect(await notifier().checkConnection(), ConnectionCheck.failed);

      expect(read().centerConfirmStage, CenterConfirmStage.pendingApproval);
      expect(store.record, isNotNull);
      expect(read().error, isA<NetworkFailure>());
      expect(read().busy, isFalse);
    });

    test('연타해도 서버에 두 번 묻지 않는다', () async {
      await waitPending();
      final gate = Completer<Result<AppSession>>();
      repo.pendingLoadSession = gate.future;

      final first = notifier().checkConnection();
      await Future<void>.delayed(Duration.zero);
      final second = notifier().checkConnection();

      expect(await second, ConnectionCheck.failed); // 두 번째 탭은 조용히 무시
      gate.complete(const Err(MemberNotLinkedFailure()));
      expect(await first, ConnectionCheck.notYet);
      expect(repo.loadSessionCount, 1);
    });

    test('확인 중엔 checkingConnection만 켜진다 (본인확인 CTA가 뒤바뀌지 않게)', () async {
      await waitPending();
      final gate = Completer<Result<AppSession>>();
      repo.pendingLoadSession = gate.future;

      final future = notifier().checkConnection();
      await Future<void>.delayed(Duration.zero);

      expect(read().checkingConnection, isTrue);
      expect(read().submitting, isFalse);
      expect(read().busy, isTrue);

      gate.complete(const Err(MemberNotLinkedFailure()));
      await future;
      expect(read().busy, isFalse);
    });
  });

  // P69 C2 — 409 `join_pending`(계약 v2.34)은 실패가 아니라 pending 확답이다.
  group('requestJoin — 409 join_pending 승격', () {
    test('alreadyPending을 돌려주고 serverJoinStatus=pending·joinCenterId·로컬 기록을 세운다', () async {
      notifier().setPhone('010-1234-5678');
      repo.requestJoinResult = const Err(JoinPendingFailure(centerId: 'gangnam-2'));

      expect(await notifier().requestJoin('김라이즈', centerId: 'rise'), JoinRequestOutcome.alreadyPending);

      expect(read().joinRequestTrace, JoinRequestTrace.pending);
      expect(read().centerConfirmStage, CenterConfirmStage.pendingApproval);
      expect(read().joinCenterId, 'gangnam-2', reason: '서버가 말한 센터가 고른 센터를 이긴다');
      expect(read().joinRequestedAt, isNull, reason: '요청 시각은 서버 것 — 지어내지 않는다');
      expect(read().error, isNull, reason: '실패가 아니다');
      expect(store.record?.centerId, 'gangnam-2');
      expect(store.record?.phone, '+821012345678');
    });

    test('409에 center_id가 없으면 고른 센터로 폴백', () async {
      notifier().setPhone('010-1234-5678');
      repo.requestJoinResult = const Err(JoinPendingFailure());
      await notifier().requestJoin('김라이즈', centerId: 'rise');
      expect(read().joinCenterId, 'rise');
    });

    test('성공 시 고른 센터가 상태·로컬 기록에 남는다', () async {
      notifier().setPhone('010-1234-5678');
      expect(await notifier().requestJoin('김라이즈', centerId: 'gangnam-2'), JoinRequestOutcome.sent);
      expect(read().joinCenterId, 'gangnam-2');
      expect(store.record?.centerId, 'gangnam-2');
    });

    test('restorePendingJoinRequest는 기록의 센터를 폴백으로 세운다', () {
      notifier().restorePendingJoinRequest(
        JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime(2026, 9, 8), centerId: 'gangnam-2'),
      );
      expect(read().joinCenterId, 'gangnam-2');
      // 서버가 뒤에 빈 값을 주면(구서버) 폴백이 남고, 값을 주면 덮는다.
      notifier().applyServerJoinStatus('pending');
      expect(read().joinCenterId, 'gangnam-2');
      notifier().applyServerJoinStatus('pending', joinCenterId: 'rise');
      expect(read().joinCenterId, 'rise');
    });

  });

  // 앱 시작 복원이 GET /v1/me에 실패했을 때 — "미연결"로 단정하지 않는 상태.
  group('markConnectionUnknown — 확인하지 못한 상태', () {
    test('connectionUnknown 단계로 세우고 사유를 남긴다', () {
      notifier().markConnectionUnknown(const NetworkFailure());

      expect(read().centerConfirmStage, CenterConfirmStage.connectionUnknown);
      expect(read().error, isA<NetworkFailure>());
    });

    test('"아직"이라는 확답을 받으면 재확인 화면에서 내려온다', () async {
      notifier().markConnectionUnknown(const NetworkFailure());

      expect(await notifier().checkConnection(), ConnectionCheck.notYet);
      expect(read().centerConfirmStage, CenterConfirmStage.notFound);
    });

    test('확인에 또 실패하면 재확인 화면을 유지한다', () async {
      notifier().markConnectionUnknown(const NetworkFailure());
      repo.sessionResult = const Err(NetworkFailure());

      expect(await notifier().checkConnection(), ConnectionCheck.failed);
      expect(read().centerConfirmStage, CenterConfirmStage.connectionUnknown);
    });

    test('매칭이 성공하면 폴백이 내려간다 (재인증으로 상태가 확정된 경우)', () async {
      notifier().markConnectionUnknown(const NetworkFailure());
      notifier().setPhone('010-1234-5678');
      await notifier().sendCode();
      await notifier().verifyAndMatch();

      expect(read().connectionUnknown, isFalse);
      expect(read().centerConfirmStage, CenterConfirmStage.notFound);
    });
  });

  // P10 — 홈 헤더의 이름이 "실행 시점에 따라" 달라지던 문제의 앱 쪽 절반.
  //
  // 최초 로그인은 매칭 응답의 이름을 쓰고, 앱 재실행 복원은 GET /v1/me만 쓴다.
  // /v1/me가 이름을 주지 않던 시절엔 두 경로의 결과가 갈렸다(로그인 직후엔
  // "김민지 님", 재실행 뒤엔 센터명). 계약 v2.2 이후로는 **양쪽 다 /v1/me의
  // name을 1차 출처로** 쓰고, 그게 비었을 때만 매칭 응답으로 메운다.
  group('세션 표시 이름 — 최초 로그인과 재실행 복원이 같은 값에 도달한다', () {
    const matched = JoinMatch(
      member: MatchedMember(id: 'm1', name: '김라이즈', status: 'active'),
      needsConfirm: true,
    );

    Future<void> matchThenConfirm() async {
      notifier().setPhone('010-1234-5678');
      repo.match = matched;
      await notifier().sendCode();
      await notifier().verifyAndMatch();
      expect(await notifier().confirmMatch(true), isTrue);
    }

    AppSession session({String name = ''}) =>
        AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: name);

    test('confirmMatch — /v1/me가 이름을 주면 그 값을 쓴다', () async {
      repo.session = session(name: '김민지');
      await matchThenConfirm();

      // 재실행 복원(session_restore)이 세우는 세션과 같은 출처·같은 값이다.
      expect(container.read(sessionProvider)?.memberName, '김민지');
    });

    test('confirmMatch — /v1/me가 이름을 못 주면 매칭 응답으로 메운다', () async {
      // best-effort 실패·구버전 서버. 최초 로그인만큼은 이름을 띄울 수 있다.
      repo.session = session();
      await matchThenConfirm();

      expect(container.read(sessionProvider)?.memberName, '김라이즈');
    });

    test('checkConnection — 매칭 이력이 없는 승인 대기 경로도 /v1/me 이름을 받는다', () async {
      // 이 경로엔 매칭 응답 자체가 없다(가입 요청 → 대표 승인). 예전엔 여기서
      // 이름이 무조건 ''이라 헤더가 센터명으로 떨어졌다.
      notifier().setPhone('010-1234-5678');
      await notifier().requestJoin('김라이즈');
      repo.session = session(name: '김민지');

      expect(await notifier().checkConnection(), ConnectionCheck.connected);
      expect(container.read(sessionProvider)?.memberName, '김민지');
    });

    test('둘 다 없으면 "" — 헤더의 센터명 폴백에 맡긴다', () async {
      notifier().setPhone('010-1234-5678');
      await notifier().requestJoin('김라이즈');
      repo.session = session();

      expect(await notifier().checkConnection(), ConnectionCheck.connected);
      // ''가 그대로 남아야 헤더가 폴백을 탄다(빈 문자열을 보간하면 "  님").
      expect(container.read(sessionProvider)?.memberName, isEmpty);
    });

    test('매칭 이름이 공백뿐이면 폴백으로 치지 않는다', () async {
      notifier().setPhone('010-1234-5678');
      repo.match = const JoinMatch(
        member: MatchedMember(id: 'm1', name: '   ', status: 'active'),
        needsConfirm: true,
      );
      repo.session = session();
      await notifier().sendCode();
      await notifier().verifyAndMatch();
      expect(await notifier().confirmMatch(true), isTrue);

      expect(container.read(sessionProvider)?.memberName, isEmpty);
    });
  });

  test('confirmMatch 성공 — 연결이 끝나면 대기기록을 폐기한다', () async {
    notifier().setPhone('010-1234-5678');
    repo.match = const JoinMatch(
      member: MatchedMember(id: 'm1', name: '김라이즈', status: 'active'),
      needsConfirm: true,
    );
    repo.session = const AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1');
    await notifier().sendCode();
    await notifier().verifyAndMatch();
    await notifier().requestJoin('김라이즈');
    expect(store.record, isNotNull);

    expect(await notifier().confirmMatch(true), isTrue);
    expect(store.record, isNull);
    expect(store.clearCount, greaterThanOrEqualTo(1));
  });
}

class _FakeAuthRepository implements AuthRepository {
  int signOutCount = 0;
  int matchJoinCount = 0;
  int loadSessionCount = 0;
  Result<void> requestJoinResult = const Ok(null);
  JoinMatch match = const JoinMatch(needsConfirm: false);
  AppSession? session;

  /// 발송 결과 고정 — 즉시 인증(빈 verificationId) 경로 재현용.
  Result<PhoneVerificationSession> sendResult =
      const Ok(PhoneVerificationSession(verificationId: 'vid'));

  /// 매칭 결과 고정 — 지정하면 [match]보다 우선(실패 경로 재현용).
  Result<JoinMatch>? matchResult;

  /// 세션 조회 결과 고정 — 지정하면 [session]보다 우선.
  Result<AppSession>? sessionResult;

  /// 진행 중 상태를 관찰하려고 발송을 붙잡아 두는 게이트.
  Future<Result<PhoneVerificationSession>>? pendingSend;

  /// 같은 목적의 세션 조회 게이트(연결 확인 연타·진행 표시 관찰용).
  Future<Result<AppSession>>? pendingLoadSession;

  @override
  Future<Result<PhoneVerificationSession>> requestVerificationCode(
    String phone, {
    int? resendToken,
  }) {
    return pendingSend ?? Future.value(sendResult);
  }

  @override
  Future<Result<void>> verifyCode({
    required String phone,
    required String verificationId,
    required String code,
  }) async =>
      const Ok(null);

  /// 매칭을 붙잡아 두는 게이트 — "확인"과 자동 진행이 겹치는 순간을 재현한다.
  Future<Result<JoinMatch>>? pendingMatch;

  @override
  Future<Result<JoinMatch>> matchJoin(String phone) {
    matchJoinCount++;
    final gate = pendingMatch;
    if (gate != null) return gate;
    return Future.value(matchResult ?? Ok(match));
  }

  @override
  Future<Result<void>> confirmJoin({
    required String memberId,
    required bool confirm,
    required String phone,
  }) async =>
      const Ok(null);

  @override
  Future<Result<void>> requestJoin({required String name, required String phone, String centerId = ''}) async =>
      requestJoinResult;

  /// v2.33 — 센터 목록. 이 스위트들은 선택 UI를 다루지 않으므로 빈 목록(= 고를 것 없음)이다.
  @override
  Future<Result<List<CenterDirectory>>> fetchJoinCenters() async =>
      const Ok(<CenterDirectory>[]);

  @override
  Future<Result<AppSession>> loadSession() {
    loadSessionCount++;
    final gate = pendingLoadSession;
    if (gate != null) return gate;
    final override = sessionResult;
    if (override != null) return Future.value(override);
    final s = session;
    // 실제 구현과 동일하게 "아직 연결 전"은 전용 타입으로 돌려준다 —
    // 세션 복원·연결 확인이 네트워크 오류와 가르는 기준이 이 타입이다.
    return Future.value(s == null ? const Err(MemberNotLinkedFailure()) : Ok(s));
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
  }

  /// 안드로이드 SMS 자동 회수가 codeSent **이후** 로그인을 끝내는 순간을
  /// 테스트가 직접 흘려 넣는다(실구현은 authStateChanges().skip(1)).
  final signedIn = StreamController<String?>.broadcast();

  @override
  Stream<String?> signedInPhoneChanges() => signedIn.stream;
}

class _FakeJoinRequestStore implements JoinRequestStore {
  JoinRequestRecord? record;
  int clearCount = 0;

  @override
  Future<JoinRequestRecord?> read() async => record;

  @override
  Future<void> save(JoinRequestRecord value) async => record = value;

  @override
  Future<void> clear() async {
    clearCount++;
    record = null;
  }
}
