/// 순수 도메인 — 센터 운영 정책 중 회원 앱이 소비하는 값(GET /v1/center policy).
/// Flutter/외부 의존 0, codegen 0. 조회 실패 시 [fallback](24h/2회/30일)으로 동작한다.
///
/// 문구 표시·사전 차단(버튼 비활성)용 — 최종 검증은 항상 서버가 한다.
class CenterPolicy {
  const CenterPolicy({
    required this.slotCapacity,
    required this.cancelCutoffHours,
    required this.graceOnce,
    required this.penaltyRate,
    required this.expiringDays,
    required this.maxHoldsPerPass,
    required this.maxHoldTotalDays,
    this.openHour = defaultOpenHour,
    this.closeHour = defaultCloseHour,
    this.isFallback = false,
  });

  /// 이 값들이 **서버에서 온 것이 아니라 폴백**인가.
  ///
  /// 폴백 자체는 옳다 — 정책을 못 받았다고 화면을 못 그리게 하면 더 나쁘다.
  /// 문제는 받는 쪽이 **출처를 구별할 수 없었다**는 것이다. 그래서
  /// `next_booking_card`가 폴백 24시간을 `"24시간 전까지 취소 가능"`이라고
  /// **사실처럼** 찍었다. 센터 실제 기준이 48시간이면, 그 문구를 믿고 30시간 전에
  /// 취소한 회원이 차감된다.
  ///
  /// 이 플래그가 참이면 화면은 **숫자를 말하지 않는다**(모르는 걸 아는 척하지 않는다).
  final bool isFallback;

  /// 시간당 최대 팀 수(예약 안내 문구 · 빈 시간대 합성 슬롯의 capacity).
  final int slotCapacity;

  /// 무료 취소 마감(시간 단위, 예: 24 = "24시간 전까지 무료").
  ///
  /// **"취소 마감"이 아니다** — 서버는 컷오프가 지나도 취소를 실행하고 원장 차감만
  /// 붙인다([BookingRules.isFreeCancel] 주석).
  final int cancelCutoffHours;

  /// 노쇼(및 컷오프 경과 취소) 최초 1회 유예(P7). 확인 문구가 없는 유예를 약속하지
  /// 않도록 실값을 쓴다 — 유예 **잔여**(이미 썼는지)는 원장 이력에 있어 앱이 모른다.
  final bool graceOnce;

  /// 위약금율(환불 예상액 클라 추정) — v1.5: 10% 하드코딩 대신 센터 실정책 값.
  /// 백엔드 MaxPenaltyRate(10%) 상한은 서버가 최종 캡핑한다(클라도 동일 캡 미러링).
  final double penaltyRate;

  /// 만료임박 기준일 — 유효기간이 이 일수 이하로 남으면 회원에게 알린다.
  ///
  /// **센터가 정하는 값이다.** 앱이 임의 상수를 쓰면 대표가 설정 화면에서 바꾼 기준과
  /// 회원이 보는 경고가 갈린다(어드민 대시보드의 "만료임박" 목록은 이 값을 쓴다).
  final int expiringDays;

  /// 패스당 홀딩 최대 횟수. -1 = 무제한(계약 v1.3: 무제한은 -1로만 표현).
  final int maxHoldsPerPass;

  /// 패스당 홀딩 총 일수 상한. -1 = 무제한.
  final int maxHoldTotalDays;

  /// 센터 운영시간 — **슬롯 시작 시각, 양끝 포함**([openHour]..[closeHour]).
  ///
  /// 9·21이면 09시 시작부터 21시 시작까지 13칸이고 **마지막 수업은 21:00 시작**이다
  /// (21시에 문을 닫는다는 뜻이 아니다). 백엔드 `policy.open_hour`/`close_hour`와
  /// 같은 의미이고, 어드민 Schedule의 시간축도 같은 규약을 쓴다.
  ///
  /// 예전엔 이 두 값이 `BookingRules`의 상수(9·21)로 박혀 있었다 — 06시에 열거나
  /// 23시에 닫는 센터는 그 시간대를 앱에서 표현할 방법이 없어, 실제로 영업 중인
  /// 시간대를 회원이 예약할 수 없었다.
  final int openHour;
  final int closeHour;

