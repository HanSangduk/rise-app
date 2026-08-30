import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/theme/app_typography.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/domain/records_models.dart'
    as records;
import 'package:rise_member/features/bodycheck/presentation/widgets/grid_overlay.dart';
import 'package:rise_member/features/records/presentation/widgets/body_photo_viewer.dart';
import 'package:rise_member/features/records/presentation/widgets/photo_measure_grid.dart';

/// 체형 분석 타임라인 — 포즈 칩으로 볼 포즈를 고르고, **날짜 칩으로 「기준」을 고른 뒤
/// 아래 스크러버로 「비교」쪽을 날짜순으로 훑는다.**
///
/// ## 왜 「와이프」가 아니라 「날짜 스크러버」인가 (P31)
///
/// 두 장을 겹쳐 놓고 경계를 미는 전/후 와이프는 이 앱에서 **거짓말을 한다.** 두 사진이
/// 정합(registration)돼 있어야 성립하는 인터랙션인데, 정합 자유도 7개 중 이 앱이
/// 강제하는 건 roll 하나뿐이고 **저장하는 건 0개**다. `level_angle.dart`는 폰이 뒤로
/// 눕는 각(pitch)을 아예 측정하지 않는다고 명시해 뒀는데, 폰을 벽에 기대 세우는 이
/// 촬영에서 그게 가장 큰 왜곡원이다.
///
/// 산술이 결정적이다 — 카메라 2.5m에서 회원이 **20cm 앞으로 서면 실루엣이 8.7% 커진다.**
/// 한 달치 실제 허리 변화는 **5% 남짓**이다. **오차가 신호보다 크고, 부호가 뒤집힐 수도
/// 있다**(잘 됐는데 나빠진 걸로 보인다).
///
/// 그래서 **두 사진을 합성하지 않는다.** 화면에 있는 건 언제나 진짜 사진 두 장이고,
/// 스크러버는 오른쪽 사진을 **다른 날짜의 사진으로 바꿀** 뿐이다. 거짓말이 들어갈 자리가
/// 구조적으로 없다. `divisions`로 노치를 끊었으므로 손잡이를 좌우로 까딱하면 두 날짜가
/// 번갈아 뜨는 **블링크 비교**가 되는데, 이게 와이프가 노리던 감도를 대신한다 —
/// 카메라가 움직인 쌍은 화면 전체가 점프해 **실패가 스스로 자백한다.**
///
/// ## 「전/후」가 아니라 「기준/비교」인 이유
///
/// 스크러버는 과거 방향으로도 훑는다("어디서부터 이렇게 됐지"는 정당한 행동이다).
/// 그러면 "후"가 "전"보다 이전 날짜가 되어 **라벨이 거짓이 된다.**
///
/// ## 두 컨트롤의 소유를 가른다
///
/// 날짜 칩은 **기준만**, 스크러버는 **비교만** 건드린다. 종전 칩 핸들러는
/// `_beforeIndex = afterIndex; _afterIndex = i`였는데, **이미 선택된 오른쪽 칩을 다시
/// 누르면 둘 다 같은 값이 되어 같은 사진이 좌우에 그려졌다** — 사진 1장일 때 막아 둔
/// "자기 자신과의 비교"가 2장 이상에서 탭 한 번으로 되살아났다. 소유를 가르면 그 상태가
/// 애초에 만들어지지 않는다.
///
/// 사진은 Firebase Storage에서 **getData로 직접** 받아 그린다 —
/// `getDownloadURL`은 규칙을 거치지 않는 무기한 토큰 URL을 만들어 P8 민감정보에 맞지 않는다.
class BodyPhotoTimelineCard extends StatefulWidget {
  const BodyPhotoTimelineCard({
    super.key,
    required this.album,
    this.poses = PoseSpec.fallbackSequence,
    this.failed = false,
    this.onPhotoDeleted,
  });

  /// 포즈 4종 전부. 예전엔 `ohsquat` 하나만 담긴 타임라인을 받았고, 나머지 3종은
  /// 저장은 되지만 앱 어디에도 나타나지 않았다(records_repository_impl의 포즈 필터).
  final records.BodyPhotoAlbum album;

  /// 사진 조회 실패(RecordsData.bodyPhotosFailed) — 빈 앨범을 "아직 촬영한
  /// 사진이 없어요"로 위장하지 않기 위한 플래그.
  final bool failed;

  /// 이 회원의 현재 포즈 시퀀스(계약 v2.10). 칩 목록은 이것과 **실제 사진의 key를
  /// 합집합**으로 만든다 — 대표가 포즈를 빼도 이미 찍은 사진은 계속 보여야 한다.
  final List<PoseSpec> poses;

