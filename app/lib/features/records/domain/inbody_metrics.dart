import 'package:rise_member/features/records/domain/records_models.dart';

/// 순수 도메인 — 인바디 6지표의 **표시 규칙**(라벨·단위·입력 범위)과 **방향 인식 델타**.
/// Flutter 의존 0: 색은 [InbodyTrend]로만 말하고 실제 Color는 위젯이 고른다
/// (`homework_week_rules.dart`와 같은 규약 — 규칙은 도메인, 픽셀은 presentation).
///
/// ## 왜 6개를 다 그리나
/// weight/bfm/vfl/bmr은 지금도 서버 → DTO → 도메인까지 **다 와서 화면 직전에
/// 버려지고 있었다**(records_screen의 하드코딩 2행). 목업
/// (목업_회원앱_라이즈_2026-08-14.html:226-232)도 델타(`▲0.4`/`▼0.9`)를 이미
/// 그려 놨다 — 새 발명이 아니라 미구현분 이행이다.
///
/// ## 왜 방향을 도메인에 두나
/// 색이 곧 해석이다. 회원은 숫자보다 색을 먼저 읽어서, 방향을 한 군데서 틀리면
/// 나쁜 변화가 초록으로 칠해진다. 어드민(`admin/src/features/BodyPhotos.tsx`의
/// `Delta`)이 이미 SMM↑=ok / PBF↑=danger를 갖고 있으므로 그 규칙을 **그대로**
/// 이식하고, 어드민이 안 그리는 4개만 여기서 확장한다.
enum InbodyMetric {
  /// 중립: 증량이 목표인 회원과 감량이 목표인 회원에게 같은 화살표가 반대 뜻이다.
  weight(
    label: '체중',
    formLabel: '체중(kg)',
    unit: 'kg',
    goodWhenUp: null,
    min: 20,
    max: 300,
  ),
  smm(
    label: '골격근량(SMM)',
    formLabel: 'SMM(kg)',
    unit: 'kg',
    goodWhenUp: true,
    min: 5,
    max: 120,
  ),
  bfm(
    label: '체지방량(BFM)',
    formLabel: 'BFM(kg)',
    unit: 'kg',
    goodWhenUp: false,
    min: 1,
    max: 200,
  ),
  pbf(
    label: '체지방률(PBF)',
    formLabel: 'PBF(%)',
    unit: '%',
    goodWhenUp: false,
    min: 1,
    max: 70,
  ),

  /// 단위 없는 **레벨**(1~20대). 기종에 따라 같은 칸에 내장지방'단면적'(cm²,
  /// 100 근처)을 인쇄하는 결과지가 있어 상한을 레벨 기준으로 잡아 둔다 —
  /// 770/970 결과지의 cm² 값을 그대로 옮겨 적으면 여기서 걸린다.
  vfl(
    label: '내장지방(VFL)',
    formLabel: '내장지방(VFL)',
    unit: '',
    goodWhenUp: false,
    min: 1,
    max: 30,
  ),

  /// 중립: 체중에 딸려 움직여서 단독 해석이 위험하다.
  bmr(
    label: '기초대사량(BMR)',
    formLabel: 'BMR(kcal)',
    unit: 'kcal',
    goodWhenUp: null,
    min: 500,
    max: 5000,
  );

  const InbodyMetric({
    required this.label,
    required this.formLabel,
    required this.unit,
    required this.goodWhenUp,
    required this.min,
    required this.max,
  });

  /// 기록 카드의 행 라벨 — 목업의 `한글명(약어)` 형태. 약어를 괄호에 품고 있어
  /// 어드민(`SMM`/`PBF`/`VFL`)과 같은 지표를 가리키는지 바로 대조된다.
  final String label;

  /// 입력 폼의 필드 라벨 — 어드민 `BodyPhotos.tsx`의 `NumField` 라벨과 **문자
  /// 그대로 동일**. 회원이 옮겨 적은 칸과 코치가 보는 칸이 같은 이름이어야 한다.
  final String formLabel;

