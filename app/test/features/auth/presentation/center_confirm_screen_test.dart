import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/trainer_avatar.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';
import 'package:rise_member/features/auth/domain/auth_repository.dart';
import 'package:rise_member/features/auth/domain/join_request_store.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
import 'package:rise_member/features/auth/presentation/center_confirm_screen.dart';

// P2R — 승인 대기 화면에 "확인" 수단이 없던 문제(대표가 승인해도 앱은 알 방법이
// 없었고, 재요청은 대표 화면에 중복 줄을 만든다)와, 연결 여부를 모르는 상태를
// "찾지 못했어요"로 뭉뚱그리던 문제.
void main() {
  late _FakeAuthRepository repo;
  late _FakeJoinRequestStore store;
  late ProviderContainer container;
  late Map<String, StaffDto> staffMap;

  setUp(() {
    repo = _FakeAuthRepository();
    store = _FakeJoinRequestStore();
    staffMap = {};
    container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        joinRequestStoreProvider.overrideWithValue(store),
        staffMapProvider.overrideWith((ref) async => staffMap),
      ],
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const CenterConfirmScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void seedPending() {
    container.read(authViewModelProvider.notifier).restorePendingJoinRequest(
          JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime.now()),
        );
  }

  /// 번호 인증 → 자동 매칭까지 태워 "매칭된 회원" 카드가 그려지는 상태를 만든다
  /// (담당 코치 이름은 스태프 캐시에서 보강된다 — _resolveTrainerName).
  Future<void> seedMatched(String trainerId) async {
    repo.match = JoinMatch(
      member: MatchedMember(id: 'm1', name: '람', trainerId: trainerId, status: 'active'),
      needsConfirm: true,
    );
    final notifier = container.read(authViewModelProvider.notifier);
    notifier.setPhone('01012345678');
    await notifier.sendCode();
    notifier.setCode('123456');
    await notifier.verifyAndMatch();
  }

  group('승인 대기 카드', () {
    testWidgets('"연결됐는지 확인"이 재요청과 함께 놓인다 (쿨다운 중에도 확인은 열려 있다)',
        (tester) async {
      seedPending();
      await pumpScreen(tester);

      expect(find.text('연결됐는지 확인'), findsOneWidget);
      // 재요청은 30초 쿨다운 — 확인만이 지금 누를 수 있는 유일한 액션이다.
      expect(find.textContaining('다시 요청 ('), findsOneWidget);

      final check = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('연결됐는지 확인'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(check.onPressed, isNotNull);
    });

    testWidgets('아직 승인 전이면 안내만 하고 대기 상태를 유지한다', (tester) async {
      seedPending();
      await pumpScreen(tester);

      await tester.tap(find.text('연결됐는지 확인'));
      await tester.pumpAndSettle();

      expect(find.text('아직 승인 전이에요. 승인되면 바로 연결돼요'), findsOneWidget);
      expect(find.text('가입 요청을 보냈어요'), findsOneWidget); // 대기 카드 그대로
    });

    testWidgets('좁은 화면에서도 두 버튼이 넘치지 않는다 (Wrap으로 줄바꿈)', (tester) async {
      tester.view.physicalSize = const Size(320, 568); // 가장 좁은 현역 폰
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      seedPending();
      await pumpScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('연결됐는지 확인'), findsOneWidget);
      expect(find.textContaining('다시 요청'), findsOneWidget);
    });

    testWidgets('확인에 실패해도 대기 카드는 사라지지 않는다', (tester) async {
      seedPending();
      repo.sessionResult = const Err(NetworkFailure());
      await pumpScreen(tester);

      await tester.tap(find.text('연결됐는지 확인'));
      await tester.pumpAndSettle();

      expect(find.text('가입 요청을 보냈어요'), findsOneWidget);
      expect(find.text('연결이 불안정해요'), findsOneWidget);
    });
  });

  // 계약 v2.0 — 담당 코치 이름이 "공백뿐"일 때 매칭 카드가 깨지던 문제.
  // CoachLabel.resolve가 fallback은 trim하지 않아, 공백뿐인 이름이 non-null로
  // 살아남아 "담당    코치" + 빈 이니셜 아바타(TrainerAvatar는 isEmpty만 본다)가 됐다.
  group('매칭 카드의 담당 코치 표기', () {
    testWidgets('공백뿐인 이름은 미배정과 같게 — 코치 줄을 통째로 생략한다', (tester) async {
      staffMap = {'t1': const StaffDto(uid: 't1', name: '   ')};
      await seedMatched('t1');
      await pumpScreen(tester);

      expect(find.textContaining('담당'), findsNothing);
      expect(find.byType(TrainerAvatar), findsNothing);
      // 카드 자체는 그대로(회원 이름 확인이 이 화면의 본론).
      expect(find.textContaining('님으로 등록되어 있어요'), findsOneWidget);
    });

    testWidgets('앞뒤 공백이 낀 이름도 이중 공백 없이 렌더된다', (tester) async {
      staffMap = {'t1': const StaffDto(uid: 't1', name: ' 정혜린 ')};
      await seedMatched('t1');
      await pumpScreen(tester);

      expect(find.text('담당 정혜린 코치'), findsOneWidget);
      expect(find.byType(TrainerAvatar), findsOneWidget);
    });

    testWidgets('퇴사한 코치면 이름 뒤에 "(퇴사)" — 온보딩의 유일한 앵커', (tester) async {
      staffMap = {'t1': const StaffDto(uid: 't1', name: '정혜린', status: 'inactive')};
      await seedMatched('t1');
      await pumpScreen(tester);

      expect(find.text('담당 정혜린 코치 (퇴사)'), findsOneWidget);
    });
  });

  group('연결 확인 실패 상태(connectionUnknown)', () {
    testWidgets('"찾지 못했어요"라고 말하지 않고 재확인을 권한다', (tester) async {
      container
          .read(authViewModelProvider.notifier)
          .markConnectionUnknown(const NetworkFailure());
      await pumpScreen(tester);

      expect(find.text('연결 상태를 확인하지 못했어요'), findsOneWidget);
      expect(find.text('이 번호로 등록된 센터를 찾지 못했어요'), findsNothing);
      expect(find.text('연결됐는지 다시 확인'), findsOneWidget);

      // 이미 연결된 회원일 수 있으니 가입 요청을 권하지 않는다(중복 줄 방지).
      expect(find.text('우리 센터가 안 보여요'), findsNothing);
      // 그래도 탈출구는 항상 열려 있다.
      expect(find.text('다른 번호로 다시 시도'), findsOneWidget);
    });

    testWidgets('서버가 "아직"이라고 확답하면 매칭 실패 화면으로 정리된다', (tester) async {
      container
          .read(authViewModelProvider.notifier)
          .markConnectionUnknown(const NetworkFailure());
      await pumpScreen(tester);

      await tester.tap(find.text('연결됐는지 다시 확인'));
      await tester.pumpAndSettle();

      expect(find.text('이 번호로 등록된 센터를 찾지 못했어요'), findsWidgets);
      expect(find.text('우리 센터가 안 보여요'), findsOneWidget); // 가입 요청 경로 복귀
    });
  });
}

