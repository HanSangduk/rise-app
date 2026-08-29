import 'package:rise_member/features/records/domain/inbody_metrics.dart';

/// 회원이 결과지를 보고 옮겨 적은 인바디 1건 — 검증을 통과한 값만 만들어진다.
/// 이 객체가 존재한다는 것 자체가 "6칸이 다 찼고 전부 범위 안"이라는 뜻이다.
class InbodyDraft {
  const InbodyDraft({
    required this.date,
    required this.weight,
    required this.smm,
    required this.bfm,
    required this.pbf,
    required this.vfl,
    required this.bmr,
  });

  /// 측정일(센터 KST 벽시계 표현). 전송은 `DateFmt.isoDate`로 YYYY-MM-DD.
  final DateTime date;
  final double weight;
  final double smm;
  final double bfm;
  final double pbf;
  final double vfl;
  final double bmr;
}

/// 인바디 수기 입력의 **사전 검증** — 순수 도메인(Flutter 의존 0).
///
/// 서버가 거부할 게 확실한 값이면 왕복하지 않고 버튼을 잠근다
/// (`hold_request_sheet.dart`의 사전 판정과 같은 원칙). 다만 **미입력은 거부가
/// 아니라 미완성**이라 빈 칸에 붉은 에러를 띄우지 않고, 제출 시 무엇이 비었는지
/// 말한다.
///
/// 범위는 [InbodyMetric.min]/[InbodyMetric.max] 한 곳에서만 정의한다 — 표시와
/// 입력이 같은 표를 보므로 "화면엔 되는데 저장이 안 되는" 어긋남이 안 생긴다.
abstract final class InbodyInputRules {
  /// 한 칸의 판정. `null` = 지금 막을 이유가 없다(**빈 칸 포함**).
  static String? fieldError(InbodyMetric metric, String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null; // 미완성 — 거부가 아니다.
    final value = double.tryParse(text);
    if (value == null) return '${metric.formLabel} — 숫자만 넣어주세요';
    if (value < metric.min || value > metric.max) {
      return '${metric.formLabel} — '
          '${InbodyMetric.formatValue(metric.min)}~${InbodyMetric.formatValue(metric.max)} '
          '사이로 넣어주세요';
    }
    return null;
  }

  /// 6칸이 전부 채워졌나(범위는 보지 않는다 — 그건 [fieldError]의 몫).
  static bool isComplete(Map<InbodyMetric, String> raw) =>
      InbodyMetric.values.every((m) => (raw[m] ?? '').trim().isNotEmpty);

  /// 개별 범위는 통과하지만 **조합이 물리적으로 불가능한** 입력.
  ///
  /// 서버 `domain.Inbody.Validate()`의 교차 검증 세 줄을 그대로 옮긴 것이다 —
  /// SMM·BFM은 체중의 구성 요소라 체중 이상일 수 없고(같아도 불가능: 뼈·수분·
  /// 장기가 남는다), 둘의 합도 체중을 넘을 수 없다.
  ///
  /// 체/제 오기(BFM 칸에 FFM=제지방량)가 실질적으로 여기서 잡힌다: FFM은 보통
  /// 체중의 70~90%라 [fieldError]의 개별 범위는 태연히 통과하지만, 골격근량과
  /// 더하면 체중을 넘는다.
  ///
  /// 값이 덜 찼으면 판정하지 않는다(`null`) — 입력 중에 결론을 내지 않는다.
  static String? crossFieldError(Map<InbodyMetric, String> raw) {
    double? v(InbodyMetric m) => double.tryParse((raw[m] ?? '').trim());
    final weight = v(InbodyMetric.weight);
    final smm = v(InbodyMetric.smm);
    final bfm = v(InbodyMetric.bfm);
    if (weight == null || weight <= 0) return null;
    String kg(double x) => '${InbodyMetric.formatValue(x)}kg';

    if (smm != null && smm >= weight) {
      return '골격근량(${kg(smm)})이 체중(${kg(weight)})보다 클 수 없어요 — 두 값을 다시 확인해주세요';
    }
    if (bfm != null && bfm >= weight) {
      return '체지방량(${kg(bfm)})이 체중(${kg(weight)})보다 클 수 없어요 — '
          '제지방량(FFM)을 적으신 건 아닌지 확인해주세요';
    }
    if (smm != null && bfm != null && smm + bfm > weight) {
      return '골격근량(${kg(smm)})+체지방량(${kg(bfm)})이 체중(${kg(weight)})을 넘어요 — '
          '체지방량 칸에 제지방량(FFM)을 적으신 건 아닌지 확인해주세요';
    }
    return null;
  }

