import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/booking/presentation/widgets/trainer_profile_sheet.dart';

// 계약 v2.0 보완 — 프로필 시트의 "빈 프로필" 안내가 원인을 구분하지 못하던 문제.
//
// 계약상 role=member 응답은 inactive 스태프의 profile을 **빈 객체로 마스킹**한다.
// 예전 시트는 빈 프로필을 캐시 미로드와 미등록 둘로만 갈랐기 때문에, 퇴사한 코치를
// 열면 "불러오지 못했어요 — 새로고침"으로 안내해 정상 응답을 네트워크 오류로
// 오인시켰다(될 리 없는 새로고침을 반복하게 된다).
//
// 안내 우선순위: 퇴사 > 캐시 미로드 > 실제 미등록.
void main() {
  const active = StaffDto(uid: 't1', name: '정혜린');
  const retired = StaffDto(uid: 't1', name: '정혜린', status: 'inactive');

  Future<void> openSheet(
    WidgetTester tester, {
    required StaffDto staff,
    bool profileUnavailable = false,
  }) async {
    await tester.pumpWidget(
      // showRiseSheet는 세션 감시자(_SessionSheetGuard)를 달아 연다 — 앱과 같은 DI 루트가 필요하다.
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showTrainerProfileSheet(
                  context,
                  staff: staff,
                  profileUnavailable: profileUnavailable,
                ),
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

  testWidgets('퇴사한 코치 — "불러오지 못했어요"가 아니라 퇴사 안내 + 퇴사 배지', (tester) async {
    await openSheet(tester, staff: retired);

    expect(find.textContaining('활동하지 않는 코치'), findsOneWidget);
    expect(find.text('퇴사'), findsOneWidget);
    // 이름은 계약대로 그대로 남는다(이름 해석 보존).
    expect(find.text('정혜린'), findsOneWidget);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
    expect(find.textContaining('아직 소개가 등록되지 않았어요'), findsNothing);
  });

  testWidgets('퇴사 + left_at — 퇴사 시점을 함께 안내', (tester) async {
    await openSheet(
      tester,
      staff: const StaffDto(
        uid: 't1',
        name: '정혜린',
        status: 'inactive',
        leftAt: '2026-08-22T09:00:00Z',
      ),
    );

    expect(find.textContaining('2026년 8월에 퇴사한 코치'), findsOneWidget);
  });

  testWidgets('캐시 미로드 폴백 — 재시도 안내(현직·빈 프로필)', (tester) async {
    await openSheet(tester, staff: active, profileUnavailable: true);

    expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    expect(find.text('퇴사'), findsNothing);
  });

  testWidgets('현직인데 소개 미등록 — 미등록 안내(재시도 안내 아님)', (tester) async {
    await openSheet(tester, staff: active);

    expect(find.text('아직 소개가 등록되지 않았어요'), findsOneWidget);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
  });

  testWidgets('퇴사가 캐시 미로드보다 우선 — 확정 사실을 먼저 말한다', (tester) async {
    // 캐시에서 실제 StaffDto를 받아 퇴사임을 아는데 호출부가 플래그를 잘못 넘긴
    // 경우에도, "새로고침하면 나올지도 모른다"고 오해시키지 않는다.
    await openSheet(tester, staff: retired, profileUnavailable: true);

    expect(find.textContaining('활동하지 않는 코치'), findsOneWidget);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
  });

  testWidgets('퇴사여도 프로필이 남아 있으면 내용은 그대로 보여준다', (tester) async {
    // 구버전 서버·마스킹 전 응답 방어 — 안내는 위에 붙고 소개는 숨기지 않는다.
    await openSheet(
      tester,
      staff: const StaffDto(
        uid: 't1',
        name: '정혜린',
        status: 'inactive',
        profile: StaffProfileDto(title: '퍼포먼스 트레이너', bio: '여성 회원 비율 80%.'),
      ),
    );

    expect(find.text('퇴사'), findsOneWidget);
    expect(find.textContaining('활동하지 않는 코치'), findsOneWidget);
    expect(find.text('여성 회원 비율 80%.'), findsOneWidget);
  });

  testWidgets('현직 + 소개 있음 — 안내 문구 없이 프로필만', (tester) async {
    await openSheet(
      tester,
      staff: const StaffDto(
        uid: 't1',
        name: '정혜린',
        profile: StaffProfileDto(title: '퍼포먼스 트레이너', careerYears: 7),
      ),
    );

    expect(find.text('퍼포먼스 트레이너 · 7년차'), findsOneWidget);
    expect(find.text('퇴사'), findsNothing);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
    expect(find.textContaining('아직 소개가'), findsNothing);
  });
}
