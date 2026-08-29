import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/presentation/widgets/body_photo_timeline.dart';

// 기록 탭에서 **찍은 4종을 다 볼 수 있는지**.
//
// 카메라는 PoseSpec.fallbackSequence 4종을 전부 찍게 하는데 기록 탭은 ohsquat 하나만 보여줬다.
// 회원 입장에서는 4장을 찍었는데 1장만 남은 것으로 보인다(나머지는 저장은 됐지만
// 앱 어디에도 나타나지 않는다). 데이터 계층의 필터를 걷어내고 포즈 칩을 붙였다.
void main() {
  BodyPhotoEntry photo(String pose, int day) => BodyPhotoEntry(
        id: '$pose$day',
        memberId: 'm1',
        pose: pose,
        direction: BodyDirection.front,
        date: DateTime(2026, 8, day),
        blurred: false,
      );

  Future<void> pump(WidgetTester tester, List<BodyPhotoEntry> photos, {bool failed = false}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BodyPhotoTimelineCard(
              album: BodyPhotoAlbum.from(photos),
              failed: failed,
            ),
          ),
        ),
      ),
    );
  }

  /// 지금 나란히 떠 있는 사진 타일의 키. 날짜 문자열은 칩·타일 pill·스크러버 양 끝
  /// 라벨 **세 군데**에 나오므로 개수를 세면 레이아웃이 바뀔 때마다 깨진다. 키는
  /// storagePath라 어떤 사진이 떠 있는지를 정확히 말한다.
  List<String> tileKeys(WidgetTester tester) => tester
      .widgetList(find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('body-photo-tile-')))
      .map((w) => (w.key! as ValueKey<String>).value)
      .toList();

  testWidgets('포즈 칩 4종이 장수와 함께 뜬다 — 안 찍은 포즈도 목록에서 빼지 않는다', (tester) async {
    await pump(tester, [photo('stand', 1), photo('stand', 2), photo('fold', 3)]);

    // 0장 포즈를 감추면 회원은 그 포즈를 찍을 수 있다는 사실 자체를 모른다.
    expect(find.text('차렷 2'), findsOneWidget);
    expect(find.text('T자 0'), findsOneWidget);
    expect(find.text('전굴 1'), findsOneWidget);
    expect(find.text('OH스쿼트 0'), findsOneWidget);
  });

  testWidgets('첫 진입은 사진이 가장 많은 포즈 — ohsquat 고정이 아니다', (tester) async {
    // 종전 구현이면 이 회원의 첫 화면은 "아직 촬영한 사진이 없어요"였다.
    await pump(tester, [photo('stand', 1), photo('stand', 8)]);

    // 헤더 배지가 지금 보고 있는 포즈를 말한다.
    expect(find.text('차렷'), findsOneWidget);
    expect(find.textContaining('아직 촬영한 사진이 없어요'), findsNothing);
    // 비교 UI의 증거는 **두 장이 나란히 뜨는 것**이다. 종전엔 Slider의 존재로
    // 판정했는데, 그 슬라이더는 아무것도 하지 않는 죽은 컨트롤이었다 —
    // 존재가 곧 동작으로 취급돼 P31까지 아무도 못 잡았다.
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('body-photo-tile-')), findsNWidgets(2), reason: '2장이면 비교 UI가 떠야 한다');
  });

  testWidgets('다른 포즈 칩을 누르면 그 포즈의 타임라인으로 바뀐다', (tester) async {
    await pump(tester, [
      photo('stand', 1),
      photo('stand', 8),
      photo('ohsquat', 20),
      photo('ohsquat', 27),
    ]);
    expect(tileKeys(tester).every((k) => k.contains('stand')), isTrue,
        reason: '차렷 타임라인이 떠 있어야 한다');

    await tester.tap(find.text('OH스쿼트 2'));
    await tester.pumpAndSettle();

    expect(tileKeys(tester).every((k) => k.contains('ohsquat')), isTrue,
        reason: '포즈를 바꿨는데 이전 포즈 사진이 남아 있다');
  });

  testWidgets('사진이 없는 포즈로 옮기면 "그 포즈만 없다"고 말한다 — 전체가 없다고 하지 않는다', (tester) async {
    await pump(tester, [photo('stand', 1), photo('stand', 8)]);

    await tester.tap(find.text('전굴 0'));
    await tester.pumpAndSettle();

    expect(find.textContaining('전굴 사진은 아직 없어요'), findsOneWidget);
    expect(find.textContaining('아직 촬영한 사진이 없어요'), findsNothing);
  });

  testWidgets('한 장도 없으면 종전 첫 촬영 안내 그대로', (tester) async {
    await pump(tester, const []);

    expect(find.textContaining('아직 촬영한 사진이 없어요'), findsOneWidget);
    expect(find.textContaining('사진은 아직 없어요'), findsNothing);
  });

  testWidgets('조회 실패면 포즈 칩을 띄우지 않는다 — 전부 "0장"이 사실처럼 보인다', (tester) async {
    await pump(tester, [photo('stand', 1)], failed: true);

    expect(find.text('차렷 0'), findsNothing);
    expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('포즈를 바꾸면 날짜 선택도 그 포즈 기준으로 다시 잡힌다', (tester) async {
    // 5장짜리 포즈에서 고른 인덱스가 2장짜리 포즈에 그대로 남으면(clamp) 엉뚱한
    // 두 장이 선택된 것처럼 보인다.
    await pump(tester, [
      for (var d = 1; d <= 5; d++) photo('stand', d),
      photo('tpose', 20),
      photo('tpose', 21),
    ]);
    // 차렷에서 가운데 날짜를 「기준」으로 골라 둔다. 날짜 문자열은 칩 말고도
    // 타일 pill·스크러버 양 끝 라벨에 나오므로 탭은 칩으로 한정한다.
    await tester.tap(find.widgetWithText(RiseChip, '8/3'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('T자 2'));
    await tester.pumpAndSettle();

    // T자는 2장뿐 — 기준=8/20, 비교=8/21이 그대로 잡혀야 한다.
    final keys = tileKeys(tester);
    expect(keys, hasLength(2));
    expect(keys.first, contains('tpose'));
    expect(keys.first, isNot(keys.last),
        reason: '인덱스가 이전 포즈 값으로 clamp되면 같은 사진이 좌우에 온다');
  });
}
