import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/domain/records_repository.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';
import 'package:rise_member/features/records/presentation/widgets/inbody_recent_list.dart';

// 정정 경로(삭제). 입력 폼과 한 묶음이다 — 이 리스트가 없으면 회원이 잘못 옮겨
// 적은 숫자를 지울 방법이 앱에 하나도 없고, 오입력이 차트에 영구히 남는다
// (수정 PUT은 만들지 않았다).
//
// 삭제 액션은 `source == 'member_self'`인 본인 기록에만 붙는다. 출처가 아예 없는
// (`null`) 예전 레코드를 "본인 것"으로 취급하면, 코치가 넣은 기록을 회원이
// 지워 버릴 수 있다.
void main() {
  late _FakeRecordsRepository repo;

  InbodyRecord rec({required String id, required int day, String? source}) => InbodyRecord(
        id: id,
        date: DateTime(2026, 8, day),
        weight: 70.2,
        smm: 30.1,
        bfm: 18.8,
        pbf: 26.8,
        vfl: 8,
        bmr: 1420,
        source: source,
      );

  Widget host(List<InbodyRecord> records) {
    repo = _FakeRecordsRepository();
    final container = ProviderContainer.test(
      overrides: [recordsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(child: InbodyRecentList(records: records)),
        ),
      ),
    );
  }

  group('삭제 액션이 붙는 조건', () {
    testWidgets('본인 입력(member_self)에만 삭제가 붙는다', (tester) async {
      await tester.pumpWidget(host([
        rec(id: 'i1', day: 1, source: 'member_self'),
        rec(id: 'i2', day: 2, source: 'staff'),
      ]));

      expect(find.text('삭제'), findsOneWidget);
      expect(find.text('센터 기록'), findsOneWidget);
    });

    testWidgets('출처가 없는(null) 예전 레코드는 삭제도, 출처 표기도 하지 않는다', (tester) async {
      await tester.pumpWidget(host([rec(id: 'i1', day: 1)]));

      expect(find.text('삭제'), findsNothing);
      // 누가 넣었는지 모르는 것을 "센터 기록"이라고 단정하면 그게 새 거짓말이다.
      expect(find.text('센터 기록'), findsNothing);
    });

    testWidgets('기록이 없으면 아무것도 그리지 않는다', (tester) async {
      await tester.pumpWidget(host([]));

      expect(find.text('최근 기록'), findsNothing);
    });

    testWidgets('최신순으로 처음엔 5행 — 오래된 순으로 들어온 목록을 뒤집는다', (tester) async {
      await tester.pumpWidget(host([
        for (var d = 1; d <= 7; d++) rec(id: 'i$d', day: d, source: 'member_self'),
      ]));

      expect(find.text('삭제'), findsNWidgets(InbodyRecentList.maxRows));
      expect(find.textContaining('8/7'), findsOneWidget, reason: '가장 최근 기록이 보여야 한다');
      expect(find.textContaining('8/1'), findsNothing, reason: '가장 오래된 기록은 접혀 있다');
    });
  });

  // 입력 시트는 2년 소급을 허용한다 — 5건 밖 날짜의 셀프 기록이 화면에 없으면
  // 지울 수 없고, 같은 날 409의 안내("기존 기록을 지우고 다시 저장해주세요")를
  // 따라갈 방법이 없어진다. 그래서 접힌 리스트는 반드시 전체로 열려야 한다.
  group('더 보기 — 5건 밖 기록에 도달 가능해야 한다', () {
    testWidgets('접혀 있으면 감춰진 건수를 말하는 더 보기가 있다', (tester) async {
      await tester.pumpWidget(host([
        for (var d = 1; d <= 7; d++) rec(id: 'i$d', day: d, source: 'member_self'),
      ]));

      expect(find.text('이전 기록 2건 더 보기'), findsOneWidget);
    });

    testWidgets('더 보기를 누르면 전체가 열리고, 가장 오래된 기록도 지울 수 있다', (tester) async {
      await tester.pumpWidget(host([
        for (var d = 1; d <= 7; d++) rec(id: 'i$d', day: d, source: 'member_self'),
      ]));

      await tester.tap(find.text('이전 기록 2건 더 보기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('8/1'), findsOneWidget, reason: '409가 지목할 수 있는 옛 기록에 도달해야 한다');
      expect(find.text('삭제'), findsNWidgets(7), reason: '펼친 뒤에는 모든 셀프 기록에 정정 경로가 붙는다');
      expect(find.textContaining('더 보기'), findsNothing, reason: '다 보여주고 있으면서 더 있다고 말하면 안 된다');

      // 펼친 목록의 옛 기록에서 삭제가 끝까지 동작하는지 — 도달 가능성은
      // 버튼이 그려지는 것이 아니라 요청이 나가는 것으로 증명된다.
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제하기'));
      await tester.pumpAndSettle();

      expect(repo.deletedIds, ['i1']);
    });

    testWidgets('5건 이하면 더 보기가 없다 — 감춘 게 없는데 있다고 말하지 않는다', (tester) async {
      await tester.pumpWidget(host([
        for (var d = 1; d <= 5; d++) rec(id: 'i$d', day: d, source: 'member_self'),
      ]));

      expect(find.textContaining('더 보기'), findsNothing);
    });
  });

  group('삭제 확인 — 비가역 동작', () {
    testWidgets('바로 지우지 않고 결과를 구체적으로 말한 뒤 확인받는다', (tester) async {
      await tester.pumpWidget(host([rec(id: 'i1', day: 17, source: 'member_self')]));

      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();

      expect(find.textContaining('2026-08-17 기록을 삭제할까요?'), findsOneWidget);
      expect(find.textContaining('되돌릴 수 없어요'), findsOneWidget);
      expect(find.textContaining('추이 그래프'), findsOneWidget);
      expect(repo.deletedIds, isEmpty, reason: '확인 전에는 요청이 나가지 않는다');
    });

    testWidgets('"아니요"면 아무 일도 일어나지 않는다', (tester) async {
      await tester.pumpWidget(host([rec(id: 'i1', day: 17, source: 'member_self')]));

      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('아니요'));
      await tester.pumpAndSettle();

      expect(repo.deletedIds, isEmpty);
    });

    testWidgets('"삭제하기"면 그 기록의 id로 요청하고 결과를 알린다', (tester) async {
      await tester.pumpWidget(host([rec(id: 'i1', day: 17, source: 'member_self')]));

      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제하기'));
      await tester.pumpAndSettle();

      expect(repo.deletedIds, ['i1']);
      expect(find.text('인바디 기록을 삭제했어요'), findsOneWidget);
    });

    testWidgets('삭제 실패는 실패라고 말한다 — 안 지워졌는데 지웠다고 하면 안 된다', (tester) async {
      await tester.pumpWidget(host([rec(id: 'i1', day: 17, source: 'member_self')]));
      repo.deleteFailure = const RejectedFailure('권한이 없어요');

      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제하기'));
      await tester.pumpAndSettle();

      expect(find.text('권한이 없어요'), findsOneWidget);
      expect(find.text('인바디 기록을 삭제했어요'), findsNothing);
    });
  });
}

class _FakeRecordsRepository implements RecordsRepository {
  final deletedIds = <String>[];
  Failure? deleteFailure;

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
  }) =>
      throw UnsupportedError('이 테스트는 삭제만 본다');

  @override
  Future<Result<void>> deleteInbody(String id) async {
    deletedIds.add(id);
    return deleteFailure == null ? const Ok(null) : Err(deleteFailure!);
  }
}
