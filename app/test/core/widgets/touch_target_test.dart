import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/features/booking/presentation/widgets/date_strip.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/widgets/homework_checklist_card.dart';

/// 탭 타깃 회귀 — 시각 크기는 그대로 두고 히트 영역만 44dp로 키운 자리들.
///
/// 위젯 테스트는 기본적으로 글리프 폭/높이가 실제와 다른 테스트 폰트를 쓴다.
/// 칩·행의 높이는 텍스트 줄높이에 직접 좌우되므로 **번들된 Pretendard를 실제로
/// 로드**해서 잰다 — 그러지 않으면 기기에서만 글자가 알약 밖으로 삐져나온다.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Pretendard')
      ..addFont(
        File('assets/fonts/PretendardVariable.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
    await loader.load();
  });

  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(fontFamily: 'Pretendard'),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('RiseChip — 히트 44dp, 알약 자체는 자연 크기 그대로', (tester) async {
    await tester.pumpWidget(host(RiseChip(label: '금 14', onTap: () {})));

    final hit = tester.getSize(find.byType(InkWell));
    final pill = tester.getSize(
      find.descendant(of: find.byType(RiseChip), matching: find.byType(Container)),
    );
    // 알약(배경·보더를 칠하는 Container)은 목업 `.chip` 그대로 — 패딩은 투명하다.
    expect(pill.height, lessThan(hit.height), reason: '패딩이 배경까지 키우면 안 된다');
    expect(hit.height, greaterThanOrEqualTo(44));
  });

  testWidgets('DateStrip — 예약 주 내비게이션의 날짜 칩이 44dp이고 알약이 눌리지 않는다',
      (tester) async {
    // 기준: 제약 없는 곳(Wrap 등)에서의 알약 높이.
    await tester.pumpWidget(host(RiseChip(label: '금 14', onTap: () {})));
    final natural = tester
        .getSize(
          find.descendant(of: find.byType(RiseChip), matching: find.byType(Container)),
        )
        .height;

    await tester.pumpWidget(
      host(DateStrip(selected: DateTime.now(), onSelect: (_) {})),
    );

    final chip = find.byType(RiseChip).first;
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));

    // 가로 ListView는 cross축 tight 제약을 준다 — 스트립 높이가 모자라면 알약이
    // 세로로 눌리고 글자가 알약 밖으로 새어 나온다.
    final pill = tester.getSize(
      find.descendant(of: chip, matching: find.byType(Container)),
    );
    expect(
      pill.height,
      greaterThanOrEqualTo(natural),
      reason: 'DateStrip 높이가 칩 자연 높이 + 히트 패딩(상하 9)을 담지 못한다 '
          '— 알약 ${pill.height} < 자연 $natural',
    );
  });

  testWidgets('Home Work 체크리스트 — 44dp 히트는 유지하되 라벨 들여쓰기는 다른 카드와 같다',
      (tester) async {
    await tester.pumpWidget(
      host(
        HomeworkChecklistCard(
          items: const [
            HomeworkItem(hwId: 'h1', index: 0, name: '플랭크 3세트', done: false),
          ],
          done: 0,
          total: 1,
          onToggle: (_) {},
        ),
      ),
    );

    // Checkbox의 padded 기본 탭 타깃(48×48)이 이 카드만 라벨을 48까지 밀어냈다.
    // shrinkWrap + compact로 체크박스는 32가 되고, 44dp는 행 전체(InkWell)가 낸다.
    final box = tester.getSize(find.byType(Checkbox));
    expect(box.width, lessThanOrEqualTo(32));

    final row = tester.getSize(find.byType(InkWell));
    expect(row.height, greaterThanOrEqualTo(44), reason: '행 전체가 44dp 타깃이어야 한다');

    // 라벨 왼쪽 시작점 = 체크박스 폭 + 명시한 SizedBox(8). 48 들여쓰기 회귀 방지.
    final cardLeft = tester.getTopLeft(find.byType(InkWell)).dx;
    final labelLeft = tester.getTopLeft(find.text('플랭크 3세트')).dx;
    expect(labelLeft - cardLeft, lessThanOrEqualTo(41));
  });

  testWidgets('RiseRow.minHeight — 탭 행은 44dp, 정적 행은 목업 그대로', (tester) async {
    await tester.pumpWidget(
      host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RiseRow(child: Text('정적 행')),
            RiseRow(minHeight: 44, showDivider: false, child: Text('탭 행')),
          ],
        ),
      ),
    );

    final rows = tester.widgetList<Container>(
      find.descendant(of: find.byType(RiseRow), matching: find.byType(Container)),
    );
    expect(rows.length, 2);

    final staticRow = tester.getSize(find.byType(RiseRow).at(0));
    final tapRow = tester.getSize(find.byType(RiseRow).at(1));
    expect(tapRow.height, greaterThanOrEqualTo(44));
    expect(staticRow.height, lessThan(44), reason: '정적 행까지 키우면 카드가 늘어진다');
  });
}
