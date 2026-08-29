import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/records/domain/inbody_metrics.dart';
import 'package:rise_member/features/records/domain/inbody_input_rules.dart';

// 회원 수기 입력의 **사전 검증**. 서버가 거부할 게 확실한 값이면 왕복하지 않고
// 버튼을 잠근다(hold_request_sheet의 사전 판정 규약과 같은 원칙).
//
// 미입력은 "거부"가 아니라 "미완성"이다 — 빈 칸에 붉은 에러를 띄우지 않고,
// 제출을 눌렀을 때 무엇이 비었는지 말한다.
//
// 경계 주의: 서버는 0을 거부한다(범위 하한이 0보다 크다). 그래서 "선택 입력"이
// 성립하지 않고 6칸이 전부 필수다 — 미입력을 0.0으로 채워 보내면 확실히 400이다.
void main() {
  Map<InbodyMetric, String> raw({
    String weight = '70.2',
    String smm = '30.1',
    String bfm = '18.8',
    String pbf = '26.8',
    String vfl = '8',
    String bmr = '1420',
  }) =>
      {
        InbodyMetric.weight: weight,
        InbodyMetric.smm: smm,
        InbodyMetric.bfm: bfm,
        InbodyMetric.pbf: pbf,
        InbodyMetric.vfl: vfl,
        InbodyMetric.bmr: bmr,
      };

  group('fieldError — 한 칸의 사전 판정', () {
    test('빈 칸은 에러가 아니다(미완성이지 거부가 아니다)', () {
      expect(InbodyInputRules.fieldError(InbodyMetric.weight, ''), isNull);
      expect(InbodyInputRules.fieldError(InbodyMetric.weight, '   '), isNull);
    });

    test('숫자가 아니면 거부', () {
      expect(InbodyInputRules.fieldError(InbodyMetric.weight, '칠십'), isNotNull);
      expect(InbodyInputRules.fieldError(InbodyMetric.weight, '70.2.3'), isNotNull);
    });

    test('0과 음수는 거부 — 미입력을 0으로 채워 보내면 서버가 400이다', () {
      expect(InbodyInputRules.fieldError(InbodyMetric.weight, '0'), isNotNull);
      expect(InbodyInputRules.fieldError(InbodyMetric.smm, '0'), isNotNull);
      expect(InbodyInputRules.fieldError(InbodyMetric.pbf, '-3'), isNotNull);
    });

    test('소수점이 밀린 전형적 오타(체중 702kg, PBF 268%)를 잡는다', () {
      expect(InbodyInputRules.fieldError(InbodyMetric.weight, '702'), isNotNull);
      expect(InbodyInputRules.fieldError(InbodyMetric.pbf, '268'), isNotNull);
    });

    test('정상 범위는 통과', () {
      for (final e in raw().entries) {
        expect(InbodyInputRules.fieldError(e.key, e.value), isNull, reason: '${e.key.name}=${e.value}');
      }
    });

    test('에러 문구는 원인과 다음 행동을 함께 말한다', () {
      final msg = InbodyInputRules.fieldError(InbodyMetric.weight, '702')!;
      expect(msg, contains('체중'));
      expect(msg, contains('넣어주세요'));
    });
  });

  group('isComplete / draft — 6칸 전부 필수', () {
    test('한 칸이라도 비면 미완성이고 draft가 나오지 않는다', () {
      expect(InbodyInputRules.isComplete(raw(bmr: '')), isFalse);
      expect(InbodyInputRules.draft(date: DateTime(2026, 8, 17), raw: raw(bmr: '')), isNull);
    });

    test('범위 밖이 하나라도 있으면 draft가 나오지 않는다', () {
      expect(InbodyInputRules.draft(date: DateTime(2026, 8, 17), raw: raw(pbf: '268')), isNull);
    });

    test('전부 유효하면 draft를 만든다 — 값과 날짜가 그대로 실린다', () {
      final d = InbodyInputRules.draft(date: DateTime(2026, 8, 17), raw: raw())!;
      expect(d.date, DateTime(2026, 8, 17));
      expect(d.weight, 70.2);
      expect(d.smm, 30.1);
      expect(d.bfm, 18.8);
      expect(d.pbf, 26.8);
      expect(d.vfl, 8);
      expect(d.bmr, 1420);
    });

    test('앞뒤 공백은 흡수한다 — 붙여넣기로 들어온 값이 거부되지 않게', () {
      final d = InbodyInputRules.draft(date: DateTime(2026, 8, 17), raw: raw(weight: ' 70.2 '))!;
      expect(d.weight, 70.2);
    });
  });

  // 서버 `domain.Inbody.Validate()`의 교차 검증 세 줄과 같은 판정. 개별 범위는
  // 통과하는데 조합이 불가능한 값이라 서버가 **확실히** 400을 준다 — 왕복하지 않고
  // 여기서 막는다. 체/제 오기가 실질적으로 여기서 잡힌다.
  group('crossFieldError — 조합이 물리적으로 불가능한 입력', () {
    test('골격근량이 체중 이상이면 거부', () {
      expect(InbodyInputRules.crossFieldError(raw(weight: '70', smm: '70')), isNotNull);
      expect(InbodyInputRules.crossFieldError(raw(weight: '70', smm: '80')), isNotNull);
    });

    test('체지방량이 체중 이상이면 거부 — 제지방량 확인을 안내한다', () {
      final msg = InbodyInputRules.crossFieldError(raw(weight: '70', smm: '10', bfm: '75'))!;
      expect(msg, contains('제지방량(FFM)'));
    });

    test('SMM+BFM이 체중을 넘으면 거부 — FFM 오기가 여기서 잡힌다', () {
      // 체중 70 · 골격근량 30 · 체지방량 칸에 제지방량 51.2 → 81.2 > 70.
      final msg = InbodyInputRules.crossFieldError(
        raw(weight: '70', smm: '30', bfm: '51.2'),
      )!;
      expect(msg, contains('넘어요'));
      expect(msg, contains('제지방량(FFM)'));
    });

    test('정상 조합은 통과', () {
      expect(InbodyInputRules.crossFieldError(raw()), isNull);
    });

    test('값이 덜 찼으면 판정하지 않는다 — 입력 중에 결론을 내지 않는다', () {
      expect(InbodyInputRules.crossFieldError(raw(weight: '')), isNull);
      expect(InbodyInputRules.crossFieldError(raw(smm: '', bfm: '')), isNull);
    });

    test('조합 오류가 있으면 draft가 나오지 않고 버튼도 잠긴다', () {
      final bad = raw(weight: '70', smm: '30', bfm: '51.2');
      expect(InbodyInputRules.hasBlockingError(bad), isTrue);
      expect(InbodyInputRules.draft(date: DateTime(2026, 8, 17), raw: bad), isNull);
    });
  });

  group('consistencyWarning — 체지방량(BFM)에 제지방량(FFM)을 넣은 오기', () {
    test('BFM/체중 = PBF가 맞으면 경고 없음(반올림 오차는 흡수)', () {
      expect(
        InbodyInputRules.consistencyWarning(weightRaw: '70.2', bfmRaw: '18.8', pbfRaw: '26.8'),
        isNull,
      );
    });

    test('체지방량 자리에 제지방량(51.2kg)을 넣으면 경고한다', () {
      final w = InbodyInputRules.consistencyWarning(weightRaw: '70.0', bfmRaw: '51.2', pbfRaw: '26.8');
      expect(w, isNotNull);
      expect(w, contains('제지방량'));
    });

    test('아직 다 안 채웠으면 경고하지 않는다 — 입력 중에 붉은 글씨가 깜빡이지 않게', () {
      expect(InbodyInputRules.consistencyWarning(weightRaw: '70', bfmRaw: '', pbfRaw: '26.8'), isNull);
      expect(InbodyInputRules.consistencyWarning(weightRaw: '', bfmRaw: '18', pbfRaw: '26'), isNull);
    });

    test('경고는 저장을 막지 않는다 — 교차 검증을 통과하는 꼬리에서 draft가 그대로 나온다', () {
      // 서버는 이 조합을 받아 준다(6+51.2 = 57.2 ≤ 70). 서버가 받아 줄 값을 앱만
      // 막으면 회원에게 막다른 길이 되므로, 이 구간에서는 경고만 하고 통과시킨다.
      final r = raw(weight: '70.0', smm: '6', bfm: '51.2', pbf: '26.8');
      expect(InbodyInputRules.crossFieldError(r), isNull);
      expect(
        InbodyInputRules.consistencyWarning(weightRaw: '70.0', bfmRaw: '51.2', pbfRaw: '26.8'),
        isNotNull,
      );
      expect(InbodyInputRules.draft(date: DateTime(2026, 8, 17), raw: r), isNotNull);
    });
  });
}
