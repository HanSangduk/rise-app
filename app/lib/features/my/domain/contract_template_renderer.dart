// 순수 도메인 — 계약서 템플릿(마크다운 부분집합)의 **결정적 파서/렌더러**. Flutter 의존 0.
//
// 마크다운 패키지를 쓰지 않는 이유(P39 결정 5): flutter_markdown 계열은 패키지 버전에
// 따라 렌더가 변해 계약서doc §D "언제나 같은 결과"(전자문서법 §5①2 재현성)와 상충한다.
// P32가 브랜드 마크를 자산 대신 CustomPainter로 그린 것과 같은 원칙의 연장 — 재현이
// 요건이면 렌더 경로를 우리가 소유한다.
//
// **파싱 범위 = assets/legal/contract_pt_v1.md(§A)가 실제 쓰는 문법 전부, 그 이상 금지.**
// 2026-08-29 전수 스캔 인벤토리(P39):
//   · 헤딩 `# `/`## `/`### `(1·2·25곳) — h4+는 없다
//   · 문단 — 연속 행은 공백으로 결합(굵게가 행을 넘어 이어지는 곳 포함)
//   · `**굵게**` — 홑별표·밑줄·백틱·링크·이미지·HTML(단일 행 주석 제외)은 §A에 없다
//   · 표 — 선행·후행 `|`, 구분자 `---`/`---:`(우측 정렬 2곳), 빈 헤더 `| | |` 1곳(서명란)
//   · 순서 목록 `N. ` 17항목 + 들여쓴 연속 행 — 비순서 `- `는 §A에 없다
//   · 인용 `> ` 3곳(여러 행, 굵게·슬롯 포함)
//   · 맨 코드펜스 ``` 2곳(제13조 산식·[별지] 신청서) — **펜스 안에서도 슬롯은 치환**한다:
//     [별지]의 "받는 사람" 칸은 실제 상호·연락처가 인쇄돼야 하는 법정 서식이다(방판법 §30①6)
//   · 수평선 `---` 3곳 · 단일 행 HTML 주석(파싱에서 스킵 — 가버전 표시 헤더 포함)
// 이 목록 밖의 문법을 만나면 **렌더하지 않고 [ContractRenderUnknownSyntax]로 거부한다**
// (모르는 것을 아는 척하지 않는다). 조용히 평문으로 굴리면 회원이 보는 문서가 원문
// 의도와 달라진 채 서명된다(§D D-4 "본 것 = 서명한 것").
//
// 슬롯 입력이 두 맵인 이유(P39 결정 3):
//   · [vars] — send가 확정하고 sha256이 봉인하는 Vars 스냅샷(§C 29종 중 28종).
//   · [entityVars] — Vars **밖** 슬롯. 지금은 {{계약 체결일}} 하나로, send 시점엔 값이
//     존재하지 않아 엔티티 필드에서 렌더 시점에 온다(signed_at, 미서명이면 first_sent_at —
//     계약서doc :781 표시 규칙).
//   한 맵으로 합치면 "이 값은 해시가 덮는가"가 시그니처에서 사라진다 — 체결일을 Vars에
//   얼려 보내는 실수도, 반대로 Vars 값을 렌더 시점 실시간 값으로 덮는 실수도 타입이
//   막지 못한다. 같은 키가 양쪽에 오면 우선순위를 정하는 대신 거부한다(우선순위가 곧
//   조용한 덮어쓰기다) — [ContractRenderSlotSourceConflict].
//
// 치환은 파싱 **뒤에** 온다: 슬롯 값은 데이터지 마크업이 아니다. 값에 `**`·`{{`·`- `가
// 들어 있어도 재파싱되지 않고 문자 그대로 렌더된다 — 값 내용이 문서 구조를 흔들 수
// 없어야 "본 것 = 서명한 것"이 값과 무관하게 성립한다. 값 누락은 문서 전체를 훑어
// **전부 모은 뒤** [ContractRenderMissingVars]로 한 번에 거부한다(부분 치환된 모델은
// 타입상 존재하지 않는다 — 실패 갈래에는 document가 없다).

import 'package:rise_member/features/my/domain/contract_render_model.dart';

