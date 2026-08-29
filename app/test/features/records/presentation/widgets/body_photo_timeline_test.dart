import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/presentation/widgets/body_photo_timeline.dart';

// 체형 비교 타임라인의 "비교할 게 있는가" 가드.
//
// 사진이 1장일 때 `_beforeIndex=0`, `_afterIndex = n>0 ? n-1 : 0`이 **둘 다 0**이 되어
// 같은 사진을 좌우에 놓고 슬라이더까지 정상처럼 그렸다(자기 자신과 비교).
// 같은 탭의 인바디 추이는 "2회 이상 필요해요"로 같은 상황을 막고 있어 비대칭이었다
// (inbody_chart.dart) — 그 패턴에 맞춘다.
void main() {
  BodyPhotoEntry photo(int day) => BodyPhotoEntry(
        id: 'p$day',
        memberId: 'm1',
        pose: 'ohsquat',
        direction: BodyDirection.front,
        date: DateTime(2026, 8, day),
        blurred: false,
      );

  Future<void> pump(WidgetTester tester, List<BodyPhotoEntry> entries, {bool failed = false}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BodyPhotoTimelineCard(
              album: BodyPhotoAlbum.from(entries),
              failed: failed,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('사진 1장 — 비교 UI를 그리지 않는다', (tester) async {
    await pump(tester, [photo(14)]);

    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('body-photo-tile-')), findsOneWidget);
    expect(find.textContaining('사진이 2장 이상 필요해요'), findsOneWidget);
  });

  testWidgets('사진 1장 — 찍은 한 장은 그대로 보여준다(감추지 않는다)', (tester) async {
    await pump(tester, [photo(14)]);

    // 날짜 라벨이 정확히 한 번 — 좌우 두 칸에 같은 사진이 겹쳐 뜨던 게 문제였다.
    expect(find.text('8/14'), findsOneWidget);
    expect(find.textContaining('아직 촬영한 사진이 없어요'), findsNothing);
  });

  testWidgets('사진 2장 — 비교 UI가 정상 복귀한다(가드가 과잉 차단하지 않는다)', (tester) async {
    await pump(tester, [photo(14), photo(21)]);

    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('body-photo-tile-')), findsNWidgets(2));
    expect(find.textContaining('사진이 2장 이상 필요해요'), findsNothing);
    // 기준(8/14) / 비교(8/21)가 **서로 다른 사진**으로 떠야 비교다. 날짜 문자열
    // 개수를 세지 않는 이유는 같은 날짜가 칩·타일 pill·스크러버 양 끝 라벨 세 군데에
    // 나오기 때문이다 — 레이아웃이 바뀔 때마다 숫자가 틀려지는 계약은 잠금이 아니다.
    final keys = tester
        .widgetList(find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('body-photo-tile-')))
        .map((w) => (w.key! as ValueKey<String>).value)
        .toList();
    expect(keys.first, isNot(keys.last));
  });

  testWidgets('사진 0장 — 기존 빈 상태 문구 유지', (tester) async {
    await pump(tester, const []);

    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('body-photo-tile-')), findsNothing);
    expect(find.textContaining('아직 촬영한 사진이 없어요'), findsOneWidget);
    expect(find.textContaining('사진이 2장 이상 필요해요'), findsNothing);
  });

  testWidgets('조회 실패는 "1장" 안내로 위장되지 않는다', (tester) async {
    await pump(tester, [photo(14)], failed: true);

    expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    expect(find.textContaining('사진이 2장 이상 필요해요'), findsNothing);
    // 실패 상태에서는 타일도 그리지 않는다 — 사진 한 장을 띄우면 "일부는 왔다"로
    // 읽혀 실패가 부분 성공으로 위장된다.
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('body-photo-tile-')), findsNothing);
  });
}
