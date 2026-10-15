import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/features/my/domain/my_models.dart';

/// 목업 "이용 내역 (PT 20회 원장)" — 최근 몇 건만 보여주고 "전체 ▾"로 펼침.
class LedgerList extends StatefulWidget {
  const LedgerList({
    super.key,
    required this.passLabel,
    required this.entries,
    this.failed = false,
  });

  final String passLabel;

  /// 최신순으로 정렬되어 들어온다고 가정.
  final List<LedgerEntry> entries;

  /// 이 패스의 원장 조회 실패(MySummary.ledgerFailedPassIds) — 빈 목록을
  /// "아직 내역이 없어요"로 위장하지 않기 위한 플래그. 수십 회 이력이 있는
  /// 회원에게 "이력 0"이라고 말하는 것이 이 화면이 할 수 있는 최악의 거짓말이다.
  final bool failed;

  @override
  State<LedgerList> createState() => _LedgerListState();
}

class _LedgerListState extends State<LedgerList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final visibleCount = _expanded ? entries.length : (entries.length < 3 ? entries.length : 3);
    final visible = entries.take(visibleCount).toList();
    final rest = entries.length - visibleCount;
    // "… 이전 내역 n건" 행이 목록 뒤에 붙는지 — 마지막 내역 행의 구분선 유지 여부를 가른다.
    final hasMoreRow = !_expanded && rest > 0;

    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseCardHeader(title: '이용 내역 (${widget.passLabel} 원장)'),
          // 조회 실패는 "내역 없음"과 다른 상태 — 계약 카드(contracts_row)·
          // Home Work 주간 기록(workout_log_list)과 같은 규약·같은 문구 뼈대.
          if (widget.failed)
            const Text(
              '이용 내역을 불러오지 못했어요 — 아래로 당겨 새로고침해주세요',
              style: TextStyle(fontSize: 11.5, color: AppColors.danger, height: 1.4),
            )
          else if (visible.isEmpty)
            const Text('아직 내역이 없어요', style: TextStyle(fontSize: 11.5, color: AppColors.muted))
          else
            // 마지막 행의 구분선은 뒤에 "… 이전 내역 n건" 행이 있을 때만 의미가 있다
            // — 전부 펼쳐진 상태에선 카드 하단 보더와 겹쳐 이중선이 된다.
            for (final (i, e) in visible.indexed)
              RiseRow(
                showDivider: i < visible.length - 1 || hasMoreRow,
                child: Text('${DateFmt.monthDayWeekday(e.at)} ${e.reason.label}'),
                trailing: Text(
                  e.delta == 0 ? '0' : (e.delta > 0 ? '+${e.delta}' : '${e.delta}'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: e.delta < 0 ? AppColors.danger : (e.delta > 0 ? AppColors.ok : AppColors.muted),
                  ),
                ),
              ),
          if (hasMoreRow)
            // 스크린리더가 "버튼"으로 읽게 — InkWell만으로는 탭 동작만 있고 역할이 없다(수업 기록 "더 보기"와 같은 구성).
            Semantics(
              container: true,
              button: true,
              child: InkWell(
                onTap: () => setState(() => _expanded = true),
                child: RiseRow(
                  showDivider: false,
                  minHeight: 44,
                  child: Text('… 이전 내역 $rest건', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  trailing: const Text('전체', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