  /// 뷰어에서 사진을 지운 뒤 목록을 다시 받아온다. 넘기지 않으면 삭제 버튼을
  /// 띄우지 않는다 — 지웠는데 화면이 그대로면 삭제가 거짓말이 된다.
  final VoidCallback? onPhotoDeleted;

  @override
  State<BodyPhotoTimelineCard> createState() => _BodyPhotoTimelineCardState();
}

class _BodyPhotoTimelineCardState extends State<BodyPhotoTimelineCard> {
  /// 지금 보고 있는 포즈 — 첫 진입은 데이터가 정한다([BodyPhotoAlbum.defaultPose]).
  /// 회원이 칩을 눌러 바꾸면 그 선택이 이긴다(아래 [_selectPose]).
  late String _pose;

  /// 왼쪽 「기준」 — **날짜 칩만** 바꾼다. 첫 진입은 0 = 가장 오래된 사진
  /// (`BodyPhotoAlbum.from`이 오래된 순으로 정렬한다). 처음 몸을 기준에 두는 게
  /// 이 화면의 기본 질문("얼마나 달라졌나")에 맞다.
  late int _baseIndex;

  /// 오른쪽 「비교」 — **스크러버만** 바꾼다. 첫 진입은 마지막 = 최신 사진.
  late int _compareIndex;

  /// 계측 격자 표시(P46). 기본 **켜짐** — 이 화면의 목적이 "얼마나 달라졌나"를 재는
  /// 것이고, 눈금 없는 두 사진은 그 질문에 답하지 못한다. 사진 자체를 보고 싶을 때
  /// 끌 수 있게 토글을 준다.
  bool _grid = true;

  /// 눈금 촘촘함 — 타일이 작아 기본은 성김(9×12). 뷰어에서 확대해 볼 땐 촘촘한 쪽이 낫다.
  GridDensity _density = GridDensity.coarse;

  /// **두 사진이 공유하는** 가로 기준선(0~1). 기준 사진의 어깨에 맞춰 두면 비교
  /// 사진에서 그 선이 어깨 위·아래 어디에 걸리는지가 곧 변화량이다.
  /// 사진마다 따로 두지 않는 이유는 [MeasureGridPhoto.refLine] 주석 참조.
  double _refLine = 0.42;

  @override
  void initState() {
    super.initState();
    _pose = widget.album.defaultPose(widget.poses);
    _resetIndices();
  }

  /// 포즈를 바꾸면 날짜 인덱스는 그 포즈의 것으로 다시 잡는다 — 안 하면 사진 5장짜리
  /// 포즈에서 고른 인덱스가 2장짜리 포즈에 그대로 남아(clamp되어) 엉뚱한 두 장이
  /// 선택된 것처럼 보인다.
  void _resetIndices() {
    final n = widget.album.countFor(_pose);
    _baseIndex = 0;
    _compareIndex = n > 0 ? n - 1 : 0;
  }

  /// 새 사진이 들어오면 **「비교」를 그 사진으로 옮긴다.**
  ///
  /// 실기기에서 드러난 결함이다: 촬영하고 돌아왔는데 스크러버 손잡이가 왼쪽 끝에
  /// 붙은 채 두 칸 모두 예전 사진이었다. `initState`가 **데이터가 도착하기 전의**
  /// 개수로 인덱스를 잡아 놓고, 새 데이터가 와도 다시 잡지 않았기 때문이다
  /// (`build`의 clamp는 범위만 지킬 뿐 따라가지 않는다). 방금 찍은 사진을 보러 온
  /// 회원에게 그 사진이 안 보이는 게 이 화면에서 가장 나쁜 실패다.
  ///
  /// **가장 최신 사진의 id가 바뀔 때만** 옮긴다. 목록이 갱신될 때마다 무조건
  /// 옮기면, 회원이 일부러 과거로 훑어 둔 자리를 백그라운드 새로고침이 걷어찬다.
  @override
  void didUpdateWidget(BodyPhotoTimelineCard old) {
    super.didUpdateWidget(old);
    final before = old.album.entriesFor(_pose);
    final after = widget.album.entriesFor(_pose);
    if (after.isEmpty) return;
    final newestChanged = before.isEmpty || before.last.id != after.last.id;
    if (newestChanged) setState(_resetIndices);
  }

