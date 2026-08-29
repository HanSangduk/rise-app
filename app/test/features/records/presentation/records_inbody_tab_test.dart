import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/member_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/domain/records_repository.dart';
import 'package:rise_member/features/records/presentation/records_screen.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';

// 기록 탭 인바디 서브탭의 **배선**. 위젯 단위 테스트가 통과해도 화면이 그 위젯을
// 부르지 않으면 회원에겐 아무 변화가 없다 — 종전 상태가 정확히 그랬다(6지표가
// 도메인까지 다 와서 화면 직전에 버려졌다).
void main() {
  Widget host(List<InbodyRecord> inbody) {
    final container = ProviderContainer.test(
      overrides: [
        recordsRepositoryProvider.overrideWithValue(_FakeRecordsRepository(inbody)),
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
    container.read(selectedRecordsTabProvider.notifier).select(RecordsTab.inbody);
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const RecordsScreen()),
    );
  }

  InbodyRecord rec({
    required String id,
    required int day,
    double smm = 30,
    double pbf = 26,
    String? source,
  }) =>
      InbodyRecord(
        id: id,
        date: DateTime(2026, 8, day),
        weight: 70.2,
        smm: smm,
        bfm: 18.8,
        pbf: pbf,
        vfl: 8,
        bmr: 1420,
        source: source,
      );

  testWidgets('카드 헤더에 "기록 추가"가 있고 눌러 시트가 열린다', (tester) async {
    await tester.pumpWidget(host([]));
    await tester.pumpAndSettle();

    expect(find.text('기록 추가'), findsOneWidget);

    await tester.tap(find.text('기록 추가'));
    await tester.pumpAndSettle();

    expect(find.text('인바디 기록 추가'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(6));
  });

  testWidgets('기록이 없으면 빈 상태에서 다음 행동을 안내한다', (tester) async {
    await tester.pumpWidget(host([]));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 인바디 기록이 없어요'), findsOneWidget);
    expect(find.textContaining('기록 추가'), findsWidgets);
  });

  testWidgets('기록이 있으면 6지표 전부 + 직전 대비 델타 + 최근 기록이 함께 그려진다', (tester) async {
    await tester.pumpWidget(host([
      rec(id: 'i1', day: 1, smm: 30, pbf: 27),
      rec(id: 'i2', day: 17, smm: 30.4, pbf: 26.1, source: 'member_self'),
    ]));
    await tester.pumpAndSettle();

    // 6지표(종전엔 SMM/PBF 2행만 있었다)
    expect(find.text('체중'), findsOneWidget);
    expect(find.text('체지방량(BFM)'), findsOneWidget);
    expect(find.text('내장지방(VFL)'), findsOneWidget);
    expect(find.text('기초대사량(BMR)'), findsOneWidget);
    // 직전(8/1) 대비 델타 — 최신 기록이 마지막 원소라는 정렬 규약에 의존한다.
    expect(find.text('▲0.4'), findsOneWidget);
    expect(find.text('▼0.9'), findsOneWidget);
    // 정정 경로
    expect(find.text('최근 기록'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);
  });

  testWidgets('기록이 1건이면 델타를 그리지 않는다 — 비교 대상이 없다', (tester) async {
    await tester.pumpWidget(host([rec(id: 'i1', day: 17)]));
    await tester.pumpAndSettle();

    expect(find.textContaining('▲'), findsNothing);
    expect(find.textContaining('▼'), findsNothing);
  });
}

class _FakeRecordsRepository implements RecordsRepository {
  _FakeRecordsRepository(this.inbody);

  /// 오래된 순(RecordsData 규약).
  final List<InbodyRecord> inbody;

  @override
  Future<Result<RecordsData>> load(String memberId) async => Ok(RecordsData(
        workoutLogs: const [],
        homeworkWeeks: const [],
        inbodyRecords: inbody,
        bodyPhotos: BodyPhotoAlbum.empty,
      ));

  @override
  Future<Result<void>> createInbody({
    required String memberId,
    required InbodyDraft draft,
  }) async =>
      const Ok(null);

  @override
  Future<Result<void>> deleteInbody(String id) async => const Ok(null);
}
