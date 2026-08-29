import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/member_api.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/bodycheck/data/body_check_repository_provider.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_uploader.dart';
import 'package:rise_member/features/bodycheck/domain/body_photo_storage_path.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/bodycheck/presentation/body_camera_provider.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/grid_overlay.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';

part 'camera_view_model.g.dart';

/// 찍었지만 아직 서버까지 도달하지 못한 한 장.
///
/// 바이트를 메모리에 들고 있는 이유: 업로드가 실패했을 때 **다시 찍게 하지 않기
/// 위해서**다. 회원은 이미 포즈를 잡고 셔터를 눌렀고, 실패 원인은 대개 네트워크다.
/// [storagePath]도 여기 고정된다 — 재시도가 매번 새 경로를 만들면 실패한 조각이
/// 버킷에 유령으로 쌓인다(BodyPhotoStoragePath 주석).
class PendingBodyPhoto {
  const PendingBodyPhoto({
    required this.bytes,
    required this.pose,
    required this.direction,
    required this.capturedAt,
    required this.storagePath,
    this.uploadedToStorage = false,
  });

  final Uint8List bytes;

  /// 촬영 시점의 pose **key**. 재시도 중 대표가 시퀀스를 바꿔도 이 사진이 어떤 포즈로
  /// 찍혔는지는 변하지 않아야 하므로 인덱스가 아니라 key를 들고 있는다.
  final String pose;
  final BodyDirection direction;
  final DateTime capturedAt;
  final String storagePath;

  /// Storage 업로드까지는 끝났고 `POST /v1/body-photos`만 남은 상태 —
  /// 재시도 때 같은 바이트를 두 번 올리지 않는다.
  final bool uploadedToStorage;

  PendingBodyPhoto markUploaded() => PendingBodyPhoto(
        bytes: bytes,
        pose: pose,
        direction: direction,
        capturedAt: capturedAt,
        storagePath: storagePath,
        uploadedToStorage: true,
      );
}

/// 카메라 화면 UI State — freezed 미사용(회원 앱 컨벤션: freezed는 DTO 전용).
class CameraState {
  const CameraState({
    this.poses = PoseSpec.fallbackSequence,
    this.poseIndex = 0,
    this.completed = const {},
    this.gridDensity = GridDensity.fine,
    this.hLine = defaultHLine,
    this.submitting = false,
    this.error,
    this.lastSavedMessage,
    this.pendingRetry,
    this.review,
  });

  /// 이 회원의 촬영 시퀀스(계약 v2.10). 서버가 회원별로 정해 내려주고, 못 받으면
  /// [PoseSpec.fallbackSequence]로 떨어진다 — 촬영 자체를 막지는 않는다.
  final List<PoseSpec> poses;

  final int poseIndex;

  /// 이번 세션에 저장을 마친 포즈 **key** 집합.
  final Set<String> completed;
  /// 격자 밀도 — 촬영 조건에 따라 회원이 고른다.
  final GridDensity gridDensity;

  /// 수평 기준선 위치(0~1). 어깨·골반에 맞춰 끌어 옮긴다 — 키가 다르면 고정 높이는
  /// 아무 데도 안 맞는다.
  final double hLine;

  /// 기준선 기본 높이 — 성인 전신을 프레임에 넣었을 때 골반 언저리.
  static const double defaultHLine = 0.60;

  final bool submitting;
  final Failure? error;
  final String? lastSavedMessage;

  /// null이 아니면 **저장에 실패한 사진이 아직 손에 남아 있다** — 화면이 재시도
  /// 배너를 띄운다. 업로드 실패가 스낵바 한 줄로 사라지면 회원은 사진이 저장된 줄
  /// 알고 탭을 떠난다(조용한 유실).
  final PendingBodyPhoto? pendingRetry;