/// 결정적 부분집합 렌더러 — 같은 (template, vars, entityVars)는 언제나 같은
/// [ContractRenderOutcome]을 낸다(시계·로케일·플랫폼 입력 0).
abstract final class ContractTemplateRenderer {
  /// [template]을 파싱하고 슬롯을 치환해 블록 모델을 만든다.
  ///
  /// 거부 우선순위(항상 이 순서라 결과가 결정적이다):
  /// ① 구조(미지 문법) → ② 슬롯 원천 충돌 → ③ 슬롯 값 누락(전부 수집).
  static ContractRenderOutcome render({
    required String template,
    required Map<String, String> vars,
    required Map<String, String> entityVars,
  }) {
    // ① 구조 파싱 — 치환 전. 미지 문법이면 여기서 끝난다.
    final parser = _Parser(template);
    final raw = parser.parse();
    if (raw == null) return parser.refusal!;

    // ② 같은 키가 양쪽에 있으면 거부 — 파일 상단 "슬롯 입력이 두 맵인 이유" 참조.
    final conflict = vars.keys.where(entityVars.containsKey).toList()..sort();
    if (conflict.isNotEmpty) {
      return ContractRenderSlotSourceConflict(conflict);
    }

    // ③ 누락 키를 문서 전체에서 첫 등장 순서로 전부 모은다.
    String? lookup(String key) => vars[key] ?? entityVars[key];
    final missing = <String>[];
    for (final toks in _allTokLists(raw)) {
      for (final t in toks) {
        if (t is _SlotTok && lookup(t.key) == null && !missing.contains(t.key)) {
          missing.add(t.key);
        }
      }
    }
    if (missing.isNotEmpty) return ContractRenderMissingVars(missing);

    // 치환·조립 — 여기 도달하면 실패 경로가 없다.
    return ContractRenderReady(ContractDocument([
      for (final b in raw) _build(b, lookup),
    ]));
  }

  static Iterable<List<_Tok>> _allTokLists(List<_RawBlock> blocks) sync* {
    for (final b in blocks) {
      switch (b) {
        case _RawHeading(:final toks):
          yield toks;
        case _RawParagraph(:final toks):
          yield toks;
        case _RawQuote(:final toks):
          yield toks;
        case _RawListItem(:final toks):
          yield toks;
        case _RawTable(:final header, :final rows):
          yield* header;
          for (final r in rows) {
            yield* r;
          }
        case _RawCode(:final lineToks):
          yield* lineToks;
        case _RawDivider():
          break;
      }
    }
  }

  static ContractBlock _build(_RawBlock b, String? Function(String) lookup) {
    switch (b) {
      case _RawHeading(:final level, :final toks):
        return ContractHeading(level, _runs(toks, lookup));
      case _RawParagraph(:final toks):
        return ContractParagraph(_runs(toks, lookup));
      case _RawQuote(:final toks):
        return ContractQuote(_runs(toks, lookup));
      case _RawListItem(:final ordinal, :final toks):
        return ContractListItem(ordinal, _runs(toks, lookup));
      case _RawTable(:final aligns, :final header, :final rows):
        return ContractTable(
          aligns: aligns,
          headerCells: [for (final c in header) ContractTableCell(_runs(c, lookup))],
          rows: [
            for (final r in rows) [for (final c in r) ContractTableCell(_runs(c, lookup))],
          ],
        );
      case _RawCode(:final lineToks):
        return ContractCodeBlock([
          for (final toks in lineToks)
            toks.map((t) => t is _SlotTok ? lookup(t.key)! : (t as _TextTok).text).join(),
        ]);
      case _RawDivider():
        return const ContractDivider();
    }
  }

  /// 토큰 → 런. 값은 문자 그대로 들어가고(재파싱 없음), 같은 굵기의 이웃 런은
  /// 합친다 — 토큰 경계가 아니라 **보이는 결과**가 모델이 되게(결정성 비교가
  /// 내부 토큰화 방식에 흔들리지 않는다).
  static List<ContractRun> _runs(List<_Tok> toks, String? Function(String) lookup) {
    final out = <ContractRun>[];
    for (final t in toks) {
      final text = t is _SlotTok ? lookup(t.key)! : (t as _TextTok).text;
      if (text.isEmpty) continue;
      if (out.isNotEmpty && out.last.bold == t.bold) {
        out[out.length - 1] = ContractRun(out.last.text + text, bold: t.bold);
      } else {
        out.add(ContractRun(text, bold: t.bold));
      }
    }
    return out;
  }
}

