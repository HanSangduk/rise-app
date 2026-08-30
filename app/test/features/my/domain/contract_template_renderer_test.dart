// 계약서 템플릿 렌더러(P39·P42·P47) — 변형 자산 2종의 내용 골든 + 결정성 + 거부 규약.
//
// 골든값의 출처는 추측이 아니라 **자산 원문과 P39·P42·P47 결정**이다:
//  · 블록 시그니처·개수 — assets/legal/contract_pt_v1_reported.md를 2026-08-30
//    grep 전수 스캔한 인벤토리(h1 1·h2 1·h3 25·표 6·펜스 2·수평선 3·인용 2·목록 17)와
//    파서 출력이 **독립 경로로 일치**함을 확인하고 고정했다. P39의 146블록 골든에서
//    제5조 조문 대체(:1275 — 부가상품 표·②항·작성 지시 인용 제거)로 3블록이,
//    P47의 발췌 흔적 헤딩(`# §A 계약서 본문`) 제거로 1블록이 줄었다 — h2였던 문서
//    제목이 h1로 올라와 h1 1·h2 1이 됐다(개수 총합은 그대로 헤딩 2).
//  · exempt 골든은 reported에서 **유도**한다(당사자 표 9행→8행 한 곳) — 두 변형이
//    "감사 지점 밖에서는 행 단위로 같다"는 P42 불변식 자체를 골든으로 삼는 것이다.
//    exempt가 다른 곳에서 구조적으로 갈라지면 이 유도 골든이 시끄럽게 깨진다.
//  · 거부 규약 — P39 결정 5(미지 문법 렌더 거부 — 모르는 것을 아는 척하지 않는다),
//    결정 3({{계약 체결일}}은 Vars 밖 — 엔티티 필드에서 렌더).
//  · 이미지 골든이 아니라 내용 골든인 이유 — 하우스에 이미지 골든 선례가 없고
//    (matchesGoldenFile 0건), §D가 고정하려는 것은 픽셀이 아니라 "무엇이 어떤 구조로
//    치환·표시되는가"다.
//
// 템플릿이 바뀌면(최종 동결 등) 이 골든은 **일부러 시끄럽게** 깨진다 — 그때 파서
// 인벤토리를 다시 재고 골든을 의식적으로 다시 고정하는 것이 P39가 정한 절차다.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/my/domain/contract_render_model.dart';
import 'package:rise_member/features/my/domain/contract_template_renderer.dart';

import '../../../support/contract_render_fixture.dart';

String plain(List<ContractRun> runs) => runs.map((r) => r.text).join();

String cellText(ContractTableCell c) => plain(c.runs);

/// 블록 시퀀스 시그니처 — 종류·형태만 접는다(헤딩은 짧아 본문까지).
/// 표는 `t{열}x{본문행}{정렬(l/r)…}`, 펜스는 `f{행수}`, 목록은 `li{원문 번호}`.
List<String> signature(ContractDocument doc) => [
      for (final b in doc.blocks)
        switch (b) {
          ContractHeading(:final level, :final runs) => 'h$level ${plain(runs)}',
          ContractParagraph() => 'p',
          ContractQuote() => 'q',
          ContractListItem(:final ordinal) => 'li$ordinal',
          ContractTable(:final aligns, :final rows) =>
            't${aligns.length}x${rows.length}'
                '${aligns.map((a) => a == ContractCellAlign.right ? 'r' : 'l').join()}',
          ContractCodeBlock(:final lines) => 'f${lines.length}',
          ContractDivider() => 'hr',
        },
    ];

/// 블록별 표시 텍스트 전부 — 잔재·잔존 문자열 감사용.
List<String> allTexts(ContractDocument d) {
  final texts = <String>[];
  for (final b in d.blocks) {
    switch (b) {
      case ContractHeading(:final runs):
        texts.add(plain(runs));
      case ContractParagraph(:final runs):
        texts.add(plain(runs));
      case ContractQuote(:final runs):
        texts.add(plain(runs));
      case ContractListItem(:final runs):
        texts.add(plain(runs));
      case ContractTable(:final headerCells, :final rows):
        texts.addAll(headerCells.map(cellText));
        for (final r in rows) {
          texts.addAll(r.map(cellText));
        }
      case ContractCodeBlock(:final lines):
        texts.addAll(lines);
      case ContractDivider():
        break;
    }
  }
  return texts;
}