  /// null이 아니면 **방금 찍었고 아직 아무 데도 올라가지 않은 사진**이다 —
  /// 화면이 전체 프리뷰를 띄우고 회원의 판단을 기다린다.
  ///
  /// **이 한 칸이 자동 촬영의 가장 큰 구멍을 막는다.** 종전에는 셔터가 눌리는
  /// 즉시 Storage와 서버로 갔다. 자동 촬영은 사람이 프레임 안에 있는지 알 방법이
  /// 없어서(수평만 본다) 책상에 세워 둔 폰이 빈 방을 찍어 그대로 올렸고, 실제로
  /// 버킷에 쓰레기 50장이 쌓였다. 눈이 한 번 보고 통과시킨 것만 나가야 한다.
  ///
  /// [pendingRetry]와 다르다: 저쪽은 **회원이 저장하겠다고 한 뒤** 실패해서 손에
  /// 남은 것이고, 이쪽은 **아직 아무것도 시작하지 않은** 것이다. 그래서 이쪽을
  /// 버리면 지울 것이 없다.
  final PendingBodyPhoto? review;

  /// 현재 포즈. 시퀀스가 바뀌어 인덱스가 범위를 벗어나면 안전하게 접는다
  /// (대표가 어드민에서 포즈를 줄이는 순간 앱이 촬영 중일 수 있다).
  PoseSpec get currentPose =>
      poses.isEmpty ? PoseSpec.fallbackSequence.first : poses[poseIndex.clamp(0, poses.length - 1)];

  CameraState copyWith({
    List<PoseSpec>? poses,
    int? poseIndex,
    Set<String>? completed,
    GridDensity? gridDensity,
    double? hLine,
    bool? submitting,
    Failure? error,
    bool clearError = false,
    String? lastSavedMessage,
    PendingBodyPhoto? pendingRetry,
    bool clearPendingRetry = false,
    PendingBodyPhoto? review,
    bool clearReview = false,
  }) {
    return CameraState(
      poses: poses ?? this.poses,
      poseIndex: poseIndex ?? this.poseIndex,
      completed: completed ?? this.completed,
      gridDensity: gridDensity ?? this.gridDensity,
      hLine: hLine ?? this.hLine,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
      lastSavedMessage: lastSavedMessage,
      pendingRetry: clearPendingRetry ? null : (pendingRetry ?? this.pendingRetry),
      review: clearReview ? null : (review ?? this.review),
    );
  }
}

/// 셔터 → 실촬영 → Firebase Storage 업로드 → `POST /v1/body-photos`.
@riverpod
class CameraViewModel extends _$CameraViewModel {
  @override
  CameraState build() {
    // 촬영 시퀀스는 회원마다 다르다(계약 v2.10) — 대표가 어드민에서 정한다.
    // 프로필은 capture()가 이미 쓰는 통로라 새 의존이 아니다. **조회 실패해도 촬영을 막지
    // 않는다**: 폴백 4종으로 찍게 두는 편이, 서버가 잠깐 흔들렸다고 회원을 돌려보내는 것보다 낫다.
    final profile = ref.watch(myProfileProvider);
    final poses = profile.asData?.value.bodyPoses
            ?.map((p) => PoseSpec(p.key, p.label))
            .toList(growable: false) ??
        PoseSpec.fallbackSequence;
    if (poses.isEmpty) return const CameraState();
    return CameraState(poses: poses);
  }

  /// 포즈 칩 선택. 시퀀스 밖 인덱스는 접는다(목록이 갱신되는 순간의 탭을 무해하게).
  void selectPose(int index) => state = state.copyWith(
        poseIndex: index.clamp(0, state.poses.length - 1),
      );

  void cycleGridDensity() =>
      state = state.copyWith(gridDensity: state.gridDensity.next);

  /// 기준선 드래그. 프레임 밖으로 나가지 않게 접는다.
  void moveHLine(double v) => state = state.copyWith(hLine: v.clamp(0.05, 0.95));

  /// 센서 프레임 하나를 자동 촬영 판정에 흘려 넣는다.
  ///
  /// **촬영 자체는 화면이 부르지 않는다** — 여기서 판정하고 여기서 [capture]까지 간다.
  /// 화면이 조건을 다시 계산하면 두 곳의 판정이 갈리고, 그 순간 "찍힌 줄 알았는데
  /// 안 찍힌" 사진이 생긴다.
  /// 기준선을 기본 높이로. 끌어 옮길 수 있게 만든 이상 되돌릴 길도 있어야 한다 —
  /// 화면 끝까지 밀어놓고 원위치를 손으로 찾는 건 정확히 맞출 수가 없다.
  void resetHLine() => state = state.copyWith(hLine: CameraState.defaultHLine);

