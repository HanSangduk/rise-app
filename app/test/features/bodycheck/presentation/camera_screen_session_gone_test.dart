// 촬영 화면이 `SessionGoneFailure`를 받았을 때의 스낵바(P64 검증 반영).
//
// 종전엔 error 리스너가 모든 실패를 danger 스낵바로 그려서, 세션이 빈 채 셔터를 누르면
// "실패했으니 다시 시도"라는 색과 함께 중립 문구가 떴다 — 리스너(`app.dart`)가 이 전체화면
// 라우트째 내리는 중이라 재시도는 세션을 만들지 못한다. 지금은 닫힘을 예고하고, 리스너가
// 이동하지 못했을 때를 위한 탈출 액션(`SessionGoneView`와 같은 라벨·같은 착지)을 단다.
//
// 뮤테이션: 리스너의 `is SessionGoneFailure` 분기를 지우면 첫 테스트가 죽는다(중립 문구가
// danger 색으로 뜬다).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/member_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/session/app_session.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/session/session_store.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/bodycheck/presentation/body_camera_provider.dart';
import 'package:rise_member/features/bodycheck/presentation/camera_screen.dart';
import 'package:rise_member/features/bodycheck/presentation/camera_view_model.dart';
import 'package:rise_member/features/bodycheck/presentation/level_simulator_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  const me = AppSession(uid: 'u1', role: 'member', centerId: 'c1', memberId: 'm1');

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer.test(
      overrides: [
        sessionStoreProvider.overrideWithValue(_NoopStore()),
        cameraPermissionGateProvider.overrideWithValue(_FakeGate()),
        accelerometerSourceProvider.overrideWithValue(
          () => const Stream<AccelerometerEvent>.empty(),
        ),
        bodyCameraProvider.overrideWith(_FakeBodyCamera.new),
        myProfileProvider.overrideWith(
          (ref) async => const MemberDto(
            id: 'm1',
            name: '람',
            phone: '01012345678',
            consent: ConsentDto(general: true, sensitive: true),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const CameraScreen()),
      ),
    );
    await tester.pump();
    // 뷰모델은 `myProfileProvider`를 watch한다 — 프로필 future가 셔터 **뒤에** 풀리면
    // 재빌드로 방금 세운 error가 씻긴다(camera_view_model_test와 같은 사정). 먼저 안착시킨다.
    await container.read(myProfileProvider.future);
    await tester.pump();
    return container;
  }

  testWidgets('세션이 빈 채 셔터 → danger 스낵바 대신 닫힘 예고 + 탈출 액션', (tester) async {
    final container = await pump(tester);
    container.read(sessionProvider.notifier).set(me);
    container.read(sessionProvider.notifier).clear(reason: SessionEndReason.notLinked);

    await container.read(cameraViewModelProvider.notifier).capture();
    await tester.pump();

    expect(container.read(cameraViewModelProvider).error, isA<SessionGoneFailure>());
    expect(find.text('로그인 정보가 바뀌어 촬영을 닫아요'), findsOneWidget);
    expect(find.text('로그인 정보가 바뀌어 화면을 다시 준비하고 있어요'), findsNothing,
        reason: 'SessionGoneFailure의 진단 문구가 그대로 노출됐다');
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, isNot(AppColors.badgeDanBg), reason: '실패·재시도의 색이 나갔다');
    expect(find.text('연결 상태 확인하러 가기'), findsOneWidget,
        reason: '탈출 액션은 SessionGoneView와 같은 규칙 — notLinked면 대기실 라벨');
    expect(find.text('로그인 화면으로'), findsNothing);
  });

  testWidgets('그 밖의 실패는 종전대로 danger 스낵바', (tester) async {
    final container = await pump(tester);
    container.read(sessionProvider.notifier).set(me);

    // 카메라가 바이트를 못 주는 경로 — RejectedFailure.
    await container.read(cameraViewModelProvider.notifier).capture();
    await tester.pump();

    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, AppColors.badgeDanBg);
    expect(find.textContaining('사진을 찍지 못했어요'), findsOneWidget);
  });
}

class _NoopStore implements SessionStore {
  @override
  Future<AppSession?> read(String uid) async => null;
  @override
  Future<void> write(AppSession session) async {}
  @override
  Future<void> clear() async {}
}

class _FakeGate implements CameraPermissionGate {
  @override
  Future<CameraPermissionResult> ensureGranted() async => CameraPermissionResult.denied;
  @override
  Future<void> openSettings() async {}
}

/// 프리뷰는 이 테스트의 관심사가 아니다 — 바이트도 주지 않는다(실패 경로용).
class _FakeBodyCamera extends BodyCamera {
  @override
  Future<BodyCameraState> build() async => const BodyCameraFailed('테스트 카메라');
  @override
  Future<Uint8List?> takeJpeg() async => null;
}