  void _selectPose(String pose) {
    if (pose == _pose) return;
    setState(() {
      _pose = pose;
      _resetIndices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.album.entriesFor(_pose);
    // 타임라인이 갱신되어 entries가 줄어도 RangeError가 나지 않게 build에서 clamp.
    final baseIndex = entries.isEmpty
        ? 0
        : _baseIndex.clamp(0, entries.length - 1);
    final compareIndex = entries.isEmpty
        ? 0
        : _compareIndex.clamp(0, entries.length - 1);
    // 해가 바뀐 타임라인에서 `8/14`가 두 번 나오면 어느 해인지 알 수 없다. 한 해 안에
    // 머무는 흔한 경우엔 연도를 붙이지 않는다 — 없어도 안 헷갈리는 자리에 붙는 연도는
    // 좁은 칩 폭만 잡아먹는다.
    final showYear =
        entries.isNotEmpty && entries.first.date.year != entries.last.date.year;
    final poseLabel = PoseSpec.labelFor(_pose, sequence: widget.poses);

    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseCardHeader(
            title: '체형 분석 타임라인',
            trailing: RiseBadge(poseLabel, variant: RiseBadgeVariant.red),
          ),
          // 포즈 칩 — 조회에 실패했을 땐 띄우지 않는다. 전부 "0장"으로 보여서
          // 사진이 없는 것처럼 읽히고, 눌러 봐야 같은 실패 문구만 반복된다.
          if (!widget.failed) ...[
            _PoseChips(
              album: widget.album,
              poses: widget.poses,
              selected: _pose,
              onSelect: _selectPose,
            ),
            const SizedBox(height: 4),
          ],
          // 조회 실패는 "0장"과 다른 상태 — 같은 탭의 주간 기록(workout_log_list)과
          // 같은 규약으로 실패를 실패라고 말한다.
          if (widget.failed)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '사진을 불러오지 못했어요 — 아래로 당겨 새로고침해주세요',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.danger,
                  height: 1.4,
                ),
              ),
            )
          // "한 장도 없다"와 "이 포즈만 없다"는 다른 사건이다 — 다른 포즈에 사진이
          // 있는데 "아직 촬영한 사진이 없어요"라고 하면, 위 포즈 칩이 장수를 세고
          // 있는 바로 그 화면에서 앞뒤가 안 맞는 말을 하는 셈이 된다.
          else if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                // **"촬영 탭"은 없다.** `app_shell.dart`가 명시한다 — *"촬영은 탭이
                // 아니다(P21)"*. 탭은 4개(홈·예약·기록·마이)이고 촬영은 그 사이의
                // 빨간 원 버튼이라 **선택 상태를 갖지 않는다.** 없는 탭을 찾아
                // 하단바를 훑게 만드는 안내는 안 하느니만 못하다.
                widget.album.isEmpty
                    ? '아직 촬영한 사진이 없어요 — 아래 가운데 빨간 버튼으로 첫 사진을 남겨보세요'
                    : '${PoseSpec.labelFor(_pose, sequence: widget.poses)} 사진은 아직 없어요 — 위에서 다른 포즈를 고르거나 아래 가운데 빨간 버튼으로 남겨보세요',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.muted,
                  height: 1.4,
                ),
              ),
            )
          // 사진 1장으론 "비교"가 성립하지 않는다 — before/after 인덱스가 둘 다 0이라
          // 같은 사진을 좌우에 그려 놓고 슬라이더까지 정상처럼 보여줬다(자기 자신과
          // 비교). 같은 탭의 인바디 추이가 "2회 이상 필요해요"로 막는 것과 같은 가드다
          // (inbody_chart.dart). 찍은 한 장은 감추지 않고 그대로 남긴다.
          else if (entries.length == 1) ...[
            _PhotoTile(
              key: bodyPhotoTileKey(entries.first),
              entry: entries.first,
              role: null,
              showYear: showYear,
              poseLabel: poseLabel,
              onDeleted: widget.onPhotoDeleted,
            ),
            const SizedBox(height: 8),
            const Text(
              '비교하려면 사진이 2장 이상 필요해요 — 다음 촬영 후 나란히 놓고 볼 수 있어요',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ] else ...[
            // 날짜 칩 = 「기준」 선택. 스크러버가 「비교」를 맡으므로 여기서는 왼쪽만
            // 바뀐다 — 한 컨트롤이 두 값을 건드리던 종전 구조가 자기 자신과의 비교를
            // 만들어냈다(클래스 주석).
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < entries.length; i++)
                  RiseChip(
                    label: _shortDate(entries[i].date, withYear: showYear),
                    selected: i == baseIndex,
                    onTap: () => setState(() => _baseIndex = i),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // 눈금 컨트롤 — 두 사진에 **같은 값**이 걸린다(비교의 전제).
            _GridControls(
              on: _grid,
              density: _density,
              onToggle: () => setState(() => _grid = !_grid),
              onDensity: () => setState(() => _density = _density.next),
            ),
            const SizedBox(height: 6),
            // 기준선 드래그는 **두 타일에 걸쳐** 동작한다 — 한쪽에서 어깨에 맞추면
            // 반대쪽에도 같은 높이로 그어진다. 그래서 제스처를 Row 전체에 건다.
            _RefLineDragArea(
              enabled: _grid,
              value: _refLine,
              onChanged: (v) => setState(() => _refLine = v),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PhotoTile(
                      key: bodyPhotoTileKey(entries[baseIndex]),
                      entry: entries[baseIndex],
                      role: '기준',
                      showYear: showYear,
                      poseLabel: poseLabel,
                      onDeleted: widget.onPhotoDeleted,
                      showGrid: _grid,
                      gridDensity: _density,
                      refLine: _grid ? _refLine : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PhotoTile(
                      key: bodyPhotoTileKey(entries[compareIndex]),
                      entry: entries[compareIndex],
                      role: '비교',
                      highlighted: true,
                      showYear: showYear,
                      poseLabel: poseLabel,
                      onDeleted: widget.onPhotoDeleted,
                      showGrid: _grid,
                      gridDensity: _density,
                      refLine: _grid ? _refLine : null,
                    ),
                  ),
                ],
              ),
            ),
            _DateScrubber(
              entries: entries,
              index: compareIndex,
              showYear: showYear,
              onChanged: (i) => setState(() => _compareIndex = i),
            ),
            _comparisonStatus(entries, baseIndex, compareIndex, showYear),
            const SizedBox(height: 2),
          ],
          // 종전 이 자리엔 빨간 슬라이더가 있었는데 **아무것도 하지 않았다** — `_slider`는
          // 자기 값을 읽고 쓸 뿐 두 사진은 고정 50:50 `Expanded`라 끝까지 밀어도 픽셀
          // 하나 안 움직였다. 목업(`목업_회원앱_라이즈_2026-08-14.html:245`)의
          // `<input type="range">`에도 핸들러가 없었으니 **한 번도 동작한 적이 없다.**
          // 지금은 위 `_DateScrubber`가 실제로 오른쪽 사진을 날짜순으로 바꾼다.
          //
          // 문구도 두 군데가 사실이 아니었다:
          //  · "자동 비교" — 회원이 손으로 고른다.
          //  · "코치가 그리드 눈금으로" — 저장 파일에 격자가 없었다. `takePicture()`가
          //    카메라 원본 JPEG을 그대로 주고 격자는 프리뷰 **위에** 얹힌 CustomPaint라,
          //    다 찍고 나면 눈금이 사라졌다. **P46에서 닫았다**: 파일에 굽지 않고
          //    표시할 때 두 사진에 같은 눈금을 얹는다([MeasureGridPhoto] — 굽지 않는
          //    근거는 그 클래스 주석). 어드민 뷰어(BodyPhotoLightbox)는 여전히 맨
          //    `<img>`라 격자가 없다(후속).
          //
          // 아래 문구는 이 화면에서 가장 중요한 한 줄이다 — 회원이 눈으로 보는 크기
          // 차이의 상당 부분이 **몸이 아니라 촬영 거리**에서 온다(2.5m에서 20cm 앞으로
          // 서면 8.7% 커진다. 한 달치 실제 변화는 5% 남짓이다). 이걸 말하지 않으면
          // 화면이 조용히 과장한다.
          const Text(
            '촬영 거리·폰 높이가 매번 조금씩 달라 크기도 달라 보여요 · 그래서 겹치지 않고 나란히 둬요\n'
            '눈금은 사진에 남지 않고 볼 때만 그려요 — 원본은 그대로예요',
            style: AppTypography.note,
          ),
        ],
      ),
    );
  }

  /// 지금 무엇과 무엇을 견주고 있는지 한 줄로. 사진 위 날짜 pill과 **같은 사실**을
  /// 말하지만, 여기엔 두 날짜의 **간격**이 붙는다 — 회원이 알고 싶은 건 "8/14"가
  /// 아니라 "28일 만에 이만큼"이다.
  ///
  /// 손잡이가 기준 위를 지나갈 때 막지 않는다. 막으면 그 지점에서 손잡이가 튕겨
  /// "고장 났다"로 읽힌다 — 대신 같은 사진이라고 **말한다.**
  Widget _comparisonStatus(
    List<BodyPhotoEntry> entries,
    int baseIndex,
    int compareIndex,
    bool showYear,
  ) {
    final base = entries[baseIndex].date;
    final compare = entries[compareIndex].date;
    final String text;
    if (baseIndex == compareIndex) {
      text = '기준과 같은 사진이에요 — 손잡이를 옮기면 다른 날짜와 비교해요';
    } else {
      final days = compare.difference(base).inDays;
      // 과거로 훑는 것도 정당한 행동이라 "뒤"만 말하면 거짓이 된다.
      final gap = days >= 0 ? '$days일 뒤' : '${-days}일 전';
      text =
          '기준 ${_shortDate(base, withYear: showYear)}'
          ' → 비교 ${_shortDate(compare, withYear: showYear)} · $gap';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          color: AppColors.muted,
          height: 1.4,
        ),
      ),
    );
  }
}

