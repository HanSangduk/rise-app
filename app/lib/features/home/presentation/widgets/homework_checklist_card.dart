import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_typography.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/features/home/domain/home_models.dart';

/// 목업 "Home Work · 오늘" 카드 — 체크하면 코치에게 완료율이 보인다는 안내 포함.
class HomeworkChecklistCard extends StatelessWidget {
  const HomeworkChecklistCard({
    super.key,
    required this.items,
    required this.done,
    required this.total,
    required this.onToggle,
    this.checksFailed = false,
  });

  final List<HomeworkItem> items;
  final int done;
  final int total;
  final ValueChanged<HomeworkItem> onToggle;

  /// 오늘 체크 상태 조회 실패(HomeSummary.homeworkChecksFailed) — 체크박스가
  /// 전부 꺼져 보이는 건 "안 했다"가 아니라 "모른다"다.
  ///
  /// 토글을 잠그는 이유는 표시가 틀려서가 아니라 **쓰기 때문**이다: 저장은 형제
  /// 항목의 done 배열 전체를 보내고 서버가 문서를 통째로 교체하므로, 모르는 상태에서
  /// 한 칸을 누르면 서버에 남아 있는 다른 완료 기록이 지워진다.
  final bool checksFailed;

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseCardHeader(
            title: 'Home Work · 오늘',
            // 배정이 없으면 "오늘 0/0" 배지는 정보가 아니라 소음 — 숨긴다.
            // 상태를 모를 땐 "오늘 0/3"이 소음보다 나쁘다(거짓) — 함께 숨긴다.
            trailing: items.isEmpty || checksFailed
                ? null
                : RiseBadge('오늘 $done/$total', variant: RiseBadgeVariant.ok),
          ),
          // 실패는 실패라고 말한다(계약 카드·주간 기록과 같은 규약).
          if (checksFailed && items.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Text(
                '오늘 체크 상태를 불러오지 못했어요 — 아래로 당겨 새로고침해야 체크할 수 있어요',
                style: TextStyle(fontSize: 11, color: AppColors.danger, height: 1.4),
              ),
            ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                // 회원이 할 수 있는 일이 없다(배정은 코치 몫) — 행동을 지시하지 않고
                // **어떻게 채워지는지**만 말한다. 그래야 "앱이 고장 났나"가 아니라
                // "아직 안 왔구나"로 읽힌다.
                '오늘 배정된 Home Work가 없어요 — 코치가 배정하면 여기에 떠요',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
              ),
            )
          else
            for (final item in items)
              InkWell(
                onTap: checksFailed ? null : () => onToggle(item),
                child: Padding(
                  // 44dp 히트는 행 전체(InkWell)가 만든다 — 체크박스 자신의 탭
                  // 타깃이 아니라. 그래서 아래 shrinkWrap과 짝으로만 값이 맞는다.
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    children: [
                      // 기본 Checkbox는 padded 탭 타깃(48×48)을 차지해서, 이 카드만
                      // 라벨 들여쓰기가 48로 튀었다(다른 카드는 13~21). 시각 크기(18)는
                      // 그대로 두고 그 투명 여백만 걷어낸다.
                      Checkbox(
                        value: item.done,
                        activeColor: AppColors.brand,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        // null이면 비활성(회색) — 잠겼다는 걸 눌러보기 전에 보여준다.
                        onChanged: checksFailed ? null : (_) => onToggle(item),
                      ),
                      // 체크박스가 자기 여백을 잃었으므로 라벨 간격은 명시한다.
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.note == null ? item.name : '${item.name} — ${item.note}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      // 처방(세트·횟수)은 이름과 **같은 Text에 이어붙이지 않는다** —
                      // 이름·메모가 길면 Expanded의 말줄임이 뒤쪽부터 먹어서 정작
                      // 회원이 봐야 할 "3×40초"가 먼저 사라진다. 오른쪽 고정이라
                      // 길이와 무관하게 읽히고, 수업기록 카드(RiseRow trailing)와도
                      // 같은 자리·같은 강조다.
                      if (item.prescription case final p?) ...[
                        const SizedBox(width: 8),
                        // 폭 상한이 있는 이유: reps는 코치가 자유 입력하는 문자열이라
                        // ("각 15회 좌우 번갈아 …") 길이 상한이 계약에 없다. 상한 없이
                        // 두면 Expanded(이름)가 0까지 밀린 뒤 실기기 폭(360dp)에서
                        // Row가 넘쳐 카드 위에 오버플로 줄무늬가 그려진다(실측 71px).
                        // 120은 "3×각 15회"급 정상 표기가 잘리지 않는 선 — 그보다 긴
                        // 값만 말줄임으로 접힌다.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            p,
                            style: AppTypography.bodyStrong,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          // **배정이 있을 때만.** 종전엔 이 문구가 `if (items.isEmpty)` 바깥에 있어서
          // 빈 상태에서 "없어요" 바로 아래 "코치가 배정했어요"가 붙었다 — 한 카드
          // 안에서 두 문장이 서로를 부정했다(실기기 확인).
          //
          // 앞 절("코치가 배정했어요")은 항목을 보고 있는 회원에게 새 정보가 아니라
          // 함께 뺐다. 뒤 절은 남긴다 — 체크가 코치에게 보인다는 건 동기이기도 하고
          // **누가 내 기록을 보는가**라는 사실이기도 하다.
          if (items.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '체크하면 코치에게 완료율이 보여요',
                style: AppTypography.note,
              ),
            ),
        ],
      ),
    );
  }
}