  /// 셔터 → 동의 확인 → 촬영 → 업로드(P8).
  Future<void> capture() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    // **확인을 기다리는 사진이 있으면 새로 찍지 않는다.** 지금은 확인 층이 화면을
    // 통째로 덮어 셔터가 눌릴 일이 없지만, 그 층을 부분 오버레이로 바꾸는 순간
    // 회원이 본 것과 다른 사진이 저장된다. 가드는 두 줄이고 그 회귀는 조용하다.
    if (state.review != null || state.submitting) return;

    state = state.copyWith(
      submitting: true,
      clearError: true,
      lastSavedMessage: null,
      clearPendingRetry: true,
    );

    try {
      final profile = await ref.read(myProfileProvider.future);
      if (profile.consent?.sensitive != true) {
        state = state.copyWith(
          submitting: false,
          error: const RejectedFailure('체형 사진 동의가 필요해요 — 마이 탭에서 동의해주세요'),
        );
        return;
      }
    } catch (_) {
      // 프로필 조회 실패해도 서버가 최종 검증하므로 촬영 자체는 계속 진행.
    }

    final bytes = await ref.read(bodyCameraProvider.notifier).takeJpeg();
    if (bytes == null || bytes.isEmpty) {
      state = state.copyWith(
        submitting: false,
        error: const RejectedFailure('사진을 찍지 못했어요 — 카메라가 준비됐는지 확인하고 다시 눌러주세요'),
      );
      return;
    }

    // 센터(KST) 벽시계 — 이 값이 두 곳에 그대로 박힌다: ① Storage 경로의 **날짜
    // 앞머리**(BodyPhotoStoragePath.build의 yyyyMMdd), ② 서버로 가는 `date`
    // (BodyCheckRepositoryImpl이 DateFmt.isoDate로 찍는다). 로컬 시각으로 두면
    // 해외 기기에서 파일명 날짜와 서버 기록이 서로, 그리고 화면의 날짜 pill과도
    // 하루씩 어긋난다(DateFmt 클래스 주석의 시간축 규약).
    //
    // 경로 꼬리의 epochMillis는 같은 날 같은 포즈를 다시 찍었을 때의 **충돌 회피용
    // 일련번호**일 뿐이라(BodyPhotoStoragePath 주석), 벽시계 표현이라 절대 시각과
    // 오프셋만큼 차이나는 건 문제가 되지 않는다 — 한 기기 안에서는 여전히 단조 증가다.
    final capturedAt = DateFmt.nowKst();
    final pending = PendingBodyPhoto(
      bytes: bytes,
      pose: state.currentPose.key,
      direction: BodyDirection.front,
      capturedAt: capturedAt,
      // 경로 형태는 이미 배포된 storage.rules가 정한다(BodyPhotoStoragePath 주석).
      storagePath: BodyPhotoStoragePath.build(
        memberId: session.memberId,
        pose: state.currentPose.key,
        direction: BodyDirection.front,
        capturedAt: capturedAt,
      ),
    );

