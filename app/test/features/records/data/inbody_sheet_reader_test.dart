import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/records/data/inbody_sheet_reader.dart';

// ML Kit → 파서 토큰 어댑터. 파서(inbody_sheet_parser.dart)는 참조 구현(Vision)의
// 좌표 규약(0~1 정규화, y 위로 증가)을 전제하므로, 픽셀·y-아래 좌표를 주는
// ML Kit과의 경계는 전부 이 순수 함수에 있다 — 여기가 틀리면 파서의 모든 기하
// 규칙이 조용히 어긋난다(부등호가 반대 행을 가리킨다).
void main() {
  OcrBox box(String text, double left, double top, double w, double h) =>
      (text: text, left: left, top: top, width: w, height: h);

  group('좌표 변환 — 픽셀(y 아래로) → 정규화(y 위로)', () {
    test('y축 반전: 토큰 y는 박스의 아래 모서리를 하단 원점 기준으로 잰다', () {
      final tokens = inbodyTokensFromOcr(
        lines: [
          (line: box('72.5', 100, 200, 50, 30), elements: [
            box('72.5', 100, 200, 50, 30),
          ]),
        ],
        imageWidth: 1000,
        imageHeight: 2000,
      );
      // 엘리먼트 + 한글 없는 라인 — 같은 박스가 두 번 들어간다(무해: 파서의
      // 모호성 판정은 "다른 값"만 센다).
      expect(tokens, hasLength(2));
      final t = tokens.first;
      expect(t.x, 0.1);
      expect(t.w, 0.05);
      expect(t.h, 0.015);
      // 픽셀 상단 200+높이 30 = 하단 230 → 정규화 y(아래 모서리) = 1 - 230/2000.
      expect(t.y, closeTo(0.885, 1e-9));
    });

    test('위에 있는 글자가 더 큰 y를 갖는다 — 파서의 "위 우선" 정렬이 기대는 성질', () {
      final tokens = inbodyTokensFromOcr(
        lines: [
          (line: box('1', 0, 100, 10, 10), elements: []),
          (line: box('2', 0, 900, 10, 10), elements: []),
        ],
        imageWidth: 1000,
        imageHeight: 1000,
      );
      final top = tokens.firstWhere((t) => t.text == '1');
      final bottom = tokens.firstWhere((t) => t.text == '2');
      expect(top.y, greaterThan(bottom.y));
    });
  });

  group('토큰 구성 — 라인/엘리먼트 양쪽 사용(README "ML Kit 이식 주의")', () {
    test('한글 라인은 라인 토큰으로 넣지 않는다 — 행 전체 박스가 R7b 라벨이 되어 '
        '자기 행 값을 "남의 행"으로 오판하는 것을 막는다', () {
      final tokens = inbodyTokensFromOcr(
        lines: [
          (
            line: box('골격근량 35.6 (26.5~32.5)', 60, 100, 500, 30),
            elements: [
              box('골격근량', 60, 100, 100, 30),
              box('35.6', 300, 100, 60, 30),
              box('(26.5~32.5)', 380, 100, 120, 30),
            ],
          ),
        ],
        imageWidth: 1000,
        imageHeight: 1000,
      );
      expect([for (final t in tokens) t.text],
          ['골격근량', '35.6', '(26.5~32.5)']);
    });

    test('숫자만의 라인은 라인 토큰도 넣는다 — 값+범위가 한 토큰이어야 잡히는 '
        'R6/R9 조합(엘리먼트 분할 습성 보완)', () {
      final tokens = inbodyTokensFromOcr(
        lines: [
          (
            line: box('72.5 (55.8~75.4)', 300, 100, 220, 30),
            elements: [
              box('72.5', 300, 100, 60, 30),
              box('(55.8~75.4)', 380, 100, 140, 30),
            ],
          ),
        ],
        imageWidth: 1000,
        imageHeight: 1000,
      );
      expect([for (final t in tokens) t.text],
          ['72.5', '(55.8~75.4)', '72.5 (55.8~75.4)']);
    });
  });

  group('EXIF 방어', () {
    test('박스가 이미지 크기를 벗어나면 가로세로가 뒤집힌 것 — 크기를 맞바꾼다', () {
      // 세로 사진: ML Kit은 회전 적용 후(1000×2000) 좌표를 주는데 인코딩 헤더는
      // 회전 전(2000×1000)을 말하는 경우. 세로로 1500까지 내려간 박스가 신호다.
      final tokens = inbodyTokensFromOcr(
        lines: [
          (line: box('72.5', 100, 1400, 50, 100), elements: []),
        ],
        imageWidth: 2000,
        imageHeight: 1000,
      );
      final t = tokens.single;
      expect(t.x, 0.1); // 1000 기준
      expect(t.y, closeTo(1 - 1500 / 2000, 1e-9)); // 2000 기준
    });

    test('이미지 크기가 0이면 빈 목록 — 0으로 나누지 않는다', () {
      expect(
        inbodyTokensFromOcr(
          lines: [
            (line: box('x', 0, 0, 1, 1), elements: []),
          ],
          imageWidth: 0,
          imageHeight: 0,
        ),
        isEmpty,
      );
    });
  });
}
