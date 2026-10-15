// 홈 담당 코치 카드(P30).
//
// 서버는 `GET /v1/staff`로 회원에게 사진·직함·연차·전문분야·자격·수상·소개를 **전부**
// 내려주고, 그 호출은 홈 로드의 첫 번째다. 그런데 홈은 여태 `name` 하나만 썼다.
// 프로필 시트도 이미 있고 네트워크 0이다 — 이 카드는 새 요청도 새 서버 작업도 없다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/home/presentation/widgets/home_coach_card.dart';

import '../../../../support/font_loader.dart';

void main() {
  setUpAll(loadPretendard);

  const full = StaffDto(
    uid: 't1',
    name: '정혜린',
    color: '#f43f5e',
    profile: StaffProfileDto(
      photoUrl: '',
      title: '헤드 트레이너',
      careerYears: 8,
      specialties: ['체형교정', '근력강화', '재활운동', '다이어트'],
      bio: '안녕하세요',
    ),
  );

  Future<void> pump(
    WidgetTester tester, {
    Map<String, StaffDto>? staffMap,
    bool inactive = false,
    double width = 360,
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffMapProvider.overrideWith((ref) async => staffMap ?? const {}),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SingleChildScrollView(
                child: HomeCoachCard(
                  trainerId: 't1',
                  trainerName: '정혜린',
                  trainerInactive: inactive,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('프로필이 있을 때', () {
    testWidgets('이름·직함·연차·전문분야를 보여준다', (tester) async {
      await pump(tester, staffMap: {'t1': full});

      expect(find.text('담당 코치'), findsOneWidget);
      expect(find.text('정혜린'), findsOneWidget);
      expect(find.text('헤드 트레이너 · 8년차'), findsOneWidget);
      expect(find.text('체형교정'), findsOneWidget);
    });

    testWidgets('전문분야는 3개까지 — 카드가 프로필 시트를 대신하려 들면 안 된다', (tester) async {
      await pump(tester, staffMap: {'t1': full});

      expect(find.text('재활운동'), findsOneWidget);
      expect(find.text('다이어트'), findsNothing, reason: '4번째는 시트에서 본다');
    });

    testWidgets('탭하면 프로필 시트가 열린다', (tester) async {
      await pump(tester, staffMap: {'t1': full});

      await tester.tap(find.text('정혜린'));
      await tester.pumpAndSettle();

      // 시트에만 있는 항목으로 확인 — 카드에는 소개가 없다.
      expect(find.text('안녕하세요'), findsOneWidget);
    });
  });

  group('프로필이 비었을 때 — 세 가지 이유를 뭉치지 않는다', () {
    testWidgets('캐시 미로드는 "불러오지 못했어요"라고 말한다', (tester) async {
      // 조용히 이름만 보여주면 회원은 코치가 소개를 안 쓴 줄 안다.
      await pump(tester, staffMap: const {});

      expect(find.text('정혜린'), findsOneWidget);
      expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    });

    // 문구가 "탭해서 다시 시도"라고 약속하면 탭은 실제로 다시 읽어야 한다. 종전엔
    // 캐시가 없어도 프로필 시트를 열었고, 그 시트는 같은 실패 캐시로 만들어져
    // "새로고침 후 다시 시도해주세요"라며 회원을 홈으로 되돌렸다 — 약속한 행동과
    // 실제 동작이 갈려, 회원은 같은 실패를 한 겹 더 보고 돌아왔다.
    //
    // 뮤테이션: 탭 핸들러의 invalidate를 지우면 로드 수가 1에 멈춘다.
    testWidgets('"탭해서 다시 시도"는 진짜로 다시 읽는다 — 실패 시트로 보내지 않는다', (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staffMapProvider.overrideWith((ref) async {
              loads++;
              return const <String, StaffDto>{};
            }),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: HomeCoachCard(trainerId: 't1', trainerName: '정혜린'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loads, 1);

      await tester.tap(find.textContaining('탭해서 다시 시도'));
      await tester.pump();

      expect(loads, 2, reason: '재조회 없이 같은 실패 캐시를 다시 보여줬다');
      expect(find.text('프로필을 불러오는 중이에요'), findsOneWidget,
          reason: '탭이 먹혔다는 유일한 피드백');

      await tester.pumpAndSettle();
      expect(find.textContaining('새로고침 후 다시 시도'), findsNothing,
          reason: '실패 캐시로 만든 프로필 시트가 열렸다 — 회원을 홈으로 되돌리는 그 경로');
    });

    testWidgets('현직인데 소개 미등록이면 빈 줄을 만들지 않는다', (tester) async {
      await pump(tester, staffMap: {
        't1': const StaffDto(uid: 't1', name: '정혜린'),
      });

      expect(find.text('정혜린'), findsOneWidget);
      expect(find.textContaining('불러오지 못했어요'), findsNothing);
      expect(find.textContaining('년차'), findsNothing);
    });

    testWidgets('퇴사면 배지를 단다', (tester) async {
      await pump(tester, staffMap: {
        't1': const StaffDto(uid: 't1', name: '정혜린', status: 'inactive'),
      });
      expect(find.text('퇴사'), findsOneWidget);
    });

    testWidgets('패스가 퇴사라고 하면 캐시가 현직이어도 퇴사로 본다', (tester) async {
      // 서버가 규칙을 어겼을 때 이름만 멀쩡히 보여주지 않기 위한 방어.
      await pump(tester, staffMap: {'t1': full}, inactive: true);
      expect(find.text('퇴사'), findsOneWidget);
    });
  });

  group('레이아웃', () {
    testWidgets('320dp · 배율 1.35에서 넘치지 않는다', (tester) async {
      await pump(tester, staffMap: {'t1': full}, width: 320, scale: 1.35);
      expect(tester.takeException(), isNull);
    });

    testWidgets('탭 타깃이 44dp 이상이다', (tester) async {
      await pump(tester, staffMap: {'t1': full});

      final row = find.ancestor(
        of: find.text('정혜린'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(row.first).height, greaterThanOrEqualTo(44));
    });
  });
}
