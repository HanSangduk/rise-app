/// 코치 이름 표기 유틸 — 순수 Dart(외부 의존 0). home/booking/my/auth 공용.
///
/// 두 가지 문제를 한 곳에서 처리한다:
///
/// 1) **이름 해석 실패** — Member/Pass/Booking에는 trainer_id만 있고 이름이 없어
///    앱은 GET /v1/staff 맵으로 이름을 해석한다(StaffDirectory). 미배정이거나
///    디렉토리에 없으면 이름이 null/""이 되는데, 이걸 그대로 문자열에 끼우면
///    "담당  코치"(빈자리) · "PT 20회 · "(꼬리 구분자)처럼 깨져 보인다.
///    [nameOrNull]은 null과 공백 문자열을 같은 "미해석"(null)으로 묶어 문구·구분자
///    자체를 생략할지 판단하게 해주고, [resolve]는 그 자리를 폴백으로 메운다.
///    조각을 이을 땐 [joinDot]이 빈 조각과 구분자를 함께 버린다.
///
/// 2) **퇴사 표기(계약 v2.0)** — inactive 스태프도 GET /v1/staff에 계속 남는다
///    (이름 해석을 잃으면 담당 코치 표시가 원시 uid로 무너지기 때문). 그래서 앱은
///    이름을 지우지 않고 상태만 덧붙여 현직과 구분한다. 문구가 화면마다 갈리지
///    않도록 접미사는 [retiredSuffix] 한 곳에서만 정의한다.
///
/// 표기를 붙이는 **위치**는 화면 문맥이 정한다("담당 정혜린 코치" 뒤 vs 괄호 안).
/// 그래서 조립은 호출부가 하고, 이 유틸은 조각([tag]·[inline])만 제공한다.
///
/// 다만 **정규화(trim)는 전부 여기서 끝낸다** — 호출부가 판정만 이 유틸에 맡기고
/// 보간은 원본 문자열로 하면 규칙이 반쪽이 된다: 예전엔 [isUnresolved]가 trim해서
/// 통과시킨 `" 정혜린 "`을 호출부가 그대로 끼워 "담당  정혜린  코치"가 됐다.
/// 그래서 호출부는 [nameOrNull]이 돌려준 값(또는 [resolve])만 보간해야 하고,
/// 원본 `trainerName`을 다시 읽어선 안 된다.
///
/// 노이즈 방지 규약 — 퇴사 표기는 **한 화면에 한 번**, 그 화면에서 "내 담당 코치가
/// 누구인가"를 말하는 앵커에만 붙인다. 같은 화면의 부차적 언급(패스 속성 줄, 원장
/// 대상 칩 등)은 이름만 그대로 둔다. 앵커 목록은 각 호출부 주석 참조.
abstract final class CoachLabel {
  /// 퇴사 접미사 — "정혜린 코치 (퇴사)".
  static const retiredSuffix = '(퇴사)';

  /// 정규화된 이름, 해석 실패면 null — "미해석"(null·""·공백)을 null 하나로 좁힌다.
  ///
  /// 이 유틸의 **단일 정규화 지점**: 판정과 값이 한 번에 나와서, 호출부가
  /// `isUnresolved(name) ? … : '…$name…'`처럼 판정은 trim으로 하고 보간은 원본으로
  /// 하는 어긋남이 생길 수 없다.
  static String? nameOrNull(String? name) {
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 이름 자리 표기. null·공백은 [fallback]("담당 코치"의 "담당")으로 메운다.
  /// [fallback]도 같은 규칙으로 정규화한다 — 공백뿐인 폴백(예: 온보딩의
  /// `fallback: trainerName ?? ''`)이 non-null로 살아남아 "담당    코치" +
  /// 빈 이니셜 아바타가 되던 구멍을 막는다. 둘 다 비면 ""(호출부가 생략 판단).
  static String resolve(String? name, {String fallback = '담당'}) =>
      nameOrNull(name) ?? nameOrNull(fallback) ?? '';

  /// 이름을 해석하지 못했는가(null 또는 공백) — 호출부가 " · " 같은 구분자나
  /// "담당 … 코치" 문구 자체를 통째로 생략할지 판단할 때 쓴다.
  /// 값까지 필요하면 [nameOrNull]을 써서 원본 재보간을 피한다.
  static bool isUnresolved(String? name) => nameOrNull(name) == null;

  /// " · "로 잇되 비어 있는 조각은 통째로 버린다 — 조각 하나가 비어도 매달린
  /// 구분자(" · 정혜린" · "정혜린 코치 (퇴사) · ")가 남지 않게.
  ///
  /// 이름 쪽만 막아서는 부족했다: 코치 이름과 나란히 놓이는 조각(상품명 등)이
  /// 비면 같은 모양으로 깨진다("PT 20회 · "는 이 유틸이 처음부터 막으려던 것).
  /// 각 조각은 [nameOrNull]과 같은 규칙으로 정규화된다.
  static String joinDot(Iterable<String?> parts) =>
      [for (final p in parts) ?nameOrNull(p)].join(' · ');

  /// 이미 완성된 문구 뒤에 퇴사 표기를 붙인다 — tag('담당 정혜린 코치', …)
  /// → "담당 정혜린 코치 (퇴사)". 현직이면 원문 그대로.
  static String tag(String label, {required bool inactive}) =>
      inactive ? '$label $retiredSuffix' : label;

  /// 괄호 안처럼 좁은 자리의 짧은 표기 — inline('정혜린', inactive: true)
  /// → "정혜린 · 퇴사"("내 코치 (정혜린 · 퇴사)"). 괄호 중첩("(정혜린 (퇴사))")을 피한다.
  static String inline(String name, {required bool inactive}) =>
      inactive ? '$name · 퇴사' : name;
}
