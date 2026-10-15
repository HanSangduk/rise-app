// 대기실 접근성 회귀(P72) — 이 화면은 앱을 처음 깐 사람이 **가장 오래 머무는** 곳이고,
// PT 센터 회원에는 40~60대가 섞인다. 착수 시점 실태:
//   · `features/auth/` 전체에 `Semantics` **0건** — 스텝퍼가 어디까지 왔는지, 30초마다
//     바뀌는 확인 상태가 무엇인지 스크린리더에 한 마디도 안 갔다.
//   · 탭 타깃 3곳이 44dp 미달(주소 행 18dp · 매칭 카드 코치 행 26dp · 센터 선택 행 37.5dp).
//     같은 화면의 밑줄 링크·코치 줄·미리보기는 이미 44dp를 지키고 있었다 — 규약이 있는데
//     새로 붙은 자리들만 빠져 있었다.
//   · 10~10.5px 글자가 화면에 8개(iOS 11pt·Material 12sp 양쪽 미달).
//
// 대비비는 `test/core/theme/contrast_test.dart`가 따로 잰다(여기는 렌더 결과만).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/auth/presentation/center_confirm_screen.dart';
import 'package:rise_member/features/auth/presentation/center_contact_provider.dart';
import 'package:rise_member/features/auth/presentation/widgets/lobby_auto_check.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer.test(
      overrides: [
        staffMapProvider.overrideWith((ref) async => <String, StaffDto>{}),
        lobbyAutoCheckIntervalProvider.overrideWithValue(null),
        centerContactProvider.overrideWith(
          (ref, centerId) async => const CenterContact(
            name: '라이즈 컨디셔닝',
            address: '서울시 강남구 테헤란로 1',
          ),
        ),
      ],
    );
  });

  Future<void> pumpLobby(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const CenterConfirmScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('스크린리더 — 모양·색으로만 나르던 정보의 음성 대응', () {
    // 뮤테이션: `_StepSemantics`를 지우거나 `_StepStatus.semantics`를 빈 문자열로 만들면 죽는다.
    testWidgets('스텝퍼가 단계마다 상태어를 함께 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLobby(tester); // notFound

      expect(find.bySemanticsLabel('번호 인증, 완료'), findsOneWidget);
      expect(find.bySemanticsLabel('가입 요청, 현재 단계'), findsOneWidget);
      expect(find.bySemanticsLabel('센터 승인, 남은 단계'), findsOneWidget);
      expect(find.bySemanticsLabel('연결, 남은 단계'), findsOneWidget);

      handle.dispose();
    });

    // 뮤테이션: `CheckStatusLine`의 `Semantics(liveRegion: true)`를 벗기면 죽는다.
    testWidgets('확인 상태 줄은 liveRegion — 30초마다 바뀌는데 침묵하면 화면이 멈춘 줄 안다',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLobby(tester);

      final node = tester.getSemantics(find.text('아직 확인 전'));
      expect(node.flagsCollection.isLiveRegion, isTrue);

      handle.dispose();
    });
  });

  group('44dp 탭 타깃 — 규약이 있는데 새로 붙은 자리만 빠져 있었다', () {
    testWidgets('센터 카드 주소 행(종전 18dp)', (tester) async {
      await pumpLobby(tester);

      final row = find.ancestor(
        of: find.text('서울시 강남구 테헤란로 1'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(row.first).height, greaterThanOrEqualTo(44.0));
    });

    testWidgets('밑줄 링크는 종전대로 44dp를 지킨다(회귀 방지)', (tester) async {
      await pumpLobby(tester);

      for (final label in ['이용약관', '개인정보처리방침', '계정 삭제', '번호 다시 인증하기']) {
        final box = find.ancestor(of: find.text(label), matching: find.byType(ConstrainedBox));
        expect(tester.getSize(box.first).height, greaterThanOrEqualTo(44.0), reason: label);
      }
    });
  });

  group('글자 크기 하한 — iOS 11pt / Material 12sp', () {
    // 뮤테이션: 어느 fontSize든 10 또는 10.5로 되돌리면 죽는다. 착수 시점엔 8개였다.
    testWidgets('대기실에 11px 미만 글자가 없다', (tester) async {
      await pumpLobby(tester);

      final tooSmall = <String>[];
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final size = text.style?.fontSize;
        if (size != null && size < 11) tooSmall.add('"${text.data}" ${size}px');
      }
      expect(tooSmall, isEmpty, reason: '노안·헬스장 조명에서 읽을 수 없다: $tooSmall');
    });
  });
}
