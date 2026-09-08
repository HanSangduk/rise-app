// 세션 소멸 문구·이유 없는 종료의 **정적 가드**(P64).
//
// 4탭 뷰모델은 세션이 비면 `AuthFailure('로그인이 필요해요')`를 던졌다. 뷰모델은 세션이
// **왜** 비었는지 모르므로 어떤 문장을 넣어도 절반은 거짓이다(연결 해제면 신원은
// 살아 있다). 그래서 문구가 아니라 타입(`SessionGoneFailure`)만 내기로 했는데, 이
// 규약은 컴파일이 지켜 주지 않는다 — 다음 뷰모델이 같은 문장을 다시 쓰면 그만이다.
// `legal_identifier_guard_test`와 같은 방식으로 소스를 훑어 잡는다.
//
// `clear()`의 이유 인자는 `required`라 컴파일이 강제하지만, 누군가 기본값을 붙이는
// 순간 새 호출부가 조용히 전화번호 화면으로 떨어진다 — 인자 없는 호출 0건을 여기서
// 함께 못 박는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/` 아래 모든 .dart 소스 — 주석 줄(`//`·`///`)은 뺀다. 이 가드의 대상은
/// **코드**지 "종전엔 이랬다"는 설명이 아니다.
Map<String, List<String>> _codeLinesByFile() {
  final out = <String, List<String>>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart') || f.path.endsWith('.freezed.dart')) {
      continue;
    }
    out[f.path] = f
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .toList(growable: false);
  }
  expect(out, isNotEmpty, reason: 'lib/를 못 읽었다 — 작업 디렉토리가 app/인지 확인할 것');
  return out;
}

void main() {
  test("'로그인이 필요해요' 리터럴이 lib/ 코드에 없다 — 원인을 모르는 뷰모델이 문장을 말하지 않는다", () {
    // 정확한 리터럴만 잡는다. 진짜 401을 말하는 다른 문장(예: api_result_guard의
    // 만료 안내)은 대상이 아니다 — 그쪽은 원인을 아는 자리다.
    final offenders = <String>[];
    _codeLinesByFile().forEach((path, lines) {
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains("'로그인이 필요해요'") || lines[i].contains('"로그인이 필요해요"')) {
          offenders.add('$path:${i + 1}');
        }
      }
    });
    expect(offenders, isEmpty,
        reason: '세션 소멸을 문구로 말하는 자리가 되살아났다 — SessionGoneFailure를 쓸 것: $offenders');
  });

  test('이유 없는 세션 종료가 없다 — Session.clear() 인자 없는 호출 0건', () {
    // P64 검증 반영 — 줄 단위 정규식은 `ref\n  .read(sessionProvider.notifier)\n  .clear()`처럼
    // 포맷터가 줄을 나누면 놓친다. sessionProvider가 등장하는 파일의 **전체 텍스트**(주석 제외)에
    // 걸고, 두 형태를 다 본다: ① `sessionProvider.notifier).clear(` 직접 호출, ② notifier를
    // 변수에 담은 뒤(`final s = ref.read(sessionProvider.notifier)`) `s.clear(`.
    final reasoned = RegExp(r'\.clear\(\s*reason:', multiLine: true);
    final direct = RegExp(r'sessionProvider\.notifier\)\s*\.clear\(\s*\)', multiLine: true);
    final bound = RegExp(r'(\w+)\s*=\s*ref\.read\(\s*sessionProvider\.notifier\s*\)', multiLine: true);
    final offenders = <String>[];
    var reasonedCount = 0;
    _codeLinesByFile().forEach((path, lines) {
      final text = lines.join('\n');
      if (!text.contains('sessionProvider')) return;
      if (direct.hasMatch(text)) offenders.add('$path (직접 호출)');
      for (final m in bound.allMatches(text)) {
        final name = RegExp.escape(m.group(1)!);
        if (RegExp('\\b$name\\.clear\\(\\s*\\)', multiLine: true).hasMatch(text)) {
          offenders.add('$path (${m.group(1)}.clear())');
        }
      }
      reasonedCount += reasoned.allMatches(text).length;
    });
    expect(offenders, isEmpty, reason: '이유 없는 종료는 착지를 고를 수 없다: $offenders');
    // 가드가 헛돌지 않는지 — 실제 호출부 4곳(401·로그아웃·탈퇴·재검증)이 잡혀야 한다.
    expect(reasonedCount, greaterThanOrEqualTo(4),
        reason: '이유 있는 호출이 $reasonedCount곳뿐이다 — 호출부가 사라졌거나 정규식이 틀렸다');
  });

  test('clear의 reason은 required다 — 기본값이 붙는 순간 새 호출부가 조용히 전화번호 화면으로 떨어진다', () {
    final src = File('lib/core/session/session_provider.dart').readAsStringSync();
    expect(
      RegExp(r'void clear\(\{\s*required SessionEndReason reason\s*\}\)').hasMatch(src),
      isTrue,
      reason: 'Session.clear({required SessionEndReason reason}) 시그니처가 바뀌었다',
    );
  });
}
