/// 순수 함수 — Homework.schedule {type:"once|weekly", days:[], from, to}이
/// 주어진 날짜에 해당하는지 판정(API계약_v1.md). Flutter/외부 의존 0, codegen 0.
///
/// 요일 문자열은 계약 예시("tue","fri")대로 mon/tue/wed/thu/fri/sat/sun 소문자 3글자.
abstract final class HomeworkScheduleRules {
  static const _weekdayWire = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  /// [date]에 이 스케줄의 Home Work가 "오늘 할 일"로 노출되어야 하면 true.
  ///
  /// - schedule 없음([type]이 null): 매일 노출(스케줄 미지정 데이터 호환).
  /// - weekly: 오늘 요일이 [days]에 포함(+ [from]/[to]가 있으면 그 기간 내).
  ///   [days]가 비면 매일로 간주.
  /// - once: [from]~[to] 기간 내([to] 없으면 [from] 당일만). [from] 없으면 매일 취급.
  ///
  /// [from]/[to]는 계약 날짜 포맷 "2026-08-14" — ISO 문자열 비교로 판정한다.
  static bool isActiveOn({
    required DateTime date,
    String? type,
    List<String> days = const [],
    String? from,
    String? to,
  }) {
    if (type == null) return true;

    final iso = _isoDate(date);
    if (type == 'once') {
      if (from == null || from.isEmpty) return true;
      final end = (to == null || to.isEmpty) ? from : to;
      return from.compareTo(iso) <= 0 && iso.compareTo(end) <= 0;
    }

    // weekly(및 알 수 없는 type은 weekly로 폴백).
    if (from != null && from.isNotEmpty && iso.compareTo(from) < 0) return false;
    if (to != null && to.isNotEmpty && iso.compareTo(to) > 0) return false;
    if (days.isEmpty) return true;
    return days.contains(_weekdayWire[date.weekday - 1]);
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
