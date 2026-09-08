
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/bodycheck/data/body_check_repository_provider.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/bodycheck/presentation/widgets/grid_overlay.dart';
import 'package:rise_member/features/records/presentation/widgets/photo_measure_grid.dart';

/// 체형 사진 전체화면 뷰어 — 타일을 누르면 열린다.
///
/// **왜 필요한가.** 타임라인 타일은 129dp다. 회원이 보려는 건 어깨선 기울기·허리
/// 윤곽 같은 것들인데 그 크기에선 아무것도 판독할 수 없다. 어드민에는 라이트박스가
/// 있는데(`BodyPhotoLightbox`) 정작 자기 몸을 찍은 회원 앱에만 없었다.
///
/// ## 크롬을 최소로 두는 이유
///
/// 사진이 주인공이라 얹는 것마다 근거가 필요하다. 남긴 건 넷뿐이다:
/// **날짜**(연도 포함 — 뷰어는 타임라인 문맥 밖이라 `8/14`만으론 어느 해인지 모른다),
/// **포즈**, **닫기**, **삭제**. 공유·저장 버튼은 넣지 않는다 — 이 앱은 민감정보를
/// `no-store`로 올리고 토큰 URL을 일부러 배제했는데(`body_photo_loader` 헤더),
/// 내보내기 버튼은 그 설계를 한 번에 무효로 만든다.
///
/// ## 스크린샷은 일부러 막지 않는다
///
/// 본인 기기의 본인 사진이다. 이 뷰어가 공유·저장 버튼을 이미 두지 않아서,
/// 스크린샷까지 막으면 **회원이 자기 사진 사본을 가질 방법이 0개가 된다.** 한국
/// 「안전성 확보조치 기준」·Play·Apple 어디도 이를 요구하지 않는다. (화면 공유·앱
/// 스위처 가리기는 화면 단위가 아니라 앱 전역 설정이라 여기서 다루지 않는다.)
///
/// ## 삭제가 여기 있는 이유
///
/// 지울지 말지는 **크게 보고 나서** 정해진다. 타일 크기로는 "이게 그 사진이 맞나"를
/// 확인할 수 없어서, 목록에 삭제 버튼을 두면 엉뚱한 날짜를 지우게 된다.
Future<void> showBodyPhotoViewer(
  BuildContext context, {
  required BodyPhotoEntry entry,
  required Uint8List bytes,
  required String poseLabel,
  required String heroTag,
  required VoidCallback? onDeleted,
  bool showGrid = false,
  GridDensity gridDensity = GridDensity.coarse,
  double? refLine,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      // 전환은 Hero가 맡는다 — 페이지 자체가 페이드까지 하면 사진이 두 겹으로 움직인다.
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (_, __, ___) => _BodyPhotoViewer(
        entry: entry,
        bytes: bytes,
        poseLabel: poseLabel,
        heroTag: heroTag,
        onDeleted: onDeleted,
        showGrid: showGrid,
        gridDensity: gridDensity,
        refLine: refLine,
      ),
    ),
  );
}

class _BodyPhotoViewer extends ConsumerStatefulWidget {
  const _BodyPhotoViewer({
    required this.entry,
    required this.bytes,
    required this.poseLabel,
    required this.heroTag,
    required this.onDeleted,
    required this.showGrid,
    required this.gridDensity,
    required this.refLine,
  });

  final BodyPhotoEntry entry;
  final Uint8List bytes;
  final String poseLabel;
  final String heroTag;
  final VoidCallback? onDeleted;

  /// 타일에서 맞춰 둔 눈금을 그대로 이어받는다 — 확대해서 볼 때가 정작 정밀하게
  /// 재는 순간이라, 여기서 눈금이 사라지면 비교 도구가 반쪽이 된다.
  final bool showGrid;
  final GridDensity gridDensity;
  final double? refLine;

  @override
  ConsumerState<_BodyPhotoViewer> createState() => _BodyPhotoViewerState();
}

class _BodyPhotoViewerState extends ConsumerState<_BodyPhotoViewer> {
  final _zoom = TransformationController();
  bool _deleting = false;