/// 「비교」쪽 사진을 날짜순으로 훑는 가로 바.
///
/// **가로여야 한다.** 이 카드는 `records_screen`의 세로 `ListView` 안에 있다. 가로 드래그
/// 대 세로 스크롤은 제스처 아레나가 **축으로 갈라 주지만**(각자 자기 축으로 `kTouchSlop`을
/// 먼저 넘는 쪽이 승낙한다), 세로 대 세로는 갈라 줄 게 없어 동률이면 더 깊은 자식이 이긴다
/// — 사진 위에서 페이지 스크롤이 죽는다. 같은 이유로 이 앱의 `date_strip`은 가로
/// 스크롤러인데도 충돌 처리 코드가 한 줄도 없이 동작한다.
///
/// **Material [Slider]를 직접 쓴다.** 손수 `onHorizontalDragUpdate`로 만들면 아레나 정합·
/// 트랙 탭 폴백·`divisions` 스냅을 다시 짜야 하고, 무엇보다 `isSlider` 시맨틱스를 잃는다.
/// 그게 **드래그를 할 수 없는 회원의 유일한 통로**다 — 손수 만든 드래그 위젯은 스크린리더에
/// "아무것도 아닌 것"으로 노출된다.
///
/// 트랙 탭이 중요한 이유가 하나 더 있다: 엄지는 호를 그려서 처음 몇 픽셀이 세로면
/// `ListView`가 아레나를 가져간다. 그런데 **정지한 포인터에는 세로 드래그 인식기가 절대
/// 승낙하지 않으므로**(움직임이 없어 slop을 못 넘는다) 트랙 탭은 언제나 이긴다.
class _DateScrubber extends StatelessWidget {
  const _DateScrubber({
    required this.entries,
    required this.index,
    required this.showYear,
    required this.onChanged,
  });

