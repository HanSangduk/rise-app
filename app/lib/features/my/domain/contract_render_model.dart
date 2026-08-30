// 순수 도메인 — 계약서 본문 렌더의 **블록 모델과 결과 타입**. Flutter/외부 의존 0, codegen 0.
//
// 계약서doc §D(렌더링 설계)의 "언제나 같은 결과" 요건에서 앱이 지는 절반이 이 모델이다
// (P39 결정 5): 파서(contract_template_renderer.dart)는 템플릿이 실제 쓰는 문법만
// 이 블록들로 옮기고, 위젯(contract_document_view.dart)은 이 모델만 그린다.
//
// 전 타입이 값 동등성(==)을 구현하는 이유: 결정성(같은 입력 → 같은 모델)을 테스트가
// deep-equal 한 번으로 물을 수 있어야 한다. equatable 같은 의존은 더하지 않고 손으로
// 쓴다(pubspec "도메인 엔티티는 codegen 없는 순수 Dart" 원칙과 같은 자리).

/// 인라인 런 — 굵기만 갈리는 텍스트 조각.
///
/// 템플릿 §A의 인라인 문법은 `**굵게**`가 전부라(홑별표·밑줄·링크·인라인 코드 없음 —
/// 렌더러 파일 상단의 2026-08-29 전수 인벤토리 참조) 이 한 타입으로 닫힌다.
/// 슬롯 값이 개행(`{{납부일정}}`의 "\n" 결합 — P39 결정 4)을 품으면 [text]에 그대로
/// 남는다 — 표 셀 안 여러 줄 표시는 위젯의 Text가 처리한다.
final class ContractRun {
  const ContractRun(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  bool operator ==(Object other) =>
      other is ContractRun && other.text == text && other.bold == bold;

  @override
  int get hashCode => Object.hash(text, bold);

  @override
  String toString() => bold ? 'b«$text»' : '«$text»';
}

/// 렌더 블록 (Dart 3 sealed — exhaustive 스위치로 위젯이 전 케이스를 강제 처리).
sealed class ContractBlock {
  const ContractBlock();
}

/// 헤딩 `# `·`## `·`### ` — [level]은 1~3. §A에 h4+는 없고, 나오면 파서가 거부한다.
final class ContractHeading extends ContractBlock {
  const ContractHeading(this.level, this.runs);

  final int level;
  final List<ContractRun> runs;

  @override
  bool operator ==(Object other) =>
      other is ContractHeading && other.level == level && _listEq(other.runs, runs);

  @override
  int get hashCode => Object.hash(level, Object.hashAll(runs));

  @override
  String toString() => 'H$level$runs';
}

/// 문단 — 원문의 연속 행(소프트랩)은 공백으로 결합돼 하나의 문단이 된다.
final class ContractParagraph extends ContractBlock {
  const ContractParagraph(this.runs);

  final List<ContractRun> runs;

  @override
  bool operator ==(Object other) =>
      other is ContractParagraph && _listEq(other.runs, runs);

  @override
  int get hashCode => Object.hashAll(runs);

  @override
  String toString() => 'P$runs';
}

/// 인용(`> `) — §A에 3곳(부가상품 대체 지침·노쇼 유예 안내·[별지] 근거). 여러 행은
/// 문단처럼 공백으로 결합한다.
final class ContractQuote extends ContractBlock {
  const ContractQuote(this.runs);

  final List<ContractRun> runs;

  @override
  bool operator ==(Object other) => other is ContractQuote && _listEq(other.runs, runs);

  @override
  int get hashCode => Object.hashAll(runs);

  @override
  String toString() => 'Q$runs';
}

/// 순서 목록 항목 `N. ` — [ordinal]은 템플릿의 번호 그대로다(재번호를 매기지 않는다 —
/// 조문이 "제1항 제5호"처럼 번호를 지시 대상으로 쓰므로 원문 충실이 우선).
/// 3칸 들여쓴 연속 행은 항목 본문에 공백으로 결합된다.
final class ContractListItem extends ContractBlock {
  const ContractListItem(this.ordinal, this.runs);