// ── 내부 표현 ────────────────────────────────────────────────────────────────

/// 치환 전 인라인 토큰 — 텍스트 조각 또는 슬롯 참조. 둘 다 굵기를 안다.
sealed class _Tok {
  const _Tok(this.bold);
  final bool bold;
}

final class _TextTok extends _Tok {
  const _TextTok(this.text, bool bold) : super(bold);
  final String text;
}

final class _SlotTok extends _Tok {
  const _SlotTok(this.key, bool bold) : super(bold);
  final String key;
}

/// 치환 전 블록 — 최종 블록과 1:1이되 텍스트 자리가 토큰 리스트다.
sealed class _RawBlock {
  const _RawBlock();
}

final class _RawHeading extends _RawBlock {
  const _RawHeading(this.level, this.toks);
  final int level;
  final List<_Tok> toks;
}

final class _RawParagraph extends _RawBlock {
  const _RawParagraph(this.toks);
  final List<_Tok> toks;
}

final class _RawQuote extends _RawBlock {
  const _RawQuote(this.toks);
  final List<_Tok> toks;
}

final class _RawListItem extends _RawBlock {
  const _RawListItem(this.ordinal, this.toks);
  final int ordinal;
  final List<_Tok> toks;
}

final class _RawTable extends _RawBlock {
  const _RawTable(this.aligns, this.header, this.rows);
  final List<ContractCellAlign> aligns;
  final List<List<_Tok>> header;
  final List<List<List<_Tok>>> rows;
}

final class _RawCode extends _RawBlock {
  const _RawCode(this.lineToks);
  final List<List<_Tok>> lineToks;
}

final class _RawDivider extends _RawBlock {
  const _RawDivider();
}

// ── 파서 ────────────────────────────────────────────────────────────────────

/// 행 단위 상태 기계. 실패는 예외가 아니라 [refusal]에 남긴다(도메인·presentation은
/// 예외가 아니라 값 — core/result/failure.dart와 같은 원칙).
final class _Parser {
  _Parser(String template) : _lines = template.split('\n');

  final List<String> _lines;
  int _i = 0;
  final List<_RawBlock> _blocks = [];

  ContractRenderUnknownSyntax? refusal;

  static final _headingRe = RegExp(r'^(#{1,3}) (.+)$');
  static final _listItemRe = RegExp(r'^(\d{1,2})\. (.+)$');
  static final _commentRe = RegExp(r'^<!--.*-->$');
  static final _sepCellRe = RegExp(r'^-{3,}:?$');
  static final _slotRe = RegExp(r'\{\{([^{}]+)\}\}');
  static final _linkRe = RegExp(r'\[[^\]]*\]\(');

  /// 비순서 목록 마커 — 단문자 `-`/`*`/`+` 뒤 공백(또는 행 끝). `**굵게**`로 시작하는
  /// 행은 두 번째 문자가 `*`라 걸리지 않는다(§A 서명일 행 `**{{계약 체결일}}**`).
  static final _bulletRe = RegExp(r'^[*+-](\s|$)');

  /// 수평선·세텍스트 변형(`----`·`***`·`___`·`===`) — §A는 정확히 `---`만 쓴다.
  static final _ruleVariantRe = RegExp(r'^(-{2,}|\*{3,}|_{3,}|={2,})$');

  List<_RawBlock>? parse() {
    while (_i < _lines.length) {
      final rawLine = _lines[_i];
      if (rawLine.trim().isEmpty) {
        _i++;
        continue;
      }
      final line = _checkedTrimRight(rawLine);
      if (refusal != null) return null;

      if (line.startsWith('```')) {
        _fence(line);
      } else if (line.startsWith('<!--') || line.startsWith('<')) {
        _comment(line);
      } else if (line.startsWith('#')) {
        _heading(line);
      } else if (line.startsWith('|')) {
        _table();
      } else if (line.startsWith('>')) {
        _quote();
      } else if (line == '---') {
        _blocks.add(const _RawDivider());
        _i++;
      } else if (_bulletRe.hasMatch(line)) {
        _refuse(_i, '비순서 목록(`- `) — §A 미사용 문법');
      } else if (_ruleVariantRe.hasMatch(line)) {
        _refuse(_i, '수평선/세텍스트 변형 — §A는 `---`만 쓴다');
      } else if (_listItemRe.hasMatch(line)) {
        _listItem(line);
      } else if (rawLine.startsWith(' ')) {
        _refuse(_i, '고아 들여쓴 행 — 목록 연속 행이 아닌 들여쓰기(코드 들여쓰기 등) 미지원');
      } else {
        _paragraph(line);
      }
      if (refusal != null) return null;
    }
    return _blocks;
  }