  final List<BodyPhotoEntry> entries;
  final int index;
  final bool showYear;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final last = entries.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: AppColors.red,
            inactiveTrackColor: AppColors.trackBg,
            thumbColor: AppColors.red,
            overlayColor: AppColors.redLight,
            activeTickMarkColor: AppColors.redBorder,
            inactiveTickMarkColor: AppColors.line,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
            // 사진이 많아지면 눈금이 촘촘해져 노이즈가 된다 — 그때는 트랙만 남긴다.
            tickMarkShape: entries.length <= 8
                ? const RoundSliderTickMarkShape()
                : SliderTickMarkShape.noTickMark,
          ),
          child: Slider(
            value: index.toDouble(),
            min: 0,
            max: last.toDouble(),
            // **연속값이 아니다.** 사진과 사진 사이엔 아무것도 없으므로 노치 사이를
            // 보간하는 값은 가리킬 대상이 없다.
            divisions: last,
            // `onChangeEnd`가 아니라 `onChanged`다 — 끌면서 바뀌어야 좌우로 까딱하는
            // 블링크 비교가 성립한다. 손을 뗄 때만 바뀌면 그냥 느린 칩이다.
            onChanged: (v) => onChanged(v.round()),
            semanticFormatterCallback: (v) {
              final i = v.round().clamp(0, last);
              return '${_shortDate(entries[i].date, withYear: showYear)}'
                  ' · ${entries.length}장 중 ${i + 1}번째';
            },
          ),
        ),
        // 양 끝 날짜는 슬라이더 **아래 독립 줄**에 둔다. 같은 줄에 넣으면 배율 1.35에서
        // 트랙 폭을 잡아먹는다.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _shortDate(entries.first.date, withYear: showYear),
                style: AppTypography.note,
              ),
              Text(
                _shortDate(entries.last.date, withYear: showYear),
                style: AppTypography.note,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 포즈 선택 칩 — 촬영 탭과 **같은 시퀀스·같은 순서**(+ 시퀀스에서 빠졌지만 사진이 남은 포즈)를
/// 그대로 늘어놓는다. 찍은 순서대로 보게 하려는 것도 있지만, 두 화면이 다른
/// 목록을 보이면 "내가 찍은 그 포즈"를 어디서 찾아야 할지 알 수 없다.
///
/// 장수를 라벨에 함께 실어(0장 포함) **찍지 않은 포즈까지 보여준다** — 목록에서
/// 빼 버리면 회원은 그 포즈를 찍을 수 있다는 사실 자체를 모른다.
class _PoseChips extends StatelessWidget {
  const _PoseChips({
    required this.album,
    required this.poses,
    required this.selected,
    required this.onSelect,
  });

  final records.BodyPhotoAlbum album;
  final List<PoseSpec> poses;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: [
        for (final key in album.poseKeys(poses))
          RiseChip(
            label:
                '${PoseSpec.labelFor(key, sequence: poses)} ${album.countFor(key)}',
            selected: key == selected,
            onTap: () => onSelect(key),
          ),
      ],
    );
  }
}

