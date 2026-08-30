import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/my/presentation/widgets/center_coaches_sheet.dart';

// P40 — 센터 코치 소개 목록. 계약 규약(staff_directory.dart): 이름 해석은 퇴사자
// 포함 전원, "현직만 뜻하는 자리"는 클라이언트가 isInactive로 거른다 — 이 목록이
// 정확히 그 자리다.
void main() {
  const owner = StaffDto(
    uid: 'owner1',
    role: 'owner',
    name: '박관장',
    profile: StaffProfileDto(title: '대표 · 헤드 코치', careerYears: 12),
  );
  const t1 = StaffDto(
    uid: 't1',
    name: '정혜린',
    profile: StaffProfileDto(
      title: '퍼포먼스 트레이너',
      careerYears: 7,
      specialties: ['여성 근력', '체형 교정'],
      bio: '여성 회원 비율 80%.',
    ),
  );
  const t3 = StaffDto(
    uid: 't3',
    name: '이수민',
    profile: StaffProfileDto(title: '모빌리티 코치', careerYears: 4),
  );
  const retired = StaffDto(uid: 't9', name: '한퇴사', status: 'inactive');

  Future<void> openSheet(
    WidgetTester tester, {
    required Future<Map<String, StaffDto>> Function() load,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        // Riverpod 3 기본 재시도(backoff)를 끈다 — 켜 두면 실패 상태가 테스트
        // 도중 자동 재시도로 성공으로 바뀌어 에러 UI 검증이 비결정적이 된다.
        retry: (retryCount, error) => null,
        overrides: [staffMapProvider.overrideWith((ref) => load())],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCenterCoachesSheet(context),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('현직 코치만 보이고 퇴사자는 목록에서 빠진다', (tester) async {
    await openSheet(
      tester,
      load: () async => {'t1': t1, 't9': retired, 'owner1': owner, 't3': t3},
    );

    expect(find.text('정혜린'), findsOneWidget);
    expect(find.text('이수민'), findsOneWidget);
    expect(find.text('박관장'), findsOneWidget);
    expect(find.text('한퇴사'), findsNothing);
    // 직함·연차 조립은 프로필 시트와 같은 규칙.
    expect(find.text('퍼포먼스 트레이너 · 7년차'), findsOneWidget);
    expect(find.text('여성 근력 · 체형 교정'), findsOneWidget);
  });

  testWidgets('관장이 목록 맨 위 — 열 때마다 순서가 흔들리지 않는다', (tester) async {
    await openSheet(
      tester,
      load: () async => {'t3': t3, 't1': t1, 'owner1': owner},
    );

    final ownerY = tester.getTopLeft(find.text('박관장')).dy;
    final t1Y = tester.getTopLeft(find.text('정혜린')).dy;
    final t3Y = tester.getTopLeft(find.text('이수민')).dy;
    expect(ownerY, lessThan(t1Y));
    // 트레이너끼리는 이름순(이수민 < 정혜린).
    expect(t3Y, lessThan(t1Y));
  });

  testWidgets('행을 탭하면 그 코치의 프로필 시트가 열린다', (tester) async {
    await openSheet(tester, load: () async => {'t1': t1, 'owner1': owner});

    await tester.tap(find.text('정혜린'));
    await tester.pumpAndSettle();

    // 프로필 시트에만 있는 내용(bio)으로 열림을 확인 — 목록 행에는 bio가 없다.
    expect(find.text('여성 회원 비율 80%.'), findsOneWidget);
  });

  testWidgets('로드 실패 — 오류를 위장하지 않고 다시 시도를 준다', (tester) async {
    var calls = 0;
    await openSheet(
      tester,
      load: () {
        calls++;
        if (calls == 1) return Future.error(Exception('network'));
        return Future.value({'t1': t1});
      },
    );

    expect(find.text('코치 목록을 불러오지 못했어요'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('정혜린'), findsOneWidget);
  });

  testWidgets('현직이 아무도 없으면 빈 상태 문구', (tester) async {
    await openSheet(tester, load: () async => {'t9': retired});

    expect(find.text('등록된 코치가 없어요'), findsOneWidget);
  });

  testWidgets('시트를 연 채 캐시가 만료(invalidate)돼도 목록이 유지된다 — 재조회 실패조차 목록을 덮지 않는다', (
    tester,
  ) async {
    var calls = 0;
    await openSheet(
      tester,
      load: () {
        calls++;
        // 첫 로드는 성공, TTL/invalidate 재조회는 실패 — staffMap은 15분 TTL로
        // invalidateSelf가 도는 캐시라 시트가 열린 동안 실제로 일어나는 시나리오다.
        if (calls == 1) return Future.value({'t1': t1});
        return Future.error(Exception('network'));
      },
    );
    expect(find.text('정혜린'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('정혜린')),
    );
    container.invalidate(staffMapProvider);
    await tester.pumpAndSettle();

    // 이전 값을 품은 AsyncLoading/AsyncError — 스피너·에러로 교체되면 안 된다.
    expect(find.text('정혜린'), findsOneWidget);
    expect(find.text('코치 목록을 불러오지 못했어요'), findsNothing);
  });

  testWidgets('직함·연차가 둘 다 없는 현직 코치 — 역할명 폴백으로 줄이 비지 않는다', (tester) async {
    const bare = StaffDto(uid: 't5', name: '신입코치');
    const bareOwner = StaffDto(uid: 'o2', role: 'owner', name: '민관장');
    await openSheet(tester, load: () async => {'t5': bare, 'o2': bareOwner});

    expect(find.text('코치'), findsOneWidget);
    expect(find.text('관장'), findsOneWidget);
  });

  testWidgets('320dp 좁은 폭 + 긴 이름·직함 — 오버플로 없이 말줄임', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const long = StaffDto(
      uid: 't7',
      name: '알렉산드리아크리스티나김박이최정혜린',
      profile: StaffProfileDto(
        title: '시니어 퍼포먼스 앤 컨디셔닝 헤드 트레이너 디렉터',
        careerYears: 15,
        specialties: ['여성 근력', '체형 교정', '산전 산후', '재활', '바디 리컴포지션'],
      ),
    );
    await openSheet(tester, load: () async => {'t7': long});

    // 오버플로 예외가 나면 테스트 프레임워크가 실패시킨다 — 렌더만 확인.
    expect(find.textContaining('알렉산드리아'), findsOneWidget);
  });
}
