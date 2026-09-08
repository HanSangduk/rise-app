// 액션 실패 스낵바의 단일 지점 `showFailureSnackBar`(P64 검증 반영).
//
// 4탭 액션(체크인·예약 취소·인바디 삭제·사진 삭제·홈워크 토글)은 세션이 빈 채 눌리면
// `Err(SessionGoneFailure())`를 돌려주는데, 종전엔 그 메시지가 **danger 스낵바**로 떴다 —
// 리스너가 화면을 내리는 중에 "실패했으니 다시 시도"라는 색을 내보낸 셈이다.
//
// 뮤테이션: 헬퍼의 `is SessionGoneFailure` 가드를 지우면 첫 테스트가 죽는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';

void main() {
  Future<void> pumpAndFire(WidgetTester tester, Failure failure) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFailureSnackBar(context, failure),
              child: const Text('fire'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('fire'));
    await tester.pump();
  }

  testWidgets('SessionGoneFailure는 스낵바를 띄우지 않는다 — 리스너가 화면을 내리는 중', (tester) async {
    await pumpAndFire(tester, const SessionGoneFailure());

    expect(find.byType(SnackBar), findsNothing, reason: '재시도를 권하는 색이 나갔다');
  });

  testWidgets('그 밖의 실패는 서버 문구 그대로 danger 스낵바', (tester) async {
    await pumpAndFire(tester, const RejectedFailure('컷오프가 지났어요'));

    expect(find.text('컷오프가 지났어요'), findsOneWidget);
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, AppColors.badgeDanBg, reason: '실패 색이어야 문구를 안 읽어도 안다');
  });

  testWidgets('일반 AuthFailure는 건너뛰지 않는다 — 가드는 정확히 SessionGoneFailure만', (tester) async {
    await pumpAndFire(tester, const AuthFailure('인증번호가 틀렸어요'));

    expect(find.text('인증번호가 틀렸어요'), findsOneWidget);
  });
}