  final int ordinal;
  final List<ContractRun> runs;

  @override
  bool operator ==(Object other) =>
      other is ContractListItem && other.ordinal == ordinal && _listEq(other.runs, runs);

  @override
  int get hashCode => Object.hash(ordinal, Object.hashAll(runs));

  @override
  String toString() => 'L$ordinal$runs';
}

/// 표 셀 — 셀 안에도 굵게·슬롯이 온다(`**환급액**`, `{{위약금율}}%`).
final class ContractTableCell {
  const ContractTableCell(this.runs);

  final List<ContractRun> runs;

  /// 서명란 표의 빈 헤더(`| | |`) 판정용.
  bool get isEmpty => runs.isEmpty;

  @override
  bool operator ==(Object other) => other is ContractTableCell && _listEq(other.runs, runs);

  @override
  int get hashCode => Object.hashAll(runs);

  @override
  String toString() => 'C$runs';
}

/// 열 정렬 — §A 구분자는 `---`(왼쪽)와 `---:`(오른쪽, 산정 예시 금액 열)뿐이다.
/// `:---`·`:---:`는 §A에 없으므로 파서가 거부한다.
enum ContractCellAlign { left, right }

/// 표 — 헤더 1행 + 본문 N행. [headerCells]가 전부 비면(서명란 `| | |`) 위젯이 헤더
/// 행을 그리지 않는 표시 선택을 한다(모델은 원문 그대로 보존).
final class ContractTable extends ContractBlock {
  const ContractTable({
    required this.aligns,
    required this.headerCells,
    required this.rows,
  });

  final List<ContractCellAlign> aligns;
  final List<ContractTableCell> headerCells;
  final List<List<ContractTableCell>> rows;

