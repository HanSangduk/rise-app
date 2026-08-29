import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/records/domain/inbody_metrics.dart';
import 'package:rise_member/features/records/domain/records_models.dart';

// 인바디 6지표의 표시 규칙 + **방향 인식 델타**.
//
// 목업(목업_회원앱_라이즈_2026-08-14.html:226-232)에는 이미 `24.1kg ▲0.4` /
// `26.8% ▼0.9`가 있는데 앱은 2지표 값만 그리고 델타를 버렸다. 방향 규칙은
// 어드민 `admin/src/features/BodyPhotos.tsx`의 Delta(|Δ|<0.05 생략, SMM↑=ok,
// PBF↑=danger)가 이미 갖고 있어서, 여기서 새로 발명하지 않고 그대로 이식한다.
//
// 방향을 틀리면 나쁜 변화가 초록으로 칠해진다 — 색이 곧 해석이라 회원이
// 숫자보다 색을 먼저 읽는다. 그래서 6지표 전부의 방향을 못 박는다.
InbodyRecord rec({
  String id = 'i1',
  DateTime? date,
  double weight = 70,
  double smm = 30,
  double bfm = 18,
  double pbf = 26,
  double vfl = 8,
  double bmr = 1400,
  String? source,
}) =>
    InbodyRecord(
      id: id,
      date: date ?? DateTime(2026, 8, 1),
      weight: weight,
      smm: smm,
      bfm: bfm,
      pbf: pbf,
      vfl: vfl,
      bmr: bmr,
      source: source,
    );

void main() {
  group('방향 테이블 — 색이 곧 해석이다', () {
    test('SMM은 오르면 좋음 · PBF는 오르면 나쁨(어드민과 같은 규칙)', () {
      expect(InbodyMetric.smm.goodWhenUp, isTrue);
      expect(InbodyMetric.pbf.goodWhenUp, isFalse);
    });

    test('BFM·VFL도 오르면 나쁨', () {
      expect(InbodyMetric.bfm.goodWhenUp, isFalse);
      expect(InbodyMetric.vfl.goodWhenUp, isFalse);
    });

    test('체중·BMR은 중립 — 증량/감량 목표가 사람마다 반대다', () {
      expect(InbodyMetric.weight.goodWhenUp, isNull);
      expect(InbodyMetric.bmr.goodWhenUp, isNull);
    });

    test('6지표가 모두 있고 순서가 고정이다', () {
      expect(InbodyMetric.values, hasLength(6));
      expect(
        InbodyMetric.values.map((m) => m.name),
        ['weight', 'smm', 'bfm', 'pbf', 'vfl', 'bmr'],
      );
    });
  });

  group('delta — |Δ| < 0.05면 표시하지 않는다', () {
    test('직전 기록이 없으면 null(첫 측정에는 비교 대상이 없다)', () {
      expect(InbodyMetric.smm.deltaOf(rec(), null), isNull);
    });

    test('0.04 차이는 생략 — 측정 노이즈를 변화로 말하지 않는다', () {
      final d = InbodyMetric.smm.deltaOf(rec(smm: 30.04), rec(smm: 30));
      expect(d, isNull);
    });

    test('0.05 차이는 표시한다(어드민 경계와 동일: < 0.05만 생략)', () {
      final d = InbodyMetric.smm.deltaOf(rec(smm: 30.05), rec(smm: 30));
      expect(d, isNotNull);
      expect(d!.label, '▲0.1');
    });

    test('SMM 상승 = good', () {
      final d = InbodyMetric.smm.deltaOf(rec(smm: 30.4), rec(smm: 30))!;
      expect(d.trend, InbodyTrend.good);
      expect(d.label, '▲0.4');
    });

    test('SMM 하락 = bad', () {
      expect(InbodyMetric.smm.deltaOf(rec(smm: 29.6), rec(smm: 30))!.trend, InbodyTrend.bad);
    });

    test('PBF 상승 = bad, 하락 = good', () {
      expect(InbodyMetric.pbf.deltaOf(rec(pbf: 27), rec(pbf: 26))!.trend, InbodyTrend.bad);
      final down = InbodyMetric.pbf.deltaOf(rec(pbf: 25.1), rec(pbf: 26))!;
      expect(down.trend, InbodyTrend.good);
      expect(down.label, '▼0.9');
    });

    test('체중·BMR은 오르든 내리든 중립 — 초록/빨강으로 칠하지 않는다', () {
      expect(InbodyMetric.weight.deltaOf(rec(weight: 72), rec(weight: 70))!.trend, InbodyTrend.neutral);
      expect(InbodyMetric.weight.deltaOf(rec(weight: 68), rec(weight: 70))!.trend, InbodyTrend.neutral);
      expect(InbodyMetric.bmr.deltaOf(rec(bmr: 1450), rec(bmr: 1400))!.trend, InbodyTrend.neutral);
    });
  });

  group('표시 — 값과 단위', () {
    test('소수 첫째 자리까지, 정수면 소수점을 붙이지 않는다', () {
      expect(InbodyMetric.smm.display(rec(smm: 24.1)), '24.1kg');
      expect(InbodyMetric.smm.display(rec(smm: 24)), '24kg');
      expect(InbodyMetric.pbf.display(rec(pbf: 26.8)), '26.8%');
      expect(InbodyMetric.bmr.display(rec(bmr: 1420)), '1420kcal');
    });

    test('VFL은 단위 없는 레벨이다 — kg/%가 붙으면 안 된다', () {
      expect(InbodyMetric.vfl.unit, '');
      expect(InbodyMetric.vfl.display(rec(vfl: 8)), '8');
    });

    test('라벨은 목업(한글명(약어))과 같다 — 어드민 약어를 그대로 품는다', () {
      expect(InbodyMetric.smm.label, '골격근량(SMM)');
      expect(InbodyMetric.pbf.label, '체지방률(PBF)');
      expect(InbodyMetric.weight.label, '체중');
    });

    test('입력 폼 라벨은 어드민(BodyPhotos.tsx)과 문자 그대로 같다', () {
      expect(
        InbodyMetric.values.map((m) => m.formLabel),
        ['체중(kg)', 'SMM(kg)', 'BFM(kg)', 'PBF(%)', '내장지방(VFL)', 'BMR(kcal)'],
      );
    });
  });

  // 앱 범위가 서버(`backend/internal/domain/measurement.go`의 inbodyRanges, v2.9)와
  // 어긋나면 두 방향 다 사고다: 앱이 좁으면 서버가 받아 줄 값을 앱만 막아
  // 회원에게 막다른 길이 되고, 넓으면 6칸을 다 채운 뒤 400을 받는다.
  group('범위는 서버 v2.9와 한 자리도 다르지 않다', () {
    test('6지표 min/max가 서버 표와 일치', () {
      final actual = {
        for (final m in InbodyMetric.values) m.name: (m.min, m.max),
      };
      expect(actual, {
        'weight': (20.0, 300.0),
        'smm': (5.0, 120.0),
        'bfm': (1.0, 200.0),
        'pbf': (1.0, 70.0),
        'vfl': (1.0, 30.0),
        'bmr': (500.0, 5000.0),
      });
    });
  });
}
