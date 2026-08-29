// 순수 도메인 — 셀프 체크인 시간창. Flutter/외부 의존 0, codegen 0.

/// 셀프 체크인 시간창(P44) — 서버 판정의 거울.
///
/// 서버 원본은 `backend/internal/domain/checkin.go`:
/// ```go
/// const CheckinWindow = 30 * time.Minute
/// if now.Before(start.Add(-CheckinWindow)) || now.After(start.Add(CheckinWindow)) { … }
/// ```
/// 즉 **닫힌 구간** `[시작−30분, 시작+30분]`이다. 앱이 더 좁게 잡으면 서버가 열어
/// 둔 문을 앱이 닫는 셈이고(회원은 데스크로 간다), 더 넓게 잡으면 눌러도 400이
/// 돌아온다. 여기 값이 서버 상수와 갈리면 둘 중 하나가 반드시 일어난다.
///
/// **[isOpen]은 `now`를 인자로 받는다 — 시계를 스스로 읽지 않는다.** 이 판정을
/// 로드 시점에 한 번 읽어 bool 필드로 굳혔던 게 P51 결함의 원인이었다: 창이 열리는
/// 시각이 지나도 값이 그대로라 버튼이 회색으로 남았다. 화면은 [opensAt]·[closesAt]을
/// 경계로 삼아 그 순간 다시 그린다(`core/widgets/time_boundary_builder.dart`).
abstract final class CheckinRules {
  /// 서버 `domain.CheckinWindow`와 같은 값.
  static const window = Duration(minutes: 30);

  /// 지금 셀프 체크인이 열려 있는가 — 양끝 포함(서버와 동일).
  ///
  /// **초 단위로 비교한다.** `inMinutes`는 절삭이라 30분 0~59초 구간이 "30분"으로
  /// 읽혀 서버가 이미 거부하는 시각에 버튼이 열려 보인다.
  ///
  /// [startAt]·[now] 모두 센터(KST) 벽시계 표현이어야 한다(`DateFmt` 시간축 규약).
  static bool isOpen({required DateTime startAt, required DateTime now}) =>
      startAt.difference(now).inSeconds.abs() <= window.inSeconds;

  /// 창이 열리는 시각(= 시작 −30분).
  static DateTime opensAt(DateTime startAt) => startAt.subtract(window);

  /// 창이 닫히는 시각(= 시작 +30분).
  static DateTime closesAt(DateTime startAt) => startAt.add(window);
}
