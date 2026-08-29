import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/widgets/pass_switcher_chips.dart';

// 계약 v2.0 — 홈 패스 스위처 칩의 퇴사 표기.
//
// 칩은 "패스마다 담당 코치가 다를 때 어느 쪽이 퇴사했는지" 가려주는 유일한 자리다
// (헤더는 선택된 패스 하나만 말한다). 그래서 홈 탭에서 표기를 다는 두 앵커 중 하나.
// 이름 미해석 시 "$null 코치"가 아니라 "담당 코치"로 떨어지는 것도 함께 고정한다.
void main() {
  PassOption pass({
    required String id,
    String? trainerName,
    bool trainerInactive = false,
    String status = 'active',
  }) {
    return PassOption(
      id: id,
      product: 'PT 20회',
      trainerId: 't-$id',
      trainerName: trainerName,
      trainerInactive: trainerInactive,
      status: status,
      remaining: 8,
      totalSessions: 20,
      validFrom: DateTime(2026, 1, 1),
      validUntil: DateTime(2026, 12, 31),
    );
  }

  Future<void> pumpChips(WidgetTester tester, List<PassOption> passes) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PassSwitcherChips(
            passes: passes,
            selectedId: passes.first.id,
            onSelect: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('현직 코치 — 기존 라벨 그대로(표기가 새로 끼어들지 않는다)', (tester) async {
    await pumpChips(tester, [pass(id: 'p1', trainerName: '정혜린')]);

    expect(find.text('정혜린 코치 · PT 20회 (활성)'), findsOneWidget);
  });

  testWidgets('퇴사 코치 — 이름은 유지하고 이름 뒤에 "(퇴사)"', (tester) async {
    // 표기는 코치 이름 바로 뒤에 붙는다 — 패스 상태 "(만료)"가 아니라
    // 코치를 설명하는 표기임이 위치로 드러나야 한다.
    await pumpChips(tester, [
      pass(id: 'p1', trainerName: '정혜린', trainerInactive: true, status: 'expired'),
    ]);

    expect(find.text('정혜린 코치 (퇴사) · PT 20회 (만료)'), findsOneWidget);
  });

  testWidgets('패스가 여럿이면 퇴사한 쪽 칩에만 표기된다', (tester) async {
    await pumpChips(tester, [
      pass(id: 'p1', trainerName: '김태오'),
      pass(id: 'p2', trainerName: '정혜린', trainerInactive: true, status: 'expired'),
    ]);

    expect(find.text('김태오 코치 · PT 20회 (활성)'), findsOneWidget);
    expect(find.text('정혜린 코치 (퇴사) · PT 20회 (만료)'), findsOneWidget);
  });

  // 종료 상태 표기 — 예전엔 scheduled/active만 괄호를 달고 expired·refunded는
  // **아무 표시가 없었다**. 환불된 패스 하나만 남은 회원의 홈이 그 패스를 골라
  // (home_repository_impl `_defaultPass`가 active 없으면 passes.first) 잔여 링·코치·
  // 다음 예약을 정상처럼 그렸고, 칩이 그걸 부정할 유일한 자리였는데 침묵했다.
  group('종료 상태도 반드시 괄호를 단다', () {
    testWidgets('expired → "(만료)"', (tester) async {
      await pumpChips(tester, [pass(id: 'p1', trainerName: '정혜린', status: 'expired')]);

      expect(find.text('정혜린 코치 · PT 20회 (만료)'), findsOneWidget);
    });

    testWidgets('refunded → "(환불)"', (tester) async {
      await pumpChips(tester, [pass(id: 'p1', trainerName: '정혜린', status: 'refunded')]);

      expect(find.text('정혜린 코치 · PT 20회 (환불)'), findsOneWidget);
    });

    testWidgets('종료 상태 칩이 "활성"처럼 보이지 않는다', (tester) async {
      await pumpChips(tester, [
        pass(id: 'p1', trainerName: '김태오', status: 'refunded'),
        pass(id: 'p2', trainerName: '정혜린', status: 'expired'),
      ]);

      expect(find.textContaining('(활성)'), findsNothing);
    });

    testWidgets('scheduled/active 표기는 그대로', (tester) async {
      await pumpChips(tester, [
        pass(id: 'p1', trainerName: '김태오'),
        pass(id: 'p2', trainerName: '정혜린', status: 'scheduled'),
      ]);

      expect(find.text('김태오 코치 · PT 20회 (활성)'), findsOneWidget);
      expect(find.text('정혜린 코치 · PT 20회 (1/1~)'), findsOneWidget);
    });

    testWidgets('모르는 status는 지어내지 않고 원문 그대로', (tester) async {
      // ContractItem.statusLabel의 `_ => status`와 같은 규약 — 새 상태가 추가돼도
      // 아홉 중 하나로 접혀 "활성"처럼 읽히지 않는다.
      await pumpChips(tester, [pass(id: 'p1', trainerName: '정혜린', status: 'suspended')]);

      expect(find.text('정혜린 코치 · PT 20회 (suspended)'), findsOneWidget);
    });

    testWidgets('status가 빈 문자열이면 빈 괄호를 달지 않는다', (tester) async {
      await pumpChips(tester, [pass(id: 'p1', trainerName: '정혜린', status: '')]);

      expect(find.text('정혜린 코치 · PT 20회'), findsOneWidget);
    });
  });

  testWidgets('이름 미해석 — "null 코치"가 아니라 "담당 코치"', (tester) async {
    await pumpChips(tester, [pass(id: 'p1')]);

    expect(find.text('담당 코치 · PT 20회 (활성)'), findsOneWidget);
  });

  testWidgets('이름이 빈 문자열이어도 미배정과 같게 떨어진다', (tester) async {
    // 예전 `?? '담당'`은 ""를 통과시켜 " 코치 · PT 20회"(앞이 빈 자리)가 됐다.
    await pumpChips(tester, [pass(id: 'p1', trainerName: '')]);

    expect(find.text('담당 코치 · PT 20회 (활성)'), findsOneWidget);
  });
}