  /// 운영시간 기본값 — 서버가 두 필드를 주지 않는 구버전이면 이 값으로 동작한다.
  /// **이 숫자가 곧 "필드가 생기기 전 앱"의 동작이다**(09~21시 13칸) — 바꾸면
  /// 구버전 서버에 붙은 모든 회원의 예약 화면이 조용히 달라진다.
  static const defaultOpenHour = 9;
  static const defaultCloseHour = 21;

  /// 와이어 값(널 가능) → 실제로 쓸 운영시간. **정책을 읽는 경계에서만 부른다**
  /// (`center_policy_provider`) — 규칙·화면은 이미 정해진 [openHour]/[closeHour]를 받는다.
  ///
  /// 두 값을 **함께** 판정하는 이유: 하나만 유효한 조합은 뜻이 없다. `open=22,
  /// close=6`을 그대로 통과시키면 합성 루프가 한 칸도 돌지 않아 그날 예약 화면이
  /// 통째로 "열린 슬롯이 없어요"가 되고, `close=99`는 없는 영업시간 78칸을 만들어낸다.
  /// 말이 안 되는 값은 [CenterPolicy.fallback]과 같은 태도로 처리한다 — 모르면
  /// 기본값(오늘 동작)으로 돌아가되, 서버가 실제로 준 슬롯은 운영시간 밖이어도
  /// 병합에서 그대로 살아남으므로(`BookingRules.mergeWithOpenHours`) 진짜 예약이
  /// 사라지는 경우는 없다.
  ///
  /// 한쪽만 오는 경우(예: open만 6)는 섞어 쓴다 — 계약상 둘은 함께 추가되지만,
  /// 한쪽이 빠졌다고 다른 쪽의 명시적 값까지 버리면 서버가 말한 사실을 무시하는 셈이다.
  static (int, int) resolveHours(int? open, int? close) {
    final o = open ?? defaultOpenHour;
    final c = close ?? defaultCloseHour;
    if (o < 0 || c > 23 || o > c) return (defaultOpenHour, defaultCloseHour);
    return (o, c);
  }

  /// 정책 미로드/조회 실패 시 기본값 — 백엔드 DefaultPolicy와 동일(24h/유예/10%/2회/30일).
  static const fallback = CenterPolicy(
    isFallback: true,
    slotCapacity: 3,
    cancelCutoffHours: 24,
    graceOnce: true,
    penaltyRate: 0.10,
    expiringDays: 7,
    maxHoldsPerPass: 2,
    maxHoldTotalDays: 30,
    openHour: defaultOpenHour,
    closeHour: defaultCloseHour,
  );

  /// 홀딩 상한 표시 라벨 — "최대 2회/30일" 형태, 무제한은 "제한 없음"으로.
  ///
  /// 무제한 판정을 `== -1`이 아니라 `<= 0`으로 한다. 계약은 무제한을 -1로만 표현하지만
  /// **서버 실제 판정은 `maxCount > 0`일 때만 상한을 건다**(`domain/pass.go` ValidateNewHold).
  /// `== -1`로 좁히면 0이 들어왔을 때 앱은 "최대 0회"라 쓰고 서버는 통과시키는 반대 방향
  /// 불일치가 난다 — 앱만 막고 서버는 여는 쪽이 더 나쁘다(회원에게 없는 제한을 말하게 된다).
  /// 0은 서버 Validate·NormalizeHoldLimits가 양쪽에서 걸러 현재는 도달 불가지만,
  /// 술어를 서버와 같게 두면 그 방어선이 하나 걷혔을 때도 갈리지 않는다.
  String get holdLimitLabel {
    final noCountCap = maxHoldsPerPass <= 0;
    final noDaysCap = maxHoldTotalDays <= 0;
    if (noCountCap && noDaysCap) return '제한 없음';
    if (noCountCap) return '총 $maxHoldTotalDays일 이내 · 횟수 제한 없음';
    if (noDaysCap) return '최대 $maxHoldsPerPass회 · 일수 제한 없음';
    return '최대 $maxHoldsPerPass회/$maxHoldTotalDays일';
  }
}