  void _refuse(int lineIdx, String what) {
    refusal ??= ContractRenderUnknownSyntax(
      lineNumber: lineIdx + 1,
      lineText: _lines[lineIdx].trimRight(),
      what: what,
    );
  }

  /// 행끝 공백 처리 — 1개는 노이즈로 지우고, 2개 이상은 마크다운 하드 브레이크
  /// 문법이므로 거부한다(우리는 소프트랩 결합만 안다). 펜스 안은 여기를 안 탄다.
  String _checkedTrimRight(String raw) {
    final t = raw.trimRight();
    if (raw.length >= t.length + 2) {
      _refuse(_i, '행끝 공백 2개 이상(하드 브레이크) — 미지원');
    }
    return t;
  }

  /// 다음 비어 있지 않은 행 앞이 빈 행인가 — 문단·목록이 블록에 "붙어" 있으면
  /// CommonMark 해석(세텍스트 헤딩·지연 연속)과 이 파서가 갈라지므로, 갈라질 수 있는
  /// 배치 자체를 미지로 취급한다.
  bool _nextIsAdjacentBlock() => _i < _lines.length && _lines[_i].trim().isNotEmpty;

  void _fence(String openLine) {
    if (openLine != '```') {
      _refuse(_i, '정보 문자열 붙은 코드펜스 — §A는 맨 ``` 만 쓴다');
      return;
    }
    final openIdx = _i;
    var j = _i + 1;
    final lineToks = <List<_Tok>>[];
    while (j < _lines.length) {
      final l = _lines[j];
      if (l.trimRight() == '```') {
        _blocks.add(_RawCode(lineToks));
        _i = j + 1;
        return;
      }
      // 펜스 안은 서식 보존(원문 그대로) + 슬롯 치환만. 인라인 금지 목록도 안 탄다 —
      // [별지]의 ─·□ 괘선과 임의 공백이 전부 내용이다.
      final toks = _slotToks(l, bold: false, lineIdx: j, out: <_Tok>[]);
      if (toks == null) return;
      lineToks.add(toks);
      j++;
    }
    _refuse(openIdx, '닫히지 않은 코드펜스');
  }

  void _comment(String line) {
    if (!_commentRe.hasMatch(line)) {
      _refuse(_i, 'HTML 태그/여러 행 주석 — 단일 행 `<!-- -->` 주석만 지원');
      return;
    }
    // 스킵 — 주석 안 `{{...}}`는 슬롯으로 세지 않는다(§A :36의 리터럴 예시,
    // 자산 머리의 가버전 표시 주석이 여기를 지나간다).
    _i++;
  }

  void _heading(String line) {
    final m = _headingRe.firstMatch(line);
    if (m == null) {
      _refuse(_i, 'h4+ 헤딩 또는 `#` 형식 오류 — §A는 h1~h3만 쓴다');
      return;
    }
    final toks = _inlineToks(m.group(2)!, _i);
    if (toks == null) return;
    _blocks.add(_RawHeading(m.group(1)!.length, toks));
    _i++;
  }