/// 날짜 칩·타일 라벨 공용.
///
/// [withYear]는 **타임라인이 해를 넘겼을 때만** 켠다. 1년 넘게 다닌 회원의 `8/14`가
/// 두 개면 어느 해인지 알 방법이 없고, 하필 그 회원이 이 화면을 가장 오래 쓴다.
/// 반대로 한 해 안에 머무는 흔한 경우엔 연도가 좁은 칩 폭만 잡아먹는다.
String _shortDate(DateTime d, {bool withYear = false}) =>
    withYear ? "'${d.year % 100} ${d.month}/${d.day}" : '${d.month}/${d.day}';

/// 사진 한 장 — **로딩 / 실패(재시도) / 실사진** 3상태.
///
/// 이 카드는 한 번에 두 장(before·after)만 그린다. 그래서 화면에 있는 것만 로드하면
/// 되고, 섬네일 파이프라인 없이도 v1이 성립한다. 대신 원본을 디코드하므로
/// [cacheWidth]로 디코드 해상도를 낮춘다 — 장당 원본 디코드(수 MB RAM)가 진짜 병목이다.
///
/// 실패를 "사진 없음"으로 위장하지 않는다(이 앱의 실패 규약) — 이유와 재시도를 준다.
/// 사진 타일의 식별 키 — 테스트가 "몇 장이 나란히 떴는가"를 셀 수 있게 한다.
///
/// 종전엔 테스트가 `Slider`의 **존재**로 비교 UI를 판정했는데, 그 슬라이더는
/// 아무것도 하지 않는 죽은 컨트롤이었다(P31에서 제거). 존재가 곧 동작으로
/// 취급되면 그런 걸 영영 못 잡는다 — 이제 실제로 보이는 것을 센다.
///
/// **`storagePath`가 아니라 `id`로 만든다.** 경로는 nullable이고, 서버가 빈 경로를
/// 막기 시작한 v2.10 **이전에 저장된 레코드가 남아 있다**(`_load`의 같은 주석) —
/// 그런 사진이 둘이면 키가 나란히 `body-photo-tile-null`이 되어 서로 구별되지 않는다.
/// `id`는 required라 그 구멍이 없다.
Key bodyPhotoTileKey(BodyPhotoEntry entry) =>
    ValueKey('body-photo-tile-${entry.id}');

/// 눈금 컨트롤 — 켜기/끄기 + 촘촘함. 두 사진에 같은 값이 걸리므로 컨트롤도 하나다.
class _GridControls extends StatelessWidget {
  const _GridControls({
    required this.on,
    required this.density,
    required this.onToggle,
    required this.onDensity,
  });

  final bool on;
  final GridDensity density;
  final VoidCallback onToggle;
  final VoidCallback onDensity;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        RiseChip(label: on ? '눈금 켜짐' : '눈금 꺼짐', selected: on, onTap: onToggle),
        if (on) ...[
          const SizedBox(width: 4),
          RiseChip(label: density.label, selected: false, onTap: onDensity),
        ],
        const Spacer(),
        if (on)
          const Flexible(
            child: Text(
              '빨간 선을 끌어 맞춰보세요',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.note,
            ),
          ),
      ],
    );
  }
}

/// 기준선 드래그 영역 — 두 타일을 함께 감싼다.
///
/// 타일 **안**에 제스처를 두지 않는 이유: 그러면 왼쪽에서 끈 선과 오른쪽에서 끈 선이
/// 따로 놀아 눈금자가 두 개가 된다. 여기서 한 번 받아 두 사진에 같은 값을 내려보낸다.
/// 세로 드래그만 가로챈다 — 탭(확대)과 가로 스크롤은 그대로 통과한다.
class _RefLineDragArea extends StatefulWidget {
  const _RefLineDragArea({
    required this.enabled,
    required this.value,
    required this.onChanged,
    required this.child,
  });

  final bool enabled;
  final double value;
  final ValueChanged<double> onChanged;
  final Widget child;