  /// 확대 중인가 — 확대했을 땐 아래로 쓸어 닫기를 끈다. 확대한 사진을 아래로
  /// 밀어 보려는 손짓과 닫으려는 손짓이 **완전히 같기** 때문이다.
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoom);
  }

  void _onZoom() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  void dispose() {
    _zoom
      ..removeListener(_onZoom)
      ..dispose();
    super.dispose();
  }

  void _toggleZoom(TapDownDetails d) {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
      return;
    }
    // 누른 지점을 중심으로 확대한다 — 가운데로 고정하면 회원이 보려던 부위가
    // 화면 밖으로 밀려나서 다시 끌어와야 한다.
    const scale = 2.5;
    final p = d.localPosition;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: const Text(
          '이 사진을 삭제할까요?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          // **"다시 찍을 수 있어요"라고 쓰지 않는다.** 다시 찍을 수 있는 건 오늘의
          // 몸이지 그날의 몸이 아니다. 회원 삭제는 서버가 즉시 완전 파기하고
          // 복원 경로가 없다(스태프 삭제만 30일 유예를 받는다).
          '${_fullDate(widget.entry.date)} · ${widget.poseLabel}\n\n'
          '바로 완전히 삭제되고 되돌릴 수 없어요. 센터에도 남지 않아요.',
          style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '삭제',
              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    final result = await ref
        .read(bodyCheckRepositoryProvider)
        .deletePhoto(id: widget.entry.id, storagePath: widget.entry.storagePath);
    if (!mounted) return;

    switch (result) {
      case Ok():
        // 목록 갱신을 **먼저** 건다 — pop 뒤에는 이 State가 사라져 호출할 자리가 없다.
        widget.onDeleted!();
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(riseSnackBar('사진을 삭제했어요'));
      case Err(:final failure):
        setState(() => _deleting = false);
        showFailureSnackBar(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 아래로 쓸어 닫기. 확대 중엔 끈다(위 [_zoomed] 주석).
            GestureDetector(
              onVerticalDragEnd: _zoomed
                  ? null
                  : (d) {
                      if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).pop();
                    },
              onDoubleTapDown: _toggleZoom,
              onDoubleTap: () {},
              child: Center(
                child: Hero(
                  tag: widget.heroTag,
                  child: InteractiveViewer(
                    transformationController: _zoom,
                    minScale: 1,
                    maxScale: 4,
                    // 격자를 **InteractiveViewer 안**에 둔다 — 밖에 두면 확대·이동할 때
                    // 눈금만 제자리에 남아 사진과 어긋난다(그 순간 눈금은 거짓말이 된다).
                    child: MeasureGridPhoto(
                      bytes: widget.bytes,
                      showGrid: widget.showGrid,
                      density: widget.gridDensity,
                      refLine: widget.refLine,
                      // 타임라인 타일과 달리 여기선 원본 해상도로 그린다 —
                      // 확대해서 보는 게 이 화면의 존재 이유라 `cacheWidth`를 걸면
                      // 확대할수록 뭉개진다.
                    ),
                  ),
                ),
              ),
            ),
            _TopBar(
              date: _fullDate(widget.entry.date),
              pose: widget.poseLabel,
              deleting: _deleting,
              onClose: () => Navigator.of(context).pop(),
              // 목록을 갱신할 방법이 없으면 삭제 버튼을 띄우지 않는다 — 지웠는데
              // 화면이 그대로면 삭제가 거짓말이 된다.
              onDelete: widget.onDeleted == null ? null : _confirmDelete,
            ),
            const _ScopeNote(),
          ],
        ),
      ),
    );
  }
}

/// 뷰어는 타임라인 문맥 밖이라 `8/14`만으론 어느 해인지 알 수 없다.
String _fullDate(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.date,
    required this.pose,
    required this.deleting,
    required this.onClose,
    required this.onDelete,
  });

  final String date;
  final String pose;
  final bool deleting;
  final VoidCallback onClose;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        // 사진이 밝으면 흰 글씨가 묻힌다 — 위쪽만 살짝 어둡게 깐다.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: '닫기',
            ),
            Expanded(
              child: Column(
                // **`min`이 아니면 크롬 전체가 화면 높이로 늘어난다.** `Stack`의
                // 비포지션 자식은 느슨한 제약을 받는데, `max`인 Column은 그 최대치를
                // 다 쓴다 → 부모 `Row`가 전체 높이가 되고 `crossAxisAlignment: center`
                // 때문에 닫기·삭제 버튼이 **화면 한가운데**로 내려간다(실기기에서 발견).
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    pose,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5),
                  ),
                ],
              ),
            ),
            if (deleting)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              )
            else if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: '삭제',
              ),
          ],
        ),
      ),
    );
  }
}

/// 누가 이 사진을 볼 수 있는지 한 줄. **뷰어에만 둔다** — 사진을 크게 보는 순간이
/// 회원이 "이거 누가 보지?"를 가장 강하게 떠올리는 자리다.
class _ScopeNote extends StatelessWidget {
  const _ScopeNote();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
            ),
          ),
          child: Text(
            // 서버 판정과 같은 범위다(`checkBodyPhotoAccess`): 본인 · 담당 코치 ·
            // 대표, 그중 스태프는 민감정보 동의가 유효한 동안만.
            '나와 담당 코치·대표만 볼 수 있어요 (동의를 끄면 코치·대표는 볼 수 없어요)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