/// pt-v1-reported 전문 골든 — 2026-08-29 재고정(P42). 원문 구조와 손으로 대조한 표식:
/// 표지 두 표(당사자 9행·계약내용 8행), 제5조는 조문 대체로 문단 하나(표·인용 없음),
/// 제11조 철회 3행 표, 제13조 산식 펜스 4행 + 산정 예시 두 표(마지막 열 우측 정렬 r),
/// 서명란 2행 표, [별지] 서식 펜스 24행. 총 142블록.
///
/// 첫 블록은 **문서 자신의 제목 h1**이다(P47) — 설계문서 절 라벨 `# §A 계약서 본문`이
/// 발췌 흔적으로 남아 회원이 여는 계약서 첫 줄에 인쇄되던 것을 걷어내고, h2였던 제목을
/// h1으로 올렸다.
const expectedReportedSignature = <String>[
  'h1 퍼스널 트레이닝(PT) 이용계약서',
  'p',
  'h3 계약 당사자',
  't2x9ll',
  'h3 계약 내용',
  't2x8ll',
  'hr',
  'h3 제1조 (계약의 목적)',
  'p',
  'h3 제2조 (계약의 성격과 적용 법령)',
  'p',
  'p',
  'p',
  'p',
  'h3 제3조 (계약의 내용)',
  'p',
  'p',
  'p',
  'p',
  'h3 제4조 (대금의 지급)',
  'p',
  'p',
  'p',
  'p',
  'p',
  'h3 제5조 (부가상품)',
  'p',
  'h3 제6조 (유효기간)',
  'p',
  'p',
  'p',
  'h3 제7조 (수업의 예약)',
  'p',
  'li1',
  'li2',
  'li3',
  'li4',
  'li5',
  'p',
  'p',
  'h3 제8조 (횟수의 차감 시점)',
  'p',
  'p',
  'li1',
  'li2',
  'p',
  'q',
  'p',
  'h3 제9조 (예약의 취소)',
  'p',
  'p',
  'p',
  'h3 제10조 (일시정지)',
  'p',
  'p',
  'p',
  'li1',
  'li2',
  'li3',
  'p',
  'p',
  'h3 제11조 (청약철회)',
  'p',
  't3x3lll',
  'p',
  'p',
  'p',
  'p',
  'h3 제12조 (회원의 중도해지)',
  'p',
  'p',
  'p',
  'p',
  'p',
  'h3 제13조 (해지에 따른 환급액의 산정)',
  'p',
  'f4',
  'p',
  'li1',
  'li2',
  'li3',
  'li4',
  'p',
  'p',
  'p',
  't3x4llr',
  'p',
  't3x5llr',
  'p',
  'h3 제14조 (센터의 사정에 의한 해지)',
  'p',
  'p',
  'p',
  'h3 제15조 (환급의 시기와 방법)',
  'p',
  'p',
  'p',
  'p',
  'h3 제16조 (센터의 계약 해지)',
  'p',
  'li1',
  'li2',
  'li3',
  'p',
  'p',
  'h3 제17조 (이용 내역의 열람)',
  'p',
  'p',
  'h3 제18조 (전자계약의 체결·보관)',
  'p',
  'p',
  'p',
  'p',
  'p',
  'h3 제19조 (개인정보의 처리)',
  'p',
  'p',
  'h3 제20조 (센터의 의무)',
  'p',
  'p',
  'p',
  'p',
  'p',
  'h3 제21조 (회원의 의무)',
  'p',
  'p',
  'p',
  'h3 제22조 (분쟁의 해결)',
  'p',
  'p',
  'p',
  'h3 제23조 (계약서의 교부와 약관)',
  'p',
  'p',
  'p',
  'hr',
  'p',
  't2x2ll',
  'hr',
  'h2 [별지] 계약 해지 · 청약철회 신청서',
  'q',
  'f24',
];