  /// 지금 입력으로 서버가 거부할 것이 하나라도 있나(개별 범위 + 교차 검증).
  static bool hasBlockingError(Map<InbodyMetric, String> raw) =>
      InbodyMetric.values.any((m) => fieldError(m, raw[m] ?? '') != null) ||
      crossFieldError(raw) != null;

  /// 전부 유효할 때만 [InbodyDraft]를 만든다. 하나라도 비었거나 서버가 거부할
  /// 값이면 `null`.
  static InbodyDraft? draft({
    required DateTime date,
    required Map<InbodyMetric, String> raw,
  }) {
    if (!isComplete(raw) || hasBlockingError(raw)) return null;
    double v(InbodyMetric m) => double.parse((raw[m] ?? '').trim());
    return InbodyDraft(
      date: date,
      weight: v(InbodyMetric.weight),
      smm: v(InbodyMetric.smm),
      bfm: v(InbodyMetric.bfm),
      pbf: v(InbodyMetric.pbf),
      vfl: v(InbodyMetric.vfl),
      bmr: v(InbodyMetric.bmr),
    );
  }

  /// 체지방'량'(BFM) 자리에 제지방'량'(FFM)을 적은 오기 경고 — **저장을 막지 않는다**.
  ///
  /// 글자 하나 차이에 단위가 둘 다 kg라 결과지를 보고 옮겨 적을 때 실제로 섞인다
  /// (`backend/internal/domain/measurement.go`가 사람 입력자에게 같은 경고를 한다).
  /// 다행히 이 셋은 서로 검산이 된다: `PBF ≈ BFM / weight × 100`. FFM을 넣으면
  /// 계산값이 100에서 PBF를 뺀 쪽으로 크게 벌어져 바로 드러난다.
  ///
  /// 막지 않는 이유: **서버가 이 항등식을 검증하지 않는다.** 앱이 막으면 서버가
  /// 받아 줄 값을 앱만 거부하게 된다([crossFieldError]는 반대로 서버가 확실히
  /// 거부하므로 막는다). 이 경고가 담당하는 구간은 교차 검증을 통과해 버리는
  /// 꼬리다 — SMM이 작으면 `SMM+FFM ≤ 체중`이 성립해 서버는 태연히 저장한다.
  ///
  /// 그리고 SMM·VFL·BMR은 검산 근거가 아예 없어서 이 경고로도 안 잡히는 오기가
  /// 남는다 — "경고는 뜨지만 회원 입력값은 코치가 한 번 봐야 한다"가 정확한 표현이다.
  static String? consistencyWarning({
    required String weightRaw,
    required String bfmRaw,
    required String pbfRaw,
  }) {
    final weight = double.tryParse(weightRaw.trim());
    final bfm = double.tryParse(bfmRaw.trim());
    final pbf = double.tryParse(pbfRaw.trim());
    if (weight == null || bfm == null || pbf == null) return null;
    if (weight <= 0) return null;
    final expected = bfm / weight * 100;
    if ((expected - pbf).abs() <= pbfTolerance) return null;
    return '체지방량(BFM)과 체지방률(PBF)이 서로 맞지 않아요 — '
        '이 체중·체지방량이면 체지방률은 ${InbodyMetric.formatValue(expected)}% 근처예요. '
        '제지방량(FFM)을 넣진 않았는지 확인해주세요';
  }

  /// 반올림·표기 차이는 흡수하고 자리 바꿔치기만 잡는 폭(%p).
  /// 결과지 반올림 오차는 0.1%p대라 여유가 크고, FFM 오기는 수십 %p 벌어진다.
  static const pbfTolerance = 5.0;
}
