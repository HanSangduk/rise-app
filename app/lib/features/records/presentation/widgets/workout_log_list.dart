import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_typography.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

/// 목업 "운동" 탭 — 세션별 세트/무게 + 코치 코멘트 + Home Work 주간 기록.
/// v1.4: GET /v1/workout-logs·/v1/hw-checks 실데이터 렌더.
class WorkoutLogList extends StatelessWidget {
  const WorkoutLogList({
    super.key,
    required this.logs,
    required this.homeworkWeeks,
    this.homeworkWeeksFailed = false,
  });

  final List<WorkoutLog> logs;
  final List<HomeworkWeekSummary> homeworkWeeks;

  /// hw-checks 조회 실패 — 빈 목록(기록 없음)과 구분해 실패 문구를 보여준다.
  final bool homeworkWeeksFailed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 빈 상태도 **카드 안에** 둔다. 이 탭의 다른 빈 상태(아래 Home Work 주간 기록)와
        // 다른 탭들(원장·예약·슬롯)은 전부 카드 안에서 말하는데, 여기만 카드 밖 맨
        // 텍스트라 기록이 없는 회원에게는 카드 위에 문장 한 줄이 떠 있는 화면이 됐다
        // (실기기 확인). 같은 자리에 교대로 나타나는 표현은 같은 골격을 써야 한다.
        if (logs.isEmpty)
          const RiseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RiseCardHeader(title: '수업 기록'),
                Text(
                  '아직 수업 기록이 없어요 — 첫 수업 후 코치가 남겨줘요',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ],
            ),
          )
        else
          for (final log in logs) _WorkoutLogCard(log: log),
        RiseCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RiseCardHeader(title: 'Home Work 주간 기록'),
              // 조회 실패는 "기록 없음"과 다른 상태 — 부분 실패를 빈 상태로 위장하지 않는다.
              if (homeworkWeeksFailed)
                const Text(
                  '주간 기록을 불러오지 못했어요 — 아래로 당겨 새로고침해주세요',
                  style: TextStyle(fontSize: 11.5, color: AppColors.danger),
                )
              else if (homeworkWeeks.isEmpty)
                const Text(
                  '아직 체크한 Home Work가 없어요',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                )
              else
                // 마지막 행의 구분선은 카드 하단 보더와 겹쳐 이중선으로 보인다 —
                // 목업 `.row:last-child{border-bottom:0}`와 같은 규약(pass_list 참조).
                // 마지막을 알아야 하므로 인덱스 루프.
                for (final (i, w) in homeworkWeeks.indexed)
                  RiseRow(
                    showDivider: i < homeworkWeeks.length - 1,
                    child: Text(w.label),
                    trailing: Text(
                      w.done == w.total ? '${w.done}/${w.total} 완료' : '${w.done}/${w.total} · 진행중',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: w.done == w.total ? AppColors.ok : AppColors.ink,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkoutLogCard extends StatelessWidget {
  const _WorkoutLogCard({required this.log});
  final WorkoutLog log;

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseCardHeader(
            title: '${DateFmt.monthDayWeekday(log.date)} · ${log.title}',
            trailing: const RiseBadge('완료', variant: RiseBadgeVariant.ok),
          ),
          // 마지막 운동 행의 구분선은 코치 코멘트 블록이 뒤따를 때만 의미가 있다
          // — 코멘트가 없으면 카드 하단 보더와 겹쳐 이중선이 된다.
          for (final (i, ex) in log.exercises.indexed)
            RiseRow(
              showDivider: i < log.exercises.length - 1 || log.coachComment != null,
              child: Text(ex.name),
              trailing: Text(_entryLabel(ex), style: AppTypography.bodyStrong),
            ),
          if (log.coachComment != null)
            Container(
              margin: const EdgeInsets.only(top: 7),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              // 반경 9는 목업 근거가 있는 일회성 값(운동 기록 코멘트 박스) — 유지.
              decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(9)),
              child: Text('코치 코멘트 — "${log.coachComment}"', style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  /// "3×12 · 60kg" 표기 — 빈 세그먼트 조합("0×12"·"3× · 자중") 방지:
  /// sets<=0이면 "n×" 생략, reps가 비면 reps 생략(둘 다 있을 때만 "n×reps").
  /// 계약 v1.4: weight_kg 0 = 자중.
  String _entryLabel(ExerciseEntry ex) {
    final hasSets = ex.sets > 0;
    final hasReps = ex.reps.trim().isNotEmpty;
    final setsReps = hasSets && hasReps
        ? '${ex.sets}×${ex.reps}'
        : hasSets
            ? '${ex.sets}세트'
            : hasReps
                ? ex.reps
                : '';
    final weight = ex.weightKg == 0 ? '자중' : _fmtWeight(ex.weightKg);
    return setsReps.isEmpty ? weight : '$setsReps · $weight';
  }

  String _fmtWeight(double kg) => kg == kg.roundToDouble() ? '${kg.toInt()}kg' : '${kg}kg';
}