/// pt-v1-exempt 전문 골든 — reported에서 유도: 당사자 표 9행→8행(신고번호 행 제거)
/// **한 곳**. 체육시설법 인용 4곳 제거는 문단 안 텍스트 변화라 시그니처에 나타나지
/// 않는다 — 그래서 두 변형의 블록 수는 같은 142다(P42 감사 결과 그대로, P47 −1).
final expectedExemptSignature = <String>[
  for (final s in expectedReportedSignature) s == 't2x9ll' ? 't2x8ll' : s,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String reported;
  late String exempt;

  setUpAll(() async {
    // rootBundle로 읽는다 — 파서 입력 확보에 더해, pubspec assets/legal/ 등록이
    // **두 변형 자산 모두** 실제로 번들에 넣는지까지 함께 검증한다(P42).
    reported = await rootBundle.loadString('assets/legal/contract_pt_v1_reported.md');
    exempt = await rootBundle.loadString('assets/legal/contract_pt_v1_exempt.md');
  });

  ContractRenderOutcome render({
    String? t,
    Map<String, String>? vars,
    Map<String, String>? entityVars,
  }) =>
      ContractTemplateRenderer.render(
        template: t ?? reported,
        vars: vars ?? contractReportedVarsFixture,
        entityVars: entityVars ?? contractEntityVarsFixture,
      );

  ContractDocument doc({String? t, Map<String, String>? vars, Map<String, String>? entityVars}) {
    final o = render(t: t, vars: vars, entityVars: entityVars);
    if (o is ContractRenderRefused) fail('렌더 거부: ${o.reason}');
    return (o as ContractRenderReady).document;
  }

  ContractDocument docExempt() => doc(t: exempt, vars: contractExemptVarsFixture);

  group('전체 템플릿 — 내용 골든(pt-v1-reported)', () {
    test('전문(23개조+[별지])이 거부 없이 렌더되고 블록 시그니처가 골든과 일치한다', () {
      final d = doc();
      expect(signature(d), expectedReportedSignature);
      expect(d.blocks, hasLength(142)); // P39 146 − 제5조 대체 3 − P47 발췌 흔적 헤딩 1
      // 종류별 개수는 grep 전수 스캔 인벤토리와 독립적으로 대조한 값(파일 머리 주석).
      // h1/h2는 P47에서 의식적으로 다시 고정했다 — 제목 하나가 h1, [별지]가 h2다.
      expect(d.blocks.whereType<ContractHeading>().where((h) => h.level == 1).length, 1);
      expect(d.blocks.whereType<ContractHeading>().where((h) => h.level == 2).length, 1);
      expect(d.blocks.whereType<ContractHeading>().where((h) => h.level == 3).length, 25);
      expect(d.blocks.whereType<ContractTable>().length, 6);
      expect(d.blocks.whereType<ContractCodeBlock>().length, 2);
      expect(d.blocks.whereType<ContractQuote>().length, 2);
      expect(d.blocks.whereType<ContractListItem>().length, 17);
      expect(d.blocks.whereType<ContractDivider>().length, 3);
    });

    test('제5조 — :1275 지시대로 조문이 대체됐다(조 번호·표제 유지, 빈 표 없음)', () {
      final d = doc();
      final i = d.blocks.indexWhere(
          (b) => b is ContractHeading && plain(b.runs) == '제5조 (부가상품)');
      expect(i, greaterThan(0), reason: '조 번호가 밀리지 않도록 제5조 표제는 남아야 한다');
      final body = d.blocks[i + 1];
      expect(body, isA<ContractParagraph>());
      final text = plain((body as ContractParagraph).runs);
      expect(text, contains('부가상품을 제공하지 않으며'));
      expect(text, contains('해지 시 부가상품 명목의 공제도 하지 않습니다'));
      // 부가상품 도입은 새 템플릿 버전으로 — 버전 체계가 감당한다(P42 결정).
      expect(text, contains('별도 계약서 양식(새 버전)'));
      // 문단 하나로 끝 — 빈 표도, 작성 지시 인용도 없이 바로 다음 조다.
      expect(d.blocks[i + 2], isA<ContractHeading>());
      expect(plain((d.blocks[i + 2] as ContractHeading).runs), '제6조 (유효기간)');
    });

    test('치환 스팟체크 — 전문·표지 표·산식 원문 보존·[별지] 서식', () {
      final d = doc();

      // 전문 첫 문단 — "**{{사업자명}}**(이하 "센터")…" : 굵은 상호로 시작한다.
      // 인덱스는 제목 h1 바로 다음(P47에서 발췌 흔적 헤딩이 빠져 [2]→[1]).
      final intro = d.blocks[1] as ContractParagraph;
      expect(intro.runs.first.bold, isTrue);
      expect(intro.runs.first.text, '라이즈 컨디셔닝');
      expect(plain(intro.runs), contains('이하 "센터"'));

      // 산식 펜스(제13조)는 슬롯이 없으므로 원문 그대로 보존된다.
      final formula = d.blocks.whereType<ContractCodeBlock>().first;
      expect(formula.lines, hasLength(4));
      expect(formula.lines.first, '(1) 회당 단가   = 계약금액 ÷ 총 이용 횟수            (원 미만 절사)');

      // [별지] 서식 펜스 — "받는 사람" 칸이 실제 상호·연락처로 치환된다(방판법 §30①6
      // 가 요구하는 건 작동하는 서식이다). 괘선·칸 배치는 원문 그대로.
      final annex = d.blocks.whereType<ContractCodeBlock>().last;
      expect(annex.lines, hasLength(24));
      expect(
        annex.lines,
        contains('  받는 사람   라이즈 컨디셔닝  (   hello@rise.example  /  02-1234-5678  )'),
      );
      expect(annex.lines, contains('                    계약 해지 · 청약철회 신청서'));
    });

    test('렌더된 텍스트 어디에도 {{·}}·** 잔재가 없다 — 치환·굵게가 전부 소화됐다', () {
      for (final t in allTexts(doc())) {
        expect(t, isNot(contains('{{')));
        expect(t, isNot(contains('}}')));
        expect(t, isNot(contains('**')));
      }
    });

    test('헤더 주석 2행은 블록도 슬롯도 만들지 않는다', () {
      // 자산 머리 주석 2행 — P47에서 문구를 현행화하면서("가버전" → "발행 중 ·
      // 실서명 0건 창") 카나리도 새 문구에 다시 걸었다. 리터럴 {{계약 체결일}}은
      // 원본 행에 그대로 남아, 주석 안 슬롯을 슬롯으로 세지 않는다는 규약을 **실자산**
      // 경로에서 계속 검증한다(P47에서 지운 발췌 안내 주석이 들고 있던 몫).
      // 전문 렌더 성공 자체가 "슬롯으로 안 셌다"의 증거고, 여기서는 주석 문구가
      // 표시 텍스트로 새지 않음을 못박는다.
      for (final t in allTexts(doc())) {
        expect(t, isNot(contains('발행 래치'))); // 주석 1행에만 있는 말
        expect(t, isNot(contains('pt-v1-'))); // 버전 id도 주석에만 있다
        expect(t, isNot(contains('P47 델타')));
      }
    });

    test('서명란 표 — 빈 헤더(| | |)가 모델에 그대로 보존된다', () {
      final sign = doc().blocks.whereType<ContractTable>().last;
      expect(sign.headerCells, hasLength(2));
      expect(sign.headerCells.every((c) => c.isEmpty), isTrue);
      expect(cellText(sign.rows[0][0]), '센터');
      expect(cellText(sign.rows[0][1]), '라이즈 컨디셔닝 대표 김대표 (인)');
      expect(cellText(sign.rows[1][0]), '회원');
      expect(cellText(sign.rows[1][1]), '홍길동 (서명)');
    });
  });

  group('전체 템플릿 — 내용 골든(pt-v1-exempt)', () {
    test('전문이 거부 없이 렌더되고 시그니처가 유도 골든과 일치한다 — 구조 차이는 당사자 표뿐', () {
      final d = docExempt();
      expect(signature(d), expectedExemptSignature);
      expect(d.blocks, hasLength(142)); // 행 제거·인용 제거는 블록 수를 바꾸지 않는다
      expect(d.blocks.whereType<ContractHeading>().where((h) => h.level == 1).length, 1);
      expect(d.blocks.whereType<ContractHeading>().where((h) => h.level == 2).length, 1);
      expect(d.blocks.whereType<ContractHeading>().where((h) => h.level == 3).length, 25);
      expect(d.blocks.whereType<ContractTable>().length, 6);
      expect(d.blocks.whereType<ContractCodeBlock>().length, 2);
      expect(d.blocks.whereType<ContractQuote>().length, 2);
      expect(d.blocks.whereType<ContractListItem>().length, 17);
      expect(d.blocks.whereType<ContractDivider>().length, 3);
    });

    test('당사자 표 — 신고번호 행 없이 8행, 라벨 어디에도 체육시설업이 없다(:818 갈래)', () {
      final t = docExempt().blocks[3] as ContractTable; // P47에서 [4]→[3]
      expect(t.rows, hasLength(8));
      expect(t.rows.map((r) => cellText(r[0])), [
        '상호',
        '대표자',
        '사업자등록번호',
        '사업장 주소',
        '연락처',
        '회원 성명',
        '회원 연락처',
        '담당 코치',
      ]);
    });

    test('렌더 전문 어디에도 체육시설법 흔적이 없다 — 신고 업자만 구속하는 근거 인용 금지', () {
      // 신고 대상이 아닌 시설이 체육시설법을 자기 의무의 근거로 내걸면, 스스로
      // 신고 체육시설업자라고 주장하는 문서가 된다(P42 감사 원칙).
      for (final t in allTexts(docExempt())) {
        expect(t, isNot(contains('체육시설')));
        expect(t, isNot(contains('[별표 3의2]')));
        expect(t, isNot(contains('제21조의3')));
      }
    });

    test('인용은 뺐지만 의무·약속 문장은 그대로다 — 회원에게 주던 것을 줄이는 변형이 아니다', () {
      final texts = allTexts(docExempt()).join('\n');
      // 제20조 ④ — 인용 괄호만 사라지고 의무 문장은 남는다.
      expect(texts, contains('④ 센터는 이 계약을 포함하여 회원과 약정한 사항을 지킵니다.'));
      // 제14조 ② — 센터 귀책 시 미이용분 + 위약금 가산 반환 약속 유지.
      expect(texts, contains('이용하지 않은 부분에 해당하는 금액에 위약금(계약금액의 10분의 1)을 더하여'));
      // 제15조 ② — 연 15% 지연이자 약속 유지(방판법·전상법 상향 경로도 그대로).
      expect(texts, contains('연 100분의 15 이상'));
      expect(texts, contains('더 높은 이율이 적용되는 경우에는 그 이율'));
      // 제13조 ⑥ — 법령·기준 우선 적용 약속 유지(소비자분쟁해결기준 일반 인용으로).
      expect(texts, contains('소비자분쟁해결기준 등 관계 법령·기준이 정한 것보다'));
    });

    test('렌더된 텍스트 어디에도 {{·}}·** 잔재가 없다', () {
      for (final t in allTexts(docExempt())) {
        expect(t, isNot(contains('{{')));
        expect(t, isNot(contains('}}')));
        expect(t, isNot(contains('**')));
      }
    });
  });

  test('첫 블록은 계약서 제목 h1이고 두 변형 어디에도 "§A"가 없다 — 발췌 흔적 회귀 가드(P47)', () {
    // 두 자산은 설계문서(docs/계약서_PT이용계약_v1.md) §A 절에서 바이트 그대로 떼어
    // 왔고, 그 흔적으로 문서 첫 헤딩이 `# §A 계약서 본문`이었다 — **설계문서의 절
    // 라벨**이 회원이 여는 계약서의 첫 줄로 인쇄되던 결함이다(회원에게는 뜻이 없는
    // 말이고, 진짜 제목은 그 다음 줄에 h2로 밀려 있었다). 다시 들어오는 것을 막는다.
    for (final d in [doc(), docExempt()]) {
      final first = d.blocks.first;
      expect(first, isA<ContractHeading>(), reason: '문서는 제목으로 시작해야 한다');
      expect((first as ContractHeading).level, 1);
      expect(plain(first.runs), '퍼스널 트레이닝(PT) 이용계약서');
      for (final t in allTexts(d)) {
        expect(t, isNot(contains('§A')),
            reason: '설계문서 절 기호가 회원이 보는 문서에 남으면 안 된다');
      }
    }
  });

  group('변형 자산 감사(P42) — 원문 텍스트 규약', () {
    // 헤더 주석은 델타를 설명하느라 "체육시설업"을 말할 수 있다 — 파서가 스킵하고
    // 회원에게 보이지 않으므로, 감사는 주석을 뺀 본문 행에만 건다.
    String body(String raw) =>
        raw.split('\n').where((l) => !l.startsWith('<!--')).join('\n');

    test('reported — 당사자 표에 신고번호 행이 원문 그대로 있다', () {
      expect(
        body(reported),
        contains('| 체육시설업 신고번호 | {{체육시설업 신고번호}} |'),
      );
    });

    test('exempt — 본문에 체육시설(법·업) 문자열이 0곳, 빈 괄호 잔재도 없다', () {
      final b = body(exempt);
      expect(b, isNot(contains('체육시설')));
      expect(b, isNot(contains('[별표 3의2]')));
      expect(b, isNot(contains('제21조의3')));
      // 인용 괄호를 뜯어낸 자리에 빈 괄호·빈 낫표가 남으면 편집 잔재다.
      expect(RegExp(r'\(\s*\)').hasMatch(b), isFalse);
      expect(b, isNot(contains('「」')));
    });

    test('제18조 ② — 기록 항목에 서명 이미지가 들어갔고 두 변형이 같은 문장이다(P44 결정 8)', () {
      // 가버전 창(래치 OFF — 스탬프 이력 0)이라 버전 범프 없이 문구만 갱신했다.
      // 서명 이미지를 기록하면서 계약서의 기록 조항이 침묵하면, 문서가 자기 실무를
      // 다 말하지 않는 문서가 된다. "(자필 서명을 전자적으로 입력한 경우)" 한정이
      // 구버전 앱의 체크 동의 서명(이미지 없음, 결정 6)까지 참으로 만든다.
      const clause = '② 센터는 회원이 서명한 시각, 서명 당시의 IP 주소 및 서명 이미지(자필 서명을 '
          '전자적으로 입력한 경우)를 기록합니다.';
      expect(body(reported), contains(clause));
      expect(body(exempt), contains(clause), reason: '이 문장은 두 변형의 바이트 동일 구간이다(P42 불변식)');
      // 옛 문구 잔재 0 — 갱신이 반쪽으로 남지 않았다.
      expect(body(reported), isNot(contains('시각과 서명 당시의 IP 주소를 기록합니다')));
      expect(body(exempt), isNot(contains('시각과 서명 당시의 IP 주소를 기록합니다')));
    });

    test('두 변형 모두 — 부가상품 슬롯이 어디에도 없다(:1275 조문 대체 완결)', () {
      expect(reported, isNot(contains('{{부가상품')));
      expect(exempt, isNot(contains('{{부가상품')));
      // 작성 지시 인용("빈 표를 남기지 않는다")도 이행 후 제거됐다.
      expect(body(reported), isNot(contains('빈 표를 남기지')));
      expect(body(exempt), isNot(contains('빈 표를 남기지')));
    });

    test('슬롯 인벤토리 — reported 26종(빈 입력의 누락 목록이 곧 전수 인벤토리다)', () {
      // 렌더러의 누락 수집이 첫 등장 순서 전수 목록을 내므로, grep 수작업 대신
      // 렌더러 자신에게 세게 한다 — 주석 안 리터럴은 자연히 제외된다.
      final o = render(t: reported, vars: const {}, entityVars: const {});
      expect(o, isA<ContractRenderMissingVars>());
      expect((o as ContractRenderMissingVars).missingKeys, const [
        '사업자명',
        '대표자명',
        '사업자등록번호',
        '사업장 주소',
        '대표 전화',
        '대표 이메일',
        '체육시설업 신고번호',
        '회원명',
        '회원 전화번호',
        '담당 트레이너명',
        '상품명',
        '총 회차',
        '계약금액',
        '유효기간 시작일',
        '유효기간 종료일',
        '결제방법',
        '납부일정',
        '위약금율',
        '계약 체결일',
        '슬롯 정원',
        '노쇼 유예 적용 여부',
        '취소 마감 시간',
        '홀딩 최대 횟수',
        '홀딩 최대 일수',
        '보증보험 종류·보장내용',
        '약관 게시 주소',
      ]);
    });

    test('슬롯 인벤토리 — exempt 25종 = reported − 신고번호, 다른 차이 없음', () {
      final o = render(t: exempt, vars: const {}, entityVars: const {});
      expect(o, isA<ContractRenderMissingVars>());
      final keys = (o as ContractRenderMissingVars).missingKeys;
      expect(keys, hasLength(25));
      expect(keys, isNot(contains('체육시설업 신고번호')));

      final r = render(t: reported, vars: const {}, entityVars: const {})
          as ContractRenderMissingVars;
      expect(
        r.missingKeys.where((k) => k != '체육시설업 신고번호').toList(),
        keys,
        reason: '두 변형의 슬롯 집합 차이는 신고번호 하나여야 한다(P42 결정)',
      );
    });

    test('픽스처 키 집합이 변형별 슬롯 인벤토리와 정확히 맞물린다', () {
      // Vars 픽스처(25/24종) + 엔티티({{계약 체결일}}) = 인벤토리(26/25종).
      expect(contractReportedVarsFixture, hasLength(25));
      expect(contractExemptVarsFixture, hasLength(24));
      expect(
        contractReportedVarsFixture.keys.toSet()
            .difference(contractExemptVarsFixture.keys.toSet()),
        {'체육시설업 신고번호'},
      );
      // 전체 렌더 성공(위 골든 테스트)이 "모자라지 않음"을, 여기가 "남지 않음"을 본다.
      final inv = (render(t: reported, vars: const {}, entityVars: const {})
              as ContractRenderMissingVars)
          .missingKeys
          .toSet();
      expect(
        contractReportedVarsFixture.keys.toSet().difference(inv),
        isEmpty,
        reason: '픽스처에 템플릿이 안 쓰는 죽은 키가 있으면 안 된다',
      );
    });
  });

  group('결정성 — 같은 입력은 언제나 같은 모델(§D "언제나 같은 결과")', () {
    test('두 번 렌더한 문서가 깊은 동등(==)이다 — 두 변형 모두', () {
      for (final (t, vars) in [
        (reported, contractReportedVarsFixture),
        (exempt, contractExemptVarsFixture),
      ]) {
        final d1 = doc(t: t, vars: vars);
        final d2 = doc(t: t, vars: vars);
        expect(identical(d1, d2), isFalse);
        expect(d1, equals(d2));
        expect(d1.hashCode, d2.hashCode);
        expect(signature(d1), signature(d2));
      }
    });
  });

  group('슬롯 값 누락 — 전부 모아 한 번에 거부(호출자는 요약 경로 폴백)', () {
    test('빠진 키를 첫 등장 순서로 전부 나열한다 — 첫 키만 알리면 왕복이 늘어난다', () {
      final vars = Map.of(contractReportedVarsFixture)
        ..remove('회원명')
        ..remove('납부일정');
      final o = render(vars: vars);
      expect(o, isA<ContractRenderMissingVars>());
      // 당사자 표(회원 성명)가 계약내용 표(납부 일정)보다 먼저다.
      expect((o as ContractRenderMissingVars).missingKeys, ['회원명', '납부일정']);
    });

    test('entityVars가 비면 {{계약 체결일}}만 누락으로 잡힌다', () {
      final o = render(entityVars: const {});
      expect(o, isA<ContractRenderMissingVars>());
      expect((o as ContractRenderMissingVars).missingKeys, ['계약 체결일']);
    });

    test('실패 시 부분 치환된 모델은 존재하지 않는다 — 실패 갈래에 document가 없다', () {
      final vars = Map.of(contractReportedVarsFixture)..remove('위약금율');
      final o = render(vars: vars);
      // 타입 증명: ContractRenderReady가 아니면 document 접근 경로 자체가 없다.
      // 절반 치환된 문서가 새어 나가는 상태는 표현조차 불가능하다.
      expect(o, isNot(isA<ContractRenderReady>()));
      expect(o, isA<ContractRenderMissingVars>());
    });
  });

  group('슬롯 원천 두 갈래 — P39 결정 3', () {
    test('{{계약 체결일}}은 vars 없이 entityVars만으로 렌더된다', () {
      final d = doc(
        t: '체결일: {{계약 체결일}}',
        vars: const {},
        entityVars: const {'계약 체결일': '2026-08-29'},
      );
      expect(plain((d.blocks.single as ContractParagraph).runs), '체결일: 2026-08-29');
    });

    test('같은 키가 양쪽에 있으면 우선순위 대신 거부한다 — 우선순위는 조용한 덮어쓰기다', () {
      final o = render(vars: {...contractReportedVarsFixture, '계약 체결일': '2020-01-01'});
      expect(o, isA<ContractRenderSlotSourceConflict>());
      expect((o as ContractRenderSlotSourceConflict).keys, ['계약 체결일']);
    });
  });

  group('미지 문법 — 렌더 거부(모르는 것을 아는 척하지 않는다, P39 결정 5)', () {
    ContractRenderUnknownSyntax refuse(String t) {
      final o = render(t: t, vars: const {}, entityVars: const {});
      expect(o, isA<ContractRenderUnknownSyntax>(), reason: '거부돼야 할 템플릿: $t');
      return o as ContractRenderUnknownSyntax;
    }

    test('비순서 목록(`- `) — §A는 순서 목록만 쓴다', () {
      expect(refuse('- 항목').what, contains('비순서'));
    });

    test('h4+ 헤딩', () {
      expect(refuse('#### 깊은 헤딩').what, contains('h4+'));
    });

    test('인라인 코드(백틱)', () {
      expect(refuse('이 안에 `코드` 사용').what, contains('백틱'));
    });

    test('링크 문법 — [별표 3의2] 같은 평문 대괄호는 전문 렌더에서 이미 통과했다', () {
      expect(refuse('[이름](https://x) 링크').what, contains('링크'));
    });

    test('홑별표 강조', () {
      expect(refuse('*기울임* 강조').what, contains('홑별표'));
    });

    test('짝이 맞지 않는 굵게(`**`)', () {
      expect(refuse('굵게 ** 열림만').what, contains('**'));
    });

    test('밑줄 강조', () {
      expect(refuse('_밑줄_ 강조').what, contains('_'));
    });

    test('닫히지 않은 코드펜스 — 여는 행 번호로 보고한다', () {
      final r = refuse('```\n닫히지 않음');
      expect(r.what, contains('닫히지 않은'));
      expect(r.lineNumber, 1);
    });

    test('표 열 수 불일치', () {
      expect(refuse('| a | b |\n|---|---|\n| 1 |').what, contains('열 수'));
    });

    test('문단에 빈 줄 없이 붙은 `---`(세텍스트 헤딩 가능성)', () {
      expect(refuse('문단 텍스트\n---').what, contains('붙은'));
    });

    test('HTML 태그', () {
      expect(refuse('<div>태그</div>').what, contains('HTML'));
    });

    test('슬롯 밖 홑중괄호', () {
      expect(refuse('여는 {{만 있음').what, contains('중괄호'));
    });

    test('행 번호는 템플릿 문자열 기준 1-시작이다', () {
      final r = refuse('첫 문단\n\n- 항목');
      expect(r.lineNumber, 3);
      expect(r.lineText, '- 항목');
    });

    test('주석 안 {{...}}는 슬롯이 아니다 — 원문 :36의 리터럴 예시 보호', () {
      final d = doc(t: '<!-- {{미지키}} -->\n\n본문', vars: const {}, entityVars: const {});
      expect(plain((d.blocks.single as ContractParagraph).runs), '본문');
    });
  });

  group('표 파싱 — 당사자·계약내용 표(방판법 §30① 기재사항이 실리는 자리)', () {
    test('계약 당사자 표(reported) — 9행 라벨·값이 원문 순서대로 치환된다', () {
      final t = doc().blocks[3] as ContractTable; // P47에서 [4]→[3]
      expect(t.headerCells.map(cellText), ['구분', '내용']);
      expect(t.aligns, [ContractCellAlign.left, ContractCellAlign.left]);
      expect(t.rows.map((r) => cellText(r[0])), [
        '상호',
        '대표자',
        '사업자등록번호',
        '사업장 주소',
        '연락처',
        '체육시설업 신고번호',
        '회원 성명',
        '회원 연락처',
        '담당 코치',
      ]);
      expect(cellText(t.rows[0][1]), '라이즈 컨디셔닝');
      expect(cellText(t.rows[4][1]), '02-1234-5678 · hello@rise.example');
      expect(cellText(t.rows[5][1]), '제2026-서울강남-0001호');
      expect(cellText(t.rows[8][1]), '박코치');
    });

    test('계약 내용 표 — 8행, 치환값이 접미사와 한 셀로 결합된다(20회·10%·기간)', () {
      final t = doc().blocks[5] as ContractTable; // P47에서 [6]→[5]
      expect(t.rows, hasLength(8));
      expect(cellText(t.rows[0][1]), 'PT 20회');
      expect(cellText(t.rows[1][1]), '20회');
      expect(cellText(t.rows[2][1]), '1,000,000원');
      expect(cellText(t.rows[3][1]), '2026-09-01 ~ 2026-12-31');
      expect(cellText(t.rows[6][1]), '10%');
      // {{계약 체결일}} — entityVars에서 온 값이 표에 실린다(P39 결정 3).
      expect(cellText(t.rows[7][1]), '2026-08-29');
    });

    test('납부 일정 셀 — "\\n" 결합 직렬화(P39 결정 4)가 값 그대로 살아남는다', () {
      final t = doc().blocks[5] as ContractTable; // P47에서 [6]→[5]
      final schedule = cellText(t.rows[5][1]);
      expect(schedule, contains('\n'));
      expect(schedule, contains('1회차 500,000원 (2026-09-01 납부완료)'));
      expect(schedule, contains('2회차 500,000원 (2026-10-01 납부예정)'));
    });

    test('산정 예시 표 — 금액 열 우측 정렬(---:)과 굵은 셀(**환급액**)이 보존된다', () {
      final tables = doc().blocks.whereType<ContractTable>().toList();
      final example = tables[3]; // 제13조 ④ 산정 예시(부가상품 표 제거로 P39의 [4]→[3])
      expect(example.aligns,
          [ContractCellAlign.left, ContractCellAlign.left, ContractCellAlign.right]);
      final refundRow = example.rows[3];
      expect(cellText(refundRow[0]), '환급액');
      expect(refundRow[0].runs.single.bold, isTrue);
      expect(cellText(refundRow[2]), '550,000원');
      expect(refundRow[2].runs.single.bold, isTrue);
    });
  });

  group('소프트랩 결합 — 원문이 실제로 쓰는 배치', () {
    test('행을 넘는 굵게가 한 굵은 런으로 이어진다(제6조 ③ 배치)', () {
      final d = doc(t: '앞 **굵게\n이어짐** 뒤', vars: const {}, entityVars: const {});
      final runs = (d.blocks.single as ContractParagraph).runs;
      expect(runs.map((r) => r.text), ['앞 ', '굵게 이어짐', ' 뒤']);
      expect(runs.map((r) => r.bold), [false, true, false]);
    });

    test('목록 연속 행(들여쓰기)이 항목 본문으로 결합된다(제13조 ② 배치)', () {
      final d = doc(t: '1. 첫 **줄\n   이어짐** 끝', vars: const {}, entityVars: const {});
      final li = d.blocks.single as ContractListItem;
      expect(li.ordinal, 1);
      expect(plain(li.runs), '첫 줄 이어짐 끝');
      expect(li.runs[1], const ContractRun('줄 이어짐', bold: true));
    });

    test('여러 행 인용이 한 문단으로 결합된다', () {
      final d = doc(t: '> 한 줄\n> 두 줄', vars: const {}, entityVars: const {});
      expect(plain((d.blocks.single as ContractQuote).runs), '한 줄 두 줄');
    });
  });
}
