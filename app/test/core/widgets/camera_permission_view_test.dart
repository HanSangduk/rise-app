import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/camera_permission_view.dart';

// QR 스캐너·체형 촬영이 공용하는 권한 안내의 **문장 조립**.
//
// 종전엔 "사진은 촬영 즉시 나와 담당 코치만 볼 수 있게 저장돼요"가 위젯에 박혀
// 있어 두 겹으로 거짓이었다: ① 서버 checkBodyPhotoAccess는 센터 대표(owner)도
// 동의가 유효하면 허용하므로 열람 범위를 좁혀 말했고, ② 사진을 저장하지도 않는
// QR 스캔 화면에까지 같은 문장이 붙었다. 그래서 뒤 문장(note)은 호출부가 자기
// 용도의 사실만 가져온다 — 여기서는 note가 있으면 붙고, 없으면 아무 말도
// 덧붙이지 않는 조립 규칙을 못 박는다.
void main() {
  Widget host({
    required CameraPermissionResult result,
    String? note,
  }) =>
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: CameraPermissionView(
            result: result,
            purpose: '체형 사진을 찍으려면',
            note: note,
            onRetry: () {},
            onOpenSettings: () {},
          ),
        ),
      );

  testWidgets('note가 있으면 요청 문장 뒤에 그대로 붙는다', (tester) async {
    await tester.pumpWidget(host(
      result: CameraPermissionResult.denied,
      note: '사진은 촬영 즉시 나와 담당 코치, 센터 대표만 볼 수 있게 저장돼요.',
    ));

    expect(
      find.text('체형 사진을 찍으려면 카메라 권한이 필요해요. '
          '사진은 촬영 즉시 나와 담당 코치, 센터 대표만 볼 수 있게 저장돼요.'),
      findsOneWidget,
    );
  });

  testWidgets('note가 없으면 아무 말도 덧붙이지 않는다 — 문장을 지어내지 않는다', (tester) async {
    await tester.pumpWidget(host(result: CameraPermissionResult.denied));

    expect(find.text('체형 사진을 찍으려면 카메라 권한이 필요해요.'), findsOneWidget);
    expect(find.textContaining('저장돼요'), findsNothing);
  });

  testWidgets('영구 거부에서는 note 대신 설정 경로만 말한다 — 유일한 다음 행동이 묻히면 안 된다', (tester) async {
    await tester.pumpWidget(host(
      result: CameraPermissionResult.permanentlyDenied,
      note: '사진은 촬영 즉시 나와 담당 코치, 센터 대표만 볼 수 있게 저장돼요.',
    ));

    expect(find.textContaining('설정 앱에서 이 앱의 카메라 권한을'), findsOneWidget);
    expect(find.textContaining('저장돼요'), findsNothing);
  });
}
