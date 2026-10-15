import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/brand/rise_mark.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;
import 'package:rise_member/features/auth/presentation/center_contact_provider.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';
import 'package:rise_member/features/auth/presentation/widgets/lobby_progress.dart';
import 'package:rise_member/core/widgets/trainer_avatar.dart';
import 'package:rise_member/core/config/app_config.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';
import 'package:rise_member/features/auth/domain/auth_repository.dart';
import 'package:rise_member/features/auth/domain/join_request_store.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
import 'package:rise_member/features/auth/presentation/center_confirm_screen.dart';
import 'package:rise_member/features/auth/presentation/widgets/lobby_auto_check.dart';
import 'package:rise_member/features/my/presentation/account_deletion_screen.dart';

// P2R — 승인 대기 화면에 "확인" 수단이 없던 문제(대표가 승인해도 앱은 알 방법이
// 없었고, 재요청은 대표 화면에 중복 줄을 만든다)와, 연결 여부를 모르는 상태를
// "찾지 못했어요"로 뭉뚱그리던 문제.
void main() {
  late _FakeAuthRepository repo;
  late _FakeJoinRequestStore store;
  late ProviderContainer container;
  late Map<String, StaffDto> staffMap;

  /// 기본 하네스에 오버라이드를 더해 컨테이너를 다시 만든다(센터 카드·자동 확인 테스트용).
  void rebuildContainer(List<Override> extra, {Duration? autoCheckInterval}) {
    container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        joinRequestStoreProvider.overrideWithValue(store),
        staffMapProvider.overrideWith((ref) async => staffMap),
        // 자동 확인은 끈다(P69 H1) — 주기 타이머가 살아 있으면 `pumpAndSettle`이 영원히 settle되지
        // 않는다. 자동 확인 자체는 `lobby_auto_check_test`가 따로 고정한다.
        lobbyAutoCheckIntervalProvider.overrideWithValue(autoCheckInterval),
        ...extra,
      ],
    );
  }

  setUp(() {
    repo = _FakeAuthRepository();
    store = _FakeJoinRequestStore();
    staffMap = {};
    rebuildContainer(const []);
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

  // ── 센터 선택(계약 v2.33) ────────────────────────────────────────────────
  //
  // **P55의 "앱에서 센터를 고르지 않는다"가 여기서 갱신된다.** 그 결정의 전제는 센터가
  // 하나뿐이라 고를 것이 없다는 것이었다(설계04 §4). 센터가 둘 이상이 되는 순간 전제가
  // 사라지고, 고르지 않으면 **모든 요청이 1호점 큐로 가서 2호점은 신규 회원을 영영 못 받는다.**
  // 그래서 "고를 것이 2곳 이상일 때만" 선택을 묻는다 — 없는 기능을 약속하지 않는다는 규약은
  // 그대로다(1곳이면 선택 UI 자체가 없다).
  Future<void> openJoinSheet(WidgetTester tester) async {
    await tester.tap(find.text('가입 요청 보내기').last);
    await tester.pumpAndSettle();
  }

  group('센터 선택 (v2.33)', () {
    testWidgets('센터가 1곳이면 선택을 묻지 않는다 — 고를 것이 없는 선택은 방해다', (tester) async {
      repo.joinCenters = const [CenterDirectory(id: 'rise', name: '라이즈 컨디셔닝 센터')];
      await pumpScreen(tester);
      await openJoinSheet(tester);

      expect(find.text('어느 센터에 요청할까요?'), findsNothing);

      await tester.enterText(find.byType(TextField).last, '김신규');
      await tester.tap(find.text('가입 요청 보내기').last);
      await tester.pumpAndSettle();
      // 센터를 비워 보낸다 → 서버가 기본 센터로 폴백(종전 동작 그대로).
      expect(repo.lastRequestedCenterId, '');
    });

    testWidgets('센터가 2곳 이상이면 고른 센터로 요청이 간다', (tester) async {
      repo.joinCenters = const [
        CenterDirectory(id: 'gangnam-2', name: '라이즈 강남 2호점', address: '서울 강남구'),
        CenterDirectory(id: 'rise', name: '라이즈 컨디셔닝 센터'),
      ];
      await pumpScreen(tester);
      await openJoinSheet(tester);

      expect(find.text('어느 센터에 요청할까요?'), findsOneWidget);
      expect(find.text('라이즈 강남 2호점'), findsOneWidget);

      await tester.tap(find.text('라이즈 강남 2호점'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '김신규');
      await tester.tap(find.text('가입 요청 보내기').last);
      await tester.pumpAndSettle();

      expect(repo.lastRequestedCenterId, 'gangnam-2');
    });

    testWidgets('고를 수 있는데 안 고르면 보내지 않는다 — 조용히 기본 센터로 가면 안 된다', (tester) async {
      repo.joinCenters = const [
        CenterDirectory(id: 'gangnam-2', name: '라이즈 강남 2호점'),
        CenterDirectory(id: 'rise', name: '라이즈 컨디셔닝 센터'),
      ];
      await pumpScreen(tester);
      await openJoinSheet(tester);

      await tester.enterText(find.byType(TextField).last, '김신규');
      await tester.tap(find.text('가입 요청 보내기').last);
      await tester.pumpAndSettle();

      expect(find.text('센터를 선택해주세요'), findsOneWidget);
      expect(repo.lastRequestedCenterId, isNull); // 요청 자체가 나가지 않았다
    });

    testWidgets('상호가 빈 센터도 고를 수 있다 — 목록에서 빠지면 그 센터는 신규 회원을 못 받는다',
        (tester) async {
      repo.joinCenters = const [
        CenterDirectory(id: 'gangnam-2', name: '라이즈 강남 2호점'),
        CenterDirectory(id: 'rise', name: ''), // 상호 미등록(프로덕션 라이즈의 실제 상태)
      ];
      await pumpScreen(tester);
      await openJoinSheet(tester);

      // 앱 기본 라벨로 그린다.
      expect(find.text(AppConfig.centerFullName), findsWidgets);
      await tester.tap(find.text(AppConfig.centerFullName).last);
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '김신규');
      await tester.tap(find.text('가입 요청 보내기').last);
      await tester.pumpAndSettle();

      expect(repo.lastRequestedCenterId, 'rise');
    });
  });

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

  group('승인 대기 — 확인 상태 줄과 재요청 (P69 H2로 대기 카드가 스텝퍼·상태 줄에 흡수됨)', () {
    testWidgets('"지금 확인"이 재요청과 함께 놓인다 (쿨다운 중에도 확인은 열려 있다)',
        (tester) async {
      seedPending();
      await pumpScreen(tester);

      expect(find.text('지금 확인'), findsOneWidget);
      // 재요청은 30초 쿨다운 — 확인만이 지금 누를 수 있는 유일한 액션이다.
      expect(find.textContaining('다시 요청 ('), findsOneWidget);

      final check = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('지금 확인'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(check.onPressed, isNotNull);
    });

    testWidgets('아직 승인 전이면 안내만 하고 대기 상태를 유지한다', (tester) async {
      seedPending();
      await pumpScreen(tester);

      await tester.tap(find.text('지금 확인'));
      await tester.pumpAndSettle();

      // "승인되면 바로 연결돼요"는 뺐다(P69 C1) — 확인 주기만큼 늦는다.
      expect(find.text('아직 승인 전이에요'), findsOneWidget);
      expect(find.text('센터 승인 기다리는 중'), findsOneWidget); // 스텝퍼 그대로
    });

    testWidgets('좁은 화면에서도 두 버튼이 넘치지 않는다 (Wrap으로 줄바꿈)', (tester) async {
      tester.view.physicalSize = const Size(320, 568); // 가장 좁은 현역 폰
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      seedPending();
      await pumpScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('지금 확인'), findsOneWidget);
      expect(find.textContaining('다시 요청'), findsOneWidget);
    });

    testWidgets('확인에 실패해도 대기 카드는 사라지지 않는다', (tester) async {
      seedPending();
      repo.sessionResult = const Err(NetworkFailure());
      await pumpScreen(tester);

      await tester.tap(find.text('지금 확인'));
      await tester.pumpAndSettle();

      expect(find.text('센터 승인 기다리는 중'), findsOneWidget);
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

      expect(find.text('센터에 연결됐는지 확인하지 못했어요'), findsOneWidget);
      // notFound 화면(제목)을 그리지 않는다 — 서버가 확답한 결론이 아니다.
      expect(find.text('아직 연결된 센터가 없어요'), findsNothing);
      expect(find.text('연결됐는지 다시 확인'), findsOneWidget);

      // 이미 연결된 회원일 수 있으니 가입 요청을 권하지 않는다(중복 줄 방지).
      expect(find.text('가입 요청 보내기'), findsNothing);
      // 그래도 탈출구는 항상 열려 있다.
      expect(find.text('번호 다시 인증하기'), findsOneWidget);
    });

    testWidgets('서버가 "아직"이라고 확답하면 매칭 실패 화면으로 정리된다', (tester) async {
      container
          .read(authViewModelProvider.notifier)
          .markConnectionUnknown(const NetworkFailure());
      await pumpScreen(tester);

      await tester.tap(find.text('연결됐는지 다시 확인'));
      await tester.pumpAndSettle();

      expect(find.text('아직 연결된 센터가 없어요'), findsOneWidget); // notFound 제목
      expect(find.text('가입 요청 보내기'), findsOneWidget); // 가입 요청 경로 복귀
    });
  });

  group('한 화면이 두 상태를 동시에 말하지 않는다 (P55 — 람이 실사용자 화면으로 가져온 모순)', () {
    // 종전 구조: 제목은 고정 문자열, 부제는 stage, **상단 카드는 else 체인**
    // (`member != null` → `matchDeclined` → `connectionUnknown` → else `_NotFoundCard`),
    // 하단 카드는 `joinRequestedAt`. 판별자가 넷이라 "요청 대기 중"이 else 폴백에
    // 걸려 **"찾지 못했어요" 경고와 "승인 대기 중" 카드가 함께** 떴다.
    // 게다가 그 경고 문구는 "아래에서 센터를 찾아 가입 요청해보세요"인데, 그것이
    // 가리키는 아래 카드는 **하필 대기 중일 때만 사라진다**.
    //
    // 지금은 `switch (stage)` 하나가 제목·부제·본문을 함께 정한다. 아래 두 테스트가
    // 그 불변식을 지킨다 — 누군가 else 체인을 되살리면 여기서 터진다.

    testWidgets('요청 대기 중에는 "찾지 못했어요" 안내가 함께 뜨지 않는다', (tester) async {
      seedPending();
      await pumpScreen(tester);

      expect(find.text('가입 요청을 보냈어요'), findsOneWidget); // 제목
      expect(find.text('센터 승인 기다리는 중'), findsOneWidget); // 대기 카드
      // 빈 상태의 연락 카드 힌트(notFound 전용)가 대기 화면에 섞이지 않는다.
      expect(
        find.textContaining('아직 등록 전이면 자동 연결이 안 돼요'),
        findsNothing,
        reason: '빈 상태 안내가 대기 화면에 섞였다 — else 폴백이 되살아났다',
      );
    });

    testWidgets('빈 상태에서는 대기 카드가 뜨지 않는다 — 반대 방향도 고정', (tester) async {
      await pumpScreen(tester);

      expect(find.text('아직 연결된 센터가 없어요'), findsOneWidget); // 제목
      expect(find.text('센터 승인 기다리는 중'), findsNothing);
    });

    // 없는 기능을 약속하지 않는다 — 삭제한 문구가 **6단계 어디서도** 안 뜬다.
    // ① "센터 선택" — 고를 목록이 없다(앱에 센터 목록 API 호출이 0건)
    // ② "센터를 찾아" — 검색·목록이 어느 stage에도 없다
    // ③ "여러 센터 이용 가능 — 홈 상단에서 전환" — 홈 전환 UI는 P54에서 제거됐고
    //    서버 UserIndex는 uid당 1건이라 다센터 소속이 구조적으로 불가능하다
    // ④ "달라서 자동 연결이 안 됐어요" — 원인 단정. 서버가 아는 것은 번호로 회원을 못
    //    찾았다는 사실뿐이고 등록 전일 수도 있다(P63)
    // ⑤ "앱에 등록된 번호" — 주어 오류. 다른 것은 센터(어드민)에 등록된 번호다(P63)
    // ⑥ "다른 센터" — v1은 단일 센터라 그 선택지가 없다(계약 v2.27 center_id 규약, P63).
    //    종전 검사어 '다른 센터로'는 matched 카드의 '제가 아니거나 다른 센터예요'를 놓쳤고
    //    matched 자체를 검사하지 않았다(P63 검증 반영 — 6단계 전부).
    // ⑦~⑨ (P69 C1) — "자동으로 연결"·"바로 연결"·"바로 홈": 푸시가 없고 확인은 주기·앱 재개에
    //    걸린다. 자동 확인은 상태 줄이 자기 자리에서 말하되 "바로"는 어디서도 약속하지 않는다.
    // ⑩ "언제든" — 예약은 회원권이 있어야 한다(미리보기 M3의 부사 금지).
    const lies = [
      '센터 선택',
      '아래에서 센터를 찾아',
      '홈 상단에서 전환',
      '달라서 자동 연결이 안 됐어요',
      '앱에 등록된 번호',
      '다른 센터',
      '자동으로 연결',
      '바로 연결',
      '바로 홈',
      '언제든',
    ];
    // stage마다 테스트 하나 — 한 테스트 안에서 seed를 누적하면 match·serverJoinStatus가
    // 겹쳐 declined·matched가 만들어지지 않는다(centerConfirmStage 우선순위).
    final lieSeeds = <String, Future<void> Function()>{
      'notFound': () async {},
      'pendingApproval': () async => seedPending(),
      'rejected': () async =>
          container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected'),
      'connectionUnknown': () async => container
          .read(authViewModelProvider.notifier)
          .markConnectionUnknown(const NetworkFailure()),
      'matched': () => seedMatched('t1'),
      'declined': () async {
        await seedMatched('t1');
        await container.read(authViewModelProvider.notifier).confirmMatch(false);
      },
    };
    for (final entry in lieSeeds.entries) {
      testWidgets('없는 기능을 약속하지 않는다 — ${entry.key} stage', (tester) async {
        await entry.value();
        await pumpScreen(tester);
        for (final lie in lies) {
          expect(
            find.textContaining(lie),
            findsNothing,
            reason: '${entry.key} — "$lie": 앱이 못 하는 것을 약속하고 있다',
          );
        }
      });
    }

    testWidgets('matched 카드 제목은 "제가 아니에요" — 부제(가입 요청)는 그대로', (tester) async {
      await seedMatched('t1');
      await pumpScreen(tester);

      expect(find.text('제가 아니에요'), findsOneWidget);
      expect(find.text('가입 요청을 따로 보낼 수 있어요'), findsOneWidget);
    });

    // P65 후속 3(P73): 매칭 카드의 상호는 **매칭 응답이 실은 그 회원의 센터**다. 종전엔 무인증
    // `GET /v1/public/center`(기본 센터 고정)만 읽어 2호점 회원에게 1호점 상호를 보여줬다.
    testWidgets('matched 카드 상호는 매칭 응답의 센터 — 기본 센터 상호를 찍지 않는다', (tester) async {
      rebuildContainer([
        centerContactProvider.overrideWith(
          (ref, _) async => const CenterContact(name: '라이즈 컨디셔닝 센터(1호점)'),
        ),
      ]);
      repo.match = const JoinMatch(
        member: MatchedMember(id: 'm2', name: '람', trainerId: 't1', status: 'active'),
        needsConfirm: true,
        centerName: '라이즈 2호점',
      );
      final notifier = container.read(authViewModelProvider.notifier);
      notifier.setPhone('01012345678');
      await notifier.sendCode();
      notifier.setCode('123456');
      await notifier.verifyAndMatch();
      await pumpScreen(tester);

      expect(find.text('라이즈 2호점'), findsOneWidget);
      expect(find.text('라이즈 컨디셔닝 센터(1호점)'), findsNothing, reason: '2호점 회원 카드에 1호점 상호가 찍혔다');
    });

    testWidgets('매칭 응답에 센터가 없으면(구서버·미등록) 종전대로 기본 센터 상호', (tester) async {
      rebuildContainer([
        centerContactProvider.overrideWith(
          (ref, _) async => const CenterContact(name: '라이즈 컨디셔닝 센터(1호점)'),
        ),
      ]);
      await seedMatched('t1');
      await pumpScreen(tester);

      expect(find.text('라이즈 컨디셔닝 센터(1호점)'), findsOneWidget);
    });
  });

  group('서버가 대기 상태의 주인이다 (계약 v2.27)', () {
    // 종전엔 "요청을 보냈다"는 사실이 기기 SharedPreferences에만 있었다. 기기를
    // 바꾸거나 앱을 지웠다 깔면 근거가 사라져 화면이 "요청한 적 없음"으로 떨어졌고,
    // 사용자는 같은 요청을 또 보냈다 — 그 중복이 대표 어드민을 죽이던 재료다.

    testWidgets('로컬 기록이 없어도 서버가 pending이면 대기 화면이다 — 기기 변경 시나리오', (tester) async {
      // **seedPending()을 부르지 않는다** — 기기를 바꿔 로컬 근거가 없는 상태.
      // **타임스탬프는 주지 않는다** — 로컬 기록만 보는 계산이라면 여기서
      // 빈 상태로 떨어진다. 서버 상태 단독으로 화면이 서는지를 격리해 잰다.
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('pending');
      await pumpScreen(tester);

      expect(find.text('가입 요청을 보냈어요'), findsOneWidget); // 제목
      expect(find.text('센터 승인 기다리는 중'), findsOneWidget);
      expect(
        find.text('아직 연결된 센터가 없어요'),
        findsNothing,
        reason: '로컬 기록만 보던 종전 계산이면 여기서 빈 상태로 떨어져 중복 요청이 나갔다',
      );
    });

    testWidgets('서버가 rejected면 대기가 아니라 결론 화면이다', (tester) async {
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected');
      await pumpScreen(tester);

      expect(find.text('센터에서 연결하지 않았어요'), findsOneWidget);
      expect(
        find.text('센터 승인 기다리는 중'),
        findsNothing,
        reason: '거절인데 대기 카드를 보여주면 오지 않을 승인을 영원히 기다린다',
      );
    });

    testWidgets('거절이 대기보다 우선한다 — 로컬에 대기 기록이 남아 있어도', (tester) async {
      seedPending();
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected');
      await pumpScreen(tester);

      expect(find.text('센터에서 연결하지 않았어요'), findsOneWidget);
      expect(find.text('센터 승인 기다리는 중'), findsNothing);
    });
  });

  group('대기실 하단 — 약관·방침 링크와 계정 삭제 문 (P56 A1·B5)', () {
    // A1: `AccountDeletionScreen` 진입점이 셸 안 마이 탭 하나뿐이라, 가입 요청 시트에
    // 이름을 직접 적어 서버에 넘긴 사람이 그것을 지울 문이 앱 안에 없었다(개인정보보호법
    // §36). 서버는 P55에서 열렸다(`deleteUnlinkedAccount`).
    // B5: 이름·전화번호를 수집하는 로그인 전 화면에 약관·방침 링크가 0건이었다.
    // 뮤테이션: `_LobbyFooterLinks`를 빼면 아래 전부가 죽는다.
    const footer = ['이용약관', '개인정보처리방침', '계정 삭제'];

    Future<void> seedDeclined() async {
      await seedMatched('t1');
      await container.read(authViewModelProvider.notifier).confirmMatch(false);
    }

    // stage마다 테스트 하나 — setUp이 keepAlive 뷰모델을 새로 만든다(한 테스트 안에서
    // 컨테이너를 갈아끼우면 마운트된 ProviderScope와 어긋난다).
    final seeds = <String, Future<void> Function()>{
      'notFound': () async {},
      'pendingApproval': () async => seedPending(),
      'rejected': () async =>
          container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected'),
      'connectionUnknown': () async => container
          .read(authViewModelProvider.notifier)
          .markConnectionUnknown(const NetworkFailure()),
      'matched': () => seedMatched('t1'),
      'declined': seedDeclined,
    };
    for (final entry in seeds.entries) {
      testWidgets('${entry.key} stage에서 세 링크가 보인다', (tester) async {
        await entry.value();
        await pumpScreen(tester);
        for (final label in footer) {
          expect(find.text(label), findsOneWidget, reason: '${entry.key} — "$label" 링크가 없다');
        }
      });
    }

    testWidgets('"계정 삭제"를 누르면 대기실 계정용 확인 화면이 열린다 — 회원 고지가 아니다', (tester) async {
      await pumpScreen(tester); // notFound

      await tester.tap(find.text('계정 삭제'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountDeletionScreen), findsOneWidget);
      // 이 계정에 실제로 있는 것만 고지한다. 가입 요청은 **모른다** — 코드 인증 직후의
      // 대기실은 /v1/me를 부른 적이 없다(기기를 바꿔 로그인한 사람은 서버에 pending을 둔 채
      // 여기 선다). "없다"고 단정하면 과소 고지, "보냈다"고 단정하면 과잉 열거 — "있다면".
      expect(find.text('보낸 가입 요청이 있다면 그 요청 (이름·전화번호)'), findsOneWidget);
      expect(find.text('보낸 가입 요청 (이름·전화번호)'), findsNothing);
      expect(find.text('앱 로그인 계정 (인증한 전화번호)'), findsOneWidget);
      // 회원 데이터 고지는 없는 것에 대한 고지다 — 뜨면 안 된다.
      expect(find.text('체형사진(원본 파일까지 삭제)'), findsNothing);
      expect(find.text('법에 따라 보관되는 정보'), findsNothing);
      expect(find.textContaining('남은 회차'), findsNothing);
      // 진입만으로는 아무 일도 일어나지 않는다.
      expect(find.text('삭제되는 정보'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('연결 여부를 모르는 상태에서는 회원 쪽(최악) 고지를 그대로 보여주고 그 사실을 밝힌다', (tester) async {
      // 이미 연결된 회원이 네트워크 실패로 대기실에 선 것일 수 있다 — 그때 삭제하면
      // 서버는 회원 경로(전체 파기)를 돈다. "가입 요청만 지워져요"는 거짓 고지가 된다.
      container.read(authViewModelProvider.notifier).markConnectionUnknown(const NetworkFailure());
      await pumpScreen(tester);

      await tester.tap(find.text('계정 삭제'));
      await tester.pumpAndSettle();

      expect(find.textContaining('연결 상태를 확인하지 못했어요'), findsWidgets);
      expect(find.text('체형사진(원본 파일까지 삭제)'), findsOneWidget);
      expect(find.text('법에 따라 보관되는 정보'), findsOneWidget);
      expect(find.textContaining('남은 회차를 확인하지 못했어요'), findsOneWidget);
    });

    testWidgets('하단 링크의 터치 영역은 44dp다', (tester) async {
      await pumpScreen(tester);
      for (final label in [...footer, '번호 다시 인증하기']) {
        final hit = tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(GestureDetector)).first,
        );
        expect(hit.height, greaterThanOrEqualTo(44), reason: '"$label" 히트 높이 ${hit.height}');
      }
    });

    testWidgets('좁은 화면(320×568)에서 링크가 더해져도 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpScreen(tester); // notFound — 버튼 + 링크 + 연락 카드
      expect(tester.takeException(), isNull);
      expect(find.text('계정 삭제'), findsOneWidget);
    });
  });

  group('가입 요청 시트 — 제출 중에는 닫히지 않는다 (P56 M1)', () {
    // 요청이 날아가는 동안 시트를 쓸어 내리면 409("이미 보낸 요청이 있어요")도 네트워크
    // 실패도 갈 곳이 없고, 회원은 또 보낸다. 뮤테이션: `_showJoinRequestSheet`의
    // `submitting:` 인자를 빼면 죽는다.
    testWidgets('쓸기·스크림 탭에 시트가 남고, 실패가 시트 안에 뜬다', (tester) async {
      repo.requestJoinGate = Completer<Result<void>>();
      await pumpScreen(tester); // notFound — 주 버튼이 "가입 요청 보내기"

      await tester.tap(find.text('가입 요청 보내기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '람');
      // 시트의 버튼은 화면 CTA와 라벨이 같다 — 나중에 그려진 쪽(시트)이 last.
      await tester.tap(find.text('가입 요청 보내기').last);
      await tester.pump();
      expect(find.text('요청 중…'), findsOneWidget);

      // 스텝퍼의 "가입 요청"(notFound 현재 단계)과 시트 제목이 같다 — 나중에 그려진 시트가 last.
      await tester.fling(find.text('가입 요청').last, const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(find.text('요청 중…'), findsOneWidget, reason: '제출 중 쓸기로 시트가 닫혔다');

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('요청 중…'), findsOneWidget, reason: '제출 중 스크림 탭으로 시트가 닫혔다');

      repo.requestJoinGate!.complete(const Err(NetworkFailure()));
      await tester.pumpAndSettle();
      expect(find.text('연결이 불안정해요'), findsOneWidget, reason: '실패가 회원에게 닿지 않았다');
      // 시트 뒤 화면에는 남기지 않는다(종전 규약 그대로).
      expect(find.text('연결이 불안정해요'), findsOneWidget);
    });
  });

  group('거절 이후 경로 (P56 — P55가 없앤 중복 큐가 되살아나던 자리)', () {
    testWidgets('거절 화면에서 재요청하면 화면이 대기로 바뀐다', (tester) async {
      // `centerConfirmStage`는 rejected를 pending보다 **먼저** 판정한다. 요청 성공이
      // `serverJoinStatus`를 안 세우면 화면이 한 픽셀도 안 바뀌는데, 서버는 이전 요청이
      // rejected면 409를 내지 않아 **요청은 실제로 접수된다** — 회원이 반복하면 대표
      // 큐에 진짜로 여러 줄이 쌓인다.
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected');
      await pumpScreen(tester);
      expect(find.text('센터에서 연결하지 않았어요'), findsOneWidget);

      await container.read(authViewModelProvider.notifier).requestJoin('람');
      await tester.pumpAndSettle();

      expect(find.text('가입 요청을 보냈어요'), findsOneWidget);
      expect(
        find.text('센터에서 연결하지 않았어요'),
        findsNothing,
        reason: '요청이 접수됐는데 화면이 거절에 머무르면 회원은 계속 다시 누른다',
      );
    });
  });

  group('계정 삭제 고지는 가입 요청의 흔적(JoinRequestTrace)을 따른다 (P63)', () {
    // 서버 `deleteUnlinkedAccount` ⑤는 그 uid의 요청 문서를 상태 무관 전부 지운다. 문서의
    // 모양이 상태마다 다르다 — pending은 이름·번호 원본, rejected는 센터가 비운 껍데기
    // ({상태, 요청 시각}). 고지는 지워질 문서의 모양대로 말해야 한다. 뮤테이션:
    // `AuthState.joinRequestTrace`가 항상 unknown을 돌려주면 아래 두 테스트가 죽는다.
    Future<void> openDeletion(WidgetTester tester) async {
      await tester.tap(find.text('계정 삭제'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountDeletionScreen), findsOneWidget);
    }

    testWidgets('서버가 pending이라 답한 상태면 "보낸 가입 요청" 행이 단정형으로 뜬다', (tester) async {
      // 서버 확답(requestJoin 성공 응답·/v1/me·콜드스타트 반영)만 pending이다(P63 검증 반영).
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('pending');
      await pumpScreen(tester);
      await openDeletion(tester);

      expect(find.text('보낸 가입 요청 (이름·전화번호)'), findsOneWidget);
      expect(find.text('보낸 가입 요청이 있다면 그 요청 (이름·전화번호)'), findsNothing);
      expect(find.text('앱 로그인 계정 (인증한 전화번호)'), findsOneWidget);
    });

    testWidgets('로컬 기록만 있는 대기 화면은 "있다면"으로 헤지한다 — 그 사이 거절·삭제됐을 수 있다', (tester) async {
      // 코드 인증 직후 경로는 서버를 묻지 않는다. 화면은 로컬 기록으로 대기 카드를 세우지만
      // 삭제 고지가 같은 근거로 "보낸 가입 요청 (이름·전화번호)"를 단정하면, 센터가 이미
      // 거절해 이름·번호를 비운 요청(v2.28)을 두고 지워질 이름이 있는 것처럼 말한다.
      // 뮤테이션: joinRequestTrace가 로컬 기록(joinRequestedAt)만으로 pending을 돌려주면 죽는다.
      seedPending();
      await pumpScreen(tester);
      expect(find.text('센터 승인 기다리는 중'), findsOneWidget); // 화면은 대기
      await openDeletion(tester);

      expect(find.text('보낸 가입 요청이 있다면 그 요청 (이름·전화번호)'), findsOneWidget);
      expect(find.text('보낸 가입 요청 (이름·전화번호)'), findsNothing);
    });

    testWidgets('matched에서 계정 삭제 → 회원 고지 + 배너 (재인증한 기존 회원일 수 있다)', (tester) async {
      // 이미 연결된 회원이 기기 변경·'번호 다시 인증하기'로 재인증하면 같은 uid로 matched에
      // 다시 서고, principal에 member_id가 있어 서버는 회원 경로(전체 파기 + 5년 보존)를 돈다.
      // unlinked 고지("인증 계정과 가입 요청만")는 그 사람에게 과소 고지다.
      // 뮤테이션: `_openAccountDeletion`이 matched를 unlinked로 열면 여기서 죽는다.
      await seedMatched('t1');
      await pumpScreen(tester);
      await openDeletion(tester);

      expect(find.textContaining('이 번호로 등록된 회원이 있어요'), findsOneWidget);
      expect(find.textContaining('이미 이 계정에 연결돼 있었다면 아래 내용대로 모두 삭제돼요'), findsOneWidget);
      expect(find.textContaining('연결 상태를 확인하지 못했어요'), findsNothing, reason: '확인 실패가 아니라 확인 전이다');
      // 회원 쪽(최악) 고지 그대로.
      expect(find.text('체형사진(원본 파일까지 삭제)'), findsOneWidget);
      expect(find.text('법에 따라 보관되는 정보'), findsOneWidget);
      expect(find.textContaining('남은 회차를 확인하지 못했어요'), findsOneWidget);
      // 미연결 고지가 아니다.
      expect(find.text('앱 로그인 계정 (인증한 전화번호)'), findsNothing);
      expect(find.text('여기서 지워지지 않는 정보'), findsNothing);
    });

    testWidgets('거절된 요청(rejected)은 이름·번호가 없다 — "가입 요청 기록"으로 정확히 말한다', (tester) async {
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected');
      await pumpScreen(tester);
      await openDeletion(tester);

      expect(find.text('가입 요청 기록 (처리 상태·요청 시각)'), findsOneWidget);
      expect(
        find.text('보낸 가입 요청 (이름·전화번호)'),
        findsNothing,
        reason: '거절 시 서버가 이름·번호를 이미 비웠다(v2.28) — 지워질 이름이 있는 것처럼 말했다',
      );
    });
  });

  group('대기실 문구 표 — 사실(제목·부제) / 도움 받을 곳(연락 카드 힌트) (P63)', () {
    // 각 stage에서 역할을 셋으로 고정한다: 제목+부제 = 서버가 아는 사실 / CTA = 할 수 있는
    // 일 / 연락 카드 힌트 = 왜 데스크가 도움이 되는지(원인 가설은 여기서만, 헤지해서).
    // 종전엔 notFound가 "등록 번호가 다를 수 있다"를 세 자리(부제·경고 카드·연락 카드)에서
    // 말했고, 부제는 "달라서"로 원인을 단정했다.
    //
    // 뮤테이션: `_CenterContactCard`가 [hint]를 무시하고 고정 문장을 그리면 stage별 힌트
    // 단언이 죽는다.
    // P63 검증 반영: notFound는 "고치거나 등록한 뒤" + 재인증 뒤 실제 화면(이름 확인 한 번),
    // declined는 고친 뒤의 재인증 단계까지, pending은 전화·주소가 비어도 참인 문장.
    const notFoundHint =
        '센터에 등록된 번호가 다르거나 아직 등록 전이면 자동 연결이 안 돼요. '
        '센터 데스크에 이 번호를 알려주면 등록·수정해 드려요 — 그 뒤 이 화면에서 [지금 확인]을 '
        '누르면 이름 확인 한 번으로 연결돼요.';
    const rejectedHint = '데스크에 확인한 뒤 다시 요청할 수 있어요.';
    const declinedHint =
        '내 번호가 다른 회원에게 등록된 것 같다면 데스크에서 고쳐드려요 — '
        '고친 뒤 같은 번호를 다시 인증하면 연결돼요. '
        '아직 회원이 아니라면 아래에서 가입 요청할 수 있어요.';
    const pendingHint = '승인이 늦으면 센터 데스크에 문의해주세요.';

    Future<void> seedDeclined() async {
      await seedMatched('t1');
      await container.read(authViewModelProvider.notifier).confirmMatch(false);
    }

    testWidgets('notFound — 부제는 사실만, 원인 가설은 힌트에서 헤지, 경고 카드 없음', (tester) async {
      await pumpScreen(tester);

      expect(find.text('아직 연결된 센터가 없어요'), findsOneWidget);
      expect(find.text('인증한 번호로 등록된 회원을 찾지 못했어요'), findsOneWidget);
      expect(find.text(notFoundHint), findsOneWidget);
      expect(find.text('가입 요청 보내기'), findsOneWidget);
      expect(find.text('번호 다시 인증하기'), findsOneWidget);
      // 다른 stage의 힌트가 섞이지 않는다.
      expect(find.text(rejectedHint), findsNothing);
      expect(find.text(declinedHint), findsNothing);
      expect(find.text(pendingHint), findsNothing);
    });

    testWidgets('rejected — "다른 센터로"라 쓰지 않고 번호 가설만 부제로', (tester) async {
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected');
      await pumpScreen(tester);

      expect(find.text('센터에서 연결하지 않았어요'), findsOneWidget);
      expect(find.text('요청에 적힌 번호가 등록된 번호와 다를 수 있어요'), findsOneWidget);
      expect(find.text(rejectedHint), findsOneWidget);
      // P69 C2 — 서버가 rejected 뒤 재요청을 허용한다(v2.27). 첫 요청과 같은 라벨이면 회원은
      // 자기 요청이 사라진 줄 안다.
      expect(find.text('가입 요청 다시 보내기'), findsOneWidget);
      expect(find.text('가입 요청 보내기'), findsNothing);
    });

    testWidgets('declined — 제목은 "취소"가 아니라 "연결하지 않았어요"', (tester) async {
      await seedDeclined();
      await pumpScreen(tester);

      expect(find.text('이 번호로는 연결하지 않았어요'), findsOneWidget);
      expect(find.text('연결을 취소했어요'), findsNothing, reason: '취소할 연결이 없었다');
      expect(find.text('이 번호로 찾은 회원이 본인이 아니라고 하셨어요'), findsOneWidget);
      expect(find.text(declinedHint), findsOneWidget);
      expect(find.text('가입 요청 보내기'), findsOneWidget);
    });

    testWidgets('pendingApproval — 부제는 "승인하면"(자동 아님), 스텝퍼·상태 줄이 대기 카드를 대신한다', (tester) async {
      seedPending();
      await pumpScreen(tester);

      expect(find.text('가입 요청을 보냈어요'), findsOneWidget);
      // P69 C1 — "센터에서 확인하면 자동으로 연결돼요"는 거짓이었다(푸시·폴링이 없었다).
      expect(find.text('센터가 승인하면 연결돼요'), findsOneWidget);
      expect(find.textContaining('자동으로 연결'), findsNothing);
      // 종전 대기 카드 문장은 사라졌다 — 그 정보는 스텝퍼와 상태 줄이 말한다.
      expect(find.text('승인을 기다리는 중'), findsNothing);
      expect(find.text('승인됐는지 아래 버튼으로 확인할 수 있어요.'), findsNothing);
      expect(find.text('센터 승인 기다리는 중'), findsOneWidget);
      expect(find.text('아직 확인 전'), findsOneWidget);
      expect(find.text('승인 대기 중'), findsNothing, reason: '제목과 같은 말을 배지로 또 했다');
      expect(find.text(pendingHint), findsOneWidget);
      // 쿨다운 문장은 버튼 라벨이 실시간으로 말한다 — 정적 문장은 30초 뒤 거짓이 된다.
      expect(find.textContaining('다시 요청'), findsOneWidget);
      // 안내문의 "바로"도 뺐다.
      expect(find.text('앱을 껐다 켜도 이 화면으로 돌아와요. 승인되면 다음에 앱을 열 때 홈으로 들어가요.'), findsOneWidget);
    });

    testWidgets('connectionUnknown — 카드는 안심 문장 하나, 제목·부제를 되풀이하지 않는다', (tester) async {
      container.read(authViewModelProvider.notifier).markConnectionUnknown(const NetworkFailure());
      await pumpScreen(tester);

      expect(find.text('센터에 연결됐는지 확인하지 못했어요'), findsOneWidget);
      expect(find.text('잠시 뒤 다시 확인해주세요'), findsOneWidget);
      expect(find.text('이미 연결된 회원이라면 다시 확인했을 때 그대로 홈으로 들어가요.'), findsOneWidget);
      expect(find.textContaining('연결 상태를 불러오지 못했어요'), findsNothing);
      expect(find.text('연결이 불안정해요'), findsOneWidget); // 사유는 인라인 error 한 곳
    });

    testWidgets('matched — 무변경(이름 강조가 목적인 약한 중복은 허용)', (tester) async {
      await seedMatched('t1');
      await pumpScreen(tester);

      expect(find.text('센터를 찾았어요'), findsOneWidget);
      expect(find.text('전화번호로 등록된 회원 정보를 확인했어요'), findsOneWidget);
      expect(find.textContaining('님으로 등록되어 있어요'), findsOneWidget);
    });

    testWidgets('삭제한 카드 문장 3종이 어느 stage에서도 뜨지 않는다', (tester) async {
      // 각각 _NotFoundCard·_DeclinedCard·_RejectedCard의 고유 문장이었다 — 전부 제목·부제·
      // 연락 카드·CTA의 반복이라 카드째 지웠다.
      const removed = [
        '센터에 등록된 번호와 인증한 번호가 다르거나, 아직 등록 전일 수 있어요.',
        '확인했어요. 번호가 잘못 등록됐다면',
        '센터에서 이 요청을 연결하지 않았어요.',
      ];
      final seeds = <String, Future<void> Function()>{
        'notFound': () async {},
        'pendingApproval': () async => seedPending(),
        'rejected': () async =>
            container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected'),
        'connectionUnknown': () async => container
            .read(authViewModelProvider.notifier)
            .markConnectionUnknown(const NetworkFailure()),
      };
      for (final entry in seeds.entries) {
        await entry.value();
        await pumpScreen(tester);
        for (final sentence in removed) {
          expect(find.textContaining(sentence), findsNothing, reason: '${entry.key} — "$sentence"');
        }
      }
    });
  });

  group('같은 문장을 두 번 그리지 않는다 (P63 — 중복 재발 방지의 구조적 못)', () {
    // 화면의 모든 Text 데이터를 모아 같은 문자열이 둘 이상 없음을 본다. 구분자(' · ')와
    // 빈 문자열은 문장이 아니라 제외한다. 가입 요청 시트는 열지 않는다 — 시트 버튼 라벨은
    // 화면 CTA와 같고(P56 M1 테스트가 그 중복을 다룬다) 그건 이 테스트의 대상이 아니다.
    List<String> visibleSentences(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '·')
        .toList();

    final seeds = <String, Future<void> Function()>{
      'notFound': () async {},
      'pendingApproval': () async => seedPending(),
      'rejected': () async =>
          container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected'),
      'connectionUnknown': () async => container
          .read(authViewModelProvider.notifier)
          .markConnectionUnknown(const NetworkFailure()),
      'declined': () async {
        await seedMatched('t1');
        await container.read(authViewModelProvider.notifier).confirmMatch(false);
      },
    };
    for (final entry in seeds.entries) {
      testWidgets('${entry.key} stage', (tester) async {
        await entry.value();
        await pumpScreen(tester);

        final sentences = visibleSentences(tester);
        final seen = <String>{};
        final duplicates = <String>{};
        for (final s in sentences) {
          if (!seen.add(s)) duplicates.add(s);
        }
        expect(duplicates, isEmpty, reason: '${entry.key} — 같은 문장이 두 번 그려졌다: $duplicates');
      });
    }
  });

  group('좁은 화면(320×568) + 글자 배율 1.35 (P59 후속 4의 공백)', () {
    // app.dart의 클램프 상한이 정확히 1.35라 이 배율은 실제 앱의 최대 배율과 같다(더
    // 보수적이지 않다). 화면은 스크롤 구조(P59 B5)라 세로 넘침은 스크롤이 받는다 — 여기서
    // 잡는 것은 Row·Wrap의 가로 넘침과 레이아웃 예외다.
    Future<void> pumpNarrowLarge(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.35; // app.dart 클램프 상한
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await pumpScreen(tester);
    }

    testWidgets('pendingApproval — 가장 긴 화면(대기 카드 + 연락 카드)이 넘치지 않는다', (tester) async {
      seedPending();
      await pumpNarrowLarge(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('지금 확인'), findsOneWidget);
      expect(find.text('번호 다시 인증하기'), findsOneWidget);
      expect(find.text('계정 삭제'), findsOneWidget);
    });

    testWidgets('notFound — 연락 카드 + 주 버튼 + 링크가 넘치지 않는다', (tester) async {
      await pumpNarrowLarge(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('가입 요청 보내기'), findsOneWidget);
      expect(find.text('번호 다시 인증하기'), findsOneWidget);
      expect(find.text('계정 삭제'), findsOneWidget);
    });
  });

  // ── 대기실 v2 (P69) ──────────────────────────────────────────────────────
  //
  // 실사 화면(2026-09-08)의 두 거짓("자동으로 연결돼요"·"바로 홈으로")은 확인 수단의 부재에서
  // 나왔다. v2는 스텝퍼(어디까지 갔나) + 확인 상태 줄(언제 확인했나) + 자동 확인으로 문장을
  // 참으로 만들고, 센터 카드·코치 줄·미리보기로 "우리 센터가 안 보인다"를 채운다.

  group('스텝퍼 (P69 H2)', () {
    testWidgets('pending — 네 단계, 현재는 "센터 승인 기다리는 중", 요청 시각이 붙는다', (tester) async {
      container.read(authViewModelProvider.notifier).restorePendingJoinRequest(
            JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime(2026, 9, 8, 12, 5)),
          );
      await pumpScreen(tester);

      expect(find.text('번호 인증'), findsOneWidget);
      expect(find.text('가입 요청 보냄 · 9/8 12:05'), findsOneWidget);
      // 경과가 붙는다(P72) — 데스크 어드민만 시간을 세고 앱 화면은 1분째와 3일째가
      // 글자 하나 다르지 않았다. 요청 시각이 2026-09-08이라 항상 '3일 넘음'이다.
      expect(find.textContaining('센터 승인 기다리는 중'), findsOneWidget);
      expect(find.text('센터 승인 기다리는 중 · 3일 넘음'), findsOneWidget);
      expect(find.text('연결'), findsOneWidget);
    });

    // **`find`는 화면 밖 위젯도 찾는다**(P72 · ram-verify-loop 함정 ⑩의 친척).
    // 종전의 320×568 테스트는 `takeException == null`과 `findsOneWidget`만 봤고, 실제로는
    // 주 CTA가 접힘 아래(y≈580 > 568)에 있어도 전부 초록이었다. 실기기에서는 "연결된 센터가
    // 없어요 + 회색 카드"만 보이고 다음에 뭘 눌러야 하는지가 화면 밖이다.
    testWidgets('320×568 — 주 CTA가 접힘 **안**에 있다 (find가 못 잡는 결함)', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpScreen(tester); // notFound

      final cta = tester.getRect(find.text('가입 요청 보내기'));
      expect(cta.bottom, lessThanOrEqualTo(568.0),
          reason: '주 버튼이 접힘 아래로 내려갔다 — bottom=${cta.bottom}');
    });

    testWidgets('요청 시각을 모르면 시각 없이 "가입 요청 보냄" — 지어내지 않는다', (tester) async {
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('pending');
      await pumpScreen(tester);

      expect(find.text('가입 요청 보냄'), findsOneWidget);
      expect(find.textContaining('가입 요청 보냄 ·'), findsNothing);
    });

    // **종전 규약이 뒤집혔다**(P72 C1). 예전 이름은 "확인 상태 줄은 없다(확인할 요청이 없다)"
    // 였고, 그 근거는 "요청을 안 보냈으니 확인할 것이 없다"였다. 틀린 전제다 — 이 단계에서
    // 기다리는 것은 승인이 아니라 **데스크의 번호 등록·정정**이고, 화면의 힌트가 정확히 그
    // 행동을 지시한다. 끝났는지 물어볼 버튼이 없어서, 데스크가 고쳐 줘도 회원 화면은 영영
    // "찾지 못했어요"였고 유일한 길이 SMS 재인증이었다.
    testWidgets('notFound — "가입 요청"이 현재 단계, 확인 줄은 **등록**을 기다린다', (tester) async {
      await pumpScreen(tester); // notFound

      expect(find.text('번호 인증'), findsOneWidget);
      expect(find.text('가입 요청'), findsOneWidget);
      expect(find.text('센터 승인'), findsOneWidget);
      expect(find.text('연결'), findsOneWidget);
      expect(find.text('지금 확인'), findsOneWidget, reason: 'P72 C1 — 데스크가 고쳤는지 물어볼 수단');
      expect(find.text('아직 확인 전'), findsOneWidget);
    });

    // **함수 시험은 배선을 안 잰다**(ram-verify-loop 함정 ⑩ — 실제로 여기서 걸렸다).
    // `statusText(awaiting: registration)`만 직접 부르는 시험은, 화면이 그 값을 정말
    // 넘기는지 한 글자도 보지 않는다. 실측: 화면의 `CheckAwaiting.registration`을
    // `approval`로 되돌려도 순수 함수 시험은 전부 초록이었다. 그래서 **그려서** 잰다.
    testWidgets('notFound의 확인 꼬리는 "아직 승인 전"이 아니다 — 보낸 적 없는 요청을 가리키지 않는다',
        (tester) async {
      await pumpScreen(tester); // notFound

      await tester.tap(find.text('지금 확인'));
      await tester.pumpAndSettle();

      // '· 아직 등록 전'(가운뎃점 포함)이어야 확인 상태 줄이다 — 연락 카드 힌트에도
      // "아직 등록 전이면"이 들어 있어 느슨한 finder는 배선을 안 재고 통과한다.
      expect(find.textContaining('· 아직 등록 전'), findsOneWidget);
      expect(find.text('아직 등록 전이에요'), findsOneWidget, reason: '수동 확인 스낵바도 같은 축');
      expect(find.textContaining('· 아직 승인 전'), findsNothing,
          reason: '보낸 적 없는 요청의 승인을 기다린다고 말하면 거짓이다');
    });

    testWidgets('pending의 확인 꼬리는 종전대로 "아직 승인 전"', (tester) async {
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('pending');
      // 확인 뒤에도 pending이어야 한다 — 서버가 "요청 없음"을 답하면 stage가 notFound로
      // 떨어지고(그게 P63이 만든 규약이다) 꼬리도 같이 바뀌는 게 맞다.
      repo.sessionResult = const Err(MemberNotLinkedFailure(joinStatus: 'pending'));
      await pumpScreen(tester);

      await tester.tap(find.text('지금 확인'));
      await tester.pumpAndSettle();

      expect(find.textContaining('· 아직 승인 전'), findsOneWidget);
      expect(find.text('아직 승인 전이에요'), findsOneWidget);
      expect(find.textContaining('· 아직 등록 전'), findsNothing);
    });

    testWidgets('rejected — 스텝퍼 대신 결과 행(시각 있음)', (tester) async {
      container
          .read(authViewModelProvider.notifier)
          .applyServerJoinStatus('rejected', requestedAt: DateTime(2026, 9, 8, 12, 5));
      await pumpScreen(tester);

      expect(find.text('9/8 12:05 보낸 요청 · 센터가 연결하지 않았어요'), findsOneWidget);
      expect(find.text('번호 인증'), findsNothing, reason: '✗ 스텝퍼는 징벌적으로 읽힌다');
      expect(find.text('지금 확인'), findsNothing);
    });

    testWidgets('rejected — 시각 없으면 축약형', (tester) async {
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected');
      await pumpScreen(tester);

      expect(find.text('보낸 요청을 센터가 연결하지 않았어요'), findsOneWidget);
    });

    testWidgets('matched·connectionUnknown — 스텝퍼 없음', (tester) async {
      container.read(authViewModelProvider.notifier).markConnectionUnknown(const NetworkFailure());
      await pumpScreen(tester);
      expect(find.text('번호 인증'), findsNothing);
      expect(find.text('지금 확인'), findsNothing);
    });

    testWidgets('matched — 스텝퍼 없음 (이름 확인이 본체)', (tester) async {
      await seedMatched('t1');
      await pumpScreen(tester);
      expect(find.text('번호 인증'), findsNothing);
    });

    // 임계가 360 → **400**이다(P72). `availableWidth`는 기기 폭 − 좌우 패딩 40이므로
    // 종전 경계는 기기 폭 **400dp**였다: 320·360·390(iPhone 14~16)·393(Pixel)은 이미
    // 세로였고, **412(Pixel Pro)·430(Pro Max)만 가로**였다. 즉 가로 4점 배치는 큰 폰
    // 두 종에서만 보였고 하필 그 배치의 라벨이 이 화면에서 가장 작았다 — "가장 작은 글자가
    // 가장 큰 폰에만" 나오는 배치였다. 세로는 라벨 줄바꿈이 없고 트랙선으로 진행률도
    // 보이므로 그쪽을 정본으로 굳힌다(가로는 태블릿 폭용으로 남긴다).
    //
    // 자를 두 번 고쳤다: 처음엔 350(=390dp 폰)으로 재려 했는데 **그 값은 옛 임계에서도
    // 이미 세로**라 되돌림이 조용히 통과했다. 구간을 실제로 가르는 값은 372·390이다.
    test('세로 전환 규칙 — 폭 < 400 또는 배율 ≥ 1.2', () {
      expect(LobbyProgress.isVertical(availableWidth: 280, textScale: 1.0), isTrue);
      expect(LobbyProgress.isVertical(availableWidth: 350, textScale: 1.0), isTrue,
          reason: 'iPhone 14/15/16(390dp) — 옛 임계에서도 세로였다');
      expect(LobbyProgress.isVertical(availableWidth: 372, textScale: 1.0), isTrue,
          reason: 'Pixel Pro(412dp) — 임계를 360으로 되돌리면 여기가 죽는다');
      expect(LobbyProgress.isVertical(availableWidth: 390, textScale: 1.0), isTrue,
          reason: 'iPhone Pro Max(430dp) — 같은 자리');
      expect(LobbyProgress.isVertical(availableWidth: 400, textScale: 1.2), isTrue);
      expect(LobbyProgress.isVertical(availableWidth: 400, textScale: 1.0), isFalse,
          reason: '태블릿 폭에서는 가로 4점이 남는다');
    });
  });

  group('확인 상태 줄 — 3상태 (P69 H2)', () {
    test('아직 확인 전 / 마지막 확인 HH:mm · 아직 승인 전 / HH:mm 확인 못 함', () {
      expect(CheckStatusLine.statusText(), '아직 확인 전');
      expect(
        CheckStatusLine.statusText(lastCheckedAt: DateTime(2026, 9, 8, 12, 14)),
        '마지막 확인 12:14 · 아직 승인 전',
      );
      // 실패가 성공보다 뒤면 "확인 못 함" — 실패한 호출의 시각을 "마지막 확인"으로 찍지 않는다.
      expect(
        CheckStatusLine.statusText(
          lastCheckedAt: DateTime(2026, 9, 8, 12, 14),
          lastCheckFailedAt: DateTime(2026, 9, 8, 12, 20),
        ),
        '12:20 확인 못 함',
      );
      // 실패 뒤 성공하면 다시 "마지막 확인".
      expect(
        CheckStatusLine.statusText(
          lastCheckedAt: DateTime(2026, 9, 8, 12, 30),
          lastCheckFailedAt: DateTime(2026, 9, 8, 12, 20),
        ),
        '마지막 확인 12:30 · 아직 승인 전',
      );
    });

    testWidgets('수동 확인 성공 → "마지막 확인", 실패 → "확인 못 함"', (tester) async {
      seedPending();
      await pumpScreen(tester);
      expect(find.text('아직 확인 전'), findsOneWidget);

      await tester.tap(find.text('지금 확인'));
      await tester.pumpAndSettle();
      expect(find.textContaining('마지막 확인'), findsOneWidget);
      expect(find.textContaining('아직 승인 전'), findsWidgets);

      repo.sessionResult = const Err(NetworkFailure());
      await tester.tap(find.text('지금 확인'));
      await tester.pumpAndSettle();
      expect(find.textContaining('확인 못 함'), findsOneWidget);
      expect(find.textContaining('마지막 확인'), findsNothing);
    });

    testWidgets('보조문 "자동으로 확인해요"는 자동 확인이 켜져 있을 때만', (tester) async {
      seedPending();
      await pumpScreen(tester); // 하네스는 자동 확인 off
      expect(find.text(CheckStatusLine.autoHint), findsNothing, reason: '꺼져 있는데 자동이라 말하면 거짓');
      await tester.pumpWidget(const SizedBox());

      // 켜진 컨테이너 — pumpAndSettle 대신 pump(타이머가 살아 있다), 끝에 명시 dispose.
      // 센터 카드의 네트워크도 막는다 — settle 없이 dispose하면 dio 타임아웃 타이머가 남는다.
      rebuildContainer(
        [centerContactProvider.overrideWith((ref, _) async => const CenterContact())],
        autoCheckInterval: const Duration(seconds: 30),
      );
      seedPending();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildAppTheme(), home: const CenterConfirmScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(CheckStatusLine.autoHint), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('"다시 요청" 조건부 (P69 C2)', () {
    testWidgets('서버가 pending을 확답하면 "다시 요청"이 없다 — 100% 409인 함정 버튼', (tester) async {
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('pending');
      await pumpScreen(tester);

      expect(find.text('가입 요청을 보냈어요'), findsOneWidget);
      expect(find.textContaining('다시 요청'), findsNothing);
      expect(find.text('지금 확인'), findsOneWidget, reason: '확인은 남는다');
    });

    testWidgets('로컬 기록만(unknown)이면 "다시 요청"이 있다 — 30초 쿨다운', (tester) async {
      seedPending();
      await pumpScreen(tester);

      expect(find.textContaining('다시 요청 ('), findsOneWidget);
      final retry = tester.widget<OutlinedButton>(
        find.ancestor(of: find.textContaining('다시 요청'), matching: find.byType(OutlinedButton)),
      );
      expect(retry.onPressed, isNull, reason: '쿨다운 중');
    });

    testWidgets('서버가 요청 없음(null)이라 답해도 로컬 기록이 남아 "다시 요청"이 다시 열린다 — 막다른 길 없음', (tester) async {
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('pending');
      container.read(authViewModelProvider.notifier).restorePendingJoinRequest(
            JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime.now().subtract(const Duration(minutes: 5))),
          );
      await pumpScreen(tester);
      expect(find.textContaining('다시 요청'), findsNothing);

      await tester.tap(find.text('지금 확인')); // fake는 joinStatus null
      await tester.pumpAndSettle();

      expect(find.text('가입 요청을 보냈어요'), findsOneWidget, reason: '로컬 기록은 유지');
      expect(find.text('다시 요청'), findsOneWidget, reason: '쿨다운 지난 로컬 기록 — 즉시 열린다');
    });

    testWidgets('409 join_pending → pending 승격: 시트는 성공처럼 닫히고 문구만 다르다', (tester) async {
      // 시나리오: 기기 변경으로 로컬 기록이 없고 /v1/me도 요청을 못 실어 준 사람이 다시 보낸다.
      repo.requestJoinResult = const Err(JoinPendingFailure(centerId: 'gangnam-2'));
      container.read(authViewModelProvider.notifier).restoreSignedInPhone('+821012345678');
      await pumpScreen(tester); // notFound
      await openJoinSheet(tester);
      await tester.enterText(find.byType(TextField).last, '람');
      await tester.tap(find.text('가입 요청 보내기').last);
      await tester.pumpAndSettle();

      expect(find.text('이미 보낸 요청이 있어요'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: '시트가 닫혔다');
      expect(find.text('가입 요청을 보냈어요'), findsOneWidget, reason: '대기 화면으로');
      expect(find.textContaining('다시 요청'), findsNothing, reason: '서버 확답 pending');
      final auth = container.read(authViewModelProvider);
      expect(auth.joinRequestTrace, JoinRequestTrace.pending);
      expect(auth.joinCenterId, 'gangnam-2');
      expect(store.record?.centerId, 'gangnam-2', reason: '재실행 복귀용 로컬 기록');
    });
  });

  group('센터 카드 (P69 H3)', () {
    final askedCenters = <String?>[];
    CenterContact contact = const CenterContact();
    setUp(() {
      askedCenters.clear();
      contact = const CenterContact();
      rebuildContainer([
        centerContactProvider.overrideWith((ref, centerId) async {
          askedCenters.add(centerId);
          return contact;
        }),
      ]);
    });

    testWidgets('요청한 센터가 있으면 그 센터 인스턴스(?center=)를 묻고, 2곳 이상이면 "요청한 센터" 라벨', (tester) async {
      repo.joinCenters = const [
        CenterDirectory(id: 'gangnam-2', name: '라이즈 강남 2호점'),
        CenterDirectory(id: 'rise', name: '라이즈 컨디셔닝 센터'),
      ];
      contact = const CenterContact(name: '라이즈 강남 2호점');
      container.read(authViewModelProvider.notifier).restorePendingJoinRequest(
            JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime.now(), centerId: 'gangnam-2'),
          );
      await pumpScreen(tester);

      expect(askedCenters, contains('gangnam-2'));
      expect(askedCenters, isNot(contains(null)), reason: '기본 센터 인스턴스를 섞어 부르지 않는다');
      expect(find.text('요청한 센터'), findsOneWidget);
      expect(find.text('라이즈 강남 2호점'), findsOneWidget);
    });

    testWidgets('서버 join_request.center_id가 로컬 기록보다 우선한다', (tester) async {
      container.read(authViewModelProvider.notifier).restorePendingJoinRequest(
            JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime.now(), centerId: 'rise'),
          );
      container
          .read(authViewModelProvider.notifier)
          .applyServerJoinStatus('pending', centerId: 'rise', joinCenterId: 'gangnam-2');
      await pumpScreen(tester);

      expect(askedCenters, contains('gangnam-2'));
      expect(askedCenters, isNot(contains('rise')));
    });

    testWidgets('요청 센터가 없으면 기본 인스턴스(null) — 라벨 없음 (홈 헤더와 같은 인스턴스)', (tester) async {
      repo.joinCenters = const [
        CenterDirectory(id: 'gangnam-2', name: '라이즈 강남 2호점'),
        CenterDirectory(id: 'rise', name: '라이즈 컨디셔닝 센터'),
      ];
      await pumpScreen(tester); // notFound

      expect(askedCenters, [null]);
      expect(find.text('요청한 센터'), findsNothing);
    });

    testWidgets('주소가 있으면 탭 가능한 행, 수업 시간은 close_hour+1로 표기', (tester) async {
      contact = const CenterContact(
        name: '라이즈 컨디셔닝 센터',
        address: '서울 강남구 테헤란로 1',
        openHour: 9,
        closeHour: 21,
      );
      await pumpScreen(tester);

      expect(find.text('서울 강남구 테헤란로 1'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('서울 강남구 테헤란로 1'), matching: find.byType(InkWell)),
        findsOneWidget,
        reason: '주소 행은 지도로 가는 탭 대상',
      );
      // 21은 "마지막 슬롯 시작"이라 그대로 찍으면 한 시간이 증발한다.
      expect(find.text('수업 09:00–22:00'), findsOneWidget);
      expect(find.textContaining('운영시간'), findsNothing);
    });

    testWidgets('주소·시간이 없으면 행 자체가 없다 — 카드 프레임과 힌트는 유지', (tester) async {
      contact = const CenterContact(name: '라이즈 컨디셔닝 센터');
      await pumpScreen(tester);

      expect(find.textContaining('수업 '), findsNothing);
      expect(find.byType(InkWell), findsWidgets); // 다른 InkWell(미리보기 등)은 있어도 된다
      expect(find.text('라이즈 컨디셔닝 센터'), findsOneWidget);
      expect(find.text('센터에 등록된 번호가 다르거나 아직 등록 전이면 자동 연결이 안 돼요. '
          '센터 데스크에 이 번호를 알려주면 등록·수정해 드려요 — 그 뒤 이 화면에서 [지금 확인]을 '
          '누르면 이름 확인 한 번으로 연결돼요.'), findsOneWidget);
    });

    testWidgets('한쪽 시각만 온 응답은 시간 행을 그리지 않는다', (tester) async {
      contact = const CenterContact(name: '라이즈', openHour: 9);
      await pumpScreen(tester);
      expect(find.textContaining('수업 '), findsNothing);
    });
  });

  group('코치 한 줄 (P69 M1)', () {
    const active1 = StaffDto(uid: 't1', name: '정혜린', role: 'trainer');
    const active2 = StaffDto(uid: 't2', name: '김관장', role: 'owner');
    const gone = StaffDto(uid: 't3', name: '박퇴사', status: 'inactive');

    testWidgets('현직 코치 아바타 + "코치 N명" → 탭하면 코치 소개 시트', (tester) async {
      staffMap = {'t1': active1, 't2': active2, 't3': gone};
      await pumpScreen(tester); // notFound

      expect(find.text('코치 2명'), findsOneWidget, reason: '퇴사자 제외');
      expect(find.byType(TrainerAvatar), findsNWidgets(2));

      await tester.tap(find.text('코치 2명'));
      await tester.pumpAndSettle();
      expect(find.text('센터 코치 소개'), findsOneWidget);
      expect(find.text('박퇴사'), findsNothing);
    });

    testWidgets('아바타는 최대 4개, 숫자는 전체', (tester) async {
      staffMap = {
        for (var i = 0; i < 6; i++) 't$i': StaffDto(uid: 't$i', name: '코치$i'),
      };
      await pumpScreen(tester);
      expect(find.text('코치 6명'), findsOneWidget);
      expect(find.byType(TrainerAvatar), findsNWidgets(4));
    });

    testWidgets('현직 0명이면 줄 자체가 없다 — "코치 0명"은 센터를 깎아내리는 문장', (tester) async {
      staffMap = {'t3': gone};
      await pumpScreen(tester);
      expect(find.textContaining('코치 '), findsNothing);
      expect(find.byType(TrainerAvatar), findsNothing);
    });

    testWidgets('rejected에서는 숨긴다 — 거절 직후의 쇼룸은 어긋난 톤', (tester) async {
      staffMap = {'t1': active1};
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected');
      await pumpScreen(tester);
      expect(find.text('코치 1명'), findsNothing);
    });

    testWidgets('요청 센터가 Principal 센터와 다르면 숨긴다 — /v1/staff는 기본 센터 목록이다', (tester) async {
      staffMap = {'t1': active1};
      container.read(authViewModelProvider.notifier).restorePendingJoinRequest(
            JoinRequestRecord(phone: '+821012345678', requestedAt: DateTime.now(), centerId: 'gangnam-2'),
          );
      await pumpScreen(tester);
      expect(find.text('코치 1명'), findsNothing);

      // 서버가 "요청 센터 == Principal 센터"라고 답하면 보인다.
      container
          .read(authViewModelProvider.notifier)
          .applyServerJoinStatus('pending', centerId: 'gangnam-2', joinCenterId: 'gangnam-2');
      await tester.pumpAndSettle();
      expect(find.text('코치 1명'), findsOneWidget);
    });

    testWidgets('pending에서도 보인다 (센터 일치 시)', (tester) async {
      staffMap = {'t1': active1};
      seedPending();
      await pumpScreen(tester);
      expect(find.text('코치 1명'), findsOneWidget);
    });
  });

  group('"연결되면 이 앱에서" 미리보기 (P69 M3)', () {
    const labels = ['예약', 'QR 출석', '운동 기록', '체형 사진'];

    testWidgets('notFound — 인라인 4칸, 안내문의 같은 문장은 뺀다', (tester) async {
      await pumpScreen(tester);

      expect(find.text('연결되면 이 앱에서'), findsOneWidget);
      for (final l in labels) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(find.text('연결되면 예약·운동 기록·체형 사진을 여기서 볼 수 있어요.'), findsNothing,
          reason: '같은 문장 두 번 금지 — 미리보기가 보일 땐 안내문을 뺀다');
    });

    testWidgets('320×568에서는 한 줄 링크로 접히고, 탭하면 시트가 같은 네 가지를 보여준다', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpScreen(tester);

      expect(find.text('연결되면 할 수 있는 것'), findsOneWidget);
      expect(find.text('연결되면 이 앱에서'), findsNothing);
      expect(find.byType(RiseMark), findsNothing, reason: '빠듯하면 장식이 먼저 빠진다(P72)');

      await tester.tap(find.text('연결되면 할 수 있는 것'));
      await tester.pumpAndSettle();
      expect(find.text('연결되면 이 앱에서'), findsOneWidget);
      for (final l in labels) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
    });

    testWidgets('글자 배율 1.3 이상이면 접힌다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScreen(tester);
      expect(find.text('연결되면 할 수 있는 것'), findsOneWidget);
    });

    testWidgets('rejected·connectionUnknown — 미리보기 없음, 안내문은 종전대로', (tester) async {
      container.read(authViewModelProvider.notifier).applyServerJoinStatus('rejected');
      await pumpScreen(tester);
      expect(find.text('연결되면 이 앱에서'), findsNothing);
      expect(find.text('연결되면 할 수 있는 것'), findsNothing);
      expect(find.text('연결되면 예약·운동 기록·체형 사진을 여기서 볼 수 있어요.'), findsOneWidget);
    });

    testWidgets('pending·declined에서도 보인다', (tester) async {
      seedPending();
      await pumpScreen(tester);
      expect(find.text('연결되면 이 앱에서'), findsOneWidget);
    });
  });

  group('좁은 화면(320×568) + 글자 배율 1.35 — v2 요소가 늘어도 예외 0', () {
    Future<void> pumpNarrowLarge(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.35;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await pumpScreen(tester);
    }

    testWidgets('pending — 세로 스텝퍼 + 상태 줄 + 재요청 + 센터 카드 + 코치 줄 + 접힌 미리보기', (tester) async {
      staffMap = {for (var i = 0; i < 5; i++) 't$i': StaffDto(uid: 't$i', name: '코치$i')};
      seedPending();
      await pumpNarrowLarge(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('센터 승인 기다리는 중'), findsOneWidget);
      expect(find.text('지금 확인'), findsOneWidget);
      expect(find.text('코치 5명'), findsOneWidget);
      expect(find.text('연결되면 할 수 있는 것'), findsOneWidget);
    });

    testWidgets('notFound — 스텝퍼 + 센터 카드 + 코치 줄 + 접힌 미리보기 + CTA', (tester) async {
      staffMap = {'t1': const StaffDto(uid: 't1', name: '정혜린')};
      await pumpNarrowLarge(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('가입 요청'), findsOneWidget);
      expect(find.text('가입 요청 보내기'), findsOneWidget);
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

  /// 심어 두면 가입 요청이 이 completer가 끝날 때까지 **매달린다**(제출 중 상태 재현).
  Completer<Result<void>>? requestJoinGate;

  /// 마지막 가입 요청이 실은 센터 — 선택이 실제로 전달되는지 본다.
  String? lastRequestedCenterId;

  /// 고정 결과 — 409 `join_pending` 승격 같은 실패 경로 재현용(null이면 성공).
  Result<void>? requestJoinResult;

  @override
  Future<Result<void>> requestJoin({
    required String name,
    required String phone,
    String centerId = '',
  }) async {
    lastRequestedCenterId = centerId;
    if (requestJoinGate case final gate?) return gate.future;
    return requestJoinResult ?? const Ok(null);
  }

  /// v2.33 — 센터 목록. 기본은 빈 목록(고를 것 없음 = 선택 UI 미노출)이고,
  /// 선택 화면을 시험하는 케이스가 [joinCenters]를 채운다.
  List<CenterDirectory> joinCenters = const <CenterDirectory>[];

  @override
  Future<Result<List<CenterDirectory>>> fetchJoinCenters() async => Ok(joinCenters);

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
