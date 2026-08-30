import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/features/my/domain/contract_render_model.dart';

/// 계약서 본문 뷰 — [ContractDocument] 블록을 앱 타이포로 그린다(P39).
///
/// 스크롤은 **호출자 몫**이다: 서명 시트는 "끝까지 스크롤한 뒤에만 동의 체크박스
/// 활성화"(계약서doc §D-⑤)를 재려고 스크롤 컨트롤러를 직접 쥐어야 하고, 상세 시트는
/// 자기 레이아웃(패턴 B — ConstrainedBox + SingleChildScrollView,
/// center_coaches_sheet 참조)에 끼운다. 그래서 여기는 세로 Column만 세운다.
/// 유일한 내부 스크롤은 서식 블록의 **가로** 스크롤이라 호출자의 세로 스크롤과
/// 충돌하지 않는다.
///
/// 모델이 곧 문서다 — 이 위젯은 [ContractRenderOutcome]을 받지 않는다. 거부 폴백
/// (요약 고지/업데이트 안내)은 시트가 정할 일이고, 여기까지 온 문서는 언제나
/// 렌더 가능한 전문이다.
class ContractDocumentView extends StatelessWidget {
  const ContractDocumentView({super.key, required this.document, this.signatureBlock});

  final ContractDocument document;

  /// 서명란 표 직하단에 도킹되는 블록(P44 결정 4) — **뷰 레이어만의 추가**라
  /// 렌더러·모델·템플릿은 무변경이다(이미지 문법 거부 규약 유지). null이면 오늘
  /// 화면 그대로 — 기존 골든·레이아웃에 0 변화.
  ///
  /// 자리는 **마지막 ContractTable 뒤**: 서명란 표(`| | |` 빈 헤더 2행)는 두 변형
  /// 모두 문서의 마지막 표고, [별지]는 코드펜스라 표가 아니다. "서명 이미지는
  /// 서명란에 붙는다"는 의미를 위치로 말한다. 표가 하나도 없는 문서(규약상 없지만
  /// 방어)에는 끝에 붙인다 — 자리를 못 찾았다고 서명 사실을 숨기지 않는다.
  final Widget? signatureBlock;

  @override
  Widget build(BuildContext context) {
    final blocks = document.blocks;
    // 인덱스는 한 번만 계산한다 — 블록마다 "내가 마지막 표인가"를 물으면 O(n²)다.
    var lastTableIndex = -1;
    if (signatureBlock != null) {
      for (var i = 0; i < blocks.length; i++) {
        if (blocks[i] is ContractTable) lastTableIndex = i;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          _block(blocks[i]),
          if (signatureBlock != null && i == lastTableIndex) signatureBlock!,
        ],
        if (signatureBlock != null && lastTableIndex == -1) signatureBlock!,
      ],
    );
  }

  Widget _block(ContractBlock b) {
    switch (b) {
      case ContractHeading(:final level, :final runs):
        return _heading(level, runs);
      case ContractParagraph(:final runs):
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(_span(runs), style: _body),
        );
      case ContractQuote(:final runs):
        // 안내 인용 — 본문과 톤을 가른다(왼쪽 괘선 + muted). 내용은 계약 정보라
        // 숨기지 않고 그대로 보인다.
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(10, 2, 0, 2),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.line, width: 3)),
          ),
          child: Text.rich(
            _span(runs),
            style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.55),
          ),
        );
      case ContractListItem(:final ordinal, :final runs):
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 템플릿의 번호 그대로 — 조문이 "제1항 제5호"처럼 번호를 지시하므로
              // 위젯이 재번호를 매기지 않는다(모델 주석 참조).
              SizedBox(
                width: 22,
                child: Text(
                  '$ordinal.',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, height: 1.65),
                ),
              ),
              Expanded(child: Text.rich(_span(runs), style: _body)),
            ],
          ),
        );
      case ContractTable(:final aligns, :final headerCells, :final rows):
        return _table(aligns, headerCells, rows);
      case ContractCodeBlock(:final lines):
        // 서식 블록([별지] 신청서·산식) — 원문 칸 나눔을 지키려 고정폭 + 줄바꿈 없이
        // 가로 스크롤. 원문 괘선이 한글 전각 폭 기준이라 완벽한 열 맞춤을 약속하지는
        // 않는다 — 칸이 뭉개지지 않는 것(서식 기능)이 목적이다.
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              lines.join('\n'),
              // 안드로이드는 'monospace'가 시스템 모노로 매핑되고, iOS는 그 이름이
              // 없어 폴백(Menlo)으로 떨어진다.
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.6,
                color: AppColors.ink,
                fontFamily: 'monospace',
                fontFamilyFallback: ['Menlo', 'Courier New'],
              ),
            ),
          ),
        );
      case ContractDivider():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(height: 1, color: AppColors.line),
        );
    }
  }

  Widget _heading(int level, List<ContractRun> runs) {
    final (style, padding) = switch (level) {
      1 => (
          const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, height: 1.4),
          const EdgeInsets.only(top: 2, bottom: 10),
        ),
      2 => (
          const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.4),
          const EdgeInsets.only(top: 6, bottom: 10),
        ),
      // 파서가 1~3만 내보낸다(h4+는 미지 문법 거부) — 조문 제목(###)이 여기다.
      _ => (
          const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.4),
          const EdgeInsets.only(top: 10, bottom: 8),
        ),
    };
    return Padding(padding: padding, child: Text.rich(_span(runs), style: style));
  }

  Widget _table(
    List<ContractCellAlign> aligns,
    List<ContractTableCell> headerCells,
    List<List<ContractTableCell>> rows,
  ) {
    // 서명란 표(`| | |`)처럼 헤더가 전부 비면 헤더 행을 그리지 않는다 — 모델은 원문
    // 그대로 보존하고(파서 주석), 빈 회색 띠를 만들지 않는 건 표시 선택이다.
    final showHeader = headerCells.any((c) => !c.isEmpty);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Table(
        border: TableBorder.all(color: AppColors.line, width: 1),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          if (showHeader)
            TableRow(
              decoration: const BoxDecoration(color: AppColors.surfaceMuted),
              children: [
                for (var c = 0; c < headerCells.length; c++)
                  _cell(headerCells[c], aligns[c], header: true),
              ],
            ),
          for (final row in rows)
            TableRow(
              children: [
                for (var c = 0; c < row.length; c++) _cell(row[c], aligns[c]),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(ContractTableCell cell, ContractCellAlign align, {bool header = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text.rich(
        _span(cell.runs),
        textAlign: align == ContractCellAlign.right ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.5,
          color: AppColors.ink,
          fontWeight: header ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }

  static const _body = TextStyle(fontSize: 12, color: AppColors.ink, height: 1.65);

  TextSpan _span(List<ContractRun> runs) => TextSpan(
        children: [
          for (final r in runs)
            TextSpan(
              text: r.text,
              style: r.bold ? const TextStyle(fontWeight: FontWeight.w800) : null,
            ),
        ],
      );
}
