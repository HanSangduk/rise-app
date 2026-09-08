import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/records/domain/inbody_metrics.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/presentation/records_view_model.dart';

/// 인바디 최근 기록 + **정정 경로(삭제)**.
///
/// 입력 폼과 한 묶음이다. 이 리스트가 없으면 회원이 잘못 옮겨 적은 숫자를 지울
/// 방법이 앱에 하나도 없고, 오입력이 차트에 영구히 남는다(수정 PUT은 만들지
/// 않는다 — 삭제 후 재입력으로 충분하고 API 면적이 절반이다).
///
/// 삭제 액션은 `source == 'member_self'`인 **본인 기록에만** 붙는다. 코치가 넣은
/// 기록은 회원이 지울 대상이 아니고, 출처가 아예 없는(`null`) 예전 레코드는
/// "본인 것"이라고 단정할 근거가 없다.
class InbodyRecentList extends StatefulWidget {
  const InbodyRecentList({super.key, required this.records});

  /// 전체 기록(**오래된 순** — RecordsData가 그렇게 정렬해 준다).
  final List<InbodyRecord> records;

  /// 카드가 스크롤 화면을 삼키지 않게 처음엔 최근 것만 보여준다. 다만 **접힌
  /// 채로 끝나면 안 된다** — 입력 시트가 2년 소급을 허용하므로 5건 밖 날짜의
  /// 셀프 기록이 생기고, 같은 날 409의 안내("기존 기록을 지우고 다시")는 그
  /// 기록을 지울 수 있어야 따라갈 수 있다. 그래서 아래 "더 보기"가 전체를 연다.
  static const maxRows = 5;

  @override
  State<InbodyRecentList> createState() => _InbodyRecentListState();
}

class _InbodyRecentListState extends State<InbodyRecentList> {
  /// "더 보기"로 전체를 펼쳤는지. 접는 길은 두지 않는다 — 펼침은 회원이 옛
  /// 기록을 찾는 중이라는 뜻이고, 삭제 후 재조회로 목록이 갈려도 펼친 채
  /// 남아 있어야 지운 자리를 확인할 수 있다.
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final records = widget.records;
    if (records.isEmpty) return const SizedBox.shrink();
    final newestFirst = records.reversed.toList();
    final visible =
        _showAll ? newestFirst : newestFirst.take(InbodyRecentList.maxRows).toList();
    final hiddenCount = newestFirst.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          '최근 기록',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.muted),
        ),
        const SizedBox(height: 2),
        for (final (i, r) in visible.indexed)
          RiseRow(
            // 마지막 행 아래에 "더 보기"가 이어지면 경계선을 남긴다.
            showDivider: i < visible.length - 1 || hiddenCount > 0,
            // 삭제 버튼이 44dp라 행도 그만큼 잡아 준다(구분선이 행 경계에 붙게).
            minHeight: 44,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFmt.monthDayWeekday(r.date),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                Text(
                  // 6개를 다 늘어놓으면 행이 넘친다 — 위 수치 행이 이미 최신
                  // 6지표를 다 보여주므로, 여기선 어느 날 기록인지 알아볼
                  // 최소한(체중·SMM·PBF)만 싣는다.
                  '${InbodyMetric.weight.display(r)} · '
                  'SMM ${InbodyMetric.smm.display(r)} · '
                  'PBF ${InbodyMetric.pbf.display(r)}',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                ),
              ],
            ),
            trailing: _RowAction(record: r),
          ),
        if (hiddenCount > 0)
          TextButton(
            onPressed: () => setState(() => _showAll = true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.muted,
              // 카드 안 인라인 액션 44dp 타깃(삭제 버튼과 같은 기준) + 전폭 —
              // 리스트 끝의 "계속 있음" 신호라 행처럼 눌리는 게 자연스럽다.
              minimumSize: const Size.fromHeight(44),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            // 몇 건이 감춰져 있는지 말한다 — "더 보기"만으로는 다 보여주고 있는
            // 화면과 구분이 안 된다.
            child: Text('이전 기록 $hiddenCount건 더 보기'),
          ),
      ],
    );
  }
}

class _RowAction extends ConsumerWidget {
  const _RowAction({required this.record});
  final InbodyRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (record.isMemberSelf) {
      return TextButton(
        onPressed: () => _confirmAndDelete(context, ref),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.danger,
          // 카드 안 인라인 액션도 44dp 타깃(세그먼트·예약 버튼과 같은 기준).
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        child: const Text('삭제'),
      );
    }
    // 출처가 있고 본인이 아니면 왜 삭제가 없는지 말해 준다. 출처가 아예 없는
    // 예전 레코드는 누가 넣었는지 모르므로 아무 말도 하지 않는다 — 모르는 것을
    // "센터 기록"이라고 단정하면 그게 새로운 거짓말이다.
    if (record.source != null) {
      return const Text('센터 기록', style: TextStyle(fontSize: 10.5, color: AppColors.muted));
    }
    return const SizedBox.shrink();
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('인바디 기록 삭제'),
        // 비가역 동작이라 결과를 구체적으로 말한다: 어느 날 기록이며, 되돌릴
        // 수단이 없고(수정 API가 없다), 추이 그래프에서도 사라진다는 것까지.
        content: Text(
          '${DateFmt.isoDate(record.date)} 기록을 삭제할까요?\n\n'
          '삭제하면 되돌릴 수 없어요 — 추이 그래프와 최근 기록에서 함께 사라져요.\n'
          '잘못 넣은 값이라면 삭제한 뒤 다시 입력해주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('아니요'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref.read(recordsViewModelProvider.notifier).deleteInbody(record.id);
    if (!context.mounted) return;
    switch (result) {
      case Ok():
        ScaffoldMessenger.of(context)
            .showSnackBar(riseSnackBar('인바디 기록을 삭제했어요', kind: RiseSnackKind.ok));
      case Err(:final failure):
        showFailureSnackBar(context, failure);
    }
  }
}