  @override
  State<_RefLineDragArea> createState() => _RefLineDragAreaState();
}

class _RefLineDragAreaState extends State<_RefLineDragArea> {
  double? _height;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          // 타일 탭(뷰어 열기)을 막지 않도록 **세로 드래그만** 가져간다.
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (d) => _height = context.size?.height,
          onVerticalDragUpdate: (d) {
            final h = _height ?? context.size?.height;
            if (h == null || h <= 0) return;
            widget.onChanged((widget.value + d.delta.dy / h).clamp(0.02, 0.98));
          },
          child: widget.child,
        );
      },
    );
  }
}

class _PhotoTile extends ConsumerStatefulWidget {
  const _PhotoTile({
    super.key,
    required this.entry,
    required this.role,
    required this.showYear,
    required this.poseLabel,
    required this.onDeleted,
    this.highlighted = false,
    this.showGrid = false,
    this.gridDensity = GridDensity.coarse,
    this.refLine,
  });

  /// 계측 격자 표시 여부 — 두 타일이 **같은 값**을 받는다(비교의 전제).
  final bool showGrid;
  final GridDensity gridDensity;

  /// 두 사진이 공유하는 가로 기준선(0~1). 회원이 끌어 옮긴다.
  final double? refLine;

  final BodyPhotoEntry entry;

  /// 「기준」/「비교」. 사진 1장이라 비교가 성립하지 않으면 null(배지를 달지 않는다).
  final String? role;
  final bool showYear;

  /// 뷰어 상단에 띄울 포즈 이름. 뷰어는 타임라인 밖이라 문맥이 따라가지 않는다.
  final String poseLabel;

  /// 삭제 성공 후 목록을 다시 받아온다. null이면 뷰어에 삭제 버튼을 띄우지 않는다.
  final VoidCallback? onDeleted;
  final bool highlighted;

  @override
  ConsumerState<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends ConsumerState<_PhotoTile> {
  Future<Result<Uint8List>>? _future;

  /// 캐시에 이미 있던 바이트 — 있으면 [FutureBuilder]를 아예 거치지 않는다.
  ///
  /// 스크러버로 노치를 넘을 때마다 `FutureBuilder`가 한 프레임 스피너를 그리면
  /// **블링크 비교가 성립하지 않는다**(눈이 좇아야 할 차이가 깜빡임에 묻힌다).
  /// 이미 본 사진끼리 왕복하는 게 이 컨트롤의 가장 흔한 사용법이라 그 경로가
  /// 반드시 즉시여야 한다.
  Uint8List? _cached;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PhotoTile old) {
    super.didUpdateWidget(old);
    // 날짜 칩·포즈 칩·스크러버를 움직이면 같은 자리에 다른 사진이 온다.
    if (old.entry.storagePath != widget.entry.storagePath) _load();
  }

