import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/member_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/camera_permission_view.dart';
import 'package:rise_member/features/records/data/inbody_sheet_reader.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/inbody_metrics.dart';
import 'package:rise_member/features/records/domain/inbody_sheet_parser.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/domain/records_repository.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';
import 'package:rise_member/features/records/presentation/widgets/inbody_add_sheet.dart';

// "사진에서 채우기"(P20) — 수기 폼 위에 얹힌 OCR 프리필의 흐름.
//
// 못 박는 것:
// ① 성공/부분/0건/실패/취소 전부 **같은 폼**으로 떨어진다 — 별도 에러 화면이
//    없다. 수기 입력이 곧 실패 경로다(제품 결정).
// ② 자동 저장 없음 — 프리필은 컨트롤러를 채울 뿐, 저장은 기존 경로(사람이 버튼).
// ③ 어느 칸이 기계가 읽은 값인지 보인다("사진" 표식). 회원이 고치면 표식이
//    떨어진다 — 그 순간부터 회원의 입력이다.
// ④ 프리필 문구는 과장하지 않는다 — 6칸을 다 채웠어도 확인을 요청한다.
// ⑤ 카메라는 권한 게이트를 먼저 통과한다(매니페스트에 CAMERA가 선언된 앱은
//    권한 없이 촬영 인텐트를 못 띄운다). 안내 문장은 사실만: 저장하지 않는다.
// ⑥ Android 전용 — iOS에선 버튼이 없고 "아직 없어요" 문구가 계속 사실이다.
void main() {
  late _FakeRecordsRepository repo;
  late _FakeReader reader;
  late _FakeGate gate;

  Widget host({
    CameraPermissionResult permission = CameraPermissionResult.granted,
  }) {
    repo = _FakeRecordsRepository();
    reader = _FakeReader();
    gate = _FakeGate(permission);
    final container = ProviderContainer.test(
      overrides: [
        recordsRepositoryProvider.overrideWithValue(repo),
        inbodySheetReaderProvider.overrideWithValue(reader),
        cameraPermissionGateProvider.overrideWithValue(gate),
        myProfileProvider.overrideWith((ref) async => const MemberDto(
              id: 'm1',
              name: '람',
              phone: '01012345678',
              consent: ConsentDto(general: true, sensitive: true),
            )),
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

  Future<void> fillFromPhoto(WidgetTester tester,
      {String source = '앨범에서 선택'}) async {
    await tester.tap(find.text('사진에서 채우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(source));
    await tester.pumpAndSettle();
  }

  Finder field(InbodyMetric m) => find.ancestor(
        of: find.text(m.formLabel),
        matching: find.byType(TextField),
      );

  String fieldText(WidgetTester tester, InbodyMetric m) =>
      tester.widget<TextField>(field(m)).controller!.text;

  const fullResult = InbodySheetParseResult(
    values: {
      InbodyMetric.weight: 72.5,
      InbodyMetric.smm: 35.6,
      InbodyMetric.bfm: 10.0,
      InbodyMetric.pbf: 13.7,
      InbodyMetric.vfl: 3,
      InbodyMetric.bmr: 1721,
    },
  );

  group('갤러리 경로 — 프리필', () {
    testWidgets('6칸 프리필: 값이 채워지고, 어느 칸이 사진에서 왔는지 보인다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      reader.outcome = InbodySheetRead(InbodySheetParseResult(
        values: fullResult.values,
        measuredDate: DateTime(2026, 8, 20),
      ));

      await fillFromPhoto(tester);

      expect(reader.calls, [InbodyPhotoSource.gallery]);
      expect(fieldText(tester, InbodyMetric.weight), '72.5');
      expect(fieldText(tester, InbodyMetric.smm), '35.6');
      expect(fieldText(tester, InbodyMetric.bfm), '10');
      expect(fieldText(tester, InbodyMetric.pbf), '13.7');
      expect(fieldText(tester, InbodyMetric.vfl), '3');
      expect(fieldText(tester, InbodyMetric.bmr), '1721');
      expect(find.text('사진'), findsNWidgets(6), reason: '칸별 프리필 표식');
      expect(find.text('2026-08-20'), findsOneWidget, reason: '측정일도 프리필');
      // ④ 다 채워도 확인 요청 — 과장 금지.
      expect(
        find.textContaining('읽은 값은 꼭 확인해주세요 — 사진 상태에 따라 틀리거나 비어 있을 수 있어요'),
        findsOneWidget,
      );
    });

    testWidgets('부분 프리필: 읽은 칸만 채우고 나머지는 빈칸 그대로 — 같은 폼', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      reader.outcome = const InbodySheetRead(InbodySheetParseResult(values: {
        InbodyMetric.weight: 72.5,
        InbodyMetric.smm: 35.6,
        InbodyMetric.pbf: 13.7,
      }));

      await fillFromPhoto(tester);

      expect(find.text('사진'), findsNWidgets(3));
      expect(fieldText(tester, InbodyMetric.bfm), isEmpty);
      expect(find.textContaining('3칸을 채웠어요'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(6), reason: '① 같은 폼 유지');
    });

    testWidgets('0건 인식: 같은 폼 + 직접 입력 안내 — 별도 에러 화면 없음', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      reader.outcome = const InbodySheetRead(InbodySheetParseResult.empty());

      await fillFromPhoto(tester);

      expect(find.byType(TextField), findsNWidgets(6));
      expect(find.textContaining('값을 읽지 못했어요'), findsOneWidget);
      expect(find.text('사진'), findsNothing);
    });

    testWidgets('인식 실패: 같은 폼 + 직접 입력 안내', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      reader.outcome = const InbodySheetReadFailed();

      await fillFromPhoto(tester);

      expect(find.byType(TextField), findsNWidgets(6));
      expect(find.textContaining('값을 읽지 못했어요'), findsOneWidget);
    });

    testWidgets('픽커 취소: 아무 말도 하지 않는다 — 회원이 스스로 물린 것', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      reader.outcome = const InbodySheetReadCancelled();

      await fillFromPhoto(tester);

      expect(find.textContaining('읽지 못했'), findsNothing);
      expect(find.textContaining('채웠어요'), findsNothing);
    });

    testWidgets('프리필 칸을 회원이 고치면 표식이 떨어진다 — 이제 회원의 입력', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      reader.outcome = const InbodySheetRead(InbodySheetParseResult(values: {
        InbodyMetric.weight: 72.5,
        InbodyMetric.smm: 35.6,
      }));
      await fillFromPhoto(tester);
      expect(find.text('사진'), findsNWidgets(2));

      await tester.enterText(field(InbodyMetric.weight), '72.7');
      await tester.pump();

      expect(find.text('사진'), findsNWidgets(1));
    });

    testWidgets('측정일이 데이트피커 경계(2년 전~오늘) 밖이면 버린다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      reader.outcome = InbodySheetRead(InbodySheetParseResult(
        values: const {InbodyMetric.weight: 72.5},
        // 미래 날짜 — 인쇄 연도 오독. 기본값(오늘)을 밀어내면 안 된다.
        measuredDate: DateTime(2033, 1, 1),
      ));

      await fillFromPhoto(tester);

      expect(find.text('2033-01-01'), findsNothing);
    });

    testWidgets('② 자동 저장 없음: 프리필 뒤 저장은 기존 경로 그대로 — 사람이 누른다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      reader.outcome = const InbodySheetRead(fullResult);
      await fillFromPhoto(tester);

      expect(repo.createCount, 0, reason: '프리필만으로는 아무것도 서버로 가지 않는다');

      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();

      expect(repo.createCount, 1);
      final draft = repo.lastDraft!;
      expect(draft.weight, 72.5);
      expect(draft.smm, 35.6);
      expect(draft.bfm, 10.0);
      expect(draft.pbf, 13.7);
      expect(draft.vfl, 3);
      expect(draft.bmr, 1721);
    });
  });

  group('카메라 경로 — 권한 게이트', () {
    testWidgets('허용돼 있으면 바로 촬영으로 — 게이트를 거쳐 reader가 불린다', (tester) async {
      await tester.pumpWidget(host());
      await open(tester);
      reader.outcome = const InbodySheetRead(fullResult);

      await fillFromPhoto(tester, source: '카메라로 촬영');

      expect(gate.requests, 1);
      expect(reader.calls, [InbodyPhotoSource.camera]);
    });

    testWidgets('거부면 안내를 띄우고 읽지 않는다 — 문구는 사실만(저장하지 않는다)', (tester) async {
      await tester.pumpWidget(host(permission: CameraPermissionResult.denied));
      await open(tester);

      await fillFromPhoto(tester, source: '카메라로 촬영');

      expect(find.byType(CameraPermissionView), findsOneWidget);
      expect(
        find.textContaining('결과지 사진은 숫자를 읽는 데만 쓰고 저장하지 않아요'),
        findsOneWidget,
      );
      expect(reader.calls, isEmpty);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(6), reason: '폼으로 복귀');
      expect(reader.calls, isEmpty);
    });

    testWidgets('갤러리는 게이트를 거치지 않는다 — 시스템 포토피커라 권한이 없다', (tester) async {
      await tester.pumpWidget(
          host(permission: CameraPermissionResult.permanentlyDenied));
      await open(tester);
      reader.outcome = const InbodySheetRead(fullResult);

      await fillFromPhoto(tester);

      expect(gate.requests, 0);
      expect(reader.calls, [InbodyPhotoSource.gallery]);
    });
  });

  group('⑥ 플랫폼 분기 — Android 전용', () {
    testWidgets('iOS에는 버튼이 없고 "아직 없어요"가 계속 사실이다', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(host());
        await open(tester);

        expect(find.text('사진에서 채우기'), findsNothing);
        expect(find.textContaining('사진으로 자동 입력하는 기능은 아직 없어요'), findsOneWidget);
      } finally {
        // 바인딩이 테스트 본문 종료 시점에 foundation 변수 원복을 검사한다 —
        // tearDown은 그보다 늦어서 본문 안에서 되돌린다.
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Android에는 버튼이 있고 안내문이 기능을 말한다', (tester) async {
      // 위젯 테스트의 defaultTargetPlatform 기본값이 android다.
      await tester.pumpWidget(host());
      await open(tester);

      expect(find.text('사진에서 채우기'), findsOneWidget);
      expect(find.textContaining('아직 없어요'), findsNothing);
      expect(find.textContaining('사진에서 읽어와 채울 수도 있어요'), findsOneWidget);
    });
  });
}

class _FakeRecordsRepository implements RecordsRepository {
  int createCount = 0;
  InbodyDraft? lastDraft;

  @override
  Future<Result<RecordsData>> load(String memberId) async =>
      const Ok(RecordsData(
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
    return const Ok(null);
  }

  @override
  Future<Result<void>> deleteInbody(String id) async => const Ok(null);
}

class _FakeReader implements InbodySheetReader {
  InbodySheetReadOutcome outcome = const InbodySheetReadCancelled();
  final calls = <InbodyPhotoSource>[];

  @override
  Future<InbodySheetReadOutcome> read(InbodyPhotoSource source) async {
    calls.add(source);
    return outcome;
  }
}

class _FakeGate implements CameraPermissionGate {
  _FakeGate(this.result);
  final CameraPermissionResult result;
  int requests = 0;

  @override
  Future<CameraPermissionResult> ensureGranted() async {
    requests++;
    return result;
  }

  @override
  Future<void> openSettings() async {}
}
