import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/api/dto/member_dto.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/permissions/camera_permission.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/bodycheck/presentation/body_camera_provider.dart';
import 'package:rise_member/features/bodycheck/presentation/camera_screen.dart';
import 'package:rise_member/features/bodycheck/presentation/level_simulator_provider.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/grid_overlay.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/pose_sequence_chips.dart';
import 'package:sensors_plus/sensors_plus.dart';

// 하드웨어가 없거나 권한이 거부된 상태에서 **촬영 화면이 깨지지 않는지**.
//
// 오버레이(그리드·포즈칩·안내문)는 목업 1:1 이식이라 카메라와 무관하게 항상
// 그려져야 한다 — 프리뷰 자리가 비었다고 화면 전체가 에러로 떨어지면, 권한을
// 거부한 회원은 무엇을 해야 하는지도 못 본다.
void main() {
  late _FakeGate gate;

  Future<void> pump(
    WidgetTester tester, {
    required CameraPermissionResult permission,
    bool settle = true,
    Size size = const Size(1080, 2400),
    double dpr = 3.0,
    double scale = 1.0,
    List<BodyPoseDto>? poses,
  }) async {
    // 기본 뷰포트(800x600)에서는 카메라 프레임만으로 화면이 차서 포즈 칩이 아예
    // 빌드되지 않는다(ListView는 화면 밖 자식을 만들지 않는다) — 실기기 크기로.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    gate = _FakeGate(permission);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cameraPermissionGateProvider.overrideWithValue(gate),
          // 센서 플러그인을 건드리지 않는다(level_simulator_provider 주석).
          accelerometerSourceProvider.overrideWithValue(
            () => const Stream<AccelerometerEvent>.empty(),
          ),
          myProfileProvider.overrideWith(
            (ref) async => MemberDto(
              id: 'm1',
              name: '람',
              phone: '01012345678',
              consent: const ConsentDto(general: true, sensitive: true),
              bodyPoses: poses,
            ),
          ),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(theme: buildAppTheme(), home: const CameraScreen()),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('권한 일시 거부 — 다시 물어보는 버튼이 뜨고 오버레이는 그대로', (tester) async {
    await pump(tester, permission: CameraPermissionResult.denied);

    expect(find.text('카메라 권한이 필요해요'), findsOneWidget);
    expect(find.text('권한 허용하기'), findsOneWidget);
    expect(find.text('설정 열기'), findsNothing);

    // 열람 범위는 서버 checkBodyPhotoAccess 그대로 말한다 — 본인 · 담당 코치 ·
    // 센터 대표(동의 유효 시). 종전의 "나와 담당 코치만"은 대표를 숨긴 거짓이었다.
    expect(
      find.textContaining('나와 담당 코치, 센터 대표만 볼 수 있게 저장돼요'),
      findsOneWidget,
    );
    expect(find.textContaining('담당 코치만'), findsNothing);

    // 오버레이·컨트롤은 살아 있다.
    expect(find.byType(GridOverlay), findsOneWidget);
    expect(find.text('1 차렷'), findsOneWidget);
    expect(find.text('기준선 초기화'), findsOneWidget);

    // 목업의 "기울기 시뮬"은 실기기에서 수평계를 3.4°로 잠가 자동촬영을 죽인다 —
    // 화면에 다시 올라오면 안 된다.
    expect(find.text('기울기 시뮬'), findsNothing);
  });

  testWidgets('영구 거부 — 설정으로 보내는 버튼만 뜬다(눌러도 안 되는 버튼 금지)', (tester) async {
    await pump(tester, permission: CameraPermissionResult.permanentlyDenied);

    expect(find.text('카메라 권한이 꺼져 있어요'), findsOneWidget);
    expect(find.text('설정 열기'), findsOneWidget);
    expect(find.text('권한 허용하기'), findsNothing);
  });

  testWidgets('설정 열기를 누르면 설정 앱 경로가 호출된다', (tester) async {
    await pump(tester, permission: CameraPermissionResult.permanentlyDenied);

    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();

    expect(gate.openedSettings, isTrue);
  });

  testWidgets('"권한 허용하기"는 다시 물어본다(재요청 경로가 죽어 있지 않다)', (tester) async {
    await pump(tester, permission: CameraPermissionResult.denied);
    expect(gate.requests, 1);

    await tester.tap(find.text('권한 허용하기'));
    await tester.pumpAndSettle();

    expect(gate.requests, 2);
  });

  // 영구 거부에서 이 화면이 주는 유일한 다음 행동은 "설정 열기"다. 설정에서 켜고
  // 돌아왔는데 옛 판정이 그대로면 회원은 **이미 켠 설정을 또 여는 버튼** 앞에 갇힌다 —
  // 앱으로 돌아오는 것만으로 복구돼야 한다.
  //
  // 뮤테이션: `didChangeAppLifecycleState`의 invalidate를 지우면 요청 수가 1에 멈춘다.
  testWidgets('설정에서 켜고 돌아오면 권한을 다시 확인한다 — 같은 화면에 갇히지 않는다', (tester) async {
    await pump(tester, permission: CameraPermissionResult.permanentlyDenied);
    expect(gate.requests, 1);

    await _backgroundAndReturn(tester);

    expect(gate.requests, greaterThan(1), reason: '복귀 시 권한을 다시 묻지 않으면 화면이 스스로 못 푼다');
  });

  // 머리 주석은 "포그라운드를 잃으면 구독 0이 되어 카메라가 정리된다"고 적었지만,
  // `build()`가 프레임 비율 하나를 `active` 게이팅 없이 watch해서 구독이 0이 되지
  // 않았다 — 홈 버튼을 눌러도 카메라가 계속 열려 배터리·발열이 샜다(주석과 동작 불일치).
  //
  // 뮤테이션: `previewAspect`의 `active ? …` 게이팅을 지우면 이 테스트가 죽는다.
  testWidgets('백그라운드로 가면 카메라 provider가 실제로 폐기된다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer.test(
      overrides: [
        cameraPermissionGateProvider.overrideWithValue(_FakeGate(CameraPermissionResult.denied)),
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
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const CameraScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.exists(bodyCameraProvider), isTrue, reason: '전제가 깨졌다 — 열려 있어야 한다');

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    // riverpod 3의 autoDispose 정리는 구독이 0이 된 **뒤 프레임**에 돈다 — 즉시가 아니다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.exists(bodyCameraProvider), isFalse,
        reason: '구독이 남아 카메라가 안 꺼졌다 — 배터리·발열이 샌다');
  });

  testWidgets('카메라 플러그인이 없어도(테스트 환경) 화면과 오버레이가 살아 있다', (tester) async {
    // unsupported면 권한으로 막지 않고 카메라 초기화까지 간다. 위젯 테스트의
    // fake-async 존에서는 플랫폼 채널 응답이 오지 않아 계속 "준비 중"에 머문다
    // — 여기서 확인할 건 그 상태에서도 **화면이 예외 없이 그려지는가**다.
    await pump(tester, permission: CameraPermissionResult.unsupported, settle: false);

    expect(tester.takeException(), isNull);
    expect(find.byType(GridOverlay), findsOneWidget);
    expect(find.text('1 차렷'), findsOneWidget);
  });

  // 포즈는 v2.10부터 **트레이너가 자유 입력**한다. 서버 상한이 곧 최악의 경우다:
  // `ValidateBodyPoses`가 개수 8 · 라벨 12자를 허용한다.
  //
  // 칩은 Wrap이라 가로로는 안 넘치지만, 이 화면은 프리뷰가 Expanded라 **칩이 늘어난
  // 줄 수만큼 위를 먹는다** — 세로로 밀어내는 쪽이 진짜 위험이다. 좁은 기기 + 큰 글씨에서
  // 하단 컨트롤 존이 화면을 넘기면 바깥 Column이 오버플로한다.
  testWidgets('포즈 8개 × 12자(서버 상한) + 좁은 기기 + 최대 배율에서도 안 넘친다', (tester) async {
    const label = '가나다라마바사아자차카타'; // 정확히 12자
    await pump(
      tester,
      permission: CameraPermissionResult.denied,
      // 320dp(아이폰 SE 1세대급) — long_label_overflow_test와 같은 기준.
      size: const Size(320 * 3, 640 * 3),
      // 배율 상한은 app.dart의 클램프 상한과 같은 값.
      scale: 1.35,
      poses: [
        for (var i = 0; i < 8; i++) BodyPoseDto(key: 'pose_$i', label: label),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(GridOverlay), findsOneWidget);
    // 칩이 실제로 8개 다 그려졌는지 — 안 그려졌으면 위 단언이 공허해진다.
    // 프리뷰 상단 제목도 현재 포즈 라벨을 쓰므로 **칩 위젯 안에서만** 센다.
    expect(
      find.descendant(
        of: find.byType(PoseSequenceChips),
        matching: find.textContaining(label),
      ),
      findsNWidgets(8),
    );
  });

  // 프리뷰 위 날짜 pill은 회원이 "언제 찍은 사진인지"를 읽는 유일한 자리이고,
  // 실제 저장 날짜(capturedAt → Storage 경로 앞머리 · 서버 date)는 센터(KST)다.
  // pill만 기기 로컬로 두면 해외에서 화면은 8/22인데 기록은 8/23으로 남는다.
  //
  // ⚠️ 호스트가 KST면 두 값이 같아 회귀가 보이지 않는다(date_format_test 주석).
  //    KST 날짜와 로컬 날짜가 갈리는 TZ로도 돌리는 것까지가 검증이다.
  testWidgets('날짜 pill은 센터(KST) 오늘 — 저장되는 날짜와 같은 값', (tester) async {
    await pump(tester, permission: CameraPermissionResult.denied);

    expect(find.text(DateFmt.monthDayWeekday(DateFmt.todayKst())), findsOneWidget);
  });
}

/// 홈 버튼 → 설정 → 앱 복귀. 수명주기 전이는 **건너뛸 수 없다**(프레임워크가 인접
/// 전이만 허용한다) — resumed에서 곧장 paused로 보내면 단언에 걸린다.
Future<void> _backgroundAndReturn(WidgetTester tester) async {
  const path = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];
  for (final state in path) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _FakeGate implements CameraPermissionGate {
  _FakeGate(this.result);
  final CameraPermissionResult result;
  int requests = 0;
  bool openedSettings = false;

  @override
  Future<CameraPermissionResult> ensureGranted() async {
    requests++;
    return result;
  }

  @override
  Future<void> openSettings() async => openedSettings = true;
}
