import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/presentation/widgets/body_photo_timeline.dart';

// 체형사진 조회 실패가 "아직 촬영한 사진이 없어요 — 촬영 탭에서 첫 사진을
// 남겨보세요"로 렌더되던 문제. 이미 여러 장 찍어 둔 회원에게는 기록이 사라진
// 것처럼 보이고, 안내대로 다시 찍게 만든다(중복 촬영·중복 저장).
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  const emptyAlbum = BodyPhotoAlbum.empty;

  testWidgets('조회 실패면 실패 문구 — 첫 촬영 안내를 띄우지 않는다', (tester) async {
    await tester.pumpWidget(host(
      const BodyPhotoTimelineCard(album: emptyAlbum, failed: true),
    ));

    expect(find.textContaining('사진을 불러오지 못했어요'), findsOneWidget);
    expect(find.textContaining('아직 촬영한 사진이 없어요'), findsNothing);
  });

  testWidgets('진짜 0장이면 종전 빈 상태 문구 — "없음"과 "확인 실패"를 구분한다', (tester) async {
    await tester.pumpWidget(host(
      const BodyPhotoTimelineCard(album: emptyAlbum),
    ));

    expect(find.textContaining('아직 촬영한 사진이 없어요'), findsOneWidget);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
  });
}