class _FakeAuthRepository implements AuthRepository {
  AppSession? session;
  Result<AppSession>? sessionResult;

  @override
  Future<Result<PhoneVerificationSession>> requestVerificationCode(
    String phone, {
    int? resendToken,
  }) async =>
      const Ok(PhoneVerificationSession(verificationId: 'vid'));

  @override
  Future<Result<void>> verifyCode({
    required String phone,
    required String verificationId,
    required String code,
  }) async =>
      const Ok(null);

  /// 기본은 "매칭 없음" — 매칭된 회원 카드를 그리려는 테스트만 채워 넣는다.
  JoinMatch match = const JoinMatch(needsConfirm: false);

  @override
  Future<Result<JoinMatch>> matchJoin(String phone) async => Ok(match);

  @override
  Future<Result<void>> confirmJoin({
    required String memberId,
    required bool confirm,
    required String phone,
  }) async =>
      const Ok(null);

  @override
  Future<Result<void>> requestJoin({required String name, required String phone}) async =>
      const Ok(null);

  @override
  Future<Result<AppSession>> loadSession() async {
    final override = sessionResult;
    if (override != null) return override;
    final s = session;
    return s == null ? const Err(MemberNotLinkedFailure()) : Ok(s);
  }

  @override
  Future<void> signOut() async {}

  /// 이 화면은 자동 진행(코드 화면 전용)과 무관 — 아무 이벤트도 흘리지 않는다.
  @override
  Stream<String?> signedInPhoneChanges() => const Stream<String?>.empty();
}

class _FakeJoinRequestStore implements JoinRequestStore {
  JoinRequestRecord? record;

  @override
  Future<JoinRequestRecord?> read() async => record;

  @override
  Future<void> save(JoinRequestRecord value) async => record = value;

  @override
  Future<void> clear() async => record = null;
}