  @override
  bool operator ==(Object other) {
    if (other is! ContractTable) return false;
    if (!_listEq(other.aligns, aligns)) return false;
    if (!_listEq(other.headerCells, headerCells)) return false;
    if (other.rows.length != rows.length) return false;
    for (var i = 0; i < rows.length; i++) {
      if (!_listEq(other.rows[i], rows[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(aligns),
        Object.hashAll(headerCells),
        Object.hashAll(rows.map(Object.hashAll)),
      );

  @override
  String toString() => 'T(${headerCells.length}x${rows.length})';
}

/// 코드펜스(``` ```) — 슬롯만 치환하고 그 외 원문 그대로 보존하는 서식 블록.
/// §A에 2곳: 제13조 산식, [별지] 해지·청약철회 신청서(슬롯 3종이 실제로 치환된다 —
/// "받는 사람" 칸이 실제 상호·연락처로 인쇄돼야 하는 법정 서식이라서, 방판법 §30①6).
final class ContractCodeBlock extends ContractBlock {
  const ContractCodeBlock(this.lines);

  final List<String> lines;

  @override
  bool operator ==(Object other) => other is ContractCodeBlock && _listEq(other.lines, lines);

  @override
  int get hashCode => Object.hashAll(lines);

  @override
  String toString() => 'F(${lines.length})';
}

/// 수평선 `---` — §A에 3곳(표제부/서명란 경계).
final class ContractDivider extends ContractBlock {
  const ContractDivider();

  @override
  bool operator ==(Object other) => other is ContractDivider;

  @override
  int get hashCode => (ContractDivider).hashCode;

  @override
  String toString() => 'HR';
}

/// 렌더된 문서 — 성공 결과의 전부. 위젯은 이것만 받는다.
final class ContractDocument {
  const ContractDocument(this.blocks);

  final List<ContractBlock> blocks;

  @override
  bool operator ==(Object other) => other is ContractDocument && _listEq(other.blocks, blocks);

  @override
  int get hashCode => Object.hashAll(blocks);

  @override
  String toString() => 'Doc${blocks.join(',')}';
}

/// 렌더 결과 (Dart 3 sealed — [ContractRenderRefused]까지 갈래가 닫혀 있어 호출자가
/// 폴백 분기를 빠뜨리면 컴파일이 막는다. hold_rules.dart의 HoldRequestState와 같은
/// 자리매김: core의 Result/Failure는 데이터 레이어 실패용, 이건 도메인 판정이다).
sealed class ContractRenderOutcome {
  const ContractRenderOutcome();
}

/// 렌더 가능 — [document]가 화면에 그릴 전부다.
final class ContractRenderReady extends ContractRenderOutcome {
  const ContractRenderReady(this.document);

  final ContractDocument document;
}

/// 렌더 거부 — **모르는 것을 아는 척하지 않는다**(P39 결정 5). 어떤 폴백을 보여줄지는
/// 호출자 몫이다(§D: 미지 template_version → "앱을 업데이트해야 볼 수 있어요",
/// Vars 없는 레거시 → 지금의 요약 문구 유지). [reason]은 로그·테스트용 한국어 설명이지
/// 회원에게 띄우는 문구가 아니다.
sealed class ContractRenderRefused extends ContractRenderOutcome {
  const ContractRenderRefused();

  String get reason;
}

/// 템플릿에 이 파서가 모르는(= §A 전수 인벤토리 밖의) 문법이 있다.
///
/// 조용히 평문으로 굴리는 대신 거부하는 이유: 회원이 보는 문서가 원문 의도와 달라진
/// 채 서명되면 그것이 곧 계약 내용이 된다(§D D-4 "본 것 = 서명한 것"). 템플릿 동결
/// 시점에 문법이 늘면 여기 걸려 **시끄럽게** 실패하고, 파서를 의식적으로 넓힌 뒤
/// 골든을 다시 고정한다.
final class ContractRenderUnknownSyntax extends ContractRenderRefused {
  const ContractRenderUnknownSyntax({
    required this.lineNumber,
    required this.lineText,
    required this.what,
  });

  /// 렌더러에 들어온 템플릿 문자열 기준 1-시작 행 번호(자산 파일 행 번호와 같다).
  final int lineNumber;

  final String lineText;

  /// 무엇이 미지였는지 — 한국어 한 구.
  final String what;

  @override
  String get reason => '미지 문법(행 $lineNumber, $what): $lineText';
}

/// 템플릿 슬롯인데 vars에도 entityVars에도 없는 키 — 서버 Vars 조립 누락의 신호이고,
/// 호출자는 오늘의 요약 고지 경로로 폴백한다(P39 목표: 래치 OFF 동안 다운스트림은
/// 오늘 동작 그대로).
///
/// [missingKeys]는 **전부**를 담는다(첫 등장 순서, 중복 없음) — 첫 키만 알리면
/// 서버에서 한 키 고칠 때마다 재현·왕복이 한 번씩 늘어난다.
final class ContractRenderMissingVars extends ContractRenderRefused {
  const ContractRenderMissingVars(this.missingKeys);

  final List<String> missingKeys;

  @override
  String get reason => '슬롯 값 누락: ${missingKeys.join(', ')}';
}

/// 같은 키가 vars와 entityVars 양쪽에 있다 — 어느 쪽이 회원이 서명한 진실인지
/// 렌더러가 정할 수 없다. 우선순위를 정하는 순간 그것이 곧 조용한 덮어쓰기라서,
/// P39 결정 3이 가른 경계(sha256이 봉인하는 Vars ↔ 엔티티에서 렌더 시점에 오는 값)가
/// 호출부에서 무너졌다는 신호로 보고 거부한다. [keys]는 사전순.
final class ContractRenderSlotSourceConflict extends ContractRenderRefused {
  const ContractRenderSlotSourceConflict(this.keys);

  final List<String> keys;

  @override
  String get reason => '슬롯 원천 충돌(vars ∩ entityVars): ${keys.join(', ')}';
}

/// 요소별 ==에 기대는 얕은 리스트 비교 — 모델 전 타입의 값 동등성 구현부.
/// (계약 렌더 모델 전용 헬퍼라 도메인 파일에 둔다. collection 패키지를 직접 의존에
/// 올리지 않기 위한 7줄이다.)
bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
