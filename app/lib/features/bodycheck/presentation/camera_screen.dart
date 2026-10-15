import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/session/session_gone_view.dart' show sessionGoneEscapeLabel;
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/bodycheck/domain/level_state.dart';
import 'package:rise_member/features/bodycheck/presentation/camera_view_model.dart';
import 'package:rise_member/features/bodycheck/presentation/level_simulator_provider.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/background_person_banner.dart';
import 'package:rise_member/features/bodycheck/presentation/body_camera_provider.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/camera_preview_layer.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/capture_review_layer.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/grid_overlay.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/level_indicator.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/pose_sequence_chips.dart';

/// 체형 분석 카메라 — 실 프리뷰 위에 그리드+기준선+수평계+포즈 시퀀스+배경 주의문.
/// 오버레이 좌표는 목업(t-cam) 1:1 이식이라 손대지 않는다.
///
/// **전체화면 모드다**(P21) — 탭 브랜치가 아니라 rootNavigator 위의 라우트다. 4포즈를
/// 연속으로 찍는 동안 탭바·앱바가 먹던 세로 공간을 프리뷰에 돌려주고, 화면을 벗어나면
/// 위젯이 트리에서 **사라져** 카메라가 확실히 꺼진다(브랜치였을 땐 indexedStack이 살려둬서
/// `TickerMode` 판정을 덧대야 했다).
///
/// 남은 수명주기 조건은 **포그라운드 하나**다 — 홈 버튼·전화 수신에 카메라를 놓는다.
/// watch를 놓으면 카메라·가속도계 provider 모두 autoDispose라 구독 0이 되어 정리된다.
/// 그러려면 build()가 **하나도 빠짐없이** `active`로 게이팅해야 한다 — 프레임 비율
/// 하나를 게이팅 없이 watch하는 것만으로 구독이 0이 되지 않아, 주석과 달리 홈 버튼을
/// 눌러도 카메라가 계속 열려 있었다(배터리·발열).
///
/// 포그라운드로 **돌아올 때는 권한을 다시 확인한다**(`didChangeAppLifecycleState`).
/// 영구 거부 안내에서 설정으로 나갔다 켜고 돌아오는 게 이 화면의 유일한 복구 경로인데,
/// 옛 판정을 들고 있으면 같은 안내가 그대로 남아 회원이 갇힌다.
///
/// 프리뷰는 화면을 꽉 채우지 **않는다**. 3:4 원본을 cover로 늘리면 좌우가 잘려 화면에서
/// 맞춘 자세와 저장본이 어긋난다(WYSIWYG 붕괴) — 전폭 + 원본 비율을 유지하고 남는 위아래를
/// 검은 여백과 컨트롤 존으로 쓴다.
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> with WidgetsBindingObserver {
  bool _foreground = true;

  /// 자동 촬영 판정을 몰아주는 고정 주기 티커.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    setState(() => _foreground = foreground);
    if (!foreground) return;
    // **돌아오는 것만으로 화면이 복구돼야 한다.** 권한을 영구 거부하면 이 화면이
    // 주는 유일한 다음 행동이 "설정 열기"인데, 설정에서 켜고 돌아와도 provider가
    // 옛 판정(`BodyCameraBlocked`)을 그대로 들고 있으면 같은 안내가 남는다 —
    // 누를 수 있는 건 이미 켠 설정을 또 여는 버튼뿐이라 회원이 갇힌다.
    //
    // 그래서 복귀마다 권한 판정을 버린다. 이어지는 rebuild가 다시 watch하면서
    // `ensureGranted()`가 새로 돌고 카메라도 함께 열린다. 백그라운드 동안 구독이
    // 0이 되어 이미 폐기됐다면 이 호출은 아무 일도 하지 않는다(element 없음).
    ref.invalidate(bodyCameraProvider);
  }

  @override
  Widget build(BuildContext context) {
    // 전체화면 라우트라 "보이지 않는데 살아 있는" 상태가 없다 — 포그라운드만 본다.
    final active = _foreground;

    final state = ref.watch(cameraViewModelProvider);
    // 비활성일 때는 센서를 구독하지 않는다(각도는 0 = 수평 OK로 남는다).
    final angle = active ? ref.watch(levelSimulatorProvider) : 0.0;
    final levelState = LevelEvaluator.evaluate(angle);

    ref.listen(cameraViewModelProvider, (prev, next) {
      // 저장 성공/실패는 이 화면에서 **색으로만** 구분된다 — 셔터를 누른 직후
      // 문구를 끝까지 읽지 않고도 사진이 남았는지 알아야 하는 자리다.
      if (next.lastSavedMessage != null && next.lastSavedMessage != prev?.lastSavedMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(riseSnackBar(next.lastSavedMessage!, kind: RiseSnackKind.ok));
      }
      if (next.error != null && next.error != prev?.error) {
        final error = next.error!;
        if (error is SessionGoneFailure) {
          // 세션이 비었다 — 리스너(`app.dart`)가 이 전체화면 라우트째 내리는 중이라 빨간
          // 스낵바("실패했으니 다시 시도")는 거짓이다. 대신 닫힘을 예고하고, 리스너가 어떤
          // 이유로 이동하지 못했을 때를 위해 **세션을 요구하지 않는 탈출구**를 액션으로 단다
          // (`SessionGoneView`와 같은 규칙·같은 라벨). 화면이 내려가면 손에 든 바이트도
          // autoDispose로 사라진다 — 의도한 것이다(camera_view_model 주석).
          final reason = ref.read(sessionProvider.notifier).lastEndReason ??
              SessionEndReason.unauthorized;
          ScaffoldMessenger.of(context).showSnackBar(riseSnackBar(
            '로그인 정보가 바뀌어 촬영을 닫아요',
            action: SnackBarAction(
              label: sessionGoneEscapeLabel(reason),
              onPressed: () => GoRouter.maybeOf(context)?.go(sessionEndRoute(reason)),
            ),
          ));
          return;
        }
        showFailureSnackBar(context, error);
      }
    });

    // **프레임 비율을 카메라에서 받아온다.** 하드코딩하면 프리뷰와 저장본이 갈리고,
    // 회원은 화면에 없던 영역이 파일에 들어 있는 걸 나중에야 알게 된다.
    //
    // **`active`일 때만 watch한다.** 프리뷰(`CameraPreviewLayer`)는 이미 게이팅돼
    // 있었는데 이 한 줄이 게이팅 없이 watch해서, 백그라운드로 가도 구독이 0이 되지
    // 않아 카메라가 안 꺼졌다 — 위 머리 주석("포그라운드를 잃으면 정리된다")이
    // 실제 동작과 어긋난 지점이다. 비활성 구간에는 어차피 프리뷰를 그리지 않으므로
    // 기본 비율로 두면 되고, 돌아오면 재구독이 실제 값을 다시 채운다.
    final previewAspect = active
        ? ref.watch(bodyCameraProvider).maybeWhen(
            data: (s) =>
                s is BodyCameraReady ? s.captureAspect : BodyCameraReady.defaultCaptureAspect,
            orElse: () => BodyCameraReady.defaultCaptureAspect,
          )
        : BodyCameraReady.defaultCaptureAspect;

    return PopScope(
      // 손에 남은 사진이 있으면 나가는 순간 사라진다(메모리에만 있다).
      // 검토 중인 사진도 나가는 순간 사라진다 — 아직 아무 데도 올라가지 않았다.
      //
      // **저장 왕복 중(`submitting`)도 막는다.** "이 사진으로 저장" 직후 스피너가
      // 도는 동안은 `review`가 이미 비워져 있고 `pendingRetry`는 아직 안 세워진
      // 틈이라, 이 조건이 없으면 뒤로가기가 확인 없이 화면을 닫는다. 그러면 실패해도
      // 재시도 배너를 띄울 화면이 없고(뷰모델은 autoDispose로 사라진다) 민감한 체형
      // 사진이 흔적 없이 유실된다 — 이 화면에서 가장 조용한 실패다.
      canPop: state.pendingRetry == null && state.review == null && !state.submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmExit(context);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          // **AppBar를 두지 않는다.** 프리뷰가 화면을 최대한 쓰게 하려는 것이고,
          // 닫기 버튼은 프리뷰 위에 띄운다(아래 Stack). 제목("체형 분석")도 뺐다 —
          // 지금 무엇을 찍는지는 프레임 안의 「정면 · 차렷」이 이미 말한다.
          body: state.review != null
              ? CaptureReviewLayer(
                  bytes: state.review!.bytes,
                  poseLabel: state.currentPose.label,
                  submitting: state.submitting,
                  onRetake: () => ref.read(cameraViewModelProvider.notifier).retakeReview(),
                  onConfirm: () => ref.read(cameraViewModelProvider.notifier).confirmReview(),
                )
              : Stack(
                  children: [
                    // **프리뷰가 화면 전체를 쓴다.** 비율은 카메라가 실제로 찍는 값이라
                    // (`previewAspect`) 화면보다 덜 길면 위아래에 검은 띠가 남는데,
                    // 그 띠 위에 크롬을 얹어 화면은 꽉 차 보이게 한다. 띠를 없애려고
                    // 프리뷰를 잘라 채우면 **보이는 것과 저장되는 것이 갈린다** —
                    // 이 화면이 절대 하면 안 되는 일이다.
                    Positioned.fill(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: previewAspect,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            // **터치 취소를 `Listener`로 잡는다.** `GestureDetector.onTapDown`을
                            // 쓰면 탭 제스처 아레나에 참여해 아래 버튼(권한 허용하기·설정
                            // 열기·셔터)의 탭을 빼앗는다 — 실제로 권한 테스트 2건이 그렇게
                            // 깨졌다. `Listener`는 raw 포인터만 관찰하고 경쟁하지 않는다.
                            child: Listener(
                              onPointerDown: (_) {},
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [AppColors.camBgTop, AppColors.camBgBottom],
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    // 실 프리뷰는 오버레이 **뒤**에 깔린다 — Stack의 첫 자식.
                                    Positioned.fill(child: CameraPreviewLayer(active: active)),
                                    GridOverlay(density: state.gridDensity, hLine: state.hLine),
                                    // 기준선 드래그 — 프레임 아무 데나 잡고 위아래로.
                                    //
                                    // **델타 누적이 아니라 손가락의 절대 위치**를 쓴다. 델타를
                                    // `state.hLine`에 더하면 빌드 시점 값이 기준이 되는데,
                                    // 포인터 이벤트가 리빌드보다 빨라 한 프레임 묵은 값에
                                    // 더해지는 순간 그만큼의 이동이 통째로 사라진다(실기기에서
                                    // 크게 쓸어도 선이 조금만 따라오는 걸로 드러났다).
                                    // 위치를 직접 지정하면 그 경합이 아예 없다.
                                    //
                                    // 세로 드래그만 해석한다 — 가로 스와이프로 실수로 움직이지
                                    // 않게. 높이는 **프리뷰 프레임**의 constraints에서 받는다
                                    // (localPosition도 이 프레임 기준이라 서로 맞는다).
                                    Positioned.fill(
                                      child: LayoutBuilder(
                                        builder: (_, constraints) {
                                          void place(Offset local) {
                                            final h = constraints.maxHeight;
                                            if (h <= 0) return;
                                            ref
                                                .read(cameraViewModelProvider.notifier)
                                                .moveHLine(local.dy / h);
                                          }

                                          return GestureDetector(
                                            behavior: HitTestBehavior.translucent,
                                            onVerticalDragStart: (d) {
                                              place(d.localPosition);
                                            },
                                            onVerticalDragUpdate: (d) => place(d.localPosition),
                                          );
                                        },
                                      ),
                                    ),
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        padding: const EdgeInsets.symmetric(vertical: 7),
                                        child: Text(
                                          '${BodyDirection.front.label} · ${state.currentPose.label}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 38,
                                      left: 10,
                                      // 센터(KST) 오늘 — 이 pill이 말하는 날짜와 실제로 저장되는
                                      // 날짜(capturedAt → Storage 경로 앞머리 · 서버 date)가
                                      // 갈리면 안 된다. 로컬로 두면 해외에서 화면은 8/14인데
                                      // 파일·기록은 8/15로 남는다.
                                      child: _Pill(
                                        text: DateFmt.monthDayWeekday(DateFmt.todayKst()),
                                      ),
                                    ),
                                    LevelIndicator(state: levelState),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ── 하단 컨트롤 존 ────────────────────────────────────────────
                    //
                    // **높이에 상한을 두고 넘치면 스크롤한다.** 이 존의 내용은 서버가 정하는
                    // 값으로 늘어난다: 포즈는 트레이너가 자유 입력하고(v2.10) 서버 상한이
                    // 8개 × 12자다. 상한을 다 쓰면 칩 Wrap이 여러 줄로 접히면서 위쪽
                    // Expanded 프리뷰를 0까지 밀고도 바깥 Column을 넘긴다 —
                    // 360dp(갤럭시)·배율 1.35에서 191px, 320dp에서는 배율 1.0에서도 170px가
                    // 실측으로 넘쳤다(camera_screen_permission_test).
                    //
                    // 상한을 화면 높이의 42%로 잡는 이유: 프리뷰가 최소한 절반 넘게 남아야
                    // 이 화면이 하는 일(자세를 프레임에 맞추기)이 가능하다. 칩을 가로
                    // 스크롤 한 줄로 바꾸지 않은 건 시퀀스 전체를 한눈에 보는 게 이 UI의
                    // 목적이기 때문이다 — 안 보이는 대신 스크롤로 닿게 한다.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.42,
                        ),
                        child: Container(
                          width: double.infinity,
                          // 꽉 찬 검정 대신 **스크림**이다. 프리뷰가 화면을 다 쓰므로 이
                          // 존은 그 위에 얹히는데, 불투명하면 프리뷰의 아래쪽(발 위치
                          // 마커가 있는 자리)을 가려 버린다.
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black,
                                Colors.black.withValues(alpha: 0.88),
                                Colors.black.withValues(alpha: 0),
                              ],
                              stops: const [0, 0.72, 1],
                            ),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            14,
                            22,
                            14,
                            12 + MediaQuery.paddingOf(context).bottom,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // **셔터와 주의문은 하단 존에 있다.** 프리뷰가 화면 전체를
                                // 쓰게 되면서 이 존이 프리뷰 위에 얹히는데, 셔터를 프리뷰
                                // 안(bottom:10)에 두면 **이 존 뒤로 들어가 눌리지 않는다** —
                                // 실기기에서 버튼 뒤에 숨은 셔터를 보고 잡았다.
                                const BackgroundPersonBanner(),
                                const SizedBox(height: 10),
                                Center(
                                  // 화면의 유일한 주 동작인데 아이콘도 글자도
                                  // 툴팁도 없는 흰 원이라, 스크린리더에는 무명
                                  // 덩어리로 읽혔다(P54).
                                  child: Semantics(
                                    button: true,
                                    enabled: !state.submitting,
                                    label: '촬영',
                                    hint: '${state.currentPose.label} 자세를 촬영합니다',
                                    child: GestureDetector(
                                      onTap: state.submitting
                                          ? null
                                          : () => ref
                                                .read(cameraViewModelProvider.notifier)
                                                .capture(),
                                      child: Container(
                                        width: 62,
                                        height: 62,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.45),
                                            width: 5,
                                          ),
                                        ),
                                        child: state.submitting
                                            ? const Padding(
                                                padding: EdgeInsets.all(18),
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: AppColors.brand,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (state.pendingRetry != null) ...[
                                  _UploadRetryBanner(
                                    busy: state.submitting,
                                    onRetry: () => ref
                                        .read(cameraViewModelProvider.notifier)
                                        .retryPendingUpload(),
                                    onDiscard: () => ref
                                        .read(cameraViewModelProvider.notifier)
                                        .discardPendingUpload(),
                                  ),
                                  const SizedBox(height: 9),
                                ],
                                PoseSequenceChips(
                                  poses: state.poses,
                                  completed: state.completed,
                                  currentIndex: state.poseIndex,
                                  onSelect: (i) =>
                                      ref.read(cameraViewModelProvider.notifier).selectPose(i),
                                ),
                                const SizedBox(height: 8),
                                // 검은 배경 위 버튼 — onDark로 명시한다(RiseButton이 라벨 색을
                                // 자식 Text에 직접 박아 상위 Theme으로는 못 덮는다).
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    RiseButton(
                                      label: '격자 ${state.gridDensity.label}',
                                      style: RiseButtonStyleKind.outline,
                                      small: true,
                                      onDark: true,
                                      onPressed: () => ref
                                          .read(cameraViewModelProvider.notifier)
                                          .cycleGridDensity(),
                                    ),
                                    const SizedBox(width: 6),
                                    // 목업의 "기울기 시뮬" 버튼이 있던 자리. 실기기에서 그 버튼은
                                    // 수평계를 3.4°로 **잠그는** 토글이라, 눌러 둔 채로 두면 수평이
                                    // 영영 OK가 안 되고 자동촬영(정렬되면 3·2·1)이 죽는다 —
                                    // 회원에게는 "카메라가 고장 났다"로 보인다. 센서 없는 환경용
                                    // 폴백은 provider에 남겨 두고 버튼만 뺐다.
                                    RiseButton(
                                      label: '기준선 초기화',
                                      style: RiseButtonStyleKind.outline,
                                      small: true,
                                      onDark: true,
                                      onPressed: () =>
                                          ref.read(cameraViewModelProvider.notifier).resetHLine(),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '격자로 변화량을 재고, 빨간 가로선은 어깨·골반에 맞춰 끌어 옮기세요 · 수평이면 초록\n'
                                  // 서버 checkBodyPhotoAccess와 같은 말 — 대표(owner)도 동의가
                                  // 유효하면 본다. "담당 코치만"은 열람 범위를 좁혀 말한 거짓이었다.
                                  '사진은 나와 담당 코치, 센터 대표만 봅니다(동의 필수)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.white54,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 닫기 — AppBar를 없앤 자리를 대신한다. 프리뷰 위에 떠 있으므로
                    // 밝은 배경에서도 읽히도록 어두운 원을 깔았다.
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 6,
                      left: 6,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: '닫기',
                          onPressed: () => _handleClose(context),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// AppBar 닫기 — PopScope와 **같은 판정**을 거치게 한다(둘이 갈리면 X로는 유실된다).
  ///
  /// 판정 하나를 빠뜨리면 그 경로로만 조용히 사라진다: 종전엔 `pendingRetry`만 봐서
  /// 저장 왕복 중(`submitting`)에 X를 누르면 확인 없이 닫혔다. 조건은 위 `canPop`과
  /// 한 글자도 다르지 않아야 한다.
  void _handleClose(BuildContext context) {
    final state = ref.read(cameraViewModelProvider);
    if (state.pendingRetry == null && state.review == null && !state.submitting) {
      Navigator.of(context).pop();
      return;
    }
    _confirmExit(context);
  }

  /// 저장 못 한 사진을 들고 나가려 할 때. 바이트는 메모리에만 있어 나가면 사라진다.
  Future<void> _confirmExit(BuildContext context) async {
    // 저장 왕복 중과 "찍어만 둔" 상태는 회원이 방금 한 행동이 다르다 — 저장을 누른
    // 사람에게 "저장하지 않고"라고 물으면 자기가 뭘 눌렀는지 의심하게 된다.
    final submitting = ref.read(cameraViewModelProvider).submitting;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(submitting ? '저장 중이에요 — 나갈까요?' : '저장하지 않고 나갈까요?'),
        content: Text(
          submitting
              ? '사진을 올리는 중이에요. 지금 나가면 저장이 끝나지 않고 사진도 사라져요.'
              : '방금 찍은 사진이 아직 저장되지 않았어요 — 나가면 사라져요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('계속 촬영'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if ((leave ?? false) && context.mounted) Navigator.of(context).pop();
  }
}

/// 업로드 실패가 스낵바 한 줄로 사라지면 회원은 사진이 저장된 줄 알고 탭을 떠난다.
/// 사진이 아직 손에 남아 있는 동안에는 **화면에 계속 붙어 있는** 재시도 경로를 준다.
class _UploadRetryBanner extends StatelessWidget {
  const _UploadRetryBanner({required this.busy, required this.onRetry, required this.onDiscard});

  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.badgeDanBg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '방금 찍은 사진이 아직 저장되지 않았어요',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.badgeDanFg,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            '사진은 그대로 들고 있어요 — 다시 찍지 않아도 됩니다. '
            '앱을 껐다 켜면 사라지니 지금 저장해주세요.',
            style: TextStyle(fontSize: 10.5, color: AppColors.badgeDanFg, height: 1.5),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              RiseButton(label: '다시 저장', small: true, onPressed: busy ? null : onRetry),
              const SizedBox(width: 6),
              RiseButton(
                label: '버리기',
                style: RiseButtonStyleKind.outline,
                small: true,
                onPressed: busy ? null : onDiscard,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10.5)),
    );
  }
}
