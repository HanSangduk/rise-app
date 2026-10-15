import 'package:rise_member/features/records/domain/records_models.dart';

/// 순수 함수 — HwCheck(일 단위 체크, GET /v1/hw-checks?member=)를 주 단위(월~일)로
/// 집계해 "Home Work 주간 기록" 요약을 만든다(v1.4 — mock 대체 실데이터 집계).
/// Flutter/외부 의존 0, codegen 0.
abstract final class HomeworkWeekRules {
  /// [checks]를 [now] 기준 최근 [weeks]주(이번 주 포함, 월요일 시작~일요일 끝)로 집계.
  ///
  /// - done = 그 주에 체크된 항목 수, total = 그 주 체크 문서들의 done 배열 전체 길이 합.
  /// - 체크 문서가 하나도 없는 주는 행을 만들지 않는다(0/0 노이즈 방지) — 이번 주 포함.
  /// - 라벨: 이번 주 / 지난 주 / N주 전. 반환 순서는 최신 주 먼저.
  static List<HomeworkWeekSummary> summarize({
    required DateTime now,
    required List<HomeworkCheckDay> checks,
    int weeks = 4,
  }) {
    // 주 경계 산술은 **UTC 생성자**로 한다(P73). 로컬 플래그 `DateTime`의 `subtract(days: 7)`은
    // 절대 시각 −168시간이라, 기기가 서머타임 지역이면 전환 주의 월요일 자정이 1시간 밀려
    // 그 경계에 놓인 체크(전환일 당일)가 어느 주에도 들지 않았다. 여기서 필요한 건 달력
    // 날짜뿐이므로 필드만 UTC로 옮기면 기기 타임존 규칙이 개입할 자리가 없다(비교 대상
    // `d`도 같은 UTC 표현이라 대칭이다).
    final today = DateTime.utc(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - DateTime.monday));

    final out = <HomeworkWeekSummary>[];
    for (var i = 0; i < weeks; i++) {
      final start = thisMonday.subtract(Duration(days: 7 * i));
      final end = start.add(const Duration(days: 6));

      var done = 0;
      var total = 0;
      for (final c in checks) {
        final d = DateTime.utc(c.date.year, c.date.month, c.date.day);
        if (d.isBefore(start) || d.isAfter(end)) continue;
        total += c.done.length;
        done += c.done.where((v) => v).length;
      }
      if (total == 0) continue;

      out.add(HomeworkWeekSummary(label: _label(i), done: done, total: total, isCurrent: i == 0));
    }
    return out;
  }

  static String _label(int weeksAgo) => switch (weeksAgo) {
        0 => '이번 주',
        1 => '지난 주',
        _ => '$weeksAgo주 전',
      };
}
