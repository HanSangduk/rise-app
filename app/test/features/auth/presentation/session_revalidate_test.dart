// 캐시 세션 뒤의 **백그라운드 재검증** 세 갈래의 부작용(P64).
//
// `restoreAuthLanding`은 캐시가 있으면 네트워크를 기다리지 않고 `/home`을 돌려주고
// 뒤에서 `GET /v1/me`를 다시 부른다. 그 결과를 어떻게 다루는지는 그동안 테스트가
// 한 번도 고정하지 않았다(`session_restore_test`는 순수 함수만 덮는다). 실제로 이
// 경로만 서버가 실어 준 `join_status`를 읽지 않아, 연결 해제 확답이 **빈 대기실**
// 로 떨어질 뻔했다 — 콜드스타트 경로와 같은 규약이어야 한다.
//
// 뮤테이션: notLinked 분기의 `applyServerJoinStatus` 호출을 지우면 (a)가 죽는다.
// `clear(reason: notLinked)`를 다른 이유로 바꿔도 (a)가 죽는다.
// notLinked 분기의 `seedLobbyIdentity`(phone 세팅)를 지우면 (a)·(a′)가 죽는다(P64 검증 반영).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/session/session_store.dart';
import 'package:rise_member/features/auth/domain/join_request_store.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
import 'package:rise_member/features/auth/presentation/session_restore.dart';