    // **여기서 멈춘다.** 올리는 건 회원이 보고 "이걸로 저장"을 눌렀을 때다.
    state = state.copyWith(submitting: false, review: pending);
  }

  /// 검토 화면의 "이 사진으로 저장" — 이때 처음으로 네트워크가 움직인다.
  Future<void> confirmReview() async {
    final pending = state.review;
    final memberId = ref.read(sessionProvider)?.memberId;
    if (pending == null || memberId == null) return;
    // **검토를 여기서 닫는다 — `_persist` 뒤가 아니라.** `lastSavedMessage`는
    // `copyWith`가 매번 비우는 일회성 필드라(위 클래스 정의), `_persist`가 세워 둔
    // 성공 문구를 뒤이은 `copyWith` 한 번이 지운다. 회원은 저장하고도 아무 확인도
    // 못 받는다(기존 테스트가 잡았다).
    //
    // 먼저 닫아도 안전하다: 실패하면 `_persist`가 `pendingRetry`로 재시도 배너를
    // 세우고, 그쪽이 손에 든 바이트의 주인이 된다.
    state = state.copyWith(
      submitting: true,
      clearError: true,
      lastSavedMessage: null,
      clearReview: true,
    );
    await _persist(pending, memberId: memberId);
  }

  /// 검토 화면의 "다시 찍기" — **아무것도 올라가지 않았으므로 지울 것이 없다.**
  void retakeReview() =>
      state = state.copyWith(clearReview: true, clearError: true);

  /// 재시도 배너의 "다시 저장" — 새로 찍지 않고 손에 든 사진을 그대로 다시 올린다.
  Future<void> retryPendingUpload() async {
    final pending = state.pendingRetry;
    final memberId = ref.read(sessionProvider)?.memberId;
    if (pending == null || memberId == null) return;
    state = state.copyWith(submitting: true, clearError: true, lastSavedMessage: null);
    await _persist(pending, memberId: memberId);
  }

  /// 재시도 배너의 "버리기" — 회원이 저장을 포기했다. 바이트를 메모리에서 놓는다.
  void discardPendingUpload() =>
      state = state.copyWith(clearPendingRetry: true, clearError: true);

  /// Storage 업로드 → 서버 메타데이터 기록. 어느 단계에서 실패하든 [pendingRetry]에
  /// 진행 상태를 남겨, 재시도가 이미 끝난 단계를 다시 밟지 않게 한다.
  Future<void> _persist(PendingBodyPhoto pending, {required String memberId}) async {
    var current = pending;

    if (!current.uploadedToStorage) {
      final uploaded = await ref.read(bodyPhotoUploaderProvider).upload(
            storagePath: current.storagePath,
            bytes: current.bytes,
          );
      if (uploaded case Err(:final failure)) {
        state = state.copyWith(submitting: false, error: failure, pendingRetry: current);
        return;
      }
      current = current.markUploaded();
    }

    final result = await ref.read(bodyCheckRepositoryProvider).uploadPhoto(
          memberId: memberId,
          pose: current.pose,
          direction: current.direction,
          date: current.capturedAt,
          storagePath: current.storagePath,
        );

    result.fold(
      (photo) {
        // 기록 탭의 "체형 분석 타임라인"은 같은 body-photos를 읽는다. 5개 탭이
        // StatefulShellRoute.indexedStack으로 **동시에 mount된 채 유지**되므로
        // (core/router/app_router.dart) 탭을 오가는 것만으로는 AsyncData가 폐기되지
        // 않는다 — 여기서 무효화하지 않으면 방금 저장한 사진이 기록 탭에 나타나지
        // 않고, 회원은 저장이 안 된 줄 알고 다시 찍는다(중복 촬영·중복 저장).
        // 홈 → 기록(toggleHomework)과 같은 규약: **성공 시에만**.
        ref.invalidate(recordsViewModelProvider);

        final nextCompleted = {...state.completed, current.pose};
        // 방금 저장한 포즈가 현재 선택된 포즈일 때만 다음으로 넘긴다 — 재시도 중
        // 회원이 다른 칩을 눌러 뒀다면 그 선택을 뺏지 않는다.
        final onSamePose = state.currentPose.key == current.pose;
        final atLast = state.poseIndex >= state.poses.length - 1;
        state = state.copyWith(
          submitting: false,
          completed: nextCompleted,
          poseIndex: (onSamePose && !atLast) ? state.poseIndex + 1 : state.poseIndex,
          // 저장 직후에는 **잠가 둔다.** 여기서 `reset()`을 하면 수평인 채로 놓아둔
          // 폰이 다음 포즈를 곧바로 또 찍는다(실기기에서 실제로 그랬다). 잠금은
          // `onFrame`이 수평이 깨지는 걸 보는 순간 풀린다 — 회원이 자세를 바꾸면
          // 반드시 흔들리므로, 그게 "사람이 있다"는 가장 값싼 증거다.
          //
          // 수동 셔터로 찍은 경우에도 잠근다: 그때 카운트다운이 돌고 있었다면
          // 손을 떼자마자 한 장이 더 남는다.
          lastSavedMessage:
              '${PoseSpec.labelFor(current.pose, sequence: state.poses)} 저장했어요',
          clearPendingRetry: true,
          clearError: true,
        );
      },
      (failure) {
        // Storage에는 올라갔는데 서버 기록이 실패한 상태 — 재시도는 POST만 다시 한다.
        state = state.copyWith(submitting: false, error: failure, pendingRetry: current);
      },
    );
  }
}