  void _load() {
    final path = widget.entry.storagePath;
    if (path == null || path.isEmpty) {
      setState(() {
        _cached = null;
        _future = Future.value(
          const Err<Uint8List>(RejectedFailure('사진 파일 정보가 없어요')),
        );
      });
      return;
    }
    final loader = ref.read(bodyPhotoLoaderProvider);
    final hit = loader.peek(path);
    setState(() {
      _cached = hit;
      _future = hit != null ? null : loader.load(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = _shortDate(widget.entry.date, withYear: widget.showYear);
    return Semantics(
      image: true,
      label: widget.role == null ? '체형 사진 $label' : '${widget.role} 사진 $label',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        // 종전엔 `height: 130` 고정이라 320dp에서 타일이 129×130 ≒ **정사각**이었고,
        // 3:4 사진을 `cover`로 채우면 세로의 24.4%(위아래 12.2%씩)가 잘렸다 — 9:16이면
        // 43.3%. **촬영 격자가 정렬 기준으로 삼은 어깨선·골반선·발이 프레임 밖이었다.**
        // 비교 대상이 안 보이는 비교 UI는 연극이다.
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            decoration: BoxDecoration(
              // 레터박스 바닥. `cover`로 잘라내는 대신 남는 자리를 띠로 두는데,
              // **띠는 몸의 변화로 오해될 수 없다** — 이게 `contain`을 고르는 진짜
              // 이유다. `cover`는 비율이 다른 두 사진을 서로 다르게 잘라내서
              // 그 자체로 없는 차이를 만든다.
              color: widget.highlighted ? AppColors.redLight : AppColors.chipBg,
              border: widget.highlighted
                  ? Border.all(color: AppColors.redBorder)
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: _content(label),
          ),
        ),
      ),
    );
  }

  Widget _content(String label) {
    // 캐시 히트는 Future를 거치지 않는다 — 스크러버가 노치를 넘을 때 스피너가
    // 번쩍이면 블링크 비교가 죽는다.
    final cached = _cached;
    if (cached != null) return _photo(cached, label);

    return FutureBuilder<Result<Uint8List>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _shell(
            label,
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.muted,
              ),
            ),
          );
        }
        final result = snap.data;
        if (result is Ok<Uint8List>) return _photo(result.value, label);

        final message = result is Err<Uint8List>
            ? result.failure.message
            : '사진을 불러오지 못했어요';
        return _shell(
          label,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: AppColors.danger),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: _load,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    '다시 시도',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Hero 태그에 **슬롯을 함께 넣는다.** 경로만 쓰면 기준과 비교가 같은 사진일 때
  /// (스크러버가 기준 위를 지나가는 정상 경로다) 같은 태그가 화면에 둘이 되어
  /// Flutter가 assert를 던진다.
  String get _heroTag =>
      'body-photo-${widget.role ?? 'solo'}-${widget.entry.id}';

  Widget _photo(Uint8List bytes, String label) => Semantics(
    // 우하단 확대 힌트가 시각으로 말하는 것("누르면 커진다")의 비시각 등가물 —
    // 탭 액션이 이 서브트리(GestureDetector)에 있으므로 힌트도 여기 얹는다.
    onTapHint: '크게 보기',
    child: GestureDetector(
      // **성공 상태에서만 탭이 열린다.** 로딩·실패 타일을 눌러 빈 뷰어가 뜨면
      // 회원은 사진이 사라진 걸로 읽는다(실패 타일엔 이미 "다시 시도"가 있다).
      onTap: () => showBodyPhotoViewer(
        context,
        entry: widget.entry,
        bytes: bytes,
        poseLabel: widget.poseLabel,
        heroTag: _heroTag,
        onDeleted: widget.onDeleted,
        // 뷰어도 같은 눈금으로 연다 — 타일에서 맞춰 둔 기준선이 확대하면
        // 사라진다면, 정작 자세히 볼 때 잴 것이 없어진다.
        showGrid: widget.showGrid,
        gridDensity: widget.gridDensity,
        refLine: widget.refLine,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: _heroTag,
            // 격자는 이미지 실영역에만 올라간다(레터박스 제외) — 눈금이 사진 밖으로
            // 새면 위치가 어긋나 비교가 틀린다.
            child: MeasureGridPhoto(
              bytes: bytes,
              showGrid: widget.showGrid,
              density: widget.gridDensity,
              refLine: widget.refLine,
              // 디코드 해상도 제한 — 타일이 172dp 높이라 원본 해상도가 필요 없다.
              // (캐시가 든 건 원본 JPEG 바이트 전부라 이건 디코드 쪽만 아낀다.)
              cacheWidth: 720,
            ),
          ),
          // 어느 쪽이 기준인지 사진 위에서 바로 읽혀야 한다 — 눈은 사진을 보지
          // 캡션을 보지 않는다.
          if (widget.role != null)
            Positioned(
              left: 6,
              top: 6,
              child: _pill(
                widget.role!,
                background: widget.highlighted
                    ? AppColors.red
                    : Colors.black.withValues(alpha: 0.55),
              ),
            ),
          // 날짜는 사진 위에 얹는다(사진이 자리를 다 쓰게).
          Positioned(
            left: 6,
            bottom: 6,
            child: _pill(
              label,
              background: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          // 눌러서 크게 볼 수 있다는 걸 말없이 알린다. 129dp 타일에서 회원이
          // 판독하려는 건 어깨선·허리 윤곽인데 그 크기로는 보이지 않는다.
          // 탭 핸들러는 달지 않는다(앞으로도 금지) — 타일 전체가 탭 영역이라
          // 지금은 이 원을 조준해 눌러도 성공하지만, 여기에만 핸들러를 붙이는
          // 순간 44dp 미달의 독립 터치타깃이 된다. 스크린리더에는 장식으로 제외
          // (같은 정보는 위 Semantics.onTapHint가 말한다).
          Positioned(
            right: 6,
            // 날짜 pill(높이 ~18)과 수직 중심을 맞춘다 — 같은 bottom: 6이면
            // 지름 20 원의 중심이 1dp 떠서 바닥선이 어긋나 보인다.
            bottom: 5,
            child: ExcludeSemantics(
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const RiseIcon(
                  RiseIcons.expand,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _pill(String text, {required Color background}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 10, color: Colors.white),
    ),
  );

  Widget _shell(String label, Widget child) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      const SizedBox(height: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: widget.highlighted ? AppColors.red : AppColors.muted,
        ),
      ),
    ],
  );
}
