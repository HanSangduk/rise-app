import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/records/domain/inbody_metrics.dart';
import 'package:rise_member/features/records/domain/inbody_sheet_parser.dart';

// 인바디 결과지 파서 — design/inbody-ocr/parse.py(R1~R11)의 Dart 이식 회귀 방어.
//
// fixtures/inbody/*.tsv 는 README.md의 **함정 표 각 행**을 합성한 토큰 장이고,
// 기대값은 참조 구현(parse.py)을 같은 TSV에 돌려 얻은 출력 그대로다
// ("같은 입력 → 같은 출력" — 생성·대조 하네스는 P20 work_log 참조).
// 여기 숫자를 고치고 싶다면 참조 구현과 실물 실측이 먼저다.
//
// 핵심 속성: **확신 없으면 빈칸.** 함정 픽스처의 기대값이 줄줄이 null인 이유다 —
// 틀린 프리필은 회원이 그대로 저장하지만, 빈칸은 결과지를 보고 채운다.
void main() {
  List<InbodyOcrToken> fixture(String name) {
    final file =
        File('test/features/records/domain/fixtures/inbody/$name.tsv');
    return [
      for (final line in file.readAsLinesSync())
        if (line.split('\t') case final p when p.length >= 6)
          InbodyOcrToken(
            text: p[5],
            x: double.parse(p[1]),
            y: double.parse(p[2]),
            w: double.parse(p[3]),
            h: double.parse(p[4]),
          ),
    ];
  }

  void expectParse(
    String name, {
    double? weight,
    double? smm,
    double? bfm,
    double? pbf,
    double? vfl,
    double? bmr,
    DateTime? date,
  }) {
    final result = InbodySheetParser.parse(fixture(name));
    final expected = {
      if (weight != null) InbodyMetric.weight: weight,
      if (smm != null) InbodyMetric.smm: smm,
      if (bfm != null) InbodyMetric.bfm: bfm,
      if (pbf != null) InbodyMetric.pbf: pbf,
      if (vfl != null) InbodyMetric.vfl: vfl,
      if (bmr != null) InbodyMetric.bmr: bmr,
    };
    expect(result.values, expected, reason: name);
    expect(result.measuredDate, date, reason: '$name 측정일');
  }

  group('정상 장 — 참조 구현과 같은 출력', () {
    test('요약행(A형) 장: 6지표 + 측정일 전부', () {
      // 함정 동거 확인까지 겸한다: 적정체중 67.6(R1)·신체변화 히스토리(R2)·
      // 비만도 117(R4)·제지방량 62.5(R1/R4)·권장섭취열량 2166이 한 장에 있어도
      // 전부 피해 간다.
      expectParse(
        'standard',
        weight: 72.5,
        smm: 35.6,
        bfm: 10.0,
        pbf: 13.7,
        vfl: 3,
        bmr: 1721,
        date: DateTime(2026, 5, 26),
      );
    });

    test('게이지 바(B형) 장: 라벨 아래 값 + 눈금 오픽업 방어', () {
      // 라벨 옆 눈금(55,70,85,100)은 정수라 kg 후보가 못 되고(R4), 같은 줄
      // 범위 없는 숫자는 절대 채택되지 않는다(R6). B밴드에 미끄러진 눈금 '55'는
      // R4가 소수를 강제해 배제한다 — 이게 무너지면 R10(모호)이 빈칸을 만든다.
      // VFL 눈금 '10'은 x오프셋 캡이 자른다.
      expectParse(
        'gauge',
        weight: 73.3,
        smm: 32.7,
        bfm: 15.7,
        pbf: 21.5,
        vfl: 6,
        bmr: 1614,
      );
    });
  });

  group('함정 표 — design/inbody-ocr/README.md의 각 행', () {
    test('비스듬한 사진(R3): 기울기 보정 없이는 옆 행 값이 혼입되는 기하', () {
      // 보정을 끄면 참조 구현 실측처럼 smm←72.5(윗행 체중)로 미끄러진다 —
      // 이 픽스처의 정답이 곧 R3의 회귀 방어다.
      expectParse('slant', weight: 72.5, smm: 35.2, bfm: 15.3, pbf: 21.0);
    });

    test('게이지 바 글리프(R9·R11): 135.2→35.2, 172.5→72.5 복원', () {
      // smm '135.2'는 필드 범위 초과라 토큰 단계에서 선행 1 제거(R9),
      // 체중 '172.5'는 범위 안이라 항등 검증(R11)이 복원한다.
      expectParse('bar_glyph', weight: 72.5, smm: 35.2, bfm: 9.8, pbf: 13.7);
    });

    test('쪼개진 소수(R9): "35."+"2" 병합, 공백 낀 범위, N레벨 토큰', () {
      expectParse(
        'split_decimal',
        smm: 35.2,
        vfl: 4,
        date: DateTime(2026, 5, 18),
      );
    });

    test('적정체중 배제(R1): "적정체중 67.6"은 체중 앵커가 못 된다 — 완전일치', () {
      // 체중 앵커는 범위 부정합으로 죽고(R8), 남는 건 적정체중 행(값이 라벨
      // 아래인 배치)뿐이다. 앵커 매칭이 포함매칭으로 무너지면 '적정체중'이
      // 체중 앵커가 되어 67.6이 체중으로 채워진다(실측 함정) — 빈칸이 정답.
      expectParse('ideal_weight');
    });

    test('눈금 줄 불채택(R6): 범위 없는 같은 줄 숫자는 절대 채택하지 않는다', () {
      // 모니터 촬영류 — 같은 줄에 값만 있고 표준범위가 없다. 이 완고함이
      // 눈금 줄(55,70,85…) 오픽업의 마지막 방어선이라 예외를 두지 않는다.
      expectParse('monitor');
    });

    test('범위형 줄의 B 금지(R8): 라벨 없는 아랫행 값도 줍지 않는다', () {
      // 67.6의 행 라벨이 OCR에서 누락돼 소유권(R7b)이 못 막는 경우 —
      // R8 홀로 방어한다. 무너지면 67.6이 체중으로 채워진다.
      expectParse('no_label_b_leak');
    });

    test('모호하면 빈칸(R10): 비등한 B 후보 2개', () {
      expectParse('ambiguous_b');
    });

    test('모호하면 빈칸(R6): 겹침 비등한 A 후보 2개', () {
      expectParse('ambiguous_a');
    });

    test('행 소유권(R7b): 제지방량 62.5·권장섭취열량 2166·비만도 117 배제', () {
      // 값이 없는 앵커의 B밴드로 이웃 행 값이 미끄러지는 사고 — 전부 빈칸.
      expectParse('ffm');
    });

    test('신체변화 히스토리 열 배제(R2): 헤더 아래 과거값은 앵커가 아니다', () {
      expectParse('history_only');
    });

    test('페이지 하단 15% 배제(R2b): 히스토리 헤더가 누락돼도 걸린다', () {
      expectParse('r2b_bottom');
    });

    test('교차 검증(R11): smm+bfm>체중이면 양쪽 모두 보류', () {
      expectParse('cross', weight: 70.2, pbf: 26.8);
    });

    test('항등 검증(R11): BFM≉체중×PBF면 셋 다 보류 — 나머지는 살린다', () {
      expectParse('identity', vfl: 8, bmr: 1421);
    });
  });

  group('이식 차이(Dart 전용 방어 — 참조 구현엔 없는 관문)', () {
    test('실존하지 않는 달력 날짜는 버린다 — DateTime 롤오버 금지', () {
      // 참조 구현은 문자열이라 "2026-13-45"도 내보내지만, 여기선 DateTime을
      // 만들어야 하므로 오독한 날짜가 6/31→7/1로 굴러 폼에 들어가면 안 된다.
      final result = InbodySheetParser.parse([
        const InbodyOcrToken(text: '2026.06.31', x: 0.6, y: 0.9, w: 0.1, h: 0.02),
      ]);
      expect(result.measuredDate, isNull);
    });

    test('빈 토큰 목록 — 예외 없이 빈 결과(수기 입력이 실패 경로)', () {
      final result = InbodySheetParser.parse(const []);
      expect(result.values, isEmpty);
      expect(result.measuredDate, isNull);
    });
  });
}