void main() {
  const cached = AppSession(
    uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람',
  );
  const fresh = AppSession(
    uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1', memberName: '람(개명)',
  );

  late _SpySessionStore sessionStore;
  late _FakeJoinRequestStore joinStore;
  late ProviderContainer container;

  setUp(() {
    sessionStore = _SpySessionStore();
    joinStore = _FakeJoinRequestStore()
      ..record = JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime(2026, 9, 1));
    container = ProviderContainer.test(
      overrides: [
        sessionStoreProvider.overrideWithValue(sessionStore),
        joinRequestStoreProvider.overrideWithValue(joinStore),
        // 재검증 본문은 네트워크를 만지지 않는다 — 만지면 이 스텁이 던져 테스트가 죽는다.
        authRepositoryProvider.overrideWith((ref) => throw UnimplementedError('네트워크 금지')),
      ],
    );
    // 캐시로 들여보낸 상태: 세션이 차 있고 캐시에도 써 둔 상태.
    container.read(sessionProvider.notifier).set(cached);
    sessionStore.cleared = 0;
  });

  Future<void> run(Result<AppSession> result, {String? phone = '+821012345678'}) =>
      applyRevalidation(
        read: container.read,
        result: result,
        joinStore: joinStore,
        phone: phone,
      );

  test('(a) 미연결 확답 → 세션 비움 · 캐시 삭제 · 이유 notLinked · 서버 가입 상태를 대기실에 넘긴다',
      () async {
    // 로컬 기록 없음 — 번호는 오직 Firebase 신원(phone 인자)에서만 올 수 있다(기록이 있으면
    // restorePendingJoinRequest가 번호를 채워 phone 세팅 누락을 가린다).
    joinStore.record = null;
    final requestedAt = DateTime.utc(2026, 9, 5, 3);
    await run(Err(MemberNotLinkedFailure(
      joinStatus: 'rejected',
      joinRequestedAt: requestedAt,
      centerId: 'rise',
      joinCenterId: 'gangnam-2',
    )));

    expect(container.read(sessionProvider), isNull, reason: '캐시가 가리키는 회원이 더는 없다');
    // 재검증이 먼저 기다려 지우고, `Session.clear()`가 단일 지점 규약으로 한 번 더 지운다 —
    // 두 번인 건 무해하고, 0번이면 다음 기동에 같은 유령 신원으로 들어온다.
    expect(sessionStore.cleared, greaterThanOrEqualTo(1), reason: '안 지우면 다음 기동에 같은 유령 신원으로 들어온다');
    expect(
      container.read(sessionProvider.notifier).lastEndReason,
      SessionEndReason.notLinked,
      reason: '신원은 살아 있다 — 전화번호 화면(SMS 재인증)으로 보내면 안 된다',
    );
    final auth = container.read(authViewModelProvider);
    expect(auth.serverJoinStatus, 'rejected', reason: '대기실이 서버 상태를 모르면 빈 화면으로 뜬다');
    expect(auth.joinRequestedAt, requestedAt);
    expect(auth.centerConfirmStage, CenterConfirmStage.rejected,
        reason: '콜드스타트 경로와 같은 화면이어야 한다(두 경로 분기 금지)');
    expect(joinStore.clearCount, 0, reason: '연결이 끝난 게 아니다 — 대기 기록은 그대로');
    // P64 검증 반영 — 종전엔 이 경로가 번호를 세우지 않아 대기실이 phone ''로 떴고, 거기서
    // 보낸 가입 요청의 로컬 기록이 빈 번호로 저장됐다.
    expect(auth.phone, '+821012345678', reason: 'Firebase 신원의 번호가 대기실에 서야 한다');
    // P69 H3 — 계약 v2.34: 요청 센터·Principal 센터도 콜드스타트와 같은 규약으로 넘긴다.
    expect(auth.joinCenterId, 'gangnam-2', reason: '2호점 신청자의 대기실이 1호점 연락처를 보면 남의 센터');
    expect(auth.centerId, 'rise');
  });

  test('(a′) 미연결 확답 + 서버에 요청 없음 → 로컬 대기 기록이 번호와 맞으면 대기 카드로 복귀', () async {
    await run(const Err(MemberNotLinkedFailure()));

    final auth = container.read(authViewModelProvider);
    expect(auth.phone, '+821012345678');
    expect(auth.joinRequestedAt, DateTime(2026, 9, 1), reason: '콜드스타트와 같은 규약 — 번호가 맞는 로컬 기록은 되살린다');
    expect(auth.centerConfirmStage, CenterConfirmStage.pendingApproval);
  });

  test('(a″) 로컬 기록이 다른 번호의 것이면 되살리지 않는다 — 대기는 번호의 상태다', () async {
    await run(const Err(MemberNotLinkedFailure()), phone: '+821099990000');

    final auth = container.read(authViewModelProvider);
    expect(auth.phone, '+821099990000');
    expect(auth.joinRequestedAt, isNull, reason: '남의 대기 카드가 떴다');
  });

  test('(d) 세션이 이미 null이면 아무것도 하지 않는다 — 먼저 비운 쪽의 착지를 덮어쓰지 않는다', () async {
    // 재검증 응답이 오기 전에 회원이 탈퇴했다.
    container.read(sessionProvider.notifier).clear(reason: SessionEndReason.deleted);
    sessionStore.cleared = 0;

    await run(const Err(MemberNotLinkedFailure(joinStatus: 'rejected')));

    expect(container.read(sessionProvider.notifier).lastEndReason, SessionEndReason.deleted,
        reason: '탈퇴한 사람을 notLinked로 덮어써 대기실에 세우면 안 된다');
    expect(sessionStore.cleared, 0, reason: '먼저 비운 쪽이 이미 지웠다');
    expect(container.read(authViewModelProvider).serverJoinStatus, isNull,
        reason: '세션 없는 재검증 결과가 auth 상태를 건드렸다');
  });

  test('(b) 네트워크 실패 → 세션·캐시·대기 기록 전부 그대로(모름은 미연결이 아니다)', () async {
    await run(const Err(NetworkFailure()));

    expect(container.read(sessionProvider), same(cached), reason: '지하철 한 번에 캐시를 버리면 캐시를 둔 의미가 없다');
    expect(sessionStore.cleared, 0);
    expect(container.read(sessionProvider.notifier).lastEndReason, isNull);
    expect(container.read(authViewModelProvider).serverJoinStatus, isNull);
    expect(joinStore.clearCount, 0);
  });

  test('(b′) 일반 AuthFailure·거절도 "모름" — 401은 dio 인터셉터의 몫이라 여기선 손대지 않는다', () async {
    await run(const Err(AuthFailure()));
    await run(const Err(RejectedFailure('요청을 처리할 수 없어요')));

    expect(container.read(sessionProvider), same(cached));
    expect(sessionStore.cleared, 0);
  });

  test('(c) 성공 → 최신 값으로 갱신(캐시 재기록) + 대기 기록 폐기', () async {
    await run(const Ok(fresh));

    expect(container.read(sessionProvider)?.memberName, '람(개명)', reason: '이름이 바뀌었을 수 있다');
    expect(sessionStore.writes.last.memberName, '람(개명)', reason: '다음 콜드스타트가 새 값으로 떠야 한다');
    expect(sessionStore.cleared, 0);
    expect(joinStore.clearCount, 1, reason: '이미 연결됐으니 남은 대기 기록은 폐기');
    expect(container.read(sessionProvider.notifier).lastEndReason, isNull);
  });
}

class _SpySessionStore implements SessionStore {
  final writes = <AppSession>[];
  int cleared = 0;

  @override
  Future<AppSession?> read(String uid) async => null;

  @override
  Future<void> write(AppSession s) async => writes.add(s);

  @override
  Future<void> clear() async => cleared++;
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
