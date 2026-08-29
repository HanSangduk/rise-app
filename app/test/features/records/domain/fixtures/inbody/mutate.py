"""P20 뮤테이션 검증 — 파서/어댑터의 각 규칙을 하나씩 무력화하고
테스트가 실제로 실패하는지 확인한 뒤 복구한다."""
import subprocess
import sys

APP = '/Users/straram/development/2026-06-workout-app/ptdesk/app'
PARSER = f'{APP}/lib/features/records/domain/inbody_sheet_parser.dart'
READER = f'{APP}/lib/features/records/data/inbody_sheet_reader.dart'
PARSER_TEST = 'test/features/records/domain/inbody_sheet_parser_test.dart'
READER_TEST = 'test/features/records/data/inbody_sheet_reader_test.dart'

MUTATIONS = [
    ('R1 완전일치→포함매칭', PARSER, PARSER_TEST,
     ': n == label;', ': n.contains(label);'),
    ('R2 신체변화 필터 제거', PARSER, PARSER_TEST,
     'if (hist.any((h) => _cy(t) < _cy(h) && t.x > h.x - 0.05)) continue;',
     'if (hist.any((h) => false)) continue;'),
    ('R2b 하단 15% 컷 제거', PARSER, PARSER_TEST,
     'if (_cy(t) >= cut) t,', 'if (_cy(t) >= cut || true) t,'),
    ('R3 기울기 보정 무력화', PARSER, PARSER_TEST,
     'final List<InbodyOcrToken> sel;',
     'if (fallback.isFinite) return fallback;\n  final List<InbodyOcrToken> sel;'),
    ('R4 kg/% 정수 허용', PARSER, PARSER_TEST,
     '''  } else {
    for (final m in _dec.allMatches(head)) {''',
     r'''  } else {
    for (final m in RegExp(r'(?<![\d.])\d{1,4}(?![\d.])').allMatches(head)) {
      final v = double.parse(m[0]!);
      if (lo <= v && v <= hi) vals.add(v);
    }
    for (final m in _dec.allMatches(head)) {'''),
    ('R6 범위 없는 같은 줄 숫자 채택', PARSER, PARSER_TEST,
     'if (inA && rng != null) {', 'if (inA) {'),
    ('R6 A 모호성 판정 제거', PARSER, PARSER_TEST,
     'if (ov >= ov0 - 0.15 && (v - v0).abs() > 0.05) {',
     'if (ov.isNaN) {'),
    ('R7b 행 소유권 제거', PARSER, PARSER_TEST,
     'return owner != null && !identical(owner, anchor);',
     'return owner == null && !identical(owner, anchor);'),
    ('R8 범위형 줄 B 금지 제거', PARSER, PARSER_TEST,
     'if (sawARange) return null;', 'if (sawARange && 1 > 2) return null;'),
    ('R9 선행 1 제거 복원 무력화', PARSER, PARSER_TEST,
     "} else if (v > hi && ds.startsWith('1')) {",
     "} else if (v > hi && ds.startsWith('없음')) {"),
    ('R9 분할 소수 병합 무력화', PARSER, PARSER_TEST,
     'final toks = _mergeSplitDecimals(tokens);',
     'final toks = [...tokens]..sort((a, b) => a.x.compareTo(b.x));'),
    ('R10 B 모호성 판정 제거', PARSER, PARSER_TEST,
     'if (h > 0.88 * h0 && (v - v0).abs() > 0.05) {',
     'if (h.isNaN) {'),
    ('R11 교차 검증 제거', PARSER, PARSER_TEST,
     '''  String? cross(Map<InbodyMetric, double> fields) =>
      InbodyInputRules.crossFieldError(
          {for (final e in fields.entries) e.key: raw(e.value)});''',
     '  String? cross(Map<InbodyMetric, double> fields) => null;'),
    ('R11 항등 검증 제거', PARSER, PARSER_TEST,
     'if (warnAt(w) == null) return;', 'if (warnAt(w) == null || 1 < 2) return;'),
    ('R11 항등 복원(172.5→72.5) 무력화', PARSER, PARSER_TEST,
     'if (100 < w &&', 'if (100 > w &&'),
    ('어댑터 y축 반전 제거', READER, READER_TEST,
     'y: 1 - (b.top + b.height) / h,', 'y: (b.top + b.height) / h,'),
    ('어댑터 한글 라인 필터 제거', READER, READER_TEST,
     'if (!hangul.hasMatch(entry.line.text)) toToken(entry.line),',
     'toToken(entry.line),'),
]

failures = []
for name, target, test, old, new in MUTATIONS:
    src = open(target).read()
    if old not in src:
        print(f'!! 패턴 없음: {name}')
        failures.append(name)
        continue
    if src.count(old) != 1:
        print(f'!! 패턴 중복: {name}')
        failures.append(name)
        continue
    open(target, 'w').write(src.replace(old, new))
    r = subprocess.run(['flutter', 'test', test], cwd=APP,
                       capture_output=True, text=True)
    open(target, 'w').write(src)  # 복구
    caught = r.returncode != 0
    print(f'{"CAUGHT" if caught else "SURVIVED!!"}  {name}')
    if not caught:
        failures.append(name)

print()
if failures:
    print(f'검출 실패 {len(failures)}건: {failures}')
    sys.exit(1)
print(f'전체 {len(MUTATIONS)}개 뮤테이션 전부 검출됨')