  void _table() {
    final startIdx = _i;
    final rows = <List<String>>[];
    final rowIdx = <int>[];
    while (_i < _lines.length && _lines[_i].startsWith('|')) {
      final line = _checkedTrimRight(_lines[_i]);
      if (refusal != null) return;
      if (line.length < 2 || !line.endsWith('|')) {
        _refuse(_i, '표 행이 `|`로 닫히지 않음');
        return;
      }
      rows.add([
        for (final c in line.substring(1, line.length - 1).split('|')) c.trim(),
      ]);
      rowIdx.add(_i);
      _i++;
    }
    if (rows.length < 3) {
      _refuse(startIdx, '표는 헤더·구분자·본문 1행 이상이어야 함 — §A 표 최소형');
      return;
    }
    final sep = rows[1];
    if (!sep.every(_sepCellRe.hasMatch)) {
      _refuse(rowIdx[1], '표 구분자 형식 밖 — §A는 `---`/`---:`만 쓴다');
      return;
    }
    final cols = rows.first.length;
    for (var r = 0; r < rows.length; r++) {
      if (rows[r].length != cols) {
        _refuse(rowIdx[r], '표 열 수 불일치(헤더 $cols열, 이 행 ${rows[r].length}열)');
        return;
      }
    }
    final aligns = [
      for (final c in sep) c.endsWith(':') ? ContractCellAlign.right : ContractCellAlign.left,
    ];
    final header = <List<_Tok>>[];
    for (final c in rows.first) {
      final toks = _inlineToks(c, rowIdx.first);
      if (toks == null) return;
      header.add(toks);
    }
    final body = <List<List<_Tok>>>[];
    for (var r = 2; r < rows.length; r++) {
      final rowToks = <List<_Tok>>[];
      for (final c in rows[r]) {
        final toks = _inlineToks(c, rowIdx[r]);
        if (toks == null) return;
        rowToks.add(toks);
      }
      body.add(rowToks);
    }
    if (_nextIsAdjacentBlock()) {
      _refuse(_i, '빈 줄 없이 표에 붙은 행 — 해석이 갈릴 수 있는 배치 미지원');
      return;
    }
    _blocks.add(_RawTable(aligns, header, body));
  }

  void _quote() {
    final startIdx = _i;
    final parts = <String>[];
    while (_i < _lines.length && _lines[_i].startsWith('>')) {
      final line = _checkedTrimRight(_lines[_i]);
      if (refusal != null) return;
      final m = RegExp(r'^> (.+)$').firstMatch(line);
      if (m == null) {
        _refuse(_i, '인용 형식(`> 내용`) 밖 — 빈 인용/`>>` 미지원');
        return;
      }
      final inner = m.group(1)!;
      if (_looksLikeBlockStart(inner)) {
        _refuse(_i, '인용 안 블록 문법 — §A 인용은 텍스트(굵게·슬롯)뿐');
        return;
      }
      parts.add(inner);
      _i++;
    }
    if (_nextIsAdjacentBlock()) {
      _refuse(_i, '빈 줄 없이 인용에 붙은 행 — 해석이 갈릴 수 있는 배치 미지원');
      return;
    }
    final toks = _inlineToks(parts.join(' '), startIdx);
    if (toks == null) return;
    _blocks.add(_RawQuote(toks));
  }

  void _listItem(String line) {
    final startIdx = _i;
    final m = _listItemRe.firstMatch(line)!;
    final buf = StringBuffer(m.group(2)!);
    _i++;
    // 연속 행: 들여쓴(공백 시작) 비어 있지 않은 행 — §A는 3칸을 쓰지만 폭은 재지
    // 않는다(폭이 의미를 바꾸는 문법이 아니고, 소프트랩 결합 결과는 같다).
    while (_i < _lines.length &&
        _lines[_i].trim().isNotEmpty &&
        _lines[_i].startsWith(' ')) {
      final cont = _checkedTrimRight(_lines[_i]);
      if (refusal != null) return;
      buf
        ..write(' ')
        ..write(cont.trimLeft());
      _i++;
    }
    // 빈 줄 없이 목록에 붙은 평문 행은 CommonMark에선 항목의 지연 연속이 된다 —
    // 이 파서(새 문단)와 해석이 갈리므로 미지로 취급. 다음 항목(`N. `)은 양쪽
    // 해석이 같아 허용한다.
    if (_nextIsAdjacentBlock() && !_listItemRe.hasMatch(_lines[_i].trimRight())) {
      _refuse(_i, '빈 줄 없이 목록에 붙은 행(지연 연속 가능성) — 미지원');
      return;
    }
    final toks = _inlineToks(buf.toString(), startIdx);
    if (toks == null) return;
    _blocks.add(_RawListItem(int.parse(m.group(1)!), toks));
  }

