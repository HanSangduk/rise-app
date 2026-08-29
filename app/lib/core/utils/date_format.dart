import 'package:clock/clock.dart';

/// 날짜/슬롯키 변환 유틸 — API계약_v1.md 포맷 고정:
/// 날짜 "2026-08-14" · slotKey "20260814-20" (YYYYMMDD-HH).
/// 순수 Dart(Flutter 의존 0) — 여러 feature(home/booking/records/bodycheck)가 공용.
/// 유일한 외부 의존은 시계 주입용 `package:clock`이다([nowKst] 주석).
///
/// ## 시간축 규약 — "센터 벽시계 표현"
///
/// 서버는 전 계층이 **고정 KST(+09:00)** 로 판정한다
/// (`backend/internal/domain/booking.go`의 `KST = time.FixedZone("KST", 9*60*60)`,
/// `backend/internal/api/service.go`의 `today()`). slotKey의 "20260814-20"도 KST 벽시계다.
///
/// [slotKeyToDateTime]은 그 벽시계 숫자를 **DateTime의 필드에 그대로** 담는다(로컬 플래그).
/// 표시([hhmm]·[monthDayWeekday])와 날짜 단위 비교(`_dateOnly`, `PassHold.contains`)가
/// 기기 타임존과 무관하게 언제나 "센터가 말하는 그 시각"을 가리키게 하려는 선택이다 —
/// 절대 시각으로 바꾸면 해외 기기에서 8/15 09:00(KST) 슬롯이 8/14로 읽혀 유효기간·홀딩
/// 판정이 하루씩 어긋난다.
///
/// 대가는 하나뿐이다: **"지금"과 비교할 때 `DateTime.now()`를 쓰면 안 된다.** 그건 기기
/// 로컬 시각이라 표현이 다르다(해외 체류·기기 시계 오설정 시 최대 오프셋 차만큼 어긋난다).
/// 같은 표현끼리 비교하도록 [nowKst]([todayKst])를 쓴다.
///
/// ## "지금"은 한 번 읽고 굳히지 않는다
///
/// [nowKst]는 **부르는 순간**의 시계를 읽는다. 그 값을 repository에서 한 번 읽어
/// 모델 필드(`canCheckIn` 같은 bool)에 담아 올리면, 그 판정은 로드 시점에 굳어
/// 시간이 흘러도 바뀌지 않는다 — 회원이 앱을 켜 둔 채 기다리면 창이 열려도 버튼이
/// 회색으로 남는다(P51). 시각에 의존하는 값은 **필드가 아니라 `now`를 받는 파생
/// 계산**으로 두고(`NextBooking.canCheckInAt` 등), 화면은 경계 시각에 스스로 다시
/// 그린다([TimeBoundaryBuilder]).
abstract final class DateFmt {
  /// 센터 운영 타임존의 고정 오프셋 — v1은 한국 단일 센터. 서버와 같은 값
  /// (`domain.KST`). tzdata에 의존하지 않으려고 서버도 고정 오프셋을 쓴다.
  static const kstOffset = Duration(hours: 9);

  /// 절대 시각 [instant]를 **센터(KST) 벽시계 표현**으로 환산한다 —
  /// [slotKeyToDateTime]이 만드는 것과 같은 표현이라 그대로 비교·표시할 수 있다.
  ///
  /// 시계를 읽지 않는 순수 함수다(테스트가 시각을 주입한다).
  /// 주의: 기기가 서머타임을 쓰는 지역이고 환산 결과가 마침 "존재하지 않는 벽시계"
  /// (봄철 1시간 점프 구간)이면 Dart가 1시간 앞으로 정규화한다 — 한국엔 DST가 없어
  /// 센터 시각 쪽은 안전하고, 기기 쪽 영향은 연 2회 1시간 경계뿐이다.
  static DateTime toKst(DateTime instant) {
    final k = instant.toUtc().add(kstOffset);
    return DateTime(k.year, k.month, k.day, k.hour, k.minute, k.second, k.millisecond, k.microsecond);
  }

  /// 센터(KST) 기준 **현재 시각**. 슬롯·예약 시각과 비교할 땐 `DateTime.now()` 대신 이걸 쓴다.
  /// 기기 시계가 KST면 `DateTime.now()`와 같은 값이라 국내 사용엔 변화가 없다.
  ///
  /// 시계는 `package:clock`을 거쳐 읽는다 — `clock.now()`의 기본값이 곧
  /// `DateTime.now()`라 운영 동작은 그대로고, 테스트만 `withClock(Clock.fixed(...))`로
  /// "지금"을 고정해 시간창 경계(±30분·컷오프·자정)를 실제로 기다리지 않고 검증한다.
  /// 존(zone) 스코프라 테스트 간 누수가 없다(전역 가변 훅과 다른 점).
  static DateTime nowKst() => toKst(clock.now());

  /// 센터(KST) 기준 **오늘**(자정으로 자름) — 날짜 단위 판정·기본 날짜·데이트피커용.
  static DateTime todayKst() {
    final k = nowKst();
    return DateTime(k.year, k.month, k.day);
  }

  /// slotKey("20260814-20") → 센터(KST) 벽시계 표현의 DateTime(클래스 주석의 규약 참고).
  static DateTime slotKeyToDateTime(String slotKey) {
    final parts = slotKey.split('-');
    final ymd = parts[0];
    final hour = int.parse(parts[1]);
    return DateTime(
      int.parse(ymd.substring(0, 4)),
      int.parse(ymd.substring(4, 6)),
      int.parse(ymd.substring(6, 8)),
      hour,
    );
  }

  static String toSlotKey(DateTime date, int hour) {
    return '${_ymd(date)}-${hour.toString().padLeft(2, '0')}';
  }

  /// "2026-08-14" (계약 날짜 포맷, GET 쿼리·body 공용).
  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  static const _weekdayKo = ['월', '화', '수', '목', '금', '토', '일'];

  /// "8/14 (금)" 표시용.
  static String monthDayWeekday(DateTime date) =>
      '${date.month}/${date.day} (${_weekdayKo[date.weekday - 1]})';

  /// "20:00" 표시용.
  static String hhmm(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
