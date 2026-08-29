import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/member_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/inbody_metrics.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/domain/records_repository.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';
import 'package:rise_member/features/records/presentation/widgets/inbody_add_sheet.dart';

// 인바디 수기 입력 시트. 기록 탭은 지금까지 순수 읽기였어서 쓰기 하네스가 없었다.
//
// 못 박는 것:
// ① 민감정보 동의가 없으면 **폼을 띄우지 않는다** — 6칸을 다 채운 뒤에 거부당하게
//    두지 않는다(hold_request_sheet의 _NoCandidateBody와 같은 판단).
// ② 프로필 **조회 실패는 막지 않는다** — 최종 판정은 서버가 한다. 앱이 서버보다
//    엄격해지면 이미 동의한 회원에게 막다른 길이 된다(camera_view_model 규약).
// ③ 서버가 확실히 거부할 값(범위 밖)이면 버튼을 잠근다. 다만 **빈 칸은 잠그지
//    않는다** — 미입력은 거부가 아니라 미완성이라 눌러서 안내를 받게 둔다.
// ④ 실패하면 시트를 **닫지 않는다** — 숫자 6개를 다시 옮겨 적게 만들지 않는다.
void main() {
  late _FakeRecordsRepository repo;

  Widget host({
    bool sensitiveConsent = true,
    bool profileFails = false,
  }) {
    repo = _FakeRecordsRepository();
    final container = ProviderContainer.test(
      overrides: [
        recordsRepositoryProvider.overrideWithValue(repo),
        myProfileProvider.overrideWith((ref) async {
          if (profileFails) throw const NetworkFailure('연결이 불안정해요');
          return MemberDto(
            id: 'm1',
            name: '람',
            phone: '01012345678',
            consent: ConsentDto(general: true, sensitive: sensitiveConsent),
          );
        }),
      ],
    );
    container.read(sessionProvider.notifier).set(const AppSession(
          uid: 'firebase-uid-1',
          role: 'member',
          centerId: 'rise-gangnam',
          memberId: 'm1',
          memberName: '람',
        ));
    addTearDown(container.dispose);

    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showInbodyAddSheet(context),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    String weight = '70.2',
    String smm = '30.1',
    String bfm = '18.8',
    String pbf = '26.8',
    String vfl = '8',
    String bmr = '1420',
  }) async {
    final values = {
      InbodyMetric.weight: weight,
      InbodyMetric.smm: smm,
      InbodyMetric.bfm: bfm,
      InbodyMetric.pbf: pbf,
      InbodyMetric.vfl: vfl,
      InbodyMetric.bmr: bmr,
    };
    for (final e in values.entries) {
      await tester.enterText(
        find.ancestor(
          of: find.text(e.key.formLabel),
          matching: find.byType(TextField),
        ),
        e.value,
      );
      await tester.pump();
    }
  }

  bool submitEnabled(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).enabled;

  group('동의 사전 분기', () {
    testWidgets('동의가 없으면 폼 대신 안내 — 입력 칸이 아예 없다', (tester) async {
      await tester.pumpWidget(host(sensitiveConsent: false));
      await open(tester);

      expect(find.textContaining('민감정보 동의가 필요해요'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('닫기'), findsOneWidget);
    });

    testWidgets('프로필 조회가 실패하면 막지 않고 폼을 연다 — 최종 판정은 서버가 한다', (tester) async {
      await tester.pumpWidget(host(profileFails: true));
      await open(tester);

      expect(find.byType(TextField), findsNWidgets(6));
      expect(find.textContaining('민감정보 동의가 필요해요'), findsNothing);
    });

    testWidgets('동의가 있으면 6칸 폼 — 어드민과 같은 라벨', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);

      for (final m in InbodyMetric.values) {
        expect(find.text(m.formLabel), findsOneWidget, reason: m.name);
      }
    });
  });

  group('사전 검증', () {
    testWidgets('빈 폼에서도 버튼은 눌린다 — 미입력은 거부가 아니라 미완성', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);

      expect(submitEnabled(tester), isTrue);

      await tester.tap(find.text('저장하기'));
      await tester.pump();

      expect(find.textContaining('6개 항목을 모두 입력해주세요'), findsOneWidget);
      expect(repo.createCount, 0, reason: '확실히 400인 요청을 서버로 보내지 않는다');
    });

    testWidgets('범위 밖 값이 있으면 버튼이 잠긴다(소수점 밀린 체중 702kg)', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await fill(tester, weight: '702');

      expect(submitEnabled(tester), isFalse);
      expect(find.textContaining('20~300'), findsOneWidget);
    });

    testWidgets('0은 거부 — 미입력을 0으로 채우면 서버가 400이다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await fill(tester, smm: '0');

      expect(submitEnabled(tester), isFalse);
    });

    testWidgets('BFM 칸에는 제지방량 혼동 경고가 상시 떠 있다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);

      expect(find.text('체지방량 — 제지방량(FFM) 아니에요'), findsOneWidget);
    });

    testWidgets('VFL 칸에는 단면적(cm²) 혼동 경고가 상시 떠 있다', (tester) async {
      // 770/970 결과지는 같은 자리에 단면적(cm², 100 근처)을 인쇄해 그대로 옮겨
      // 적는 실수가 난다. 서버 400 힌트("내장지방 레벨이에요 — 단면적이 아니에요")는
      // 앱 사전 판정이 요청을 막아 회원에게 영영 닿지 않는다 — 이 헬퍼가 유일한
      // 전달 경로다.
      await tester.pumpWidget(host());
      await open(tester);

      expect(find.text('내장지방 레벨 — 단면적(cm²) 아니에요'), findsOneWidget);
    });

    testWidgets('SMM+BFM이 체중을 넘으면 버튼이 잠긴다 — 서버가 확실히 거부하는 조합', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await fill(tester, weight: '70.0', smm: '30.0', bfm: '51.2');

      expect(submitEnabled(tester), isFalse);
      // 세 칸의 관계라 특정 필드의 errorText가 아니라 버튼 위 한 줄로 말한다.
      expect(find.textContaining('체중(70kg)을 넘어요'), findsOneWidget);
      expect(find.textContaining('체지방량 칸에 제지방량(FFM)을 적으신'), findsOneWidget);
    });

    testWidgets('서버가 받아 주는 조합이면 경고만 하고 막지 않는다 — 앱이 서버보다 엄격해지지 않게', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      // 6+51.2 = 57.2 ≤ 70 이라 서버 교차 검증은 통과한다. 다만 PBF와 안 맞는다.
      await fill(tester, weight: '70.0', smm: '6', bfm: '51.2', pbf: '26.8');

      expect(find.textContaining('제지방량(FFM)을 넣진 않았는지'), findsOneWidget);
      expect(submitEnabled(tester), isTrue, reason: '서버가 검증하지 않는 규칙으로 앱만 막으면 막다른 길이다');
    });
  });

  // "7"(체중 70의 첫 타) · "14"(BMR 1420의 도중)처럼 정상 값을 입력하는 과정이
  // 전부 범위 밖이다 — 키 입력마다 판정하면 옮겨 적는 내내 붉은 에러가 명멸한다.
  // 그래서 **지금 만지는 칸은 표시를 판정하지 않고**, 포커스가 떠난 칸만 판정한다.
  // 버튼 잠금은 종전대로 실시간이다(왕복 차단이 목적이라 미룰 이유가 없다).
  group('타이핑 중에는 잠잠 — 에러 표시는 칸을 떠난 뒤에만', () {
    Finder field(InbodyMetric m) => find.ancestor(
          of: find.text(m.formLabel),
          matching: find.byType(TextField),
        );

    testWidgets('입력 도중("7")에는 에러를 띄우지 않는다 — 버튼 잠금만 실시간', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);

      await tester.enterText(field(InbodyMetric.weight), '7');
      await tester.pump();

      expect(find.textContaining('20~300'), findsNothing, reason: '70을 치는 도중이다 — 아직 틀린 게 아니다');
      expect(submitEnabled(tester), isFalse, reason: '표시만 미룬다 — 이대로 제출되면 안 된다');
    });

    testWidgets('칸을 떠나면 그때 판정한다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await tester.enterText(field(InbodyMetric.weight), '7');
      await tester.pump();

      // 다음 칸으로 이동 — 체중 칸의 포커스가 떠난다.
      await tester.enterText(field(InbodyMetric.smm), '30.1');
      await tester.pump();

      expect(find.textContaining('20~300'), findsOneWidget, reason: '떠난 칸의 "7"은 이제 미완성이 아니라 오입력이다');
    });

    testWidgets('그 칸으로 돌아와 고치는 동안은 다시 잠잠해진다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await tester.enterText(field(InbodyMetric.weight), '7');
      await tester.pump();
      await tester.enterText(field(InbodyMetric.smm), '30.1');
      await tester.pump();
      expect(find.textContaining('20~300'), findsOneWidget);

      await tester.showKeyboard(field(InbodyMetric.weight));
      await tester.pump();

      expect(find.textContaining('20~300'), findsNothing, reason: '고치러 돌아온 칸에 에러를 계속 붙이면 지우는 동안 또 명멸한다');
    });
  });

  group('저장', () {
    testWidgets('성공하면 시트가 닫히고 저장됐다고 말한다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await fill(tester);

      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();

      expect(repo.createCount, 1);
      expect(find.byType(TextField), findsNothing, reason: '시트가 닫혀야 한다');
      expect(find.text('인바디 기록을 저장했어요'), findsOneWidget);
    });

    testWidgets('보내는 값은 입력한 그대로 — 측정일 기본값은 오늘(KST)', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await fill(tester);

      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();

      final draft = repo.lastDraft!;
      expect(draft.weight, 70.2);
      expect(draft.smm, 30.1);
      expect(draft.bfm, 18.8);
      expect(draft.pbf, 26.8);
      expect(draft.vfl, 8);
      expect(draft.bmr, 1420);
    });

    testWidgets('409는 시트를 유지하고 서버 문구를 그대로 보여준다 — 6칸을 다시 채우게 하지 않는다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await fill(tester);
      // 저장소가 409에 실제로 돌려주는 타입(ConflictFailure) 그대로 — ViewModel이
      // 이 타입에 재조회로 반응해도 시트는 열린 채 문구를 유지해야 한다.
      repo.createFailure = const ConflictFailure('그날 기록이 이미 있어요 — 기존 기록을 지우고 다시 넣어주세요');

      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(6), reason: '시트가 닫히면 6칸을 다시 옮겨 적어야 한다');
      expect(find.textContaining('그날 기록이 이미 있어요'), findsOneWidget);
    });

    testWidgets('네트워크 실패도 시트를 유지하고 서버 문구를 그대로 띄운다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      await fill(tester);
      repo.createFailure = const NetworkFailure('연결이 불안정해요');

      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(6));
      expect(find.textContaining('연결이 불안정해요'), findsOneWidget);
    });
  });

  // 측정일 기본값은 **센터(KST) 오늘**이어야 한다. `DateTime.now()`로 잡으면
  // 해외 체류·기기 시계 오설정 시 서버가 보는 "오늘"과 하루 어긋나고, 그 날짜가
  // 그대로 date로 저장돼 추이 그래프의 점 위치가 밀린다(DateFmt 시간축 규약).
  //
  // ⚠️ 호스트가 KST면 두 값이 같아 회귀가 원리상 안 보인다 — `TZ=UTC` 등
  // KST 아닌 TZ로도 한 번 돌리는 것까지가 검증이다(date_format_test.dart 규약).
  group('측정일 — 센터(KST) 축', () {
    testWidgets('UTC 8/17 20:00(=KST 8/18 05:00)이면 기본 측정일이 8/18이다', (tester) async {
      await withClock(Clock.fixed(DateTime.utc(2026, 8, 17, 20)), () async {
        await tester.pumpWidget(host());
        await open(tester);

        expect(find.text('2026-08-18'), findsOneWidget);
      });
    });

    testWidgets('그 날짜가 그대로 서버로 간다', (tester) async {
      await withClock(Clock.fixed(DateTime.utc(2026, 8, 17, 20)), () async {
        await tester.pumpWidget(host());
        await open(tester);
        await fill(tester);

        await tester.tap(find.text('저장하기'));
        await tester.pumpAndSettle();

        expect(repo.lastDraft!.date, DateTime(2026, 8, 18));
      });
    });
  });

  group('과장 금지 — 안내문이 실제 있는 기능만 말한다', () {
    // P20에서 "사진에서 채우기"가 생겨 "아직 없어요"는 Android에선 거짓이 됐다.
    // 안내문은 기능 존재 여부(플랫폼)를 따라간다 — 상세 분기는
    // inbody_photo_prefill_test.dart(⑥)가 iOS/Android 양쪽을 못 박는다.
    testWidgets('사진 프리필이 있는 플랫폼에선 "아직 없어요"라고 말하지 않는다', (tester) async {
      // 위젯 테스트의 defaultTargetPlatform 기본값은 android — 기능이 있는 쪽.
      await tester.pumpWidget(host());
      await open(tester);

      expect(find.textContaining('아직 없어요'), findsNothing);
      expect(find.textContaining('사진에서 읽어와 채울 수도 있어요'), findsOneWidget);
      expect(find.text('사진에서 채우기'), findsOneWidget);
    });
  });
}

class _FakeRecordsRepository implements RecordsRepository {
  int createCount = 0;
  InbodyDraft? lastDraft;
  Failure? createFailure;

  @override
  Future<Result<RecordsData>> load(String memberId) async => const Ok(RecordsData(
        workoutLogs: [],
        homeworkWeeks: [],
        inbodyRecords: [],
        bodyPhotos: BodyPhotoAlbum.empty,
      ));

  @override
  Future<Result<void>> createInbody({
    required String memberId,
    required InbodyDraft draft,
  }) async {
    createCount++;
    lastDraft = draft;
    return createFailure == null ? const Ok(null) : Err(createFailure!);
  }

  @override
  Future<Result<void>> deleteInbody(String id) async => const Ok(null);
}
