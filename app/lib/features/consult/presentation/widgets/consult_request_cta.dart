import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/features/consult/presentation/consult_providers.dart';
import 'package:rise_member/features/consult/presentation/widgets/consult_request_sheet.dart';

/// 재등록 요청 CTA(계약 v2.20, P42) — "센터에 문의해주세요"로 끝나던 데드엔드에 놓는 손잡이.
///
/// 세 상태를 스스로 판정한다(호출측은 놓기만 한다):
///   · pending 요청이 있으면 → "요청 보냈어요" 상태 문구(버튼 없음 — 서버 409를 눌러보고
///     아는 흐름을 만들지 않는다. 사전 판정 원칙, hold 시트와 동일).
///   · 없으면 → 요청 시트를 여는 버튼.
///   · 목록 조회 실패/로딩 → 버튼을 그대로 보여준다(fail-open — 중복은 서버 409가 최종
///     방어선이고, 조회 실패로 손잡이까지 숨기면 요청 경로가 통째로 사라진다).
class ConsultRequestCta extends ConsumerWidget {
  const ConsultRequestCta({super.key, this.compact = false});

  /// true면 배지 옆에 서는 소형 링크 스타일(홈 회원권 카드의 경고 줄), false면
  /// 빈 상태 뷰의 표준 버튼.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myConsultRequestsProvider);
    final pending = switch (async) {
      AsyncValue(:final value?) => value.any((r) => r.isPending),
      _ => false,
    };
    if (pending) {
      return Text(
        '재등록 요청을 보냈어요 — 센터에서 연락드릴 거예요',
        style: TextStyle(
          fontSize: compact ? 10.5 : 11.5,
          color: AppColors.ok,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
      );
    }
    if (compact) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showConsultRequestSheet(context),
        // 배지 줄에 서는 소형 링크 — 히트 영역은 패딩으로 44dp에 가깝게 벌린다
        // (독립 44dp 타깃을 그리면 배지 줄 높이가 배로 뛴다).
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Text(
            '재등록 요청하기 ›',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.red,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }
    return RiseButton(
      label: '재등록 요청하기',
      small: true,
      onPressed: () => showConsultRequestSheet(context),
    );
  }
}
