// 시트 규약 정적 가드(P54).
//
// `rise_sheet_test.dart`는 "래퍼를 쓴 시트가 올바른가"를 지키고, 이 파일은
// **"래퍼를 안 쓴 시트가 새로 생기는 것"**을 막는다. 둘 다 필요하다 — 12곳을
// 고쳐도 13번째가 `showModalBottomSheet`로 다시 생기면 같은 결함이 돌아온다.
// P50이 fetch 한 곳을 감싸 53곳을 해소한 뒤 같은 종류의 가드를 둔 것과 같은 층이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/` 아래 모든 Dart 소스. 주석 줄은 제외하고 본다.
Iterable<({String path, int line, String text})> _sourceLines() sync* {
  final dir = Directory('lib');
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final lines = e.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) continue;
      yield (path: e.path, line: i + 1, text: lines[i]);
    }
  }
}

void main() {
  test('showModalBottomSheet 직접 호출은 rise_sheet.dart 안에만 있다', () {
    final offenders = _sourceLines()
        .where((l) => l.text.contains('showModalBottomSheet'))
        .where((l) => !l.path.endsWith('core/widgets/rise_sheet.dart'))
        .map((l) => '${l.path}:${l.line}')
        .toList();

    expect(
      offenders,
      isEmpty,
      reason:
          '바텀시트는 showRiseSheet로 연다 — 직접 호출하면 하단 시스템 바 인셋을 '
          '놓쳐 CTA가 내비게이션 바 아래로 들어간다(P54). 근거는 rise_sheet.dart 주석.',
    );
  });

  test('시트 본문이 padding.bottom을 따로 더하지 않는다 — 이중 여백 방지', () {
    // 래퍼가 viewInsets에 이미 시스템 바를 합쳐 두었으므로, 시트 안에서 padding을
    // 또 더하면 여백이 두 번 들어간다. SafeArea는 무방하다(padding을 소비할 뿐
    // 더하지 않는다) — 여기서 잡는 건 산술식에 섞여 들어간 경우다.
    final sheetFiles = _sourceLines()
        .map((l) => l.path)
        .toSet()
        .where((p) => p.contains('_sheet.dart'))
        .toSet();

    final offenders = _sourceLines()
        .where((l) => sheetFiles.contains(l.path))
        .where((l) {
          final t = l.text;
          // `padding.bottom`을 덧셈에 쓰는 경우만. 단독 참조(레이아웃 계산)는 허용.
          return RegExp(r'padding\.bottom\s*\+|(\+\s*)[\w.]*padding\.bottom').hasMatch(t) &&
              !t.contains('viewPadding');
        })
        .map((l) => '${l.path}:${l.line} → ${l.text.trim()}')
        .toList();

    expect(
      offenders,
      isEmpty,
      reason: 'showRiseSheet가 viewInsets에 시스템 바를 이미 합친다 — 또 더하면 이중 여백',
    );
  });
}
