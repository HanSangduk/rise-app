import 'package:flutter/material.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/features/home/domain/home_models.dart';

/// 목업 홈 상단 칩 — "정혜린 코치 · PT 20회 (활성)" / "김태오 코치 · 그룹 10회 (9/1~)".
/// 회원권마다 담당 코치가 다르므로, 여길 탭하면 예약/Home Work가 그 코치 기준으로 전환.
class PassSwitcherChips extends StatelessWidget {
  const PassSwitcherChips({
    super.key,
    required this.passes,
    required this.selectedId,
    required this.onSelect,
  });

  final List<PassOption> passes;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: [
        for (final p in passes)
          RiseChip(
            label: _label(p),
            selected: p.id == selectedId,
            onTap: () => onSelect(p.id),
          ),
      ],
    );
  }

  /// 홈 탭의 **퇴사 표기 앵커** 두 곳 중 하나(다른 하나는 헤더의 "담당 X 코치").
  /// 칩은 패스마다 담당 코치가 다를 때 어느 쪽이 퇴사했는지 가려주는 유일한 자리라
  /// — 헤더는 선택된 패스 하나만 말한다 — 여기엔 붙여야 한다.
  /// 상태 괄호("(활성)")보다 앞, 이름 바로 뒤에 붙여 누구 이야기인지 붙여 읽히게 한다.
  String _label(PassOption p) {
    final coach = CoachLabel.resolve(p.trainerName);
    // 상품명이 비면 "정혜린 코치 ·  (활성)"처럼 구분자가 매달린다 — 빈 조각은 버린다.
    final base = CoachLabel.joinDot([
      CoachLabel.tag('$coach 코치', inactive: p.trainerInactive),
      p.product,
    ]);
    // status가 빈 문자열로 오면 "(  )"만 남는다 — 빈 괄호는 달지 않는다.
    final suffix = _statusSuffix(p);
    return suffix.isEmpty ? base : '$base ($suffix)';
  }

  /// 상태 괄호 — **모든 상태가 무언가를 말한다.**
  ///
  /// 예전엔 scheduled/active만 괄호를 달고 expired·refunded는 아무 표시가 없어,
  /// 환불된 패스 하나만 남은 회원의 홈이 그 패스를 정상처럼(잔여 링·코치·다음 예약까지)
  /// 그렸다. 상태를 말하지 않는 칩이 곧 "이 회원권 이용 중"이라는 뜻으로 읽힌 것이다.
  /// 지금은 종료 상태도 반드시 괄호를 단다 — PassList의 `_statusLabel`과 같은 어휘
  /// ('만료'·'환불')를 쓰고, 모르는 wire 값은 지어내지 않고 원문 그대로 보여준다.
  String _statusSuffix(PassOption p) {
    if (p.isScheduled) return '${p.validFrom.month}/${p.validFrom.day}~';
    if (p.isActive) return '활성';
    return switch (p.status) {
      'expired' => '만료',
      'refunded' => '환불',
      _ => p.status,
    };
  }
}
