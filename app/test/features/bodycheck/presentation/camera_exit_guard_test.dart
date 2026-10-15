// 촬영 화면을 **떠나는 판정**(P8 민감정보 유실 방지).
//
// 이 화면에서 나가는 길은 둘이다 — 프리뷰 위 X와 시스템 뒤로가기. 둘의 판정이 갈리면
// 그 한쪽으로만 사진이 조용히 사라진다: 종전 `_handleClose`는 `pendingRetry`만 봐서,
// "이 사진으로 저장" 직후 스피너가 도는 동안(`submitting`) X를 누르면 확인 한 번 없이
// 닫혔다. 그 순간 `review`는 이미 비워졌고 `pendingRetry`는 아직 안 세워진 틈이라 어느
// 조건에도 걸리지 않았고, 실패해도 재시도 배너를 띄울 화면이 이미 없었다.
//
// 뮤테이션: `canPop`이나 `_handleClose`에서 `submitting`을 빼면 첫 두 테스트가 죽는다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/member_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/features/bodycheck/presentation/camera_screen.dart';
import 'package:rise_member/features/bodycheck/presentation/camera_view_model.dart';
import 'package:rise_member/features/bodycheck/presentation/level_simulator_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  /// `pumpAndSettle`을 쓸 수 없다 — 제출 중에는 셔터의 스피너가 영원히 돈다.
  /// 전환·대화상자 애니메이션이 끝날 만큼만 시간을 밀어 준다.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 시스템 뒤로가기(안드로이드 백·iOS 스와이프가 타는 같은 채널).
  Future<void> pressSystemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await settle(tester);
  }

  /// 촬영 화면을 **push해서** 연다 — 닫힘 여부를 관측하려면 뒤에 남을 화면이 있어야 한다.
  Future<void> pushCamera(WidgetTester tester, {bool submitting = false}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cameraPermissionGateProvider.overrideWithValue(const _FakeGate()),
          accelerometerSourceProvider.overrideWithValue(
            () => const Stream<AccelerometerEvent>.empty(),
          ),
          myProfileProvider.overrideWith(
            (ref) async => const MemberDto(
              id: 'm1',
              name: '람',
              phone: '01012345678',
              consent: ConsentDto(general: true, sensitive: true),
            ),
          ),
          if (submitting) cameraViewModelProvider.overrideWith(_SubmittingViewModel.new),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const CameraScreen()),
                  ),
                  child: const Text('촬영 열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('촬영 열기'));
    await settle(tester);
  }

  testWidgets('저장 왕복 중 X — 확인 없이 닫히지 않는다', (tester) async {
    await pushCamera(tester, submitting: true);

    await tester.tap(find.byTooltip('닫기'));
    await settle(tester);

    expect(find.text('저장 중이에요 — 나갈까요?'), findsOneWidget);
    expect(find.textContaining('지금 나가면 저장이 끝나지 않고'), findsOneWidget);
    expect(find.text('촬영 열기'), findsNothing, reason: '확인도 없이 화면이 닫혔다');
  });

  testWidgets('저장 왕복 중 뒤로가기도 같은 판정을 거친다 — 두 경로가 갈리면 안 된다', (tester) async {
    await pushCamera(tester, submitting: true);

    await pressSystemBack(tester);

    expect(find.text('저장 중이에요 — 나갈까요?'), findsOneWidget);
    expect(find.text('촬영 열기'), findsNothing, reason: '뒤로가기가 확인 없이 화면을 닫았다');
  });

  testWidgets('확인 대화상자의 "나가기"는 실제로 닫는다 — 가두는 화면이 되면 안 된다', (tester) async {
    await pushCamera(tester, submitting: true);

    await tester.tap(find.byTooltip('닫기'));
    await settle(tester);
    await tester.tap(find.text('나가기'));
    await settle(tester);

    expect(find.text('촬영 열기'), findsOneWidget);
  });

  testWidgets('잃을 것이 없으면 X는 종전대로 곧장 닫는다 — 회귀 없음', (tester) async {
    await pushCamera(tester);

    await tester.tap(find.byTooltip('닫기'));
    await settle(tester);

    expect(find.text('촬영 열기'), findsOneWidget);
    expect(find.textContaining('나갈까요?'), findsNothing);
  });
}

/// 스피너가 도는 그 순간을 고정한다 — `review`는 이미 비었고 `pendingRetry`는 아직 없다.
class _SubmittingViewModel extends CameraViewModel {
  @override
  CameraState build() {
    super.build();
    return const CameraState(submitting: true);
  }
}

class _FakeGate implements CameraPermissionGate {
  const _FakeGate();
  @override
  Future<CameraPermissionResult> ensureGranted() async => CameraPermissionResult.denied;
  @override
  Future<void> openSettings() async {}
}