  /// 값 뒤에 붙는 단위. VFL은 레벨이라 빈 문자열이다(kg·%가 붙으면 안 된다).
  final String unit;

  /// 올라가면 좋은 지표인가. `null` = 중립(방향으로 해석하지 않는다).
  final bool? goodWhenUp;

  /// 사전 검증 범위(하한 포함 ~ 상한 포함). 하한이 전부 0보다 크다 —
  /// 그래서 "선택 입력"이 성립하지 않고 6칸이 전부 필수다(JSON에서 미입력 숫자는
  /// 0.0으로 직렬화되므로 "선택 입력"은 곧 "0kg 체중"이 된다).
  ///
  /// 값은 서버 `domain.inbodyRanges`(v2.9)와 **한 자리도 다르지 않아야 한다**.
  /// 앱이 좁으면 서버가 받아 줄 값을 앱만 막아 회원에게 막다른 길이 되고,
  /// 넓으면 6칸을 다 채운 뒤 400을 받는다. 어긋남을 도메인 테스트가 못 박는다.
  final double min;
  final double max;

  double valueOf(InbodyRecord r) => switch (this) {
        InbodyMetric.weight => r.weight,
        InbodyMetric.smm => r.smm,
        InbodyMetric.bfm => r.bfm,
        InbodyMetric.pbf => r.pbf,
        InbodyMetric.vfl => r.vfl,
        InbodyMetric.bmr => r.bmr,
      };

  /// "24.1kg" / "26.8%" / "8" — 소수 첫째 자리까지, 정수면 소수점을 붙이지 않는다.
  String display(InbodyRecord r) => '${formatValue(valueOf(r))}$unit';

  /// 단위 없는 숫자 표기(요약 행·경고 문구에서 재사용).
  static String formatValue(double v) {
    final rounded = double.parse(v.toStringAsFixed(1));
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }

  /// 직전 측정 대비 증감. [previous]가 없거나 변화가 [deltaEpsilon] 미만이면
  /// `null` — **표시하지 않는다**.
  ///
  /// 어드민 `Delta`의 `Math.abs(value) < 0.05` 생략과 같은 경계다. 인바디는
  /// 수분·식사·시간대에 따라 흔들려서, 그 폭의 흔들림을 "변화"라고 말하면
  /// 회원이 없는 추세를 읽는다.
  InbodyDelta? deltaOf(InbodyRecord latest, InbodyRecord? previous) {
    if (previous == null) return null;
    final diff = valueOf(latest) - valueOf(previous);
    if (diff.abs() < deltaEpsilon) return null;
    final up = diff > 0;
    return InbodyDelta(
      value: diff,
      trend: switch (goodWhenUp) {
        null => InbodyTrend.neutral,
        final good => up == good ? InbodyTrend.good : InbodyTrend.bad,
      },
    );
  }

  /// 어드민과 같은 값 — 두 화면이 서로 다른 문턱을 쓰면 같은 기록이 한쪽에선
  /// "변화 없음", 다른 쪽에선 "▲0.0"이 된다.
  static const deltaEpsilon = 0.05;
}

/// 델타를 어떤 색으로 읽어야 하는가. 색 값 자체는 presentation이 고른다.
enum InbodyTrend {
  /// 회원에게 좋은 방향(ok).
  good,

  /// 회원에게 나쁜 방향(danger).
  bad,

  /// 방향으로 해석하지 않는다(muted) — 체중·BMR.
  neutral,
}

class InbodyDelta {
  const InbodyDelta({required this.value, required this.trend});

  /// 부호 있는 차이(latest − previous).
  final double value;
  final InbodyTrend trend;

  bool get isUp => value > 0;

  /// "▲0.4" / "▼0.9" — 목업 표기 그대로(어드민 `Delta`와 같은 소수 1자리).
  String get label => '${isUp ? '▲' : '▼'}${value.abs().toStringAsFixed(1)}';
}