  void _paragraph(String first) {
    final startIdx = _i;
    final parts = <String>[first];
    _i++;
    while (_i < _lines.length && _lines[_i].trim().isNotEmpty) {
      final raw = _lines[_i];
      final line = _checkedTrimRight(raw);
      if (refusal != null) return;
      if (raw.startsWith(' ') || _looksLikeBlockStart(line)) {
        // 빈 줄 없이 문단에 붙은 블록 — CommonMark라면 `---`는 세텍스트 h2가 되고
        // `|` 행은 지연 연속이 되는 자리다. 해석이 갈라지는 배치는 미지로 취급한다.
        _refuse(_i, '빈 줄 없이 문단에 붙은 블록(세텍스트/지연 연속 가능성) — 미지원');
        return;
      }
      parts.add(line);
      _i++;
    }
    final toks = _inlineToks(parts.join(' '), startIdx);
    if (toks == null) return;
    _blocks.add(_RawParagraph(toks));
  }

  bool _looksLikeBlockStart(String s) =>
      s.startsWith('#') ||
      s.startsWith('|') ||
      s.startsWith('>') ||
      s.startsWith('```') ||
      s.startsWith('<') ||
      s.startsWith(' ') ||
      _bulletRe.hasMatch(s) ||
      _ruleVariantRe.hasMatch(s) ||
      _listItemRe.hasMatch(s) ||
      s == '---';

  /// 인라인 파싱 — 허용: 평문·`**굵게**`·`{{슬롯}}`. 그 외 인라인 마크업 후보는 전부
  /// 거부한다. 검사 대상은 **템플릿 원문**이다 — 슬롯 값은 데이터라 검사하지 않는다
  /// (치환이 파싱 뒤에 오는 이유, 파일 상단 참조).
  List<_Tok>? _inlineToks(String text, int lineIdx) {
    if (text.contains('`')) {
      _refuse(lineIdx, '백틱(인라인 코드) — §A 미사용 문법');
      return null;
    }
    if (text.contains(r'\')) {
      _refuse(lineIdx, '백슬래시 이스케이프 — §A 미사용 문법');
      return null;
    }
    if (text.contains('<')) {
      _refuse(lineIdx, '인라인 HTML/오토링크(`<`) — §A 미사용 문법');
      return null;
    }
    if (text.contains('_')) {
      _refuse(lineIdx, '밑줄(`_`) 강조 — §A 미사용 문법');
      return null;
    }
    if (text.contains('![') || _linkRe.hasMatch(text)) {
      _refuse(lineIdx, '링크/이미지 문법 — §A 미사용([별표]류 대괄호는 평문이라 통과)');
      return null;
    }
    final parts = text.split('**');
    if (parts.length.isEven) {
      _refuse(lineIdx, '짝이 맞지 않는 `**`');
      return null;
    }
    final out = <_Tok>[];
    for (var p = 0; p < parts.length; p++) {
      final bold = p.isOdd;
      if (bold && parts[p].isEmpty) {
        _refuse(lineIdx, '빈 굵게(`****`)');
        return null;
      }
      if (parts[p].contains('*')) {
        _refuse(lineIdx, '홑별표 강조 — §A 미사용 문법');
        return null;
      }
      if (_slotToks(parts[p], bold: bold, lineIdx: lineIdx, out: out) == null) {
        return null;
      }
    }
    return out;
  }

  /// [part]에서 `{{키}}`를 토큰으로 뽑는다. 슬롯 밖에 중괄호가 남으면(짝 안 맞는
  /// `{{`/`}}`, 홑중괄호) 거부 — 슬롯처럼 보이는데 슬롯이 아닌 것을 평문으로
  /// 흘리지 않는다.
  List<_Tok>? _slotToks(
    String part, {
    required bool bold,
    required int lineIdx,
    required List<_Tok> out,
  }) {
    var last = 0;
    for (final m in _slotRe.allMatches(part)) {
      final before = part.substring(last, m.start);
      if (before.contains('{') || before.contains('}')) {
        _refuse(lineIdx, '슬롯 밖 중괄호 — `{{키}}` 형식 밖');
        return null;
      }
      if (before.isNotEmpty) out.add(_TextTok(before, bold));
      out.add(_SlotTok(m.group(1)!, bold));
      last = m.end;
    }
    final tail = part.substring(last);
    if (tail.contains('{') || tail.contains('}')) {
      _refuse(lineIdx, '슬롯 밖 중괄호 — `{{키}}` 형식 밖');
      return null;
    }
    if (tail.isNotEmpty) out.add(_TextTok(tail, bold));
    return out;
  }
}
